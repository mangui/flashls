package org.mangui.hls.model {
    import org.mangui.hls.utils.AES;
    import org.mangui.hls.flv.FLVTag;
    import flash.utils.ByteArray;
    /** Fragment Data. **/
    public class FragmentData {
        /** valid fragment **/
        public var valid : Boolean;
        /** fragment byte array **/
        public var bytes : ByteArray;
        /** bytes Loaded **/
        public var bytesLoaded : int;
        /** AES decryption instance **/
        public var decryptAES : AES;        
        /** Start PTS of this chunk. **/
        public var pts_start : Number;
        /** computed Start PTS of this chunk. **/
        public var pts_start_computed : Number;
        /** min/max audio/video PTS of this chunk. **/
        public var pts_min_audio : Number;
        public var pts_max_audio : Number;
        public var pts_min_video : Number;
        public var pts_max_video : Number;
        /** audio/video expected ? */
        public var audio_expected : Boolean;
        public var video_expected : Boolean;
        /** audio/video found ? */
        public var audio_found : Boolean;
        public var video_found : Boolean;
        /** tag related stuff */
        public var tags_pts_min_audio : Number;
        public var tags_pts_max_audio : Number;
        public var tags_pts_min_video : Number;
        public var tags_pts_max_video : Number;
        public var tags : Vector.<FLVTag>;

        /** Fragment metrics **/
        public function FragmentData() {
            this.pts_start = NaN;
            this.pts_start_computed = NaN;
            this.valid = true;
        };
    }
}