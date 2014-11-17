/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.hls.demux {
    import flash.utils.getTimer;
    import flash.display.DisplayObject;

    import org.mangui.hls.flv.FLVTag;
    import org.mangui.hls.model.AudioTrack;

    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.utils.ByteArray;
    import flash.net.ObjectEncoding;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
        import org.mangui.hls.HLSSettings;
        import org.mangui.hls.utils.Hex;
    }
    /** Representation of an MPEG transport stream. **/
    public class TSDemuxer extends EventDispatcher implements Demuxer {
        /** read position **/
        private var _read_position : uint;
        /** is bytearray full ? **/
        private var _data_complete : Boolean;
        /** TS Sync byte. **/
        private static const SYNCBYTE : uint = 0x47;
        /** TS Packet size in byte. **/
        private static const PACKETSIZE : uint = 188;
        /** Packet ID of the PAT (is always 0). **/
        private static const PAT_ID : int = 0;
        /** Packet ID of the SDT (is always 17). **/
        private static const SDT_ID : int = 17;
        /** has PMT been parsed ? **/
        private var _pmtParsed : Boolean;
        /** any TS packets before PMT ? **/
        private var _packetsBeforePMT : Boolean;
        /** PMT PID **/
        private var _pmtId : int;
        /** video PID **/
        private var _avcId : int;
        /** audio PID **/
        private var _audioId : int;
        private var _audioIsAAC : Boolean;
        /** ID3 PID **/
        private var _id3Id : int;
        /** Vector of audio/video tags **/
        private var _tags : Vector.<FLVTag>;
        /** Display Object used to schedule parsing **/
        private var _displayObject : DisplayObject;
        /** Byte data to be read **/
        private var _data : ByteArray;
        /* callback functions for audio selection, and parsing progress/complete */
        private var _callback_audioselect : Function;
        private var _callback_progress : Function;
        private var _callback_complete : Function;
        private var _callback_videometadata : Function;
        /* current audio PES */
        private var _curAudioPES : ByteArray;
        /* current video PES */
        private var _curVideoPES : ByteArray;
        /* current id3 PES */
        private var _curId3PES : ByteArray;
        /* ADTS frame overflow */
        private var _adtsFrameOverflow : ByteArray;
        /* current NAL unit */
        private var _curNalUnit : ByteArray;
        /* current AVC Tag */
        private var _curVideoTag : FLVTag;
        /* ADIF tag inserted ? */
        private var _adifTagInserted : Boolean = false;
        /* last AVCC byte Array */
        private var _avcc : ByteArray;

        public static function probe(data : ByteArray) : Boolean {
            var pos : uint = data.position;
            var len : uint = Math.min(data.bytesAvailable, 188 * 2);
            for (var i : int = 0; i < len; i++) {
                if (data.readByte() == SYNCBYTE) {
                    // ensure that at least two consecutive TS start offset are found
                    if (data.bytesAvailable > 188) {
                        data.position = pos + i + 188;
                        if (data.readByte() == SYNCBYTE) {
                            data.position = pos + i;
                            return true;
                        } else {
                            data.position = pos + i + 1;
                        }
                    }
                }
            }
            data.position = pos;
            return false;
        }

        /** Transmux the M2TS file into an FLV file. **/
        public function TSDemuxer(displayObject : DisplayObject, callback_audioselect : Function, callback_progress : Function, callback_complete : Function, callback_videometadata : Function) {
            _curAudioPES = null;
            _curVideoPES = null;
            _curId3PES = null;
            _curVideoTag = null;
            _curNalUnit = null;
            _adtsFrameOverflow = null;
            _callback_audioselect = callback_audioselect;
            _callback_progress = callback_progress;
            _callback_complete = callback_complete;
            _callback_videometadata = callback_videometadata;
            _pmtParsed = false;
            _packetsBeforePMT = false;
            _pmtId = _avcId = _audioId = _id3Id = -1;
            _audioIsAAC = false;
            _tags = new Vector.<FLVTag>();
            _displayObject = displayObject;
        };

        /** append new TS data */
        public function append(data : ByteArray) : void {
            if (_data == null) {
                _data = new ByteArray();
                _data_complete = false;
                _read_position = 0;
                _avcc = null;
                _displayObject.addEventListener(Event.ENTER_FRAME, _parseTimer);
            }
            _data.position = _data.length;
            _data.writeBytes(data, data.position);
        }

        /** cancel demux operation */
        public function cancel() : void {
            CONFIG::LOGGING {
                Log.debug("TS: cancel demux");
            }
            _data = null;
            _curAudioPES = null;
            _curVideoPES = null;
            _curId3PES = null;
            _curVideoTag = null;
            _curNalUnit = null;
            _adtsFrameOverflow = null;
            _avcc = null;
            _tags = new Vector.<FLVTag>();
            _displayObject.removeEventListener(Event.ENTER_FRAME, _parseTimer);
        }

        public function notifycomplete() : void {
            _data_complete = true;
        }

        public function audio_expected() : Boolean {
            return (_audioId != -1);
        }

        public function video_expected() : Boolean {
            return (_avcId != -1);
        }

        /** Parse a limited amount of packets each time to avoid blocking **/
        private function _parseTimer(e : Event) : void {
            var start_time : int = getTimer();
            _data.position = _read_position;
            // dont spend more than 20ms demuxing TS packets to avoid loosing frames
            while ((_data.bytesAvailable >= 188) && ((getTimer() - start_time) < 20)) {
                _parseTSPacket();
            }
            if (_tags.length) {
                _callback_progress(_tags);
                _tags = new Vector.<FLVTag>();
            }
            if (_data) {
                _read_position = _data.position;
                // finish reading TS fragment
                if (_data_complete && _data.bytesAvailable < 188) {
                    // free ByteArray
                    _data = null;
                    // first check if TS parsing was successful
                    if (_pmtParsed == false) {
                        null; // just to avoid compilaton warnings if CONFIG::LOGGING is false
                        CONFIG::LOGGING {
                            Log.error("TS: no PMT found, report parsing complete");
                        }
                    }
                    _displayObject.removeEventListener(Event.ENTER_FRAME, _parseTimer);
                    _flush();
                    _callback_complete();
                }
            }
        }

        /** flux demux **/
        private function _flush() : void {
            CONFIG::LOGGING {
                Log.debug("TS: flushing demux");
            }
            // check whether last parsed audio PES is complete
            if (_curAudioPES && _curAudioPES.length > 14) {
                var pes : PES = new PES(_curAudioPES, true);
                // consider that PES with unknown size (length=0 found in header) is complete
                if (pes.len == 0 || (pes.data.length - pes.payload - pes.payload_len) >= 0) {
                    CONFIG::LOGGING {
                        Log.debug2("TS: complete Audio PES found at end of segment, parse it");
                    }
                    // complete PES, parse and push into the queue
                    if (_audioIsAAC) {
                        _parseADTSPES(pes);
                    } else {
                        _parseMPEGPES(pes);
                    }
                    _curAudioPES = null;
                } else {
                    CONFIG::LOGGING {
                        Log.debug("TS: partial audio PES at end of segment");
                    }
                    _curAudioPES.position = _curAudioPES.length;
                }
            }
            // check whether last parsed video PES is complete
            if (_curVideoPES && _curVideoPES.length > 14) {
                pes = new PES(_curVideoPES, false);
                // consider that PES with unknown size (length=0 found in header) is complete
                if (pes.len == 0 || (pes.data.length - pes.payload - pes.payload_len) >= 0) {
                    CONFIG::LOGGING {
                        Log.debug2("TS: complete AVC PES found at end of segment, parse it");
                    }
                    // complete PES, parse and push into the queue
                    _parseAVCPES(pes);
                    _curVideoPES = null;
                    // push last video tag if any
                    if (_curVideoTag) {
                        if (_curNalUnit && _curNalUnit.length) {
                            _curVideoTag.push(_curNalUnit, 0, _curNalUnit.length);
                        }
                        _tags.push(_curVideoTag);
                        _curVideoTag = null;
                        _curNalUnit = null;
                    }
                } else {
                    CONFIG::LOGGING {
                        Log.debug("TS: partial AVC PES at end of segment expected/current len:" + pes.payload_len + "/" + ( pes.data.length - pes.payload));
                    }
                    _curVideoPES.position = _curVideoPES.length;
                }
            }
            // check whether last parsed ID3 PES is complete
            if (_curId3PES && _curId3PES.length > 14) {
                var pes3 : PES = new PES(_curId3PES, false);
                if (pes3.len && (pes3.data.length - pes3.payload - pes3.payload_len) >= 0) {
                    CONFIG::LOGGING {
                        Log.debug2("TS: complete ID3 PES found at end of segment, parse it");
                    }
                    // complete PES, parse and push into the queue
                    _parseID3PES(pes3);
                    _curId3PES = null;
                } else {
                    CONFIG::LOGGING {
                        Log.debug("TS: partial ID3 PES at end of segment");
                    }
                    _curId3PES.position = _curId3PES.length;
                }
            }
            // push remaining tags and notify complete
            if (_tags.length) {
                CONFIG::LOGGING {
                    Log.debug2("TS: flush " + _tags.length + " tags");
                }
                _callback_progress(_tags);
                _tags = new Vector.<FLVTag>();
            }
            CONFIG::LOGGING {
                Log.debug("TS: parsing complete");
            }
        }

        /** parse ADTS audio PES packet **/
        private function _parseADTSPES(pes : PES) : void {
            var stamp : int;
            // check if previous ADTS frame was overflowing.
            if (_adtsFrameOverflow && _adtsFrameOverflow.length) {
                // if overflowing, append remaining data from previous frame at the beginning of PES packet
                CONFIG::LOGGING {
                    Log.debug("TS/AAC: append overflowing " + _adtsFrameOverflow.length + " bytes to beginning of new PES packet");
                }
                var ba : ByteArray = new ByteArray();
                ba.writeBytes(_adtsFrameOverflow);
                ba.writeBytes(pes.data, pes.payload);
                pes.data = ba;
                pes.payload = 0;
                _adtsFrameOverflow = null;
            }
            if (isNaN(pes.pts)) {
                CONFIG::LOGGING {
                    Log.warn("TS/AAC: no PTS info in this PES packet,discarding it");
                }
                return;
            }
            // insert ADIF TAG at the beginning
            if (_adifTagInserted == false) {
                var adifTag : FLVTag = new FLVTag(FLVTag.AAC_HEADER, pes.pts, pes.dts, true);
                var adif : ByteArray = AACDemuxer.getADIF(pes.data, pes.payload);
                CONFIG::LOGGING {
                    Log.debug("TS/AAC: insert ADIF TAG");
                }
                adifTag.push(adif, 0, adif.length);
                _tags.push(adifTag);
                _adifTagInserted = true;
            }
            // Store ADTS frames in array.
            var frames : Vector.<AudioFrame> = AACDemuxer.getFrames(pes.data, pes.payload);
            var frame : AudioFrame;
            for (var j : int = 0; j < frames.length; j++) {
                frame = frames[j];
                // Increment the timestamp of subsequent frames.
                stamp = Math.round(pes.pts + j * 1024 * 1000 / frame.rate);
                var curAudioTag : FLVTag = new FLVTag(FLVTag.AAC_RAW, stamp, stamp, false);
                curAudioTag.push(pes.data, frame.start, frame.length);
                _tags.push(curAudioTag);
            }
            if (frame) {
                // check if last ADTS frame is overflowing on next PES packet
                var adts_overflow : int = pes.data.length - (frame.start + frame.length);
                if (adts_overflow) {
                    _adtsFrameOverflow = new ByteArray();
                    _adtsFrameOverflow.writeBytes(pes.data, frame.start + frame.length);
                    CONFIG::LOGGING {
                        Log.debug("TS/AAC:ADTS frame overflow:" + adts_overflow);
                    }
                }
            } else {
                // no frame found, add data to overflow buffer
                _adtsFrameOverflow = new ByteArray();
                _adtsFrameOverflow.writeBytes(pes.data, pes.data.position);
                CONFIG::LOGGING {
                    Log.debug("TS/AAC:ADTS frame overflow:" + _adtsFrameOverflow.length);
                }
            }
        };

        /** parse MPEG audio PES packet **/
        private function _parseMPEGPES(pes : PES) : void {
            if (isNaN(pes.pts)) {
                CONFIG::LOGGING {
                    Log.warn("TS/MP3: no PTS info in this MP3 PES packet,discarding it");
                }
                return;
            }
            var tag : FLVTag = new FLVTag(FLVTag.MP3_RAW, pes.pts, pes.dts, false);
            tag.push(pes.data, pes.payload, pes.data.length - pes.payload);
            _tags.push(tag);
        };

        /** parse AVC PES packet **/
        private function _parseAVCPES(pes : PES) : void {
            var sps : ByteArray;
            var ppsvect : Vector.<ByteArray>;
            var sps_found : Boolean = false;
            var pps_found : Boolean = false;
            var frames : Vector.<VideoFrame> = Nalu.getNALU(pes.data, pes.payload);
            // If there's no NAL unit, push all data in the previous tag, if any exists
            if (!frames.length) {
                if (_curNalUnit) {
                    _curNalUnit.writeBytes(pes.data, pes.payload, pes.data.length - pes.payload);
                } else {
                    null; // just to avoid compilaton warnings if CONFIG::LOGGING is false
                    CONFIG::LOGGING {
                        Log.warn("TS: no NAL unit found in first (?) video PES packet, discarding data. possible segmentation issue ?");
                    }
                }
                return;
            }
            // If NAL units are not starting right at the beginning of the PES packet, push preceding data into previous NAL unit.
            var overflow : int = frames[0].start - frames[0].header - pes.payload;
            if (overflow && _curNalUnit) {
                _curNalUnit.writeBytes(pes.data, pes.payload, overflow);
            }
            if (isNaN(pes.pts)) {
                CONFIG::LOGGING {
                    Log.warn("TS: no PTS info in this AVC PES packet,discarding it");
                }
                return;
            }

            /* first loop : look for AUD/SPS/PPS NAL unit :
             * AUD (Access Unit Delimiter) are used to detect switch to new video tag 
             * SPS/PPS are used to generate AVC HEADER
             */

            for each (var frame : VideoFrame in frames) {
                if (frame.type == 9) {
                    if (_curVideoTag) {
                        /* AUD (Access Unit Delimiter) NAL unit:
                         * we need to push current video tag and start a new one
                         */
                        if (_curNalUnit && _curNalUnit.length) {
                            /* push current data into video tag, if any */
                            _curVideoTag.push(_curNalUnit, 0, _curNalUnit.length);
                        }
                        _tags.push(_curVideoTag);
                    }
                    _curNalUnit = new ByteArray();
                    _curVideoTag = new FLVTag(FLVTag.AVC_NALU, pes.pts, pes.dts, false);
                    // push NAL unit 9 into TAG
                    _curVideoTag.push(pes.data, frame.start, frame.length);
                } else if (frame.type == 7) {
                    sps_found = true;
                    sps = new ByteArray();
                    pes.data.position = frame.start;
                    pes.data.readBytes(sps, 0, frame.length);
                    // try to retrieve video width and height from SPS
                    var spsInfo : SPSInfo = new SPSInfo(sps);
                    sps.position = 0;
                    if (spsInfo.width && spsInfo.height) {
                        // notify upper layer
                        _callback_videometadata(spsInfo.width, spsInfo.height);
                    }
                } else if (frame.type == 8) {
                    if (!pps_found) {
                        pps_found = true;
                        ppsvect = new Vector.<ByteArray>();
                    }
                    var pps : ByteArray = new ByteArray();
                    pes.data.position = frame.start;
                    pes.data.readBytes(pps, 0, frame.length);
                    ppsvect.push(pps);
                }
            }
            // if both SPS and PPS have been found, build AVCC and push tag if needed
            if (sps_found && pps_found) {
                var avcc : ByteArray = AVCC.getAVCC(sps, ppsvect);
                // only push AVCC tag if never pushed or avcc different from previous one
                if (_avcc == null || !compareByteArray(_avcc, avcc)) {
                    _avcc = avcc;
                    var avccTag : FLVTag = new FLVTag(FLVTag.AVC_HEADER, pes.pts, pes.dts, true);
                    avccTag.push(avcc, 0, avcc.length);
                    // Log.debug("TS:AVC:push AVC HEADER");
                    _tags.push(avccTag);
                }
            }

            /* 
             * second loop, handle other NAL units and push them in tags accordingly
             */
            for each (frame in frames) {
                if (frame.type <= 6) {
                    if (_curNalUnit && _curNalUnit.length) {
                        _curVideoTag.push(_curNalUnit, 0, _curNalUnit.length);
                    }
                    _curNalUnit = new ByteArray();
                    _curNalUnit.writeBytes(pes.data, frame.start, frame.length);
                    // Unit type 5 indicates a keyframe.
                    if (frame.type == 5) {
                        _curVideoTag.keyframe = true;
                    } else if (frame.type == 1 || frame.type == 2) {
                        // retrieve slice type by parsing beginning of NAL unit (follow H264 spec, slice_header definition)
                        var ba : ByteArray = pes.data;
                        // +1 to skip NAL unit type
                        ba.position = frame.start + 1;
                        var eg : ExpGolomb = new ExpGolomb(ba);
                        /* add a try/catch, 
                         * as NALu might be partial here (in case NALu/slice header is splitted accross several PES packet ... we might end up 
                         * with buffer overflow. prevent this and in case of overflow assume it is not a keyframe. should be fixed later on 
                         */
                        try {
                            // discard first_mb_in_slice
                            eg.readUE();
                            var type : uint = eg.readUE();
                            if (type == 2 || type == 4 || type == 7 || type == 9) {
                                CONFIG::LOGGING {
                                    Log.debug("TS: frame_type:" + frame.type + ",keyframe slice_type:" + type);
                                }
                                _curVideoTag.keyframe = true;
                            }
                        } catch(e : Error) {
                            CONFIG::LOGGING {
                                Log.warn("TS: frame_type:" + frame.type + ": slice header splitted accross several PES packets, assuming not a keyframe");
                            }
                            _curVideoTag.keyframe = false;
                        }
                    }
                }
            }
        }

        // return true if same Byte Array
        private function compareByteArray(ba1 : ByteArray, ba2 : ByteArray) : Boolean {
            // compare the lengths
            var size : uint = ba1.length;
            if (ba1.length == ba2.length) {
                ba1.position = 0;
                ba2.position = 0;

                // then the bytes
                while (ba1.position < size) {
                    var v1 : int = ba1.readByte();
                    if (v1 != ba2.readByte()) {
                        return false;
                    }
                }
                return true;
            }
            return false;
        }

        /** parse ID3 PES packet **/
        private function _parseID3PES(pes : PES) : void {
            // note: apple spec does not include having PTS in ID3!!!!
            // so we should really spoof the PTS by knowing the PCR at this point
            if (isNaN(pes.pts)) {
                CONFIG::LOGGING {
                    Log.warn("TS: no PTS info in this ID3 PES packet,discarding it");
                }
                return;
            }

            var pespayload : ByteArray = new ByteArray();
            if (pes.data.length >= pes.payload + pes.payload_len) {
                pes.data.position = pes.payload;
                pespayload.writeBytes(pes.data, pes.payload, pes.payload_len);
                pespayload.position = 0;
            }
            pes.data.position = 0;

            var tag : FLVTag = new FLVTag(FLVTag.METADATA, pes.pts, pes.pts, false);
            var data : ByteArray = new ByteArray();
            data.objectEncoding = ObjectEncoding.AMF0;

            // one or more SCRIPTDATASTRING + SCRIPTDATAVALUE
            data.writeObject("onID3Data");
            // SCRIPTDATASTRING - name of object
            // to pass ByteArray, change to AMF3
            data.objectEncoding = ObjectEncoding.AMF3;
            data.writeByte(0x11);
            // AMF3 escape
            // then write the ByteArray
            data.writeObject(pespayload);
            tag.push(data, 0, data.length);
            _tags.push(tag);
        }

        /** Parse TS packet. **/
        private function _parseTSPacket() : void {
            // Each packet is 188 bytes.
            var todo : uint = TSDemuxer.PACKETSIZE;
            // Sync byte.
            if (_data.readByte() != TSDemuxer.SYNCBYTE) {
                var pos_start : uint = _data.position - 1;
                if (probe(_data) == true) {
                    var pos_end : uint = _data.position;
                    CONFIG::LOGGING {
                        Log.warn("TS: lost sync between offsets:" + pos_start + "/" + pos_end);
                        if (HLSSettings.logDebug2) {
                            var ba : ByteArray = new ByteArray();
                            _data.position = pos_start;
                            _data.readBytes(ba, 0, pos_end - pos_start);
                            Log.debug2("TS: lost sync dump:" + Hex.fromArray(ba));
                        }
                    }
                    _data.position = pos_end + 1;
                } else {
                    throw new Error("TS: Could not parse file: sync byte not found @ offset/len " + _data.position + "/" + _data.length);
                }
            }
            todo--;
            // Payload unit start indicator.
            var stt : uint = (_data.readUnsignedByte() & 64) >> 6;
            _data.position--;

            // Packet ID (last 13 bits of UI16).
            var pid : uint = _data.readUnsignedShort() & 8191;
            // Check for adaptation field.
            todo -= 2;
            var atf : uint = (_data.readByte() & 48) >> 4;
            todo--;
            // Read adaptation field if available.
            if (atf > 1) {
                // Length of adaptation field.
                var len : uint = _data.readUnsignedByte();
                todo--;
                // Random access indicator (keyframe).
                // var rai:uint = data.readUnsignedByte() & 64;
                _data.position += len;
                todo -= len;
                // Return if there's only adaptation field.
                if (atf == 2 || len == 183) {
                    _data.position += todo;
                    return;
                }
            }

            // Parse the PES, split by Packet ID.
            switch (pid) {
                case PAT_ID:
                    todo -= _parsePAT(stt);
                    if (_pmtParsed == false) {
                        null; // just to avoid compilaton warnings if CONFIG::LOGGING is false
                        CONFIG::LOGGING {
                            Log.debug("TS: PAT found.PMT PID:" + _pmtId);
                        }
                    }
                    break;
                case _pmtId:
                    if (_pmtParsed == false) {
                        CONFIG::LOGGING {
                            Log.debug("TS: PMT found");
                        }
                        todo -= _parsePMT(stt);
                        _pmtParsed = true;
                        // if PMT was not parsed before, and some unknown packets have been skipped in between,
                        // rewind to beginning of the stream, it helps recovering bad segmented content
                        // in theory there should be no A/V packets before PAT/PMT)
                        if (_packetsBeforePMT) {
                            CONFIG::LOGGING {
                                Log.warn("TS: late PMT found, rewinding at beginning of TS");
                            }
                            _data.position = 0;
                            return;
                        }
                    }
                    break;
                case _audioId:
                    if (_pmtParsed == false) {
                        break;
                    }
                    if (stt) {
                        if (_curAudioPES) {
                            if (_audioIsAAC) {
                                _parseADTSPES(new PES(_curAudioPES, true));
                            } else {
                                _parseMPEGPES(new PES(_curAudioPES, true));
                            }
                        }
                        _curAudioPES = new ByteArray();
                    }
                    if (_curAudioPES) {
                        _curAudioPES.writeBytes(_data, _data.position, todo);
                    } else {
                        null; // just to avoid compilaton warnings if CONFIG::LOGGING is false
                        CONFIG::LOGGING {
                            Log.warn("TS: Discarding audio packet with id " + pid);
                        }
                    }
                    break;
                case _id3Id:
                    if (_pmtParsed == false) {
                        break;
                    }
                    if (stt) {
                        if (_curId3PES) {
                            _parseID3PES(new PES(_curId3PES, false));
                        }
                        _curId3PES = new ByteArray();
                    }
                    if (_curId3PES) {
                        // store data.  will normally be in a single TS
                        _curId3PES.writeBytes(_data, _data.position, todo);
                        var pes : PES = new PES(_curId3PES, false);
                        if (pes.len && (pes.data.length - pes.payload - pes.payload_len) >= 0) {
                            CONFIG::LOGGING {
                                Log.debug2("TS: complete ID3 PES found, parse it");
                            }
                            // complete PES, parse and push into the queue
                            _parseID3PES(pes);
                            _curId3PES = null;
                        } else {
                            CONFIG::LOGGING {
                                Log.debug("TS: partial ID3 PES");
                            }
                            _curId3PES.position = _curId3PES.length;
                        }
                    } else {
                        null;
                        // just to avoid compilation warnings if CONFIG::LOGGING is false
                        CONFIG::LOGGING {
                            Log.warn("TS: Discarding ID3 packet with id " + pid + " bad TS segmentation ?");
                        }
                    }
                    break;
                case _avcId:
                    if (_pmtParsed == false) {
                        break;
                    }
                    if (stt) {
                        if (_curVideoPES) {
                            _parseAVCPES(new PES(_curVideoPES, false));
                        }
                        _curVideoPES = new ByteArray();
                    }
                    if (_curVideoPES) {
                        _curVideoPES.writeBytes(_data, _data.position, todo);
                    } else {
                        null; // just to avoid compilaton warnings if CONFIG::LOGGING is false
                        CONFIG::LOGGING {
                            Log.warn("TS: Discarding video packet with id " + pid + " bad TS segmentation ?");
                        }
                    }
                    break;
                case SDT_ID:
                    break;
                default:
                    _packetsBeforePMT = true;
                    break;
            }
            // Jump to the next packet.
            _data.position += todo;
        };

        /** Parse the Program Association Table. **/
        private function _parsePAT(stt : uint) : int {
            var pointerField : uint = 0;
            if (stt) {
                pointerField = _data.readUnsignedByte();
                // skip alignment padding
                _data.position += pointerField;
            }
            // skip table id
            _data.position += 1;
            // get section length
            var sectionLen : uint = _data.readUnsignedShort() & 0x3FF;
            // Check the section length for a single PMT.
            if (sectionLen > 13) {
                throw new Error("TS: Multiple PMT entries are not supported.");
            }
            // Grab the PMT ID.
            _data.position += 7;
            _pmtId = _data.readUnsignedShort() & 8191;
            return 13 + pointerField;
        };

        /** Read the Program Map Table. **/
        private function _parsePMT(stt : uint) : int {
            var pointerField : uint = 0;

            /** audio Track List */
            var audioList : Vector.<AudioTrack> = new Vector.<AudioTrack>();

            if (stt) {
                pointerField = _data.readUnsignedByte();
                // skip alignment padding
                _data.position += pointerField;
            }
            // skip table id
            _data.position += 1;
            // Check the section length for a single PMT.
            var len : uint = _data.readUnsignedShort() & 0x3FF;
            var read : uint = 13;
            _data.position += 7;
            // skip program info
            var pil : uint = _data.readUnsignedShort() & 0x3FF;
            _data.position += pil;
            read += pil;
            // Loop through the streams in the PMT.
            while (read < len) {
                // stream type
                var typ : uint = _data.readByte();
                // stream pid
                var sid : uint = _data.readUnsignedShort() & 0x1fff;
                if (typ == 0x0F) {
                    // ISO/IEC 13818-7 ADTS AAC (MPEG-2 lower bit-rate audio)
                    audioList.push(new AudioTrack('TS/AAC ' + audioList.length, AudioTrack.FROM_DEMUX, sid, (audioList.length == 0), true));
                } else if (typ == 0x1B) {
                    // ITU-T Rec. H.264 and ISO/IEC 14496-10 (lower bit-rate video)
                    _avcId = sid;
                    CONFIG::LOGGING {
                        Log.debug("TS: Selected video PID: " + _avcId);
                    }
                } else if (typ == 0x03 || typ == 0x04) {
                    // ISO/IEC 11172-3 (MPEG-1 audio)
                    // or ISO/IEC 13818-3 (MPEG-2 halved sample rate audio)
                    audioList.push(new AudioTrack('TS/MP3 ' + audioList.length, AudioTrack.FROM_DEMUX, sid, (audioList.length == 0), false));
                } else if (typ == 0x15) {
                    // ID3 pid
                    _id3Id = sid;
                    CONFIG::LOGGING {
                        Log.debug("TS: Selected ID3 PID: " + _id3Id);
                    }
                }
                // es_info_length
                var sel : uint = _data.readUnsignedShort() & 0xFFF;
                _data.position += sel;
                // loop to next stream
                read += sel + 5;
            }

            if (audioList.length) {
                null; // just to avoid compilaton warnings if CONFIG::LOGGING is false
                CONFIG::LOGGING {
                    Log.debug("TS: Found " + audioList.length + " audio tracks");
                }
            }
            // provide audio track List to audio select callback. this callback will return the selected audio track
            var audioPID : int;
            var audioTrack : AudioTrack = _callback_audioselect(audioList);
            if (audioTrack) {
                audioPID = audioTrack.id;
                _audioIsAAC = audioTrack.isAAC;
                CONFIG::LOGGING {
                    Log.debug("TS: selected " + (_audioIsAAC ? "AAC" : "MP3") + " PID: " + audioPID);
                }
            } else {
                audioPID = -1;
                CONFIG::LOGGING {
                    Log.debug("TS: no audio selected");
                }
            }
            // in case audio PID change, flush any partially parsed audio PES packet
            if (audioPID != _audioId) {
                _curAudioPES = null;
                _adtsFrameOverflow = null;
                _audioId = audioPID;
            }
            return len + pointerField;
        };
    }
}