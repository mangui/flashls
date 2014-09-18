package org.mangui.hls.model {
    /** Audio Track identifier **/
    public class AudioTrack {
        public static const FROM_DEMUX : int = 0;
        public static const FROM_PLAYLIST : int = 1;
        public var title : String;
        public var id : int;
        public var source : int;
        public var isDefault : Boolean;

        public function AudioTrack(title : String, source : int, id : int, isDefault : Boolean) {
            this.title = title;
            this.source = source;
            this.id = id;
            this.isDefault = isDefault;
        }

        public function toString() : String {
            return "AudioTrack ID: " + id + " Title: " + title + " Source: " + source + " Default: " + isDefault;
        }
    }
}