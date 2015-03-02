/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.player.osmf.plugins.traits {
    import org.mangui.adaptive.constant.SeekStates;
    import org.mangui.adaptive.event.AdaptiveEvent;
    import org.mangui.hls.HLS;
    import org.osmf.traits.SeekTrait;
    import org.osmf.traits.TimeTrait;

    CONFIG::LOGGING {
    import org.mangui.adaptive.utils.Log;
    }

    public class HLSSeekTrait extends SeekTrait {
        private var _hls : HLS;

        public function HLSSeekTrait(hls : HLS, timeTrait : TimeTrait) {
            CONFIG::LOGGING {
            Log.debug("HLSSeekTrait()");
            }
            super(timeTrait);
            _hls = hls;
            _hls.addEventListener(AdaptiveEvent.SEEK_STATE, _stateChangedHandler);
        }

        override public function dispose() : void {
            CONFIG::LOGGING {
            Log.debug("HLSSeekTrait:dispose");
            }
            _hls.removeEventListener(AdaptiveEvent.SEEK_STATE, _stateChangedHandler);
            super.dispose();
        }

        /**
         * @private
         * Communicates a <code>seeking</code> change to the media through the NetStream.
         * @param newSeeking New <code>seeking</code> value.
         * @param time Time to seek to, in seconds.
         */
        override protected function seekingChangeStart(newSeeking : Boolean, time : Number) : void {
            if (newSeeking) {
                CONFIG::LOGGING {
                Log.info("HLSSeekTrait:seekingChangeStart(newSeeking/time):(" + newSeeking + "/" + time + ")");
                }
                _hls.stream.seek(time);
            }
            super.seekingChangeStart(newSeeking, time);
        }

        /** state changed handler **/
        private function _stateChangedHandler(event : AdaptiveEvent) : void {
            if (seeking && event.state != SeekStates.SEEKING) {
                CONFIG::LOGGING {
                Log.debug("HLSSeekTrait:setSeeking(false);");
                }
                setSeeking(false, timeTrait.currentTime);
            }
        }
    }
}