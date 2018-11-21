/* This Source Code Form is subject to the terms of the Mozilla Public
* License, v. 2.0. If a copy of the MPL was not distributed with this
* file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.utils {
    
    import org.mangui.hls.model.Subtitle;

    /**
     * WebVTT subtitles parser
     * 
     * It supports standard WebVTT format text with or without align:* 
     * elements, which are currently ignored.
     * 
     * @author    Neil Rackett
     */
    public class WebVTTParser {

        static private const CUE:RegExp = /^(?:(.*)(?:\n))?([\d:,.]+) --> ([\d:,.]+)((.|\n)*)/;
        static private const TIMESTAMP:RegExp = /^(?:(\d{2,}):)?(\d{2}):(\d{2})[,.](\d{3})$/;
        static private const MPEGTS:RegExp = /MPEGTS[:=](\d+)/;

        /**
         * Parse a string into a series of Subtitles objects and return
         * them in a Vector
         */
        static public function parse(data:String, level:int=-1, fragmentTime:Number=0):Vector.<Subtitle> {
            data = StringUtil.toLF(data);

            CONFIG::LOGGING {
                Log.debug("[WebVTTParser] Received:\n"+data);
            }

            var mpegTS:Number = 0;
            var results:Vector.<Subtitle> = new Vector.<Subtitle>;
            var lines:Array = data.replace(/\balign:.*+/ig,'').split(/(?:(?:\n){2,})/);

            for each (var line:String in lines) {

                var matches:Array;

                switch (true)
                {
                    case MPEGTS.test(line): {
                        matches = MPEGTS.exec(line);
                        mpegTS = Number(matches[1]);

                        if (mpegTS > 4294967295) {
                            mpegTS -= 8589934592;
                        }                        

                        CONFIG::LOGGING {
                            Log.debug2(mpegTS);
                        }

                        continue;
                    }
                    
                    case CUE.test(line): {
                        matches = CUE.exec(line);

                        var startPosition:Number = parseTime(matches[2]);
                        var startPTS:Number = Math.round(mpegTS/90 + startPosition*1000);
                        var startTime:Number = fragmentTime + startPosition*1000;

                        var endPosition:Number = parseTime(matches[3]);
                        var endPTS:Number = Math.round(mpegTS/90 + endPosition*1000);
                        var endTime:Number = fragmentTime + endPosition*1000;

                        var text:String = StringUtil.trim((matches[4] || '').replace(/(\|)/g, '\n'));
                        var subtitle:Subtitle = new Subtitle(level, text, startPTS, endPTS, startPosition, endPosition, startTime, endTime);

                        results.push(subtitle);

                        CONFIG::LOGGING {
                            Log.debug2(subtitle);
                        }

                        continue;
                    }

                    default: {
                        CONFIG::LOGGING {
                            Log.debug("[WebVTTParser] Unknown data found: "+line);
                        }
                        continue;
                    }
                }
            }

            return results;
        }

        /**
         * Converts a time string in the format 00:00:00.000 into seconds
         */
        static public function parseTime(time:String):Number {

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
