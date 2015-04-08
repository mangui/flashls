/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.loader {
    import flash.utils.getTimer;

    import org.mangui.hls.constant.HLSLoaderTypes;
    import org.mangui.hls.constant.HLSTypes;
    import org.mangui.hls.demux.Demuxer;
    import org.mangui.hls.demux.DemuxHelper;
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

    import flash.events.*;
    import flash.net.*;
    import flash.utils.ByteArray;
    import flash.utils.Timer;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
        import org.mangui.hls.utils.Hex;
    }
    /** Class that fetches alt audio fragments. **/
    public class AltAudioFragmentLoader {
        /** Reference to the HLS controller. **/
        private var _hls : HLS;
        /** Util for loading the fragment. **/
        private var _fragstreamloader : URLStream;
        /** Util for loading the key. **/
        private var _keystreamloader : URLStream;
        /** key map **/
        private var _keymap : Object;
        /** Timer used to monitor/schedule fragment download. **/
        private var _timer : Timer;
        /** requested seek position **/
        private var _seek_pos : Number;
        /** first fragment loaded ? **/
        private var _fragment_first_loaded : Boolean;
        /* demux instance */
        private var _demux : Demuxer;
        /* stream buffer instance **/
        private var _streamBuffer : StreamBuffer;
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
        /** reference to audio level */
        private var _level : Level;
        /** reference to previous/current fragment */
        private var _frag_previous : Fragment;
        private var _frag_current : Fragment;
        /* loading state variable */
        private var _loading_state : int;
        /* loading metrics */
        private var _metrics : HLSLoadMetrics;
        private static const LOADING_IDLE : int = 0;
        private static const LOADING_IN_PROGRESS : int = 1;
        private static const LOADING_WAITING_LEVEL_UPDATE : int = 2;
        private static const LOADING_STALLED : int = 3;
        private static const LOADING_FRAGMENT_IO_ERROR : int = 4;
        private static const LOADING_KEY_IO_ERROR : int = 5;
        private static const LOADING_COMPLETED : int = 6;

        /** Create the loader. **/
        public function AltAudioFragmentLoader(hls : HLS, streamBuffer : StreamBuffer) : void {
            _hls = hls;
            _streamBuffer = streamBuffer;
            _timer = new Timer(20, 0);
            _timer.addEventListener(TimerEvent.TIMER, _checkLoading);
            _loading_state = LOADING_IDLE;
            _keymap = new Object();
        };

        public function dispose() : void {
            stop();
            _loading_state = LOADING_IDLE;
            _keymap = new Object();
        }

        /** update state and level in case of audio level loaded event **/
        private function _audioLevelLoadedHandler(event : HLSEvent) : void {
            if (_loading_state == LOADING_WAITING_LEVEL_UPDATE || _loading_state == LOADING_IDLE) {
                _loading_state = LOADING_IDLE;
                _level = _hls.audioTracks[_hls.audioTrack].level;
                // speed up loading of new fragment
                _timer.start();
            }
        };

        /**  fragment loading Timer **/
        private function _checkLoading(e : Event) : void {
            switch(_loading_state) {
                // nothing to load until level is retrieved
                case LOADING_WAITING_LEVEL_UPDATE:
                // loading already in progress
                case LOADING_IN_PROGRESS:
                    break;
                // no loading in progress, try to load first/next fragment
                case LOADING_IDLE:
                    if (_level) {
                        if (_fragment_first_loaded == false) {
                            // just after seek, load first fragment
                            _loading_state = _loadfirstfragment(_seek_pos);
                        } else {
                            if (HLSSettings.maxBufferLength == 0 || _streamBuffer.audioBufferLength < HLSSettings.maxBufferLength) {
                                _loading_state = _loadnextfragment(_frag_previous);
                            }
                        }
                    } else {
                        // playlist not yet received
                        CONFIG::LOGGING {
                            Log.debug("_checkLoading : playlist not received for audio level:" + _hls.audioTrack);
                        }
                        _loading_state = LOADING_WAITING_LEVEL_UPDATE;
                    }
                    break;
                case LOADING_STALLED:
                    /* next consecutive fragment not found:
                    it could happen on live playlist :
                    - if bandwidth available is lower than lowest quality needed bandwidth
                    - after long pause */
                    CONFIG::LOGGING {
                        Log.warn("audio loading stalled: restart playback???");
                    }
                    /* seek to force a restart of the playback session  */
                    _streamBuffer.seek(-1);
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
                        /* try to reload fragment ... */
                        _loadfragment(_frag_current);
                        _loading_state = LOADING_IN_PROGRESS;
                    }
                    break;
                case LOADING_COMPLETED:
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.LAST_VOD_FRAGMENT_LOADED));
                    // stop loading timer as well, as no other fragments can be loaded
                    _timer.stop();
                    break;
                default:
                    CONFIG::LOGGING {
                        Log.error("invalid audio loading state:" + _loading_state);
                    }
                    break;
            }
        }

        public function seek(position : Number) : void {
            // reset IO Error when seeking
            _frag_retry_count = _key_retry_count = 0;
            _frag_retry_timeout = _key_retry_timeout = 1000;
            _loading_state = LOADING_IDLE;
            _seek_pos = position;
            _fragment_first_loaded = false;
            _frag_previous = null;
            _level = _hls.audioTracks[_hls.audioTrack].level;
            _hls.addEventListener(HLSEvent.AUDIO_LEVEL_LOADED, _audioLevelLoadedHandler);
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
                        Log.debug("loading audio fragment:" + _frag_current.url);
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
                if(HLSSettings.fragmentLoadSkipAfterMaxRetry == true) {
                    CONFIG::LOGGING {
                        Log.warn("max fragment load retry reached, skip fragment and load next one");
                    }
                    _frag_previous = _frag_current;
                    // set fragment first loaded to be true to ensure that we can skip first fragment as well
                    _fragment_first_loaded = true;
                    _loading_state = LOADING_IDLE;
                } else {
                    var hlsError : HLSError = new HLSError(HLSError.FRAGMENT_LOADING_ERROR, _frag_current.url, "I/O Error :" + message);
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
                }
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
                fragData.flushTags();
                _metrics.loading_begin_time = getTimer();

                // decrypt data if needed
                if (_frag_current.decrypt_url != null) {
                    _metrics.decryption_begin_time = getTimer();
                    fragData.decryptAES = new AES(_hls.stage, _keymap[_frag_current.decrypt_url], _frag_current.decrypt_iv, _fragDecryptProgressHandler, _fragDecryptCompleteHandler);
                    CONFIG::LOGGING {
                        Log.debug("init AES context:" + fragData.decryptAES);
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
            _frag_retry_count = 0;
            _frag_retry_timeout = 1000;
            var fragData : FragmentData = _frag_current.data;
            if (fragData.bytes == null) {
                CONFIG::LOGGING {
                    Log.warn("fragment size is null, invalid it and load next one");
                }
                _level.updateFragment(_frag_current.seqnum, false);
                _loading_state = LOADING_IDLE;
                return;
            }
            CONFIG::LOGGING {
                Log.debug("loading completed");
            }
            _metrics.loading_end_time = getTimer();
            _metrics.size = fragData.bytesLoaded;

            var _loading_duration : uint = _metrics.loading_end_time - _metrics.loading_request_time;
            CONFIG::LOGGING {
                Log.debug("Loading       duration/RTT/length/speed:" + _loading_duration + "/" + (_metrics.loading_begin_time - _metrics.loading_request_time) + "/" + _metrics.size + "/" + _metrics.bandwidth.toFixed(0) + " kb/s");
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
            if (_metrics.parsing_begin_time ==0) {
                _metrics.parsing_begin_time = getTimer();
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
                _demux = DemuxHelper.probe(data, _level, _fragParsingAudioSelectionHandler, _fragParsingProgressHandler, _fragParsingCompleteHandler, null);
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
                _metrics.decryption_end_time = getTimer();
                var decrypt_duration : Number = _metrics.decryption_end_time - _metrics.decryption_begin_time;
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
                _demux = DemuxHelper.probe(bytes, _level, _fragParsingAudioSelectionHandler, _fragParsingProgressHandler, _fragParsingCompleteHandler, null);
                if (_demux) {
                    bytes.position = 0;
                    _demux.append(bytes);
                }
            }

            if (_demux == null) {
                CONFIG::LOGGING {
                    Log.error("unknown audio fragment type");
                    if (HLSSettings.logDebug2) {
                        fragData.bytes.position = 0;
                        var bytes2 : ByteArray = new ByteArray();
                        fragData.bytes.readBytes(bytes2, 0, 512);
                        Log.debug2("frag dump(512 bytes)");
                        Log.debug2(Hex.fromArray(bytes2));
                    }
                }
                // invalid fragment
                _fraghandleIOError("invalid audio fragment received");
                fragData.bytes = null;
                return;
            }
            fragData.bytes = null;
            _demux.notifycomplete();
        }

        /** stop loading fragment **/
        public function stop() : void {
            _stop_load();
            _hls.removeEventListener(HLSEvent.AUDIO_LEVEL_LOADED, _audioLevelLoadedHandler);
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

        private function _loadfirstfragment(position : Number) : int {
            CONFIG::LOGGING {
                Log.debug("loadfirstaudiofragment(" + position + ")");
            }
            var frag : Fragment = _level.getFragmentBeforePosition(position);
            CONFIG::LOGGING {
                Log.debug("Loading       " + frag.seqnum + " of [" + (_level.start_seqnum) + "," + (_level.end_seqnum) + "]");
            }
            _loadfragment(frag);
            return LOADING_IN_PROGRESS;
        }

        /** Load a fragment **/
        private function _loadnextfragment(frag_previous : Fragment) : int {
            CONFIG::LOGGING {
                Log.debug("loadnextaudiofragment()");
            }
            var new_seqnum : Number;
            var last_seqnum : Number = -1;
            var frag : Fragment;

            last_seqnum = frag_previous.seqnum;
            if (last_seqnum == _level.end_seqnum) {
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
                if (new_seqnum < _level.start_seqnum) {
                    // loading stalled ! report to caller
                    return LOADING_STALLED;
                }
            }
            frag = _level.getFragmentfromSeqNum(new_seqnum);
            if (frag == null) {
                CONFIG::LOGGING {
                    Log.warn("error trying to load audio " + new_seqnum + " of [" + (_level.start_seqnum) + "," + (_level.end_seqnum) + "]");
                }
                return LOADING_WAITING_LEVEL_UPDATE;
            } else {
                CONFIG::LOGGING {
                    Log.debug("Loading audio " + new_seqnum + " of [" + (_level.start_seqnum) + "," + (_level.end_seqnum) + "]");
                }
                _loadfragment(frag);
                return LOADING_IN_PROGRESS;
            }
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
            _metrics = new HLSLoadMetrics(HLSLoaderTypes.FRAGMENT_ALTAUDIO);
            _metrics.level = _level.index;
            _metrics.id = frag.seqnum;
            _metrics.loading_request_time = getTimer();
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
                var hlsError : HLSError = new HLSError(HLSError.FRAGMENT_LOADING_ERROR, frag.url, error.message);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
        }

        /** triggered by demux, it should return the audio track to be parsed */
        private function _fragParsingAudioSelectionHandler(audioTrackList : Vector.<AudioTrack>) : AudioTrack {
            return audioTrackList[0];
        }

        /** triggered when demux has retrieved some tags from fragment **/
        private function _fragParsingProgressHandler(tags : Vector.<FLVTag>) : void {
            CONFIG::LOGGING {
                Log.debug2(tags.length + " tags extracted");
            }
            var fragData : FragmentData = _frag_current.data;
            fragData.appendTags(tags);

            if (fragData.metadata_tag_injected == false) {
                fragData.tags.unshift(_frag_current.metadataTag);
                fragData.metadata_tag_injected = true;
            }
            // provide tags to HLSNetStream
            _streamBuffer.appendTags(HLSLoaderTypes.FRAGMENT_ALTAUDIO,fragData.tags, fragData.tag_pts_min, fragData.tag_pts_max + fragData.tag_duration, _frag_current.continuity, _frag_current.start_time + fragData.tag_pts_start_offset / 1000);
            fragData.shiftTags();
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
            CONFIG::LOGGING {
                if (fragData.audio_found) {
                    Log.debug("m/M audio PTS:" + fragData.pts_min_audio + "/" + fragData.pts_max_audio);
                }
            }
            // Calculate bandwidth
            _metrics.parsing_end_time = getTimer();
            CONFIG::LOGGING {
                Log.debug("Total Process duration/length/bw:" + _metrics.processing_duration + "/" + _metrics.size + "/" + (_metrics.bandwidth / 1024).toFixed(0) + " kb/s");
            }
            try {
                CONFIG::LOGGING {
                    Log.debug("Loaded        " + _frag_current.seqnum + " of [" + (_level.start_seqnum) + "," + (_level.end_seqnum) + "],audio track " + _hls.audioTrack + " m/M PTS:" + fragData.pts_min + "/" + fragData.pts_max);
                }
                _level.updateFragment(_frag_current.seqnum, true, fragData.pts_min, fragData.pts_max + fragData.tag_duration);
                // set pts_start here, it might not be updated directly in updateFragment() if this loaded fragment has been removed from a live playlist
                fragData.pts_start = fragData.pts_min;
                _loading_state = LOADING_IDLE;
                if (fragData.tags.length) {
                    if (fragData.metadata_tag_injected == false) {
                        fragData.tags.unshift(_frag_current.metadataTag);
                        fragData.metadata_tag_injected = true;
                    }
                    _streamBuffer.appendTags(HLSLoaderTypes.FRAGMENT_ALTAUDIO,fragData.tags, fragData.tag_pts_min, fragData.tag_pts_max + fragData.tag_duration, _frag_current.continuity, _frag_current.start_time + fragData.tag_pts_start_offset / 1000);
                    _metrics.duration = fragData.pts_max + fragData.tag_duration - fragData.pts_min;
                    _metrics.id2 = fragData.tags.length;
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.TAGS_LOADED, _metrics));
                    fragData.shiftTags();
                }
                _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOADED, _metrics));
                _fragment_first_loaded = true;
                _frag_previous = _frag_current;
            } catch (error : Error) {
                hlsError = new HLSError(HLSError.OTHER_ERROR, _frag_current.url, error.message);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
            // speed up loading of new fragment
            _timer.start();
        }
    }
}