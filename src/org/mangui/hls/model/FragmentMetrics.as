package org.mangui.hls.model {
    /** Fragment Metrics. **/
    public class FragmentMetrics {
        /** valid fragment **/
        public var valid : Boolean;
        /** Start PTS of this chunk. **/
        public var pts_start : Number;
        /** computed Start PTS of this chunk. **/
        public var pts_start_computed : Number;
        /** min/max audio/video PTS of this chunk. **/
        public var pts_min_audio : Number;
        public var pts_max_audio : Number;
        public var pts_min_video : Number;
        public var pts_max_video : Number;
        /** fragment loading start time **/
        public var loading_start_time : Number;
        /** fragment loading RTT */
        public var loading_return_trip_time : Number;
        /** fragment decrypting start time **/
        public var decrypting_start_time : Number;
        /** audio/video expected ? */
        public var audio_expected : Boolean;
        public var video_expected : Boolean;
        /** audio/video found ? */
        public var audio_found : Boolean;
        public var video_found : Boolean;

        /** Fragment metrics **/
        public function FragmentMetrics() {
            this.pts_start = NaN;
            this.pts_start_computed = NaN;
            this.valid = true;
        };
    }
}