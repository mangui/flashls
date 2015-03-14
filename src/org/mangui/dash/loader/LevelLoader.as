/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.dash.loader {

    import flash.events.*;
    import flash.net.*;
    import flash.utils.*;
    import org.mangui.adaptive.Adaptive;
    import org.mangui.adaptive.AdaptiveSettings;
    import org.mangui.adaptive.constant.PlayStates;
    import org.mangui.adaptive.constant.Types;
    import org.mangui.adaptive.event.AdaptiveError;
    import org.mangui.adaptive.event.AdaptiveEvent;
    import org.mangui.adaptive.loader.ILevelLoader;
    import org.mangui.adaptive.model.AltAudioTrack;
    import org.mangui.adaptive.model.Fragment;
    import org.mangui.adaptive.model.Level;
    import org.mangui.adaptive.utils.DataUri;


    CONFIG::LOGGING {
        import org.mangui.adaptive.utils.Log;
    }
    /** Loader for dash manifests. **/
    public class LevelLoader implements ILevelLoader {
        /** Reference to the adaptive framework controller. **/
        private var _adaptive : Adaptive;
        /** levels vector. **/
        private var _levels : Vector.<Level>;
        /** Object that fetches the manifest. **/
        private var _urlloader : URLLoader;
        /** Link to the M3U8 file. **/
        private var _url : String;
        /** are all playlists filled ? **/
        private var _canStart : Boolean;
        /** Timeout ID for reloading live/on error playlists. **/
        private var _timeoutID : uint;
        /** Streaming type (live, ondemand). **/
        private var _type : String;
        /** last reload manifest time **/
        private var _reload_playlists_timer : uint;
        /** current level **/
        private var _current_level : int;
        /** is this loader closed **/
        private var _closed : Boolean = false;
        /* playlist retry timeout */
        private var _retry_timeout : Number;
        private var _retry_count : int;
        /* alt audio tracks */
        private var _alt_audio_tracks : Vector.<AltAudioTrack>;

        /** Setup the loader. **/
        public function LevelLoader(adaptive : Adaptive) {
            _adaptive = adaptive;
            _adaptive.addEventListener(AdaptiveEvent.PLAYBACK_STATE, _stateHandler);
            _levels = new Vector.<Level>();
            _urlloader = new URLLoader();
            _urlloader.addEventListener(Event.COMPLETE, _loaderHandler);
            _urlloader.addEventListener(IOErrorEvent.IO_ERROR, _errorHandler);
            _urlloader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, _errorHandler);
        };

        public function dispose() : void {
            _close();
            _urlloader.removeEventListener(Event.COMPLETE, _loaderHandler);
            _urlloader.removeEventListener(IOErrorEvent.IO_ERROR, _errorHandler);
            _urlloader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, _errorHandler);
            _adaptive.removeEventListener(AdaptiveEvent.PLAYBACK_STATE, _stateHandler);
        }

        /** Loading failed; return errors. **/
        private function _errorHandler(event : ErrorEvent) : void {
            var txt : String;
            var code : int;
            if (event is SecurityErrorEvent) {
                code = AdaptiveError.MANIFEST_LOADING_CROSSDOMAIN_ERROR;
                txt = "Cannot load playlist: crossdomain access denied:" + event.text;
            } else if (event is IOErrorEvent && _levels.length && (AdaptiveSettings.manifestLoadMaxRetry == -1 || _retry_count < AdaptiveSettings.manifestLoadMaxRetry)) {
                CONFIG::LOGGING {
                    Log.warn("I/O Error while trying to load Playlist, retry in " + _retry_timeout + " ms");
                }
                _timeoutID = setTimeout(_loadPlaylist, _retry_timeout);
                /* exponential increase of retry timeout, capped to manifestLoadMaxRetryTimeout */
                _retry_timeout = Math.min(AdaptiveSettings.manifestLoadMaxRetryTimeout, 2 * _retry_timeout);
                _retry_count++;
                return;
            } else {
                code = AdaptiveError.MANIFEST_LOADING_IO_ERROR;
                txt = "Cannot load M3U8: " + event.text;
            }
            var dashError : AdaptiveError = new AdaptiveError(code, _url, txt);
            _adaptive.dispatchEvent(new AdaptiveEvent(AdaptiveEvent.ERROR, dashError));
        };

        /** Return the current manifest. **/
        public function get levels() : Vector.<Level> {
            return _levels;
        };

        /** Return the stream type. **/
        public function get type() : String {
            return _type;
        };

        public function get altAudioTracks() : Vector.<AltAudioTrack> {
            return _alt_audio_tracks;
        }

        /** Load the manifest file. **/
        public function load(url : String) : void {
            _close();
            _closed = false;
            _url = url;
            _levels = new Vector.<Level>();
            _canStart = false;
            _reload_playlists_timer = getTimer();
            _retry_timeout = 1000;
            _retry_count = 0;
            _alt_audio_tracks = null;
            _adaptive.dispatchEvent(new AdaptiveEvent(AdaptiveEvent.MANIFEST_LOADING, url));

            if (DataUri.isDataUri(url)) {
                CONFIG::LOGGING {
                    Log.debug("Identified main manifest <" + url + "> as a data URI.");
                }
                var data : String = new DataUri(url).extractData();
                _parseManifest(data || "");
            } else {
                _urlloader.load(new URLRequest(url));
            }
        };

        /** Manifest loaded; check and parse it **/
        private function _loaderHandler(event : Event) : void {
            // successful loading, reset retry counter
            _retry_timeout = 1000;
            _retry_count = 0;
            var loader : URLLoader = URLLoader(event.target);
            _parseManifest(String(loader.data));
        };

        /** Parse First Level Playlist **/
        private function _parseManifest(string : String) : void {
            var xml : XML = new XML(string);
            CONFIG::LOGGING {
                Log.info("Dash Manifest:" + xml.toXMLString());
            }
        };

        /** load/reload active M3U8 playlist **/
        private function _loadPlaylist() : void {
            if (_closed) {
                return;
            }
            _reload_playlists_timer = getTimer();
            _adaptive.dispatchEvent(new AdaptiveEvent(AdaptiveEvent.LEVEL_LOADING, _current_level));
            load(_url);
        };

        private function _close() : void {
            CONFIG::LOGGING {
                Log.debug("cancel any manifest load in progress");
            }
            _closed = true;
            clearTimeout(_timeoutID);
            try {
                _urlloader.close();
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
