/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.model {
    /** Fragment Metrics. **/
    public class FragmentMetrics {
        /** fragment loading request/start/end time **/
        public var loading_request_time : Number;
        public var loading_begin_time : Number;
        public var loading_end_time : Number;
        /** fragment decryption begin/end time **/
        public var decryption_begin_time : Number;
        public var decryption_end_time : Number;
        /** fragment begin/end time */
        public var parsing_begin_time : Number;
        public var parsing_end_time : Number;
        /** fragment size **/
        public var size : int;

        /** Fragment metrics **/
        public function FragmentMetrics() {
        };

        public function get processing_duration() : Number {
            return (parsing_end_time - loading_request_time);
        }

        public function get rtt_duration() : Number {
            return (loading_begin_time - loading_request_time);
        }

        public function get bandwidth() : int {
            return(Math.round(size * 8000 / (parsing_end_time - loading_request_time)));
        }
    }
}