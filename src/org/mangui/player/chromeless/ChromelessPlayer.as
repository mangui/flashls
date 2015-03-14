/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.player.chromeless {

    import flash.display.*;
    import flash.events.*;
    import flash.external.ExternalInterface;
    import flash.geom.Rectangle;
    import flash.media.SoundTransform;
    import flash.media.StageVideo;
    import flash.media.StageVideoAvailability;
    import flash.media.Video;
    import flash.net.URLStream;
    import flash.utils.setTimeout;
    import org.mangui.adaptive.Adaptive;
    import org.mangui.adaptive.AdaptiveSettings;
    import org.mangui.adaptive.event.AdaptiveError;
    import org.mangui.adaptive.event.AdaptiveEvent;
    import org.mangui.adaptive.model.AudioTrack;
    import org.mangui.adaptive.model.Level;
    import org.mangui.adaptive.utils.Log;
    import org.mangui.adaptive.utils.ScaleVideo;

    CONFIG::HLS {
        import org.mangui.hls.HLS;
    }
    CONFIG::DASH {
        import org.mangui.dash.Dash;
    }

    // import com.sociodox.theminer.*;
    public class ChromelessPlayer extends Sprite {
        /** reference to the framework. **/
        protected var _adaptive : Adaptive;
        /** Sheet to place on top of the video. **/
        protected var _sheet : Sprite;
        /** Reference to the stage video element. **/
        protected var _stageVideo : StageVideo = null;
        /** Reference to the video element. **/
        protected var _video : Video = null;
        /** Video size **/
        protected var _videoWidth : int = 0;
        protected var _videoHeight : int = 0;
        /** current media position */
        protected var _media_position : Number;
        protected var _duration : Number;
        /** URL autoload feature */
        protected var _autoLoad : Boolean = false;

        /** Initialization. **/
        public function ChromelessPlayer() {
            _setupStage();
            _setupSheet();
            _setupExternalGetters();
            _setupExternalCallers();

            setTimeout(_pingJavascript, 50);
        };

        protected function _setupExternalGetters() : void {
            ExternalInterface.addCallback("getLevel", _getLevel);
            ExternalInterface.addCallback("getPlaybackLevel", _getPlaybackLevel);
            ExternalInterface.addCallback("getLevels", _getLevels);
            ExternalInterface.addCallback("getAutoLevel", _getAutoLevel);
            ExternalInterface.addCallback("getDuration", _getDuration);
            ExternalInterface.addCallback("getPosition", _getPosition);
            ExternalInterface.addCallback("getPlaybackState", _getPlaybackState);
            ExternalInterface.addCallback("getSeekState", _getSeekState);
            ExternalInterface.addCallback("getType", _getType);
            ExternalInterface.addCallback("getmaxBufferLength", _getmaxBufferLength);
            ExternalInterface.addCallback("getminBufferLength", _getminBufferLength);
            ExternalInterface.addCallback("getlowBufferLength", _getlowBufferLength);
            ExternalInterface.addCallback("getmaxBackBufferLength", _getmaxBackBufferLength);
            ExternalInterface.addCallback("getbufferLength", _getbufferLength);
            ExternalInterface.addCallback("getLogDebug", _getLogDebug);
            ExternalInterface.addCallback("getLogDebug2", _getLogDebug2);
            ExternalInterface.addCallback("getUseHardwareVideoDecoder", _getUseHardwareVideoDecoder);
            ExternalInterface.addCallback("getCapLeveltoStage", _getCapLeveltoStage);
            ExternalInterface.addCallback("getflushLiveURLCache", _getflushLiveURLCache);
            ExternalInterface.addCallback("getstartFromLevel", _getstartFromLevel);
            ExternalInterface.addCallback("getseekFromLowestLevel", _getseekFromLevel);
            ExternalInterface.addCallback("getJSURLStream", _getJSURLStream);
            ExternalInterface.addCallback("getPlayerVersion", _getPlayerVersion);
            ExternalInterface.addCallback("getAudioTrackList", _getAudioTrackList);
            ExternalInterface.addCallback("getAudioTrackId", _getAudioTrackId);
        };

        protected function _setupExternalCallers() : void {
            ExternalInterface.addCallback("playerLoad", _load);
            ExternalInterface.addCallback("playerPlay", _play);
            ExternalInterface.addCallback("playerPause", _pause);
            ExternalInterface.addCallback("playerResume", _resume);
            ExternalInterface.addCallback("playerSeek", _seek);
            ExternalInterface.addCallback("playerStop", _stop);
            ExternalInterface.addCallback("playerVolume", _volume);
            ExternalInterface.addCallback("playerSetLevel", _setLevel);
            ExternalInterface.addCallback("playerSmoothSetLevel", _smoothSetLevel);
            ExternalInterface.addCallback("playerSetmaxBufferLength", _setmaxBufferLength);
            ExternalInterface.addCallback("playerSetminBufferLength", _setminBufferLength);
            ExternalInterface.addCallback("playerSetlowBufferLength", _setlowBufferLength);
            ExternalInterface.addCallback("playerSetbackBufferLength", _setbackBufferLength);
            ExternalInterface.addCallback("playerSetflushLiveURLCache", _setflushLiveURLCache);
            ExternalInterface.addCallback("playerSetstartFromLevel", _setstartFromLevel);
            ExternalInterface.addCallback("playerSetseekFromLevel", _setseekFromLevel);
            ExternalInterface.addCallback("playerSetLogDebug", _setLogDebug);
            ExternalInterface.addCallback("playerSetLogDebug2", _setLogDebug2);
            ExternalInterface.addCallback("playerSetUseHardwareVideoDecoder", _setUseHardwareVideoDecoder);
            ExternalInterface.addCallback("playerCapLeveltoStage", _setCapLeveltoStage);
            ExternalInterface.addCallback("playerSetAudioTrack", _setAudioTrack);
            ExternalInterface.addCallback("playerSetJSURLStream", _setJSURLStream);
        };

        protected function _setupStage() : void {
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.align = StageAlign.TOP_LEFT;
            stage.fullScreenSourceRect = new Rectangle(0, 0, stage.stageWidth, stage.stageHeight);
            stage.addEventListener(StageVideoAvailabilityEvent.STAGE_VIDEO_AVAILABILITY, _onStageVideoState);
            stage.addEventListener(Event.RESIZE, _onStageResize);
        }

        protected function _setupSheet() : void {
            // Draw sheet for catching clicks
            _sheet = new Sprite();
            _sheet.graphics.beginFill(0x000000, 0);
            _sheet.graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
            _sheet.addEventListener(MouseEvent.CLICK, _clickHandler);
            _sheet.buttonMode = true;
            addChild(_sheet);
        }

        /** Notify javascript the framework is ready. **/
        protected function _pingJavascript() : void {
            ExternalInterface.call("flashlsEvents.onHLSReady", ExternalInterface.objectID);
        };

        /** Forward events from the framework. **/
        protected function _completeHandler(event : AdaptiveEvent) : void {
            if (ExternalInterface.available) {

                ExternalInterface.call("flashlsEvents.onComplete", ExternalInterface.objectID);

            }
        };

        protected function _errorHandler(event : AdaptiveEvent) : void {
            if (ExternalInterface.available) {
                var hlsError : AdaptiveError = event.error;
                ExternalInterface.call("flashlsEvents.onError", ExternalInterface.objectID, hlsError.code, hlsError.url, hlsError.msg);
            }
        };

        protected function _fragmentLoadedHandler(event : AdaptiveEvent) : void {
            if (ExternalInterface.available) {
                ExternalInterface.call("flashlsEvents.onFragmentLoaded", ExternalInterface.objectID, event.loadMetrics);
            }
        };

        protected function _fragmentPlayingHandler(event : AdaptiveEvent) : void {
            if (ExternalInterface.available) {
                ExternalInterface.call("flashlsEvents.onFragmentPlaying", ExternalInterface.objectID, event.playMetrics);
            }
        };

        protected function _manifestHandler(event : AdaptiveEvent) : void {
            _duration = event.levels[_adaptive.startlevel].duration;

            if (_autoLoad) {
                _play(-1);
            }

            if (ExternalInterface.available) {
                ExternalInterface.call("flashlsEvents.onManifest", ExternalInterface.objectID, _duration);
            }
        };

        protected function _mediaTimeHandler(event : AdaptiveEvent) : void {
            _duration = event.mediatime.duration;
            _media_position = event.mediatime.position;
            if (ExternalInterface.available) {
                ExternalInterface.call("flashlsEvents.onPosition", ExternalInterface.objectID, event.mediatime);
            }

            var videoWidth : int = _video ? _video.videoWidth : _stageVideo.videoWidth;
            var videoHeight : int = _video ? _video.videoHeight : _stageVideo.videoHeight;

            if (videoWidth && videoHeight) {
                var changed : Boolean = _videoWidth != videoWidth || _videoHeight != videoHeight;
                if (changed) {
                    _videoHeight = videoHeight;
                    _videoWidth = videoWidth;
                    _resize();
                    if (ExternalInterface.available) {
                        ExternalInterface.call("flashlsEvents.onVideoSize", ExternalInterface.objectID, _videoWidth, _videoHeight);
                    }
                }
            }
        };

        protected function _stateHandler(event : AdaptiveEvent) : void {
            if (ExternalInterface.available) {
                ExternalInterface.call("flashlsEvents.onState", ExternalInterface.objectID, event.state);
            }
        };

        protected function _levelSwitchHandler(event : AdaptiveEvent) : void {
            if (ExternalInterface.available) {
                ExternalInterface.call("flashlsEvents.onSwitch", ExternalInterface.objectID, event.level);
            }
        };

        protected function _audioTracksListChange(event : AdaptiveEvent) : void {
            if (ExternalInterface.available) {
                ExternalInterface.call("flashlsEvents.onAudioTracksListChange", ExternalInterface.objectID, _getAudioTrackList());
            }
        }

        protected function _audioTrackChange(event : AdaptiveEvent) : void {
            if (ExternalInterface.available) {
                ExternalInterface.call("flashlsEvents.onAudioTrackChange", ExternalInterface.objectID, event.audioTrack);
            }
        }

        /** Javascript getters. **/
        protected function _getLevel() : int {
            return _adaptive.level;
        };

        protected function _getPlaybackLevel() : int {
            return _adaptive.playbacklevel;
        };

        protected function _getLevels() : Vector.<Level> {
            return _adaptive.levels;
        };

        protected function _getAutoLevel() : Boolean {
            return _adaptive.autolevel;
        };

        protected function _getDuration() : Number {
            return _duration;
        };

        protected function _getPosition() : Number {
            return _adaptive.position;
        };

        protected function _getPlaybackState() : String {
            return _adaptive.playbackState;
        };

        protected function _getSeekState() : String {
            return _adaptive.seekState;
        };

        protected function _getType() : String {
            return _adaptive.type;
        };

        protected function _getbufferLength() : Number {
            return _adaptive.bufferLength;
        };

        protected function _getmaxBufferLength() : Number {
            return AdaptiveSettings.maxBufferLength;
        };

        protected function _getminBufferLength() : Number {
            return AdaptiveSettings.minBufferLength;
        };

        protected function _getlowBufferLength() : Number {
            return AdaptiveSettings.lowBufferLength;
        };

        protected function _getmaxBackBufferLength() : Number {
            return AdaptiveSettings.maxBackBufferLength;
        };

        protected function _getflushLiveURLCache() : Boolean {
            return AdaptiveSettings.flushLiveURLCache;
        };

        protected function _getstartFromLevel() : int {
            return AdaptiveSettings.startFromLevel;
        };

        protected function _getseekFromLevel() : int {
            return AdaptiveSettings.seekFromLevel;
        };

        protected function _getLogDebug() : Boolean {
            return AdaptiveSettings.logDebug;
        };

        protected function _getLogDebug2() : Boolean {
            return AdaptiveSettings.logDebug2;
        };

        protected function _getUseHardwareVideoDecoder() : Boolean {
            return AdaptiveSettings.useHardwareVideoDecoder;
        };

        protected function _getCapLeveltoStage() : Boolean {
            return AdaptiveSettings.capLevelToStage;
        };

        protected function _getJSURLStream() : Boolean {
            return (_adaptive.URLstream is JSURLStream);
        };

        protected function _getPlayerVersion() : Number {
            return 2;
        };

        protected function _getAudioTrackList() : Array {
            var list : Array = [];
            var vec : Vector.<AudioTrack> = _adaptive.audioTracks;
            for (var i : Object in vec) {
                list.push(vec[i]);
            }
            return list;
        };

        protected function _getAudioTrackId() : int {
            return _adaptive.audioTrack;
        };

        /** Javascript calls. **/
        protected function _load(url : String) : void {
            _adaptive.load(url);
        };

        protected function _play(position : Number = -1) : void {
            _adaptive.stream.play(null, position);
        };

        protected function _pause() : void {
            _adaptive.stream.pause();
        };

        protected function _resume() : void {
            _adaptive.stream.resume();
        };

        protected function _seek(position : Number) : void {
            _adaptive.stream.seek(position);
        };

        protected function _stop() : void {
            _adaptive.stream.close();
        };

        protected function _volume(percent : Number) : void {
            _adaptive.stream.soundTransform = new SoundTransform(percent / 100);
        };

        protected function _setLevel(level : int) : void {
            _smoothSetLevel(level);
            if (!isNaN(_media_position) && level != -1) {
                _adaptive.stream.seek(_media_position);
            }
        };

        protected function _smoothSetLevel(level : int) : void {
            if (level != _adaptive.level) {
                _adaptive.level = level;
            }
        };

        protected function _setmaxBufferLength(new_len : Number) : void {
            AdaptiveSettings.maxBufferLength = new_len;
        };

        protected function _setminBufferLength(new_len : Number) : void {
            AdaptiveSettings.minBufferLength = new_len;
        };

        protected function _setlowBufferLength(new_len : Number) : void {
            AdaptiveSettings.lowBufferLength = new_len;
        };

        protected function _setbackBufferLength(new_len : Number) : void {
            AdaptiveSettings.maxBackBufferLength = new_len;
        };

        protected function _setflushLiveURLCache(flushLiveURLCache : Boolean) : void {
            AdaptiveSettings.flushLiveURLCache = flushLiveURLCache;
        };

        protected function _setstartFromLevel(startFromLevel : int) : void {
            AdaptiveSettings.startFromLevel = startFromLevel;
        };

        protected function _setseekFromLevel(seekFromLevel : int) : void {
            AdaptiveSettings.seekFromLevel = seekFromLevel;
        };

        protected function _setLogDebug(debug : Boolean) : void {
            AdaptiveSettings.logDebug = debug;
        };

        protected function _setLogDebug2(debug2 : Boolean) : void {
            AdaptiveSettings.logDebug2 = debug2;
        };

        protected function _setUseHardwareVideoDecoder(value : Boolean) : void {
            AdaptiveSettings.useHardwareVideoDecoder = value;
        };

        protected function _setCapLeveltoStage(value : Boolean) : void {
            AdaptiveSettings.capLevelToStage = value;
        };

        protected function _setJSURLStream(jsURLstream : Boolean) : void {
            if (jsURLstream) {
                _adaptive.URLstream = JSURLStream as Class;
            } else {
                _adaptive.URLstream = URLStream as Class;
            }
        };

        protected function _setAudioTrack(val : int) : void {
            if (val == _adaptive.audioTrack) return;
            _adaptive.audioTrack = val;
            if (!isNaN(_media_position)) {
                _adaptive.stream.seek(_media_position);
            }
        };

        /** Mouse click handler. **/
        protected function _clickHandler(event : MouseEvent) : void {
            if (stage.displayState == StageDisplayState.FULL_SCREEN_INTERACTIVE || stage.displayState == StageDisplayState.FULL_SCREEN) {
                stage.displayState = StageDisplayState.NORMAL;
            } else {
                stage.displayState = StageDisplayState.FULL_SCREEN;
            }
        };

        /** StageVideo detector. **/
        protected function _onStageVideoState(event : StageVideoAvailabilityEvent) : void {
            var available : Boolean = (event.availability == StageVideoAvailability.AVAILABLE);
            CONFIG::HLS {
                _adaptive = new HLS();
            }
            CONFIG::DASH {
                _adaptive = new Dash();
            }
            _adaptive.stage = stage;
            _adaptive.addEventListener(AdaptiveEvent.PLAYBACK_COMPLETE, _completeHandler);
            _adaptive.addEventListener(AdaptiveEvent.ERROR, _errorHandler);
            _adaptive.addEventListener(AdaptiveEvent.FRAGMENT_LOADED, _fragmentLoadedHandler);
            _adaptive.addEventListener(AdaptiveEvent.FRAGMENT_PLAYING, _fragmentPlayingHandler);
            _adaptive.addEventListener(AdaptiveEvent.MANIFEST_LOADED, _manifestHandler);
            _adaptive.addEventListener(AdaptiveEvent.MEDIA_TIME, _mediaTimeHandler);
            _adaptive.addEventListener(AdaptiveEvent.PLAYBACK_STATE, _stateHandler);
            _adaptive.addEventListener(AdaptiveEvent.LEVEL_SWITCH, _levelSwitchHandler);
            _adaptive.addEventListener(AdaptiveEvent.AUDIO_TRACKS_LIST_CHANGE, _audioTracksListChange);
            _adaptive.addEventListener(AdaptiveEvent.AUDIO_TRACK_SWITCH, _audioTrackChange);

            if (available && stage.stageVideos.length > 0) {
                _stageVideo = stage.stageVideos[0];
                _stageVideo.addEventListener(StageVideoEvent.RENDER_STATE, _onStageVideoStateChange)
                _stageVideo.viewPort = new Rectangle(0, 0, stage.stageWidth, stage.stageHeight);
                _stageVideo.attachNetStream(_adaptive.stream);
            } else {
                _video = new Video(stage.stageWidth, stage.stageHeight);
                _video.addEventListener(VideoEvent.RENDER_STATE, _onVideoStateChange);
                addChild(_video);
                _video.smoothing = true;
                _video.attachNetStream(_adaptive.stream);
            }
            stage.removeEventListener(StageVideoAvailabilityEvent.STAGE_VIDEO_AVAILABILITY, _onStageVideoState);

            var autoLoadUrl : String = root.loaderInfo.parameters.url as String;
            if (autoLoadUrl != null) {
                _autoLoad = true;
                _load(autoLoadUrl);
            }
        };

        private function _onStageVideoStateChange(event : StageVideoEvent) : void {
            Log.info("Video decoding:" + event.status);
        }

        private function _onVideoStateChange(event : VideoEvent) : void {
            Log.info("Video decoding:" + event.status);
        }

        protected function _onStageResize(event : Event) : void {
            stage.fullScreenSourceRect = new Rectangle(0, 0, stage.stageWidth, stage.stageHeight);
            _sheet.width = stage.stageWidth;
            _sheet.height = stage.stageHeight;
            _resize();
        };

        protected function _resize() : void {
            var rect : Rectangle;
            rect = ScaleVideo.resizeRectangle(_videoWidth, _videoHeight, stage.stageWidth, stage.stageHeight);
            // resize video
            if (_video) {
                _video.width = rect.width;
                _video.height = rect.height;
                _video.x = rect.x;
                _video.y = rect.y;
            } else if (_stageVideo && rect.width > 0) {
                _stageVideo.viewPort = rect;
            }
        }
    }
}
