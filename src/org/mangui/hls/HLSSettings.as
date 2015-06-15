/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls {
    import org.mangui.hls.constant.HLSSeekMode;
    import org.mangui.hls.constant.HLSMaxLevelCappingMode;

    public final class HLSSettings extends Object {
        /**
         * capLevelToStage
         *
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
         * maxLevelCappingMode
         *
         * Defines the max level capping mode to the one available in HLSMaxLevelCappingMode
         *      HLSMaxLevelCappingMode.DOWNSCALE - max capped level should be the one with the dimensions equal or greater than the stage dimensions (so the video will be downscaled)
         *      HLSMaxLevelCappingMode.UPSCALE - max capped level should be the one with the dimensions equal or lower than the stage dimensions (so the video will be upscaled)
         *
         * Default is HLSMaxLevelCappingMode.DOWNSCALE
         */
        public static var maxLevelCappingMode : String = HLSMaxLevelCappingMode.DOWNSCALE;

        // // // // // // /////////////////////////////////
        //
        // org.mangui.hls.stream.HLSNetStream
        //
        // // // // // // /////////////////////////////////
        /**
         * minBufferLength
         *
         * Defines minimum buffer length in seconds before playback can start, after seeking or buffer stalling.
         *
         * Default is -1 = auto
         */
        public static var minBufferLength : Number = -1;

        /**
         * maxBufferLength
         *
         * Defines maximum buffer length in seconds.
         * (0 means infinite buffering)
         *
         * Default is 120
         */
        public static var maxBufferLength : Number = 120;

        /**
         * maxBackBufferLength
         *
         * Defines maximum back buffer length in seconds.
         * (0 means infinite back buffering)
         *
         * Default is 30
         */
        public static var maxBackBufferLength : Number = 30;

        /**
         * lowBufferLength
         *
         * Defines low buffer length in seconds.
         * When crossing down this threshold, HLS will switch to buffering state.
         *
         * Default is 3
         */
        public static var lowBufferLength : Number = 3;

        /**
         * seekMode
         *
         * Defines seek mode to one form available in HLSSeekMode class:
         *      HLSSeekMode.ACCURATE_SEEK - accurate seeking to exact requested position
         *      HLSSeekMode.KEYFRAME_SEEK - key-frame based seeking (seek to nearest key frame before requested seek position)
         *
         * Default is HLSSeekMode.KEYFRAME_SEEK
         */
        public static var seekMode : String = HLSSeekMode.KEYFRAME_SEEK;

        /**
         * keyLoadMaxRetry
         *
         * Max nb of retries for Key Loading in case I/O errors are met,
         *      0, means no retry, error will be triggered automatically
         *     -1 means infinite retry
         *
         * Default is 3
         */
        public static var keyLoadMaxRetry : int = 3;

        /**
         * keyLoadMaxRetryTimeout
         *
         * Maximum key retry timeout (in milliseconds) in case I/O errors are met.
         * Every fail on key request, player will exponentially increase the timeout to try again.
         * It starts waiting 1 second (1000ms), than 2, 4, 8, 16, until keyLoadMaxRetryTimeout is reached.
         *
         * Default is 64000.
         */
        public static var keyLoadMaxRetryTimeout : Number = 64000;

        /**
         * fragmentLoadMaxRetry
         *
         * Max number of retries for Fragment Loading in case I/O errors are met,
         *      0, means no retry, error will be triggered automatically
         *     -1 means infinite retry
         *
         * Default is 3
         */
        public static var fragmentLoadMaxRetry : int = 3;

        /**
         * fragmentLoadMaxRetryTimeout
         *
         * Maximum Fragment retry timeout (in milliseconds) in case I/O errors are met.
         * Every fail on fragment request, player will exponentially increase the timeout to try again.
         * It starts waiting 1 second (1000ms), than 2, 4, 8, 16, until fragmentLoadMaxRetryTimeout is reached.
         *
         * Default is 4000
         */
        public static var fragmentLoadMaxRetryTimeout : Number = 4000

        /**
         * fragmentLoadSkipAfterMaxRetry
         *
         * control behaviour in case fragment load still fails after max retry timeout
         * if set to true, fragment will be skipped and next one will be loaded.
         * If set to false, an I/O Error will be raised.
         *
         * Default is true.
         */
        public static var fragmentLoadSkipAfterMaxRetry : Boolean = true;

        /**
         * flushLiveURLCache
         *
         * If set to true, live playlist will be flushed from URL cache before reloading
         * (this is to workaround some cache issues with some combination of Flash Player / IE version)
         *
         * Default is false
         */
        public static var flushLiveURLCache : Boolean = false;

        /**
         * manifestLoadMaxRetry
         *
         * max nb of retries for Manifest Loading in case I/O errors are met,
         *      0, means no retry, error will be triggered automatically
         *     -1 means infinite retry
         */
        public static var manifestLoadMaxRetry : int = 3;

        /**
         * manifestLoadMaxRetryTimeout
         *
         * Maximum Manifest retry timeout (in milliseconds) in case I/O errors are met.
         * Every fail on fragment request, player will exponentially increase the timeout to try again.
         * It starts waiting 1 second (1000ms), than 2, 4, 8, 16, until manifestLoadMaxRetryTimeout is reached.
         *
         * Default is 64000
         */
        public static var manifestLoadMaxRetryTimeout : Number = 64000;

        /**
         * startFromBitrate
         *
         * If greater than 0, specifies the preferred bitrate.
         * If -1, and startFromLevel is not specified, automatic start level selection will be used.
         * This parameter, if set, will take priority over startFromLevel.
         *
         * Default is -1
         */
        public static var startFromBitrate : Number = -1;

        /**
         * startFromLevel
         *
         * start level :
         *  from 0 to 1 : indicates the "normalized" preferred level. As such, if it is 0.5, the closest to the middle bitrate will be selected and used first.
         * -1 : automatic start level selection, playback will start from level matching download bandwidth (determined from download of first segment)
         * -2 : playback will start from the first level appearing in Manifest (not sorted by bitrate)
         *
         * Default is -1
         */
        public static var startFromLevel : Number = -1;

        /**
         * seekFromLevel
         *
         * Seek level:
         *  from 0 to 1: indicates the "normalized" preferred bitrate. As such, if it is 0.5, the closest to the middle bitrate will be selected and used first.
         * -1 : automatic start level selection, keep previous level matching previous download bandwidth
         *
         * Default is -1
         */
        public static var seekFromLevel : Number = -1;

        /**
         * useHardwareVideoDecoder
         *
         * Use hardware video decoder:
         *  it will set NetStream.useHardwareDecoder
         *  refer to http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/flash/net/NetStream.html#useHardwareDecoder
         *
         * Default is false
         */
        public static var useHardwareVideoDecoder : Boolean = false;

        /**
         * logInfo
         *
         * Defines whether INFO level log messages will will appear in the console
         *
         * Default is true
         */
        public static var logInfo : Boolean = true;

        /**
         * logDebug
         *
         * Defines whether DEBUG level log messages will will appear in the console
         *
         * Default is false
         */
        public static var logDebug : Boolean = false;

        /**
         * logDebug2
         *
         * Defines whether DEBUG2 level log messages will will appear in the console
         *
         * Default is false
         */
        public static var logDebug2 : Boolean = false;

        /**
         * logWarn
         *
         * Defines whether WARN level log messages will will appear in the console
         *
         * Default is true
         */
        public static var logWarn : Boolean = true;

        /**
         * logError
         *
         * Defines whether ERROR level log messages will will appear in the console
         *
         * Default is true
         */
        public static var logError : Boolean = true;
    }
}
