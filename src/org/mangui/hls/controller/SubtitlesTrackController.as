/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.controller {
    import flash.system.Capabilities;
    
    import org.mangui.hls.HLS;
    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.model.SubtitlesTrack;
    import org.mangui.hls.playlist.SubtitlesPlaylistTrack;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
	
    /*
     * Class that handles subtitles tracks, based on alternative audio controller
	 * @author	Neil Rackett
     */
    public class SubtitlesTrackController {
        /** Reference to the HLS controller. **/
        private var _hls : HLS;
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

        public function SubtitlesTrackController(hls : HLS) {
            _hls = hls;
            _hls.addEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.addEventListener(HLSEvent.LEVEL_LOADED, _levelLoadedHandler);
			
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

        private function _manifestLoadedHandler(event : HLSEvent) : void {
			
            // reset subtitles tracks
			_defaultTrackId = -1;
			_forcedTrackId = -1;
            _subtitlesTrackId = -1;
            _subtitlesTracksFromManifest = new Vector.<SubtitlesTrack>();
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
            if (streamId && _hls.subtitlesPlaylistTracks) {
                // try to find subtitles streams matching with this ID
                for (var idx : int = 0; idx < _hls.subtitlesPlaylistTracks.length; idx++) {
                    var playlistTrack : SubtitlesPlaylistTrack = _hls.subtitlesPlaylistTracks[idx];
					
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
			if (HLSSettings.autoSelectForcedSubtitles && _forcedTrackId != -1){
				subtitlesTrack = _forcedTrackId;
				return;
			}
			
			// PRIORITY #2: Automatically select default subtitles track
			if (HLSSettings.autoSelectDefaultSubtitles && _defaultTrackId != -1){
				subtitlesTrack = _defaultTrackId;
				return;
			}
			
			// PRIORITY #3: Automatically select auto-select subtitles track that matches current locale
			if (HLSSettings.autoSelectSubtitles && autoSelectId != -1) {
				subtitlesTrack = autoSelectId;
			}
			
			// Otherwise leave subtitles off/unselected
        }
		
		private function _subtitlesTracksMerge() : void {
			_subtitlesTracks = _subtitlesTracksFromManifest.slice();
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
