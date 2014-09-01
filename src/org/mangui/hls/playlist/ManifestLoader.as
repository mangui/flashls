package org.mangui.hls.playlist {
    import flash.events.*;
    import flash.net.*;
    import flash.utils.*;

    import org.mangui.hls.*;
    import org.mangui.hls.model.Level;
    import org.mangui.hls.model.Fragment;

    CONFIG::LOGGING {
    import org.mangui.hls.utils.Log;
    }

    /** Loader for hls manifests. **/
    public class ManifestLoader {
        /** Reference to the hls framework controller. **/
        private var _hls : HLS;
        /** levels vector. **/
        private var _levels : Vector.<Level>;
        /** Object that fetches the manifest. **/
        private var _urlloader : URLLoader;
        /** Link to the M3U8 file. **/
        private var _url : String;
        /** are all playlists filled ? **/
        private var _canStart : Boolean;
        /** Timeout ID for reloading live playlists. **/
        private var _timeoutID : uint;
        /** Streaming type (live, ondemand). **/
        private var _type : String;
        /** last reload manifest time **/
        private var _reload_playlists_timer : uint;
        /** current level **/
        private var _current_level : int;
        /** reference to manifest being loaded **/
        private var _manifest_loading : Manifest;
        /** is this loader closed **/
        private var _closed : Boolean = false;
        /* playlist retry timeout */
        private var _retry_timeout : Number;
        private var _retry_count : int;

        /** Setup the loader. **/
        public function ManifestLoader(hls : HLS) {
            _hls = hls;
            _hls.addEventListener(HLSEvent.PLAYBACK_STATE, _stateHandler);
            _hls.addEventListener(HLSEvent.LEVEL_SWITCH, _levelSwitchHandler);
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
            _hls.removeEventListener(HLSEvent.PLAYBACK_STATE, _stateHandler);
            _hls.removeEventListener(HLSEvent.LEVEL_SWITCH, _levelSwitchHandler);
        }

        /** Loading failed; return errors. **/
        private function _errorHandler(event : ErrorEvent) : void {
            var txt : String;
            var code : int;
            if (event is SecurityErrorEvent) {
                code = HLSError.MANIFEST_LOADING_CROSSDOMAIN_ERROR;
                txt = "Cannot load M3U8: crossdomain access denied:" + event.text;
            } else if (event is IOErrorEvent && _levels.length && (HLSSettings.manifestLoadMaxRetry == -1 || _retry_count < HLSSettings.manifestLoadMaxRetry)) {
                CONFIG::LOGGING {
                Log.warn("I/O Error while trying to load Playlist, retry in " + _retry_timeout + " ms");
                }
                _timeoutID = setTimeout(_loadActiveLevelPlaylist, _retry_timeout);
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

        /** Return the current manifest. **/
        public function get levels() : Vector.<Level> {
            return _levels;
        };

        /** Return the stream type. **/
        public function get type() : String {
            return _type;
        };

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
            _hls.dispatchEvent(new HLSEvent(HLSEvent.MANIFEST_LOADING,url));

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

        /** parse a playlist **/
        private function _parseLevelPlaylist(string : String, url : String, index : int) : void {
            if (string != null && string.length != 0) {
                CONFIG::LOGGING {
                Log.debug("level " + index + " playlist:\n" + string);
                }
                var frags : Vector.<Fragment> = Manifest.getFragments(string, url);
                // set fragment and update sequence number range
                _levels[index].updateFragments(frags);
                _levels[index].targetduration = Manifest.getTargetDuration(string);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.PLAYLIST_DURATION_UPDATED, _levels[index].duration));
            }

            // Check whether the stream is live or not finished yet
            if (Manifest.hasEndlist(string)) {
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ENDLIST_FOUND));
                _type = HLSTypes.VOD;
            } else {
                _type = HLSTypes.LIVE;
                var timeout : Number = Math.max(100, _reload_playlists_timer + 1000 * _levels[index].averageduration - getTimer());
                CONFIG::LOGGING {
                Log.debug("Level " + index + " Live Playlist parsing finished: reload in " + timeout.toFixed(0) + " ms");
                }
                _timeoutID = setTimeout(_loadActiveLevelPlaylist, timeout);
            }
            if (!_canStart) {
                _canStart = (_levels[index].fragments.length > 0);
                if (_canStart) {
                    CONFIG::LOGGING {
                    Log.debug("first level filled with at least 1 fragment, notify event");
                    }
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.MANIFEST_LOADED, _levels));
                }
            }
            _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_LOADED, index));
            _manifest_loading = null;
        };

        /** Parse First Level Playlist **/
        private function _parseManifest(string : String) : void {
            // Check for M3U8 playlist or manifest.
            if (string.indexOf(Manifest.HEADER) == 0) {
                // 1 level playlist, create unique level and parse playlist
                if (string.indexOf(Manifest.FRAGMENT) > 0) {
                    var level : Level = new Level();
                    level.url = _url;
                    _levels.push(level);
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.MANIFEST_PARSED, _levels));
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_LOADING,0));
                    CONFIG::LOGGING {
                    Log.debug("1 Level Playlist, load it");
                    }
                    _current_level = 0;
                    _parseLevelPlaylist(string, _url, 0);
                } else if (string.indexOf(Manifest.LEVEL) > 0) {
                    CONFIG::LOGGING {
                    Log.debug("adaptive playlist:\n" + string);
                    }
                    // adaptative playlist, extract levels from playlist, get them and parse them
                    _levels = Manifest.extractLevels(string, _url);
                    // retrieve start level from helper function
                    _current_level = startlevel;
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.MANIFEST_PARSED, _levels));
                    _loadActiveLevelPlaylist();
                    if (string.indexOf(Manifest.ALTERNATE_AUDIO) > 0) {
                        CONFIG::LOGGING {
                        Log.debug("alternate audio level found");
                        }
                        // parse alternate audio tracks
                        var altAudiolevels : Vector.<AltAudioTrack> = Manifest.extractAltAudioTracks(string, _url);
                        _hls.dispatchEvent(new HLSEvent(HLSEvent.ALT_AUDIO_TRACKS_LIST_CHANGE, altAudiolevels));
                    }
                }
            } else {
                var hlsError : HLSError = new HLSError(HLSError.MANIFEST_PARSING_ERROR, _url, "Manifest is not a valid M3U8 file");
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
        };

        /** load/reload active M3U8 playlist **/
        private function _loadActiveLevelPlaylist() : void {
            if (_closed) {
                return;
            }
            _reload_playlists_timer = getTimer();
            // load active M3U8 playlist only
            _manifest_loading = new Manifest();
            _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_LOADING,_current_level));
            _manifest_loading.loadPlaylist(_levels[_current_level].url, _parseLevelPlaylist, _errorHandler, _current_level, _type, HLSSettings.flushLiveURLCache);
        };

        /** When level switch occurs, assess the need of (re)loading new level playlist **/
        private function _levelSwitchHandler(event : HLSEvent) : void {
            if (_current_level != event.level) {
                _current_level = event.level;
                CONFIG::LOGGING {
                Log.debug("switch to level " + _current_level);
                }
                if (_type == HLSTypes.LIVE || _levels[_current_level].fragments.length == 0) {
                    _closed = false;
                    CONFIG::LOGGING {
                    Log.debug("(re)load Playlist");
                    }
                    clearTimeout(_timeoutID);
                    _timeoutID = setTimeout(_loadActiveLevelPlaylist, 0);
                }
            }
        };

        private function _close() : void {
            CONFIG::LOGGING {
            Log.debug("cancel any manifest load in progress");
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

        public function get startlevel() : int {
            var start_level : int = -1;
            if (levels) {
                if (HLSSettings.startFromLevel == -1) {
                    /* if startFromLevel is set to -1, it means that effective startup level
                     * will be determined from first segment download bandwidth
                     * let's use lowest bitrate for this download bandwidth assessment
                     * this should speed up playback start time
                     */
                    return 0;
                }

                // set up start level as being the lowest non-audio level.
                for (var i : int = 0; i < _levels.length; i++) {
                    if (!_levels[i].audio) {
                        start_level = i;
                        break;
                    }
                }
                // in case of audio only playlist, force startLevel to 0
                if (start_level == -1) {
                    CONFIG::LOGGING {
                    Log.info("playlist is audio-only");
                    }
                    start_level = 0;
                } else {
                    if (HLSSettings.startFromLevel > 0) {
                        // adjust start level using a rule by 3
                        start_level += Math.round(HLSSettings.startFromLevel * (_levels.length - start_level - 1));
                    }
                }
            }
            CONFIG::LOGGING {
            Log.debug("start level :" + start_level);
            }
            return start_level;
        }

        public function get seeklevel() : int {
            var seek_level : int = -1;
            if (HLSSettings.seekFromLevel == -1) {
                // keep last level
                return _hls.level;
            }

            // set up seek level as being the lowest non-audio level.
            for (var i : int = 0; i < _levels.length; i++) {
                if (!_levels[i].audio) {
                    seek_level = i;
                    break;
                }
            }
            // in case of audio only playlist, force seek_level to 0
            if (seek_level == -1) {
                seek_level = 0;
            } else {
                if (HLSSettings.seekFromLevel > 0) {
                    // adjust start level using a rule by 3
                    seek_level += Math.round(HLSSettings.seekFromLevel * (_levels.length - seek_level - 1));
                }
            }
            CONFIG::LOGGING {
            Log.debug("seek level :" + seek_level);
            }
            return seek_level;
        }
    }
}
