package org.mangui.hls.model {
    /** Fragment Metrics. **/
    public class FragmentMetrics {
        /** Start PTS of this chunk. **/
        public var pts_start : Number;
        /** computed Start PTS of this chunk. **/
        public var pts_start_computed : Number;
        /** fragment loading start time **/
        public var loading_start_time : Number;
        /** fragment decrypting start time **/
        public var decrypting_start_time : Number;
        /** valid fragment **/
        public var valid : Boolean;

        /** Fragment metrics **/
        public function FragmentMetrics() {
            this.pts_start = NaN;
            this.pts_start_computed = NaN;
            this.valid = true;
        };
    }
}