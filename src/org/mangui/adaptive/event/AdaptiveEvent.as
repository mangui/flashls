/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.adaptive.event {
    import org.mangui.adaptive.model.Level;

    import flash.events.Event;

    /** Event fired when an error prevents playback. **/
    public class AdaptiveEvent extends Event {
        /** Identifier for a manifest loading event, triggered after a call to hls.load(url) **/
        public static const MANIFEST_LOADING : String = "eventManifestLoading";
        /** Identifier for a manifest parsed event,
         * triggered after main manifest has been retrieved and parsed.
         * hls playlist may not be playable yet, in case of adaptive streaming, start level playlist is not downloaded yet at that stage */
        public static const MANIFEST_PARSED : String = "eventManifestParsed";
        /** Identifier for a manifest loaded event, when this event is received, main manifest and start level has been retrieved */
        public static const MANIFEST_LOADED : String = "eventManifestLoaded";
        /** Identifier for a level loading event  **/
        public static const LEVEL_LOADING : String = "eventLevelLoading";
        /** Identifier for a level loaded event  **/
        public static const LEVEL_LOADED : String = "eventLevelLoaded";
        /** Identifier for a level switch event. **/
        public static const LEVEL_SWITCH : String = "eventLevelSwitch";
        /** Identifier for a level ENDLIST event. **/
        public static const LEVEL_ENDLIST : String = "eventLevelEndList";
        /** Identifier for a fragment loading event. **/
        public static const FRAGMENT_LOADING : String = "eventFragmentLoading";
        /** Identifier for a fragment loaded event. **/
        public static const FRAGMENT_LOADED : String = "eventFragmentLoaded";
        /** Identifier for a fragment playing event. **/
        public static const FRAGMENT_PLAYING : String = "eventFragmentPlaying";
        /** Identifier for a audio tracks list change **/
        public static const AUDIO_TRACKS_LIST_CHANGE : String = "audioTracksListChange";
        /** Identifier for a audio track switch **/
        public static const AUDIO_TRACK_SWITCH : String = "audioTrackSwitch";
        /** Identifier for a audio level loading event  **/
        public static const AUDIO_LEVEL_LOADING : String = "eventAudioLevelLoading";
        /** Identifier for a audio level loaded event  **/
        public static const AUDIO_LEVEL_LOADED : String = "eventAudioLevelLoaded";
        /** Identifier for audio/video TAGS loaded event. **/
        public static const TAGS_LOADED : String = "eventTagsLoaded";
        /** Identifier when last fragment of playlist has been loaded **/
        public static const LAST_VOD_FRAGMENT_LOADED : String = "eventLastFragmentLoaded";
        /** Identifier for a playback error event. **/
        public static const ERROR : String = "eventError";
        /** Identifier for a playback media time change event. **/
        public static const MEDIA_TIME : String = "eventMediaTime";
        /** Identifier for a playback state switch event. **/
        public static const PLAYBACK_STATE : String = "hlsPlaybackState";
        /** Identifier for a seek state switch event. **/
        public static const SEEK_STATE : String = "hlsSeekState";
        /** Identifier for a playback complete event. **/
        public static const PLAYBACK_COMPLETE : String = "eventPlayBackComplete";
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
        public var error : AdaptiveError;
        /** Load Metrics. **/
        public var loadMetrics : AdaptiveLoadMetrics;
        /** Play Metrics. **/
        public var playMetrics : AdaptivePlayMetrics;
        /** The time position. **/
        public var mediatime : AdaptiveMediatime;
        /** The new playback state. **/
        public var state : String;
        /** The current audio track **/
        public var audioTrack : int;
        /** a complete ID3 payload from PES, as a hex dump **/
        public var ID3Data : String;

        /** Assign event parameter and dispatch. **/
        public function AdaptiveEvent(type : String, parameter : *=null) {
            switch(type) {
                case AdaptiveEvent.MANIFEST_LOADING:
                case AdaptiveEvent.FRAGMENT_LOADING:
                    url = parameter as String;
                    break;
                case AdaptiveEvent.ERROR:
                    error = parameter as AdaptiveError;
                    break;
                case AdaptiveEvent.TAGS_LOADED:
                case AdaptiveEvent.FRAGMENT_LOADED:
                    loadMetrics = parameter as AdaptiveLoadMetrics;
                    break;
                case AdaptiveEvent.MANIFEST_PARSED:
                case AdaptiveEvent.MANIFEST_LOADED:
                    levels = parameter as Vector.<Level>;
                    break;
                case AdaptiveEvent.MEDIA_TIME:
                    mediatime = parameter as AdaptiveMediatime;
                    break;
                case AdaptiveEvent.PLAYBACK_STATE:
                case AdaptiveEvent.SEEK_STATE:
                    state = parameter as String;
                    break;
                case AdaptiveEvent.LEVEL_LOADING:
                case AdaptiveEvent.LEVEL_LOADED:
                case AdaptiveEvent.LEVEL_SWITCH:
                case AdaptiveEvent.AUDIO_LEVEL_LOADED:
                case AdaptiveEvent.AUDIO_LEVEL_LOADING:
                    level = parameter as int;
                    break;
                case AdaptiveEvent.PLAYLIST_DURATION_UPDATED:
                    duration = parameter as Number;
                    break;
                case AdaptiveEvent.ID3_UPDATED:
                    ID3Data = parameter as String;
                    break;
                case AdaptiveEvent.FRAGMENT_PLAYING:
                    playMetrics = parameter as AdaptivePlayMetrics;
                    break;
            }
            super(type, false, false);
        };
    }
}