package org.mangui.hls.demux {
    /** Audio Frame **/
    public class AudioFrame {
        public var start : int;
        public var length : int;
        public var expected_length : int;
        public var rate : int;

        public function AudioFrame(start : int, length : int, expected_length : int, rate : int) {
            this.start = start;
            this.length = length;
            this.expected_length = expected_length;
            this.rate = rate;
        }
    }
}