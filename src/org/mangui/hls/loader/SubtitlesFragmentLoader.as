/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.loader {
    
    import flash.events.ErrorEvent;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.utils.Dictionary;
    import flash.utils.clearTimeout;
    import flash.utils.setTimeout;
    
    import org.mangui.hls.HLS;
    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.constant.HLSLoaderTypes;
    import org.mangui.hls.constant.HLSPlayStates;
    import org.mangui.hls.constant.HLSTypes;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.flv.FLVTag;
    import org.mangui.hls.model.Fragment;
    import org.mangui.hls.model.Subtitle;
    import org.mangui.hls.stream.StreamBuffer;
    import org.mangui.hls.utils.WebVTTParser;
    import org.mangui.hls.utils.hls_internal;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
    
    use namespace hls_internal;
    
    /**
     * Subtitles (WebVTT) fragment loader
     * @author    Neil Rackett
     */
    public class SubtitlesFragmentLoader {
        
        protected var _hls:HLS;
        
        // Loader
        protected var _streamBuffer:StreamBuffer;
        protected var _loader:URLLoader;
        protected var _fragments:Vector.<Fragment> = new Vector.<Fragment>;
        protected var _fragment:Fragment;
        protected var _retryDelay:int;
        protected var _retryRemaining:int;
        protected var _retryTimeout:uint;
		/** Cache of previously loaded subtitles tags (VOD only) */
        protected var _cache:Dictionary = new Dictionary(true);
		/** Track IDs of subtitles tracks that have alreadsy been loaded and appended to the stream (VOD only) */
        protected var _appended:Dictionary = new Dictionary(true);
		
        public function SubtitlesFragmentLoader(hls:HLS, streamBuffer:StreamBuffer) {

            _hls = hls;
            _streamBuffer = streamBuffer;
            
            _hls.addEventListener(HLSEvent.MANIFEST_LOADING, manifestLoadingHandler);
            _hls.addEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
            _hls.addEventListener(HLSEvent.SUBTITLES_LEVEL_LOADED, subtitlesLevelLoadedHandler);
            _hls.addEventListener(HLSEvent.SEEK_STATE, seekStateHandler);
            
            _loader = new URLLoader();
            _loader.addEventListener(Event.COMPLETE, loader_completeHandler);
            _loader.addEventListener(IOErrorEvent.IO_ERROR, loader_errorHandler);
            _loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, loader_errorHandler);
        }
        
        public function dispose():void {
            
            stop();
            
            _hls.removeEventListener(HLSEvent.MANIFEST_LOADING, manifestLoadingHandler);
            _hls.removeEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
            _hls.removeEventListener(HLSEvent.SUBTITLES_LEVEL_LOADED, subtitlesLevelLoadedHandler);
            _hls.removeEventListener(HLSEvent.SEEK_STATE, seekStateHandler);
            _hls = null;
            
            _loader.removeEventListener(Event.COMPLETE, loader_completeHandler);
            _loader.removeEventListener(IOErrorEvent.IO_ERROR, loader_errorHandler);
            _loader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, loader_errorHandler);
            _loader = null;
            
            _fragments = null;
            _fragment = null;
            _cache = null;
            _appended = null;
        }
        
        /**
         * Stop any currently loading subtitles
         */
        public function stop():void {
			CONFIG::LOGGING {
				Log.debug(this+" Stopping");
			}
            
			try { _loader.close(); } 
            catch (e:Error) {};
			
            _fragments = new Vector.<Fragment>();
        }
        
        /**
         * Get ready for a new stream
         */
        protected function manifestLoadingHandler(event:HLSEvent):void {
			CONFIG::LOGGING {
				Log.debug(this+" Manifest loading, stopping loading and resetting cache");
			}
            
			stop();
			
            _cache = new Dictionary(true);
            _appended = new Dictionary(true);
        }
        
        /**
         * Handle the user switching subtitles track
         */
        protected function subtitlesTrackSwitchHandler(event:HLSEvent):void {
            CONFIG::LOGGING {
                Log.debug("Switching to subtitles track "+event.subtitlesTrack);
            }
            stop();
        }
        
        protected function playbackStateHandler(event:HLSEvent):void {
            if (event.state == HLSPlayStates.IDLE) {
                stop();
            }
        }
        
        /**
         * Preload all of the subtitles listed in the loaded subtitles level definitions
         */
        protected function subtitlesLevelLoadedHandler(event:HLSEvent):void {
            if (_hls.subtitlesTrack != -1) {
				CONFIG::LOGGING {
					Log.debug(this+" Loading subtitles fragments for track "+_hls.subtitlesTrack);
				}
                _fragments = _fragments.concat(_hls.subtitlesTracks[_hls.subtitlesTrack].level.fragments);
                loadNextFragment();
            }
        }
        
        /**
         * Flashls flushes tags on seek, which wipes out VOD subtitles because they're
         * all loaded at the start, so we need to reload them (live subtitles are
         * per fragment, so they should take care of themselves)
         */
        protected function seekStateHandler(event:HLSEvent):void {
            if (_hls.type == HLSTypes.VOD && _hls.watched) {
				CONFIG::LOGGING {
					Log.debug(this+" Re-appending subtitles after seek");
				}
				_appended = new Dictionary(true);
                subtitlesLevelLoadedHandler(event);
            }
        }
        
        /**
         * Load the next subtitles fragment 
         */
        protected function loadNextFragment():void {
            if (_fragments.length) {
				CONFIG::LOGGING {
					Log.debug(this+" Loading next subtitles fragment");
				}
                _retryRemaining = HLSSettings.fragmentLoadMaxRetry;
                _retryDelay = 1000;
                _fragment = _fragments.shift();
                loadFragment();
            } else if (_hls.type == HLSTypes.VOD) {
                _appended[_hls.subtitlesTrack] = true;
            }
        }
        
        /**
         * Load fragment
         */
        protected function loadFragment():void {
			
			clearTimeout(_retryTimeout);
            
			if (_appended[_hls.subtitlesTrack]) {
                CONFIG::LOGGING {
                    Log.debug(this+" Subtitles fragments for track "+_hls.subtitlesTrack+" already loaded");
                }
                return;
            }
			
            if (_fragment) {
				
				CONFIG::LOGGING {
					Log.debug(this+" Loading subtitles fragment: "+_fragment.url);
				}
				
				// Have we already loaded the fragment?
				if (_cache[_fragment]) {
	                var cached:Vector.<FLVTag> = _cache[_fragment] as Vector.<FLVTag>;
	                if (cached) {
	                    appendTags(_fragment, cached);
	                    loadNextFragment();
					}
				} else {
					_loader.load(new URLRequest(_fragment.url));
				}
				
            } else {
                loadNextFragment();
            }
        }
        
        /**
         * Parse the loaded WebVTT data
         */
        protected function loader_completeHandler(event:Event):void {
            
			CONFIG::LOGGING {
				Log.debug(this+" Loaded "+_fragment.url);
			}
			
            var subtitles:Vector.<Subtitle> = WebVTTParser.parse(_loader.data, _fragment.level, _fragment.program_date);
			
			if (_hls.type == HLSTypes.VOD) {
				subtitles = padSubtitles(subtitles);
			}
			
			// Prepare FLVTag to be appended to the stream
			var tags:Vector.<FLVTag> = toTags(subtitles);
			if (tags) {
                if (_hls.type == HLSTypes.VOD) {
                    _cache[_fragment] = tags;
                }
                appendTags(_fragment, tags);
            }
			
            loadNextFragment();
        }
        
		/**
		 * Fill in the gaps between subtitles with blanks
		 */
		protected function padSubtitles(subtitles:Vector.<Subtitle>):Vector.<Subtitle> {
			
			// Fill all the gaps
			for (var i:uint=0; i<subtitles.length-1; i++) {
				
				var nextSubtitle:Subtitle = subtitles[i+1];
				var subtitle:Subtitle = subtitles[i];
				
				if (subtitle.endPTS < nextSubtitle.startPTS) {
					subtitles.splice(i+1, 0, new Subtitle(_fragment.level, '', subtitle.endPTS, nextSubtitle.startPTS, subtitle.endPosition, nextSubtitle.startPosition, subtitle.endDate, nextSubtitle.startDate));
					++i;
				}
			}
			
			// ... and add a blank one at the end
			subtitles.push(new Subtitle(_fragment.level, '', subtitle.endPTS, subtitle.endPTS, subtitle.endPosition, subtitle.endPosition, subtitle.endDate, subtitle.endDate));
			
			return subtitles;
		}
		
        /**
         * Convert subtitles into FLVTag that can be appended to the stream
         */
        protected function toTags(subtitles:Vector.<Subtitle>):Vector.<FLVTag> {
            
            CONFIG::LOGGING {
                Log.debug("Converting "+subtitles.length+" subtitles into tags");
            }
            
            var subtitle:Subtitle;
            var tags:Vector.<FLVTag> = new Vector.<FLVTag>();
            
            
            for each (subtitle in subtitles) {
                tags.push(subtitle.$toTag());
            }
            
            return tags;
        }
		
        /**
         * Append subtitle tags to the stream
         */
        protected function appendTags(fragment:Fragment, tags:Vector.<FLVTag>):void {
            if (fragment && tags && tags.length) {
				CONFIG::LOGGING {
					Log.debug(this+" Appending "+tags.length+" onTextData tags for seqnum "+fragment.seqnum+" to the stream at "+fragment.start_time);
				}
				_streamBuffer.appendTags(
                    HLSLoaderTypes.FRAGMENT_SUBTITLES, 
                    fragment.level,
                    fragment.seqnum, 
                    tags,
                    tags[0].pts,
                    tags[tags.length-1].pts,
                    fragment.continuity,
                    fragment.start_time
                );
            }
        }
        
        /**
         * If the subtitles fail to load, give up and load the next subtitles fragment
         */
        protected function loader_errorHandler(event:ErrorEvent):void {
            CONFIG::LOGGING {
                Log.error(this+" Error "+event.errorID+" while loading "+_fragment.url+": "+event.text);
            }
            if (_retryRemaining--) {
                var delay:Number = _retryDelay * 2;
                clearTimeout(_retryTimeout);
                if (delay <= HLSSettings.fragmentLoadMaxRetryTimeout) {
					CONFIG::LOGGING {
						Log.error(this+" Retrying in "+_retryDelay+"ms");
					}
                    _retryTimeout = setTimeout(loadFragment, _retryDelay);
                }
            }
            loadNextFragment();
        }
    }

}
