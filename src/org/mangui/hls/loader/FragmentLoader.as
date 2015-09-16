/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.loader {

    import flash.events.*;
    import flash.net.*;
    import flash.utils.ByteArray;
    import flash.utils.getTimer;
    import flash.utils.Timer;
    import org.mangui.hls.constant.HLSLoaderTypes;
    import org.mangui.hls.constant.HLSTypes;
    import org.mangui.hls.controller.AudioTrackController;
    import org.mangui.hls.controller.LevelController;
    import org.mangui.hls.demux.Demuxer;
    import org.mangui.hls.demux.DemuxHelper;
    import org.mangui.hls.demux.ID3Tag;
    import org.mangui.hls.event.HLSError;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.event.HLSLoadMetrics;
    import org.mangui.hls.flv.FLVTag;
    import org.mangui.hls.HLS;
    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.model.AudioTrack;
    import org.mangui.hls.model.Fragment;
    import org.mangui.hls.model.FragmentData;
    import org.mangui.hls.model.Level;
    import org.mangui.hls.stream.StreamBuffer;
    import org.mangui.hls.utils.AES;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
        import org.mangui.hls.utils.Hex;
    }
    /** Class that fetches fragments. **/
    public class FragmentLoader {
        /** Reference to the HLS controller. **/
        private var _hls : HLS;
        /** reference to auto level manager */
        private var _levelController : LevelController;
        /** reference to audio track controller */
        private var _audioTrackController : AudioTrackController;
        /** has manifest just being reloaded **/
        private var _manifestJustLoaded : Boolean;
        /** last loaded level. **/
        private var _levelLastLoaded : int;
        /** next level (-1 if not defined yet) **/
        private var _levelNext : int = -1;
        /** Reference to the manifest levels. **/
        private var _levels : Vector.<Level>;
        /** Util for loading the fragment. **/
        private var _fragstreamloader : URLStream;
        /** Util for loading the key. **/
        private var _keystreamloader : URLStream;
        /** key map **/
        private var _keymap : Object;
        /** Did the stream switch quality levels. **/
        private var _switchLevel : Boolean;
        /** Did a discontinuity occurs in the stream **/
        private var _hasDiscontinuity : Boolean;
        /** boolean to track whether PTS analysis is ongoing or not */
        private var _ptsAnalyzing : Boolean = false;
        /** Timer used to monitor/schedule fragment download. **/
        private var _timer : Timer;
        /** requested seek position **/
        private var _seekPosition : Number;
        /** first fragment loaded ? **/
        private var _fragmentFirstLoaded : Boolean;
        /* demux instance */
        private var _demux : Demuxer;
        /* stream buffer instance **/
        private var _streamBuffer : StreamBuffer;
        /* key error/reload */
        private var _keyLoadErrorDate : Number;
        private var _keyRetryTimeout : Number;
        private var _keyRetryCount : int;
        private var _keyLoadStatus : int;
        /* fragment error/reload */
        private var _fragLoadErrorDate : Number;
        private var _fragRetryTimeout : Number;
        private var _fragRetryCount : int;
        private var _fragLoadStatus : int;
        private var _fragSkipping : Boolean;
        /** reference to previous/current fragment */
        private var _fragPrevious : Fragment;
        private var _fragCurrent : Fragment;
        /* loading state variable */
        private var _loadingState : int;
        /* loading metrics */
        private var _metrics : HLSLoadMetrics;
        private static const LOADING_STOPPED : int = -1;
        private static const LOADING_IDLE : int = 0;
        private static const LOADING_IN_PROGRESS : int = 1;
        private static const LOADING_WAITING_LEVEL_UPDATE : int = 2;
        private static const LOADING_STALLED : int = 3;
        private static const LOADING_FRAGMENT_IO_ERROR : int = 4;
        private static const LOADING_KEY_IO_ERROR : int = 5;
        private static const LOADING_COMPLETED : int = 6;

        /** Create the loader. **/
        public function FragmentLoader(hls : HLS, audioTrackController : AudioTrackController, levelController : LevelController, streamBuffer : StreamBuffer) : void {
            _hls = hls;
            _levelController = levelController;
            _audioTrackController = audioTrackController;
            _streamBuffer = streamBuffer;
            _hls.addEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.addEventListener(HLSEvent.LEVEL_LOADED, _levelLoadedHandler);
            _timer = new Timer(20, 0);
            _timer.addEventListener(TimerEvent.TIMER, _checkLoading);
            _loadingState = LOADING_STOPPED;
            _manifestJustLoaded = false;
            _keymap = new Object();
        };

        public function dispose() : void {
            stop();
            _hls.removeEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.removeEventListener(HLSEvent.LEVEL_LOADED, _levelLoadedHandler);
            _loadingState = LOADING_STOPPED;
            _keymap = new Object();
        }

        public function get audioExpected() : Boolean {
            if (_demux) {
                return _demux.audioExpected;
            } else {
                // always return true in case demux is not yet initialized
                return true;
            }
        }

        public function get videoExpected() : Boolean {
            if (_demux) {
                return _demux.videoExpected;
            } else {
                // always return true in case demux is not yet initialized
                return true;
            }
        }

        /**  fragment loading Timer **/
        private function _checkLoading(e : Event) : void {
            switch(_loadingState) {
                // nothing to load, stop fragment loader.
                case LOADING_STOPPED:
                    stop();
                    break;
                // nothing to load until level is retrieved
                case LOADING_WAITING_LEVEL_UPDATE:
                    break;
                // loading already in progress
                case LOADING_IN_PROGRESS:
                    // only monitor fragment loading rate if in auto mode, and current level is not the lowest level
                    if(_hls.autoLevel && _fragCurrent.level) {
                        // monitor fragment load progress after half of expected fragment duration,to stabilize bitrate
                        var requestDelay : int = getTimer() - _metrics.loading_request_time;
                        var fragDuration : Number = _fragCurrent.duration;
                        if(requestDelay > 500*fragDuration) {
                            var loaded : int = _fragCurrent.data.bytesLoaded;
                            var expected : int = fragDuration*_levels[_fragCurrent.level].bitrate/8;
                            if(expected < loaded) {
                                expected = loaded;
                            }
                            var loadRate : int = loaded*1000/requestDelay; // byte/s
                            var fragLoadedDelay : Number =(expected-loaded)/loadRate;
                            var fragLevel0LoadedDelay : Number = fragDuration*_levels[0].bitrate/(8*loadRate); //bps/Bps
                            var bufferLen : Number = _hls.stream.bufferLength;
                            // CONFIG::LOGGING {
                            //     Log.info("bufferLen/fragDuration/fragLoadedDelay/fragLevel0LoadedDelay:" + bufferLen.toFixed(1) + "/" + fragDuration.toFixed(1) + "/" + fragLoadedDelay.toFixed(1) + "/" + fragLevel0LoadedDelay.toFixed(1));
                            // }
                            /* if we have less than 2 frag duration in buffer and if frag loaded delay is greater than buffer len
                              ... and also bigger than duration needed to load fragment at next level ...*/
                            if(bufferLen < 2*fragDuration && fragLoadedDelay > bufferLen && fragLoadedDelay > fragLevel0LoadedDelay) {
                                // abort fragment loading ...
                                CONFIG::LOGGING {
                                    Log.warn("_checkLoading : loading too slow, abort fragment loading");
                                    Log.warn("fragLoadedDelay/bufferLen/fragLevel0LoadedDelay:" + fragLoadedDelay.toFixed(1) + "/" + bufferLen.toFixed(1) + "/" + fragLevel0LoadedDelay.toFixed(1));
                                }
                                //abort fragment loading
                                _stop_load();
                                // fill loadMetrics so please LevelController that will adjust bw for next fragment
                                // fill theoritical value, assuming bw will remain as it is
                                _metrics.size = expected;
                                _metrics.duration = 1000*fragDuration;
                                _metrics.loading_end_time = _metrics.parsing_end_time = _metrics.loading_request_time + 1000*expected/loadRate;
                                _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOAD_EMERGENCY_ABORTED, _metrics));
                                _levelNext = _levelController.getnextlevel(_fragCurrent.level, bufferLen);
                              // switch back to IDLE state to request new fragment at lowest level
                              _loadingState = LOADING_IDLE;
                            }
                        }
                    }
                    break;
                // no loading in progress, try to load first/next fragment
                case LOADING_IDLE:
                    var level : int;
                    // check if first fragment after seek has been already loaded
                    if (_fragmentFirstLoaded == false) {
                        // select level for first fragment load
                        if(_levelNext != -1) {
                            level = _levelNext;
                        } else if (_hls.autoLevel) {
                            if (_manifestJustLoaded) {
                                level = _hls.startLevel;
                            } else {
                                if(_hls.stream.bufferLength) {
                                    // if buffer not empty, select level from heuristics
                                    level = _levelController.getnextlevel(_hls.loadLevel, _hls.stream.bufferLength);
                                } else {
                                    // if buffer empty, retrieve seek level
                                    level = _hls.seekLevel;
                                }
                            }
                        } else {
                            level = _hls.manualLevel;
                        }
                        if (level != _hls.loadLevel) {
                            _demux = null;
                            _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, level));
                        }
                        _switchLevel = true;

                        // check if we received playlist for choosen level. if live playlist, ensure that new playlist has been refreshed
                        if ((_levels[level].fragments.length == 0) || (_hls.type == HLSTypes.LIVE && _levelLastLoaded != level)) {
                            // playlist not yet received
                            CONFIG::LOGGING {
                                Log.debug("_checkLoading : playlist not received for level:" + level);
                            }
                            _loadingState = LOADING_WAITING_LEVEL_UPDATE;
                            _levelNext = level;
                        } else {
                            // just after seek, load first fragment
                            _loadingState = _loadfirstfragment(_seekPosition, level);
                        }

                        /* first fragment already loaded
                         * check if we need to load next fragment, do it only if buffer is NOT full
                         */
                    } else if (HLSSettings.maxBufferLength == 0 || _hls.stream.bufferLength < HLSSettings.maxBufferLength) {
                        // select level for next fragment load
                        if(_levelNext != -1) {
                            level = _levelNext;
                        } else if (_hls.autoLevel && _levels.length > 1 ) {
                            // select level from heuristics (current level / last fragment duration / buffer length)
                            level = _levelController.getnextlevel(_hls.loadLevel, _hls.stream.bufferLength);
                        } else if (_hls.autoLevel && _levels.length == 1 ) {
                            level = 0;
                        } else {
                            level = _hls.manualLevel;
                        }
                        // notify in case level switch occurs
                        if (level != _hls.loadLevel) {
                            _switchLevel = true;
                            _demux = null;
                            _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, level));
                        }
                        // check if we received playlist for choosen level. if live playlist, ensure that new playlist has been refreshed
                        if ((_levels[level].fragments.length == 0) || (_hls.type == HLSTypes.LIVE && _levelLastLoaded != level)) {
                            // playlist not yet received
                            CONFIG::LOGGING {
                                Log.debug("_checkLoading : playlist not received for level:" + level);
                            }
                            _loadingState = LOADING_WAITING_LEVEL_UPDATE;
                            _levelNext = level;
                        } else {
                            _loadingState = _loadnextfragment(level, _fragPrevious);
                        }
                    }
                    break;
                case LOADING_STALLED:
                    /* next consecutive fragment not found:
                    it could happen on live playlist :
                    - if bandwidth available is lower than lowest quality needed bandwidth
                    - after long pause
                    */
                    CONFIG::LOGGING {
                        Log.warn("loading stalled:stop fragment loading");
                    }
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.LIVE_LOADING_STALLED));
                    stop();
                    break;
                // if key loading failed
                case  LOADING_KEY_IO_ERROR:
                    // compare current date and next retry date.
                    if (getTimer() >= _keyLoadErrorDate) {
                        /* try to reload the key ...
                        calling _loadfragment will also reload key */
                        _loadfragment(_fragCurrent);
                        _loadingState = LOADING_IN_PROGRESS;
                    }
                    break;
                // if fragment loading failed
                case LOADING_FRAGMENT_IO_ERROR:
                    // compare current date and next retry date.
                    if (getTimer() >= _fragLoadErrorDate) {
                        /* try to reload fragment ... */
                        _loadfragment(_fragCurrent);
                        _loadingState = LOADING_IN_PROGRESS;
                    }
                    break;
                case LOADING_COMPLETED:
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.LAST_VOD_FRAGMENT_LOADED));
                    // stop fragment loader, as no other fragments can be loaded
                    stop();
                    break;
                default:
                    CONFIG::LOGGING {
                        Log.error("invalid loading state:" + _loadingState);
                    }
                    break;
            }
        }

        public function seek(position : Number) : void {
            CONFIG::LOGGING {
                Log.debug("FragmentLoader:seek(" + position.toFixed(2) + ")");
            }
            // reset IO Error when seeking
            _fragRetryCount = _keyRetryCount = 0;
            _fragRetryTimeout = _keyRetryTimeout = 1000;
            _loadingState = LOADING_IDLE;
            _seekPosition = position;
            _fragmentFirstLoaded = false;
            _fragPrevious = null;
            _fragSkipping = false;
            _levelNext = -1;
            _timer.start();
        }

        /** key load completed. **/
        private function _keyLoadCompleteHandler(event : Event) : void {
            if (_loadingState == LOADING_IDLE)
                return;
            CONFIG::LOGGING {
                Log.debug("key loading completed");
            }
            var hlsError : HLSError;
            // Collect key data
            if ( _keystreamloader.bytesAvailable == 16 ) {
                // load complete, reset retry counter
                _keyRetryCount = 0;
                _keyRetryTimeout = 1000;
                var keyData : ByteArray = new ByteArray();
                _keystreamloader.readBytes(keyData, 0, 0);
                _keymap[_fragCurrent.decrypt_url] = keyData;
                // now load fragment
                try {
                    CONFIG::LOGGING {
                        Log.debug("loading fragment:" + _fragCurrent.url);
                    }
                    _fragCurrent.data.bytes = null;
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOADING, _fragCurrent.url));
                    _fragstreamloader.load(new URLRequest(_fragCurrent.url));
                } catch (error : Error) {
                    hlsError = new HLSError(HLSError.FRAGMENT_LOADING_ERROR, _fragCurrent.url, error.message);
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
                }
            } else {
                hlsError = new HLSError(HLSError.KEY_PARSING_ERROR, _fragCurrent.decrypt_url, "invalid key size: received " + _keystreamloader.bytesAvailable + " / expected 16 bytes");
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
        };

        private function _keyLoadHTTPStatusHandler(event : HTTPStatusEvent) : void {
            _keyLoadStatus = event.status;
        }

        private function _keyhandleIOError(message : String) : void {
            CONFIG::LOGGING {
                Log.error("I/O Error while loading key:" + message);
            }
            if (HLSSettings.keyLoadMaxRetry == -1 || _keyRetryCount < HLSSettings.keyLoadMaxRetry) {
                _loadingState = LOADING_KEY_IO_ERROR;
                _keyLoadErrorDate = getTimer() + _keyRetryTimeout;
                CONFIG::LOGGING {
                    Log.warn("retry key load in " + _keyRetryTimeout + " ms, count=" + _keyRetryCount);
                }
                /* exponential increase of retry timeout, capped to keyLoadMaxRetryTimeout */
                _keyRetryCount++;
                _keyRetryTimeout = Math.min(HLSSettings.keyLoadMaxRetryTimeout, 2 * _keyRetryTimeout);
            } else {
                var hlsError : HLSError = new HLSError(HLSError.KEY_LOADING_ERROR, _fragCurrent.decrypt_url, "I/O Error :" + message);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
        }

        private function _fraghandleIOError(message : String) : void {
            /* usually, errors happen in two situations :
            - bad networks  : in that case, the second or third reload of URL should fix the issue
                               if loading retry still fails after HLSSettings.fragmentLoadMaxRetry, and
                               if (a) redundant stream(s) is/are available for that level, then try to switch
                               to that redundant stream instead.
            - live playlist : when we are trying to load an out of bound fragments : for example,
            the playlist on webserver is from SN [51-61]
            the one in memory is from SN [50-60], and we are trying to load SN50.
             */
            CONFIG::LOGGING {
                Log.error("I/O Error while loading fragment:" + message);
            }
            if (HLSSettings.fragmentLoadMaxRetry == -1 || _fragRetryCount < HLSSettings.fragmentLoadMaxRetry) {
                _loadingState = LOADING_FRAGMENT_IO_ERROR;
                _fragLoadErrorDate = getTimer() + _fragRetryTimeout;
                CONFIG::LOGGING {
                    Log.warn("retry fragment load in " + _fragRetryTimeout + " ms, count=" + _fragRetryCount);
                }
                /* exponential increase of retry timeout, capped to fragmentLoadMaxRetryTimeout */
                _fragRetryCount++;
                _fragRetryTimeout = Math.min(HLSSettings.fragmentLoadMaxRetryTimeout, 2 * _fragRetryTimeout);
            } else {
                var level : Level = _levels[_fragCurrent.level];
                // if we have redundant streams left for that level, switch to it
                if(level.redundantStreamId < level.redundantStreamsNb) {
                    CONFIG::LOGGING {
                        Log.warn("max load retry reached, switch to redundant stream");
                    }
                    level.redundantStreamId++;
                    _fragRetryCount = 0;
                    _fragRetryTimeout = 1000;
                    _loadingState = LOADING_IDLE;
                    // dispatch event to force redundant level loading
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, _fragCurrent.level));
                } else if(HLSSettings.fragmentLoadSkipAfterMaxRetry == true) {
                    /* check if loaded fragment is not the last one of a live playlist.
                        if it is the case, don't skip to next, as there is no next fragment :-)
                    */
                    if(_hls.type == HLSTypes.LIVE && _fragCurrent.seqnum == level.end_seqnum) {
                        _loadingState = LOADING_FRAGMENT_IO_ERROR;
                        _fragLoadErrorDate = getTimer() + _fragRetryTimeout;
                        CONFIG::LOGGING {
                            Log.warn("max load retry reached on last fragment of live playlist, retrying loading this one...");
                        }
                        /* exponential increase of retry timeout, capped to fragmentLoadMaxRetryTimeout */
                        _fragRetryCount++;
                        _fragRetryTimeout = Math.min(HLSSettings.fragmentLoadMaxRetryTimeout, 2 * _fragRetryTimeout);
                    } else {
                        CONFIG::LOGGING {
                            Log.warn("max fragment load retry reached, skip fragment and load next one");
                        }
                        var tags : Vector.<FLVTag> = tags = new Vector.<FLVTag>();
                        tags.push(_fragCurrent.getSkippedTag());
                        // send skipped FLV tag to StreamBuffer
                        _streamBuffer.appendTags(HLSLoaderTypes.FRAGMENT_MAIN,_fragCurrent.level,_fragCurrent.seqnum ,tags,_fragCurrent.data.pts_start_computed, _fragCurrent.data.pts_start_computed + 1000*_fragCurrent.duration, _fragCurrent.continuity, _fragCurrent.start_time);
                        _fragRetryCount = 0;
                        _fragRetryTimeout = 1000;
                        _fragPrevious = _fragCurrent;
                        _fragSkipping = true;
                        // set fragment first loaded to be true to ensure that we can skip first fragment as well
                        _fragmentFirstLoaded = true;
                        _loadingState = LOADING_IDLE;
                    }
                } else {
                    var hlsError : HLSError = new HLSError(HLSError.FRAGMENT_LOADING_ERROR, _fragCurrent.url, "I/O Error :" + message);
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
                }
            }
        }

        private function _fragLoadHTTPStatusHandler(event : HTTPStatusEvent) : void {
            _fragLoadStatus = event.status;
        }

        private function _fragLoadProgressHandler(event : ProgressEvent) : void {
            var fragData : FragmentData = _fragCurrent.data;
            if (fragData.bytes == null) {
                fragData.bytes = new ByteArray();
                fragData.bytesLoaded = 0;
                fragData.flushTags();
                _metrics.loading_begin_time = getTimer();

                // decrypt data if needed
                if (_fragCurrent.decrypt_url != null) {
                    _metrics.decryption_begin_time = getTimer();
                    fragData.decryptAES = new AES(_hls.stage, _keymap[_fragCurrent.decrypt_url], _fragCurrent.decrypt_iv, _fragDecryptProgressHandler, _fragDecryptCompleteHandler);
                    CONFIG::LOGGING {
                        Log.debug("init AES context");
                    }
                } else {
                    fragData.decryptAES = null;
                }
            }
            if (event.bytesLoaded > fragData.bytesLoaded
                && _fragstreamloader.bytesAvailable > 0) {  // prevent EOF error race condition
                var data : ByteArray = new ByteArray();
                _fragstreamloader.readBytes(data);
                fragData.bytesLoaded += data.length;
                // CONFIG::LOGGING {
                // Log.debug2("bytesLoaded/bytesTotal:" + event.bytesLoaded + "/" + event.bytesTotal);
                // }
                if (fragData.decryptAES != null) {
                    fragData.decryptAES.append(data);
                } else {
                    _fragDecryptProgressHandler(data);
                }
            }
        }

        /** frag load completed. **/
        private function _fragLoadCompleteHandler(event : Event) : void {
            // load complete, reset retry counter
            _fragRetryCount = 0;
            _fragRetryTimeout = 1000;
            var fragData : FragmentData = _fragCurrent.data;
            if (fragData.bytes == null) {
                CONFIG::LOGGING {
                    Log.warn("fragment size is null, invalid it and load next one");
                }
                _levels[_hls.loadLevel].updateFragment(_fragCurrent.seqnum, false);
                _loadingState = LOADING_IDLE;
                return;
            }
            CONFIG::LOGGING {
                Log.debug("loading completed");
            }
            _fragSkipping = false;
            _metrics.loading_end_time = getTimer();
            _metrics.size = fragData.bytesLoaded;

            var _loading_duration : uint = _metrics.loading_end_time - _metrics.loading_request_time;
            CONFIG::LOGGING {
                Log.debug("Loading       duration/RTT/length/speed:" + _loading_duration + "/" + (_metrics.loading_begin_time - _metrics.loading_request_time) + "/" + _metrics.size + "/" + Math.round((8000 * _metrics.size / _loading_duration) / 1024) + " kb/s");
            }
            if (fragData.decryptAES) {
                fragData.decryptAES.notifycomplete();
            } else {
                _fragDecryptCompleteHandler();
            }
        }

        private function _fragDecryptProgressHandler(data : ByteArray) : void {
            data.position = 0;
            var fragData : FragmentData = _fragCurrent.data;
            if (_metrics.parsing_begin_time ==0) {
                _metrics.parsing_begin_time = getTimer();
            }
            var bytes : ByteArray = fragData.bytes;
            if (_fragCurrent.byterange_start_offset != -1) {
                bytes.position = bytes.length;
                bytes.writeBytes(data);
                // if we have retrieved all the data, disconnect loader and notify fragment complete
                if (bytes.length >= _fragCurrent.byterange_end_offset) {
                    if (_fragstreamloader.connected) {
                        _fragstreamloader.close();
                        _fragLoadCompleteHandler(null);
                    }
                }
                /* dont do progressive parsing of segment with byte range option */
                return;
            }
            if (_demux == null) {
                /* probe file type */
                bytes.position = bytes.length;
                bytes.writeBytes(data);
                data = bytes;
                _demux = DemuxHelper.probe(data, _levels[_hls.loadLevel], _fragParsingAudioSelectionHandler, _fragParsingProgressHandler, _fragParsingCompleteHandler, _fragParsingVideoMetadataHandler, _fragParsingID3TagHandler, false);
            }
            if (_demux) {
                _demux.append(data);
            }
        }

        private function _fragDecryptCompleteHandler() : void {
            if (_loadingState == LOADING_IDLE)
                return;
            var fragData : FragmentData = _fragCurrent.data;

            if (fragData.decryptAES) {
                _metrics.decryption_end_time = getTimer();
                var decrypt_duration : Number = _metrics.decryption_end_time - _metrics.decryption_begin_time;
                CONFIG::LOGGING {
                    Log.debug("Decrypted     duration/length/speed:" + decrypt_duration + "/" + fragData.bytesLoaded + "/" + Math.round((8000 * fragData.bytesLoaded / decrypt_duration) / 1024) + " kb/s");
                }
                fragData.decryptAES = null;
            }

            // deal with byte range here
            if (_fragCurrent.byterange_start_offset != -1) {
                CONFIG::LOGGING {
                    Log.debug("trim byte range, start/end offset:" + _fragCurrent.byterange_start_offset + "/" + _fragCurrent.byterange_end_offset);
                }
                var bytes : ByteArray = new ByteArray();
                fragData.bytes.position = _fragCurrent.byterange_start_offset;
                fragData.bytes.readBytes(bytes, 0, _fragCurrent.byterange_end_offset - _fragCurrent.byterange_start_offset);
                _demux = DemuxHelper.probe(bytes, _levels[_hls.loadLevel], _fragParsingAudioSelectionHandler, _fragParsingProgressHandler, _fragParsingCompleteHandler, _fragParsingVideoMetadataHandler, _fragParsingID3TagHandler, false);
                if (_demux) {
                    bytes.position = 0;
                    _demux.append(bytes);
                }
            }

            if (_demux == null) {
                CONFIG::LOGGING {
                    Log.error("unknown fragment type");
                    if (HLSSettings.logDebug2) {
                        fragData.bytes.position = 0;
                        var bytes2 : ByteArray = new ByteArray();
                        fragData.bytes.readBytes(bytes2, 0, 512);
                        Log.debug2("frag dump(512 bytes)");
                        Log.debug2(Hex.fromArray(bytes2));
                    }
                }
                // invalid fragment
                _fraghandleIOError("invalid content received");
                fragData.bytes = null;
                return;
            }
            fragData.bytes = null;
            _demux.notifycomplete();
        }

        /** stop loading fragment **/
        public function stop() : void {
            _stop_load();
            _timer.stop();
            _loadingState = LOADING_STOPPED;
        }

        private function _stop_load() : void {
            if (_fragstreamloader && _fragstreamloader.connected) {
                _fragstreamloader.close();
            }
            if (_keystreamloader && _keystreamloader.connected) {
                _keystreamloader.close();
            }

            if (_demux) {
                _demux.cancel();
                _demux = null;
            }

            if (_fragCurrent) {
                var fragData : FragmentData = _fragCurrent.data;
                if (fragData.decryptAES) {
                    fragData.decryptAES.cancel();
                    fragData.decryptAES = null;
                }
                fragData.bytes = null;
            }
        }

        /** Catch IO and security errors. **/
        private function _keyLoadErrorHandler(event : ErrorEvent) : void {
            var txt : String;
            var code : int;
            if (event is SecurityErrorEvent) {
                txt = "Cannot load key: crossdomain access denied:" + event.text;
                code = HLSError.KEY_LOADING_CROSSDOMAIN_ERROR;
            } else {
                _keyhandleIOError("HTTP status:" + _keyLoadStatus + ",msg:" + event.text);
            }
        };

        /** Catch IO and security errors. **/
        private function _fragLoadErrorHandler(event : ErrorEvent) : void {
            if (event is SecurityErrorEvent) {
                var txt : String = "Cannot load fragment: crossdomain access denied:" + event.text;
                var hlsError : HLSError = new HLSError(HLSError.FRAGMENT_LOADING_CROSSDOMAIN_ERROR, _fragCurrent.url, txt);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            } else {
                _fraghandleIOError("HTTP status:" + _fragLoadStatus + ",msg:" + event.text);
            }
        };

        private function _loadfirstfragment(position : Number, level : int) : int {
            CONFIG::LOGGING {
                Log.debug("loadfirstfragment(" + position + ")");
            }
            var frag : Fragment = _levels[level].getFragmentBeforePosition(position);
            _hasDiscontinuity = true;
            CONFIG::LOGGING {
                Log.debug("Loading       " + frag.seqnum + " of [" + (_levels[level].start_seqnum) + "," + (_levels[level].end_seqnum) + "],level " + level);
            }
            _loadfragment(frag);
            return LOADING_IN_PROGRESS;
        }

        /** Load a fragment **/
        private function _loadnextfragment(level : int, frag_previous : Fragment) : int {
            CONFIG::LOGGING {
                Log.debug("loadnextfragment()");
            }
            var new_seqnum : Number;
            var last_seqnum : Number = -1;
            var log_prefix : String;
            var frag : Fragment;

            if (_switchLevel == false || frag_previous.continuity == -1) {
                last_seqnum = frag_previous.seqnum;
            } else {
                // level switch
                // trust program-time : if program-time defined in previous loaded fragment, try to find seqnum matching program-time in new level.
                if (frag_previous.program_date) {
                    last_seqnum = _levels[level].getSeqNumFromProgramDate(frag_previous.program_date);
                    CONFIG::LOGGING {
                        Log.debug("loadnextfragment : getSeqNumFromProgramDate(level,date,cc:" + level + "," + frag_previous.program_date + ")=" + last_seqnum);
                    }
                }
                if (last_seqnum == -1) {
                    // if we are here, it means that no program date info is available in the playlist. try to get last seqnum position from PTS + continuity counter
                    last_seqnum = _levels[level].getSeqNumNearestPTS(frag_previous.data.pts_start, frag_previous.continuity);
                    CONFIG::LOGGING {
                        Log.debug("loadnextfragment : getSeqNumNearestPTS(level,pts,cc:" + level + "," + frag_previous.data.pts_start + "," + frag_previous.continuity + ")=" + last_seqnum);
                    }
                    if (last_seqnum == Number.POSITIVE_INFINITY) {
                        /* requested PTS above max PTS of this level:
                         * this case could happen when switching level at the edge of live playlist,
                         * in case playlist of new level is outdated
                         * return 1 to retry loading later.
                         */
                        return LOADING_WAITING_LEVEL_UPDATE;
                    } else if (last_seqnum == -1) {
                        // if we are here, it means that we have no PTS info for this continuity index, we need to do some PTS probing to find the right seqnum
                        /* we need to perform PTS analysis on fragments from same continuity range
                        get first fragment from playlist matching with criteria and load pts */
                        last_seqnum = _levels[level].getFirstSeqNumfromContinuity(frag_previous.continuity);
                        CONFIG::LOGGING {
                            Log.debug("loadnextfragment : getFirstSeqNumfromContinuity(level,cc:" + level + "," + frag_previous.continuity + ")=" + last_seqnum);
                        }
                        if (last_seqnum == Number.NEGATIVE_INFINITY) {
                            // playlist not yet received
                            return LOADING_WAITING_LEVEL_UPDATE;
                        }
                        /* when probing PTS, take previous sequence number as reference if possible */
                        new_seqnum = Math.min(frag_previous.seqnum + 1, _levels[level].getLastSeqNumfromContinuity(frag_previous.continuity));
                        new_seqnum = Math.max(new_seqnum, _levels[level].getFirstSeqNumfromContinuity(frag_previous.continuity));
                        _ptsAnalyzing = true;
                        log_prefix = "analyzing PTS ";
                    } else {
                        // last seqnum found on new level, reset PTS analysis flag
                        _ptsAnalyzing = false;
                    }
                }
            }

            if (_ptsAnalyzing == false) {
                if (last_seqnum == _levels[level].end_seqnum) {
                    // if last segment of level already loaded, return
                    if (_hls.type == HLSTypes.VOD) {
                        // if VOD playlist, loading is completed
                        return LOADING_COMPLETED;
                    } else {
                        // if live playlist, loading is pending on manifest update
                        return LOADING_WAITING_LEVEL_UPDATE;
                    }
                } else {
                    // if previous segment is not the last one, increment it to get new seqnum
                    new_seqnum = last_seqnum + 1;
                    if (new_seqnum < _levels[level].start_seqnum) {
                        // loading stalled ! report to caller
                        return LOADING_STALLED;
                    }
                    frag = _levels[level].getFragmentfromSeqNum(new_seqnum);
                    if (frag == null) {
                        CONFIG::LOGGING {
                            Log.warn("error trying to load " + new_seqnum + " of [" + (_levels[level].start_seqnum) + "," + (_levels[level].end_seqnum) + "],level " + level);
                        }
                        return LOADING_WAITING_LEVEL_UPDATE;
                    }
                    // check whether there is a discontinuity between last segment and new segment
                    _hasDiscontinuity = ((frag.continuity != frag_previous.continuity) || _fragSkipping);
                    ;
                    log_prefix = "Loading       ";
                }
            }
            frag = _levels[level].getFragmentfromSeqNum(new_seqnum);
            CONFIG::LOGGING {
                Log.debug(log_prefix + new_seqnum + " of [" + (_levels[level].start_seqnum) + "," + (_levels[level].end_seqnum) + "],level " + level);
            }
            _loadfragment(frag);
            return LOADING_IN_PROGRESS;
        };

        private function _loadfragment(frag : Fragment) : void {
            // postpone URLStream init before loading first fragment
            if (_fragstreamloader == null) {
                var urlStreamClass : Class = _hls.URLstream as Class;
                _fragstreamloader = (new urlStreamClass()) as URLStream;
                _fragstreamloader.addEventListener(IOErrorEvent.IO_ERROR, _fragLoadErrorHandler);
                _fragstreamloader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, _fragLoadErrorHandler);
                _fragstreamloader.addEventListener(ProgressEvent.PROGRESS, _fragLoadProgressHandler);
                _fragstreamloader.addEventListener(HTTPStatusEvent.HTTP_STATUS, _fragLoadHTTPStatusHandler);
                _fragstreamloader.addEventListener(Event.COMPLETE, _fragLoadCompleteHandler);
                _keystreamloader = (new urlStreamClass()) as URLStream;
                _keystreamloader.addEventListener(IOErrorEvent.IO_ERROR, _keyLoadErrorHandler);
                _keystreamloader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, _keyLoadErrorHandler);
                _keystreamloader.addEventListener(HTTPStatusEvent.HTTP_STATUS, _keyLoadHTTPStatusHandler);
                _keystreamloader.addEventListener(Event.COMPLETE, _keyLoadCompleteHandler);
            }
            if (_hasDiscontinuity || _switchLevel) {
                _demux = null;
            }
            _metrics = new HLSLoadMetrics(HLSLoaderTypes.FRAGMENT_MAIN);
            _metrics.level = frag.level;
            _metrics.id = frag.seqnum;
            _metrics.loading_request_time = getTimer();
            _fragCurrent = frag;
            frag.data.auto_level = _hls.autoLevel;
            if (frag.decrypt_url != null) {
                if (_keymap[frag.decrypt_url] == undefined) {
                    // load key
                    CONFIG::LOGGING {
                        Log.debug("loading key:" + frag.decrypt_url);
                    }
                    _keystreamloader.load(new URLRequest(frag.decrypt_url));
                    return;
                }
            }
            try {
                frag.data.bytes = null;
                CONFIG::LOGGING {
                    Log.debug("loading fragment:" + frag.url);
                }
                _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOADING, frag.url));
                _fragstreamloader.load(new URLRequest(frag.url));
            } catch (error : Error) {
                var hlsError : HLSError = new HLSError(HLSError.FRAGMENT_LOADING_ERROR, frag.url, error.message);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
        }

        /** Store the manifest data. **/
        private function _manifestLoadedHandler(event : HLSEvent) : void {
            _levels = event.levels;
            _manifestJustLoaded = true;
        };

        /** Store the manifest data. **/
        private function _levelLoadedHandler(event : HLSEvent) : void {
            _levelLastLoaded = event.loadMetrics.level;
            if (_loadingState == LOADING_WAITING_LEVEL_UPDATE && _levelLastLoaded == _hls.loadLevel) {
                _loadingState = LOADING_IDLE;
            }
            // speed up loading of new fragment
            _timer.start();
        };

        private function _fragParsingID3TagHandler(id3_tags : Vector.<ID3Tag>) : void {
            _fragCurrent.data.id3_tags = id3_tags;
        }

        /** triggered by demux, it should return the audio track to be parsed */
        private function _fragParsingAudioSelectionHandler(audioTrackList : Vector.<AudioTrack>) : AudioTrack {
            return _audioTrackController.audioTrackSelectionHandler(audioTrackList);
        }

        /** triggered by demux, it should return video width/height */
        private function _fragParsingVideoMetadataHandler(width : uint, height : uint) : void {
            var fragData : FragmentData = _fragCurrent.data;
            if (fragData.video_width == 0) {
                CONFIG::LOGGING {
                    Log.debug("AVC: width/height:" + width + "/" + height);
                }
                fragData.video_width = width;
                fragData.video_height = height;
            }
        }

        /** triggered when demux has retrieved some tags from fragment **/
        private function _fragParsingProgressHandler(tags : Vector.<FLVTag>) : void {
            CONFIG::LOGGING {
                Log.debug2(tags.length + " tags extracted");
            }
            var fragData : FragmentData = _fragCurrent.data;
            fragData.appendTags(tags);

            /* try to do progressive buffering here.
             * only do it in case :
             * 		first fragment is already loaded
             *      if first fragment is not loaded, we can do it if startLevel is already defined (if startFromLevel is set to -1
             *      we first need to download one fragment to check the dl bw, in order to assess start level ...)
             *      in case startFromLevel is to -1 and there is only one level, then we can do progressive buffering
             */
            if (( _fragmentFirstLoaded || (_manifestJustLoaded && (HLSSettings.startFromLevel !== -1 || HLSSettings.startFromBitrate !== -1 || _levels.length == 1) ) )) {
                /* if audio expected, PTS analysis is done on audio
                 * if audio not expected, PTS analysis is done on video
                 * the check below ensures that we can compute min/max PTS
                 */
                if ((_demux.audioExpected && fragData.audio_found) || (!_demux.audioExpected && fragData.video_found)) {
                    if (_ptsAnalyzing == true) {
                        _ptsAnalyzing = false;
                        _levels[_hls.loadLevel].updateFragment(_fragCurrent.seqnum, true, fragData.pts_min, fragData.pts_min + _fragCurrent.duration * 1000);
                        /* in case we are probing PTS, retrieve PTS info and synchronize playlist PTS / sequence number */
                        CONFIG::LOGGING {
                            Log.debug("analyzed  PTS " + _fragCurrent.seqnum + " of [" + (_levels[_hls.loadLevel].start_seqnum) + "," + (_levels[_hls.loadLevel].end_seqnum) + "],level " + _hls.loadLevel + " m PTS:" + fragData.pts_min);
                        }
                        /* check if fragment loaded for PTS analysis is the next one
                        if this is the expected one, then continue
                        if not, then cancel current fragment loading, next call to loadnextfragment() will load the right seqnum
                         */
                        var next_seqnum : Number = _levels[_hls.loadLevel].getSeqNumNearestPTS(_fragPrevious.data.pts_start, _fragCurrent.continuity) + 1;
                        CONFIG::LOGGING {
                            Log.debug("analyzed PTS : getSeqNumNearestPTS(level,pts,cc:" + _hls.loadLevel + "," + _fragPrevious.data.pts_start + "," + _fragCurrent.continuity + ")=" + next_seqnum);
                        }
                        // CONFIG::LOGGING {
                        // Log.info("seq/next:"+ _seqnum+"/"+ next_seqnum);
                        // }
                        if (next_seqnum != _fragCurrent.seqnum) {
                            // stick to same level after PTS analysis
                            _levelNext = _hls.loadLevel;
                            CONFIG::LOGGING {
                                Log.debug("PTS analysis done on " + _fragCurrent.seqnum + ", matching seqnum is " + next_seqnum + " of [" + (_levels[_hls.loadLevel].start_seqnum) + "," + (_levels[_hls.loadLevel].end_seqnum) + "],cancel loading and get new one");
                            }
                            // cancel loading
                            _stop_load();
                            // clean-up tags
                            fragData.flushTags();
                            // tell that new fragment could be loaded
                            _loadingState = LOADING_IDLE;
                            return;
                        }
                    }
                    if (fragData.metadata_tag_injected == false) {
                        fragData.tags.unshift(_fragCurrent.getMetadataTag());
                        if (_hasDiscontinuity) {
                            fragData.tags.unshift(new FLVTag(FLVTag.DISCONTINUITY, fragData.dts_min, fragData.dts_min, false));
                        }
                        fragData.metadata_tag_injected = true;
                    }
                    // provide tags to StreamBuffer
                    _streamBuffer.appendTags(HLSLoaderTypes.FRAGMENT_MAIN,_fragCurrent.level,_fragCurrent.seqnum , fragData.tags, fragData.tag_pts_min, fragData.tag_pts_max + fragData.tag_duration, _fragCurrent.continuity, _fragCurrent.start_time + fragData.tag_pts_start_offset / 1000);
                    _metrics.parsing_end_time = getTimer();
                    _metrics.size = fragData.bytesLoaded;
                    _metrics.duration = fragData.tag_pts_end_offset;
                    _metrics.id2 = fragData.tags.length;
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.TAGS_LOADED, _metrics));
                    fragData.shiftTags();
                    _hasDiscontinuity = false;
                }
            }
        }

        /** triggered when demux has completed fragment parsing **/
        private function _fragParsingCompleteHandler() : void {
            if (_loadingState == LOADING_IDLE)
                return;
            var hlsError : HLSError;
            var fragData : FragmentData = _fragCurrent.data;
            var fragLevelIdx : int = _fragCurrent.level;
            if ((_demux.audioExpected && !fragData.audio_found) && (_demux.videoExpected && !fragData.video_found)) {
                hlsError = new HLSError(HLSError.FRAGMENT_PARSING_ERROR, _fragCurrent.url, "error parsing fragment, no tag found");
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
            CONFIG::LOGGING {
                if (fragData.audio_found) {
                    Log.debug("m/M audio PTS:" + fragData.pts_min_audio + "/" + fragData.pts_max_audio);
                }
                if (fragData.video_found) {
                    Log.debug("m/M video PTS:" + fragData.pts_min_video + "/" + fragData.pts_max_video);

                    if (!fragData.audio_found) {
                    } else {
                        Log.debug("Delta audio/video m/M PTS:" + (fragData.pts_min_video - fragData.pts_min_audio) + "/" + (fragData.pts_max_video - fragData.pts_max_audio));
                    }
                }
            }

            // Calculate bandwidth
            _metrics.parsing_end_time = getTimer();
            CONFIG::LOGGING {
                Log.debug("Total Process duration/length/bw:" + _metrics.processing_duration + "/" + _metrics.size + "/" + Math.round(_metrics.bandwidth / 1024) + " kb/s");
            }

            if (_manifestJustLoaded) {
                _manifestJustLoaded = false;
                if (HLSSettings.startFromLevel === -1 && HLSSettings.startFromBitrate === -1 && _levels.length > 1 && !_levelController.isStartLevelSet()) {
                    // check if we can directly switch to a better bitrate, in case download bandwidth is enough
                    var bestlevel : int = _levelController.getbestlevel(_metrics.bandwidth);
                    if (bestlevel > fragLevelIdx) {
                        CONFIG::LOGGING {
                            Log.info("enough download bandwidth, adjust start level from 0 to " + bestlevel);
                        }
                        // dispatch event for tracking purpose
                        _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOADED, _metrics));
                        // let's directly jump to the accurate level to improve quality at player start
                        _levelNext = bestlevel;
                        _loadingState = LOADING_IDLE;
                        _switchLevel = true;
                        _demux = null;
                        _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, fragLevelIdx));
                        // speed up loading of new playlist
                        _timer.start();
                        return;
                    }
                }
            }

            try {
                _switchLevel = false;
                _levelNext = -1;
                var fragLevel : Level = _levels[fragLevelIdx];
                CONFIG::LOGGING {
                    Log.debug("Loaded        " + _fragCurrent.seqnum + " of [" + (fragLevel.start_seqnum) + "," + (fragLevel.end_seqnum) + "],level " + fragLevelIdx + " m/M PTS:" + fragData.pts_min + "/" + fragData.pts_max);
                }
                if (fragData.audio_found || fragData.video_found) {
                    fragLevel.updateFragment(_fragCurrent.seqnum, true, fragData.pts_min, fragData.pts_max + fragData.tag_duration);
                    // set pts_start here, it might not be updated directly in updateFragment() if this loaded fragment has been removed from a live playlist
                    fragData.pts_start = fragData.pts_min;
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.PLAYLIST_DURATION_UPDATED, fragLevel.duration));
                    if (fragData.tags.length) {
                        if (fragData.metadata_tag_injected == false) {
                            fragData.tags.unshift(_fragCurrent.getMetadataTag());
                            if (_hasDiscontinuity) {
                                fragData.tags.unshift(new FLVTag(FLVTag.DISCONTINUITY, fragData.dts_min, fragData.dts_min, false));
                            }
                            fragData.metadata_tag_injected = true;
                        }
                        _streamBuffer.appendTags(HLSLoaderTypes.FRAGMENT_MAIN, _fragCurrent.level,_fragCurrent.seqnum , fragData.tags, fragData.tag_pts_min, fragData.tag_pts_max + fragData.tag_duration, _fragCurrent.continuity, _fragCurrent.start_time + fragData.tag_pts_start_offset / 1000);
                        _metrics.duration = fragData.pts_max + fragData.tag_duration - fragData.pts_min;
                        _metrics.id2 = fragData.tags.length;
                        _hls.dispatchEvent(new HLSEvent(HLSEvent.TAGS_LOADED, _metrics));
                        fragData.shiftTags();
                        _hasDiscontinuity = false;
                    }
                } else {
                    _metrics.duration = _fragCurrent.duration * 1000;
                }
                _loadingState = LOADING_IDLE;
                _ptsAnalyzing = false;
                _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOADED, _metrics));
                _fragmentFirstLoaded = true;
                _fragPrevious = _fragCurrent;
            } catch (error : Error) {
                hlsError = new HLSError(HLSError.OTHER_ERROR, _fragCurrent.url, error.message);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
            // speed up loading of new fragment
            _timer.start();
        }
    }
}
