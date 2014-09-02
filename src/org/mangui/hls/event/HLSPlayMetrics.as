package org.mangui.hls.event {
    /** playback metrics, notified when playback of a given fragment starts **/
    public class HLSPlayMetrics {
        public var level : int;
        public var seqnum : int;
        public var continuity_counter : int;
        public var custom_tags : Vector.<String>;

        public function HLSPlayMetrics(level : int, seqnum : int, cc : int, custom_tags : Vector.<String>) {
            this.level = level;
            this.seqnum = seqnum;
            this.continuity_counter = cc;
            this.custom_tags = custom_tags;
        }
    }
}