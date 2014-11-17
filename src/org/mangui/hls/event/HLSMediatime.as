/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.hls.event {
    /** Identifiers for the different stream types. **/
    public class HLSMediatime {
        /**  playback position (in seconds), relative to current playlist start. 
         * this value could be negative in case of live playlist sliding :
         *  this can happen in case current playback position 
         * is in a fragment that has been removed from the playlist
         */
        public var position : Number;
        /** current playlist duration (in seconds) **/
        public var duration : Number;
        /**  live playlist sliding since previous seek()  (in seconds)**/
        public var live_sliding : Number;
        /** current buffer duration  (in seconds) **/
        public var buffer : Number;
        /** current date : meaningful is playlist contains date information */
        public var program_date : Number;

        public function HLSMediatime(position : Number, duration : Number, buffer : Number, live_sliding : Number, program_date : Number) {
            this.position = position;
            this.duration = duration;
            this.buffer = buffer;
            this.live_sliding = live_sliding;
            this.program_date = program_date;
        }
    }
}