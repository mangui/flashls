/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.hls.stream {
    import org.mangui.hls.controller.AutoBufferController;
    import org.mangui.hls.loader.FragmentLoader;
    import org.mangui.hls.event.HLSPlayMetrics;
    import org.mangui.hls.event.HLSError;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.event.HLSMediatime;
    import org.mangui.hls.constant.HLSSeekStates;
    import org.mangui.hls.constant.HLSPlayStates;
    import org.mangui.hls.constant.HLSSeekMode;
    import org.mangui.hls.flv.FLVTag;
    import org.mangui.hls.HLS;
    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.utils.Hex;

    import flash.events.Event;
    import flash.events.NetStatusEvent;
    import flash.events.TimerEvent;
    import flash.net.*;
    import flash.utils.*;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
    /** Class that keeps the buffer filled. **/
    public class HLSNetStream extends NetStream {
        /** Reference to the framework controller. **/
        private var _hls : HLS;
        /** reference to auto buffer manager */
        private var _autoBufferController : AutoBufferController;
        /** FLV tags buffer vector **/
        private var _flvTagBuffer : Vector.<FLVTag>;
        /** FLV tags buffer duration **/
        private var _flvTagBufferDuration : Number;
        /** The fragment loader. **/
        private var _fragmentLoader : FragmentLoader;
        /** means that last fragment of a VOD playlist has been loaded */
        private var _reached_vod_end : Boolean;
        /** Timer used to check buffer and position. **/
        private var _timer : Timer;
        /** requested start position **/
        private var _seek_position_requested : Number;
        /** real start position , retrieved from first fragment **/
        private var _seek_position_real : Number;
        /** seek date in ms , since epoch **/
        private var _seek_date_real : Number = 0;
        /** is a seek operation in progress ? **/
        private var _seek_in_progress : Boolean;
        /** Current play position (relative position from beginning of sliding window) **/
        private var _playback_current_position : Number;
        /** playlist sliding (non null for live playlist) **/
        private var _playlist_sliding_duration : Number;
        /** total duration of buffered data before last discontinuity */
        private var _buffered_before_last_continuity : Number;
        /** buffer min PTS since last discontinuity  */
        private var _buffer_cur_min_pts : Number;
        /** buffer max PTS since last discontinuity  */
        private var _buffer_cur_max_pts : Number;
        /** previous buffer time. **/
        private var _last_buffer : Number;
        /** Current playback state. **/
        private var _playbackState : String;
        /** Current seek state. **/
        private var _seekState : String;
        /** threshold to get out of buffering state
         * by default it is set to _buffer_low_len
         * however if buffer gets empty, its value is moved to _buffer_min_len
         */
        private var _buffer_threshold : Number;
        /** playlist duration **/
        private var _playlist_duration : Number = 0;
        /** level/sn used to detect fragment change **/
        private var _cur_level : int;
        private var _cur_sn : int;
        private var _playbackLevel : int;
        /** Netstream client proxy */
        private var _client : HLSNetStreamClient;

        /** Create the buffer. **/
        public function HLSNetStream(connection : NetConnection, hls : HLS, fragmentLoader : FragmentLoader) : void {
            super(connection);
            super.bufferTime = 0.1;
            _hls = hls;
            _autoBufferController = new AutoBufferController(hls);
            _fragmentLoader = fragmentLoader;
            _hls.addEventListener(HLSEvent.LAST_VOD_FRAGMENT_LOADED, _lastVODFragmentLoadedHandler);
            _hls.addEventListener(HLSEvent.PLAYLIST_DURATION_UPDATED, _playlistDurationUpdated);
            _playbackState = HLSPlayStates.IDLE;
            _seekState = HLSSeekStates.IDLE;
            _timer = new Timer(100, 0);
            _timer.addEventListener(TimerEvent.TIMER, _checkBuffer);
            _client = new HLSNetStreamClient();
            _client.registerCallback("onHLSFragmentChange", onHLSFragmentChange);
            _client.registerCallback("onID3Data", onID3Data);
            super.client = _client;
        };

        public function onHLSFragmentChange(level : int, seqnum : int, cc : int, audio_only : Boolean, width : int, height : int, ... tags) : void {
            CONFIG::LOGGING {
                Log.debug("playing fragment(level/sn/cc):" + level + "/" + seqnum + "/" + cc);
            }
            _playbackLevel = level;
            var tag_list : Array = new Array();
            for (var i : uint = 0; i < tags.length; i++) {
                tag_list.push(tags[i]);
                CONFIG::LOGGING {
                    Log.debug("custom tag:" + tags[i]);
                }
            }
            _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_PLAYING, new HLSPlayMetrics(level, seqnum, cc, audio_only, width, height, tag_list)));
        }

        // function is called by SCRIPT in FLV
        public function onID3Data(data : ByteArray) : void {
            var dump : String = "unset";

            // we dump the content as hex to get it to the Javascript in the browser.
            // from lots of searching, we could use base64, but even then, the decode would
            // not be native, so hex actually seems more efficient
            dump = Hex.fromArray(data);

            CONFIG::LOGGING {
                Log.debug("id3:" + dump);
            }
            _hls.dispatchEvent(new HLSEvent(HLSEvent.ID3_UPDATED, dump));
        }

        /** Check the bufferlength. **/
        private function _checkBuffer(e : Event) : void {
            var playback_absolute_position : Number;
            var playback_relative_position : Number;
            var buffer : Number = this.bufferLength;
            // Calculate the buffer and position.
            if (_seek_in_progress) {
                playback_relative_position = playback_absolute_position = _seek_position_requested;
            } else {
                /** Absolute playback position (start position + play time) **/
                playback_absolute_position = super.time + _seek_position_real;
                /** Relative playback position (Absolute Position - playlist sliding, non null for Live Playlist) **/
                playback_relative_position = playback_absolute_position - _playlist_sliding_duration;
            }
            // only send media time event if data has changed
            if (playback_relative_position != _playback_current_position || buffer != _last_buffer) {
                _playback_current_position = playback_relative_position;
                _last_buffer = buffer;
                var playback_date : Number = _seek_date_real ? 1000 * super.time + _seek_date_real : 0;
                _hls.dispatchEvent(new HLSEvent(HLSEvent.MEDIA_TIME, new HLSMediatime(_playback_current_position, _playlist_duration, buffer, _playlist_sliding_duration, playback_date)));
            }

            // Set playback state. no need to check buffer status if first fragment not yet received
            if (!_seek_in_progress) {
                // check low buffer condition
                if (buffer < HLSSettings.lowBufferLength) {
                    if (buffer <= 0.1) {
                        if (_reached_vod_end) {
                            // reach end of playlist + playback complete (as buffer is empty).
                            // stop timer, report event and switch to IDLE mode.
                            _timer.stop();
                            CONFIG::LOGGING {
                                Log.debug("reached end of VOD playlist, notify playback complete");
                            }
                            _hls.dispatchEvent(new HLSEvent(HLSEvent.PLAYBACK_COMPLETE));
                            _setPlaybackState(HLSPlayStates.IDLE);
                            _setSeekState(HLSSeekStates.IDLE);
                            return;
                        } else {
                            // pause Netstream in really low buffer condition
                            super.pause();
                            if (HLSSettings.minBufferLength == -1) {
                                _buffer_threshold = _autoBufferController.minBufferLength;
                            } else {
                                _buffer_threshold = HLSSettings.minBufferLength;
                            }
                        }
                    }
                    // dont switch to buffering state in case we reached end of a VOD playlist
                    if (!_reached_vod_end) {
                        if (_playbackState == HLSPlayStates.PLAYING) {
                            // low buffer condition and play state. switch to play buffering state
                            _setPlaybackState(HLSPlayStates.PLAYING_BUFFERING);
                        } else if (_playbackState == HLSPlayStates.PAUSED) {
                            // low buffer condition and pause state. switch to paused buffering state
                            _setPlaybackState(HLSPlayStates.PAUSED_BUFFERING);
                        }
                    }
                }
                // in case buffer is full enough or if we have reached end of VOD playlist
                if (buffer >= _buffer_threshold || _reached_vod_end) {
                    /* after we reach back threshold value, set it buffer low value to avoid
                     * reporting buffering state to often. using different values for low buffer / min buffer
                     * allow to fine tune this 
                     */
                    if (HLSSettings.minBufferLength == -1) {
                        // in automode, low buffer threshold should be less than min auto buffer
                        _buffer_threshold = Math.min(_autoBufferController.minBufferLength / 2, HLSSettings.lowBufferLength);
                    } else {
                        _buffer_threshold = HLSSettings.lowBufferLength;
                    }

                    // no more in low buffer state
                    if (_playbackState == HLSPlayStates.PLAYING_BUFFERING) {
                        CONFIG::LOGGING {
                            Log.debug("resume playback");
                        }
                        super.resume();
                        _setPlaybackState(HLSPlayStates.PLAYING);
                    } else if (_playbackState == HLSPlayStates.PAUSED_BUFFERING) {
                        _setPlaybackState(HLSPlayStates.PAUSED);
                    }
                }
            }
            // in case any data available in our FLV buffer, append into NetStream
            if (_flvTagBuffer.length) {
                if (_seek_in_progress) {
                    /* this is our first injection after seek(),
                    let's flush netstream now
                    this is to avoid black screen during seek command */
                    super.close();
                    CONFIG::FLASH_11_1 {
                        try {
                            super.useHardwareDecoder = HLSSettings.useHardwareVideoDecoder;
                        } catch(e : Error) {
                        }
                    }
                    super.play(null);
                    super.appendBytesAction(NetStreamAppendBytesAction.RESET_SEEK);
                    // immediatly pause NetStream, it will be resumed when enough data will be buffered in the NetStream
                    super.pause();
                    _seek_in_progress = false;
                    // dispatch event to mimic NetStream behaviour
                    dispatchEvent(new NetStatusEvent(NetStatusEvent.NET_STATUS, false, false, {code:"NetStream.Seek.Notify", level:"status"}));
                    _setSeekState(HLSSeekStates.SEEKED);
                }
                // CONFIG::LOGGING {
                // Log.debug("appending data into NetStream");
                // }
                while (0 < _flvTagBuffer.length) {
                    var tagBuffer : FLVTag = _flvTagBuffer.shift();
                    // append data until we drain our _buffer
                    try {
                        if (tagBuffer.type == FLVTag.DISCONTINUITY) {
                            super.appendBytesAction(NetStreamAppendBytesAction.RESET_BEGIN);
                            super.appendBytes(FLVTag.getHeader());
                        }
                        super.appendBytes(tagBuffer.data);
                    } catch (error : Error) {
                        var hlsError : HLSError = new HLSError(HLSError.TAG_APPENDING_ERROR, null, tagBuffer.type + ": " + error.message);
                        _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
                    }
                    // Last tag done? Then append sequence end.
                    if (_reached_vod_end && _flvTagBuffer.length == 0) {
                        super.appendBytesAction(NetStreamAppendBytesAction.END_SEQUENCE);
                        super.appendBytes(new ByteArray());
                    }
                }
                // FLV tag buffer drained, reset its duration
                _flvTagBufferDuration = 0;
            }
            // update buffer threshold here if needed
            if (HLSSettings.minBufferLength == -1) {
                _buffer_threshold = _autoBufferController.minBufferLength;
            }
        };

        /** Return the current playback state. **/
        public function get position() : Number {
            return _playback_current_position;
        };

        /** Return the current playback state. **/
        public function get playbackState() : String {
            return _playbackState;
        };

        /** Return the current seek state. **/
        public function get seekState() : String {
            return _seekState;
        };

        /** Return the current playback quality level **/
        public function get playbackLevel() : int {
            return _playbackLevel;
        };

        /** Add a fragment to the buffer. **/
        private function _loaderCallback(level : int, cc : int, sn : int, audio_only : Boolean, width : int, height : int, tag_list : Vector.<String>, tags : Vector.<FLVTag>, min_pts : Number, max_pts : Number, hasDiscontinuity : Boolean, start_position : Number, program_date : Number) : void {
            var tag : FLVTag;
            /* PTS of first tag that will be pushed into FLV tag buffer */
            var first_pts : Number;
            /* PTS of last video keyframe before requested seek position */
            var keyframe_pts : Number;
            if (_seek_position_real == Number.NEGATIVE_INFINITY) {
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
                if (_seek_position_requested < start_position || _seek_position_requested >= start_position + ((max_pts - min_pts) / 1000)) {
                    _seek_position_real = start_position;
                    _seek_date_real = program_date;
                    first_pts = min_pts;
                } else {
                    /* if requested position is within segment bounds, determine real seek position depending on seek mode setting */
                    if (HLSSettings.seekMode == HLSSeekMode.SEGMENT_SEEK) {
                        _seek_position_real = start_position;
                        _seek_date_real = program_date;
                        first_pts = min_pts;
                    } else {
                        /* accurate or keyframe seeking */
                        /* seek_pts is the requested PTS seek position */
                        var seek_pts : Number = min_pts + 1000 * (_seek_position_requested - start_position);
                        /* analyze fragment tags and look for PTS of last keyframe before seek position.*/
                        keyframe_pts = tags[0].pts;
                        for each (tag in tags) {
                            // look for last keyframe with pts <= seek_pts
                            if (tag.keyframe == true && tag.pts <= seek_pts && (tag.type == FLVTag.AVC_HEADER || tag.type == FLVTag.AVC_NALU)) {
                                keyframe_pts = tag.pts;
                            }
                        }
                        if (HLSSettings.seekMode == HLSSeekMode.KEYFRAME_SEEK) {
                            _seek_position_real = start_position + (keyframe_pts - min_pts) / 1000;
                            _seek_date_real = program_date ? program_date + (keyframe_pts - min_pts) : 0;
                            first_pts = keyframe_pts;
                        } else {
                            // accurate seek, to exact requested position
                            _seek_position_real = _seek_position_requested;
                            _seek_date_real = program_date ? program_date + 1000 * (_seek_position_requested - start_position) : 0;
                            first_pts = seek_pts;
                        }
                    }
                }
            } else {
                /* no seek in progress operation, whole fragment will be injected */
                first_pts = min_pts;
                /* check live playlist sliding here :
                _seek_position_real + getTotalBufferedDuration()  should be the start_position
                 * /of the new fragment if the playlist was not sliding
                => live playlist sliding is the difference between the new start position  and this previous value */
                _playlist_sliding_duration = (_seek_position_real + getTotalBufferedDuration()) - start_position;
            }
            /* if first fragment loaded, or if discontinuity, record discontinuity start PTS, and insert discontinuity TAG */
            if (hasDiscontinuity) {
                _buffered_before_last_continuity += (_buffer_cur_max_pts - _buffer_cur_min_pts);
                _buffer_cur_min_pts = first_pts;
                _buffer_cur_max_pts = max_pts;
                tag = new FLVTag(FLVTag.DISCONTINUITY, first_pts, first_pts, false);
                _flvTagBuffer.push(tag);
            } else {
                // same continuity than previously, update its max PTS
                _buffer_cur_max_pts = max_pts;
            }
            /* detect if we are switching to a new fragment. in that case inject a metadata tag
             * Netstream will notify the metadata back when starting playback of this fragment  
             */
            if (_cur_level != level || _cur_sn != sn) {
                _cur_level = level;
                _cur_sn = sn;
                tag = new FLVTag(FLVTag.METADATA, first_pts, first_pts, false);
                var data : ByteArray = new ByteArray();
                data.objectEncoding = ObjectEncoding.AMF0;
                data.writeObject("onHLSFragmentChange");
                data.writeObject(level);
                data.writeObject(sn);
                data.writeObject(cc);
                data.writeObject(audio_only);
                data.writeObject(width);
                data.writeObject(height);
                for each (var custom_tag : String in tag_list) {
                    data.writeObject(custom_tag);
                }
                tag.push(data, 0, data.length);
                _flvTagBuffer.push(tag);
            }

            /* if no seek in progress or if in segment seeking mode : push all FLV tags */
            if (!_seek_in_progress || HLSSettings.seekMode == HLSSeekMode.SEGMENT_SEEK) {
                for each (tag in tags) {
                    _flvTagBuffer.push(tag);
                }
            } else {
                /* keyframe / accurate seeking, we need to filter out some FLV tags */
                for each (tag in tags) {
                    if (tag.pts >= first_pts) {
                        _flvTagBuffer.push(tag);
                    } else {
                        switch(tag.type) {
                            case FLVTag.AAC_HEADER:
                            case FLVTag.AVC_HEADER:
                                tag.pts = tag.dts = first_pts;
                                _flvTagBuffer.push(tag);
                                break;
                            case FLVTag.AVC_NALU:
                                /* only append video tags starting from last keyframe before seek position to avoid playback artifacts
                                 *  rationale of this is that there can be multiple keyframes per segment. if we append all keyframes
                                 *  in NetStream, all of them will be displayed in a row and this will introduce some playback artifacts
                                 *  */
                                if (tag.pts >= keyframe_pts) {
                                    tag.pts = tag.dts = first_pts;
                                    _flvTagBuffer.push(tag);
                                }
                                break;
                            default:
                                break;
                        }
                    }
                }
            }
            _flvTagBufferDuration += (max_pts - first_pts) / 1000;
            CONFIG::LOGGING {
                Log.debug("Loaded position/duration/sliding/discontinuity:" + start_position.toFixed(2) + "/" + ((max_pts - min_pts) / 1000).toFixed(2) + "/" + _playlist_sliding_duration.toFixed(2) + "/" + hasDiscontinuity);
            }
        };

        /** return total buffered duration since seek() call, needed to compute live playlist sliding  */
        private function getTotalBufferedDuration() : Number {
            return (_buffered_before_last_continuity + _buffer_cur_max_pts - _buffer_cur_min_pts) / 1000;
        }

        private function _lastVODFragmentLoadedHandler(event : HLSEvent) : void {
            CONFIG::LOGGING {
                Log.debug("last fragment loaded");
            }
            _reached_vod_end = true;
        }

        private function _playlistDurationUpdated(event : HLSEvent) : void {
            _playlist_duration = event.duration;
        }

        /** Change playback state. **/
        private function _setPlaybackState(state : String) : void {
            if (state != _playbackState) {
                CONFIG::LOGGING {
                    Log.debug('[PLAYBACK_STATE] from ' + _playbackState + ' to ' + state);
                }
                _playbackState = state;
                _hls.dispatchEvent(new HLSEvent(HLSEvent.PLAYBACK_STATE, _playbackState));
            }
        };

        /** Change seeking state. **/
        private function _setSeekState(state : String) : void {
            if (state != _seekState) {
                CONFIG::LOGGING {
                    Log.debug('[SEEK_STATE] from ' + _seekState + ' to ' + state);
                }
                _seekState = state;
                _hls.dispatchEvent(new HLSEvent(HLSEvent.SEEK_STATE, _seekState));
            }
        };

        override public function play(...args) : void {
            var _playStart : Number;
            if (args.length >= 2) {
                _playStart = Number(args[1]);
            } else {
                _playStart = -1;
            }
            CONFIG::LOGGING {
                Log.info("HLSNetStream:play(" + _playStart + ")");
            }
            seek(_playStart);
            _setPlaybackState(HLSPlayStates.PLAYING_BUFFERING);
        }

        override public function play2(param : NetStreamPlayOptions) : void {
            CONFIG::LOGGING {
                Log.info("HLSNetStream:play2(" + param.start + ")");
            }
            seek(param.start);
            _setPlaybackState(HLSPlayStates.PLAYING_BUFFERING);
        }

        /** Pause playback. **/
        override public function pause() : void {
            CONFIG::LOGGING {
                Log.info("HLSNetStream:pause");
            }
            if (_playbackState == HLSPlayStates.PLAYING) {
                super.pause();
                _setPlaybackState(HLSPlayStates.PAUSED);
            } else if (_playbackState == HLSPlayStates.PLAYING_BUFFERING) {
                super.pause();
                _setPlaybackState(HLSPlayStates.PAUSED_BUFFERING);
            }
        };

        /** Resume playback. **/
        override public function resume() : void {
            CONFIG::LOGGING {
                Log.info("HLSNetStream:resume");
            }
            if (_playbackState == HLSPlayStates.PAUSED) {
                super.resume();
                _setPlaybackState(HLSPlayStates.PLAYING);
            } else if (_playbackState == HLSPlayStates.PAUSED_BUFFERING) {
                // dont resume NetStream here, it will be resumed by Timer. this avoids resuming playback while seeking is in progress
                _setPlaybackState(HLSPlayStates.PLAYING_BUFFERING);
            }
        };

        /** get Buffer Length  **/
        override public function get bufferLength() : Number {
            /* remaining buffer is total duration buffered since beginning minus playback time */
            if (_seek_in_progress) {
                return _flvTagBufferDuration;
            } else {
                return super.bufferLength + _flvTagBufferDuration;
            }
        };

        /** Start playing data in the buffer. **/
        override public function seek(position : Number) : void {
            CONFIG::LOGGING {
                Log.info("HLSNetStream:seek(" + position + ")");
            }
            _fragmentLoader.stop();
            _fragmentLoader.seek(position, _loaderCallback);
            _flvTagBuffer = new Vector.<FLVTag>();
            _flvTagBufferDuration = _buffered_before_last_continuity = _buffer_cur_min_pts = _buffer_cur_max_pts = _playlist_sliding_duration = 0;
            _seek_position_requested = Math.max(position, 0);
            _seek_position_real = Number.NEGATIVE_INFINITY;
            _seek_in_progress = true;
            _reached_vod_end = false;
            _cur_level = _cur_sn = -1;
            if (HLSSettings.minBufferLength == -1) {
                _buffer_threshold = _autoBufferController.minBufferLength;
            } else {
                _buffer_threshold = HLSSettings.minBufferLength;
            }
            /* if HLS was in paused state before seeking, 
             * switch to paused buffering state
             * otherwise, switch to playing buffering state
             */
            switch(_playbackState) {
                case HLSPlayStates.PAUSED:
                case HLSPlayStates.PAUSED_BUFFERING:
                    _setPlaybackState(HLSPlayStates.PAUSED_BUFFERING);
                    break;
                case HLSPlayStates.PLAYING:
                case HLSPlayStates.PLAYING_BUFFERING:
                    _setPlaybackState(HLSPlayStates.PLAYING_BUFFERING);
                    break;
                default:
                    break;
            }
            _setSeekState(HLSSeekStates.SEEKING);
            /* always pause NetStream while seeking, even if we are in play state
             * in that case, NetStream will be resumed after first fragment loading
             */
            super.pause();
            _timer.start();
        };

        public override function set client(client : Object) : void {
            _client.delegate = client;
        };

        public override function get client() : Object {
            return _client.delegate;
        }

        /** Stop playback. **/
        override public function close() : void {
            CONFIG::LOGGING {
                Log.info("HLSNetStream:close");
            }
            super.close();
            _timer.stop();
            _fragmentLoader.stop();
            _setPlaybackState(HLSPlayStates.IDLE);
            _setSeekState(HLSSeekStates.IDLE);
        };

        public function dispose_() : void {
            close();
            _autoBufferController.dispose();
            _hls.removeEventListener(HLSEvent.LAST_VOD_FRAGMENT_LOADED, _lastVODFragmentLoadedHandler);
            _hls.removeEventListener(HLSEvent.PLAYLIST_DURATION_UPDATED, _playlistDurationUpdated);
        }
    }
}
