/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.loader {
    import flash.events.ErrorEvent;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.ProgressEvent;
    import flash.events.SecurityErrorEvent;
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.utils.clearTimeout;
    import flash.utils.getTimer;
    import flash.utils.setTimeout;
    import org.mangui.hls.constant.HLSLoaderTypes;
    import org.mangui.hls.constant.HLSPlayStates;
    import org.mangui.hls.constant.HLSTypes;
    import org.mangui.hls.event.HLSError;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.event.HLSLoadMetrics;
    import org.mangui.hls.HLS;
    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.model.Fragment;
    import org.mangui.hls.model.Level;
    import org.mangui.hls.playlist.AltAudioTrack;
    import org.mangui.hls.playlist.DataUri;
    import org.mangui.hls.playlist.Manifest;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
    public class LevelLoader {
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
        /* alt audio tracks */
        private var _alt_audio_tracks : Vector.<AltAudioTrack>;
        /* manifest load metrics */
        private var _metrics : HLSLoadMetrics;

        /** Setup the loader. **/
        public function LevelLoader(hls : HLS) {
            _hls = hls;
            _hls.addEventListener(HLSEvent.PLAYBACK_STATE, _stateHandler);
            _hls.addEventListener(HLSEvent.LEVEL_SWITCH, _levelSwitchHandler);
            _levels = new Vector.<Level>();
        };

        public function dispose() : void {
            _close();
            if(_urlloader) {
                _urlloader.removeEventListener(Event.COMPLETE, _loadCompleteHandler);
                _urlloader.removeEventListener(ProgressEvent.PROGRESS, _loadProgressHandler);
                _urlloader.removeEventListener(IOErrorEvent.IO_ERROR, _errorHandler);
                _urlloader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, _errorHandler);
                _urlloader = null;
            }
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

        public function get altAudioTracks() : Vector.<AltAudioTrack> {
            return _alt_audio_tracks;
        }

        /** Load the manifest file. **/
        public function load(url : String) : void {
            if(!_urlloader) {
                //_urlloader = new URLLoader();
                var urlLoaderClass : Class = _hls.URLloader as Class;
                _urlloader = (new urlLoaderClass()) as URLLoader;
                _urlloader.addEventListener(Event.COMPLETE, _loadCompleteHandler);
                _urlloader.addEventListener(ProgressEvent.PROGRESS, _loadProgressHandler);
                _urlloader.addEventListener(IOErrorEvent.IO_ERROR, _errorHandler);
                _urlloader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, _errorHandler);
            }
            _close();
            _closed = false;
            _url = url;
            _levels = new Vector.<Level>();
            _canStart = false;
            _reload_playlists_timer = getTimer();
            _retry_timeout = 1000;
            _retry_count = 0;
            _alt_audio_tracks = null;
            _hls.dispatchEvent(new HLSEvent(HLSEvent.MANIFEST_LOADING, url));

            if (DataUri.isDataUri(url)) {
                CONFIG::LOGGING {
                    Log.debug("Identified main manifest <" + url + "> as a data URI.");
                }
                var data : String = new DataUri(url).extractData();
                _parseManifest(data || "");
            } else {
                _urlloader.load(new URLRequest(url));
                _metrics = new HLSLoadMetrics(HLSLoaderTypes.MANIFEST);
                _metrics.loading_request_time = getTimer();
            }
        };

        /** loading progress handler, use to determine loading latency **/
        private function _loadProgressHandler(event : Event) : void {
            if(_metrics.loading_begin_time == 0) {
                _metrics.loading_begin_time = getTimer();
            }
        };


        /** Manifest loaded; check and parse it **/
        private function _loadCompleteHandler(event : Event) : void {
             _metrics.loading_end_time = getTimer();
            // successful loading, reset retry counter
            _retry_timeout = 1000;
            _retry_count = 0;
            _parseManifest(String(_urlloader.data));
        };

        /** parse a playlist **/
        private function _parseLevelPlaylist(string : String, url : String, level : int, metrics : HLSLoadMetrics) : void {
            if (string != null && string.length != 0) {
                CONFIG::LOGGING {
                    Log.debug("level " + level + " playlist:\n" + string);
                }
                var frags : Vector.<Fragment> = Manifest.getFragments(string, url, level);
                // set fragment and update sequence number range
                _levels[level].updateFragments(frags);
                _levels[level].targetduration = Manifest.getTargetDuration(string);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.PLAYLIST_DURATION_UPDATED, _levels[level].duration));
            }

            // Check whether the stream is live or not finished yet
            if (Manifest.hasEndlist(string)) {
                _type = HLSTypes.VOD;
                _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_ENDLIST, level));
            } else {
                _type = HLSTypes.LIVE;
                /* in order to determine playlist reload timer,
                    check playback position against playlist duration.
                    if we are near the edge of a live playlist, reload playlist quickly
                    to discover quicker new fragments and avoid buffer starvation.
                */
                var reload_interval : Number = 1000*Math.min((_levels[level].duration - _hls.position)/2,_levels[level].averageduration);
                // avoid spamming the server if we are at the edge ... wait 500ms between 2 reload at least
                var timeout : Number = Math.max(500, _reload_playlists_timer + reload_interval - getTimer());
                CONFIG::LOGGING {
                    Log.debug("Level " + level + " Live Playlist parsing finished: reload in " + timeout.toFixed(0) + " ms");
                }
                _timeoutID = setTimeout(_loadActiveLevelPlaylist, timeout);
            }
            if (!_canStart) {
                _canStart = (_levels[level].fragments.length > 0);
                if (_canStart) {
                    CONFIG::LOGGING {
                        Log.debug("first level filled with at least 1 fragment, notify event");
                    }
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.MANIFEST_LOADED, _levels, _metrics));
                }
            }
            metrics.id  = _levels[level].start_seqnum;
            metrics.id2 = _levels[level].end_seqnum;
            _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_LOADED, metrics));
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
                    _metrics.parsing_end_time = getTimer();
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.MANIFEST_PARSED, _levels));
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_LOADING, 0));
                    CONFIG::LOGGING {
                        Log.debug("1 Level Playlist, load it");
                    }
                    _current_level = 0;
                    _metrics.type = HLSLoaderTypes.LEVEL_MAIN;
                    _parseLevelPlaylist(string, _url, 0,_metrics);
                } else if (string.indexOf(Manifest.LEVEL) > 0) {
                    CONFIG::LOGGING {
                        Log.debug("adaptive playlist:\n" + string);
                    }
                    // adaptative playlist, extract levels from playlist, get them and parse them
                    _levels = Manifest.extractLevels(string, _url);

                    var levelsLength : int = _levels.length;
                    if (levelsLength == 0) {
                        hlsError = new HLSError(HLSError.MANIFEST_PARSING_ERROR, _url, "No level found in Manifest");
                        _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
                    }
                    _metrics.parsing_end_time = getTimer();
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.MANIFEST_PARSED, _levels));
                    // retrieve start level from helper function
                    _current_level = _hls.startlevel;
                    _loadActiveLevelPlaylist();
                    if (string.indexOf(Manifest.ALTERNATE_AUDIO) > 0) {
                        CONFIG::LOGGING {
                            Log.debug("alternate audio level found");
                        }
                        // parse alternate audio tracks
                        _alt_audio_tracks = Manifest.extractAltAudioTracks(string, _url);
                        CONFIG::LOGGING {
                            if (_alt_audio_tracks.length > 0) {
                                Log.debug(_alt_audio_tracks.length + " alternate audio tracks found");
                            }
                        }
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
            _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_LOADING, _current_level));
            _manifest_loading.loadPlaylist(_hls,_levels[_current_level].url, _parseLevelPlaylist, _errorHandler, _current_level, _type, HLSSettings.flushLiveURLCache);
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
    }
}
