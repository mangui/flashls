/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.controller {
    import flash.system.Capabilities;
    import flash.utils.setTimeout;
    
    import org.mangui.hls.HLS;
    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.loader.LevelLoader;
    import org.mangui.hls.model.SubtitlesTrack;
    import org.mangui.hls.playlist.SubtitlesPlaylistTrack;
    import org.mangui.hls.stream.HLSNetStream;
    import org.mangui.hls.stream.StreamBuffer;
    import org.mangui.hls.utils.hls_internal;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
    
    /**
     * Class that handles subtitles tracks, based on alternative audio controller
     * @author    Neil Rackett
     */
    public class SubtitlesTrackController {
        /** Reference to the HLS controller. **/
        private var _hls : HLS;
        /** Reference to the HLS level loader. **/
        private var _levelLoader : LevelLoader;
        /** stream buffer instance **/
        private var _streamBuffer : StreamBuffer;
        /** list of subtitles tracks from Manifest, matching with current level **/
        private var _subtitlesTracksFromManifest : Vector.<SubtitlesTrack>;
        /** merged subtitles tracks list **/
        private var _subtitlesTracks : Vector.<SubtitlesTrack>;
        /** current subtitles track id **/
        private var _subtitlesTrackId : int;
        /** default subtitles track id **/
        private var _defaultTrackId : int;
        /** forced subtitles track id **/
        private var _forcedTrackId : int;
        
        use namespace hls_internal;
        
        public function SubtitlesTrackController(hls : HLS, streamBuffer : StreamBuffer, levelLoader : LevelLoader) {
            _hls = hls;
            _hls.addEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.addEventListener(HLSEvent.LEVEL_LOADED, _levelLoadedHandler);
            
            _streamBuffer = streamBuffer;
            _levelLoader = levelLoader;
            
            _subtitlesTracks = new Vector.<SubtitlesTrack>;
            _subtitlesTrackId = -1;
            _defaultTrackId = -1;
            _forcedTrackId = -1;
        }

        public function dispose() : void {
            _hls.removeEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.removeEventListener(HLSEvent.LEVEL_LOADED, _levelLoadedHandler);
        }

        public function set subtitlesTrack(num : int) : void {
            if (_subtitlesTrackId != num) {
                _subtitlesTrackId = num;
                var ev : HLSEvent = new HLSEvent(HLSEvent.SUBTITLES_TRACK_SWITCH);
                ev.subtitlesTrack = _subtitlesTrackId;
                _hls.dispatchEvent(ev);
                CONFIG::LOGGING {
                    Log.info('Setting subtitles track to ' + num);
                }
            }
        }

        public function get subtitlesTrack() : int {
            return _subtitlesTrackId;
        }

        public function get subtitlesTracks() : Vector.<SubtitlesTrack> {
            return _subtitlesTracks;
        }

        /**
         * Reset subtitles tracks
         */
        private function _manifestLoadedHandler(event : HLSEvent) : void {
            _defaultTrackId = -1;
            _forcedTrackId = -1;
            _subtitlesTrackId = -1;
            _subtitlesTracksFromManifest = new Vector.<SubtitlesTrack>();
            _subtitlesTracks = new Vector.<SubtitlesTrack>();
            _updateSubtitlesTrackForLevel(_hls.loadLevel);
        };

        /** Store the manifest data. **/
        private function _levelLoadedHandler(event : HLSEvent) : void {
            var level : int = event.loadMetrics.level;
            if (level == _hls.loadLevel) {
                _updateSubtitlesTrackForLevel(level);
            }
        };

        private function _updateSubtitlesTrackForLevel(level : uint) : void {
            
            var subtitlesTrackList : Vector.<SubtitlesTrack> = new Vector.<SubtitlesTrack>();
            var streamId : String = _hls.levels[level].subtitles_stream_id;
            var autoSelectId : int = -1;
            
            // check if subtitles stream id is set, and subtitles tracks available
            if (streamId && _levelLoader.subtitlesPlaylistTracks) {
                // try to find subtitles streams matching with this ID
                for (var idx : int = 0; idx < _levelLoader.subtitlesPlaylistTracks.length; idx++) {
                    var playlistTrack : SubtitlesPlaylistTrack = _levelLoader.subtitlesPlaylistTracks[idx];
                    
                    if (playlistTrack.group_id == streamId) {
                        var isDefault : Boolean = playlistTrack.default_track;
                        var isForced : Boolean = playlistTrack.forced;
                        var autoSelect : Boolean = playlistTrack.autoselect;
                        var track:SubtitlesTrack = new SubtitlesTrack(playlistTrack.name, idx, SubtitlesTrack.FROM_PLAYLIST, playlistTrack.lang, isDefault, isForced, autoSelect);
                        
                        CONFIG::LOGGING {
                            Log.debug("subtitles track[" + subtitlesTrackList.length + "]:" + (isDefault ? "default:" : "alternate:") + playlistTrack.name);
                        }
                        
                        subtitlesTrackList.push(track);
                        
                        if (isDefault) _defaultTrackId = idx;
                        if (isForced) _forcedTrackId = idx;
                        
                        // Technical Note TN2288: https://developer.apple.com/library/ios/technotes/tn2288/_index.html
                        if (autoSelect 
                            && playlistTrack.lang.toLowerCase().substr(0,2) == Capabilities.language) {
                            autoSelectId = idx;
                        }
                    }
                }
            }

            // check if subtitles tracks matching with current level have changed since last time
            var subtitlesTrackChanged : Boolean = false;
            if (_subtitlesTracksFromManifest.length != subtitlesTrackList.length) {
                subtitlesTrackChanged = true;
            } else {
                for (idx = 0; idx < _subtitlesTracksFromManifest.length; ++idx) {
                    if (_subtitlesTracksFromManifest[idx].id != subtitlesTrackList[idx].id) {
                        subtitlesTrackChanged = true;
                    }
                }
            }

            // update subtitles list
            if (subtitlesTrackChanged) {
                _subtitlesTracksFromManifest = subtitlesTrackList;
                _subtitlesTracksMerge();
            }

            // PRIORITY #1: Automatically select forced subtitles track
            if (HLSSettings.subtitlesAutoSelectForced && _forcedTrackId != -1){
                subtitlesTrack = _forcedTrackId;
                return;
            }

            // PRIORITY #2: Automatically select auto-select subtitles track that matches current locale
            if (HLSSettings.subtitlesAutoSelect && autoSelectId != -1) {
                subtitlesTrack = autoSelectId;
                return;
            }

            // PRIORITY #3: Automatically select default subtitles track
            if (HLSSettings.subtitlesAutoSelectDefault && _defaultTrackId != -1){
                subtitlesTrack = _defaultTrackId;
                return;
            }
            
            // Otherwise leave subtitles off/unselected
        }

        /**
         * Strictly speaking this isn't really needed for subtitles, but I've 
         * left it in place in case we want to merge in CEA-608 captions or
         * add external subtitles support in the future
         */
        private function _subtitlesTracksMerge() : void {
            _subtitlesTracks = _subtitlesTracksFromManifest.slice();
            setTimeout(dispatchMetaData, 0);
        }

        /**
         * Announce availability of subtitles tracks using TX3G metadata
         */
        protected function dispatchMetaData():void {
            // Appending an FLVTag here breaks the stream, so we use script to achieve the same outcome
            var stream:HLSNetStream = _hls.stream as HLSNetStream;
			stream.dispatchClientEvent("onMetaData", tx3gMetaData);
        }
        
        /**
         * Minimal TX3G timed text metadata used to announce available 
         * subtitles tracks via an onMetaData NetStream event
         */
        private function get tx3gMetaData():Object {
            var trackinfo : Array = [];
            for each (var track:SubtitlesTrack in subtitlesTracks) {
                trackinfo.push({
                    language: track.language,
                    title: track.title,
                    sampledescription: [{
                        sampletype: 'tx3g'
                    }]
                });
            }
            return {trackinfo:trackinfo};
        }

        /** Normally triggered by user selection, it should return the subtitles track to be parsed */
        public function subtitlesTrackSelectionHandler(subtitlesTrackList : Vector.<SubtitlesTrack>) : SubtitlesTrack {
            var subtitlesTrackChanged : Boolean = false;
            subtitlesTrackList = subtitlesTrackList.sort(function(a : SubtitlesTrack, b : SubtitlesTrack) : int {
                return a.id - b.id;
            });
            /* if subtitles track not defined, or subtitles from external source (playlist) return null (not selected) */
            if (_subtitlesTrackId == -1 || _subtitlesTrackId >= _subtitlesTracks.length || _subtitlesTracks[_subtitlesTrackId].source == SubtitlesTrack.FROM_PLAYLIST) {
                return null;
            } else {
                return _subtitlesTracks[_subtitlesTrackId];
            }
        }

        public function get defaultSubtitlesTrack():int {
            return _defaultTrackId;
        }

        public function get hasForcedSubtitles():Boolean {
            return _forcedTrackId != -1;
        }

        public function get forcedSubtitlesTrack():int {
            return _forcedTrackId;
        }
    }
}
