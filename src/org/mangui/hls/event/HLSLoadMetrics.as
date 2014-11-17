/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.hls.event {
    /** Fragment Loading metrics **/
    public class HLSLoadMetrics {
        private var _level : int;
        private var _bandwidth : Number;
        private var _frag_duration : Number;
        private var _frag_processing_time : Number;

        public function HLSLoadMetrics(level : int, bandwidth : Number, frag_duration : Number, frag_processing_time : Number) {
            _level = level;
            _bandwidth = bandwidth;
            _frag_duration = frag_duration;
            _frag_processing_time = frag_processing_time;
        }

        public function get level() : int {
            return _level;
        }

        public function get bandwidth() : Number {
            return _bandwidth;
        }

        public function get frag_duration() : Number {
            return _frag_duration;
        }

        public function get frag_processing_time() : Number {
            return _frag_processing_time;
        }
    }
}