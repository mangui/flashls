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
	 * This is a massively simplified/improved version of the WebVTT parser 
	 * used by Denivip HLS plugin for OSMF
	 * 
	 * @author	Neil Rackett
	 */
	public class WebVTTParser
	{
		static private const CUE:RegExp = /^(?:(.*)(?:\r\n|\n))?([\d:,.]+) --> ([\d:,.]+)(?:\s.*)((.|\n|\r\n)*)/;
		static private const TIMESTAMP:RegExp = /^(?:(\d{2,}):)?(\d{2}):(\d{2})[,.](\d{3})$/;
		
		/**
		 * Parse a string into a series of Subtitles objects and return
		 * them in a Vector
		 */
		static public function parse(data:String, offset:Number=0):Vector.<Subtitles>
		{
			var results:Vector.<Subtitles> = new Vector.<Subtitles>;
			var lines:Array = data.split(/(?:(?:\r\n|\n){2,})/);
			
			for each (var line:String in lines)
			{
				if (!CUE.test(line)) continue;
				
				var matches:Array = CUE.exec(line);
				var startPosition:Number = offset+parseTime(matches[2]);
				var endPosition:Number = offset+parseTime(matches[3]);
				var text:String = StringUtil.trim(matches[4] || '').replace(/(\r\n)/g, '\n');
				
				if (text)
				{
					results.push(new Subtitles(startPosition, endPosition, text));
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
			var result:Number = a[4]/1000;
			
			result += parseInt(a[3]);
			
			if (a[2]) result += a[2] * 60;
			if (a[1]) result += a[1] * 60 * 60;
			
			return result;
		}
		
	}
	
}
