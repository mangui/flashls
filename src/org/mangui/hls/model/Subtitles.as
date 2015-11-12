package org.mangui.hls.model
{
	/**
	 * Subtitles model for Flashls
	 * @author	Neil Rackett
	 */
	public class Subtitles
	{
		private var _startPosition:Number;
		private var _endPosition:Number;
		private var _text:String;
		
		public function Subtitles(startPosition:Number, endPosition:Number, text:String) 
		{
			_startPosition = startPosition;
			_endPosition = endPosition;
			_text = text || '';
		}
		
		public function get startPosition():Number { return _startPosition; }
		public function get endPosition():Number { return _endPosition; }
		public function get duration():Number { return _endPosition-_startPosition; }
		public function get text():String { return _text; }
		
		public function toString():String
		{
			return '[Subtitles startPosition='+startPosition+' endPosition='+endPosition+' duration='+duration+' text="'+text+'"]';
		}
	}
}