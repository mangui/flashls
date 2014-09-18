package org.mangui.hls.demux {

    import org.mangui.hls.HLSSettings;
    import flash.utils.ByteArray;
    CONFIG::LOGGING {
    import org.mangui.hls.utils.Log;
    }

    /** Constants and utilities for the H264 video format. **/
    public class Nalu {
        /** H264 NAL unit names. **/
        private static const NAMES : Array = ['Unspecified',                  // 0 
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

        /** Return an array with NAL delimiter indexes. **/
        public static function getNALU(nalu : ByteArray, position : uint) : Vector.<VideoFrame> {
            var units : Vector.<VideoFrame> = new Vector.<VideoFrame>();
            var unit_start : int;
            var unit_type : int;
            var unit_header : int;
            // Loop through data to find NAL startcodes.
            var window : uint = 0;
            nalu.position = position;
            while (nalu.bytesAvailable > 4) {
                window = nalu.readUnsignedInt();
                // Match four-byte startcodes
                if ((window & 0xFFFFFFFF) == 0x01) {
                    // push previous NAL unit if new start delimiter found, dont push unit with type = 0
                    if (unit_start && unit_type) {
                        units.push(new VideoFrame(unit_header, nalu.position - 4 - unit_start, unit_start, unit_type));
                    }
                    unit_header = 4;
                    unit_start = nalu.position;
                    unit_type = nalu.readByte() & 0x1F;
                    // NDR or IDR NAL unit
                    if (unit_type == 1 || unit_type == 5) {
                        break;
                    }
                    // Match three-byte startcodes
                } else if ((window & 0xFFFFFF00) == 0x100) {
                    // push previous NAL unit if new start delimiter found, dont push unit with type = 0
                    if (unit_start && unit_type) {
                        units.push(new VideoFrame(unit_header, nalu.position - 4 - unit_start, unit_start, unit_type));
                    }
                    nalu.position--;
                    unit_header = 3;
                    unit_start = nalu.position;
                    unit_type = nalu.readByte() & 0x1F;
                    // NDR or IDR NAL unit
                    if (unit_type == 1 || unit_type == 5) {
                        break;
                    }
                } else {
                    nalu.position -= 3;
                }
            }
            // Append the last NAL to the array.
            if (unit_start) {
                units.push(new VideoFrame(unit_header, nalu.length - unit_start, unit_start, unit_type));
            }
            // Reset position and return results.
            CONFIG::LOGGING {
            if (HLSSettings.logDebug2) {
                if (units.length) {
                    var txt : String = "AVC: ";
                    for (var i : int = 0; i < units.length; i++) {
                        txt += NAMES[units[i].type] + ", ";
                    }
                    Log.debug2(txt.substr(0, txt.length - 2) + " slices");
                } else {
                    Log.debug2('AVC: no NALU slices found');
                }
            }
            }
            nalu.position = position;
            return units;
        };
		
        // read the rbsp data from a marked NAL unit
        public static function getRBSP( nalu:ByteArray, UnitMarkers:VideoFrame ): ByteArray {
            var Output: ByteArray = new ByteArray();
            for (nalu.position = UnitMarkers.start + 1; nalu.position < UnitMarkers.start + UnitMarkers.length; ) {
                if (nalu.position + 3 < UnitMarkers.start + UnitMarkers.length) {
                    // read a long
                    var window: uint = nalu.readUnsignedInt();
                    // does the first 3 bytes contain 00 00 03?
                    if ((window & 0xffffff00) == 0x300) {
                        Output.writeByte( 0 );
                        Output.writeByte( 0 );
                        nalu.position -= 1;
                    } else { // if not, then does the last 3 bytes contain 00 00 03?
                        if ((window & 0x00ffffff) == 0x3) {
                            nalu.position -= 4;
                            Output.writeByte( nalu.readByte() );
                            Output.writeByte( 0 );
                            Output.writeByte( 0 );
                            nalu.position += 3;
                        } else { // else move on one byte
                            nalu.position -= 4;
                            Output.writeByte( nalu.readByte() );
                        }
                    }
                } else { // we have less than 4 bytes left; must have either aleary been eaten,
                    // or not enough rrom for 00 00 03
                    Output.writeByte( nalu.readByte() );
                }
            }			
            return Output;
        }
    }
}