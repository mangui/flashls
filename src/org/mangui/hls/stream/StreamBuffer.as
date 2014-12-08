/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.stream {
    import flash.events.TimerEvent;
    import flash.events.Event;
    import flash.utils.Timer;
    import flash.utils.Dictionary;

    import org.mangui.hls.event.HLSMediatime;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.constant.HLSSeekStates;
    import org.mangui.hls.constant.HLSSeekMode;
    import org.mangui.hls.constant.HLSTypes;
    import org.mangui.hls.flv.FLVTag;
    import org.mangui.hls.HLS;
    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.loader.FragmentLoader;
    import org.mangui.hls.controller.AudioTrackController;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
    /*
     * intermediate FLV Tag Buffer
     *  input : FLV tags retrieved from different fragment loaders (video/alt-audio...)
     *  output : provide muxed FLV tags to HLSNetStream
     */
    public class StreamBuffer {
        private var _hls : HLS;
        private var _fragmentLoader : FragmentLoader;
        /** Timer used to process FLV tags. **/
        private var _timer : Timer;
        private var _audioTags : Vector.<FLVData>;
        private var _videoTags : Vector.<FLVData>;
        private var _metaTags : Vector.<FLVData>;
        private var _audioIdx : uint;
        private var _videoIdx : uint;
        private var _metaIdx : uint;
        private var _aacHeader : FLVData;
        private var _avcHeader : FLVData;
        /** playlist duration **/
        private var _playlist_duration : Number = 0;
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
        private static const MIN_NETSTREAM_BUFFER_SIZE : Number = 1.0;
        private static const MAX_NETSTREAM_BUFFER_SIZE : Number = 3.0;

        public function StreamBuffer(hls : HLS, audioTrackController : AudioTrackController) {
            _hls = hls;
            _fragmentLoader = new FragmentLoader(hls, audioTrackController, this);
            flushAll();
            _timer = new Timer(100, 0);
            _timer.addEventListener(TimerEvent.TIMER, _checkBuffer);
            _hls.addEventListener(HLSEvent.PLAYLIST_DURATION_UPDATED, _playlistDurationUpdated);
        }

        public function dispose() : void {
            flushAll();
            _hls.removeEventListener(HLSEvent.PLAYLIST_DURATION_UPDATED, _playlistDurationUpdated);
            _timer.stop();
            _fragmentLoader.dispose();
            _fragmentLoader = null;
            _hls = null;
            _timer = null;
        }

        public function stop() : void {
            _fragmentLoader.stop();
            flushAll();
        }

        /* 
         * if requested position is available in StreamBuffer, trim buffer 
         * and inject from that point
         * if seek position out of buffer, ask fragment loader to retrieve data 
         */
        public function seek(position : Number) : void {
            // compute _seek_position_requested based on position and playlist type
            if (_hls.type == HLSTypes.LIVE) {
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
                _audioIdx = _videoIdx = _metaIdx = 0;
            } else {
                // seek position is out of buffer : load from fragment
                _fragmentLoader.stop();
                _fragmentLoader.seek(position);
                flushAll();
            }
            _timer.start();
        }

        public function appendTags(tags : Vector.<FLVTag>, min_pts : Number, max_pts : Number, continuity : int, start_position : Number) : void {
            for each (var tag : FLVTag in tags) {
                var position : Number = start_position + (tag.pts - min_pts) / 1000;
                var tagData : FLVData = new FLVData(tag, position, _time_sliding, continuity);
                switch(tag.type) {
                    case FLVTag.AAC_HEADER:
                        _aacHeader = tagData;
                    case FLVTag.AAC_RAW:
                    case FLVTag.MP3_RAW:
                        _audioTags.push(tagData);
                        break;
                    case FLVTag.AVC_HEADER:
                        _avcHeader = tagData;
                    case FLVTag.AVC_NALU:
                        _videoTags.push(tagData);
                        break;
                    case FLVTag.DISCONTINUITY:
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
            if (_hls.seekState == HLSSeekStates.SEEKED) {
                if ( _hls.type == HLSTypes.LIVE) {
                    // Log.info("_time_sliding/_first_start_position/getTotalBufferedDuration/start pos:" + _time_sliding + "/" + _first_start_position + "/" + getTotalBufferedDuration() + "/" + start_position);
                    _time_sliding = (min_pos + getTotalBufferedDuration()) - start_position;
                }
            } else {
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
                case HLSSeekStates.SEEKING:
                    return  _seek_position_requested;
                case HLSSeekStates.SEEKED:
                    /** Relative playback position = (Absolute Position(seek position + play time) - playlist sliding, non null for Live Playlist) **/
                    return _seek_position_real + _hls.stream.time - _time_sliding;
                case HLSSeekStates.IDLE:
                default:
                    return 0;
            }
        };

        private function flushAll() : void {
            _audioTags = new Vector.<FLVData>();
            _videoTags = new Vector.<FLVData>();
            _metaTags = new Vector.<FLVData>();
            _audioIdx = _videoIdx = _metaIdx = 0;
            _buffer_pts = new Dictionary();
            _seek_pos_reached = false;
            _time_sliding = 0;
        }

        /*
        private function flushAudio() : void {
        _audioTags = new Vector.<FLVData>();
        }
         */
        private function get audioBufferLength() : Number {
            return getbuflen(_audioTags, _audioIdx);
        }

        private function get videoBufferLength() : Number {
            return getbuflen(_videoTags, _videoIdx);
        }

        public function get bufferLength() : Number {
            switch(_hls.seekState) {
                case HLSSeekStates.SEEKING:
                    return  Math.max(0, max_pos - _seek_position_requested);
                case HLSSeekStates.SEEKED:
                    return Math.max(audioBufferLength, videoBufferLength);
                case HLSSeekStates.IDLE:
                default:
                    return 0;
            }
        }

        /**  Timer **/
        private function _checkBuffer(e : Event) : void {
            // dispatch media time event
            _hls.dispatchEvent(new HLSEvent(HLSEvent.MEDIA_TIME, new HLSMediatime(position, _playlist_duration, _hls.stream.bufferLength, _time_sliding)));

            /* only append tags if seek position has been reached, otherwise wait for more tags to come
             * this is to ensure that accurate seeking will work appropriately
             */

            var duration : Number = 0;
            if (_seek_pos_reached) {
                var netStreamBuffer : Number = (_hls.stream as HLSNetStream).netStreamBufferLength;
                if (netStreamBuffer < MIN_NETSTREAM_BUFFER_SIZE) {
                    duration = MAX_NETSTREAM_BUFFER_SIZE - netStreamBuffer;
                }
            } else {
                /* seek position not reached yet. 
                 * check if buffer max position is greater than requested seek position
                 * if it is the case, then we can start injecting tags in NetStream
                 */
                if (max_pos >= _seek_position_requested) {
                    // inject enough tags to reach seek position
                    duration = _seek_position_requested + MAX_NETSTREAM_BUFFER_SIZE - min_pos;
                }
            }
            if (duration > 0) {
                var data : Vector.<FLVData> = shiftmultipletags(duration);
                if (!_seek_pos_reached) {
                    data = seekFilterTags(data);
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
                    (_hls.stream as HLSNetStream).appendTags(tags);
                }
            }
        }

        /* filter/tweak tags to seek accurately into the stream */
        private function seekFilterTags(tags : Vector.<FLVData>) : Vector.<FLVData> {
            var aacHeaderfound : Boolean = false;
            var avcHeaderfound : Boolean = false;
            var filteredTags : Vector.<FLVData>=  new Vector.<FLVData>();
            /* PTS of first tag that will be pushed into FLV tag buffer */
            var first_pts : Number;
            /* PTS of last video keyframe before requested seek position */
            var keyframe_pts : Number;
            /* */
            var min_offset : Number = tags[0].position - (_time_sliding - tags[0].sliding );
            var min_pts : Number = tags[0].tag.pts;
            /* 
             * 
             *    real seek       requested seek                 Frag 
             *     position           position                    End
             *        *------------------*-------------------------
             *        <------------------>
             *             seek_offset
             *
             * real seek position is the start offset of the first received fragment after seek command. (= fragment start offset).
             * seek offset is the diff between the requested seek position and the real seek position
             */

            /* if requested seek position is out of this segment bounds
             * all the segments will be pushed, first pts should be thus be min_pts
             */
            if (_seek_position_requested < min_offset) {
                _seek_position_real = min_offset;
                first_pts = min_pts;
            } else {
                /* if requested position is within segment bounds, determine real seek position depending on seek mode setting */
                if (HLSSettings.seekMode == HLSSeekMode.SEGMENT_SEEK) {
                    _seek_position_real = min_offset;
                    first_pts = min_pts;
                } else {
                    /* accurate or keyframe seeking */
                    /* seek_pts is the requested PTS seek position */
                    var seek_pts : Number = min_pts + 1000 * (_seek_position_requested - min_offset);
                    /* analyze fragment tags and look for PTS of last keyframe before seek position.*/
                    keyframe_pts = min_pts;
                    for each (var flvData : FLVData in tags) {
                        var tag : FLVTag = flvData.tag;
                        // look for last keyframe with pts <= seek_pts
                        if (tag.keyframe == true && tag.pts <= seek_pts && (tag.type == FLVTag.AVC_HEADER || tag.type == FLVTag.AVC_NALU)) {
                            keyframe_pts = tag.pts;
                        }
                    }
                    if (HLSSettings.seekMode == HLSSeekMode.KEYFRAME_SEEK) {
                        _seek_position_real = min_offset + (keyframe_pts - min_pts) / 1000;
                        first_pts = keyframe_pts;
                    } else {
                        // accurate seek, to exact requested position
                        _seek_position_real = _seek_position_requested;
                        first_pts = seek_pts;
                    }
                }
            }
            /* if in segment seeking mode : push all FLV tags */
            if (HLSSettings.seekMode == HLSSeekMode.SEGMENT_SEEK) {
                filteredTags = tags;
            } else {
                /* keyframe / accurate seeking, we need to filter out some FLV tags */
                for each (flvData in tags) {
                    tag = flvData.tag;
                    if (tag.type == FLVTag.AAC_HEADER) {
                        aacHeaderfound = true;
                    } else if (tag.type == FLVTag.AVC_HEADER) {
                        avcHeaderfound = true;
                    }
                    if (tag.pts >= first_pts) {
                        filteredTags.push(flvData);
                    } else {
                        switch(tag.type) {
                            case FLVTag.AAC_HEADER:
                            case FLVTag.AVC_HEADER:
                            case FLVTag.DISCONTINUITY:
                                // as we need to adjust tag PTS, we need to clone the tag to keep the original tag untouched (this tag is kept in the main buffer
                                var tagclone : FLVTag = tag.clone();
                                tagclone.pts = tagclone.dts = first_pts;
                                var dataclone : FLVData = new FLVData(tagclone, flvData.position, flvData.sliding, flvData.continuity);
                                filteredTags.push(dataclone);
                                break;
                            case FLVTag.AVC_NALU:
                            case FLVTag.METADATA:
                                /* only append video and metadata tags starting from last keyframe before seek position to avoid playback artifacts
                                 *  rationale of this is that there can be multiple keyframes per segment. if we append all keyframes
                                 *  in NetStream, all of them will be displayed in a row and this will introduce some playback artifacts
                                 *  */
                                if (tag.pts >= keyframe_pts) {
                                    // as we need to adjust tag PTS, we need to clone the tag to keep the original tag untouched (this tag is kept in the main buffer
                                    tagclone = tag.clone();
                                    tagclone.pts = tagclone.dts = first_pts;
                                    dataclone = new FLVData(tagclone, flvData.position, flvData.sliding, flvData.continuity);
                                    filteredTags.push(dataclone);
                                }
                                break;
                            default:
                                break;
                        }
                    }
                }
            }
            /*
            if (aacHeaderfound == false && _aacHeader != null) {
            _aacHeader.tag.pts = first_pts;
            filteredTags.unshift(_aacHeader);
            }
            if (avcHeaderfound == false && _avcHeader != null) {
            _avcHeader.tag.pts = first_pts;
            filteredTags.unshift(_avcHeader);
            }
             */
            return filteredTags;
        }

        private function _playlistDurationUpdated(event : HLSEvent) : void {
            _playlist_duration = event.duration;
        }

        private function getbuflen(tags : Vector.<FLVData>, startIdx : uint) : Number {
            var min_pts : Number = 0;
            var max_pts : Number = 0;
            var continuity : int = -1;
            var len : Number = 0;

            for (var i : uint = startIdx; i < tags.length; i++) {
                var data : FLVData = tags[i];
                if (data.continuity != continuity) {
                    len += (max_pts - min_pts);
                    min_pts = data.tag.pts;
                    continuity = data.continuity;
                } else {
                    max_pts = data.tag.pts;
                }
            }
            len += (max_pts - min_pts);
            return len / 1000;
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
         * then smallest pts
         * then metadata then video then audio tags
         */
        private function getnexttag() : FLVData {
            if (_videoTags.length == 0 && _audioTags.length == 0 && _metaTags.length == 0)
                return null;

            var continuity : int = int.MAX_VALUE;
            // find smallest continuity counter
            if (_metaTags.length > _metaIdx) continuity = Math.min(continuity, _metaTags[_metaIdx].continuity);
            if (_videoTags.length > _videoIdx) continuity = Math.min(continuity, _videoTags[_videoIdx].continuity);
            if (_audioTags.length > _audioIdx) continuity = Math.min(continuity, _audioTags[_audioIdx].continuity);

            var pts : Number = Number.MAX_VALUE;
            // for this continuity counter, find smallest PTS
            if ((_metaTags.length > _metaIdx) && _metaTags[_metaIdx].continuity == continuity) pts = Math.min(pts, _metaTags[_metaIdx].tag.pts);
            if ((_videoTags.length > _videoIdx) && _videoTags[_videoIdx].continuity == continuity) pts = Math.min(pts, _videoTags[_videoIdx].tag.pts);
            if ((_audioTags.length > _audioIdx) && _audioTags[_audioIdx].continuity == continuity) pts = Math.min(pts, _audioTags[_audioIdx].tag.pts);

            // for this continuity counter, this PTS, prioritize tags with the following order : metadata/video/audio
            if ((_metaTags.length > _metaIdx) && _metaTags[_metaIdx].continuity == continuity && _metaTags[_metaIdx].tag.pts == pts) return _metaTags[_metaIdx++];
            if ((_videoTags.length > _videoIdx) && _videoTags[_videoIdx].continuity == continuity && _videoTags[_videoIdx].tag.pts == pts) return _videoTags[_videoIdx++];
            else return _audioTags[_audioIdx++];
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
            var min_pos_ : Number = Number.POSITIVE_INFINITY;
            if (_metaTags.length) min_pos_ = Math.min(min_pos_, _metaTags[0].position - (_time_sliding - _metaTags[0].sliding ));
            if (_videoTags.length) min_pos_ = Math.min(min_pos_, _videoTags[0].position - (_time_sliding - _videoTags[0].sliding ));
            if (_audioTags.length) min_pos_ = Math.min(min_pos_, _audioTags[0].position - (_time_sliding - _audioTags[0].sliding ));
            return min_pos_;
        }

        private function get max_pos() : Number {
            var max_pos_ : Number = Number.NEGATIVE_INFINITY;
            if (_metaTags.length) max_pos_ = Math.max(max_pos_, _metaTags[_metaTags.length - 1].position - (_time_sliding - _metaTags[_metaIdx].sliding ));
            if (_videoTags.length) max_pos_ = Math.max(max_pos_, _videoTags[_videoTags.length - 1].position - (_time_sliding - _videoTags[_videoIdx].sliding ));
            if (_audioTags.length) max_pos_ = Math.max(max_pos_, _audioTags[_audioTags.length - 1].position - (_time_sliding - _audioTags[_audioIdx].sliding ));
            return max_pos_;
        }
    }
}

import org.mangui.hls.flv.FLVTag;


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

