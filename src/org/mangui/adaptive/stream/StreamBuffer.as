/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.adaptive.stream {

    import flash.events.Event;
    import flash.events.TimerEvent;
    import flash.utils.Dictionary;
    import flash.utils.Timer;
    import org.mangui.adaptive.constant.SeekMode;
    import org.mangui.adaptive.constant.SeekStates;
    import org.mangui.adaptive.constant.Types;
    import org.mangui.adaptive.event.AdaptiveEvent;
    import org.mangui.adaptive.event.AdaptiveMediatime;
    import org.mangui.adaptive.flv.FLVTag;
    import org.mangui.hls.controller.AudioTrackController;
    import org.mangui.hls.controller.LevelController;
    import org.mangui.hls.HLS;
    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.loader.AltAudioFragmentLoader;
    import org.mangui.hls.loader.FragmentLoader;
    import org.mangui.hls.model.AudioTrack;

    CONFIG::LOGGING {
        import org.mangui.adaptive.utils.Log;
    }
    /*
     * intermediate FLV Tag Buffer
     *  input : FLV tags retrieved from different fragment loaders (video/alt-audio...)
     *  output : provide muxed FLV tags to AdaptiveNetStream
     */
    public class StreamBuffer {
        private var _hls : HLS;
        private var _fragmentLoader : FragmentLoader;
        private var _altaudiofragmentLoader : AltAudioFragmentLoader;
        /** Timer used to process FLV tags. **/
        private var _timer : Timer;
        private var _audioTags : Vector.<FLVData>,  _videoTags : Vector.<FLVData>,_metaTags : Vector.<FLVData>, _headerTags : Vector.<FLVData>;
        private var _audioIdx : uint,  _videoIdx : uint,  _metaIdx : uint, _headerIdx : uint;
        /** playlist duration **/
        private var _playlist_duration : Number = 0;
        private var _seeking_min_position : Number;
        /** requested start position **/
        private var _seek_position_requested : Number;
        /** real start position , retrieved from first fragment **/
        private var _seek_position_real : Number;
        /** start position of first injected tag **/
        private var _seek_pos_reached : Boolean;
        /** playlist sliding (non null for live playlist) **/
        private var _time_sliding : Number;
        /** buffer PTS (indexed by continuity counter)  */
        private var _buffer_pts : Dictionary;
        private static const MIN_NETSTREAM_BUFFER_SIZE : Number = 3.0;
        private static const MAX_NETSTREAM_BUFFER_SIZE : Number = 4.0;
        /** means that last fragment of a VOD playlist has been loaded */
        private var _reached_vod_end : Boolean;
        /* are we using alt-audio ? */
        private var _use_altaudio : Boolean;

        public function StreamBuffer(hls : HLS, audioTrackController : AudioTrackController, levelController : LevelController) {
            _hls = hls;
            _fragmentLoader = new FragmentLoader(hls, audioTrackController, levelController, this);
            _altaudiofragmentLoader = new AltAudioFragmentLoader(hls, this);
            flushAll();
            _timer = new Timer(100, 0);
            _timer.addEventListener(TimerEvent.TIMER, _checkBuffer);
            _hls.addEventListener(AdaptiveEvent.PLAYLIST_DURATION_UPDATED, _playlistDurationUpdated);
            _hls.addEventListener(AdaptiveEvent.LAST_VOD_FRAGMENT_LOADED, _lastVODFragmentLoadedHandler);
            _hls.addEventListener(AdaptiveEvent.AUDIO_TRACK_SWITCH, _audioTrackChange);
        }

        public function dispose() : void {
            flushAll();
            _hls.removeEventListener(AdaptiveEvent.PLAYLIST_DURATION_UPDATED, _playlistDurationUpdated);
            _hls.removeEventListener(AdaptiveEvent.LAST_VOD_FRAGMENT_LOADED, _lastVODFragmentLoadedHandler);
            _hls.removeEventListener(AdaptiveEvent.AUDIO_TRACK_SWITCH, _audioTrackChange);
            _timer.stop();
            _fragmentLoader.dispose();
            _altaudiofragmentLoader.dispose();
            _fragmentLoader = null;
            _altaudiofragmentLoader = null;
            _hls = null;
            _timer = null;
        }

        public function stop() : void {
            _fragmentLoader.stop();
            _altaudiofragmentLoader.stop();
            flushAll();
        }

        /*
         * if requested position is available in StreamBuffer, trim buffer
         * and inject from that point
         * if seek position out of buffer, ask fragment loader to retrieve data
         */
        public function seek(position : Number) : void {
            // compute _seek_position_requested based on position and playlist type
            if (_hls.type == Types.LIVE) {
                /* follow HLS spec :
                If the EXT-X-ENDLIST tag is not present
                and the client intends to play the media regularly (i.e. in playlist
                order at the nominal playback rate), the client SHOULD NOT
                choose a segment which starts less than three target durations from
                the end of the Playlist file */
                var maxLivePosition : Number = Math.max(0, _hls.levels[_hls.level].duration - 3 * _hls.levels[_hls.level].averageduration);
                if (position == -1) {
                    // seek 3 fragments from end
                    _seek_position_requested = maxLivePosition;
                } else {
                    _seek_position_requested = Math.min(position, maxLivePosition);
                }
            } else {
                _seek_position_requested = Math.max(position, 0);
            }
            CONFIG::LOGGING {
                Log.debug("seek : requested position:" + position.toFixed(2) + ",seek position:" + _seek_position_requested.toFixed(2) + ",min/max buffer position:" + min_pos.toFixed(2) + "/" + max_pos.toFixed(2));
            }
            // check if we can seek in buffer
            if (_seek_position_requested >= min_pos && _seek_position_requested <= max_pos) {
                _seek_pos_reached = false;
                _audioIdx = _videoIdx = _metaIdx = _headerIdx = 0;
            } else {
                // seek position is out of buffer : load from fragment
                _fragmentLoader.stop();
                _fragmentLoader.seek(_seek_position_requested);
                // check if we need to use alt audio fragment loader
                if (_hls.audioTracks.length && _hls.audioTracks[_hls.audioTrack].source == AudioTrack.FROM_PLAYLIST) {
                    CONFIG::LOGGING {
                        Log.info("seek : need to load alt audio track");
                    }
                    _altaudiofragmentLoader.stop();
                    _altaudiofragmentLoader.seek(_seek_position_requested);
                    _use_altaudio = true;
                } else {
                    _use_altaudio = false;
                }
                flushAll();
            }
            _timer.start();
        }

        public function appendTags(tags : Vector.<FLVTag>, min_pts : Number, max_pts : Number, continuity : int, start_position : Number) : void {
            for each (var tag : FLVTag in tags) {
//                CONFIG::LOGGING {
//                    Log.debug2('append type/dts/pts:' + tag.typeString + '/' + tag.dts + '/' + tag.pts);
//                }
                var pos : Number = start_position + (tag.pts - min_pts) / 1000;
                var tagData : FLVData = new FLVData(tag, pos, _time_sliding, continuity);
                switch(tag.type) {
                    case FLVTag.DISCONTINUITY:
                    case FLVTag.AAC_HEADER:
                    case FLVTag.AVC_HEADER:
                        _headerTags.push(tagData);
                        break;
                    case FLVTag.AAC_RAW:
                    case FLVTag.MP3_RAW:
                        _audioTags.push(tagData);
                        break;
                    case FLVTag.AVC_NALU:
                        _videoTags.push(tagData);
                        break;
                    case FLVTag.METADATA:
                        _metaTags.push(tagData);
                        break;
                    default:
                }
            }
            /* check live playlist sliding here :
            _seek_position_real + getTotalBufferedDuration()  should be the start_position
             * /of the new fragment if the playlist was not sliding
            => live playlist sliding is the difference between the new start position  and this previous value */
            if (_hls.seekState == SeekStates.SEEKED) {
                if ( _hls.type == Types.LIVE) {
                    _time_sliding = (_seeking_min_position + getTotalBufferedDuration()) - start_position;
                    // Log.info("min_pos/getTotalBufferedDuration/start pos/end pos/_time_sliding:" + "/" + _seeking_min_position.toFixed(2) + "/" + getTotalBufferedDuration().toFixed(2) + "/" + start_position.toFixed(2) + "/" + pos.toFixed(2) + "/" + _time_sliding.toFixed(2));
                }
            } else {
                _seeking_min_position = min_pos;
                /* if in seeking mode, force timer start here, this could help reducing the seek time by 100ms */
                _timer.start();
            }
            // update buffer min/max table indexed with continuity counter
            if (_buffer_pts[continuity] == undefined) {
                _buffer_pts[continuity] = new BufferPTS(min_pts, max_pts);
            } else {
                (_buffer_pts[continuity] as BufferPTS).max = max_pts;
            }
        }

        /** Return current media position **/
        public function get position() : Number {
            switch(_hls.seekState) {
                case SeekStates.SEEKING:
                    return  _seek_position_requested;
                case SeekStates.SEEKED:
                    /** Relative playback position = (Absolute Position(seek position + play time) - playlist sliding, non null for Live Playlist) **/
                    return _seek_position_real + _hls.stream.time - _time_sliding;
                case SeekStates.IDLE:
                default:
                    return 0;
            }
        };

        public function get reachedEnd() : Boolean {
            return _reached_vod_end;
        }

        private function flushAll() : void {
            _audioTags = new Vector.<FLVData>();
            _videoTags = new Vector.<FLVData>();
            _metaTags = new Vector.<FLVData>();
            _headerTags = new Vector.<FLVData>();
            _audioIdx = _videoIdx = _metaIdx = _headerIdx = 0;
            _buffer_pts = new Dictionary();
            _seek_pos_reached = false;
            _reached_vod_end = false;
            _time_sliding = 0;
        }

        private function flushAudio() : void {
            // flush audio buffer and AAC HEADER tags (if any)
            _audioTags = new Vector.<FLVData>();
            _audioIdx = 0;
            var _filteredHeaderTags : Vector.<FLVData> = _headerTags.filter(filterAACHeader);
            _headerIdx -= (_headerTags.length - _filteredHeaderTags.length);
        }

        private function filterAACHeader(item : FLVData, index : int, vector : Vector.<FLVData>) : Boolean {
            return (item.tag.type != FLVTag.AAC_HEADER);
        }

        /* compare two tags, smallest continuity
         * then smallest pts. then discontinuity then aac/avc header then metadata, then others
         *
        return a negative number, if x should appear before y in the sorted sequence
        retun 0, if x equals y
        return a positive number, if x should appear after y in the sorted sequence*
         *
         * */
        private function compareTags(x : FLVData, y : FLVData) : Number {
            if (x.continuity != y.continuity) {
                return (x.continuity - y.continuity);
            } else {
                if (x.tag.dts != y.tag.dts) {
                    return (x.tag.dts - y.tag.dts);
                } else {
                    return (gettagrank(x.tag) - gettagrank(y.tag));
                }
            }
        }

        private function gettagrank(tag : FLVTag) : uint {
            switch(tag.type) {
                case FLVTag.DISCONTINUITY:
                    return 0;
                case FLVTag.METADATA:
                    return 1;
                case FLVTag.AVC_HEADER:
                case FLVTag.AAC_HEADER:
                    return 2;
                default:
                    return 3;
            }
        }

        /*
        private function flushAudio() : void {
        _audioTags = new Vector.<FLVData>();
        }
         */
        private function get audio_expected() : Boolean {
            return (_fragmentLoader.audio_expected || _use_altaudio);
        }

        private function get video_expected() : Boolean {
            return _fragmentLoader.video_expected;
        }

        public function get audioBufferLength() : Number {
            return getbuflen(_audioTags, _audioIdx);
        }

        public function get videoBufferLength() : Number {
            return getbuflen(_videoTags, _videoIdx);
        }

        public function get bufferLength() : Number {
            switch(_hls.seekState) {
                case SeekStates.SEEKING:
                    return  Math.max(0, max_pos - _seek_position_requested);
                case SeekStates.SEEKED:
                    if (audio_expected) {
                        if (video_expected) {
                            return Math.min(audioBufferLength, videoBufferLength);
                        } else {
                            return audioBufferLength;
                        }
                    } else {
                        return videoBufferLength;
                    }
                case SeekStates.IDLE:
                default:
                    return 0;
            }
        }

        public function get backBufferLength() : Number {
            if (min_pos != Number.POSITIVE_INFINITY) {
                return (position - min_pos);
            } else {
                return 0;
            }
        }

        /**  StreamBuffer Timer, responsible of
         * reporting media time event
         *  injecting tags into NetStream
         *  clipping backbuffer
         */
        private function _checkBuffer(e : Event) : void {
            // dispatch media time event
            _hls.dispatchEvent(new AdaptiveEvent(AdaptiveEvent.MEDIA_TIME, new AdaptiveMediatime(position, _playlist_duration, _hls.stream.bufferLength, backBufferLength, _time_sliding)));

            /* only append tags if seek position has been reached, otherwise wait for more tags to come
             * this is to ensure that accurate seeking will work appropriately
             */
            CONFIG::LOGGING {
                Log.debug2("position/audio/video bufferLength:" + position.toFixed(2) + "/" + audioBufferLength.toFixed(2) + "/" + videoBufferLength.toFixed(2));
            }

            var duration : Number = 0;
            if (_seek_pos_reached) {
                var netStreamBuffer : Number = (_hls.stream as AdaptiveNetStream).netStreamBufferLength;
                if (netStreamBuffer < MIN_NETSTREAM_BUFFER_SIZE) {
                    duration = MAX_NETSTREAM_BUFFER_SIZE - netStreamBuffer;
                }
            } else {
                /* seek position not reached yet.
                 * check if buffer max position is greater than requested seek position
                 * if it is the case, then we can start injecting tags in NetStream
                 */

//                CONFIG::LOGGING {
//                    Log.info("min_audio/max_audio/min_video/max_video:" + min_audio_pos.toFixed(2) + "/" + max_audio_pos.toFixed(2) + "/" + min_video_pos.toFixed(2) + "/" + max_video_pos.toFixed(2));
//                }

                if (max_pos >= _seek_position_requested) {
                    // inject enough tags to reach seek position
                    duration = _seek_position_requested + MAX_NETSTREAM_BUFFER_SIZE - min_min_pos;
                    /* force header tag sorting here : it is mandatory  for seek filtering logic
                    in case of alt audio tracks, audio/video headers might be not be sorted correctly */
                    _headerTags = _headerTags.sort(compareTags);
                }
            }
            if (duration > 0) {
                var data : Vector.<FLVData> = shiftmultipletags(duration);
                if (!_seek_pos_reached) {
                    data = seekFilterTags(data, _seek_position_requested);
                    _seek_pos_reached = true;
                }

                var tags : Vector.<FLVTag> = new Vector.<FLVTag>();
                for each (var flvdata : FLVData in data) {
                    tags.push(flvdata.tag);
                }
                if (tags.length) {
                    CONFIG::LOGGING {
                        var t0 : Number = data[0].position - (_time_sliding - data[0].sliding );
                        var t1 : Number = data[data.length - 1].position - (_time_sliding - data[data.length - 1].sliding );
                        Log.debug2("appending " + tags.length + " tags, start/end :" + t0.toFixed(2) + "/" + t1.toFixed(2));
                    }
                    (_hls.stream as AdaptiveNetStream).appendTags(tags);
                }
            }
            // clip backbuffer if needed
            if (HLSSettings.maxBackBufferLength > 0) {
                _clipBackBuffer(HLSSettings.maxBackBufferLength);
            }
        }

        /* filter/tweak tags to seek accurately into the stream */
        private function seekFilterTags(tags : Vector.<FLVData>, start_position : Number) : Vector.<FLVData> {
            var aacIdx : int,avcIdx : int,disIdx : int,keyIdx : int,lastIdx : int;
            aacIdx = avcIdx = disIdx = keyIdx = lastIdx = -1;
            var filteredTags : Vector.<FLVData>=  new Vector.<FLVData>();

            // loop through all tags and find index position of header tags located before start position
            for (var i : int = 0; i < tags.length; i++) {
                var data : FLVData = tags[i];
                if (data.position - (_time_sliding - data.sliding) <= start_position) {
                    lastIdx = i;
                    // current tag is before requested start position
                    // grab AVC/AAC/DISCONTINUITY/KEYFRAMES tag located just before
                    switch(data.tag.type) {
                        case FLVTag.DISCONTINUITY:
                            disIdx = i;
                            break;
                        case FLVTag.AAC_HEADER:
                            aacIdx = i;
                            break;
                        case FLVTag.AVC_HEADER:
                            avcIdx = i;
                            break;
                        case FLVTag.AVC_NALU:
                            if (data.tag.keyframe) keyIdx = i;
                        default:
                            break;
                    }
                } else {
                    break;
                }
            }

            if (keyIdx == -1) {
                // audio only stream, no keyframe. we can seek accurately
                keyIdx = lastIdx;
            }

            var first_pts : Number;
            if (HLSSettings.seekMode == SeekMode.ACCURATE_SEEK) {
                // start injecting from last tag before start position
                first_pts = tags[lastIdx].tag.pts;
                _seek_position_real = tags[lastIdx].position;
            } else {
                // start injecting from keyframe tag
                first_pts = tags[keyIdx].tag.pts;
                _seek_position_real = tags[keyIdx].position;
            }

            // inject discontinuity/AVC header/AAC header if available
            if (disIdx != -1) {
                var tagclone : FLVTag = tags[disIdx].tag.clone();
                tagclone.pts = tagclone.dts = first_pts;
                var dataclone : FLVData = new FLVData(tagclone, _seek_position_real, 0, tags[disIdx].continuity);
                filteredTags.push(dataclone);
            }
            if (aacIdx != -1) {
                tagclone = tags[aacIdx].tag.clone();
                tagclone.pts = tagclone.dts = first_pts;
                dataclone = new FLVData(tagclone, _seek_position_real, 0, tags[aacIdx].continuity);
                filteredTags.push(dataclone);
            }
            if (avcIdx != -1) {
                tagclone = tags[avcIdx].tag.clone();
                tagclone.pts = tagclone.dts = first_pts;
                dataclone = new FLVData(tagclone, _seek_position_real, 0, tags[avcIdx].continuity);
                filteredTags.push(dataclone);
            }
            // inject tags from nearest keyframe to start position
            for (i = keyIdx; i < lastIdx; i++) {
                data = tags[i];
                // if accurate seek mode, adjust tags with pts and position from start position
                if (HLSSettings.seekMode == SeekMode.ACCURATE_SEEK) {
                    // only push NALU to be able to reconstruct frame at seek position
                    if (data.tag.type == FLVTag.AVC_NALU) {
                        tagclone = data.tag.clone();
                        tagclone.pts = tagclone.dts = first_pts;
                        dataclone = new FLVData(tagclone, _seek_position_real, 0, tags[i].continuity);
                        filteredTags.push(dataclone);
                    }
                } else {
                    // keyframe seeking : push straight away
                    filteredTags.push(data);
                }
            }
            // tags located after start position, push straight away
            for (i = lastIdx; i < tags.length; i++) {
                data = tags[i];
                filteredTags.push(data);
            }
            return filteredTags;
        }

        private function _clipBackBuffer(maxBackBufferLength : Number) : void {
            /*      min_pos        		                   current
             *                                    		   position
             *        *------------------*---------------------*----
             *         ****************** <-------------------->
             *           to be clipped     maxBackBufferLength
             */

            // determine clipping position
            var clipping_position : Number = position - maxBackBufferLength;
            var clipped_tags : uint = 0;

            // loop through each tag list and clip tags if out of max back buffer boundary
            while (_audioTags.length && (_audioTags[0].position - (_time_sliding - _audioTags[0].sliding )) < clipping_position) {
                _audioTags.shift();
                _audioIdx--;
                clipped_tags++;
            }

            while (_videoTags.length && (_videoTags[0].position - (_time_sliding - _videoTags[0].sliding )) < clipping_position) {
                _videoTags.shift();
                _videoIdx--;
                clipped_tags++;
            }

            while (_metaTags.length && (_metaTags[0].position - (_time_sliding - _metaTags[0].sliding )) < clipping_position) {
                _metaTags.shift();
                _metaIdx--;
                clipped_tags++;
            }

            /* clip header tags : the tricky thing here is that we need to keep the last AAC HEADER / AVC HEADER before clip position
             * if we dont keep these tags, we will have audio/video playback issues when seeking into the buffer
             *
             * so we loop through all header tags and we retrieve the position of last AAC/AVC header tags
             * then if any subsequent header tag is found after seek position, we create a new Vector in which we first append the previously
             * found AAC/AVC header
             *
             */
            var _aacHeader : FLVData;
            var _avcHeader : FLVData;
            var _disHeader : FLVData;
            var headercounter : uint = 0;
            var _newheaderTags : Vector.<FLVData> = new Vector.<FLVData>();
            for each (var data : FLVData in _headerTags) {
                if ((data.position - (_time_sliding - data.sliding)) < clipping_position) {
                    switch(data.tag.type) {
                        case FLVTag.DISCONTINUITY:
                            _disHeader = data;
                            headercounter++;
                            break;
                        case FLVTag.AAC_HEADER:
                            _aacHeader = data;
                            headercounter++;
                            break;
                        case FLVTag.AVC_HEADER:
                            _avcHeader = data;
                            headercounter++;
                        default:
                            break;
                    }
                } else {
                    /* tag located after clip position : we need to keep it
                     * first try to push DISCONTINUITY/AVC HEADER/AAC HEADER tag located
                     * before the clip position
                     */
                    if (_disHeader) {
                        headercounter--;
                        // Log.info("push DISCONTINUITY header tags/position:" + _disHeader.position);
                        _disHeader.position = clipping_position;
                        _disHeader.sliding = 0;
                        _newheaderTags.push(_disHeader);
                        _disHeader = null;
                    }
                    if (_aacHeader) {
                        headercounter--;
                        // Log.info("push AAC header tags/position:" + _aacHeader.position);
                        _aacHeader.position = clipping_position;
                        _aacHeader.sliding = 0;
                        _newheaderTags.push(_aacHeader);
                        _aacHeader = null;
                    }
                    if (_avcHeader) {
                        headercounter--;
                        // Log.info("push AVC header tags/position:" + _avcHeader.position);
                        _avcHeader.position = clipping_position;
                        _avcHeader.sliding = 0;
                        _newheaderTags.push(_avcHeader);
                        _avcHeader = null;
                    }
                    // Log.info("push tag type/position:" + data.tag.type + "/" + data.position);
                    _newheaderTags.push(data);
                }
            }

            if (headercounter != 0) {
                // Log.info("clipped " + headercounter + " header tags");
                _headerTags = _newheaderTags;
                // we need to adjust headerIdx, as the size of the Vector has been adjusted
                _headerIdx -= headercounter;
                clipped_tags += headercounter;
            }

            CONFIG::LOGGING {
                if (clipped_tags > 0) {
                    Log.debug2("clipped " + clipped_tags + " tags, clipping position :" + clipping_position);
                }
            }
        }

        private function _playlistDurationUpdated(event : AdaptiveEvent) : void {
            _playlist_duration = event.duration;
        }

        private function getbuflen(tags : Vector.<FLVData>, startIdx : uint) : Number {
            if (tags.length > startIdx) {
                var start_pos : Number = tags[startIdx].position + tags[startIdx].sliding;
                var end_pos : Number = tags[tags.length - 1].position + tags[tags.length - 1].sliding;
                return (end_pos - start_pos);
            } else {
                return 0;
            }
        }

        /** return total buffered duration since seek() call, needed to compute live playlist sliding  */
        private function getTotalBufferedDuration() : Number {
            var len : Number = 0;
            for each (var entry : BufferPTS in _buffer_pts) {
                len += (entry.max - entry.min);
            }
            return len / 1000;
        }

        /*
         * retrieve queue containing next tag to be injected, using the following priority :
         * smallest continuity
         * then smallest dts
         * then header  then video then audio then metadata tags
         */
        private function getnexttag() : FLVData {
            var mtag : FLVData ,vtag : FLVData,atag : FLVData, htag : FLVData;

            var continuity : int = int.MAX_VALUE;
            // find smallest continuity counter
            if (_headerTags.length > _headerIdx) {
                htag = _headerTags[_headerIdx];
                continuity = Math.min(continuity, htag.continuity);
            }
            if (_videoTags.length > _videoIdx) {
                vtag = _videoTags[_videoIdx];
                continuity = Math.min(continuity, vtag.continuity);
            }
            if (_audioTags.length > _audioIdx) {
                atag = _audioTags[_audioIdx];
                continuity = Math.min(continuity, atag.continuity);
            }
            if (_metaTags.length > _metaIdx) {
                mtag = _metaTags[_metaIdx];
                continuity = Math.min(continuity, mtag.continuity);
            }
            if (continuity == int.MAX_VALUE)
                return null;

            var dts : Number = Number.MAX_VALUE;
            // for this continuity counter, find smallest DTS

            if (htag && htag.continuity == continuity) dts = Math.min(dts, htag.tag.dts);
            if (vtag && vtag.continuity == continuity) dts = Math.min(dts, vtag.tag.dts);
            if (atag && atag.continuity == continuity) dts = Math.min(dts, atag.tag.dts);
            if (mtag && mtag.continuity == continuity) dts = Math.min(dts, mtag.tag.dts);

            // for this continuity counter, this DTS, prioritize tags with the following order : header/metadata/video/audio
            if (htag && htag.continuity == continuity && htag.tag.dts == dts) {
                _headerIdx++;
                return htag;
            }
            if (mtag && mtag.continuity == continuity && mtag.tag.dts == dts) {
                _metaIdx++;
                return mtag;
            }
            if (vtag && vtag.continuity == continuity && vtag.tag.dts == dts) {
                _videoIdx++;
                return vtag;
            } else {
                _audioIdx++;
                return atag;
            }
        }

        private function shiftmultipletags(max_duration : Number) : Vector.<FLVData> {
            var tags : Vector.<FLVData>=  new Vector.<FLVData>();
            var tag : FLVData = getnexttag();
            if (tag) {
                var min_offset : Number = tag.position + tag.sliding;
                do {
                    tags.push(tag);
                    var tag_offset : Number = tag.position + tag.sliding;
                    if (tag_offset - min_offset > max_duration) {
                        break;
                    }
                } while ((tag = getnexttag()) != null);
            }
            return tags;
        }

        private function get min_pos() : Number {
            if (audio_expected) {
                if (video_expected) {
                    return Math.max(min_audio_pos, min_video_pos);
                } else {
                    return min_audio_pos;
                }
            } else {
                return min_video_pos;
            }
        }

        private function get min_min_pos() : Number {
            if (audio_expected) {
                if (video_expected) {
                    return Math.min(min_audio_pos, min_video_pos);
                } else {
                    return min_audio_pos;
                }
            } else {
                return min_video_pos;
            }
        }

        private function get min_audio_pos() : Number {
            var min_pos_ : Number = Number.POSITIVE_INFINITY;
            if (_audioTags.length) min_pos_ = Math.min(min_pos_, _audioTags[0].position - (_time_sliding - _audioTags[0].sliding ));
            return min_pos_;
        }

        private function get min_video_pos() : Number {
            var min_pos_ : Number = Number.POSITIVE_INFINITY;
            if (_videoTags.length) min_pos_ = Math.min(min_pos_, _videoTags[0].position - (_time_sliding - _videoTags[0].sliding ));
            return min_pos_;
        }

        private function get max_pos() : Number {
            if (audio_expected) {
                if (video_expected) {
                    return Math.min(max_audio_pos, max_video_pos);
                } else {
                    return max_audio_pos;
                }
            } else {
                return max_video_pos;
            }
        }

        private function get max_audio_pos() : Number {
            var max_pos_ : Number = Number.NEGATIVE_INFINITY;
            if (_audioTags.length) max_pos_ = Math.max(max_pos_, _audioTags[_audioTags.length - 1].position - (_time_sliding - _audioTags[_audioTags.length - 1].sliding ));
            return max_pos_;
        }

        private function get max_video_pos() : Number {
            var max_pos_ : Number = Number.NEGATIVE_INFINITY;
            if (_videoTags.length) max_pos_ = Math.max(max_pos_, _videoTags[_videoTags.length - 1].position - (_time_sliding - _videoTags[_videoTags.length - 1].sliding ));
            return max_pos_;
        }

        private function _lastVODFragmentLoadedHandler(event : AdaptiveEvent) : void {
            CONFIG::LOGGING {
                Log.debug("last fragment loaded");
            }
            _reached_vod_end = true;
        }

        private function _audioTrackChange(event : AdaptiveEvent) : void {
            CONFIG::LOGGING {
                Log.debug("StreamBuffer : audio track changed, flushing audio buffer:" + event.audioTrack);
            }
            flushAudio();
        }
    }
}

import org.mangui.adaptive.flv.FLVTag;


class FLVData {
    public var tag : FLVTag;
    public var position : Number;
    public var sliding : Number;
    public var continuity : int;

    public function FLVData(tag : FLVTag, position : Number, sliding : Number, continuity : int) {
        this.tag = tag;
        this.position = position;
        this.sliding = sliding;
        this.continuity = continuity;
    }
}

class BufferPTS {
    public var min : Number;
    public var max : Number;

    public function BufferPTS(min : Number, max : Number) {
        this.min = min;
        this.max = max;
    }
}
