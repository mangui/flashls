/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.controller {
    import org.mangui.hls.constant.HLSLoaderTypes;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.event.HLSLoadMetrics;
    import org.mangui.hls.HLS;
    import org.mangui.hls.HLSSettings;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
    /** Class that manages buffer threshold values (minBufferLength/lowBufferLength)
     */
    public class BufferThresholdController {
        /** Reference to the HLS controller. **/
        private var _hls : HLS;
        // max nb of samples used for bw checking. the bigger it is, the more conservative it is.
        private static const MAX_SAMPLES : int = 30;
        private var _bw : Vector.<Number>;
        private var _nbSamples : uint;
        private var _targetduration : Number;
        private var _minBufferLength : Number;

        /** Create the loader. **/
        public function BufferThresholdController(hls : HLS) : void {
            _hls = hls;
            _hls.addEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.addEventListener(HLSEvent.TAGS_LOADED, _fragmentLoadedHandler);
            _hls.addEventListener(HLSEvent.FRAGMENT_LOADED, _fragmentLoadedHandler);
        };

        public function dispose() : void {
            _hls.removeEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.removeEventListener(HLSEvent.TAGS_LOADED, _fragmentLoadedHandler);
            _hls.removeEventListener(HLSEvent.FRAGMENT_LOADED, _fragmentLoadedHandler);
        }

        public function get minBufferLength() : Number {
            if (HLSSettings.minBufferLength == -1) {
                return _minBufferLength;
            } else {
                return HLSSettings.minBufferLength;
            }
        }

        public function get lowBufferLength() : Number {
            if (HLSSettings.minBufferLength == -1) {
                // in automode, low buffer threshold should be less than min auto buffer
                return Math.min(minBufferLength / 2, HLSSettings.lowBufferLength);
            } else {
                return HLSSettings.lowBufferLength;
            }
        }

        private function _manifestLoadedHandler(event : HLSEvent) : void {
            _nbSamples = 0;
            _targetduration = event.levels[_hls.startLevel].targetduration;
            _bw = new Vector.<Number>(MAX_SAMPLES,true);
            _minBufferLength = _targetduration;
        };

        private function _fragmentLoadedHandler(event : HLSEvent) : void {
            var metrics : HLSLoadMetrics = event.loadMetrics;
            // only monitor main fragment metrics for buffer threshold computing
            if(metrics.type == HLSLoaderTypes.FRAGMENT_MAIN) {
                var cur_bw : Number = metrics.bandwidth;
                _bw[_nbSamples % MAX_SAMPLES] = cur_bw;
                _nbSamples++;

                // compute min bw on MAX_SAMPLES
                var minBw : Number = Number.POSITIVE_INFINITY;
                var samples_max : int = Math.min(_nbSamples, MAX_SAMPLES);
                for (var i : int = 0; i < samples_max; i++) {
                    minBw = Math.min(minBw, _bw[i]);
                }

                // give more weight to current bandwidth
                var bw_ratio : Number = 2 * cur_bw / (minBw + cur_bw);

                /* predict time to dl next segment using a conservative approach.
                 *
                 * heuristic is as follow :
                 *
                 * time to dl next segment = time to dl current segment *  (playlist target duration / current segment duration) * bw_ratio
                 *                           \---------------------------------------------------------------------------------/
                 *                                  this part is a simple rule by 3, assuming we keep same dl bandwidth
                 *  bw ratio is the conservative factor, assuming that next segment will be downloaded with min bandwidth
                 */
                _minBufferLength = metrics.processing_duration * (_targetduration / metrics.duration) * bw_ratio;
                // avoid min > max
                if (HLSSettings.maxBufferLength) {
                    _minBufferLength = Math.min(HLSSettings.maxBufferLength, _minBufferLength);
                }
                CONFIG::LOGGING {
                    Log.debug2("AutoBufferController:minBufferLength:" + _minBufferLength);
                }
            };
        }
    }
}