/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.utils {
    import flash.external.ExternalInterface;
    import flash.utils.ByteArray;
    import flash.net.ObjectEncoding;

    import by.blooddy.crypto.Base64;
    
    import org.mangui.hls.HLSSettings;

    /** Class that sends log messages to browser console. **/
    public class Log {
        private static const LEVEL_INFO : String = "INFO:";
        private static const LEVEL_DEBUG : String = "DEBUG:";
        private static const LEVEL_WARN : String = "WARN:";
        private static const LEVEL_ERROR : String = "ERROR:";

        public static function info(message : *) : void {
            if (HLSSettings.logInfo)
                outputlog(LEVEL_INFO, String(message));
        };

        public static function debug(message : *) : void {
            if (HLSSettings.logDebug)
                outputlog(LEVEL_DEBUG, String(message));
        };

        public static function debug2(message : *) : void {
            if (HLSSettings.logDebug2)
                outputlog(LEVEL_DEBUG, String(message));
        };

        public static function warn(message : *) : void {
            if (HLSSettings.logWarn)
                outputlog(LEVEL_WARN, String(message));
        };

        public static function error(message : *) : void {
            if (HLSSettings.logError)
                outputlog(LEVEL_ERROR, String(message));
        };

        /** Log a message to the console. **/
        private static function outputlog(level : String, message : String) : void {
            if (ExternalInterface.available)
                ExternalInterface.call('console.log', level + message);
            else trace(level + message);
        }

        public static function outputCCFLVTagToConsole(prefix:String, data:ByteArray):void
        {
            data.position = 11;
            data.objectEncoding = ObjectEncoding.AMF0;
            var method:* = data.readObject();
            if (method === "onCaptionInfo")
            {
                data.objectEncoding = ObjectEncoding.AMF3;
                data.readUnsignedByte();
                var object:* = data.readObject();

                if (object && object.type && object.data)
                {
                    var ba:ByteArray = Base64.decode(object.data);
                    ba.readUnsignedInt();
                    var total:int = 31 & ba.readUnsignedByte();
                    ba.readUnsignedByte();
                    Log.outputCCDataToConsole(prefix , ba, total);
                }
            }            
        }

        public static function outputCCDataToConsole(prefix:String, data:ByteArray, total:int):void
        {
            // The following code is for debug logging...
            //var byte:uint;
            var byte:int;
            var ccbyte1:int;
            var ccbyte2:int;
            var ccValid:Boolean = false;
            var ccType:int;
            var assembling:Boolean = false;

            var output:String = "";
            for (var i:int=0; i<total; i++)
            {
                byte = data.readUnsignedByte();

                ccValid = !((4 & byte) == 0);
                ccType = (3 & byte);

                ccbyte1 = 0x7F & data.readUnsignedByte();
                ccbyte2 = 0x7F & data.readUnsignedByte();                                              

                if (ccbyte1 === 0 && ccbyte2 === 0)
                {
                    continue;
                }

                if (ccValid)
                {
                    if (ccType == 0) // || ccType == 1)
                    {
                        output += byte.toString(16) + " ";
                        output += (ccbyte1 < 0x10 ? "0" : "") + ccbyte1.toString(16) + " ";
                        output += (ccbyte2 < 0x10 ? "0" : "") + ccbyte2.toString(16) + " ";
                        output += " | type " + ccType + ": ";

                        if (ccbyte1 == 0x11 || ccbyte1 == 0x19)
                        {
                            // Extended North American character...
                            // todo: output these characters
                            output += "Special North American Character";
                        }
                        else if (ccbyte1 == 0x12 && ccbyte1 == 0x1A)
                        {
                            // Spanish / French character
                            // todo: output these characters
                            output += "Spanish / French Extended Character";
                        }
                        else if (ccbyte1 == 0x13 && ccbyte1 == 0x1B)
                        {
                            // Portugese / German / Danish character
                            // todo: output these characters
                            output += "Port/Germ/Danish Extended Character";
                        }
                        else if (ccbyte1 == 0x14 || ccbyte1 == 0x1C || ccbyte1 == 0x15 || ccbyte1 == 0x1D)
                        {
                            // command...
                            output += "Command A";
                        }
                        else if (ccbyte1 == 0x17 || ccbyte1 == 0x1F)
                        {
                            // another command
                            output += "Command B";
                        }
                        else if (ccbyte1 >= 32 || ccbyte2 > 32)
                        {
                            output += String.fromCharCode(ccbyte1) + " " + String.fromCharCode(ccbyte2);
                        }
                    }
                    else if (ccType == 1) // todo this might be language 2?
                    {
                        //
                    }
                    // TODO: assemble DTVCC packets.  not sure if needed...
                    else if (ccType == 3)
                    {
                        if (assembling)
                        {
                            // close previous packet
                            assembling = false;
                        }
                        // Start assembling packet
                        assembling = true;
                    }
                    else if (ccType == 2)
                    {
                        if (ccValid == false && assembling)
                        {
                            // close previous packet
                            assembling = false;
                        }
                        // append bytes to packet
                    }
                }

                //output += "\n";
            }

            if (output)
            {
                Log.info(prefix + ": " + output + "\n");
            }
        }
    };
}