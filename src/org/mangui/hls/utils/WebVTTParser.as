package org.mangui.hls.utils
{
	import mx.utils.StringUtil;
	
	import org.mangui.hls.model.Subtitles;

	public class WebVTTParser
	{
		static private const CUE:RegExp = /^(?:(.*)(?:\r\n|\n))?([\d:,.]+) --> ([\d:,.]+)(?:\s.*)((.|\n|\r\n)*)/;
		static private const TIMESTAMP:RegExp = /^(?:(\d{2,}):)?(\d{2}):(\d{2})[,.](\d{3})$/;
		
		static private var targetDuration:Number = 10;
		
		static public function parse(data:String, offset:Number=0):Vector.<Subtitles>
		{
			var subtitles:Subtitles;
			var results:Vector.<Subtitles> = new Vector.<Subtitles>;
			var lines:Array = data.split(/(?:(?:\r\n|\n){2,})/);
			var length:uint = lines.length;
			var i:uint = 0;
			
			for (i=0; i<length; ++i)
			{
				if (!CUE.test(lines[i]))
				{
					continue;
				}
				
				var matches:Array = CUE.exec(lines[i]);
				var start:Number = offset+parseTime(matches[2]);
				var end:Number = offset+parseTime(matches[3]);
				var text:String = StringUtil.trim(matches[4] || '');
				
				if (text)
				{
					text = text.replace(/(\r\n)/g, '\n');
					subtitles = new Subtitles(start, end-start, text);
					results.push(subtitles);
					
					trace(subtitles.toString());
				}
			}
			
			offset += targetDuration;
			
			return results;
		}
		
		static public function parseTime(time:String):Number
		{
			if (!TIMESTAMP.test(time))
			{
				return NaN;
			}
			
			var a:Array = TIMESTAMP.exec(time);
			var result:Number = a[4]/1000;
			
			result += parseInt(a[3]);
			
			if (a[2])
			{
				result += a[2] * 60;
			}
			
			if (a[1])
			{
				result += a[1] * 60 * 60;
			}
			
			return result;
		}
		
	}
	
}
