/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.hls.loader {
    import flash.utils.getTimer;
    import org.mangui.hls.controller.AudioTrackController;
    import org.mangui.hls.controller.AutoLevelController;
    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.event.HLSLoadMetrics;
    import org.mangui.hls.constant.HLSTypes;
    import org.mangui.hls.flv.FLVTag;
    import org.mangui.hls.event.HLSError;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.demux.Demuxer;
    import org.mangui.hls.demux.DemuxHelper;
    import org.mangui.hls.model.AudioTrack;
    import org.mangui.hls.HLS;
    import org.mangui.hls.model.Fragment;
    import org.mangui.hls.model.FragmentData;
    import org.mangui.hls.model.FragmentMetrics;
    import org.mangui.hls.model.Level;
    import org.mangui.hls.utils.AES;
    import org.mangui.hls.utils.PTS;

    import flash.events.*;
    import flash.net.*;
    import flash.utils.ByteArray;
    import flash.utils.Timer;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
        import org.mangui.hls.utils.Hex;
    }
    /** Class that fetches fragments. **/
    public class FragmentLoader {
        /** Reference to the HLS controller. **/
        private var _hls : HLS;
        /** reference to auto level manager */
        private var _autoLevelManager : AutoLevelController;
        /** reference to audio track controller */
        private var _audioTrackController : AudioTrackController;
        /** has manifest been loaded **/
        private var _manifest_loaded : Boolean;
        /** has manifest just being reloaded **/
        private var _manifest_just_loaded : Boolean;
        /** last loaded level. **/
        private var _last_loaded_level : int;
        /** Callback for passing forward the fragment tags. **/
        private var _tags_callback : Function;
        /** Quality level of the last fragment load. **/
        private var _level : int;
        /* overrided quality_manual_level level */
        private var _manual_level : int = -1;
        /** Reference to the manifest levels. **/
        private var _levels : Vector.<Level>;
        /** Util for loading the fragment. **/
        private var _fragstreamloader : URLStream;
        /** Util for loading the key. **/
        private var _keystreamloader : URLStream;
        /** key map **/
        private var _keymap : Object;
        /** Did the stream switch quality levels. **/
        private var _switchlevel : Boolean;
        /** Did a discontinuity occurs in the stream **/
        private var _hasDiscontinuity : Boolean;
        /** boolean to track whether PTS analysis is ongoing or not */
        private var _pts_analyzing : Boolean = false;
        /** boolean to indicate that PTS has just been analyzed */
        private var _pts_just_analyzed : Boolean = false;
        /** Timer used to monitor/schedule fragment download. **/
        private var _timer : Timer;
        /** requested seek position **/
        private var _seek_pos : Number;
        /** first fragment loaded ? **/
        private var _fragment_first_loaded : Boolean;
        /* demux instance */
        private var _demux : Demuxer;
        /* key error/reload */
        private var _key_load_error_date : Number;
        private var _key_retry_timeout : Number;
        private var _key_retry_count : int;
        private var _key_load_status : int;
        /* fragment error/reload */
        private var _frag_load_error_date : Number;
        private var _frag_retry_timeout : Number;
        private var _frag_retry_count : int;
        private var _frag_load_status : int;
        /** reference to previous/current fragment */
        private var _frag_previous : Fragment;
        private var _frag_current : Fragment;
        /* loading state variable */
        private var _loading_state : int;
        private static const LOADING_IDLE : int = 0;
        private static const LOADING_IN_PROGRESS : int = 1;
        private static const LOADING_WAITING_LEVEL_UPDATE : int = 2;
        private static const LOADING_STALLED : int = 3;
        private static const LOADING_FRAGMENT_IO_ERROR : int = 4;
        private static const LOADING_KEY_IO_ERROR : int = 5;

        /** Create the loader. **/
        public function FragmentLoader(hls : HLS, audioTrackController : AudioTrackController) : void {
            _hls = hls;
            _autoLevelManager = new AutoLevelController(hls);
            _audioTrackController = audioTrackController;
            _hls.addEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.addEventListener(HLSEvent.LEVEL_LOADED, _levelLoadedHandler);
            _timer = new Timer(100, 0);
            _timer.addEventListener(TimerEvent.TIMER, _checkLoading);
            _loading_state = LOADING_IDLE;
            _manifest_loaded = false;
            _manifest_just_loaded = false;
            _keymap = new Object();
        };

        public function dispose() : void {
            stop();
            _autoLevelManager.dispose();
            _hls.removeEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.removeEventListener(HLSEvent.LEVEL_LOADED, _levelLoadedHandler);
            _manifest_loaded = false;
            _keymap = new Object();
        }

        /**  fragment loading Timer **/
        private function _checkLoading(e : Event) : void {
            // cannot load fragment until manifest is loaded
            if (_manifest_loaded == false) {
                return;
            }
            switch(_loading_state) {
                // nothing to load until level is retrieved
                case LOADING_WAITING_LEVEL_UPDATE:
                // loading already in progress
                case LOADING_IN_PROGRESS:
                    break;
                // no loading in progress, try to load first/next fragment
                case LOADING_IDLE:
                    var level : int;
                    // check if first fragment after seek has been already loaded
                    if (_fragment_first_loaded == false) {
                        // select level for first fragment load
                        if (_manual_level == -1) {
                            if (_manifest_just_loaded) {
                                level = _hls.startlevel;
                            } else {
                                level = _hls.seeklevel;
                            }
                        } else {
                            level = _manual_level;
                        }
                        if (level != _level || _manifest_just_loaded) {
                            _level = level;
                            _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, _level));
                        }
                        _switchlevel = true;

                        // check if we received playlist for choosen level. if live playlist, ensure that new playlist has been refreshed
                        if ((_levels[level].fragments.length == 0) || (_hls.type == HLSTypes.LIVE && _last_loaded_level != level)) {
                            // playlist not yet received
                            CONFIG::LOGGING {
                                Log.debug("_checkLoading : playlist not received for level:" + level);
                            }
                            _loading_state = LOADING_WAITING_LEVEL_UPDATE;
                        } else {
                            // just after seek, load first fragment
                            _loading_state = _loadfirstfragment(_seek_pos, level);
                        }

                        /* first fragment already loaded
                         * check if we need to load next fragment, do it only if buffer is NOT full
                         */
                    } else if (HLSSettings.maxBufferLength == 0 || _hls.stream.bufferLength < HLSSettings.maxBufferLength) {
                        // select level for next fragment load
                        // dont switch level after PTS analysis
                        if (_pts_just_analyzed == true) {
                            _pts_just_analyzed = false;
                            level = _level;
                            /* in case we are switching levels (waiting for playlist to reload) or seeking , stick to same level */
                        } else if (_switchlevel == true) {
                            level = _level;
                        } else if (_manual_level == -1 && _levels.length > 1 ) {
                            // select level from heuristics (current level / last fragment duration / buffer length)
                            level = _autoLevelManager.getnextlevel(_level, _hls.stream.bufferLength);
                        } else if (_manual_level == -1 && _levels.length == 1 ) {
                            level = 0;
                        } else {
                            level = _manual_level;
                        }
                        // notify in case level switch occurs
                        if (level != _level) {
                            _level = level;
                            _switchlevel = true;
                            _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, _level));
                        }
                        // check if we received playlist for choosen level. if live playlist, ensure that new playlist has been refreshed
                        if ((_levels[level].fragments.length == 0) || (_hls.type == HLSTypes.LIVE && _last_loaded_level != level)) {
                            // playlist not yet received
                            CONFIG::LOGGING {
                                Log.debug("_checkLoading : playlist not received for level:" + level);
                            }
                            _loading_state = LOADING_WAITING_LEVEL_UPDATE;
                        } else {
                            _loading_state = _loadnextfragment(_level, _frag_previous);
                        }
                    }
                    if (_loading_state == LOADING_STALLED) {
                        /* next consecutive fragment not found:
                        it could happen on live playlist :
                        - if bandwidth available is lower than lowest quality needed bandwidth
                        - after long pause */
                        CONFIG::LOGGING {
                            Log.warn("loading stalled: restart playback");
                        }
                        /* seek to force a restart of the playback session  */
                        seek(-1, _tags_callback);
                        return;
                    }
                    break;
                // if key loading failed
                case  LOADING_KEY_IO_ERROR:
                    // compare current date and next retry date.
                    if (getTimer() >= _key_load_error_date) {
                        /* try to reload the key ...
                        calling _loadfragment will also reload key */
                        _loadfragment(_frag_current);
                        _loading_state = LOADING_IN_PROGRESS;
                    }
                    break;
                // if fragment loading failed
                case LOADING_FRAGMENT_IO_ERROR:
                    // compare current date and next retry date.
                    if (getTimer() >= _frag_load_error_date) {
                        /* try to reload the key ...
                        calling _loadfragment will also reload key */
                        _loadfragment(_frag_current);
                        _loading_state = LOADING_IN_PROGRESS;
                    }
                    break;
            }
        }

        public function seek(position : Number, callback : Function) : void {
            // reset IO Error when seeking
            _frag_retry_count = _key_retry_count = 0;
            _frag_retry_timeout = _key_retry_timeout = 1000;
            _loading_state = LOADING_IDLE;
            _tags_callback = callback;
            _seek_pos = position;
            _fragment_first_loaded = false;
            _frag_previous = null;
            _timer.start();
        }

        /** key load completed. **/
        private function _keyLoadCompleteHandler(event : Event) : void {
            if (_loading_state == LOADING_IDLE)
                return;
            CONFIG::LOGGING {
                Log.debug("key loading completed");
            }
            var hlsError : HLSError;
            // Collect key data
            if ( _keystreamloader.bytesAvailable == 16 ) {
                // load complete, reset retry counter
                _key_retry_count = 0;
                _key_retry_timeout = 1000;
                var keyData : ByteArray = new ByteArray();
                _keystreamloader.readBytes(keyData, 0, 0);
                _keymap[_frag_current.decrypt_url] = keyData;
                // now load fragment
                try {
                    CONFIG::LOGGING {
                        Log.debug("loading fragment:" + _frag_current.url);
                    }
                    _frag_current.data.bytes = null;
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOADING, _frag_current.url));
                    _fragstreamloader.load(new URLRequest(_frag_current.url));
                } catch (error : Error) {
                    hlsError = new HLSError(HLSError.FRAGMENT_LOADING_ERROR, _frag_current.url, error.message);
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
                }
            } else {
                hlsError = new HLSError(HLSError.KEY_PARSING_ERROR, _frag_current.decrypt_url, "invalid key size: received " + _keystreamloader.bytesAvailable + " / expected 16 bytes");
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
        };

        private function _keyLoadHTTPStatusHandler(event : HTTPStatusEvent) : void {
            _key_load_status = event.status;
        }

        private function _keyhandleIOError(message : String) : void {
            CONFIG::LOGGING {
                Log.error("I/O Error while loading key:" + message);
            }
            if (HLSSettings.keyLoadMaxRetry == -1 || _key_retry_count < HLSSettings.keyLoadMaxRetry) {
                _loading_state = LOADING_KEY_IO_ERROR;
                _key_load_error_date = getTimer() + _key_retry_timeout;
                CONFIG::LOGGING {
                    Log.warn("retry key load in " + _key_retry_timeout + " ms, count=" + _key_retry_count);
                }
                /* exponential increase of retry timeout, capped to keyLoadMaxRetryTimeout */
                _key_retry_count++;
                _key_retry_timeout = Math.min(HLSSettings.keyLoadMaxRetryTimeout, 2 * _key_retry_timeout);
            } else {
                var hlsError : HLSError = new HLSError(HLSError.KEY_LOADING_ERROR, _frag_current.decrypt_url, "I/O Error :" + message);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
        }

        private function _fraghandleIOError(message : String) : void {
            /* usually, errors happen in two situations :
            - bad networks  : in that case, the second or third reload of URL should fix the issue
            - live playlist : when we are trying to load an out of bound fragments : for example,
            the playlist on webserver is from SN [51-61]
            the one in memory is from SN [50-60], and we are trying to load SN50.
            we will keep getting 404 error if the HLS server does not follow HLS spec,
            which states that the server should keep SN50 during EXT-X-TARGETDURATION period
            after it is removed from playlist
            in the meantime, ManifestLoader will keep refreshing the playlist in the background ...
            so if the error still happens after EXT-X-TARGETDURATION, it means that there is something wrong
            we need to report it.
             */
            CONFIG::LOGGING {
                Log.error("I/O Error while loading fragment:" + message);
            }
            if (HLSSettings.fragmentLoadMaxRetry == -1 || _frag_retry_count < HLSSettings.fragmentLoadMaxRetry) {
                _loading_state = LOADING_FRAGMENT_IO_ERROR;
                _frag_load_error_date = getTimer() + _frag_retry_timeout;
                CONFIG::LOGGING {
                    Log.warn("retry fragment load in " + _frag_retry_timeout + " ms, count=" + _frag_retry_count);
                }
                /* exponential increase of retry timeout, capped to fragmentLoadMaxRetryTimeout */
                _frag_retry_count++;
                _frag_retry_timeout = Math.min(HLSSettings.fragmentLoadMaxRetryTimeout, 2 * _frag_retry_timeout);
            } else {
                var hlsError : HLSError = new HLSError(HLSError.FRAGMENT_LOADING_ERROR, _frag_current.url, "I/O Error :" + message);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
        }

        private function _fragLoadHTTPStatusHandler(event : HTTPStatusEvent) : void {
            _frag_load_status = event.status;
        }

        private function _fragLoadProgressHandler(event : ProgressEvent) : void {
            var fragData : FragmentData = _frag_current.data;
            if (fragData.bytes == null) {
                fragData.bytes = new ByteArray();
                fragData.bytesLoaded = 0;
                fragData.tags = new Vector.<FLVTag>();
                fragData.audio_found = fragData.video_found = false;
                fragData.pts_min_audio = fragData.pts_min_video = fragData.tags_pts_min_audio = fragData.tags_pts_min_video = Number.POSITIVE_INFINITY;
                fragData.pts_max_audio = fragData.pts_max_video = fragData.tags_pts_max_audio = fragData.tags_pts_max_video = Number.NEGATIVE_INFINITY;
                var fragMetrics : FragmentMetrics = _frag_current.metrics;
                fragMetrics.loading_begin_time = getTimer();

                // decrypt data if needed
                if (_frag_current.decrypt_url != null) {
                    fragMetrics.decryption_begin_time = getTimer();
                    fragData.decryptAES = new AES(_hls.stage, _keymap[_frag_current.decrypt_url], _frag_current.decrypt_iv, _fragDecryptProgressHandler, _fragDecryptCompleteHandler);
                    CONFIG::LOGGING {
                        Log.debug("init AES context:" + fragData.decryptAES);
                    }
                } else {
                    fragData.decryptAES = null;
                }
            }
            if (event.bytesLoaded > fragData.bytesLoaded) {
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
            _frag_retry_count = 0;
            _frag_retry_timeout = 1000;
            var fragData : FragmentData = _frag_current.data;
            if (fragData.bytes == null) {
                CONFIG::LOGGING {
                    Log.warn("fragment size is null, invalid it and load next one");
                }
                _levels[_level].updateFragment(_frag_current.seqnum, false);
                _loading_state = LOADING_IDLE;
                return;
            }
            CONFIG::LOGGING {
                Log.debug("loading completed");
            }
            var fragMetrics : FragmentMetrics = _frag_current.metrics;
            fragMetrics.loading_end_time = getTimer();
            fragMetrics.size = fragData.bytesLoaded;

            var _loading_duration : uint = fragMetrics.loading_end_time - fragMetrics.loading_request_time;
            CONFIG::LOGGING {
                Log.debug("Loading       duration/RTT/length/speed:" + _loading_duration + "/" + (fragMetrics.loading_begin_time - fragMetrics.loading_request_time) + "/" + fragMetrics.size + "/" + ((8000 * fragMetrics.size / _loading_duration) / 1024).toFixed(0) + " kb/s");
            }
            if (fragData.decryptAES) {
                fragData.decryptAES.notifycomplete();
            } else {
                _fragDecryptCompleteHandler();
            }
        }

        private function _fragDecryptProgressHandler(data : ByteArray) : void {
            data.position = 0;
            var fragData : FragmentData = _frag_current.data;
            var fragMetrics : FragmentMetrics = _frag_current.metrics;
            if (isNaN(fragMetrics.parsing_begin_time)) {
                fragMetrics.parsing_begin_time = getTimer();
            }
            var bytes : ByteArray = fragData.bytes;
            if (_frag_current.byterange_start_offset != -1) {
                bytes.position = bytes.length;
                bytes.writeBytes(data);
                // if we have retrieved all the data, disconnect loader and notify fragment complete
                if (bytes.length >= _frag_current.byterange_end_offset) {
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
                _demux = DemuxHelper.probe(data, _levels[level], _hls.stage, _fragParsingAudioSelectionHandler, _fragParsingProgressHandler, _fragParsingCompleteHandler, _fragParsingVideoMetadataHandler);
            }
            if (_demux) {
                _demux.append(data);
            }
        }

        private function _fragDecryptCompleteHandler() : void {
            if (_loading_state == LOADING_IDLE)
                return;
            var fragData : FragmentData = _frag_current.data;

            if (fragData.decryptAES) {
                var fragMetrics : FragmentMetrics = _frag_current.metrics;
                fragMetrics.decryption_end_time = getTimer();
                var decrypt_duration : Number = fragMetrics.decryption_end_time - fragMetrics.decryption_begin_time;
                CONFIG::LOGGING {
                    Log.debug("Decrypted     duration/length/speed:" + decrypt_duration + "/" + fragData.bytesLoaded + "/" + ((8000 * fragData.bytesLoaded / decrypt_duration) / 1024).toFixed(0) + " kb/s");
                }
                fragData.decryptAES = null;
            }

            // deal with byte range here
            if (_frag_current.byterange_start_offset != -1) {
                CONFIG::LOGGING {
                    Log.debug("trim byte range, start/end offset:" + _frag_current.byterange_start_offset + "/" + _frag_current.byterange_end_offset);
                }
                var bytes : ByteArray = new ByteArray();
                fragData.bytes.position = _frag_current.byterange_start_offset;
                fragData.bytes.readBytes(bytes, 0, _frag_current.byterange_end_offset - _frag_current.byterange_start_offset);
                _demux = DemuxHelper.probe(bytes, _levels[level], _hls.stage, _fragParsingAudioSelectionHandler, _fragParsingProgressHandler, _fragParsingCompleteHandler, _fragParsingVideoMetadataHandler);
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
            _loading_state = LOADING_IDLE;
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

            if (_frag_current) {
                var fragData : FragmentData = _frag_current.data;
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
                _keyhandleIOError("HTTP status:" + _key_load_status + ",msg:" + event.text);
            }
        };

        /** Catch IO and security errors. **/
        private function _fragLoadErrorHandler(event : ErrorEvent) : void {
            if (event is SecurityErrorEvent) {
                var txt : String = "Cannot load fragment: crossdomain access denied:" + event.text;
                var hlsError : HLSError = new HLSError(HLSError.FRAGMENT_LOADING_CROSSDOMAIN_ERROR, _frag_current.url, txt);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            } else {
                _fraghandleIOError("HTTP status:" + _frag_load_status + ",msg:" + event.text);
            }
        };

        private function _loadfirstfragment(position : Number, level : int) : int {
            CONFIG::LOGGING {
                Log.debug("loadfirstfragment(" + position + ")");
            }
            var seek_position : Number;
            if (_hls.type == HLSTypes.LIVE) {
                /* follow HLS spec :
                If the EXT-X-ENDLIST tag is not present
                and the client intends to play the media regularly (i.e. in playlist
                order at the nominal playback rate), the client SHOULD NOT
                choose a segment which starts less than three target durations from
                the end of the Playlist file */
                var maxLivePosition : Number = Math.max(0, _levels[level].duration - 3 * _levels[level].averageduration);
                if (position == -1) {
                    // seek 3 fragments from end
                    seek_position = maxLivePosition;
                } else {
                    seek_position = Math.min(position, maxLivePosition);
                }
            } else {
                seek_position = Math.max(position, 0);
            }
            CONFIG::LOGGING {
                Log.debug("loadfirstfragment : requested position:" + position + ",seek position:" + seek_position);
            }
            position = seek_position;

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

            if (_switchlevel == false || frag_previous.continuity == -1) {
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
                        _pts_analyzing = true;
                        log_prefix = "analyzing PTS ";
                    }
                }
            }

            if (_pts_analyzing == false) {
                if (last_seqnum == _levels[level].end_seqnum) {
                    // if last segment was last fragment of VOD playlist, notify last fragment loaded event, and return
                    if (_hls.type == HLSTypes.VOD) {
                        _hls.dispatchEvent(new HLSEvent(HLSEvent.LAST_VOD_FRAGMENT_LOADED));
                        // stop loading timer as well, as no other fragments can be loaded
                        _timer.stop();
                    }
                    return LOADING_WAITING_LEVEL_UPDATE;
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
                    _hasDiscontinuity = (frag.continuity != frag_previous.continuity);
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
                if (_hls.stage == null) {
                    var err : String = "hls.stage not set, cannot parse TS data !!!";
                    CONFIG::LOGGING {
                        Log.error(err);
                    }
                    var hlsError : HLSError = new HLSError(HLSError.OTHER_ERROR, frag.url, err);
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
                    return;
                }
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
            if (_hasDiscontinuity || _switchlevel) {
                _demux = null;
            }
            frag.metrics.loading_request_time = getTimer();
            _frag_current = frag;
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
                hlsError = new HLSError(HLSError.FRAGMENT_LOADING_ERROR, frag.url, error.message);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
        }

        /** Store the manifest data. **/
        private function _manifestLoadedHandler(event : HLSEvent) : void {
            _levels = event.levels;
            if (_manual_level == -1) {
                _level = _hls.startlevel;
            } else {
                _level = _manual_level = Math.min(_manual_level, _levels.length - 1);
            }
            _manifest_loaded = true;
            _manifest_just_loaded = true;
        };

        /** Store the manifest data. **/
        private function _levelLoadedHandler(event : HLSEvent) : void {
            _last_loaded_level = event.level;
            if (_loading_state == LOADING_WAITING_LEVEL_UPDATE && _last_loaded_level == _level) {
                _loading_state = LOADING_IDLE;
                // speed up loading of new fragment
                _timer.start();
            }
        };

        /** triggered by demux, it should return the audio track to be parsed */
        private function _fragParsingAudioSelectionHandler(audioTrackList : Vector.<AudioTrack>) : AudioTrack {
            return _audioTrackController.audioTrackSelectionHandler(audioTrackList);
        }

        /** triggered by demux, it should return video width/height */
        private function _fragParsingVideoMetadataHandler(width : uint, height : uint) : void {
            var fragData : FragmentData = _frag_current.data;
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
            var tag : FLVTag;
            /* ref PTS / DTS value for PTS looping */
            var fragData : FragmentData = _frag_current.data;
            var ref_pts : Number = fragData.pts_start_computed;
            // Audio PTS/DTS normalization + min/max computation
            for each (tag in tags) {
                tag.pts = PTS.normalize(ref_pts, tag.pts);
                tag.dts = PTS.normalize(ref_pts, tag.dts);
                switch( tag.type ) {
                    case FLVTag.AAC_HEADER:
                    case FLVTag.AAC_RAW:
                    case FLVTag.MP3_RAW:
                        fragData.audio_found = true;
                        fragData.tags_audio_found = true;
                        fragData.tags_pts_min_audio = Math.min(fragData.tags_pts_min_audio, tag.pts);
                        fragData.tags_pts_max_audio = Math.max(fragData.tags_pts_max_audio, tag.pts);
                        fragData.pts_min_audio = Math.min(fragData.pts_min_audio, tag.pts);
                        fragData.pts_max_audio = Math.max(fragData.pts_max_audio, tag.pts);
                        break;
                    case FLVTag.AVC_HEADER:
                    case FLVTag.AVC_NALU:
                    case FLVTag.DISCONTINUITY:
                        fragData.video_found = true;
                        fragData.tags_video_found = true;
                        fragData.tags_pts_min_video = Math.min(fragData.tags_pts_min_video, tag.pts);
                        fragData.tags_pts_max_video = Math.max(fragData.tags_pts_max_video, tag.pts);
                        fragData.pts_min_video = Math.min(fragData.pts_min_video, tag.pts);
                        fragData.pts_max_video = Math.max(fragData.pts_max_video, tag.pts);
                        break;
                    case FLVTag.METADATA:
                    default:
                        break;
                }
                fragData.tags.push(tag);
            }

            /* try to do progressive buffering here.
             * only do it in case :
             * 		first fragment is already loaded
             *      if first fragment is not loaded, we can do it if startlevel is already defined (if startFromLevel is set to -1
             *      we first need to download one fragment to check the dl bw, in order to assess start level ...)
             *      in case startFromLevel is to -1 and there is only one level, then we can do progressive buffering
             */
            if (( _fragment_first_loaded || (_manifest_just_loaded && (HLSSettings.startFromLevel !== -1 || HLSSettings.startFromBitrate !== -1 || _levels.length == 1) ) )) {
                if (_demux.audio_expected() && !fragData.audio_found) {
                    /* if no audio tags found, it means that only video tags have been retrieved here
                     * we cannot do progressive buffering in that case.
                     * we need to have some new audio tags to inject as well
                     */
                    return;
                }

                if (fragData.tag_pts_min != Number.POSITIVE_INFINITY && fragData.tag_pts_max != Number.NEGATIVE_INFINITY) {
                    var min_offset : Number = _frag_current.start_time + fragData.tag_pts_start_offset / 1000;
                    var max_offset : Number = _frag_current.start_time + fragData.tag_pts_end_offset / 1000;
                    // in case of cold start/seek use case,
                    if (!_fragment_first_loaded ) {
                        /* ensure buffer max offset is greater than requested seek position.
                         * this will avoid issues with accurate seeking feature */
                        if (_seek_pos > max_offset) {
                            // cannot do progressive buffering until we have enough data to reach requested seek offset
                            return;
                        }
                    }

                    if (_pts_analyzing == true) {
                        _pts_analyzing = false;
                        _levels[_level].updateFragment(_frag_current.seqnum, true, fragData.pts_min, fragData.pts_min + _frag_current.duration * 1000);
                        /* in case we are probing PTS, retrieve PTS info and synchronize playlist PTS / sequence number */
                        CONFIG::LOGGING {
                            Log.debug("analyzed  PTS " + _frag_current.seqnum + " of [" + (_levels[_level].start_seqnum) + "," + (_levels[_level].end_seqnum) + "],level " + _level + " m PTS:" + fragData.pts_min);
                        }
                        /* check if fragment loaded for PTS analysis is the next one
                        if this is the expected one, then continue
                        if not, then cancel current fragment loading, next call to loadnextfragment() will load the right seqnum
                         */
                        var next_seqnum : Number = _levels[_level].getSeqNumNearestPTS(_frag_previous.data.pts_start, _frag_current.continuity) + 1;
                        CONFIG::LOGGING {
                            Log.debug("analyzed PTS : getSeqNumNearestPTS(level,pts,cc:" + _level + "," + _frag_previous.data.pts_start + "," + _frag_current.continuity + ")=" + next_seqnum);
                        }
                        // CONFIG::LOGGING {
                        // Log.info("seq/next:"+ _seqnum+"/"+ next_seqnum);
                        // }
                        if (next_seqnum != _frag_current.seqnum) {
                            _pts_just_analyzed = true;
                            CONFIG::LOGGING {
                                Log.debug("PTS analysis done on " + _frag_current.seqnum + ", matching seqnum is " + next_seqnum + " of [" + (_levels[_level].start_seqnum) + "," + (_levels[_level].end_seqnum) + "],cancel loading and get new one");
                            }
                            // cancel loading
                            _stop_load();
                            // clean-up tags
                            fragData.tags = new Vector.<FLVTag>();
                            fragData.tags_audio_found = fragData.tags_video_found = false;
                            // tell that new fragment could be loaded
                            _loading_state = LOADING_IDLE;
                            return;
                        }
                    }
                    // provide tags to HLSNetStream
                    _tags_callback(_level, _frag_current.continuity, _frag_current.seqnum, !fragData.video_found, fragData.video_width, fragData.video_height, _frag_current.tag_list, fragData.tags, fragData.tag_pts_min, fragData.tag_pts_max, _hasDiscontinuity, min_offset, _frag_current.program_date + fragData.tag_pts_start_offset);
                    var processing_duration : Number = (getTimer() - _frag_current.metrics.loading_request_time);
                    var bandwidth : Number = Math.round(fragData.bytesLoaded * 8000 / processing_duration);
                    var tagsMetrics : HLSLoadMetrics = new HLSLoadMetrics(_level, bandwidth, fragData.tag_pts_end_offset, processing_duration);
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.TAGS_LOADED, tagsMetrics));
                    _hasDiscontinuity = false;
                    fragData.tags = new Vector.<FLVTag>();
                    if (fragData.tags_audio_found) {
                        fragData.tags_pts_min_audio = fragData.tags_pts_max_audio;
                        fragData.tags_audio_found = false;
                    }
                    if (fragData.tags_video_found) {
                        fragData.tags_pts_min_video = fragData.tags_pts_max_video;
                        fragData.tags_video_found = false;
                    }
                }
            }
        }

        /** triggered when demux has completed fragment parsing **/
        private function _fragParsingCompleteHandler() : void {
            if (_loading_state == LOADING_IDLE)
                return;
            var hlsError : HLSError;
            var fragData : FragmentData = _frag_current.data;
            if (!fragData.audio_found && !fragData.video_found) {
                hlsError = new HLSError(HLSError.FRAGMENT_PARSING_ERROR, _frag_current.url, "error parsing fragment, no tag found");
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
            if (fragData.audio_found) {
                null;
                // just to stop the compiler warning
                CONFIG::LOGGING {
                    Log.debug("m/M audio PTS:" + fragData.pts_min_audio + "/" + fragData.pts_max_audio);
                }
            }

            if (fragData.video_found) {
                CONFIG::LOGGING {
                    Log.debug("m/M video PTS:" + fragData.pts_min_video + "/" + fragData.pts_max_video);
                }
                if (!fragData.audio_found) {
                } else {
                    null;
                    // just to avoid compilation warnings if CONFIG::LOGGING is false
                    CONFIG::LOGGING {
                        Log.debug("Delta audio/video m/M PTS:" + (fragData.pts_min_video - fragData.pts_min_audio) + "/" + (fragData.pts_max_video - fragData.pts_max_audio));
                    }
                }
            }

            // Calculate bandwidth
            var fragMetrics : FragmentMetrics = _frag_current.metrics;
            fragMetrics.parsing_end_time = getTimer();
            CONFIG::LOGGING {
                Log.debug("Total Process duration/length/bw:" + fragMetrics.processing_duration + "/" + fragMetrics.size + "/" + (fragMetrics.bandwidth / 1024).toFixed(0) + " kb/s");
            }

            if (_manifest_just_loaded) {
                _manifest_just_loaded = false;
                if (HLSSettings.startFromLevel === -1 && HLSSettings.startFromBitrate === -1 && _levels.length > 1) {
                    // check if we can directly switch to a better bitrate, in case download bandwidth is enough
                    var bestlevel : int = _autoLevelManager.getbestlevel(fragMetrics.bandwidth);
                    if (bestlevel > _level) {
                        CONFIG::LOGGING {
                            Log.info("enough download bandwidth, adjust start level from " + _level + " to " + bestlevel);
                        }
                        // let's directly jump to the accurate level to improve quality at player start
                        _level = bestlevel;
                        _loading_state = LOADING_IDLE;
                        _switchlevel = true;
                        _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, _level));
                        return;
                    }
                }
            }

            try {
                _switchlevel = false;
                CONFIG::LOGGING {
                    Log.debug("Loaded        " + _frag_current.seqnum + " of [" + (_levels[_level].start_seqnum) + "," + (_levels[_level].end_seqnum) + "],level " + _level + " m/M PTS:" + fragData.pts_min + "/" + fragData.pts_max);
                }
                var start_offset : Number = _levels[_level].updateFragment(_frag_current.seqnum, true, fragData.pts_min, fragData.pts_max);
                // set pts_start here, it might not be updated directly in updateFragment() if this loaded fragment has been removed from a live playlist
                fragData.pts_start = fragData.pts_min;
                _hls.dispatchEvent(new HLSEvent(HLSEvent.PLAYLIST_DURATION_UPDATED, _levels[_level].duration));
                _loading_state = LOADING_IDLE;

                var tagsMetrics : HLSLoadMetrics = new HLSLoadMetrics(_level, fragMetrics.bandwidth, fragData.pts_max - fragData.pts_min, fragMetrics.processing_duration);

                if (fragData.tags.length) {
                    _tags_callback(_level, _frag_current.continuity, _frag_current.seqnum, !fragData.video_found, fragData.video_width, fragData.video_height, _frag_current.tag_list, fragData.tags, fragData.tag_pts_min, fragData.tag_pts_max, _hasDiscontinuity, start_offset + fragData.tag_pts_start_offset / 1000, _frag_current.program_date + fragData.tag_pts_start_offset);
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.TAGS_LOADED, tagsMetrics));
                    if (fragData.tags_audio_found) {
                        fragData.tags_pts_min_audio = fragData.tags_pts_max_audio;
                        fragData.tags_audio_found = false;
                    }
                    if (fragData.tags_video_found) {
                        fragData.tags_pts_min_video = fragData.tags_pts_max_video;
                        fragData.tags_video_found = false;
                    }
                    _hasDiscontinuity = false;
                    fragData.tags = new Vector.<FLVTag>();
                }
                _pts_analyzing = false;
                _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOADED, tagsMetrics));
                _fragment_first_loaded = true;
                _frag_previous = _frag_current;
            } catch (error : Error) {
                hlsError = new HLSError(HLSError.OTHER_ERROR, _frag_current.url, error.message);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
        }

        /** return current quality level. **/
        public function get level() : int {
            return _level;
        };

        /* set current quality level */
        public function set level(level : int) : void {
            _manual_level = level;
        };

        /** get auto/manual level mode **/
        public function get autolevel() : Boolean {
            if (_manual_level == -1) {
                return true;
            } else {
                return false;
            }
        };
    }
}