/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.hls.controller {
    import org.mangui.hls.playlist.AltAudioTrack;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.model.AudioTrack;
    import org.mangui.hls.HLS;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }

    /*
     * class that handle audio tracks, consolidating tracks retrieved from Manifest and from Demux
     */
    public class AudioTrackController {
        /** Reference to the HLS controller. **/
        private var _hls : HLS;
        /** list of audio tracks from demuxed fragments **/
        private var _audioTracksfromDemux : Vector.<AudioTrack>;
        /** list of audio tracks from Manifest, matching with current level **/
        private var _audioTracksfromManifest : Vector.<AudioTrack>;
        /** merged audio tracks list **/
        private var _audioTracks : Vector.<AudioTrack>;
        /** current audio track id **/
        private var _audioTrackId : int;

        public function AudioTrackController(hls : HLS) {
            _hls = hls;
            _hls.addEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.addEventListener(HLSEvent.LEVEL_LOADED, _levelLoadedHandler);
        }

        public function dispose() : void {
            _hls.removeEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.removeEventListener(HLSEvent.LEVEL_LOADED, _levelLoadedHandler);
        }

        public function set audioTrack(num : int) : void {
            if (_audioTrackId != num) {
                _audioTrackId = num;
                var ev : HLSEvent = new HLSEvent(HLSEvent.AUDIO_TRACK_CHANGE);
                ev.audioTrack = _audioTrackId;
                _hls.dispatchEvent(ev);
                CONFIG::LOGGING {
                    Log.info('Setting audio track to ' + num);
                }
            }
        }

        public function get audioTrack() : int {
            return _audioTrackId;
        }

        public function get audioTracks() : Vector.<AudioTrack> {
            return _audioTracks;
        }

        private function _manifestLoadedHandler(event : HLSEvent) : void {
            // reset audio tracks
            _audioTrackId = -1;
            _audioTracksfromDemux = new Vector.<AudioTrack>();
            _audioTracksfromManifest = new Vector.<AudioTrack>();
            _audioTracksMerge();
        };

        /** Store the manifest data. **/
        private function _levelLoadedHandler(event : HLSEvent) : void {
            if (event.level == _hls.level) {
                var audioTrackList : Vector.<AudioTrack> = new Vector.<AudioTrack>();
                var stream_id : String = _hls.levels[ _hls.level].audio_stream_id;
                // check if audio stream id is set, and alternate audio tracks available
                if (stream_id && _hls.altAudioTracks) {
                    // try to find alternate audio streams matching with this ID
                    for (var idx : int = 0; idx < _hls.altAudioTracks.length; idx++) {
                        var altAudioTrack : AltAudioTrack = _hls.altAudioTracks[idx];
                        if (altAudioTrack.group_id == stream_id) {
                            var isDefault : Boolean = (altAudioTrack.default_track == true || altAudioTrack.autoselect == true);
                            CONFIG::LOGGING {
                                Log.debug(" audio track[" + audioTrackList.length + "]:" + (isDefault ? "default:" : "alternate:") + altAudioTrack.name);
                            }
                            audioTrackList.push(new AudioTrack(altAudioTrack.name, AudioTrack.FROM_PLAYLIST, idx, isDefault, true));
                        }
                    }
                }
                // check if audio tracks matching with current level have changed since last time
                var audio_track_changed : Boolean = false;
                if (_audioTracksfromManifest.length != audioTrackList.length) {
                    audio_track_changed = true;
                } else {
                    for (idx = 0; idx < _audioTracksfromManifest.length; ++idx) {
                        if (_audioTracksfromManifest[idx].id != audioTrackList[idx].id) {
                            audio_track_changed = true;
                        }
                    }
                }
                // update audio list
                if (audio_track_changed) {
                    _audioTracksfromManifest = audioTrackList;
                    _audioTracksMerge();
                }
            }
        };

        // merge audio track info from demux and from manifest into a unified list that will be exposed to upper layer
        private function _audioTracksMerge() : void {
            var i : int;
            var default_demux : int = -1;
            var default_manifest : int = -1;
            var default_found : Boolean = false;
            var default_track_title : String;
            var audioTrack_ : AudioTrack;
            _audioTracks = new Vector.<AudioTrack>();

            // first look for default audio track.
            for (i = 0; i < _audioTracksfromManifest.length; i++) {
                if (_audioTracksfromManifest[i].isDefault) {
                    default_manifest = i;
                    break;
                }
            }
            for (i = 0; i < _audioTracksfromDemux.length; i++) {
                if (_audioTracksfromDemux[i].isDefault) {
                    default_demux = i;
                    break;
                }
            }
            /* default audio track from manifest should take precedence */
            if (default_manifest != -1) {
                audioTrack_ = _audioTracksfromManifest[default_manifest];
                // if URL set, default audio track is not embedded into MPEG2-TS
                if (_hls.altAudioTracks[audioTrack_.id].url || default_demux == -1) {
                    CONFIG::LOGGING {
                        Log.debug("default audio track found in Manifest");
                    }
                    default_found = true;
                    _audioTracks.push(audioTrack_);
                } else {
                    // empty URL, default audio track is embedded into MPEG2-TS. retrieve track title from manifest and override demux title
                    default_track_title = audioTrack_.title;
                    if (default_demux != -1) {
                        CONFIG::LOGGING {
                            Log.debug("default audio track signaled in Manifest, will be retrieved from MPEG2-TS");
                        }
                        audioTrack_ = _audioTracksfromDemux[default_demux];
                        audioTrack_.title = default_track_title;
                        default_found = true;
                        _audioTracks.push(audioTrack_);
                    }
                }
            } else if (default_demux != -1 ) {
                audioTrack_ = _audioTracksfromDemux[default_demux];
                default_found = true;
                _audioTracks.push(audioTrack_);
            }
            // then append other audio tracks, start from manifest list, then continue with demux list
            for (i = 0; i < _audioTracksfromManifest.length; i++) {
                if (i != default_manifest) {
                    CONFIG::LOGGING {
                        Log.debug("alternate audio track found in Manifest");
                    }
                    audioTrack_ = _audioTracksfromManifest[i];
                    _audioTracks.push(audioTrack_);
                }
            }

            for (i = 0; i < _audioTracksfromDemux.length; i++) {
                if (i != default_demux) {
                    CONFIG::LOGGING {
                        Log.debug("alternate audio track retrieved from demux");
                    }
                    audioTrack_ = _audioTracksfromDemux[i];
                    _audioTracks.push(audioTrack_);
                }
            }
            // notify audio track list update
            _hls.dispatchEvent(new HLSEvent(HLSEvent.AUDIO_TRACKS_LIST_CHANGE));

            // switch track id to default audio track, if found
            if (default_found == true && _audioTrackId == -1) {
                audioTrack = 0;
            }
        }

        /** triggered by demux, it should return the audio track to be parsed */
        public function audioTrackSelectionHandler(audioTrackList : Vector.<AudioTrack>) : AudioTrack {
            var audio_track_changed : Boolean = false;
            audioTrackList = audioTrackList.sort(function(a : AudioTrack, b : AudioTrack) : int {
                return a.id - b.id;
            });
            if (_audioTracksfromDemux.length != audioTrackList.length) {
                audio_track_changed = true;
            } else {
                for (var idx : int = 0; idx < _audioTracksfromDemux.length; ++idx) {
                    if (_audioTracksfromDemux[idx].id != audioTrackList[idx].id) {
                        audio_track_changed = true;
                    }
                }
            }
            // update audio list if changed
            if (audio_track_changed) {
                _audioTracksfromDemux = audioTrackList;
                _audioTracksMerge();
            }

            /* if audio track not defined, or audio from external source (playlist) 
            return null (demux audio not selected) */
            if (_audioTrackId == -1 || _audioTracks[_audioTrackId].source == AudioTrack.FROM_PLAYLIST) {
                return null;
            } else {
                // source is demux,return selected audio track
                return _audioTracks[_audioTrackId];
            }
        }
    }
}
