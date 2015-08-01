/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.stream {
    import org.mangui.hls.constant.HLSPlayStates;
    import org.mangui.hls.constant.HLSSeekStates;
    import org.mangui.hls.controller.BufferThresholdController;
    import org.mangui.hls.demux.ID3Tag;
    import org.mangui.hls.event.HLSError;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.event.HLSPlayMetrics;
    import org.mangui.hls.flv.FLVTag;
    import org.mangui.hls.HLS;
    import org.mangui.hls.HLSSettings;

    import by.blooddy.crypto.Base64;

    import flash.events.Event;
    import flash.events.NetStatusEvent;
    import flash.events.TimerEvent;
    import flash.net.*;
    import flash.utils.*;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
    /** Class that overrides standard flash.net.NetStream class, keeps the buffer filled, handles seek and play state
     *
     * play state transition :
     * 				FROM								TO								condition
     *  HLSPlayStates.IDLE              	HLSPlayStates.PLAYING_BUFFERING     idle => play()/play2() called
     *  HLSPlayStates.IDLE                  HLSPlayStates.PAUSED_BUFFERING      idle => seek() called
     *  HLSPlayStates.PLAYING_BUFFERING  	HLSPlayStates.PLAYING  				buflen > minBufferLength
     *  HLSPlayStates.PAUSED_BUFFERING  	HLSPlayStates.PAUSED  				buflen > minBufferLength
     *  HLSPlayStates.PLAYING  				HLSPlayStates.PLAYING_BUFFERING  	buflen < lowBufferLength
     *  HLSPlayStates.PAUSED  				HLSPlayStates.PAUSED_BUFFERING  	buflen < lowBufferLength
     *
     * seek state transition :
     *
     *              FROM                                TO                              condition
     *  HLSSeekStates.IDLE/SEEKED           HLSSeekStates.SEEKING     play()/play2()/seek() called
     *  HLSSeekStates.SEEKING               HLSSeekStates.SEEKED      upon first FLV tag appending after seek
     *  HLSSeekStates.SEEKED                HLSSeekStates.IDLE        upon playback complete or stop() called
     */
    public class HLSNetStream extends NetStream {
        /** Reference to the framework controller. **/
        private var _hls : HLS;
        /** reference to buffer threshold controller */
        private var _bufferThresholdController : BufferThresholdController;
        /** FLV Tag Buffer . **/
        private var _streamBuffer : StreamBuffer;
        /** Timer used to check buffer and position. **/
        private var _timer : Timer;
        /** Current playback state. **/
        private var _playbackState : String;
        /** Current seek state. **/
        private var _seekState : String;
        /** current playback level **/
        private var _currentLevel : int;
        /** Netstream client proxy */
        private var _client : HLSNetStreamClient;
        /** skipped fragment duration **/
        private var _skippedDuration : Number;

        /** Create the buffer. **/
        public function HLSNetStream(connection : NetConnection, hls : HLS, streamBuffer : StreamBuffer) : void {
            super(connection);
            super.bufferTime = 0.1;
            _hls = hls;
            _skippedDuration = 0;
            _bufferThresholdController = new BufferThresholdController(hls);
            _streamBuffer = streamBuffer;
            _playbackState = HLSPlayStates.IDLE;
            _seekState = HLSSeekStates.IDLE;
            _timer = new Timer(100, 0);
            _timer.addEventListener(TimerEvent.TIMER, _checkBuffer);
            _client = new HLSNetStreamClient();
            _client.registerCallback("onHLSFragmentChange", onHLSFragmentChange);
            _client.registerCallback("onHLSFragmentSkipped", onHLSFragmentSkipped);
            _client.registerCallback("onCaptionInfo", onCaptionInfo);
            _client.registerCallback("onID3Data", onID3Data);
            super.client = _client;
        }

        public function onHLSFragmentChange(level : int, seqnum : int, cc : int, duration : Number, audio_only : Boolean, program_date : Number, width : int, height : int, auto_level : Boolean, customTagNb : int, id3TagNb : int, ... tags) : void {
            CONFIG::LOGGING {
                Log.debug("playing fragment(level/sn/cc):" + level + "/" + seqnum + "/" + cc);
            }
            _currentLevel = level;
            var customTagArray : Array = new Array();
            var id3TagArray : Array = new Array();
            for (var i : uint = 0; i < customTagNb; i++) {
                customTagArray.push(tags[i]);
                CONFIG::LOGGING {
                    Log.debug("custom tag:" + tags[i]);
                }
            }
            for (i = customTagNb; i < tags.length; i+=4) {
                var id3Tag : ID3Tag = new ID3Tag(tags[i],tags[i+1],tags[i+2],tags[i+3]);
                id3TagArray.push(id3Tag);
                CONFIG::LOGGING {
                    Log.debug("id3 tag:" + id3Tag);
                }
            }
            _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_PLAYING, new HLSPlayMetrics(level, seqnum, cc, duration, audio_only, program_date, width, height, auto_level, customTagArray,id3TagArray)));
        }


        public function onHLSFragmentSkipped(level : int, seqnum : int,duration : Number) : void {
            CONFIG::LOGGING {
                Log.warn("skipped fragment(level/sn/duration):" + level + "/" + seqnum + "/" + duration);
            }
            _skippedDuration+=duration;
        }

        // function is called by SCRIPT in FLV
        public function onID3Data(data : ByteArray) : void {
            // we dump the content as base64 to get it to the Javascript in the browser.
            // The client can use window.atob() to decode the ID3Data.
            var dump : String = Base64.encode(data);
            CONFIG::LOGGING {
                Log.debug("id3:" + dump);
            }
            _hls.dispatchEvent(new HLSEvent(HLSEvent.ID3_UPDATED, dump));
        }

        public function onCaptionInfo(info:Object):void
        {
            _hls.dispatchEvent(new HLSEvent(HLSEvent.CLOSED_CAPTION_INFO, info));
        }

        /** timer function, check/update NetStream state, and append tags if needed **/
        private function _checkBuffer(e : Event) : void {
            var buffer : Number = this.bufferLength;
            // Log.info("netstream/total:" + super.bufferLength + "/" + this.bufferLength);
            // Set playback state. no need to check buffer status if seeking
            if (_seekState != HLSSeekStates.SEEKING) {
                // check low buffer condition
                if (buffer <= 0.1) {
                    if (_streamBuffer.reachedEnd || _streamBuffer.liveLoadingStalled) {
                        // Last tag done? Then append sequence end.
                        super.appendBytesAction(NetStreamAppendBytesAction.END_SEQUENCE);
                        super.appendBytes(new ByteArray());
                        // reach end of playlist + playback complete (as buffer is empty).
                        // stop timer, report event and switch to IDLE mode.
                        if(_streamBuffer.reachedEnd) {
                            _timer.stop();
                            CONFIG::LOGGING {
                                Log.debug("reached end of VOD playlist, notify playback complete");
                            }
                            _hls.dispatchEvent(new HLSEvent(HLSEvent.PLAYBACK_COMPLETE));
                            _setPlaybackState(HLSPlayStates.IDLE);
                            _setSeekState(HLSSeekStates.IDLE);
                        } else {
                            // flush buffer and restart playback in case live loading stalled
                            CONFIG::LOGGING {
                                Log.warn("loading stalled: restart playback");
                            }
                            // flush whole buffer before seeking
                            _streamBuffer.flushBuffer();
                            /* seek to force a restart of the playback session  */
                            seek(-1);
                        }
                        return;
                    } else {
                        // buffer <= 0.1 and not EOS, pause playback
                        super.pause();
                    }
                }
                // if buffer len is below lowBufferLength, get into buffering state
                if (!_streamBuffer.reachedEnd && !_streamBuffer.liveLoadingStalled && buffer < _bufferThresholdController.lowBufferLength) {
                    if (_playbackState == HLSPlayStates.PLAYING) {
                        // low buffer condition and play state. switch to play buffering state
                        _setPlaybackState(HLSPlayStates.PLAYING_BUFFERING);
                    } else if (_playbackState == HLSPlayStates.PAUSED) {
                        // low buffer condition and pause state. switch to paused buffering state
                        _setPlaybackState(HLSPlayStates.PAUSED_BUFFERING);
                    }
                }
                // if buffer len is above minBufferLength, get out of buffering state
                if (buffer >= _bufferThresholdController.minBufferLength || _streamBuffer.reachedEnd || _streamBuffer.liveLoadingStalled) {
                    if (_playbackState == HLSPlayStates.PLAYING_BUFFERING) {
                        CONFIG::LOGGING {
                            Log.debug("resume playback");
                        }
                        // resume playback in case it was paused, this can happen if buffer was in really low condition (less than 0.1s)
                        super.resume();
                        _setPlaybackState(HLSPlayStates.PLAYING);
                    } else if (_playbackState == HLSPlayStates.PAUSED_BUFFERING) {
                        _setPlaybackState(HLSPlayStates.PAUSED);
                    }
                }
            }
        }

        /** Return the current playback state. **/
        public function get playbackState() : String {
            return _playbackState;
        }

        /** Return the current seek state. **/
        public function get seekState() : String {
            return _seekState;
        }

        /** Return the current playback quality level **/
        public function get currentLevel() : int {
            return _currentLevel;
        }

        /** append tags to NetStream **/
        public function appendTags(tags : Vector.<FLVTag>) : void {
            if (_seekState == HLSSeekStates.SEEKING) {
                /* this is our first injection after seek(),
                let's flush netstream now
                this is to avoid black screen during seek command */
                super.close();
                _skippedDuration = 0;
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
            }
            // append all tags
            for each (var tagBuffer : FLVTag in tags) {
                // CONFIG::LOGGING {
                //     Log.debug2('inject type/dts/pts:' + tagBuffer.typeString + '/' + tagBuffer.dts + '/' + tagBuffer.pts);
                // }
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
            }
            if (_seekState == HLSSeekStates.SEEKING) {
                // dispatch event to mimic NetStream behaviour
                dispatchEvent(new NetStatusEvent(NetStatusEvent.NET_STATUS, false, false, {code:"NetStream.Seek.Notify", level:"status"}));
                _setSeekState(HLSSeekStates.SEEKED);
            }
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
        }

        /** Change seeking state. **/
        private function _setSeekState(state : String) : void {
            if (state != _seekState) {
                CONFIG::LOGGING {
                    Log.debug('[SEEK_STATE] from ' + _seekState + ' to ' + state);
                }
                _seekState = state;
                _hls.dispatchEvent(new HLSEvent(HLSEvent.SEEK_STATE, _seekState));
            }
        }

        /* also include skipped duration in get time() so that play position will match fragment position */
        override public function get time() : Number {
            return super.time+_skippedDuration;
        }

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
        }

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
        }

        /** get Buffer Length  **/
        override public function get bufferLength() : Number {
            return netStreamBufferLength + _streamBuffer.bufferLength;
        }

        /** get Back Buffer Length  **/
        override public function get backBufferLength() : Number {
            return _streamBuffer.backBufferLength;
        }

        public function get netStreamBufferLength() : Number {
            if (_seekState == HLSSeekStates.SEEKING) {
                return 0;
            } else {
                return super.bufferLength;
            }
        }

        /** Start playing data in the buffer. **/
        override public function seek(position : Number) : void {
            CONFIG::LOGGING {
                Log.info("HLSNetStream:seek(" + position + ")");
            }
            _streamBuffer.seek(position);
            _setSeekState(HLSSeekStates.SEEKING);
            /* if HLS playback state was in PAUSED or IDLE state before seeking,
             * switch to paused buffering state
             * otherwise, switch to playing buffering state
             */
            switch(_playbackState) {
                case HLSPlayStates.IDLE:
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
            /* always pause NetStream while seeking, even if we are in play state
             * in that case, NetStream will be resumed during next call to appendTags()
             */
            super.pause();
            _timer.start();
        }

        public override function set client(client : Object) : void {
            _client.delegate = client;
        }

        public override function get client() : Object {
            return _client.delegate;
        }

        /** Stop playback. **/
        override public function close() : void {
            CONFIG::LOGGING {
                Log.info("HLSNetStream:close");
            }
            super.close();
            _streamBuffer.stop();
            _timer.stop();
            _setPlaybackState(HLSPlayStates.IDLE);
            _setSeekState(HLSSeekStates.IDLE);
        }

        public function dispose_() : void {
            close();
            _bufferThresholdController.dispose();
        }
    }
}
