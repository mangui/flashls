package org.mangui.hls.stream {
    import flash.events.*;
    import flash.net.*;
    import flash.utils.ByteArray;
    import flash.utils.Timer;

    import org.mangui.hls.*;
    import org.mangui.hls.demux.*;
    import org.mangui.hls.flv.*;
    import org.mangui.hls.playlist.*;
    import org.mangui.hls.stream.*;
    import org.mangui.hls.model.Fragment;
    import org.mangui.hls.model.FragmentData;
    import org.mangui.hls.model.FragmentMetrics;
    import org.mangui.hls.model.Level;
    import org.mangui.hls.utils.AES;
    import org.mangui.hls.utils.PTS;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
        import org.mangui.hls.utils.Hex;
    }
    /** Class that fetches fragments. **/
    public class FragmentLoader {
        /** Reference to the HLS controller. **/
        private var _hls : HLS;
        /** reference to auto level manager */
        private var _autoLevelManager : AutoLevelManager;
        /** has manifest just being reloaded **/
        private var _manifest_just_loaded : Boolean = false;
        /** last updated level. **/
        private var _last_updated_level : int = 0;
        /** Callback for passing forward the fragment tags. **/
        private var _callback : Function;
        /** sequence number that's currently loading. **/
        private var _seqnum : int;
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
        private var _keymap : Object = new Object();
        /** Did the stream switch quality levels. **/
        private var _switchlevel : Boolean;
        /** Did a discontinuity occurs in the stream **/
        private var _hasDiscontinuity : Boolean;
        /* flag handling load cancelled (if new seek occurs for example) */
        private var _cancel_load : Boolean;
        /* variable to deal with IO Error retry */
        private var _bIOError : Boolean;
        private var _nIOErrorDate : Number = 0;
        /** boolean to track playlist PTS in loading */
        private var _pts_loading_in_progress : Boolean = false;
        /** boolean to indicate that PTS of new playlist has just been loaded */
        private var _pts_just_loaded : Boolean = false;
        /** boolean to indicate whether Buffer could request new fragment load **/
        private var _need_reload : Boolean = true;
        /** Reference to the alternate audio track list. **/
        private var _altAudioTrackLists : Vector.<AltAudioTrack>;
        /** list of audio tracks from demuxed fragments **/
        private var _audioTracksfromDemux : Vector.<HLSAudioTrack>;
        /** list of audio tracks from Manifest, matching with current level **/
        private var _audioTracksfromManifest : Vector.<HLSAudioTrack>;
        /** merged audio tracks list **/
        private var _audioTracks : Vector.<HLSAudioTrack>;
        /** current audio track id **/
        private var _audioTrackId : int;
        /** Timer used to monitor/schedule fragment download. **/
        private var _timer : Timer;
        /** requested seek position **/
        private var _seek_pos : Number;
        /** first fragment loaded ? **/
        private var _fragment_first_loaded : Boolean;
        /* demux instance */
        private var _demux : Demuxer;
        /* fragment retry timeout */
        private var _retry_timeout : Number;
        private var _retry_count : int;
        private var _frag_load_status : int;
        /** Store that a fragment load is in progress. **/
        private var _frag_loading : Boolean;
        /** reference to previous/current fragment */
        private var _frag_previous : Fragment;
        private var _frag_current : Fragment;
        /** reference to previous metrics */
        private var _metrics_previous : FragmentMetrics;

        /** Create the loader. **/
        public function FragmentLoader(hls : HLS) : void {
            _hls = hls;
            _autoLevelManager = new AutoLevelManager(hls);
            _hls.addEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.addEventListener(HLSEvent.LEVEL_LOADED, _levelLoadedHandler);
            _hls.addEventListener(HLSEvent.ALT_AUDIO_TRACKS_LIST_CHANGE, _altAudioTracksListChangedHandler);
            _timer = new Timer(100, 0);
            _timer.addEventListener(TimerEvent.TIMER, _checkLoading);
        };

        public function dispose() : void {
            stop();
            _autoLevelManager.dispose();
            _hls.removeEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);
            _hls.removeEventListener(HLSEvent.LEVEL_LOADED, _levelLoadedHandler);
            _hls.removeEventListener(HLSEvent.ALT_AUDIO_TRACKS_LIST_CHANGE, _altAudioTracksListChangedHandler);
        }

        /**  fragment loading Timer **/
        private function _checkLoading(e : Event) : void {
            // dont try to load any fragment if _level is not defined (should be the case if manifest not yet loaded for example
            if (isNaN(_level)) {
                return;
            }
            // check fragment loading status, try to load a new fragment if needed
            if (_frag_loading == false || _need_reload == true) {
                var loadstatus : int;
                // if previous fragment loading failed
                if (_bIOError) {
                    // compare current date and next retry date.
                    if (new Date().valueOf() < _nIOErrorDate) {
                        // too early to reload it, return...
                        return;
                    }
                }

                if (_fragment_first_loaded == false) {
                    // just after seek, load first fragment
                    loadstatus = _loadfirstfragment(_seek_pos);
                    // check if we need to load next fragment, check if buffer is full
                } else if (HLSSettings.maxBufferLength == 0 || _hls.stream.bufferLength < HLSSettings.maxBufferLength) {
                    loadstatus = _loadnextfragment();
                } else {
                    // no need to load any new fragment, buffer is full already
                    return;
                }
                if (loadstatus == 0) {
                    // good, new fragment being loaded
                    _frag_loading = true;
                } else if (loadstatus < 0) {
                    /* it means PTS requested is smaller than playlist start PTS.
                    it could happen on live playlist :
                    - if bandwidth available is lower than lowest quality needed bandwidth
                    - after long pause
                    seek to offset 0 to force a restart of the playback session  */
                    CONFIG::LOGGING {
                        Log.warn("long pause on live stream or bad network quality");
                    }
                    _timer.stop();
                    seek(-1, _callback);
                    return;
                } else if (loadstatus > 0) {
                    // seqnum not available in playlist
                    _frag_loading = false;
                }
            }
        }

        public function seek(position : Number, callback : Function) : void {
            // reset IO Error when seeking
            _bIOError = false;
            _retry_count = 0;
            _retry_timeout = 1000;
            _frag_loading = false;
            _callback = callback;
            _seek_pos = position;
            _fragment_first_loaded = false;
            _frag_previous = null;
            _timer.start();
        }

        public function set audioTrack(num : int) : void {
            if (_audioTrackId != num) {
                _audioTrackId = num;
                var ev : HLSEvent = new HLSEvent(HLSEvent.AUDIO_TRACK_CHANGE);
                ev.audioTrack = _audioTrackId;
                _hls.dispatchEvent(ev);
                CONFIG::LOGGING {
                    Log.info('Setting audio track to ' + num);
                }
            }
        }

        public function get audioTrack() : int {
            return _audioTrackId;
        }

        public function get audioTracks() : Vector.<HLSAudioTrack> {
            return _audioTracks;
        }

        public function get altAudioTracks() : Vector.<AltAudioTrack> {
            return _altAudioTrackLists;
        }

        /** key load completed. **/
        private function _keyLoadCompleteHandler(event : Event) : void {
            CONFIG::LOGGING {
                Log.debug("key loading completed");
            }
            var hlsError : HLSError;
            // Collect key data
            if ( _keystreamloader.bytesAvailable == 16 ) {
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
            if (HLSSettings.fragmentLoadMaxRetry == -1 || _retry_count < HLSSettings.fragmentLoadMaxRetry) {
                _bIOError = true;
                _nIOErrorDate = new Date().valueOf() + _retry_timeout;
                CONFIG::LOGGING {
                    Log.warn("retry fragment load in " + _retry_timeout + " ms, count=" + _retry_count);
                }
                /* exponential increase of retry timeout, capped to fragmentLoadMaxRetryTimeout */
                _retry_count++;
                _retry_timeout = Math.min(HLSSettings.fragmentLoadMaxRetryTimeout, 2 * _retry_timeout);
                // in case IO Error reload same fragment
                _seqnum--;
            } else {
                var hlsError : HLSError = new HLSError(HLSError.FRAGMENT_LOADING_ERROR, _frag_current.url, "I/O Error :" + message);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
            _need_reload = true;
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
                fragMetrics.loading_begin_time = new Date().valueOf();

                // decrypt data if needed
                if (_frag_current.decrypt_url != null) {
                    fragMetrics.decryption_begin_time = new Date().valueOf();
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
            _retry_count = 0;
            _retry_timeout = 1000;
            var fragData : FragmentData = _frag_current.data;
            if (fragData.bytes == null) {
                CONFIG::LOGGING {
                    Log.warn("fragment size is null, invalid it and load next one");
                }
                _levels[_level].updateFragment(_seqnum, false);
                _need_reload = true;
                return;
            }
            CONFIG::LOGGING {
                Log.debug("loading completed");
            }
            var fragMetrics : FragmentMetrics = _frag_current.metrics;
            fragMetrics.loading_end_time = new Date().valueOf();
            fragMetrics.size = fragData.bytesLoaded;

            var _loading_duration : uint = fragMetrics.loading_end_time - fragMetrics.loading_request_time;
            CONFIG::LOGGING {
                Log.debug("Loading       duration/RTT/length/speed:" + _loading_duration + "/" + (fragMetrics.loading_begin_time - fragMetrics.loading_request_time) + "/" + fragMetrics.size + "/" + ((8000 * fragMetrics.size / _loading_duration) / 1024).toFixed(0) + " kb/s");
            }
            _cancel_load = false;
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
                fragMetrics.parsing_begin_time = new Date().valueOf();
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
                _demux = probe(data);
            }
            if (_demux) {
                _demux.append(data);
            }
        }

        private function probe(data : ByteArray) : Demuxer {
            var fragData : FragmentData = _frag_current.data;
            data.position = 0;
            CONFIG::LOGGING {
                Log.debug("probe fragment type");
            }
            if (AACDemuxer.probe(data) == true) {
                CONFIG::LOGGING {
                    Log.debug("AAC ES found");
                }
                fragData.video_expected = false;
                return new AACDemuxer(_fragParsingAudioSelectionHandler, _fragParsingProgressHandler, _fragParsingCompleteHandler);
            } else if (MP3Demuxer.probe(data) == true) {
                CONFIG::LOGGING {
                    Log.debug("MP3 ES found");
                }
                fragData.video_expected = false;
                return new MP3Demuxer(_fragParsingAudioSelectionHandler, _fragParsingProgressHandler, _fragParsingCompleteHandler);
            } else if (TSDemuxer.probe(data) == true) {
                CONFIG::LOGGING {
                    Log.debug("MPEG2-TS found");
                }
                fragData.video_expected = true;
                return new TSDemuxer(_hls.stage, _fragParsingAudioSelectionHandler, _fragParsingProgressHandler, _fragParsingCompleteHandler);
            } else {
                CONFIG::LOGGING {
                    Log.debug("probe fails");
                }
                return null;
            }
        }

        private function _fragDecryptCompleteHandler() : void {
            if (_cancel_load == true)
                return;
            var fragData : FragmentData = _frag_current.data;

            if (fragData.decryptAES) {
                var fragMetrics : FragmentMetrics = _frag_current.metrics;
                fragMetrics.decryption_end_time = new Date().valueOf();
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
                _demux = probe(bytes);
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
            _cancel_load = true;
            _bIOError = false;
        }

        /** Catch IO and security errors. **/
        private function _keyLoadErrorHandler(event : ErrorEvent) : void {
            var txt : String;
            var code : int;
            if (event is SecurityErrorEvent) {
                txt = "Cannot load key: crossdomain access denied:" + event.text;
                code = HLSError.KEY_LOADING_CROSSDOMAIN_ERROR;
            } else {
                txt = "Cannot load key: IO Error:" + event.text;
                code = HLSError.KEY_LOADING_ERROR;
            }
            var hlsError : HLSError = new HLSError(code, _frag_current.decrypt_url, txt);
            _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
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

        private function _updateLevel(buffer : Number) : int {
            var level : int;
            if (_manifest_just_loaded) {
                level = _hls.startlevel;
            } else if (_fragment_first_loaded == false) {
                level = _hls.seeklevel;
            } else if (_bIOError == true) {
                /* in case IO Error has been raised, stick to same level */
                level = _level;
                /* in case fragment was loaded for PTS analysis, stick to same level */
            } else if (_pts_just_loaded == true) {
                _pts_just_loaded = false;
                level = _level;
                /* in case we are switching levels (waiting for playlist to reload) or seeking , stick to same level */
            } else if (_switchlevel == true) {
                level = _level;
            } else if (_manual_level == -1 && _levels.length > 1 ) {
                if (_metrics_previous) {
                    var last_segment_duration : Number = (_frag_previous ? 1000*_frag_previous.duration : 0);
                    level = _autoLevelManager.getnextlevel(_level, buffer, last_segment_duration, _metrics_previous.processing_duration, _metrics_previous.bandwidth);
                } else {
                    level = _autoLevelManager.getnextlevel(_level, buffer, 0, 0, 0);
                }
            } else if (_manual_level == -1 && _levels.length == 1 ) {
                level = 0;
            } else {
                level = _manual_level;
            }
            if (level != _level || _manifest_just_loaded) {
                _level = level;
                _switchlevel = true;
                _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, _level));
            }
            return level;
        }

        private function _loadfirstfragment(position : Number) : int {
            CONFIG::LOGGING {
                Log.debug("loadfirstfragment(" + position + ")");
            }
            _need_reload = false;
            _switchlevel = true;
            _updateLevel(0);

            // check if we received playlist for new level. if live playlist, ensure that new playlist has been refreshed
            if ((_levels[_level].fragments.length == 0) || (_hls.type == HLSTypes.LIVE && _last_updated_level != _level)) {
                // playlist not yet received
                CONFIG::LOGGING {
                    Log.debug("loadfirstfragment : playlist not received for level:" + _level);
                }
                return 1;
            }

            var seek_position : Number;
            if (_hls.type == HLSTypes.LIVE) {
                /* follow HLS spec :
                If the EXT-X-ENDLIST tag is not present
                and the client intends to play the media regularly (i.e. in playlist
                order at the nominal playback rate), the client SHOULD NOT
                choose a segment which starts less than three target durations from
                the end of the Playlist file */
                var maxLivePosition : Number = Math.max(0, _levels[_level].duration - 3 * _levels[_level].averageduration);
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

            var seqnum : int = _levels[_level].getSeqNumBeforePosition(position);
            var frag : Fragment = _levels[_level].getFragmentfromSeqNum(seqnum);
            _seqnum = seqnum;
            _hasDiscontinuity = true;
            CONFIG::LOGGING {
                Log.debug("Loading       " + _seqnum + " of [" + (_levels[_level].start_seqnum) + "," + (_levels[_level].end_seqnum) + "],level " + _level);
            }
            _loadfragment(frag);
            return 0;
        }

        /** Load a fragment **/
        private function _loadnextfragment() : int {
            CONFIG::LOGGING {
                Log.debug("loadnextfragment()");
            }
            _need_reload = false;

            _updateLevel(_hls.stream.bufferLength);
            // check if we received playlist for new level. if live playlist, ensure that new playlist has been refreshed
            if ((_levels[_level].fragments.length == 0) || (_hls.type == HLSTypes.LIVE && _last_updated_level != _level)) {
                // playlist not yet received
                CONFIG::LOGGING {
                    Log.debug("loadnextfragment : playlist not received for level:" + _level);
                }
                return 1;
            }

            var new_seqnum : Number;
            var last_seqnum : Number = -1;
            var log_prefix : String;
            var frag : Fragment;

            if (_switchlevel == false || _frag_previous.continuity == -1) {
                last_seqnum = _seqnum;
            } else {
                // level switch
                // trust program-time : if program-time defined in previous loaded fragment, try to find seqnum matching program-time in new level.
                if (_frag_previous.program_date) {
                    last_seqnum = _levels[_level].getSeqNumFromProgramDate(_frag_previous.program_date);
                    CONFIG::LOGGING {
                        Log.debug("loadnextfragment : getSeqNumFromProgramDate(level,date,cc:" + _level + "," + _frag_previous.program_date + ")=" + last_seqnum);
                    }
                }
                if (last_seqnum == -1) {
                    // if we are here, it means that no program date info is available in the playlist. try to get last seqnum position from PTS + continuity counter
                    last_seqnum = _levels[_level].getSeqNumNearestPTS(_frag_previous.data.pts_start, _frag_previous.continuity);
                    CONFIG::LOGGING {
                        Log.debug("loadnextfragment : getSeqNumNearestPTS(level,pts,cc:" + _level + "," + _frag_previous.data.pts_start + "," + _frag_previous.continuity + ")=" + last_seqnum);
                    }
                    if (last_seqnum == Number.POSITIVE_INFINITY) {
                        /* requested PTS above max PTS of this level:
                         * this case could happen when switching level at the edge of live playlist,
                         * in case playlist of new level is outdated
                         * return 1 to retry loading later.
                         */
                        return 1;
                    } else if (last_seqnum == -1) {
                        // if we are here, it means that we have no PTS info for this continuity index, we need to do some PTS probing to find the right seqnum
                        /* we need to perform PTS analysis on fragments from same continuity range
                        get first fragment from playlist matching with criteria and load pts */
                        last_seqnum = _levels[_level].getFirstSeqNumfromContinuity(_frag_previous.continuity);
                        CONFIG::LOGGING {
                            Log.debug("loadnextfragment : getFirstSeqNumfromContinuity(level,cc:" + _level + "," + _frag_previous.continuity + ")=" + last_seqnum);
                        }
                        if (last_seqnum == Number.NEGATIVE_INFINITY) {
                            // playlist not yet received
                            return 1;
                        }
                        /* when probing PTS, take previous sequence number as reference if possible */
                        new_seqnum = Math.min(_seqnum + 1, _levels[_level].getLastSeqNumfromContinuity(_frag_previous.continuity));
                        new_seqnum = Math.max(new_seqnum, _levels[_level].getFirstSeqNumfromContinuity(_frag_previous.continuity));
                        _pts_loading_in_progress = true;
                        log_prefix = "analyzing PTS ";
                    }
                }
            }

            if (_pts_loading_in_progress == false) {
                if (last_seqnum == _levels[_level].end_seqnum) {
                    // if last segment was last fragment of VOD playlist, notify last fragment loaded event, and return
                    if (_hls.type == HLSTypes.VOD) {
                        _hls.dispatchEvent(new HLSEvent(HLSEvent.LAST_VOD_FRAGMENT_LOADED));
                        // stop loading timer as well, as no other fragments can be loaded
                        _timer.stop();
                    }
                    return 1;
                } else {
                    // if previous segment is not the last one, increment it to get new seqnum
                    new_seqnum = last_seqnum + 1;
                    if (new_seqnum < _levels[_level].start_seqnum) {
                        // we are late ! report to caller
                        return -1;
                    }
                    frag = _levels[_level].getFragmentfromSeqNum(new_seqnum);
                    if (frag == null) {
                        CONFIG::LOGGING {
                            Log.warn("error trying to load " + new_seqnum + " of [" + (_levels[_level].start_seqnum) + "," + (_levels[_level].end_seqnum) + "],level " + _level);
                        }
                        return 1;
                    }
                    // check whether there is a discontinuity between last segment and new segment
                    _hasDiscontinuity = (frag.continuity != _frag_previous.continuity);
                    ;
                    log_prefix = "Loading       ";
                }
            }
            _seqnum = new_seqnum;
            frag = _levels[_level].getFragmentfromSeqNum(_seqnum);
            CONFIG::LOGGING {
                Log.debug(log_prefix + _seqnum + " of [" + (_levels[_level].start_seqnum) + "," + (_levels[_level].end_seqnum) + "],level " + _level);
            }
            _loadfragment(frag);
            return 0;
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
                _keystreamloader.addEventListener(Event.COMPLETE, _keyLoadCompleteHandler);
            }
            if (_hasDiscontinuity || _switchlevel) {
                _demux = null;
            }
            frag.metrics.loading_request_time = new Date().valueOf();
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

        /** Store the alternate audio track lists. **/
        private function _altAudioTracksListChangedHandler(event : HLSEvent) : void {
            _altAudioTrackLists = event.altAudioTracks;
            CONFIG::LOGGING {
                Log.info(_altAudioTrackLists.length + " alternate audio tracks found");
            }
        }

        /** Store the manifest data. **/
        private function _manifestLoadedHandler(event : HLSEvent) : void {
            _levels = event.levels;
            _level = 0;
            _manifest_just_loaded = true;
            // reset audio tracks
            _audioTrackId = -1;
            _audioTracksfromDemux = new Vector.<HLSAudioTrack>();
            _audioTracksfromManifest = new Vector.<HLSAudioTrack>();
            _audioTracksMerge();
        };

        /** Store the manifest data. **/
        private function _levelLoadedHandler(event : HLSEvent) : void {
            _last_updated_level = event.level;
            if (_last_updated_level == _level) {
                var altAudioTrack : AltAudioTrack;
                var audioTrackList : Vector.<HLSAudioTrack> = new Vector.<HLSAudioTrack>();
                var stream_id : String = _levels[_level].audio_stream_id;
                // check if audio stream id is set, and alternate audio tracks available
                if (stream_id && _altAudioTrackLists) {
                    // try to find alternate audio streams matching with this ID
                    for (var idx : int = 0; idx < _altAudioTrackLists.length; idx++) {
                        altAudioTrack = _altAudioTrackLists[idx];
                        if (altAudioTrack.group_id == stream_id) {
                            var isDefault : Boolean = (altAudioTrack.default_track == true || altAudioTrack.autoselect == true);
                            CONFIG::LOGGING {
                                Log.debug(" audio track[" + audioTrackList.length + "]:" + (isDefault ? "default:" : "alternate:") + altAudioTrack.name);
                            }
                            audioTrackList.push(new HLSAudioTrack(altAudioTrack.name, HLSAudioTrack.FROM_PLAYLIST, idx, isDefault));
                        }
                    }
                }
                // check if audio tracks matching with current level have changed since last time
                var audio_track_changed : Boolean = false;
                if (_audioTracksfromManifest.length != audioTrackList.length) {
                    audio_track_changed = true;
                } else {
                    for (idx = 0; idx < _audioTracksfromManifest.length; ++idx) {
                        if (_audioTracksfromManifest[idx].id != audioTrackList[idx].id) {
                            audio_track_changed = true;
                        }
                    }
                }
                // update audio list
                if (audio_track_changed) {
                    _audioTracksfromManifest = audioTrackList;
                    _audioTracksMerge();
                }
            }
        };

        // merge audio track info from demux and from manifest into a unified list that will be exposed to upper layer
        private function _audioTracksMerge() : void {
            var i : int;
            var default_demux : int = -1;
            var default_manifest : int = -1;
            var default_found : Boolean = false;
            var default_track_title : String;
            var audioTrack_ : HLSAudioTrack;
            _audioTracks = new Vector.<HLSAudioTrack>();

            // first look for default audio track.
            for (i = 0; i < _audioTracksfromManifest.length; i++) {
                if (_audioTracksfromManifest[i].isDefault) {
                    default_manifest = i;
                    break;
                }
            }
            for (i = 0; i < _audioTracksfromDemux.length; i++) {
                if (_audioTracksfromDemux[i].isDefault) {
                    default_demux = i;
                    break;
                }
            }
            /* default audio track from manifest should take precedence */
            if (default_manifest != -1) {
                audioTrack_ = _audioTracksfromManifest[default_manifest];
                // if URL set, default audio track is not embedded into MPEG2-TS
                if (_altAudioTrackLists[audioTrack_.id].url || default_demux == -1) {
                    CONFIG::LOGGING {
                        Log.debug("default audio track found in Manifest");
                    }
                    default_found = true;
                    _audioTracks.push(audioTrack_);
                } else {
                    // empty URL, default audio track is embedded into MPEG2-TS. retrieve track title from manifest and override demux title
                    default_track_title = audioTrack_.title;
                    if (default_demux != -1) {
                        CONFIG::LOGGING {
                            Log.debug("default audio track signaled in Manifest, will be retrieved from MPEG2-TS");
                        }
                        audioTrack_ = _audioTracksfromDemux[default_demux];
                        audioTrack_.title = default_track_title;
                        default_found = true;
                        _audioTracks.push(audioTrack_);
                    }
                }
            } else if (default_demux != -1 ) {
                audioTrack_ = _audioTracksfromDemux[default_demux];
                default_found = true;
                _audioTracks.push(audioTrack_);
            }
            // then append other audio tracks, start from manifest list, then continue with demux list
            for (i = 0; i < _audioTracksfromManifest.length; i++) {
                if (i != default_manifest) {
                    CONFIG::LOGGING {
                        Log.debug("alternate audio track found in Manifest");
                    }
                    audioTrack_ = _audioTracksfromManifest[i];
                    _audioTracks.push(audioTrack_);
                }
            }

            for (i = 0; i < _audioTracksfromDemux.length; i++) {
                if (i != default_demux) {
                    CONFIG::LOGGING {
                        Log.debug("alternate audio track retrieved from demux");
                    }
                    audioTrack_ = _audioTracksfromDemux[i];
                    _audioTracks.push(audioTrack_);
                }
            }
            // notify audio track list update
            _hls.dispatchEvent(new HLSEvent(HLSEvent.AUDIO_TRACKS_LIST_CHANGE));

            // switch track id to default audio track, if found
            if (default_found == true && _audioTrackId == -1) {
                audioTrack = 0;
            }
        }

        // should return PID of selected audio track
        private function _fragParsingAudioSelectionHandler(audioTrackList : Vector.<HLSAudioTrack>) : HLSAudioTrack {
            var audio_track_changed : Boolean = false;
            audioTrackList = audioTrackList.sort(function(a : HLSAudioTrack, b : HLSAudioTrack) : int {
                return a.id - b.id;
            });
            if (_audioTracksfromDemux.length != audioTrackList.length) {
                audio_track_changed = true;
            } else {
                for (var idx : int = 0; idx < _audioTracksfromDemux.length; ++idx) {
                    if (_audioTracksfromDemux[idx].id != audioTrackList[idx].id) {
                        audio_track_changed = true;
                    }
                }
            }
            // update audio list if changed
            if (audio_track_changed) {
                _audioTracksfromDemux = audioTrackList;
                _audioTracksMerge();
            }

            /* if audio track not defined, or audio from external source (playlist) 
            return null (demux audio not selected) */
            if (_audioTrackId == -1 || _audioTracks[_audioTrackId].source == HLSAudioTrack.FROM_PLAYLIST) {
                _frag_current.data.audio_expected = false;
                return null;
            } else {
                // source is demux,return selected audio track
                _frag_current.data.audio_expected = true;
                return _audioTracks[_audioTrackId];
            }
        }

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
                if (tag.type == FLVTag.AAC_HEADER || tag.type == FLVTag.AAC_RAW || tag.type == FLVTag.MP3_RAW) {
                    fragData.audio_found = true;
                    fragData.tags_pts_min_audio = Math.min(fragData.tags_pts_min_audio, tag.pts);
                    fragData.tags_pts_max_audio = Math.max(fragData.tags_pts_max_audio, tag.pts);
                    fragData.pts_min_audio = Math.min(fragData.pts_min_audio, tag.pts);
                    fragData.pts_max_audio = Math.max(fragData.pts_max_audio, tag.pts);
                } else {
                    fragData.video_found = true;
                    fragData.tags_pts_min_video = Math.min(fragData.tags_pts_min_video, tag.pts);
                    fragData.tags_pts_max_video = Math.max(fragData.tags_pts_max_video, tag.pts);
                    fragData.pts_min_video = Math.min(fragData.pts_min_video, tag.pts);
                    fragData.pts_max_video = Math.max(fragData.pts_max_video, tag.pts);
                }
                fragData.tags.push(tag);
            }

            /* do progressive buffering here. 
             * only do it in case :
             *      it is not a cold start use case. in case of cold start, accept progressive buffering if we start playback from lowest level
             */
            if (( _fragment_first_loaded || (_manifest_just_loaded && HLSSettings.startFromLevel != -1) )) {
                if (fragData.audio_expected && !fragData.audio_found) {
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

                    if (_pts_loading_in_progress == true) {
                        _pts_loading_in_progress = false;
                        _levels[_level].updateFragment(_seqnum, true, fragData.pts_min, fragData.pts_min + _frag_current.duration * 1000);
                        /* in case we are probing PTS, retrieve PTS info and synchronize playlist PTS / sequence number */
                        CONFIG::LOGGING {
                            Log.debug("analyzed  PTS " + _seqnum + " of [" + (_levels[_level].start_seqnum) + "," + (_levels[_level].end_seqnum) + "],level " + _level + " m PTS:" + fragData.pts_min);
                        }
                        /* check if fragment loaded for PTS analysis is the next one
                        if this is the expected one, then continue
                        if not, then cancel current fragment loading, next call to loadnextfragment() will load the right seqnum
                         */
                        var next_seqnum : Number = _levels[_level].getSeqNumNearestPTS(_frag_previous.data.pts_start, _frag_current.continuity) + 1;
                        // CONFIG::LOGGING {
                        // Log.info("seq/next:"+ _seqnum+"/"+ next_seqnum);
                        // }
                        if (next_seqnum != _seqnum) {
                            _pts_just_loaded = true;
                            CONFIG::LOGGING {
                                Log.debug("PTS analysis done on " + _seqnum + ", matching seqnum is " + next_seqnum + " of [" + (_levels[_level].start_seqnum) + "," + (_levels[_level].end_seqnum) + "],cancel loading and get new one");
                            }
                            // cancel loading
                            _stop_load();
                            // tell that new fragment could be loaded
                            _need_reload = true;
                            return;
                        }
                    }
                    // provide tags to HLSNetStream
                    _callback(fragData.tags, fragData.pts_min, fragData.pts_max, _hasDiscontinuity, min_offset, _frag_current.program_date + fragData.tag_pts_start_offset);
                    var processing_duration : Number = (new Date().valueOf() - _frag_current.metrics.loading_request_time);
                    var bandwidth : Number = Math.round(fragData.bytesLoaded * 8000 / processing_duration);
                    var tagsMetrics : HLSMetrics = new HLSMetrics(_level, bandwidth, fragData.tag_pts_end_offset, processing_duration);
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.TAGS_LOADED, tagsMetrics));
                    _hasDiscontinuity = false;
                    fragData.tags = new Vector.<FLVTag>();
                    fragData.tags_pts_min_audio = fragData.tags_pts_max_audio;
                    fragData.tags_pts_min_video = fragData.tags_pts_max_video;
                }
            }
        }

        /** Handles the actual reading of the TS fragment **/
        private function _fragParsingCompleteHandler() : void {
            if (_cancel_load == true)
                return;
            var hlsError : HLSError;

            // reset IO error, as if we reach this point, it means fragment has been successfully retrieved and demuxed
            _bIOError = false;

            var fragData : FragmentData = _frag_current.data;
            if (!fragData.audio_found && !fragData.video_found) {
                hlsError = new HLSError(HLSError.FRAGMENT_PARSING_ERROR, _frag_current.url, "error parsing fragment, no tag found");
                _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
            if (fragData.audio_found) {
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
            } else {
                // report audio-only segment
                _hls.dispatchEvent(new HLSEvent(HLSEvent.AUDIO_ONLY));
            }

            // Calculate bandwidth
            var fragMetrics : FragmentMetrics = _frag_current.metrics;
            fragMetrics.parsing_end_time = new Date().valueOf();
            CONFIG::LOGGING {
                Log.debug("Total Process duration/length/bw:" + fragMetrics.processing_duration + "/" + fragMetrics.size + "/" + (fragMetrics.bandwidth / 1024).toFixed(0) + " kb/s");
            }

            if (_manifest_just_loaded) {
                _manifest_just_loaded = false;
                if (HLSSettings.startFromLevel == -1) {
                    // check if we can directly switch to a better bitrate, in case download bandwidth is enough
                    var bestlevel : int = _autoLevelManager.getbestlevel(fragMetrics.bandwidth);
                    if (bestlevel > _level) {
                        CONFIG::LOGGING {
                            Log.info("enough download bandwidth, adjust start level from " + _level + " to " + bestlevel);
                        }
                        // let's directly jump to the accurate level to improve quality at player start
                        _level = bestlevel;
                        _need_reload = true;
                        _switchlevel = true;
                        _hls.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, _level));
                        return;
                    }
                }
            }

            try {
                _switchlevel = false;
                CONFIG::LOGGING {
                    Log.debug("Loaded        " + _seqnum + " of [" + (_levels[_level].start_seqnum) + "," + (_levels[_level].end_seqnum) + "],level " + _level + " m/M PTS:" + fragData.pts_min + "/" + fragData.pts_max);
                }
                var start_offset : Number = _levels[_level].updateFragment(_seqnum, true, fragData.pts_min, fragData.pts_max);
                _hls.dispatchEvent(new HLSEvent(HLSEvent.PLAYLIST_DURATION_UPDATED, _levels[_level].duration));
                _frag_loading = false;

                var tagsMetrics : HLSMetrics = new HLSMetrics(_level, fragMetrics.bandwidth, fragData.pts_max - fragData.pts_min, fragMetrics.processing_duration);

                if (fragData.tags.length) {
                    _callback(fragData.tags, fragData.tag_pts_min, fragData.tag_pts_max, _hasDiscontinuity, start_offset + fragData.tag_pts_start_offset / 1000, _frag_current.program_date + fragData.tag_pts_start_offset);
                    _hls.dispatchEvent(new HLSEvent(HLSEvent.TAGS_LOADED, tagsMetrics));
                    fragData.tags_pts_min_audio = fragData.tags_pts_max_audio;
                    fragData.tags_pts_min_video = fragData.tags_pts_max_video;
                    _hasDiscontinuity = false;
                    fragData.tags = new Vector.<FLVTag>();
                }
                _pts_loading_in_progress = false;
                _hls.dispatchEvent(new HLSEvent(HLSEvent.FRAGMENT_LOADED, tagsMetrics));
                _fragment_first_loaded = true;
                _frag_previous = _frag_current;
                _metrics_previous = _frag_previous.metrics;
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