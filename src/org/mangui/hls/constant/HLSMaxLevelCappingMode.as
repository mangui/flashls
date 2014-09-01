package org.mangui.hls.constant {
    /** Max Level Capping Modes **/
    public class HLSMaxLevelCappingMode {
        /**
         * max capped level should be the one with the dimensions equal or greater than the stage dimensions (so the video will be downscaled)
         */
        public static const DOWNSCALE : String = "downscale";
        
        /**
         *  max capped level should be the one with the dimensions equal or lower than the stage dimensions (so the video will be upscaled)
         */
        public static const UPSCALE : String = "upscale";
    }
}