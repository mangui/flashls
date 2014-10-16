package org.mangui.flowplayer {
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.utils.Params2Settings;

    import flash.display.DisplayObject;
    import flash.net.NetConnection;
    import flash.net.NetStream;
    import flash.utils.Dictionary;
    import flash.media.Video;

    import org.mangui.hls.HLS;
    import org.mangui.hls.constant.HLSPlayStates;

    import org.flowplayer.model.Plugin;
    import org.flowplayer.model.PluginModel;
    import org.flowplayer.view.Flowplayer;
    import org.flowplayer.controller.StreamProvider;
    import org.flowplayer.controller.TimeProvider;
    import org.flowplayer.controller.VolumeController;
    import org.flowplayer.model.Clip;
    import org.flowplayer.model.ClipType;
    import org.flowplayer.model.ClipEvent;
    import org.flowplayer.model.ClipEventType;
    import org.flowplayer.model.Playlist;
    import org.flowplayer.view.StageVideoWrapper;
    
    CONFIG::LOGGING {
    import org.mangui.hls.utils.Log;
    }

    public class HLSStreamProvider  implements StreamProvider,Plugin {
        private var _volumecontroller : VolumeController;
        private var _playlist : Playlist;
        private var _timeProvider : TimeProvider;
        private var _model : PluginModel;
        private var _player : Flowplayer;
        private var _clip : Clip;
        private var _video : Video;
        /** reference to the framework. **/
        private var _hls : HLS;
        // event values
        private var _position : Number = 0;
        private var _duration : Number = 0;
        private var _bufferedTime : Number = 0;
        private var _videoWidth : int = -1;
        private var _videoHeight : int = -1;
        private var _isManifestLoaded : Boolean = false;
        private var _pauseAfterStart : Boolean;
        private var _seekable : Boolean = false;

        public function getDefaultConfig() : Object {
            return null;
        }

        public function onConfig(model : PluginModel) : void {
            CONFIG::LOGGING {
            Log.info("onConfig()");
            }
            _model = model;
        }

        public function onLoad(player : Flowplayer) : void {
            CONFIG::LOGGING {
            Log.info("onLoad()");
            }
            _player = player;
            _hls = new HLS();
            _hls.stage = player.screen.getDisplayObject().stage;
            _hls.addEventListener(HLSEvent.PLAYBACK_COMPLETE, _completeHandler);
            _hls.addEventListener(HLSEvent.ERROR, _errorHandler);
            _hls.addEventListener(HLSEvent.MANIFEST_LOADED, _manifestHandler);
            _hls.addEventListener(HLSEvent.MEDIA_TIME, _mediaTimeHandler);
            _hls.addEventListener(HLSEvent.PLAYBACK_STATE, _stateHandler);

            var cfg : Object = _model.config;
            for (var object : String in cfg) {
                var subidx : int = object.indexOf("hls_");
                if (subidx != -1) {
                    Params2Settings.set(object.substr(4), cfg[object]);
                }
            }

            _model.dispatchOnLoad();
        }

        private function _completeHandler(event : HLSEvent) : void {
            // dispatch a before event because the finish has default behavior that can be prevented by listeners
            _clip.dispatchBeforeEvent(new ClipEvent(ClipEventType.FINISH));
        };

        private function _errorHandler(event : HLSEvent) : void {
        };

        private function _manifestHandler(event : HLSEvent) : void {
            _duration = event.levels[_hls.startlevel].duration;
            _isManifestLoaded = true;
            _clip.duration = _duration;
            _clip.stopLiveOnPause = false;
            _clip.dispatch(ClipEventType.METADATA);
            _seekable = true;
            // if (_hls.type == HLSTypes.LIVE) {
            // _seekable = false;
            // } else {
            // _seekable = true;
            // }
            _hls.stream.play();
            _clip.dispatch(ClipEventType.SEEK);
            if (_pauseAfterStart) {
                _hls.stream.pause();
            }
        };

        private function _mediaTimeHandler(event : HLSEvent) : void {
            _position = Math.max(0, event.mediatime.position);
            _duration = event.mediatime.duration;
            _clip.duration = _duration;
            _bufferedTime = event.mediatime.buffer + event.mediatime.position;
            var videoWidth : int = _video.videoWidth;
            var videoHeight : int = _video.videoHeight;
            if (videoWidth && videoHeight) {
                var changed : Boolean = _videoWidth != videoWidth || _videoHeight != videoHeight;
                if (changed) {
                    CONFIG::LOGGING {
                    Log.info("video size changed to " + videoWidth + "/" + videoHeight);
                    }
                    _videoWidth = videoWidth;
                    _videoHeight = videoHeight;
                    _clip.originalWidth = videoWidth;
                    _clip.originalHeight = videoHeight;
                    _clip.dispatch(ClipEventType.START);
                    _clip.dispatch(ClipEventType.METADATA_CHANGED);
                }
            }
        };

        private function _stateHandler(event : HLSEvent) : void {
            // CONFIG::LOGGING {
            // Log.txt("state:"+ event.state);
            // }
            switch(event.state) {
                case HLSPlayStates.IDLE:
                case HLSPlayStates.PLAYING:
                    _clip.dispatch(ClipEventType.BUFFER_FULL);
                    break;
                case HLSPlayStates.PLAYING_BUFFERING:
                    _clip.dispatch(ClipEventType.BUFFER_EMPTY);
                    break;
                case HLSPlayStates.PAUSED_BUFFERING:
                    _clip.dispatch(ClipEventType.BUFFER_EMPTY);
                    _clip.dispatch(ClipEventType.PAUSE);
                    break;
                case HLSPlayStates.PAUSED:
                    _clip.dispatch(ClipEventType.BUFFER_FULL);
                    _clip.dispatch(ClipEventType.PAUSE);
                    break;
            }
        };

        /**
         * Starts loading the specified clip. Once video data is available the provider
         * must set it to the clip using <code>clip.setContent()</code>. Typically the video
         * object passed to the clip is an instance of <a href="http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/media/Video.html">flash.media.Video</a>.
         *
         * @param event the event that this provider should dispatch once loading has successfully started,
         * once dispatched the player will call <code>getVideo()</code>
         * @param clip the clip to load
         * @param pauseAfterStart if <code>true</code> the playback is paused on first frame and
         * buffering is continued
         * @see Clip#setContent()
         * @see #getVideo()
         */
        public function load(event : ClipEvent, clip : Clip, pauseAfterStart : Boolean = true) : void {
            _clip = clip;
            CONFIG::LOGGING {
            Log.info("load()" + clip.completeUrl);
            }
            _hls.load(clip.completeUrl);
            _pauseAfterStart = pauseAfterStart;
            clip.type = ClipType.VIDEO;
            clip.dispatch(ClipEventType.BEGIN);
            clip.setNetStream(_hls.stream);
            return;
        }

        /**
         * Gets the <a href="http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/media/Video.html">Video</a> object.
         * A stream will be attached to the returned video object using <code>attachStream()</code>.
         * @param clip the clip for which the Video object is queried for
         * @see #attachStream()
         */
        public function getVideo(clip : Clip) : DisplayObject {
            CONFIG::LOGGING {
            Log.debug("getVideo()");
            }
            if (_video == null) {
                if (clip.useStageVideo) {
                    CONFIG::LOGGING {
                    Log.debug("useStageVideo");
                    }
                    _video = new StageVideoWrapper(clip);
                } else {
                    _video = new Video();
                    _video.smoothing = clip.smoothing;
                }
            }
            return _video;
        }

        /**
         * Attaches a stream to the specified display object.
         * @param video the video object that was originally retrieved using <code>getVideo()</code>.
         * @see #getVideo()
         */
        public function attachStream(video : DisplayObject) : void {
            CONFIG::LOGGING {
            Log.debug("attachStream()");
            }
            Video(video).attachNetStream(_hls.stream);
            return;
        }

        /**
         * Pauses playback.
         * @param event the event that this provider should dispatch once loading has been successfully paused
         */
        public function pause(event : ClipEvent) : void {
            CONFIG::LOGGING {
            Log.info("pause()");
            }
            _hls.stream.pause();
            return;
        }

        /**
         * Resumes playback.
         * @param event the event that this provider should dispatch once loading has been successfully resumed
         */
        public function resume(event : ClipEvent) : void {
            CONFIG::LOGGING {
            Log.info("resume()");
            }
            _hls.stream.resume();
            _clip.dispatch(ClipEventType.RESUME);
            return;
        }

        /**
         * Stops and rewinds to the beginning of current clip.
         * @param event the event that this provider should dispatch once loading has been successfully stopped
         */
        public function stop(event : ClipEvent, closeStream : Boolean = false) : void {
            CONFIG::LOGGING {
            Log.info("stop()");
            }
            _hls.stream.close();
            return;
        }

        /**
         * Seeks to the specified point in the timeline.
         * @param event the event that this provider should dispatch once the seek is in target
         * @param seconds the target point in the timeline
         */
        public function seek(event : ClipEvent, seconds : Number) : void {
            CONFIG::LOGGING {
            Log.info("seek()");
            }
            _hls.stream.seek(seconds);
            _position = seconds;
            _bufferedTime = seconds;
            _clip.dispatch(ClipEventType.SEEK, seconds);
            return;
        }

        /**
         * File size in bytes.
         */
        public function get fileSize() : Number {
            return 0;
        }

        /**
         * Current playhead time in seconds.
         */
        public function get time() : Number {
            return _position;
        }

        /**
         * The point in timeline where the buffered data region begins, in seconds.
         */
        public function get bufferStart() : Number {
            return 0;
        }

        /**
         * The point in timeline where the buffered data region ends, in seconds.
         */
        public function get bufferEnd() : Number {
            return _bufferedTime;
        }

        /**
         * Does this provider support random seeking to unbuffered areas in the timeline?
         */
        public function get allowRandomSeek() : Boolean {
            // CONFIG::LOGGING {
            // Log.info("allowRandomSeek()");
            // }
            return _seekable;
        }

        /**
         * Volume controller used to control the video volume.
         */
        public function set volumeController(controller : VolumeController) : void {
            _volumecontroller = controller;
            _volumecontroller.netStream = _hls.stream;
            return;
        }

        /**
         * Is this provider in the process of stopping the stream?
         * When stopped the provider should not dispatch any events resulting from events that
         * might get triggered by the underlying streaming implementation.
         */
        public function get stopping() : Boolean {
            CONFIG::LOGGING {
            Log.info("stopping()");
            }
            return false;
        }

        /**
         * The playlist instance.
         */
        public function set playlist(playlist : Playlist) : void {
            // CONFIG::LOGGING {
            // Log.debug("set playlist()");
            // }
            _playlist = playlist;
            return;
        }

        public function get playlist() : Playlist {
            CONFIG::LOGGING {
            Log.debug("get playlist()");
            }
            return _playlist;
        }

        /**
         * Adds a callback public function to the NetConnection instance. This public function will fire ClipEvents whenever
         * the callback is invoked in the connection.
         * @param name
         * @param listener
         * @return
         * @see ClipEventType#CONNECTION_EVENT
         */
        public function addConnectionCallback(name : String, listener : Function) : void {
            CONFIG::LOGGING {
            Log.debug("addConnectionCallback()");
            }
            return;
        }

        /**
         * Adds a callback public function to the NetStream object. This public function will fire a ClipEvent of type StreamEvent whenever
         * the callback has been invoked on the stream. The invokations typically come from a server-side app running
         * on RTMP server.
         * @param name
         * @param listener
         * @return
         * @see ClipEventType.NETSTREAM_EVENT
         */
        public function addStreamCallback(name : String, listener : Function) : void {
            CONFIG::LOGGING {
            Log.debug("addStreamCallback()");
            }
            return;
        }

        /**
         * Get the current stream callbacks.
         * @return a dictionary of callbacks, keyed using callback names and values being the callback functions
         */
        public function get streamCallbacks() : Dictionary {
            CONFIG::LOGGING {
            Log.debug("get streamCallbacks()");
            }
            return null;
        }

        /**
         * Gets the underlying NetStream object.
         * @return the netStream currently in use, or null if this provider has not started streaming yet
         */
        public function get netStream() : NetStream {
            CONFIG::LOGGING {
            Log.debug("get netStream()");
            }
            return _hls.stream;
        }

        /**
         * Gets the underlying netConnection object.
         * @return the netConnection currently in use, or null if this provider has not started streaming yet
         */
        public function get netConnection() : NetConnection {
            CONFIG::LOGGING {
            Log.debug("get netConnection()");
            }
            return null;
        }

        /**
         * Sets a time provider to be used by this StreamProvider. Normally the playhead time is queried from
         * the NetStream.time property.
         *
         * @param timeProvider
         */
        public function set timeProvider(timeProvider : TimeProvider) : void {
            CONFIG::LOGGING {
            Log.debug("set timeProvider()");
            }
            _timeProvider = timeProvider;
            return;
        }

        /**
         * Gets the type of StreamProvider either http, rtmp, psuedo.
         */
        public function get type() : String {
            return "httpstreaming";
        }

        /**
         * Switch the stream in realtime with / without dynamic stream switching support
         *
         * @param event ClipEvent the clip event
         * @param clip Clip the clip to switch to
         * @param netStreamPlayOptions Object the NetStreamPlayOptions object to enable dynamic stream switching
         */
        public function switchStream(event : ClipEvent, clip : Clip, netStreamPlayOptions : Object = null) : void {
            CONFIG::LOGGING {
            Log.info("switchStream()");
            }
            return;
        }
    }
}
