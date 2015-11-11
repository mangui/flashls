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

	public class SubtitlesFragmentLoader
	{
		protected var _hls:HLS;
		protected var _loader:URLLoader;
		protected var _subtitles:Vector.<Subtitles>;
		protected var _fragments:Vector.<Fragment>;
		protected var _fragment:Fragment;
		protected var _offset:Number;
		protected var _programDate:Number;
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
		}
		
		public function dispose():void
		{
			_hls.removeEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
			_hls.removeEventListener(HLSEvent.SUBTITLES_LEVEL_LOADED, subtitlesLevelLoadedHandler);
			_hls.removeEventListener(HLSEvent.FRAGMENT_PLAYING, fragmentPlayingHandler);
			_hls.removeEventListener(HLSEvent.MEDIA_TIME, mediaTimeHandler);
			_hls = null;
			
			_loader.removeEventListener(Event.COMPLETE, loader_completeHandler);
			_loader.removeEventListener(IOErrorEvent.IO_ERROR, loader_errorHandler);
			_loader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, loader_errorHandler);
			_loader = null;
		}
		
		public function get currentSubtitles():Subtitles
		{
			return _currentSubtitles;
		}
		
		public function stop():void
		{
			try { _loader.close(); }
			catch (e:Error) {};
		}
		
		protected function subtitlesTrackSwitchHandler(event:Event):void
		{
			stop();
			_subtitles = new Vector.<Subtitles>;
		}
		
		protected function subtitlesLevelLoadedHandler(event:HLSEvent):void
		{
			_fragments = _hls.subtitlesTracks[_hls.subtitlesTrack].level.fragments;
			_offset = 0;
			
			loadNextFragment();
		}
		
		protected function fragmentPlayingHandler(event:HLSEvent):void
		{
			_programDate = event.playMetrics.program_date;
		}
		
		protected function get subtitleTime():Number
		{
			return _programDate/1000 + _hls.position;
		}
		
		protected function mediaTimeHandler(event:HLSEvent):void
		{
			if (!_subtitles || !_subtitles.length) return;
			
			var mt:HLSMediatime = event.mediatime;
			var currentSubtitles:Subtitles;
			
			for each (var subtitles:Subtitles in _subtitles)
			{
				if (subtitles.start <= subtitleTime && subtitles.end >= subtitleTime)
				{
					currentSubtitles = subtitles;
					break;
				}
			}
			
			if (currentSubtitles != _currentSubtitles)
			{
				if (currentSubtitles) trace("\t\t", currentSubtitles.text);
				
				_currentSubtitles = currentSubtitles;
				_hls.dispatchEvent(new HLSEvent(HLSEvent.SUBTITLES_CHANGE, currentSubtitles));
			}
		}
		
		protected function loadNextFragment():void
		{
			if (!_fragments || !_fragments.length) return;
			
			_fragment = _fragments.shift();
			_loader.load(new URLRequest(_fragment.url));
		}
		
		protected function loader_completeHandler(event:Event):void
		{
			_subtitles = _subtitles.concat(WebVTTParser.parse(_loader.data, _fragment.program_date/1000 + _offset));
			_offset += 10;
			
			loadNextFragment();
		}
		
		protected function loader_errorHandler(event:ErrorEvent):void
		{
			// TODO Log error
			_offset += 10;

			loadNextFragment();
		}
		
	}
}
