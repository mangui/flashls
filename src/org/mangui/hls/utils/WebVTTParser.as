/* This Source Code Form is subject to the terms of the Mozilla Public
* License, v. 2.0. If a copy of the MPL was not distributed with this
* file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.utils
{
	import mx.utils.StringUtil;
	
	import org.mangui.hls.model.Subtitles;

	/**
	 * WebVTT subtitles parser
	 * 
	 * It supports standard WebVTT format text with or without align:* 
	 * elements, which are currently ignored.
	 * 
	 * This class is loosely based Denivips's WebVTT parser, but has been 
	 * massively simplified, re-worked and generally updated to more reliably 
	 * capture subtitle text in as small amount of code as possible. 
	 * 
	 * @author	Neil Rackett
	 */
	public class WebVTTParser
	{
		static private const CUE:RegExp = /^(?:(.*)(?:\r\n|\n))?([\d:,.]+) --> ([\d:,.]+)((.|\n|\r|\r\n)*)/;
		static private const TIMESTAMP:RegExp = /^(?:(\d{2,}):)?(\d{2}):(\d{2})[,.](\d{3})$/;
		
		/**
		 * Parse a string into a series of Subtitles objects and return
		 * them in a Vector
		 */
		static public function parse(data:String, offset:Number=0):Vector.<Subtitles>
		{
			var results:Vector.<Subtitles> = new Vector.<Subtitles>;
			var lines:Array = data.replace(/\balign:.*+/ig,'').split(/(?:(?:\r\n|\r|\n){2,})/);
			
			for each (var line:String in lines)
			{
				if (!CUE.test(line)) continue;
				
				var matches:Array = CUE.exec(line);
				var startPosition:Number = offset+parseTime(matches[2]);
				var endPosition:Number = offset+parseTime(matches[3]);
				var text:String = StringUtil.trim((matches[4] || '').replace(/(\r\n|\r|\|)/g, '\n'));
				
				if (text)
				{
					var subs:Subtitles = new Subtitles(startPosition, endPosition, text);
					
					CONFIG::LOGGING 
					{
						Log.debug(subs);
					}
					
					results.push(subs);
				}
			}
			
			return results;
		}
		
		/**
		 * Converts a time string in the format 00:00:00.000 into seconds
		 */
		static public function parseTime(time:String):Number
		{
			if (!TIMESTAMP.test(time)) return NaN;
			
			var a:Array = TIMESTAMP.exec(time);
			var seconds:Number = a[4]/1000;
			
			seconds += parseInt(a[3]);
			
			if (a[2]) seconds += a[2] * 60;
			if (a[1]) seconds += a[1] * 60 * 60;
			
			return seconds;
		}
		
	}
	
}
