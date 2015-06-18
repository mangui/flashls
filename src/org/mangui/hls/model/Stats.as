/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.model {
    /** Audio Track identifier **/
    public class Stats {
        public var tech : String;
        public var levelNb : int;
        public var levelStart : int;
        public var autoLevelMin : int;
        public var autoLevelMax : int;
        public var autoLevelAvg : Number;
        public var autoLevelLast : int;
        public var autoLevelSwitch : int;
        public var autoLevelCappingMin : int;
        public var autoLevelCappingMax : int;
        public var autoLevelCappingLast : int;
        public var manualLevelMin : int;
        public var manualLevelMax : int;
        public var manualLevelLast : int;
        public var manualLevelSwitch : int;
        public var fragMinKbps : int;
        public var fragMaxKbps : int;
        public var fragAvgKbps : int;
        public var fragMinLatency : int;
        public var fragMaxLatency : int;
        public var fragAvgLatency : int;
        public var fragBuffered : int;
        public var fragBufferedBytes : int;
        public var fragChangedAuto : int;
        public var fragChangedManual : int;
        public function Stats() {
            tech = "flashls";
            fragBuffered = fragChangedAuto = fragChangedManual = 0;
        }
    }
}