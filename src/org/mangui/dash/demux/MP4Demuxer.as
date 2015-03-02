/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.dash.demux {

    import flash.utils.ByteArray;
    import org.mangui.adaptive.demux.Demuxer;
    import org.mangui.adaptive.flv.FLVTag;

    CONFIG::LOGGING {
        import org.mangui.adaptive.utils.Log;
    }
    public class MP4Demuxer implements Demuxer {
        /** Byte data to be read **/
        private var _data : ByteArray;
        /* callback functions for audio selection, and parsing progress/complete */
        private var _callback_audioselect : Function;
        private var _callback_progress : Function;
        private var _callback_complete : Function;

        /** append new data */
        public function append(data : ByteArray) : void {
            if (_data == null) {
                _data = new ByteArray();
            }
            _data.writeBytes(data);
        }

        /** cancel demux operation */
        public function cancel() : void {
            _data = null;
        }

        public function get audio_expected() : Boolean {
            return true;
        }

        public function get video_expected() : Boolean {
            return true;
        }

        public function notifycomplete() : void {
            CONFIG::LOGGING {
                Log.debug("MP4: notifycomplete");
            }
        }

        public function MP4Demuxer(callback_audioselect : Function, callback_progress : Function, callback_complete : Function) : void {
            _callback_audioselect = callback_audioselect;
            _callback_progress = callback_progress;
            _callback_complete = callback_complete;
        };

        public static function probe(data : ByteArray) : Boolean {
            return false;
        }
    }
}