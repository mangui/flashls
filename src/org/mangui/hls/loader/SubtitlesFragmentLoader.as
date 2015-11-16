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
	import org.mangui.hls.constant.HLSPlayStates;
	import org.mangui.hls.constant.HLSTypes;
	import org.mangui.hls.event.HLSEvent;
	import org.mangui.hls.event.HLSMediatime;
	import org.mangui.hls.model.Fragment;
	import org.mangui.hls.model.Subtitles;
	import org.mangui.hls.utils.WebVTTParser;

	CONFIG::LOGGING {
		import org.mangui.hls.utils.Log;
	}
	
	/**
	 * Subtitles fragment loader and sequencer
	 * @author	Neil Rackett
	 */
	public class SubtitlesFragmentLoader {
		
		protected var _hls:HLS;
		protected var _loader:URLLoader;
		protected var _fragments:Vector.<Fragment>;
		protected var _fragment:Fragment;
		protected var _seqSubs:Dictionary;
		protected var _seqNum:Number;
		protected var _seqStartPosition:Number;
		protected var _currentSubtitles:Subtitles;
		protected var _seqIndex:int;
		protected var _remainingRetries:int;
		protected var _retryTimeout:uint;
		protected var _emptySubtitles:Subtitles;
		
		public function SubtitlesFragmentLoader(hls:HLS) {
			
			_hls = hls;
			_hls.addEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
			_hls.addEventListener(HLSEvent.SUBTITLES_LEVEL_LOADED, subtitlesLevelLoadedHandler);
			_hls.addEventListener(HLSEvent.FRAGMENT_PLAYING, fragmentPlayingHandler);
			_hls.addEventListener(HLSEvent.MEDIA_TIME, mediaTimeHandler);
			_hls.addEventListener(HLSEvent.SEEK_STATE, seekStateHandler);
			_hls.addEventListener(HLSEvent.PLAYBACK_STATE, playbackStateHandler);
			
			_loader = new URLLoader();
			_loader.addEventListener(Event.COMPLETE, loader_completeHandler);
			_loader.addEventListener(IOErrorEvent.IO_ERROR, loader_errorHandler);
			_loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, loader_errorHandler);
			
			_seqSubs = new Dictionary(true);
			_seqIndex = 0;
			_emptySubtitles = new Subtitles(-1, -1, '');
		}
		
		public function dispose():void {
			
			stop();
			
			_hls.removeEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
			_hls.removeEventListener(HLSEvent.SUBTITLES_LEVEL_LOADED, subtitlesLevelLoadedHandler);
			_hls.removeEventListener(HLSEvent.FRAGMENT_PLAYING, fragmentPlayingHandler);
			_hls.removeEventListener(HLSEvent.MEDIA_TIME, mediaTimeHandler);
			_hls.removeEventListener(HLSEvent.SEEK_STATE, seekStateHandler);
			_hls.removeEventListener(HLSEvent.PLAYBACK_STATE, playbackStateHandler);
			_hls = null;
			
			_loader.removeEventListener(Event.COMPLETE, loader_completeHandler);
			_loader.removeEventListener(IOErrorEvent.IO_ERROR, loader_errorHandler);
			_loader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, loader_errorHandler);
			_loader = null;
			
			_seqSubs = null;
		}
		
		/**
		 * The currently displayed subtitles
		 */
		public function get currentSubtitles():Subtitles {
			return _currentSubtitles;
		}
		
		/**
		 * Stop any currently loading subtitles
		 */
		public function stop():void {
			
			if (_currentSubtitles)
			{
				_currentSubtitles = null;
				_hls.dispatchEvent(new HLSEvent(HLSEvent.SUBTITLES_CHANGE, _emptySubtitles));
			}
			
			try {
				_loader.close(); 
			} catch (e:Error) {};
		}
		
		/**
		 * Handle the user switching subtitles track
		 */
		protected function subtitlesTrackSwitchHandler(event:HLSEvent):void {
			
			CONFIG::LOGGING {
				Log.debug("Switching to subtitles track "+event.subtitlesTrack);
			}
			
			stop();
			
			_seqSubs = new Dictionary();
			_seqIndex = 0;			
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
			_fragments = _hls.subtitlesTracks[_hls.subtitlesTrack].level.fragments;
			loadNextFragment();
		}
		
		/**
		 * Sync subtitles with the current audio/video fragments
		 * 
		 * Live subtitles are assumed to contain times reletive to the current
		 * sequence, and VOD content relative to the entire video duration 
		 */
		protected function fragmentPlayingHandler(event:HLSEvent):void {
			
			if (_hls.type == HLSTypes.LIVE) {
				
				// Keep track all the time to prevent delay in subtitles starting when selected
				_seqNum = event.playMetrics.seqnum;
				_seqStartPosition = _hls.position;
				_seqIndex = 0;
				
				// Only needed if subs are selected and being listened for
				if (_hls.subtitlesTrack != -1
					&& _hls.hasEventListener(HLSEvent.SUBTITLES_CHANGE)) {
					
					_currentSubtitles = _emptySubtitles;
					
					try {
						var targetDuration:Number = _hls.subtitlesTracks[_hls.subtitlesTrack].level.targetduration
						var dvrWindowDuration:Number = _hls.liveSlidingMain;
						var firstSeqNum:Number = _seqNum - (dvrWindowDuration/targetDuration);
						
						for (var seqNum:* in _seqSubs) {
							if (seqNum is Number && seqNum < firstSeqNum) {
								delete _seqSubs[seqNum];
							}
						}
					}
					catch(e:Error) {}
				}
				
				return;
			}
			
			_seqNum = 0;
			_seqStartPosition = 0;
		}
		
		/**
		 * The current position relative to the start of the current sequence 
		 * (live) or to the entire video (VOD)
		 */
		protected function get seqPosition():Number {
			return _hls.position - _seqStartPosition;
		}
		
		/**
		 * Match subtitles to the current playhead position and dispatch
		 * events as appropriate
		 */
		protected function mediaTimeHandler(event:HLSEvent):void {
			// If subtitles are disabled or nobody's listening, there's nothing to do
			if (_hls.subtitlesTrack == -1 || !_hls.hasEventListener(HLSEvent.SUBTITLES_CHANGE)) {
				return;
			}
			
			var position:Number = seqPosition;
			
			// If the subtitles haven't changed, there's nothing to do
			if (isCurrent(_currentSubtitles, position)) return;
			
			// Get the subtitles list for the current sequence (always 0 for VOD)
			var subs:Vector.<Subtitles> = _seqSubs[_seqNum];
			
			if (subs) {
				var mt:HLSMediatime = event.mediatime;
				var matchingSubtitles:Subtitles = _emptySubtitles;
				var i:uint;
				var length:uint = subs.length;
				
				for (i=_seqIndex; i<length; ++i) {
					
					var subtitles:Subtitles = subs[i];
					
					// There's no point searching more that we need to!
					if (subtitles.startPosition > position) {
						break;
					}
					
					if (isCurrent(subtitles, position)) {
						matchingSubtitles = subtitles;
						break;
					}
				}
				
				// To keep the search for the next subtitles as inexpensive as possible
				// for big VOD, we start the next search at the previous jump off point
				if (_hls.type == HLSTypes.VOD) {
					_seqIndex = i;
				}
				
				if (matchingSubtitles != _currentSubtitles) {
					
					CONFIG::LOGGING {
						Log.debug("Changing subtitles to: "+matchingSubtitles);
					}
					
					_currentSubtitles = matchingSubtitles;
					_hls.dispatchEvent(new HLSEvent(HLSEvent.SUBTITLES_CHANGE, matchingSubtitles));
				}
			}
		}
		
		/**
		 * Are the specified subtitles the correct ones for the specified position?
		 */
		protected function isCurrent(subtitles:Subtitles, position:Number):Boolean {
			return subtitles 
				&& subtitles.startPosition <= position 
				&& subtitles.endPosition >= position
		}
		
		/**
		 * When the media seeks, we reset the index from which we look for the next subtitles
		 */
		protected function seekStateHandler(event:Event):void {
			_seqIndex = 0;
		}
		
		/**
		 * Load the next subtitles fragment (if it hasn't been loaded already) 
		 */
		protected function loadNextFragment():void {
			
			if (!_fragments || !_fragments.length) return;
			
			_remainingRetries = HLSSettings.fragmentLoadMaxRetry;
			_fragment = _fragments.shift();
			
			if (!_seqSubs[_fragment.seqnum]) {
				loadFragment();
			} else {
				loadNextFragment();
			}
		}
		
		/**
		 * The load operation was separated from loadNextFragment() to enable retries
		 */
		protected function loadFragment():void {
			clearTimeout(_retryTimeout);
			_loader.load(new URLRequest(_fragment.url));
		}
		
		/**
		 * Parse the loaded WebVTT subtitles
		 */
		protected function loader_completeHandler(event:Event):void {
			
			var parsed:Vector.<Subtitles> = WebVTTParser.parse(_loader.data);
			
			if (_hls.type == HLSTypes.LIVE) {
				_seqSubs[_fragment.seqnum] = parsed;
			} else {
				_seqSubs[_fragment.seqnum] = true;
				_seqSubs[0] = (_seqSubs[0] is Vector.<Subtitles> ? _seqSubs[0] : new Vector.<Subtitles>).concat(parsed);
			}
			
			CONFIG::LOGGING {
				Log.debug("Loaded "+parsed.length+" subtitles from "+_fragment.url.split("/").pop()+":\n"+parsed.join("\n"));
			}
			
			loadNextFragment();
		}
		
		/**
		 * If the subtitles fail to load, give up and load the next subtitles fragment
		 */
		protected function loader_errorHandler(event:ErrorEvent):void {
			
			CONFIG::LOGGING {
				Log.error("Error "+event.errorID+" while loading "+_fragment.url+": "+event.text);
				Log.error(_remainingRetries+" retries remaining");
			}
			
			// We only wait 1s to retry because if we waited any longer the playhead will probably
			// have moved past the position where these subtitles were supposed to be used
			if (_remainingRetries--) {
				clearTimeout(_retryTimeout);
				_retryTimeout = setTimeout(loadFragment, 1000);
			} else {
				loadNextFragment();
			}
		}
		
	}

}
