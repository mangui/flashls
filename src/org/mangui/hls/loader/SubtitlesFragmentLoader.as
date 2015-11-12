/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.loader
{
	import flash.events.ErrorEvent;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.SecurityErrorEvent;
	import flash.net.URLLoader;
	import flash.net.URLRequest;
	
	import org.mangui.hls.HLS;
	import org.mangui.hls.event.HLSEvent;
	import org.mangui.hls.event.HLSMediatime;
	import org.mangui.hls.model.Fragment;
	import org.mangui.hls.model.Subtitles;
	import org.mangui.hls.utils.WebVTTParser;

	CONFIG::LOGGING 
	{
		import org.mangui.hls.utils.Log;
	}
	
	/**
	 * Subtitles fragment loader and sequencer
	 * @author	Neil Rackett
	 */
	public class SubtitlesFragmentLoader
	{
		protected var _hls:HLS;
		protected var _loader:URLLoader;
		protected var _fragments:Vector.<Fragment>;
		protected var _fragment:Fragment;
		protected var _seqSubtitles:Array;
		protected var _seqNum:Number;
		protected var _seqPosition:Number;
		protected var _currentSubtitles:Subtitles;
		
		public function SubtitlesFragmentLoader(hls:HLS)
		{
			_hls = hls;
			_hls.addEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
			_hls.addEventListener(HLSEvent.SUBTITLES_LEVEL_LOADED, subtitlesLevelLoadedHandler);
			_hls.addEventListener(HLSEvent.FRAGMENT_PLAYING, fragmentPlayingHandler);
			_hls.addEventListener(HLSEvent.MEDIA_TIME, mediaTimeHandler);
			
			_loader = new URLLoader();
			_loader.addEventListener(Event.COMPLETE, loader_completeHandler);
			_loader.addEventListener(IOErrorEvent.IO_ERROR, loader_errorHandler);
			_loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, loader_errorHandler);
			
			_seqSubtitles = [];
		}
		
		public function dispose():void
		{
			stop();
			
			_hls.removeEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
			_hls.removeEventListener(HLSEvent.SUBTITLES_LEVEL_LOADED, subtitlesLevelLoadedHandler);
			_hls.removeEventListener(HLSEvent.FRAGMENT_PLAYING, fragmentPlayingHandler);
			_hls.removeEventListener(HLSEvent.MEDIA_TIME, mediaTimeHandler);
			_hls = null;
			
			_loader.removeEventListener(Event.COMPLETE, loader_completeHandler);
			_loader.removeEventListener(IOErrorEvent.IO_ERROR, loader_errorHandler);
			_loader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, loader_errorHandler);
			_loader = null;
			
			_seqSubtitles = null;
		}
		
		/**
		 * The currently displayed subtitles
		 */
		public function get currentSubtitles():Subtitles
		{
			return _currentSubtitles;
		}
		
		/**
		 * Stop any currently loading subtitles
		 */
		public function stop():void
		{
			try { _loader.close(); }
			catch (e:Error) {};
		}
		
		/**
		 * Handle the user switching subtitles track
		 */
		protected function subtitlesTrackSwitchHandler(event:HLSEvent):void
		{
			CONFIG::LOGGING 
			{
				Log.debug("Switching to subtitles track "+event.subtitlesTrack);
			}
			
			stop();
			_seqSubtitles = [];
		}
		
		/**
		 * Preload all of the subtitles listed in the loaded subtitles level definitions
		 */
		protected function subtitlesLevelLoadedHandler(event:HLSEvent):void
		{
			_fragments = _hls.subtitlesTracks[_hls.subtitlesTrack].level.fragments;
			loadNextFragment();
		}
		
		/**
		 * Sync subtitles with the current audio/video fragments
		 * 
		 * TODO	This works fine for live media, but do we need a better sync 
		 * 		method for on-demand content?
		 */
		protected function fragmentPlayingHandler(event:HLSEvent):void
		{
			_seqNum = event.playMetrics.seqnum;
			_seqPosition = _hls.position;
		}
		
		/**
		 * The time within the current sequence 
		 */
		protected function get subtitleTime():Number
		{
			return _hls.position-_seqPosition;
		}
		
		/**
		 * Match subtitles to the current playhead position and dispatch
		 * events as appropriate
		 */
		protected function mediaTimeHandler(event:HLSEvent):void
		{
			var subs:Vector.<Subtitles> = _seqSubtitles[_seqNum];
			
			if (subs)
			{
				var mt:HLSMediatime = event.mediatime;
				var matchingSubtitles:Subtitles;
				var time:Number = subtitleTime;
				
				for each (var subtitles:Subtitles in subs)
				{
					if (subtitles.startPosition <= time && subtitles.endPosition >= time)
					{
						matchingSubtitles = subtitles;
						break;
					}
				}
				
				if (matchingSubtitles != _currentSubtitles)
				{
					CONFIG::LOGGING 
					{
						Log.debug("Changing subtitles to: "+matchingSubtitles);
					}
					
					_currentSubtitles = matchingSubtitles;
					_hls.dispatchEvent(new HLSEvent(HLSEvent.SUBTITLES_CHANGE, matchingSubtitles));
				}
			}
		}
		
		/**
		 * Load the next subtitles fragment (if it hasn't been loaded already) 
		 */
		protected function loadNextFragment():void
		{
			if (!_fragments || !_fragments.length) return;
			
			_fragment = _fragments.shift();
			
			if (!_seqSubtitles[_fragment.seqnum])
			{
				_loader.load(new URLRequest(_fragment.url));
			}
			else
			{
				loadNextFragment();
			}
		}
		
		/**
		 * Parse the loaded WebVTT subtitles
		 */
		protected function loader_completeHandler(event:Event):void
		{
			_seqSubtitles[_fragment.seqnum] = WebVTTParser.parse(_loader.data);
			
			CONFIG::LOGGING 
			{
				Log.debug("Loaded "+_seqSubtitles[_fragment.seqnum].length+" subtitles from "+_fragment.url);
			}
			
			loadNextFragment();
		}
		
		/**
		 * If the subtitles fail to load, give up and load the next subtitles fragment
		 */
		protected function loader_errorHandler(event:ErrorEvent):void
		{
			CONFIG::LOGGING 
			{
				Log.error("Error "+event.errorID+" while loading "+_fragment.url+": "+event.text);
			}
			
			loadNextFragment();
		}
		
	}

}
