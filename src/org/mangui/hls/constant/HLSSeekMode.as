package org.mangui.hls.constant {
    /** HLS Seek mode configuration **/
    public class HLSSeekMode {
        /** seek on segment boundary **/
        public static const SEGMENT_SEEK : String = "SEGMENT";
        /** seek on keyframe boundary **/
        public static const KEYFRAME_SEEK : String = "KEYFRAME";
        /** accurate seeking **/
        public static const ACCURATE_SEEK : String = "ACCURATE";
    }
}