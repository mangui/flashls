/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.loader {
    import org.mangui.hls.model.Level;

    import flash.utils.getTimer;
    import flash.utils.clearTimeout;
    import flash.utils.setTimeout;
    import flash.events.ErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.events.IOErrorEvent;

    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.constant.HLSPlayStates;
    import org.mangui.hls.model.AudioTrack;
    import org.mangui.hls.model.Fragment;
    import org.mangui.hls.event.HLSError;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.playlist.AltAudioTrack;
    import org.mangui.hls.playlist.Manifest;

    import flash.net.URLLoader;

    import org.mangui.hls.HLS;

    public class AltAudioLevelLoader {
        CONFIG::LOGGING {
            import org.mangui.hls.utils.Log;
        }
        /** Reference to the hls framework controller. **/
        private var _hls : HLS;
        /** Object that fetches the manifest. **/
        private var _urlloader : URLLoader;
        /** Link to the M3U8 file. **/
        private var _url : String;
        /** Timeout ID for reloading live playlists. **/
        private var _timeoutID : uint;
        /** last reload manifest time **/
        private var _reload_playlists_timer : uint;
        /** current audio level **/
        private var _current_level : int;
        /** reference to manifest being loaded **/
        private var _manifest_loading : Manifest;
        /** is this loader closed **/
        private var _closed : Boolean = false;
        /* playlist retry timeout */
        private var _retry_timeout : Number;
        private var _retry_count : int;

        /** Setup the loader. **/
        public function AltAudioLevelLoader(hls : HLS) {
            _hls = hls;
            _hls.addEventListener(HLSEvent.PLAYBACK_STATE, _stateHandler);
            _hls.addEventListener(HLSEvent.AUDIO_TRACK_SWITCH, _audioTrackSwitchHandler);
        };

        public function dispose() : void {
            _close();
            _hls.removeEventListener(HLSEvent.PLAYBACK_STATE, _stateHandler);
            _hls.removeEventListener(HLSEvent.AUDIO_TRACK_SWITCH, _audioTrackSwitchHandler);
        }

        /** Loading failed; return errors. **/
        private function _errorHandler(event : ErrorEvent) : void {
            var txt : String;
            var code : int;
            if (event is SecurityErrorEvent) {
                code = HLSError.MANIFEST_LOADING_CROSSDOMAIN_ERROR;
                txt = "Cannot load M3U8: crossdomain access denied:" + event.text;
            } else if (event is IOErrorEvent && (HLSSettings.manifestLoadMaxRetry == -1 || _retry_count < HLSSettings.manifestLoadMaxRetry)) {
                CONFIG::LOGGING {
                    Log.warn("I/O Error while trying to load Playlist, retry in " + _retry_timeout + " ms");
                }
                _timeoutID = setTimeout(_loadAudioLevelPlaylist, _retry_timeout);
                /* exponential increase of retry timeout, capped to manifestLoadMaxRetryTimeout */
                _retry_timeout = Math.min(HLSSettings.manifestLoadMaxRetryTimeout, 2 * _retry_timeout);
                _retry_count++;
                return;
            } else {
                code = HLSError.MANIFEST_LOADING_IO_ERROR;
                txt = "Cannot load M3U8: " + event.text;
            }
            var hlsError : HLSError = new HLSError(code, _url, txt);
            _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
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
                newLevel.fragments = frags;
                newLevel.targetduration = Manifest.getTargetDuration(string);
                _hls.audioTracks[_current_level].level = newLevel;
            }
            _hls.dispatchEvent(new HLSEvent(HLSEvent.AUDIO_LEVEL_LOADED, level));
            _manifest_loading = null;
        };

        /** load/reload active M3U8 playlist **/
        private function _loadAudioLevelPlaylist() : void {
            if (_closed) {
                return;
            }
            _reload_playlists_timer = getTimer();
            var altAudioTrack : AltAudioTrack = _hls.altAudioTracks[_hls.audioTracks[_current_level].id];
            _manifest_loading = new Manifest();
            _manifest_loading.loadPlaylist(altAudioTrack.url, _parseAudioPlaylist, _errorHandler, _current_level, _hls.type, HLSSettings.flushLiveURLCache);
            _hls.dispatchEvent(new HLSEvent(HLSEvent.AUDIO_LEVEL_LOADING, _current_level));
        };

        /** When audio track switch occurs, assess the need of loading audio level playlist **/
        private function _audioTrackSwitchHandler(event : HLSEvent) : void {
            _current_level = event.level;
            var audioTrack : AudioTrack = _hls.audioTracks[_current_level];
            if (audioTrack.source == AudioTrack.FROM_PLAYLIST) {
                var altAudioTrack : AltAudioTrack = _hls.altAudioTracks[audioTrack.id];
                if (altAudioTrack.url && audioTrack.level == null) {
                    Log.debug("switch to audio level " + _current_level + ", load Playlist");
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
        private function _stateHandler(event : HLSEvent) : void {
            if (event.state == HLSPlayStates.IDLE) {
                _close();
            }
        };
    }
}
