package org.mangui.hls.model {
    /** Fragment Metrics. **/
    public class FragmentMetrics {
        /** Start PTS of this chunk. **/
        public var pts_start : Number;
        /** computed Start PTS of this chunk. **/
        public var pts_start_computed : Number;
        /** valid fragment **/
        public var valid : Boolean;

        /** Fragment metrics **/
        public function FragmentMetrics() {
            this.pts_start = Number.NEGATIVE_INFINITY;
            this.pts_start_computed = Number.NEGATIVE_INFINITY;
            this.valid = true;
        };
    }
}