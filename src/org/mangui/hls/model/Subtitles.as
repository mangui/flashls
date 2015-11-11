package org.mangui.hls.model
{
	public class Subtitles
	{
		private var _start:Number;
		private var _duration:Number;
		private var _text:String;
		
		public function Subtitles(start:Number, duration:Number, text:String) 
		{
			_start = start;
			_duration = duration;
			_text = text;
		}
		
		public function get start():Number { return _start; }
		public function get end():Number { return _start + _duration; }
		public function get duration():Number { return _duration; }
		public function get text():String { return _text; }
		
		public function toString():String
		{
			return '[Subtitles start='+start+' end='+end+' duration='+duration+' text="'+text+'"]';
		}
	}
}