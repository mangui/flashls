/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.player.osmf.plugins.traits {
    import org.mangui.adaptive.constant.PlayStates;
    import org.mangui.adaptive.event.AdaptiveEvent;
    import org.mangui.hls.HLS;
    import org.osmf.traits.BufferTrait;

    CONFIG::LOGGING {
    import org.mangui.adaptive.utils.Log;
    }

    public class HLSBufferTrait extends BufferTrait {
        private var _hls : HLS;

        public function HLSBufferTrait(hls : HLS) {
            CONFIG::LOGGING {
            Log.debug("HLSBufferTrait()");
            }
            super();
            _hls = hls;
            _hls.addEventListener(AdaptiveEvent.PLAYBACK_STATE, _stateChangedHandler);
        }

        override public function dispose() : void {
            CONFIG::LOGGING {
            Log.debug("HLSBufferTrait:dispose");
            }
            _hls.removeEventListener(AdaptiveEvent.PLAYBACK_STATE, _stateChangedHandler);
            super.dispose();
        }

        override public function get bufferLength() : Number {
            return _hls.stream.bufferLength;
        }

        /** state changed handler **/
        private function _stateChangedHandler(event : AdaptiveEvent) : void {
            switch(event.state) {
                case PlayStates.PLAYING_BUFFERING:
                case PlayStates.PAUSED_BUFFERING:
                    CONFIG::LOGGING {
                    Log.debug("HLSBufferTrait:_stateChangedHandler:setBuffering(true)");
                    }
                    setBuffering(true);
                    break;
                default:
                    CONFIG::LOGGING {
                    Log.debug("HLSBufferTrait:_stateChangedHandler:setBuffering(false)");
                    }
                    setBuffering(false);
                    break;
            }
        }
    }
}
