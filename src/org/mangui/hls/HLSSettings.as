package org.mangui.hls {
    public final class HLSSettings extends Object {
        /**
         * Limit levels usable in auto-quality by the stage dimensions (width and height).
         *      true - level width and height (defined in m3u8 playlist) will be compared with the player width and height (stage.stageWidth and stage.stageHeight). 
         *             Max level will be set depending on the maxLevelCappingMode option.
         *      false - levels will not be limited. All available levels could be used in auto-quality mode taking only bandwidth into consideration.
         * 
         * Note: this setting is ignored in manual mode so all the levels could be selected manually.
         *
         * Default is false
         */
        public static var capLevelToStage : Boolean = false;
        
        /**
         * Defines the max level capping mode to the one available in HLSMaxLevelCappingMode
         *      HLSMaxLevelCappingMode.DOWNSCALE - max capped level should be the one with the dimensions equal or greater than the stage dimensions (so the video will be downscaled)
         *      HLSMaxLevelCappingMode.UPSCALE - max capped level should be the one with the dimensions equal or lower than the stage dimensions (so the video will be upscaled)
         * 
         * Default is HLSMaxLevelCappingMode.DOWNSCALE
         */
        public static var maxLevelCappingMode : String = HLSMaxLevelCappingMode.DOWNSCALE;
        
        // // // // // ///////////////////////////////////
        //
        // org.mangui.hls.stream.HLSNetStream
        //
        // // // // // ///////////////////////////////////
        /**
         * Defines minimum buffer length in seconds before playback can start, after seeking or buffer stalling.
         * 
         * Default is -1 = auto
         */
        public static var minBufferLength : Number = -1;
        /**
         * Defines maximum buffer length in seconds. 
         * (0 means infinite buffering)
         * 
         * Default is 60.
         */
        public static var maxBufferLength : Number = 60;
        /**
         * Defines low buffer length in seconds. 
         * When crossing down this threshold, HLS will switch to buffering state.
         * 
         * Default is 3.
         */
        public static var lowBufferLength : Number = 3;
        /**
         * Defines seek mode to one form available in HLSSeekMode class:
         *      HLSSeekMode.ACCURATE_SEEK - accurate seeking to exact requested position
         *      HLSSeekMode.KEYFRAME_SEEK - key-frame based seeking (seek to nearest key frame before requested seek position)
         *      HLSSeekMode.SEGMENT_SEEK - segment based seeking (seek to beginning of segment containing requested seek position)
         * 
         * Default is HLSSeekMode.ACCURATE_SEEK.
         */
        public static var seekMode : String = HLSSeekMode.ACCURATE_SEEK;
        /** max nb of retries for Fragment Loading in case I/O errors are met,
         *      0, means no retry, error will be triggered automatically
         *     -1 means infinite retry 
         */
        public static var fragmentLoadMaxRetry : int = -1;

        /** fragmentLoadMaxRetryTimeout

         * Maximum Fragment retry timeout (in milliseconds) in case I/O errors are met.
         * Every fail on fragment request, player will exponentially increase the timeout to try again.
         * It starts waiting 1 second (1000ms), than 2, 4, 8, 16, until fragmentLoadMaxRetryTimeout is reached.
         *
         * Default is 64000.
         */
        public static var fragmentLoadMaxRetryTimeout : Number = 64000;
        /**
         * If set to true, live playlist will be flushed from URL cache before reloading 
         * (this is to workaround some cache issues with some combination of Flash Player / IE version)
         * 
         * Default is false
         */
        public static var flushLiveURLCache : Boolean = false;
        /** max nb of retries for Manifest Loading in case I/O errors are met,
         *      0, means no retry, error will be triggered automatically
         *     -1 means infinite retry 
         */
        public static var manifestLoadMaxRetry : int = -1;
        /** manifestLoadMaxRetryTimeout

         * Maximum Manifest retry timeout (in milliseconds) in case I/O errors are met.
         * Every fail on fragment request, player will exponentially increase the timeout to try again.
         * It starts waiting 1 second (1000ms), than 2, 4, 8, 16, until manifestLoadMaxRetryTimeout is reached.
         *
         * Default is 64000.
         */
        public static var manifestLoadMaxRetryTimeout : Number = 64000;


        /** start level : 
         *  from 0 to 1 : indicates the "normalized" preferred bitrate. As such, if it is 0.5, the closest to the middle bitrate will be selected and used first.
         * -1 : automatic start level selection, playback will start from level matching download bandwidth (determined from download of first segment) 
         */
        public static var startFromLevel : Number = -1;
        

        /** seek level : 
         *  from 0 to 1 : indicates the "normalized" preferred bitrate. As such, if it is 0.5, the closest to the middle bitrate will be selected and used first.
         * -1 : automatic start level selection, keep previous level matching previous download bandwidth 
         */
        public static var seekFromLevel : Number = -1;
        /**
         * Defines whether INFO level log messages will will appear in the console
         * Default is true.
         */
        public static var logInfo : Boolean = true;
        /**
         * Defines whether DEBUG level log messages will will appear in the console
         * Default is false.
         */
        public static var logDebug : Boolean = false;
        /**
         * Defines whether DEBUG2 level log messages will will appear in the console
         * Default is false.
         */
        public static var logDebug2 : Boolean = false;
        /**
         * Defines whether WARN level log messages will will appear in the console
         * Default is true.
         */
        public static var logWarn : Boolean = true;
        /**
         * Defines whether ERROR level log messages will will appear in the console
         * Default is true.
         */
        public static var logError : Boolean = true;
    }
}