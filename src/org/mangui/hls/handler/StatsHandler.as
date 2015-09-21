/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.hls.handler {
    import flash.system.Capabilities;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.event.HLSLoadMetrics;
    import org.mangui.hls.event.HLSPlayMetrics;
    import org.mangui.hls.HLS;
    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
    /*
     * class that handle per playback session stats
     */
     public class StatsHandler {
        /** Reference to the HLS controller. **/
        private var _hls : HLS;
        private var _stats : Object;
        private var _sumLatency : int;
        private var _sumKbps : int;
        private var _sumAutoLevel : int;
        private var _levelLastAuto : Boolean;

        public function StatsHandler(hls : HLS) {
            _hls = hls;
            _hls.addEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.addEventListener(HLSEvent.FRAGMENT_LOADED, _fragmentLoadedHandler);
            _hls.addEventListener(HLSEvent.FRAGMENT_PLAYING,_fragmentPlayingHandler);
            _hls.addEventListener(HLSEvent.FRAGMENT_SKIPPED,_fragmentSkippedHandler);
            _hls.addEventListener(HLSEvent.FPS_DROP, _fpsDropHandler);
            _hls.addEventListener(HLSEvent.FPS_DROP_LEVEL_CAPPING, _fpsDropLevelCappingHandler);
            _hls.addEventListener(HLSEvent.FPS_DROP_SMOOTH_LEVEL_SWITCH, _fpsDropSmoothLevelSwitchHandler);
        }

        public function dispose() : void {
            _hls.removeEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.removeEventListener(HLSEvent.FRAGMENT_LOADED, _fragmentLoadedHandler);
            _hls.removeEventListener(HLSEvent.FRAGMENT_PLAYING, _fragmentPlayingHandler);
            _hls.removeEventListener(HLSEvent.FRAGMENT_SKIPPED,_fragmentSkippedHandler);
            _hls.removeEventListener(HLSEvent.FPS_DROP, _fpsDropHandler);
            _hls.removeEventListener(HLSEvent.FPS_DROP_LEVEL_CAPPING, _fpsDropLevelCappingHandler);
            _hls.removeEventListener(HLSEvent.FPS_DROP_SMOOTH_LEVEL_SWITCH, _fpsDropSmoothLevelSwitchHandler);
        }

        public function get stats() : Object {
            return _stats;
        }

        private function _manifestLoadedHandler(event : HLSEvent) : void {
            _stats = {};
            _stats.levelNb = event.levels.length;
            _stats.levelStart = -1;
            _stats.tech = "flashls,"+Capabilities.version;
            _stats.fragBuffered = _stats.fragChangedAuto = _stats.fragChangedManual = _stats.fragSkipped = 0;
            _stats.fpsDropEvent = _stats.fpsDropSmoothLevelSwitch = 0;
        };

        private function _fragmentLoadedHandler(event : HLSEvent) : void {
            var metrics : HLSLoadMetrics = event.loadMetrics;
            var latency : int = metrics.loading_begin_time-metrics.loading_request_time;
            var bandwidth : int = metrics.bandwidth/1000;
            if(_stats.fragBuffered) {
              _stats.fragLastLatency = latency;
              _stats.fragMinLatency = Math.min(_stats.fragMinLatency,latency);
              _stats.fragMaxLatency = Math.max(_stats.fragMaxLatency,latency);
              _stats.fragLastKbps = bandwidth;
              _stats.fragMinKbps = Math.min(_stats.fragMinKbps,bandwidth);
              _stats.fragMaxKbps = Math.max(_stats.fragMaxKbps,bandwidth);
              _stats.autoLevelCappingMin = Math.min(_stats.autoLevelCappingMin,_hls.autoLevelCapping);
              _stats.autoLevelCappingMax = Math.max(_stats.autoLevelCappingMax,_hls.autoLevelCapping);
              _stats.fragBuffered++;
            } else {
                  _stats.fragMinLatency = _stats.fragMaxLatency = latency;
                  _stats.fragMinKbps = _stats.fragMaxKbps = bandwidth;
                  _stats.fragBuffered = 1;
                  _stats.fragBufferedBytes = 0;
                  _stats.autoLevelCappingMin = _stats.autoLevelCappingMax = _hls.autoLevelCapping;
                  _sumLatency=0;
                  _sumKbps=0;
            }
            _sumLatency+=latency;
            _sumKbps+=bandwidth;
            _stats.fragBufferedBytes+=metrics.size;
            _stats.fragAvgLatency = _sumLatency/_stats.fragBuffered;
            _stats.fragAvgKbps = _sumKbps/_stats.fragBuffered;
            _stats.autoLevelCappingLast = _hls.autoLevelCapping;
        }

        private function _fragmentPlayingHandler(event : HLSEvent) : void {
          var metrics : HLSPlayMetrics = event.playMetrics;
          var level : int = metrics.level;
          var autoLevel : Boolean = metrics.auto_level;
          if(_stats.levelStart == -1) {
              _stats.levelStart = level;
          }

          if(autoLevel) {
              if(_stats.fragChangedAuto) {
                _stats.autoLevelMin = Math.min(_stats.autoLevelMin,level);
                _stats.autoLevelMax = Math.max(_stats.autoLevelMax,level);
                _stats.fragChangedAuto++;
                if(_levelLastAuto && level !== _stats.autoLevelLast) {
                  _stats.autoLevelSwitch++;
              }
              } else {
                _stats.autoLevelMin = _stats.autoLevelMax = level;
                _stats.autoLevelSwitch = 0;
                _stats.fragChangedAuto = 1;
                _sumAutoLevel = 0;
            }
            _sumAutoLevel+=level;
            _stats.autoLevelAvg = _sumAutoLevel/_stats.fragChangedAuto;
            _stats.autoLevelLast = level;
            } else {
              if(_stats.fragChangedManual) {
                _stats.manualLevelMin = Math.min(_stats.manualLevelMin,level);
                _stats.manualLevelMax = Math.max(_stats.manualLevelMax,level);
                _stats.fragChangedManual++;
                if(!_levelLastAuto && level !== _stats.manualLevelLast) {
                  _stats.manualLevelSwitch++;
              }
              } else {
                _stats.manualLevelMin = _stats.manualLevelMax = level;
                _stats.manualLevelSwitch = 0;
                _stats.fragChangedManual = 1;
            }
            _stats.manualLevelLast = level;
        }
        _levelLastAuto = autoLevel;
      }

      private function _fragmentSkippedHandler(event : HLSEvent) : void {
        if(_stats.fragSkipped) {
            _stats.fragSkipped++;
        } else {
            _stats.fragSkipped = 1;
        }
      }

      private function _fpsDropHandler(event : HLSEvent) : void {
        _stats.fpsDropEvent++;
        _stats.fpsTotalDroppedFrames = _hls.stream.info.droppedFrames;
      }

      private function _fpsDropLevelCappingHandler(event : HLSEvent) : void {
         _stats.fpsDropLevelCappingMin=event.level;
      }

      private function _fpsDropSmoothLevelSwitchHandler(event : HLSEvent) : void {
        _stats.fpsDropSmoothLevelSwitch++;
      }
  }
}
