/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.stream {
    import org.mangui.hls.controller.BufferThresholdController;
    import org.mangui.hls.event.HLSPlayMetrics;
    import org.mangui.hls.event.HLSError;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.constant.HLSSeekStates;
    import org.mangui.hls.constant.HLSPlayStates;
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
    /** Class that overrides standard flash.net.NetStream class, keeps the buffer filled, handles seek and play state
     * 
     * play state transition :
     * 				FROM								TO								condition 	
     *  HLSPlayStates.IDLE              	HLSPlayStates.PLAYING_BUFFERING     play()/play2()/seek() called
     *  HLSPlayStates.PLAYING_BUFFERING  	HLSPlayStates.PLAYING  				buflen > minBufferLength
     *  HLSPlayStates.PAUSED_BUFFERING  	HLSPlayStates.PAUSED  				buflen > minBufferLength
     *  HLSPlayStates.PLAYING  				HLSPlayStates.PLAYING_BUFFERING  	buflen < lowBufferLength
     *  HLSPlayStates.PAUSED  				HLSPlayStates.PAUSED_BUFFERING  	buflen < lowBufferLength
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
        private var _playbackLevel : int;
        /** Netstream client proxy */
        private var _client : HLSNetStreamClient;

        /** Create the buffer. **/
        public function HLSNetStream(connection : NetConnection, hls : HLS, streamBuffer : StreamBuffer) : void {
            super(connection);
            super.bufferTime = 0.1;
            _hls = hls;
            _bufferThresholdController = new BufferThresholdController(hls);
            _streamBuffer = streamBuffer;
            _playbackState = HLSPlayStates.IDLE;
            _seekState = HLSSeekStates.IDLE;
            _timer = new Timer(100, 0);
            _timer.addEventListener(TimerEvent.TIMER, _checkBuffer);
            _client = new HLSNetStreamClient();
            _client.registerCallback("onHLSFragmentChange", onHLSFragmentChange);
            _client.registerCallback("onID3Data", onID3Data);
            super.client = _client;
        };

        public function onHLSFragmentChange(level : int, seqnum : int, cc : int, audio_only : Boolean, program_date : Number, width : int, height : int, ... tags) : void {
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
            _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_PLAYING, new HLSPlayMetrics(level, seqnum, cc, audio_only, program_date, width, height, tag_list)));
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

        /** timer function, check/update NetStream state, and append tags if needed **/
        private function _checkBuffer(e : Event) : void {
            var buffer : Number = this.bufferLength;
            // Log.info("netstream/total:" + super.bufferLength + "/" + this.bufferLength);
            // Set playback state. no need to check buffer status if seeking
            if (_seekState != HLSSeekStates.SEEKING) {
                // check low buffer condition
                if (buffer <= 0.1) {
                    if (_streamBuffer.reachedEnd) {
                        // Last tag done? Then append sequence end.
                        super.appendBytesAction(NetStreamAppendBytesAction.END_SEQUENCE);
                        super.appendBytes(new ByteArray());
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
                        // buffer <= 0.1 and not EOS, pause playback
                        super.pause();
                    }
                }
                // if buffer len is below lowBufferLength, get into buffering state
                if (!_streamBuffer.reachedEnd && buffer < _bufferThresholdController.lowBufferLength) {
                    if (_playbackState == HLSPlayStates.PLAYING) {
                        // low buffer condition and play state. switch to play buffering state
                        _setPlaybackState(HLSPlayStates.PLAYING_BUFFERING);
                    } else if (_playbackState == HLSPlayStates.PAUSED) {
                        // low buffer condition and pause state. switch to paused buffering state
                        _setPlaybackState(HLSPlayStates.PAUSED_BUFFERING);
                    }
                }
                // if buffer len is above minBufferLength, get out of buffering state
                if (buffer >= _bufferThresholdController.minBufferLength || _streamBuffer.reachedEnd) {
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

        /** append tags to NetStream **/
        public function appendTags(tags : Vector.<FLVTag>) : void {
            if (_seekState == HLSSeekStates.SEEKING) {
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
            }
            // append all tags
            for each (var tagBuffer : FLVTag in tags) {
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
        };

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
            return netStreamBufferLength + _streamBuffer.bufferLength;
        };

        /** get Back Buffer Length  **/
        override public function get backBufferLength() : Number {
            return _streamBuffer.backBufferLength;
        };

        public function get netStreamBufferLength() : Number {
            if (_seekState == HLSSeekStates.SEEKING) {
                return 0;
            } else {
                return super.bufferLength;
            }
        };

        /** Start playing data in the buffer. **/
        override public function seek(position : Number) : void {
            CONFIG::LOGGING {
                Log.info("HLSNetStream:seek(" + position + ")");
            }
            _streamBuffer.seek(position);
            _setSeekState(HLSSeekStates.SEEKING);
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
            /* always pause NetStream while seeking, even if we are in play state
             * in that case, NetStream will be resumed during next call to appendTags()
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
            _streamBuffer.stop();
            _timer.stop();
            _setPlaybackState(HLSPlayStates.IDLE);
            _setSeekState(HLSSeekStates.IDLE);
        };

        public function dispose_() : void {
            close();
            _bufferThresholdController.dispose();
        }
    }
}
