package org.mangui.hls.event {
    /** playback metrics, notified when playback of a given fragment starts **/
    public class HLSPlayMetrics {
        public var level : int;
        public var seqnum : int;
        public var continuity_counter : int;
        public var audio_only : Boolean;
        public var video_width : int;
        public var video_height : int;
        public var tag_list : Array;

        public function HLSPlayMetrics(level : int, seqnum : int, cc : int, audio_only : Boolean, video_width : int, video_height : int, tag_list : Array) {
            this.level = level;
            this.seqnum = seqnum;
            this.continuity_counter = cc;
            this.audio_only = audio_only;
            this.video_width = video_width;
            this.video_height = video_height;
            this.tag_list = tag_list;
        }
    }
}