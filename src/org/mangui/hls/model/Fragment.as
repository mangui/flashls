package org.mangui.hls.model {
    import flash.utils.ByteArray;

    /** HLS streaming chunk. **/
    public class Fragment {
        /** Duration of this chunk. **/
        public var duration : Number;
        /** Start time of this chunk. **/
        public var start_time : Number;
        /** Start PTS of this chunk. **/
        public var start_pts : Number;
        /** computed Start PTS of this chunk. **/
        public var start_pts_computed : Number;
        /** sequence number of this chunk. **/
        public var seqnum : int;
        /** URL to this chunk. **/
        public var url : String;
        /** continuity index of this chunk. **/
        public var continuity : int;
        /** program date of this chunk. **/
        public var program_date : Number;
        /** URL of the key used to decrypt content **/
        public var decrypt_url : String;
        /** Initialization Vector to decrypt content **/
        public var decrypt_iv : ByteArray;
        /** byte range start offset **/
        public var byterange_start_offset : int;
        /** byte range offset **/
        public var byterange_end_offset : int;
        /** valid fragment **/
        public var valid : Boolean;

        /** Create the fragment. **/
        public function Fragment(url : String, duration : Number, seqnum : int, start_time : Number, continuity : int, program_date : Number, decrypt_url : String, decrypt_iv : ByteArray, byterange_start_offset : int, byterange_end_offset : int) {
            this.duration = duration;
            this.url = url;
            this.seqnum = seqnum;
            this.start_time = start_time;
            this.continuity = continuity;
            this.program_date = program_date;
            this.decrypt_url = decrypt_url;
            this.decrypt_iv = decrypt_iv;
            this.byterange_start_offset = byterange_start_offset;
            this.byterange_end_offset = byterange_end_offset;
            this.start_pts = Number.NEGATIVE_INFINITY;
            this.start_pts_computed = Number.NEGATIVE_INFINITY;
            this.valid = true;
            // CONFIG::LOGGING {
            // Log.info("Frag["+seqnum+"]:duration/start_time,cc="+duration+","+start_time+","+continuity);
            // }
        };

         public function toString():String
	{
	    return "Fragment (seqnum: " + seqnum + ", start_time:" + start_time + ", start_pts_computed:" + start_pts_computed + ", duration:" + duration + ")";
         }        
    }
}