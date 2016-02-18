/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.hls.playlist {
    public class SubtitlesPlaylistTrack {
        public var group_id : String;
        public var lang : String;
        public var name : String;
        public var autoselect : Boolean;
        public var default_track : Boolean;
        public var forced : Boolean;
        public var url : String;
        public var id:Object;
        
        /** Create the quality level. **/
        public function SubtitlesPlaylistTrack(alt_group_id : String, alt_lang : String, alt_name : String, alt_autoselect : Boolean, alt_default : Boolean, alt_forced : Boolean, alt_url : String) {
            group_id = alt_group_id;
            lang = alt_lang;
            name = alt_name;
            autoselect = alt_autoselect;
            default_track = alt_default;
            forced = alt_forced;
            url = alt_url;
        };

        public function toString() : String {
            return "SubtitlesTrack url: " + url + " group_id: " + group_id + " lang: " + lang + " name: " + name + ' default: ' + default_track + ' forced: ' + forced ;
        };
    }
}
