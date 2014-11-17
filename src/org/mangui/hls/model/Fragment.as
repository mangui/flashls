/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.hls.model {
    import flash.utils.ByteArray;

    /** Fragment model **/
    public class Fragment {
        /** Duration of this chunk. **/
        public var duration : Number;
        /** Start time of this chunk. **/
        public var start_time : Number;
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
        /** data **/
        public var data : FragmentData;
        /** metrics **/
        public var metrics : FragmentMetrics;
        /** custom tags **/
        public var tag_list : Vector.<String>;

        /** Create the fragment. **/
        public function Fragment(url : String, duration : Number, seqnum : int, start_time : Number, continuity : int, program_date : Number, decrypt_url : String, decrypt_iv : ByteArray, byterange_start_offset : int, byterange_end_offset : int , tag_list : Vector.<String>) {
            this.url = url;
            this.duration = duration;
            this.seqnum = seqnum;
            this.start_time = start_time;
            this.continuity = continuity;
            this.program_date = program_date;
            this.decrypt_url = decrypt_url;
            this.decrypt_iv = decrypt_iv;
            this.byterange_start_offset = byterange_start_offset;
            this.byterange_end_offset = byterange_end_offset;
            this.tag_list = tag_list;
            data = new FragmentData();
            metrics = new FragmentMetrics();
            // CONFIG::LOGGING {
            // Log.info("Frag["+seqnum+"]:duration/start_time,cc="+duration+","+start_time+","+continuity);
            // }
        };

         public function toString():String
	{
	    return "Fragment (seqnum: " + seqnum + ", start_time:" + start_time + ", duration:" + duration + ")";
         }        
    }
}