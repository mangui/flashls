/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.dash.controller {
    import org.mangui.adaptive.Adaptive;
    import org.mangui.adaptive.controller.IAudioTrackController;
    import org.mangui.adaptive.event.AdaptiveEvent;
    import org.mangui.adaptive.model.AudioTrack;

    CONFIG::LOGGING {
        import org.mangui.adaptive.utils.Log;
    }
    /*
     * class that handle audio tracks, consolidating tracks retrieved from Manifest and from Demux
     */
    public class AudioTrackController implements IAudioTrackController {
        /** Reference to the Adaptive controller. **/
        private var _adaptive : Adaptive;
        /** merged audio tracks list **/
        private var _audioTracks : Vector.<AudioTrack>;
        /** current audio track id **/
        private var _audioTrackId : int;

        public function AudioTrackController(adaptive : Adaptive) {
            _adaptive = adaptive;
        }

        public function dispose() : void {
        }

        public function set audioTrack(num : int) : void {
            _audioTrackId = num;
            var ev : AdaptiveEvent = new AdaptiveEvent(AdaptiveEvent.AUDIO_TRACK_SWITCH);
            ev.audioTrack = _audioTrackId;
            _adaptive.dispatchEvent(ev);
            CONFIG::LOGGING {
                Log.info('Setting audio track to ' + num);
            }
        }

        public function get audioTrack() : int {
            return _audioTrackId;
        }

        public function get audioTracks() : Vector.<AudioTrack> {
            return _audioTracks;
        }

        /** triggered by demux, it should return the audio track to be parsed */
        public function audioTrackSelectionHandler(audioTrackList : Vector.<AudioTrack>) : AudioTrack {
            return audioTrackList[0];
        }
    }
}
