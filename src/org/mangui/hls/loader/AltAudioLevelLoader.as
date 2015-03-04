/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.loader {

    import flash.events.ErrorEvent;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.net.URLLoader;
    import flash.utils.clearTimeout;
    import flash.utils.getTimer;
    import flash.utils.setTimeout;
    import org.mangui.adaptive.Adaptive;
    import org.mangui.adaptive.AdaptiveSettings;
    import org.mangui.adaptive.constant.PlayStates;
    import org.mangui.adaptive.event.AdaptiveError;
    import org.mangui.adaptive.event.AdaptiveEvent;
    import org.mangui.adaptive.model.AltAudioTrack;
    import org.mangui.adaptive.model.AudioTrack;
    import org.mangui.adaptive.model.Fragment;
    import org.mangui.adaptive.model.Level;
    import org.mangui.hls.playlist.Manifest;

    public class AltAudioLevelLoader {
        CONFIG::LOGGING {
            import org.mangui.adaptive.utils.Log;
        }
        /** Reference to the hls framework controller. **/
        private var _hls : Adaptive;
        /** Object that fetches the manifest. **/
        private var _urlloader : URLLoader;
        /** Link to the M3U8 file. **/
        private var _url : String;
        /** Timeout ID for reloading live playlists. **/
        private var _timeoutID : uint;
        /** last reload manifest time **/
        private var _reload_playlists_timer : uint;
        /** current audio level **/
        private var _current_track : int;
        /** reference to manifest being loaded **/
        private var _manifest_loading : Manifest;
        /** is this loader closed **/
        private var _closed : Boolean = false;
        /* playlist retry timeout */
        private var _retry_timeout : Number;
        private var _retry_count : int;

        /** Setup the loader. **/
        public function AltAudioLevelLoader(hls : Adaptive) {
            _hls = hls;
            _hls.addEventListener(AdaptiveEvent.PLAYBACK_STATE, _stateHandler);
            _hls.addEventListener(AdaptiveEvent.AUDIO_TRACK_SWITCH, _audioTrackSwitchHandler);
        };

        public function dispose() : void {
            _close();
            _hls.removeEventListener(AdaptiveEvent.PLAYBACK_STATE, _stateHandler);
            _hls.removeEventListener(AdaptiveEvent.AUDIO_TRACK_SWITCH, _audioTrackSwitchHandler);
        }

        /** Loading failed; return errors. **/
        private function _errorHandler(event : ErrorEvent) : void {
            var txt : String;
            var code : int;
            if (event is SecurityErrorEvent) {
                code = AdaptiveError.MANIFEST_LOADING_CROSSDOMAIN_ERROR;
                txt = "Cannot load M3U8: crossdomain access denied:" + event.text;
            } else if (event is IOErrorEvent && (AdaptiveSettings.manifestLoadMaxRetry == -1 || _retry_count < AdaptiveSettings.manifestLoadMaxRetry)) {
                CONFIG::LOGGING {
                    Log.warn("I/O Error while trying to load Playlist, retry in " + _retry_timeout + " ms");
                }
                _timeoutID = setTimeout(_loadAudioLevelPlaylist, _retry_timeout);
                /* exponential increase of retry timeout, capped to manifestLoadMaxRetryTimeout */
                _retry_timeout = Math.min(AdaptiveSettings.manifestLoadMaxRetryTimeout, 2 * _retry_timeout);
                _retry_count++;
                return;
            } else {
                code = AdaptiveError.MANIFEST_LOADING_IO_ERROR;
                txt = "Cannot load M3U8: " + event.text;
            }
            var hlsError : AdaptiveError = new AdaptiveError(code, _url, txt);
            _hls.dispatchEvent(new AdaptiveEvent(AdaptiveEvent.ERROR, hlsError));
        };

        /** parse a playlist **/
        private function _parseAudioPlaylist(string : String, url : String, level : int) : void {
            if (string != null && string.length != 0) {
                CONFIG::LOGGING {
                    Log.debug("audio level " + level + " playlist:\n" + string);
                }
                var frags : Vector.<Fragment> = Manifest.getFragments(string, url, level);
                // set fragment and update sequence number range
                var newLevel : Level = new Level();
                newLevel.updateFragments(frags);
                newLevel.targetduration = Manifest.getTargetDuration(string);
            // if stream is live, arm a timer to periodically reload playlist
            if (!Manifest.hasEndlist(string)) {
                var timeout : Number = Math.max(100, _reload_playlists_timer + 1000 * newLevel.averageduration - getTimer());
                CONFIG::LOGGING {
                    Log.debug("Alt Audio Level Live Playlist parsing finished: reload in " + timeout.toFixed(0) + " ms");
                }
                _timeoutID = setTimeout(_loadAudioLevelPlaylist, timeout);
            }
                _hls.audioTracks[_current_track].level = newLevel;
            }
            _hls.dispatchEvent(new AdaptiveEvent(AdaptiveEvent.AUDIO_LEVEL_LOADED, level));
            _manifest_loading = null;
        };

        /** load/reload active M3U8 playlist **/
        private function _loadAudioLevelPlaylist() : void {
            if (_closed) {
                return;
            }
            _reload_playlists_timer = getTimer();
            var altAudioTrack : AltAudioTrack = _hls.altAudioTracks[_hls.audioTracks[_current_track].id];
            _manifest_loading = new Manifest();
            _manifest_loading.loadPlaylist(altAudioTrack.url, _parseAudioPlaylist, _errorHandler, _current_track, _hls.type, AdaptiveSettings.flushLiveURLCache);
            _hls.dispatchEvent(new AdaptiveEvent(AdaptiveEvent.AUDIO_LEVEL_LOADING, _current_track));
        };

        /** When audio track switch occurs, assess the need of loading audio level playlist **/
        private function _audioTrackSwitchHandler(event : AdaptiveEvent) : void {
            _current_track = event.audioTrack;
            var audioTrack : AudioTrack = _hls.audioTracks[_current_track];
            if (audioTrack.source == AudioTrack.FROM_PLAYLIST) {
                var altAudioTrack : AltAudioTrack = _hls.altAudioTracks[audioTrack.id];
                if (altAudioTrack.url && audioTrack.level == null) {
                    CONFIG::LOGGING {
                        Log.debug("switch to audio track " + _current_track + ", load Playlist");
                    }
                    _retry_timeout = 1000;
                    _retry_count = 0;
                    _closed = false;
                    clearTimeout(_timeoutID);
                    _timeoutID = setTimeout(_loadAudioLevelPlaylist, 0);
                }
            }
        };

        private function _close() : void {
            CONFIG::LOGGING {
                Log.debug("cancel any audio level load in progress");
            }
            _closed = true;
            clearTimeout(_timeoutID);
            try {
                _urlloader.close();
                if (_manifest_loading) {
                    _manifest_loading.close();
                }
            } catch(e : Error) {
            }
        }

        /** When the framework idles out, stop reloading manifest **/
        private function _stateHandler(event : AdaptiveEvent) : void {
            if (event.state == PlayStates.IDLE) {
                _close();
            }
        };
    }
}
