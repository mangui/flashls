/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.event {
    import org.mangui.hls.model.Level;

    import flash.events.Event;

    /** Event fired when an error prevents playback. **/
    public class HLSEvent extends Event {
        /** Identifier for a manifest loading event, triggered after a call to hls.load(url) **/
        public static const MANIFEST_LOADING : String = "hlsEventManifestLoading";
        /** Identifier for a manifest parsed event,
         * triggered after main manifest has been retrieved and parsed.
         * hls playlist may not be playable yet, in case of adaptive streaming, start level playlist is not downloaded yet at that stage */
        public static const MANIFEST_PARSED : String = "hlsEventManifestParsed";
        /** Identifier for a manifest loaded event, when this event is received, main manifest and start level has been retrieved */
        public static const MANIFEST_LOADED : String = "hlsEventManifestLoaded";
        /** Identifier for a level loading event  **/
        public static const LEVEL_LOADING : String = "hlsEventLevelLoading";
        /** Identifier for a level loaded event  **/
        public static const LEVEL_LOADED : String = "hlsEventLevelLoaded";
        /** Identifier for a level switch event. **/
        public static const LEVEL_SWITCH : String = "hlsEventLevelSwitch";
        /** Identifier for a level ENDLIST event. **/
        public static const LEVEL_ENDLIST : String = "hlsEventLevelEndList";
        /** Identifier for a fragment loading event. **/
        public static const FRAGMENT_LOADING : String = "hlsEventFragmentLoading";
        /** Identifier for a fragment loaded event. **/
        public static const FRAGMENT_LOADED : String = "hlsEventFragmentLoaded";
        /** Identifier for a fragment playing event. **/
        public static const FRAGMENT_PLAYING : String = "hlsEventFragmentPlaying";
        /** Identifier for a audio tracks list change **/
        public static const AUDIO_TRACKS_LIST_CHANGE : String = "audioTracksListChange";
        /** Identifier for a audio track switch **/
        public static const AUDIO_TRACK_SWITCH : String = "audioTrackSwitch";
        /** Identifier for a audio level loading event  **/
        public static const AUDIO_LEVEL_LOADING : String = "hlsEventAudioLevelLoading";
        /** Identifier for a audio level loaded event  **/
        public static const AUDIO_LEVEL_LOADED : String = "hlsEventAudioLevelLoaded";
        /** Identifier for audio/video TAGS loaded event. **/
        public static const TAGS_LOADED : String = "hlsEventTagsLoaded";
        /** Identifier when last fragment of playlist has been loaded **/
        public static const LAST_VOD_FRAGMENT_LOADED : String = "hlsEventLastFragmentLoaded";
        /** Identifier for a playback error event. **/
        public static const ERROR : String = "hlsEventError";
        /** Identifier for a playback media time change event. **/
        public static const MEDIA_TIME : String = "hlsEventMediaTime";
        /** Identifier for a playback state switch event. **/
        public static const PLAYBACK_STATE : String = "hlsPlaybackState";
        /** Identifier for a seek state switch event. **/
        public static const SEEK_STATE : String = "hlsSeekState";
        /** Identifier for a playback complete event. **/
        public static const PLAYBACK_COMPLETE : String = "hlsEventPlayBackComplete";
        /** Identifier for a Playlist Duration updated event **/
        public static const PLAYLIST_DURATION_UPDATED : String = "hlsPlayListDurationUpdated";
        /** Identifier for a ID3 updated event **/
        public static const ID3_UPDATED : String = "hlsID3Updated";
        /** The current url **/
        public var url : String;
        /** The current quality level. **/
        public var level : int;
        /** The current playlist duration. **/
        public var duration : Number;
        /** The list with quality levels. **/
        public var levels : Vector.<Level>;
        /** The error message. **/
        public var error : HLSError;
        /** Load Metrics. **/
        public var loadMetrics : HLSLoadMetrics;
        /** Play Metrics. **/
        public var playMetrics : HLSPlayMetrics;
        /** The time position. **/
        public var mediatime : HLSMediatime;
        /** The new playback state. **/
        public var state : String;
        /** The current audio track **/
        public var audioTrack : int;
        /** a complete ID3 payload from PES, as a hex dump **/
        public var ID3Data : String;

        /** Assign event parameter and dispatch. **/
        public function HLSEvent(type : String, parameter : *=null, parameter2 : *=null) {
            switch(type) {
                case HLSEvent.MANIFEST_LOADING:
                case HLSEvent.FRAGMENT_LOADING:
                    url = parameter as String;
                    break;
                case HLSEvent.ERROR:
                    error = parameter as HLSError;
                    break;
                case HLSEvent.TAGS_LOADED:
                case HLSEvent.FRAGMENT_LOADED:
                case HLSEvent.LEVEL_LOADED:
                case HLSEvent.AUDIO_LEVEL_LOADED:
                    loadMetrics = parameter as HLSLoadMetrics;
                    break;
                case HLSEvent.MANIFEST_PARSED:
                case HLSEvent.MANIFEST_LOADED:
                    levels = parameter as Vector.<Level>;
                    if(parameter2) {
                        loadMetrics = parameter2 as HLSLoadMetrics;
                    }
                    break;
                case HLSEvent.MEDIA_TIME:
                    mediatime = parameter as HLSMediatime;
                    break;
                case HLSEvent.PLAYBACK_STATE:
                case HLSEvent.SEEK_STATE:
                    state = parameter as String;
                    break;
                case HLSEvent.LEVEL_LOADING:
                case HLSEvent.LEVEL_SWITCH:
                case HLSEvent.AUDIO_LEVEL_LOADING:
                    level = parameter as int;
                    break;
                case HLSEvent.PLAYLIST_DURATION_UPDATED:
                    duration = parameter as Number;
                    break;
                case HLSEvent.ID3_UPDATED:
                    ID3Data = parameter as String;
                    break;
                case HLSEvent.FRAGMENT_PLAYING:
                    playMetrics = parameter as HLSPlayMetrics;
                    break;
            }
            super(type, false, false);
        };
    }
}