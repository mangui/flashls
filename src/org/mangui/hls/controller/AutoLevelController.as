/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.hls.controller {
    import org.mangui.hls.constant.HLSMaxLevelCappingMode;
    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.HLS;
    import org.mangui.hls.model.Level;
    import org.mangui.hls.event.HLSEvent;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
    /** Class that manages auto level selection 
     * 
     * this is an implementation based on Serial segment fetching method from 
     * http://www.cs.tut.fi/~moncef/publications/rate-adaptation-IC-2011.pdf
     */
    public class AutoLevelController {
        /** Reference to the HLS controller. **/
        private var _hls : HLS;
        /** switch up threshold **/
        private var _switchup : Vector.<Number> = null;
        /** switch down threshold **/
        private var _switchdown : Vector.<Number> = null;
        /** bitrate array **/
        private var _bitrate : Vector.<Number> = null;
        /** vector of levels with unique dimension with highest bandwidth **/
        private var _maxUniqueLevels : Vector.<Level> = null;
        /** nb level **/
        private var _nbLevel : int = 0;
        private var _last_segment_duration : Number;
        private var _last_fetch_duration : Number;
        private var  last_bandwidth : Number;

        /** Create the loader. **/
        public function AutoLevelController(hls : HLS) : void {
            _hls = hls;
            _hls.addEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.addEventListener(HLSEvent.FRAGMENT_LOADED, _fragmentLoadedHandler);
        }
        ;

        public function dispose() : void {
            _hls.removeEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.removeEventListener(HLSEvent.FRAGMENT_LOADED, _fragmentLoadedHandler);
        }

        private function _fragmentLoadedHandler(event : HLSEvent) : void {
            last_bandwidth = event.loadMetrics.bandwidth;
            _last_segment_duration = event.loadMetrics.frag_duration;
            _last_fetch_duration = event.loadMetrics.frag_processing_time;
        }

        /** Store the manifest data. **/
        private function _manifestLoadedHandler(event : HLSEvent) : void {
            var levels : Vector.<Level> = event.levels;
            var maxswitchup : Number = 0;
            var minswitchdwown : Number = Number.MAX_VALUE;
            _nbLevel = levels.length;
            _bitrate = new Vector.<Number>(_nbLevel, true);
            _switchup = new Vector.<Number>(_nbLevel, true);
            _switchdown = new Vector.<Number>(_nbLevel, true);
            _last_segment_duration = 0;
            _last_fetch_duration = 0;
            last_bandwidth = 0;

            var i : int;

            for (i = 0; i < _nbLevel; i++) {
                _bitrate[i] = levels[i].bitrate;
            }

            for (i = 0; i < _nbLevel - 1; i++) {
                _switchup[i] = (_bitrate[i + 1] - _bitrate[i]) / _bitrate[i];
                maxswitchup = Math.max(maxswitchup, _switchup[i]);
            }
            for (i = 0; i < _nbLevel - 1; i++) {
                _switchup[i] = Math.min(maxswitchup, 2 * _switchup[i]);

                CONFIG::LOGGING {
                    Log.debug("_switchup[" + i + "]=" + _switchup[i]);
                }
            }

            for (i = 1; i < _nbLevel; i++) {
                _switchdown[i] = (_bitrate[i] - _bitrate[i - 1]) / _bitrate[i];
                minswitchdwown = Math.min(minswitchdwown, _switchdown[i]);
            }
            for (i = 1; i < _nbLevel; i++) {
                _switchdown[i] = Math.max(2 * minswitchdwown, _switchdown[i]);

                CONFIG::LOGGING {
                    Log.debug("_switchdown[" + i + "]=" + _switchdown[i]);
                }
            }

            if (HLSSettings.capLevelToStage) {
                _maxUniqueLevels = _maxLevelsWithUniqueDimensions;
            }
        }
        ;

        public function getbestlevel(download_bandwidth : Number) : int {
            var max_level : int = _max_level;
            for (var i : int = max_level; i >= 0; i--) {
                if (_bitrate[i] <= download_bandwidth) {
                    return i;
                }
            }
            return 0;
        }

        private function get _maxLevelsWithUniqueDimensions() : Vector.<Level> {
            var filter : Function = function(l : Level, i : int, v : Vector.<Level>) : Boolean {
                if (l.width > 0 && l.height > 0) {
                    if (i + 1 < v.length) {
                        var nextLevel : Level = v[i + 1];
                        if (l.width != nextLevel.width && l.height != nextLevel.height) {
                            return true;
                        }
                    } else {
                        return true;
                    }
                }
                return false;
            };

            return _hls.levels.filter(filter);
        }

        private function get _max_level() : int {
            if (HLSSettings.capLevelToStage) {
                var maxLevelsCount : int = _maxUniqueLevels.length;

                if (_hls.stage && maxLevelsCount) {
                    var maxLevel : Level = this._maxUniqueLevels[0], maxLevelIdx : int = maxLevel.index, sWidth : Number = this._hls.stage.stageWidth, sHeight : Number = this._hls.stage.stageHeight, lWidth : int, lHeight : int, i : int;

                    switch (HLSSettings.maxLevelCappingMode) {
                        case HLSMaxLevelCappingMode.UPSCALE:
                            for (i = maxLevelsCount - 1; i >= 0; i--) {
                                maxLevel = this._maxUniqueLevels[i];
                                maxLevelIdx = maxLevel.index;
                                lWidth = maxLevel.width;
                                lHeight = maxLevel.height;
                                CONFIG::LOGGING {
                                    Log.debug("stage size: " + sWidth + "x" + sHeight + " ,level" + maxLevelIdx + " size: " + lWidth + "x" + lHeight);
                                }
                                if (sWidth >= lWidth || sHeight >= lHeight) {
                                    break;
                                    // from for loop
                                }
                            }
                            break;
                        case HLSMaxLevelCappingMode.DOWNSCALE:
                            for (i = 0; i < maxLevelsCount; i++) {
                                maxLevel = this._maxUniqueLevels[i];
                                maxLevelIdx = maxLevel.index;
                                lWidth = maxLevel.width;
                                lHeight = maxLevel.height;
                                CONFIG::LOGGING {
                                    Log.debug("stage size: " + sWidth + "x" + sHeight + " ,level" + maxLevelIdx + " size: " + lWidth + "x" + lHeight);
                                }
                                if (sWidth <= lWidth || sHeight <= lHeight) {
                                    break;
                                    // from for loop
                                }
                            }
                            break;
                    }
                    CONFIG::LOGGING {
                        Log.debug("max capped level idx: " + maxLevelIdx);
                    }
                }
                return maxLevelIdx;
            } else {
                return _nbLevel - 1;
            }
        }

        /** Update the quality level for the next fragment load. **/
        public function getnextlevel(current_level : int, buffer : Number) : int {
            if (_last_fetch_duration == 0 || _last_segment_duration == 0) {
                return 0;
            }

            /* rsft : remaining segment fetch time : available time to fetch next segment
            it depends on the current playback timestamp , the timestamp of the first frame of the next segment
            and TBMT, indicating a desired latency between the time instant to receive the last byte of a
            segment to the playback of the first media frame of a segment
            buffer is start time of next segment
            TBMT is the buffer size we need to ensure (we need at least 2 segments buffered */
            var rsft : Number = 1000 * buffer - 2 * _last_fetch_duration;
            var sftm : Number = Math.min(_last_segment_duration, rsft) / _last_fetch_duration;
            var max_level : Number = _max_level;
            var switch_to_level : int = current_level;
            // CONFIG::LOGGING {
            // Log.info("rsft:" + rsft);
            // Log.info("sftm:" + sftm);
            // }
            // }
            /* to switch level up :
            rsft should be greater than switch up condition
             */
            if ((current_level < max_level) && (sftm > (1 + _switchup[current_level]))) {
                CONFIG::LOGGING {
                    Log.debug("sftm:> 1+_switchup[_level]=" + (1 + _switchup[current_level]));
                }
                switch_to_level = current_level + 1;
            }
            
            /* to switch level down :
            rsft should be smaller than switch up condition,
            or the current level is greater than max level
             */ else if ((current_level > max_level && current_level > 0) || (current_level > 0 && (sftm < 1 - _switchdown[current_level]))) {
                CONFIG::LOGGING {
                    Log.debug("sftm < 1-_switchdown[current_level]=" + _switchdown[current_level]);
                }
                var bufferratio : Number = 1000 * buffer / _last_segment_duration;
                /* find suitable level matching current bandwidth, starting from current level
                when switching level down, we also need to consider that we might need to load two fragments.
                the condition (bufferratio > 2*_levels[j].bitrate/_last_bandwidth)
                ensures that buffer time is bigger than than the time to download 2 fragments from level j, if we keep same bandwidth.
                 */

                for (var j : int = current_level - 1; j >= 0; j--) {
                    if (_bitrate[j] <= last_bandwidth && (bufferratio > 2 * _bitrate[j] / last_bandwidth)) {
                        switch_to_level = j;
                        break;
                    }
                    if (j == 0) {
                        switch_to_level = 0;
                    }
                }
            }

            // Then we should check if selected level is higher than max_level if so, than take the min of those two
            switch_to_level = Math.min(max_level, switch_to_level);

            if (switch_to_level != current_level) {
                CONFIG::LOGGING {
                    Log.debug("switch to level " + switch_to_level);
                }
                null;
            }

            return switch_to_level;
        }
    }
}