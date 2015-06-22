/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.hls.controller {
    import flash.events.Event;
    import flash.events.TimerEvent;
    import flash.utils.getTimer;
    import flash.utils.Timer;
    import org.mangui.hls.constant.HLSPlayStates;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.HLS;
    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
    /*
     * class that control/monitor FPS
     */
    public class FPSController {
      /** Reference to the HLS controller. **/
      private var _hls : HLS;
      private var _timer : Timer;
      private var _lastTimer : int;
      private var _lastdroppedFrames : int;
      private var _hiddenVideo : Boolean;

      public function FPSController(hls : HLS) {
          _hls = hls;
          _hls.addEventListener(HLSEvent.PLAYBACK_STATE, _playbackStateHandler);
          _timer = new Timer(50,0);
          _timer.addEventListener(TimerEvent.TIMER, _checkFPS);
      }

      public function dispose() : void {
          _hls.removeEventListener(HLSEvent.PLAYBACK_STATE, _playbackStateHandler);
      }

      private function _playbackStateHandler(event : HLSEvent) : void {
        switch(event.state) {
          case HLSPlayStates.PLAYING:
            // start fps check timer when switching to playing state
            _lastTimer = 0;
            _hiddenVideo = true;
            _timer.start();
            break;
          default:
            if(_timer.running)  {
              // stop it in all other cases
              _lastTimer = 0;
              _hiddenVideo = true;
              _timer.stop();
                CONFIG::LOGGING {
                  Log.info("video not playing, stop monitoring dropped FPS");
                }
            }
            break;
        }
      };

      private function _checkFPS(e : Event) : void {
        var newTimer : int = getTimer();
        if(_lastTimer) {
          var delta:int = newTimer - _lastTimer;
          /* according to http://www.kaourantin.net/2010/03/timing-it-right.html, when player is hidden, Flash timer only runs at 8Hz.
             here we armed our timer to 50ms, if delta time between 2 runs is more than 100ms, consider that our player is hidden ...
          */
          the idea here is
          if(delta && delta < 100) {
            if(_hiddenVideo == false) {
              var deltaDroppedFrames : int = _hls.stream.info.droppedFrames - _lastdroppedFrames;
              var dropFPS : Number = 1000*deltaDroppedFrames/delta;
              if(dropFPS > 1) {
                CONFIG::LOGGING {
                  Log.warn("!!! display/dropped FPS > 1, dispatch event:" + _hls.stream.currentFPS.toFixed(2) + "/" + dropFPS.toFixed(2));
                  _hls.dispatchEvent(new HLSEvent(HLSEvent.FPS_DROP, _hls.currentLevel));
                }
              }
            } else {
                CONFIG::LOGGING {
                  Log.info("video displayed,start monitoring dropped FPS");
                }
              _hiddenVideo = false;
            }
          } else {
            if(_hiddenVideo == false) {
              _hiddenVideo = true;
              CONFIG::LOGGING {
                Log.info("video hidden,stop monitoring dropped FPS,delta:"+delta);
              }
            }
          }
        }
        _lastTimer = newTimer;
        _lastdroppedFrames = _hls.stream.info.droppedFrames;
      }
  }
}
