/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.player.osmf.plugins.traits {
    import org.mangui.adaptive.event.AdaptiveEvent;
    import org.mangui.hls.HLS;
    import org.osmf.traits.TimeTrait;

    CONFIG::LOGGING {
    import org.mangui.adaptive.utils.Log;
    }

    public class HLSTimeTrait extends TimeTrait {
        private var _hls : HLS;

        public function HLSTimeTrait(hls : HLS, duration : Number = 0) {
            CONFIG::LOGGING {
            Log.debug("HLSTimeTrait()");
            }
            super(duration);
            setCurrentTime(0);
            _hls = hls;
            _hls.addEventListener(AdaptiveEvent.MEDIA_TIME, _mediaTimeHandler);
            _hls.addEventListener(AdaptiveEvent.PLAYBACK_COMPLETE, _playbackComplete);
        }

        override public function dispose() : void {
            CONFIG::LOGGING {
            Log.debug("HLSTimeTrait:dispose");
            }
            _hls.removeEventListener(AdaptiveEvent.MEDIA_TIME, _mediaTimeHandler);
            _hls.removeEventListener(AdaptiveEvent.PLAYBACK_COMPLETE, _playbackComplete);
            super.dispose();
        }

        /** Update playback position/duration **/
        private function _mediaTimeHandler(event : AdaptiveEvent) : void {
            var new_duration : Number = event.mediatime.duration;
            var new_position : Number = Math.max(0, event.mediatime.position);
            setDuration(new_duration);
            setCurrentTime(new_position);
        };

        /** playback complete handler **/
        private function _playbackComplete(event : AdaptiveEvent) : void {
            signalComplete();
        }
    }
}