package org.mangui.hls.model
{
    import flash.net.ObjectEncoding;
    import flash.utils.ByteArray;
    
    import org.mangui.hls.flv.FLVTag;
    import org.mangui.hls.utils.StringUtil;
    import org.mangui.hls.utils.hls_internal;

	use namespace hls_internal;
	
    /**
     * Subtitle model for Flashls
     * @author    Neil Rackett
     */
    public class Subtitle
    {
		private var _tag:FLVTag; 
		
		/**
		 * Convert an object (e.g. data from an onTextData event) into a 
		 * Subtitle class instance
		 */
		public static function toSubtitle(data:Object):Subtitle
		{
			return new Subtitle(data.htmlText || data.text, 
				data.startPTS, data.endPTS, 
				data.startPosition, data.endPosition, 
				data.startDate, data.endDate);
		}
		
		private var _trackid:int;
		private var _htmlText:String;
		private var _text:String;
		private var _startPTS:Number;
		private var _endPTS:Number;
		private var _startDate:Number;
		private var _endDate:Number;
		private var _startPosition:Number;
		private var _endPosition:Number;
        
		/**
		 * Create a new Subtitle object
		 * 
		 * @param	trackid			The ID of the subtitles track this subtitle related to (TX3G standard naming)
		 * @param	htmlText		Subtitle text, including any HTML styling
		 * @param	startPTS		Start timestamp for FLVTag in milliseconds (MPEGTS/90 + startPosition*1000)
		 * @param	endPTS			End timestamp for FLVTag in milliseconds (MPEGTS/90 + endPosition*1000)
		 * @param	startPosition	Start position in seconds
		 * @param	endPosition		End position in seconds
		 * @param	startDate		Start timestamp (#EXT-X-PROGRAM-DATE-TIME + startPosition*1000)
		 * @param	endDate			End timestamp (#EXT-X-PROGRAM-DATE-TIME + endPosition*1000)
		 */
        public function Subtitle(
			trackid:int,
			htmlText:String, 
			startPTS:Number, endPTS:Number,
			startPosition:Number=NaN, endPosition:Number=NaN,
			startDate:Number=NaN, endDate:Number=NaN
		)
        {
			_trackid = trackid;
			
			_htmlText = htmlText || '';
			_text = StringUtil.removeHtmlTags(_htmlText);
			
			_startPTS = startPTS;
			_endPTS = endPTS;
			
			_startPosition = startPosition || _startPTS/1000;
			_endPosition = endPosition || _endPTS/1000;
			
			_startDate = startDate || _startPosition*1000;
			_endDate = endDate || _endPosition*1000
        }
        
		/**
		 * The subtitle's text, including HTML tags (if applicable)
		 */
		public function get htmlText():String { return _htmlText; }
		
		/**
		 * The subtitle's text, with HTML markup removed
		 */
		public function get text():String { return _text; }
		
        public function get trackid():Number { return _trackid; }
        public function get startPTS():Number { return _startPTS; }
        public function get endPTS():Number { return _endPTS; }
		public function get startPosition():Number { return _startPosition; }
		public function get endPosition():Number { return _endPosition; }
        public function get startDate():Number { return _startDate; }
        public function get endDate():Number { return _endDate; }
        public function get duration():Number { return _endPosition-_startPosition; }
		
        /**
         * Convert to a plain object via the standard toJSON method
         */
        public function toJSON():Object
        {
            return {
				// TX3G properties
				trackid: trackid,
				text: text,
				
				// flashls specific properties
				htmlText: htmlText,
				startPTS: startPTS,
				endPTS: endPTS,
				startPosition: startPosition,
				endPosition: endPosition,
				startDate: startDate,
				endDate: endDate,
                duration: duration
            }
        }
		
		/**
		 * Does this subtitle have the same content as the specified subtitle?
		 * @param	subtitle	The subtitle to compare
		 * @returns				Boolean true if the contents are the same
		 */
		public function equals(subtitle:Subtitle, textOnly:Boolean=true):Boolean 
		{
			var isMatch:Boolean = subtitle is Subtitle
				&& htmlText == subtitle.htmlText;
			
			if (textOnly) return isMatch;
			
			return isMatch 
				&& startPTS == subtitle.startPTS
				&& endPTS == subtitle.endPTS;
		}
		
        public function toString():String
        {
            return '[Subtitles startPTS='+startPTS+' endPTS='+endPTS+' htmlText="'+htmlText+'"]';
        }
		
		hls_internal function $toTag():FLVTag 
		{
			if (!_tag) 
			{
				_tag = new FLVTag(FLVTag.METADATA, startPTS, startPTS, false);
				
				var bytes:ByteArray = new ByteArray();
				
				bytes.objectEncoding = ObjectEncoding.AMF0;
				bytes.writeObject("onTextData");
				bytes.writeObject(toJSON());
				
				_tag.push(bytes, 0, bytes.length);
				_tag.build();
			}
			
			return _tag;
		}
	}
}