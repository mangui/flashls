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
    import org.mangui.hls.utils.Log;
    import org.mangui.hls.HLS;
    import org.mangui.hls.flv.FLVTag;

    /*
     * intermediate FLV Tag Buffer
     *  input : FLV tags retrieved from different fragment loaders (video/alt-audio...)
     *  output : provide muxed FLV tags to HLSNetStream
     */
    public class TagBuffer {
        private var _hls : HLS;
        /** Timer used to process FLV tags. **/
        private var _timer : Timer;
        private var _audioTags : Vector.<FLVData>;
        private var _videoTags : Vector.<FLVData>;
        private var _metaTags : Vector.<FLVData>;
        /** playlist duration **/
        private var _playlist_duration : Number = 0;
        /** requested start position **/
        private var _seek_position_requested : Number;
        /** start position of first injected tag **/
        private var _first_start_position : Number;
        private var _seek_pos_reached : Boolean;
        /** Current play position (relative position from beginning of sliding window) **/
        private var _playback_current_position : Number;
        /** playlist sliding (non null for live playlist) **/
        private var _playlist_sliding_duration : Number;
        /** buffer PTS (indexed by continuity counter)  */
        private var _buffer_pts : Dictionary;

        public function TagBuffer(hls : HLS) {
            _hls = hls;
            flushAll();
            _timer = new Timer(100, 0);
            _timer.addEventListener(TimerEvent.TIMER, _checkBuffer);
            _hls.addEventListener(HLSEvent.PLAYLIST_DURATION_UPDATED, _playlistDurationUpdated);
        }

        public function dispose() : void {
            flushAll();
            _hls.removeEventListener(HLSEvent.PLAYLIST_DURATION_UPDATED, _playlistDurationUpdated);
            _timer.stop();
            _hls = null;
            _timer = null;
        }

        public function stop() : void {
            flushAll();
        }

        public function seek(position : Number) : void {
            _seek_position_requested = position;
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
            }
            // update buffer min/max table indexed with continuity counter
            if (_buffer_pts[continuity] == undefined) {
                _buffer_pts[continuity] = new BufferPTS(min_pts, max_pts);
            } else {
                (_buffer_pts[continuity] as BufferPTS).max = max_pts;
            }
            _timer.start();
        }

        /** Return the current playback state. **/
        public function get position() : Number {
            return _playback_current_position;
        };

        public function get audioBufferLength() : Number {
            return getbuflen(_audioTags);
        }

        public function get videoBufferLength() : Number {
            return getbuflen(_videoTags);
        }

        /**  Timer **/
        private function _checkBuffer(e : Event) : void {
            var tags : Vector.<FLVTag> = new Vector.<FLVTag>();
            var min_pts : Number;
            var max_pts : Number;
            var start_position : Number;
            var continuity : int;

            /* report buffer len */
            var playback_absolute_position : Number;
            //Log.info("stream/audio/video bufferLength:" + _hls.stream.bufferLength + "/" + audioBufferLength + "/" + videoBufferLength);
            var buffer : Number = _hls.stream.bufferLength + Math.max(audioBufferLength, videoBufferLength);
            // Calculate the buffer and position.
            if (_hls.seekState == HLSSeekStates.SEEKING) {
                _playback_current_position = playback_absolute_position = _seek_position_requested;
            } else {
                /** Absolute playback position (start position + play time) **/
                playback_absolute_position = _hls.stream.time + (_hls.stream as HLSNetStream).seekPosition;
                /** Relative playback position (Absolute Position - playlist sliding, non null for Live Playlist) **/
                _playback_current_position = playback_absolute_position - _playlist_sliding_duration;
            }
            _hls.dispatchEvent(new HLSEvent(HLSEvent.MEDIA_TIME, new HLSMediatime(_playback_current_position, _playlist_duration, buffer, _playlist_sliding_duration)));

            /* only append tags if seek position has been reached, otherwise wait for more tags to come
             * this is to ensure that accurate seeking will work appropriately
             */
            if (_seek_pos_reached || max_pos >= _seek_position_requested) {
                var flvdata : FLVData;
                while ((flvdata = shift()) != null) {
                    tags.push(flvdata.tag);
                    if (isNaN(start_position)) {
                        start_position = flvdata.position;
                        continuity = flvdata.continuity;
                    }
                }
                if (tags.length) {
                    min_pts = tags[0].pts;
                    max_pts = tags[tags.length - 1].pts;
                    (_hls.stream as HLSNetStream).appendTags(tags, min_pts, max_pts, start_position);
                    Log.debug("appending " + tags.length + " tags");
                    _seek_pos_reached = true;
                }
            }
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
         * 
         * return next tag from queue, using the following priority :
         * smallest continuity
         * then smallest pts
         * then metadata then video then audio tags
         */
        private function shift() : FLVData {
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
            if (_metaTags.length && _metaTags[0].continuity == continuity && _metaTags[0].tag.pts == pts) return _metaTags.shift();
            if (_videoTags.length && _videoTags[0].continuity == continuity && _videoTags[0].tag.pts == pts) return _videoTags.shift();
            else return _audioTags.shift();
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

