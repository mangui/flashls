package org.mangui.hls.event {
    /** playback metrics, notified when playback of a given fragment starts **/
    public class HLSPlayMetrics {
        public var level : int;
        private var seqnum : int;
        private var continuity_counter : int;

        public function HLSPlayMetrics(level : int, seqnum : int, cc : int) {
            this.level = level;
            this.seqnum = seqnum;
			this.continuity_counter = cc;

        }


    }
}