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
        /** playlist duration **/
        private var _playlist_duration : Number = 0;
        /** requested start position **/
        private var _seek_position_requested : Number;
        /** real start position , retrieved from first fragment **/
        private var _seek_position_real : Number;
        /** start position of first injected tag **/
        private var _first_start_position : Number;
        private var _seek_pos_reached : Boolean;
        /** playlist sliding (non null for live playlist) **/
        private var _playlist_sliding_duration : Number;
        /** buffer PTS (indexed by continuity counter)  */
        private var _buffer_pts : Dictionary;
        private static const MIN_NETSTREAM_BUFFER_SIZE : Number = 1.0;
        private static const MAX_NETSTREAM_BUFFER_SIZE : Number = 2.0;

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

        public function seek(position : Number) : void {
            _seek_position_requested = position;
            _fragmentLoader.stop();
            _fragmentLoader.seek(position);
            flushAll();
            _timer.start();
        }

        public function flushAll() : void {
            _audioTags = new Vector.<FLVData>();
            _videoTags = new Vector.<FLVData>();
            _metaTags = new Vector.<FLVData>();
            _buffer_pts = new Dictionary();
            _seek_pos_reached = false;
            _playlist_sliding_duration = 0;
            _first_start_position = -1;
        }

        public function flushAudio() : void {
            _audioTags = new Vector.<FLVData>();
        }

        public function appendTags(tags : Vector.<FLVTag>, min_pts : Number, max_pts : Number, continuity : int, start_position : Number) : void {
            for each (var tag : FLVTag in tags) {
                var position : Number = start_position + (tag.pts - min_pts) / 1000;
                var tagData : FLVData = new FLVData(tag, position, continuity);
                switch(tag.type) {
                    case FLVTag.AAC_HEADER:
                    case FLVTag.AAC_RAW:
                    case FLVTag.MP3_RAW:
                        _audioTags.push(tagData);
                        break;
                    case FLVTag.AVC_HEADER:
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
                // Log.info("seek pos/getTotalBufferedDuration/start pos:" + _seek_position_requested + "/" + getTotalBufferedDuration() + "/" + start_position);
                _playlist_sliding_duration = (_first_start_position + getTotalBufferedDuration()) - start_position;
            } else {
                if (_first_start_position == -1) {
                    // remember position of first tag injected after seek. it will be used for playlist sliding computation
                    _first_start_position = start_position;
                }
                /* if in seeking mode, force timer start here, this could help reducing the seek time by 100ms 
                 */
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
                    return _seek_position_real + _hls.stream.time - _playlist_sliding_duration;
                case HLSSeekStates.IDLE:
                default:
                    return 0;
            }
        };

        public function get audioBufferLength() : Number {
            return getbuflen(_audioTags);
        }

        public function get videoBufferLength() : Number {
            return getbuflen(_videoTags);
        }

        public function get bufferLength() : Number {
            return Math.max(audioBufferLength, videoBufferLength);
        }

        /**  Timer **/
        private function _checkBuffer(e : Event) : void {
            // dispatch media time event
            _hls.dispatchEvent(new HLSEvent(HLSEvent.MEDIA_TIME, new HLSMediatime(position, _playlist_duration, _hls.stream.bufferLength, _playlist_sliding_duration)));

            /* only append tags if seek position has been reached, otherwise wait for more tags to come
             * this is to ensure that accurate seeking will work appropriately
             */

            var duration : Number = 0;
            if (_seek_pos_reached) {
                var netStreamBuffer : Number = (_hls.stream as HLSNetStream).netStreamBufferLength;
                if (netStreamBuffer < MIN_NETSTREAM_BUFFER_SIZE) {
                    duration = MAX_NETSTREAM_BUFFER_SIZE - netStreamBuffer;
                }
            } else if (max_pos >= _seek_position_requested) {
                duration = _seek_position_requested + MAX_NETSTREAM_BUFFER_SIZE - _first_start_position;
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
                        Log.debug2("appending " + tags.length + " tags, max duration:" + duration);
                    }
                    (_hls.stream as HLSNetStream).appendTags(tags);
                }
            }
        }

        /* filter/tweak tags to seek accurately into the stream */
        private function seekFilterTags(tags : Vector.<FLVData>) : Vector.<FLVData> {
            var filteredTags : Vector.<FLVData>=  new Vector.<FLVData>();
            /* PTS of first tag that will be pushed into FLV tag buffer */
            var first_pts : Number;
            /* PTS of last video keyframe before requested seek position */
            var keyframe_pts : Number;
            /* */
            var min_offset : Number = tags[0].position;
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
                    if (tag.pts >= first_pts) {
                        filteredTags.push(flvData);
                    } else {
                        switch(tag.type) {
                            case FLVTag.AAC_HEADER:
                            case FLVTag.AVC_HEADER:
                            case FLVTag.METADATA:
                            case FLVTag.DISCONTINUITY:
                                tag.pts = tag.dts = first_pts;
                                filteredTags.push(flvData);
                                break;
                            case FLVTag.AVC_NALU:
                                /* only append video tags starting from last keyframe before seek position to avoid playback artifacts
                                 *  rationale of this is that there can be multiple keyframes per segment. if we append all keyframes
                                 *  in NetStream, all of them will be displayed in a row and this will introduce some playback artifacts
                                 *  */
                                if (tag.pts >= keyframe_pts) {
                                    tag.pts = tag.dts = first_pts;
                                    filteredTags.push(flvData);
                                }
                                break;
                            default:
                                break;
                        }
                    }
                }
            }
            return filteredTags;
        }

        private function _playlistDurationUpdated(event : HLSEvent) : void {
            _playlist_duration = event.duration;
        }

        private function getbuflen(tags : Vector.<FLVData>) : Number {
            var min_pts : Number = 0;
            var max_pts : Number = 0;
            var continuity : int = -1;
            var len : Number = 0;

            for each (var data : FLVData in tags) {
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
        private function getnextqueue() : Vector.<FLVData> {
            if (_videoTags.length == 0 && _audioTags.length == 0 && _metaTags.length == 0)
                return null;

            var continuity : int = int.MAX_VALUE;
            // find smallest continuity counter
            if (_metaTags.length) continuity = Math.min(continuity, _metaTags[0].continuity);
            if (_videoTags.length) continuity = Math.min(continuity, _videoTags[0].continuity);
            if (_audioTags.length) continuity = Math.min(continuity, _audioTags[0].continuity);

            var pts : Number = Number.MAX_VALUE;
            // for this continuity counter, find smallest PTS
            if (_metaTags.length && _metaTags[0].continuity == continuity) pts = Math.min(pts, _metaTags[0].tag.pts);
            if (_videoTags.length && _videoTags[0].continuity == continuity) pts = Math.min(pts, _videoTags[0].tag.pts);
            if (_audioTags.length && _audioTags[0].continuity == continuity) pts = Math.min(pts, _audioTags[0].tag.pts);

            // for this continuity counter, this PTS, prioritize tags with the following order : metadata/video/audio
            if (_metaTags.length && _metaTags[0].continuity == continuity && _metaTags[0].tag.pts == pts) return _metaTags;
            if (_videoTags.length && _videoTags[0].continuity == continuity && _videoTags[0].tag.pts == pts) return _videoTags;
            else return _audioTags;
        }

        private function shiftmultipletags(max_duration : Number) : Vector.<FLVData> {
            var tags : Vector.<FLVData>=  new Vector.<FLVData>();
            var queue : Vector.<FLVData> = getnextqueue();
            if (queue) {
                var continuity : int = queue[0].continuity;
                var min_pts : Number = queue[0].tag.pts;
                while ((queue = getnextqueue()) != null && queue[0].continuity == continuity && (queue[0].tag.pts - min_pts) / 1000 < max_duration ) {
                    tags.push(queue.shift());
                }
            }
            return tags;
        }

        /*
        private function get min_pos() : Number {
        var min_pos_ : Number = Number.POSITIVE_INFINITY;
        if (_metaTags.length) min_pos_ = Math.min(min_pos_, _metaTags[0].position);
        if (_videoTags.length) min_pos_ = Math.min(min_pos_, _videoTags[0].position);
        if (_audioTags.length) min_pos_ = Math.min(min_pos_, _audioTags[0].position);
        return min_pos_;
        }
         */
        private function get max_pos() : Number {
            var max_pos_ : Number = Number.NEGATIVE_INFINITY;
            if (_metaTags.length) max_pos_ = Math.max(max_pos_, _metaTags[_metaTags.length - 1].position);
            if (_videoTags.length) max_pos_ = Math.max(max_pos_, _videoTags[_videoTags.length - 1].position);
            if (_audioTags.length) max_pos_ = Math.max(max_pos_, _audioTags[_audioTags.length - 1].position);
            return max_pos_;
        }
    }
}

import org.mangui.hls.flv.FLVTag;


class FLVData {
    public var tag : FLVTag;
    public var position : Number;
    public var continuity : int;

    public function FLVData(tag : FLVTag, position : Number, continuity : int) {
        this.tag = tag;
        this.position = position;
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

