package org.mangui.hls.playlist {
    public class AltAudioTrack {
        public var group_id : String;
        public var lang : String;
        public var name : String;
        public var autoselect : Boolean;
        public var default_track : Boolean;
        public var url : String;

        /** Create the quality level. **/
        public function AltAudioTrack(alt_group_id : String, alt_lang : String, alt_name : String, alt_autoselect : Boolean, alt_default : Boolean, alt_url : String) {
            group_id = alt_group_id;
            lang = alt_lang;
            name = alt_name;
            autoselect = alt_autoselect;
            default_track = alt_default;
            url = alt_url;
        };

        public function toString() : String {
            return "AltAudioTrack url: " + url + " lang: " + lang + " name: " + name + ' default: ' + default_track;
        };
    }
}
