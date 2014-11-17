/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
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
        /** audio/video found ? */
        public var audio_found : Boolean;
        public var video_found : Boolean;
        /** tag related stuff */
        public var tags_pts_min_audio : Number;
        public var tags_pts_max_audio : Number;
        public var tags_pts_min_video : Number;
        public var tags_pts_max_video : Number;
        public var tags_audio_found : Boolean;
        public var tags_video_found : Boolean;
        public var tags : Vector.<FLVTag>;
        /* video dimension */
        public var video_width : int;
        public var video_height : int;

        /** Fragment metrics **/
        public function FragmentData() {
            this.pts_start = NaN;
            this.pts_start_computed = NaN;
            this.valid = true;
            this.video_width = 0;
            this.video_height = 0;
        };

        public function get pts_min() : Number {
            if (audio_found) {
                return pts_min_audio;
            } else {
                return pts_min_video;
            }
        }

        public function get pts_max() : Number {
            if (audio_found) {
                return pts_max_audio;
            } else {
                return pts_max_video;
            }
        }

        public function get tag_pts_min() : Number {
            if (audio_found) {
                return tags_pts_min_audio;
            } else {
                return tags_pts_min_video;
            }
        }

        public function get tag_pts_max() : Number {
            if (audio_found) {
                return tags_pts_max_audio;
            } else {
                return tags_pts_max_video;
            }
        }

        public function get tag_pts_start_offset() : Number {
            if (tags_audio_found) {
                return tags_pts_min_audio - pts_min_audio;
            } else {
                return tags_pts_min_video - pts_min_video;
            }
        }

        public function get tag_pts_end_offset() : Number {
            if (tags_audio_found) {
                return tags_pts_max_audio - pts_min_audio;
            } else {
                return tags_pts_max_video - pts_min_video;
            }
        }
    }
}