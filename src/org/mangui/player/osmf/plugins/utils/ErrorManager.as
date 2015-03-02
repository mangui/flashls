/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.player.osmf.plugins.utils {
    import org.mangui.adaptive.event.AdaptiveError;
    import org.mangui.adaptive.event.AdaptiveEvent;
    import org.osmf.events.MediaErrorCodes;

    public class ErrorManager {

        public static function getMediaErrorCode(event : AdaptiveEvent) : int {
            var errorCode : int = MediaErrorCodes.NETSTREAM_PLAY_FAILED;
            if (event && event.error) {
                switch (event.error.code) {
                    case AdaptiveError.FRAGMENT_LOADING_ERROR:
                    case AdaptiveError.FRAGMENT_LOADING_CROSSDOMAIN_ERROR:
                    case AdaptiveError.KEY_LOADING_ERROR:
                    case AdaptiveError.KEY_LOADING_CROSSDOMAIN_ERROR:
                    case AdaptiveError.MANIFEST_LOADING_CROSSDOMAIN_ERROR:
                    case AdaptiveError.MANIFEST_LOADING_IO_ERROR:
                        errorCode = MediaErrorCodes.IO_ERROR;
                        break;
                    case org.mangui.adaptive.event.AdaptiveError.FRAGMENT_PARSING_ERROR:
                    case org.mangui.adaptive.event.AdaptiveError.KEY_PARSING_ERROR:
                    case org.mangui.adaptive.event.AdaptiveError.MANIFEST_PARSING_ERROR:
                        errorCode = MediaErrorCodes.NETSTREAM_FILE_STRUCTURE_INVALID;
                        break;
                    case org.mangui.adaptive.event.AdaptiveError.TAG_APPENDING_ERROR:
                        errorCode = MediaErrorCodes.ARGUMENT_ERROR;
                        break;
                }
            }
            return errorCode;
        };

        public static function getMediaErrorMessage(event : AdaptiveEvent) : String {
            return (event && event.error) ? event.error.msg : "Unknown error";
        };
    };
}