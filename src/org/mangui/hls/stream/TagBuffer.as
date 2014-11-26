/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.stream {
    import org.mangui.hls.HLS;
    import org.mangui.hls.flv.FLVTag;

    /*
     * intermediate FLV Tag Buffer
     *  input : FLV tags retrieved from different fragment loaders (video/alt-audio...)
     *  output : provide muxed FLV tags to HLSNetStream
     */
    public class TagBuffer {
        private var _hls : HLS;

        public function TagBuffer(hls : HLS) {
            _hls = hls;
        }

        public function appendTags(tags : Vector.<FLVTag>, min_pts : Number, max_pts : Number, continuity : int, start_position : Number) : void {
            (_hls.stream as HLSNetStream).appendTags(tags, min_pts, max_pts, continuity, start_position);
        }

        public function dispose() : void {
            _hls = null;
        }
    }
}
