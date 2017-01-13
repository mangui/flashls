/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.hls.demux {

    import flash.utils.ByteArray;
    CONFIG::LOGGING {
    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.utils.Log;
    }

    /** Constants and utilities for the H264 video format. **/
    public class Nalu {

        private static var _audNalu : ByteArray;
        // static initializer
        {
            _audNalu = new ByteArray();
            _audNalu.length = 2;
            _audNalu.writeByte(0x09);
            _audNalu.writeByte(0xF0);
        };


        /** Return an array with NAL delimiter indexes. **/
        public static function getNALU(nalu : ByteArray, position : uint) : Vector.<VideoFrame> {
            var len : uint = nalu.length,i : uint = position;
            var unitHeader : int,lastUnitHeader : int = 0;
            var unitStart : int,lastUnitStart : int = 0;
            var unitType : int,lastUnitType : int = 0;
            var audFound : Boolean = false;
            var value : uint,state : uint = 0;
            var units : Vector.<VideoFrame> = new Vector.<VideoFrame>();
            // Loop through data to find NAL startcodes.
            while (i < len) {
                // finding 3 or 4-byte start codes (00 00 01 OR 00 00 00 01)
                value = nalu[i++];
                switch(state)
                {
                    case 0:
                        if(!value) {
                            state = 1;
                            // unitHeader is NAL header offset
                            unitHeader=i-1;
                        }
                        break;
                    case 1:
                        if(value) {
                            state = 0;
                        } else {
                            state = 2;
                        }
                        break;
                    case 2:
                    case 3:
                        if(value) {
                            if(value === 1 && i < len) {
                                unitType = nalu[i] & 0x1f;
                                if(unitType == 9) {
                                    audFound = true;
                                }
                                if(lastUnitStart) {
                                    // use Math.min(4,...) as max header size is 4.
                                    // in case there are any leading zeros
                                    // such as 00 00 00 00 00 00 01
                                    //                  ^^
                                    // we need to ignore them as they are part of previous NAL unit
                                    units.push(new VideoFrame(Math.min(4,lastUnitStart-lastUnitHeader), i-state-1-lastUnitStart, lastUnitStart, lastUnitType));
                                }
                                lastUnitStart = i;
                                lastUnitType = unitType;
                                lastUnitHeader = unitHeader;
                                if(audFound == true && (unitType === 1 || unitType === 5)) {
                                  // OPTI !!! if AUD unit already parsed and if IDR/NDR unit, consider it is last NALu
                                  i = len;
                                }
                            }
                            state = 0;
                        } else {
                            state = 3;
                        }
                        break;
                    default:
                        break;
                }
            }
            //push last unit
            if(lastUnitStart) {
                units.push(new VideoFrame(Math.min(4,lastUnitStart-lastUnitHeader), len-lastUnitStart, lastUnitStart, lastUnitType));
            }
            // Reset position and return results.
            CONFIG::LOGGING {
                if (HLSSettings.logDebug2) {
                    /** H264 NAL unit names. **/
                    const NAMES : Array = ['Unspecified',// 0
                    'NDR',                          // 1
                    'Partition A',                  // 2
                    'Partition B',                  // 3
                    'Partition C',                  // 4
                    'IDR',                          // 5
                    'SEI',                          // 6
                    'SPS',                          // 7
                    'PPS',                          // 8
                    'AUD',                          // 9
                    'End of Sequence',              // 10
                    'End of Stream',                // 11
                    'Filler Data'// 12
                    ];
                    if (units.length) {
                        var txt : String = "AVC: ";
                        for (i = 0; i < units.length; i++) {
                            txt += NAMES[units[i].type] + ","; //+ ":" + units[i].length
                        }
                        Log.debug2(txt.substr(0,txt.length-1) + " slices");
                    } else {
                        Log.debug2('AVC: no NALU slices found');
                    }
                }
            }
            nalu.position = position;
            return units;
        };

        public static function get AUD():ByteArray {
            return _audNalu;
        }

        /**
          * remove Emulation Prevention bytes from a RBSP
          */
		public static function unescapeStream(data : ByteArray):ByteArray {
            var length : uint = data.length;
            var EPBPositions : Vector.<uint> = new Vector.<uint>();
            var i : uint = 1;
            var newLength : uint;
            var newData : ByteArray;

            // Find all `Emulation Prevention Bytes`
            while (i < length - 2) {
              if (data[i] === 0 &&
                  data[i + 1] === 0 &&
                  data[i + 2] === 0x03) {
                EPBPositions.push(i + 2);
                i += 2;
              } else {
                i++;
              }
            }

            // If no Emulation Prevention Bytes were found just return the original
            // array
            if (EPBPositions.length === 0) {
              return data;
            }
            // Create a new array to hold the NAL unit data
            newLength = length - EPBPositions.length;
            newData = new ByteArray();
            newData.length = newLength;
            var sourceIndex : uint = 0;
            for (i = 0; i < newLength; sourceIndex++, i++) {
              if (EPBPositions.length && sourceIndex === EPBPositions[0]) {
                // Skip this byte
                sourceIndex++;
                // Remove this position index
                EPBPositions.shift();
              }
              newData[i] = data[sourceIndex];
            }
            return newData;
		}
    }
}
