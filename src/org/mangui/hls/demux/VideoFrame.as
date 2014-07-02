package org.mangui.hls.demux {
    /** Video Frame **/
    public class VideoFrame {
        public var header : int;
        public var start : int;
        public var length : int;
        public var type : int;

        public function VideoFrame(header : int, length : int, start : int, type : int) {
            this.header = header;
            this.start = start;
            this.length = length;
            this.type = type;
        }
    }
}