/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.playlist {
    import org.mangui.hls.HLS;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.event.HLSError;
    import org.mangui.hls.utils.Hex;

    import flash.events.*;
    import flash.net.*;
    import flash.utils.ByteArray;

    import org.mangui.hls.constant.HLSTypes;
    import org.mangui.hls.model.Level;
    import org.mangui.hls.model.Fragment;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
    /** Helpers for parsing M3U8 files. **/
    public class Manifest {
        /** Starttag for a fragment. **/
        public static const FRAGMENT : String = '#EXTINF:';
        /** Header tag that must be at the first line. **/
        public static const HEADER : String = '#EXTM3U';
        /** Version of the playlist file. **/
        public static const VERSION : String = '#EXT-X-VERSION';
        /** Starttag for a level. **/
        public static const LEVEL : String = '#EXT-X-STREAM-INF:';
        /** Tag that delimits the end of a playlist. **/
        public static const ENDLIST : String = '#EXT-X-ENDLIST';
        /** Tag that provides info related to alternative audio tracks */
        public static const ALTERNATE_AUDIO : String = '#EXT-X-MEDIA:TYPE=AUDIO,';
        /** Tag that provides the sequence number. **/
        private static const SEQNUM : String = '#EXT-X-MEDIA-SEQUENCE:';
        /** Tag that provides the target duration for each segment. **/
        private static const TARGETDURATION : String = '#EXT-X-TARGETDURATION:';
        /** Tag that indicates discontinuity in the stream */
        private static const DISCONTINUITY : String = '#EXT-X-DISCONTINUITY';
        /** Tag that indicates discontinuity sequence in the stream */
        private static const DISCONTINUITY_SEQ : String = '#EXT-X-DISCONTINUITY-SEQUENCE:';
        /** Tag that provides date/time information */
        private static const PROGRAMDATETIME : String = '#EXT-X-PROGRAM-DATE-TIME';
        /** Tag that provides fragment decryption info */
        private static const KEY : String = '#EXT-X-KEY:';
        /** Tag that provides byte range info */
        private static const BYTERANGE : String = '#EXT-X-BYTERANGE:';
        /** useful regular expression */
        private static const replacespace : RegExp = new RegExp("\\s+", "g");
        private static const replacesinglequote : RegExp = new RegExp("\\\'", "g");
        private static const replacedoublequote : RegExp = new RegExp("\\\"", "g");
        /** Index in the array with levels. **/
        private var _index : int;
        /** URLLoader instance. **/
        private var _urlloader : URLLoader;
        /** Function to callback loading to. **/
        private var _success : Function;
        /** URL of an M3U8 playlist. **/
        private var _url : String;

        /** Load a playlist M3U8 file. **/
        public function loadPlaylist(url : String, success : Function, error : Function, index : int, type : String, flushLiveURLcache : Boolean) : void {
            _url = url;
            _success = success;
            _index = index;
            _urlloader = new URLLoader();
            _urlloader.addEventListener(Event.COMPLETE, _loaderHandler);
            _urlloader.addEventListener(IOErrorEvent.IO_ERROR, error);
            _urlloader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, error);

            if (flushLiveURLcache && type == HLSTypes.LIVE) {
                /*
                add time parameter to force reload URL, there are some issues with browsers/CDN reloading from cache even if the URL has been updated ...
                see http://stackoverflow.com/questions/14448219/as3-resetting-urlloader-cache
                 */
                var extra : String = "time=" + new Date().getTime();
                if (_url.indexOf("?") == -1) {
                    url += "?" + extra;
                } else {
                    url += "&" + extra;
                }
            }
            if (DataUri.isDataUri(url)) {
                CONFIG::LOGGING {
                    Log.debug("Identified playlist <" + url + "> as a data URI.");
                }
                var data : String = new DataUri(url).extractData();
                onLoadedData(data || "");
                return;
            }

            _urlloader.load(new URLRequest(url));
        };

        /* cancel loading in progress */
        public function close() : void {
            try {
                _urlloader.close();
            } catch(e : Error) {
            }
        }

        /** The M3U8 playlist was loaded. **/
        private function _loaderHandler(event : Event) : void {
            var loader : URLLoader = URLLoader(event.target);
            onLoadedData(String(loader.data));
        };

        private function onLoadedData(data : String) : void {
            _success(data, _url, _index);
        }

        private static function zeropad(str : String, length : uint) : String {
            while (str.length < length) {
                str = "0" + str;
            }
            return str;
        }

        /** Extract fragments from playlist data. **/
        public static function getFragments(data : String, base : String , level : int) : Vector.<Fragment> {
            var fragments : Vector.<Fragment> = new Vector.<Fragment>();
            var lines : Array = data.split("\n");
            // fragment seqnum
            var seqnum : int = 0;
            // fragment start time (in sec)
            var start_time : Number = 0;
            // nb of ms since epoch
            var program_date : Number = 0;
            var program_date_defined : Boolean = false;
            /* URL of decryption key */
            var decrypt_url : String = null;
            /* Initialization Vector */
            var decrypt_iv : ByteArray = null;
            // fragment continuity index incremented at each discontinuity
            var continuity_index : int = 0;
            var i : int = 0;
            var extinf_found : Boolean = false;
            var byterange_start_offset : int = -1;
            var byterange_end_offset : int = -1;
            var tag_list : Vector.<String> = new Vector.<String>();

            while (i < lines.length) {
                var line : String = lines[i++];
                // discard blank line, length could be 0 or 1 if DOS terminated line (CR/LF)
                if (line.length <= 1) {
                    continue;
                }

                // discard tags pertaining to a playlist and not a fragment, that require no further processing
                if (line.indexOf(HEADER) == 0 || line.indexOf(TARGETDURATION) == 0 || line.indexOf(VERSION) == 0) {
                    continue;
                }

                if (line.indexOf(SEQNUM) == 0) {
                    seqnum = parseInt(line.substr(SEQNUM.length));
                } else if (line.indexOf(DISCONTINUITY_SEQ) == 0) {
                    continuity_index = parseInt(line.substr(DISCONTINUITY_SEQ.length));
                } else if (line.indexOf(BYTERANGE) == 0) {
                    var params : Array = line.substr(BYTERANGE.length).split('@');
                    if (params.length == 1) {
                        byterange_start_offset = byterange_end_offset;
                    } else {
                        byterange_start_offset = parseInt(params[1]);
                    }
                    byterange_end_offset = parseInt(params[0]) + byterange_start_offset;
                    tag_list.push(line);
                } else if (line.indexOf(KEY) == 0) {
                    // #EXT-X-KEY:METHOD=AES-128,URI="https://priv.example.com/key.php?r=52",IV=.....
                    var keyLine : String = line.substr(KEY.length);
                    // reset previous values
                    decrypt_url = null;
                    decrypt_iv = null;
                    // remove space, single and double quote
                    keyLine = keyLine.replace(replacespace, "");
                    keyLine = keyLine.replace(replacesinglequote, "");
                    keyLine = keyLine.replace(replacedoublequote, "");
                    var keyArray : Array = keyLine.split(",");
                    var keyArray2 : Array = new Array();
                    /* correctly parse #EXT-X-KEY:METHOD=AES-128,URI="Keys(LiveTest-m3u8-aapl,format=m3u8-aapl).key"
                     * take into account comma not followed by attribute name, append value to previous entry
                     */
                    for each (var key : String in keyArray) {
                        if (key.indexOf("METHOD=") == 0 || key.indexOf("URI=") == 0 || key.indexOf("IV=") == 0 || key.indexOf("KEYFORMAT=") == 0 || key.indexOf("KEYFORMATVERSIONS=") == 0) {
                            keyArray2.push(key);
                        } else {
                            if (keyArray2.length) {
                                // append to previous element
                                keyArray2[keyArray2.length - 1] += "," + key;
                            }
                        }
                    }

                    for each (var keyProperty : String in keyArray2) {
                        var delimiter : int = keyProperty.indexOf("=");
                        if (delimiter == -1) {
                            throw new Error("invalid playlist, no delimiter while parsing:" + keyProperty);
                        }
                        var tag : String = keyProperty.substr(0, delimiter).toUpperCase();
                        var value : String = keyProperty.substr(delimiter + 1);
                        switch(tag) {
                            case "METHOD":
                                switch (value) {
                                    case "NONE":
                                    case "AES-128":
                                        break;
                                    case "AES-SAMPLE":
                                        throw new Error("encryption method " + value + "not supported (yet ;-))");
                                    default:
                                        throw new Error("invalid encryption method " + value);
                                        break;
                                }
                                break;
                            case "URI":
                                decrypt_url = _extractURL(value, base);
                                break;
                            case "IV":
                                decrypt_iv = Hex.toArray(zeropad(value.substr("0x".length), 32));
                                break;
                            case "KEYFORMAT":
                            case "KEYFORMATVERSIONS":
                            default:
                                break;
                        }
                    }
                    tag_list.push(line);
                } else if (line.indexOf(PROGRAMDATETIME) == 0) {
                    // CONFIG::LOGGING {
                    // Log.info(line);
                    // }
                    var year : int = parseInt(line.substr(25, 4));
                    var month : int = parseInt(line.substr(30, 2));
                    var day : int = parseInt(line.substr(33, 2));
                    var hour : int = parseInt(line.substr(36, 2));
                    var minutes : int = parseInt(line.substr(39, 2));
                    var seconds : int = parseInt(line.substr(42, 2));
                    // month should be from 0 (January) to 11 (December).
                    program_date = new Date(year, (month - 1), day, hour, minutes, seconds).getTime();
                    program_date_defined = true;
                    tag_list.push(line);
                } else if (line.indexOf(DISCONTINUITY) == 0) {
                    continuity_index++;
                    tag_list.push(line);
                } else if (line.indexOf(FRAGMENT) == 0) {
                    var comma_position : int = line.indexOf(',');
                    var duration : Number = (comma_position == -1) ? parseFloat(line.substr(FRAGMENT.length)) : parseFloat(line.substr(FRAGMENT.length, comma_position - FRAGMENT.length));
                    extinf_found = true;
                    tag_list.push(line);
                } else if (line.indexOf('#') == 0) {
                    // unsupported/custom tags, store them
                    tag_list.push(line);
                } else if (extinf_found == true) {
                    var url : String = _extractURL(line, base);
                    var fragment_decrypt_iv : ByteArray;
                    if (decrypt_url != null) {
                        /* as per HLS spec :
                        if IV not defined, then use seqnum as IV :
                        http://tools.ietf.org/html/draft-pantos-http-live-streaming-11#section-5.2
                         */
                        if (decrypt_iv != null) {
                            fragment_decrypt_iv = decrypt_iv;
                        } else {
                            fragment_decrypt_iv = Hex.toArray(zeropad(seqnum.toString(16), 32));
                        }

                        CONFIG::LOGGING {
                            Log.debug("sn/key/iv:" + seqnum + "/" + decrypt_url + "/" + Hex.fromArray(fragment_decrypt_iv));
                        }
                    } else {
                        fragment_decrypt_iv = null;
                    }
                    fragments.push(new Fragment(url, duration, level, seqnum++, start_time, continuity_index, program_date, decrypt_url, fragment_decrypt_iv, byterange_start_offset, byterange_end_offset, tag_list));
                    start_time += duration;
                    if (program_date_defined) {
                        program_date += 1000 * duration;
                    }
                    extinf_found = false;
                    tag_list = new Vector.<String>();
                    byterange_start_offset = -1;
                }
            }
            if (fragments.length == 0) {
                // throw new Error("No TS fragments found in " + base);
                null;
                // just to avoid compilation warnings if CONFIG::LOGGING is false
                CONFIG::LOGGING {
                    Log.warn("No TS fragments found in " + base);
                }
            }
            return fragments;
        };

        /** Extract levels from manifest data. **/
        public static function extractLevels(hls : HLS, data : String, base : String = '') : Vector.<Level> {
            var levels : Array = [];
            var level : Level;
            var lines : Array = data.split("\n");
            var level_found : Boolean = false;
            var i : int = 0;
            while (i < lines.length) {
                var line : String = lines[i++];
                // discard blank line, length could be 0 or 1 if DOS terminated line (CR/LF)
                if (line.length <= 1) {
                    continue;
                }
                if (line.indexOf(LEVEL) == 0) {
                    level_found = true;
                    level = new Level();
                    var params : Array = line.substr(LEVEL.length).split(',');
                    for (var j : int = 0; j < params.length; j++) {
                        var param : String = params[j];
                        if (param.indexOf('BANDWIDTH') > -1) {
                            level.bitrate = param.split('=')[1];
                        } else if (param.indexOf('RESOLUTION') > -1) {
                            var res : String = param.split('=')[1] as String;
                            var dim : Array = res.split('x');
                            level.width = parseInt(dim[0]);
                            level.height = parseInt(dim[1]);
                        } else if (param.indexOf('CODECS') > -1) {
                            if (line.indexOf('avc1') > -1) {
                                level.codec_h264 = true;
                            } else {
                                level.audio = true;
                            }
                            if (line.indexOf('mp4a.40.2') > -1 || line.indexOf('mp4a.40.5') > -1) {
                                level.codec_aac = true;
                            } else if (line.indexOf('mp4a.40.34') > -1) {
                                level.codec_mp3 = true;
                            }
                        } else if (param.indexOf('AUDIO') > -1) {
                            level.audio_stream_id = (param.split('=')[1] as String).replace(replacedoublequote, "");
                        } else if (param.indexOf('NAME') > -1) {
                            level.name = (param.split('=')[1] as String).replace(replacedoublequote, "");
                        }
                    }
                } else if (level_found == true) {
                    level.url = _extractURL(line, base);
                    levels.push(level);
                    level_found = false;
                }
            }
            var levelsLength : int = levels.length;
            if (levelsLength == 0) {
                var hlsError : HLSError = new HLSError(HLSError.MANIFEST_PARSING_ERROR, base, "No level found in Manifest");
                hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
            }
            levels.sortOn('bitrate', Array.NUMERIC);
            var vectorLevels : Vector.<Level> = new Vector.<Level>();
            for (i = 0; i < levelsLength; i++) {
                level = levels[i];
                level.index = i;
                vectorLevels.push(level);
            }
            return vectorLevels;
        };

        /** Extract Alternate Audio Tracks from manifest data. **/
        public static function extractAltAudioTracks(data : String, base : String = '') : Vector.<AltAudioTrack> {
            var altAudioTracks : Vector.<AltAudioTrack> = new Vector.<AltAudioTrack>();
            var lines : Array = data.split("\n");
            var i : int = 0;
            while (i < lines.length) {
                var line : String = lines[i++];
                if (line.indexOf(ALTERNATE_AUDIO) == 0) {
                    line = line.replace(replacedoublequote, "");
                    CONFIG::LOGGING {
                        Log.debug("parsing alternate audio level info:\n" + line);
                    }
                    // #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="bipbop_audio",LANGUAGE="eng",NAME="BipBop Audio 1",AUTOSELECT=YES,DEFAULT=YES
                    // #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="bipbop_audio",LANGUAGE="eng",NAME="BipBop Audio 2",AUTOSELECT=NO,DEFAULT=NO,URI="alternate_audio_aac_sinewave/prog_index.m3u8"
                    var params : Array = line.substr(ALTERNATE_AUDIO.length).split(',');
                    var alt_group_id : String;
                    var alt_lang : String;
                    var alt_name : String;
                    var alt_autoselect : Boolean = false;
                    var alt_default : Boolean = false;
                    var alt_url : String;
                    for (var j : int = 0; j < params.length; j++) {
                        var param : String = params[j];
                        if (param.indexOf('GROUP-ID') > -1) {
                            alt_group_id = param.split('=')[1];
                        } else if (param.indexOf('LANGUAGE') > -1) {
                            alt_lang = param.split('=')[1];
                        } else if (param.indexOf('NAME') > -1) {
                            alt_name = param.split('=')[1];
                        } else if (param.indexOf('AUTOSELECT') > -1) {
                            if (param.split('=')[1] == "NO") {
                                alt_autoselect = false;
                            } else {
                                alt_autoselect = true;
                            }
                        } else if (param.indexOf('DEFAULT') > -1) {
                            if (param.split('=')[1] == "NO") {
                                alt_default = false;
                            } else {
                                alt_default = true;
                            }
                        } else if (param.indexOf('URI') > -1) {
                            alt_url = Manifest._extractURL(param.split('=')[1], base);
                        }
                    }
                    var alternate_audio : AltAudioTrack = new AltAudioTrack(alt_group_id, alt_lang, alt_name, alt_autoselect, alt_default, alt_url);
                    altAudioTracks.push(alternate_audio);
                }
            }
            return altAudioTracks;
        };

        /** Extract whether the stream is live or ondemand. **/
        public static function hasEndlist(data : String) : Boolean {
            if (data.indexOf(ENDLIST) > 0) {
                return true;
            } else {
                return false;
            }
        };

        public static function getTargetDuration(data : String) : Number {
            var lines : Array = data.split("\n");
            var i : int = 0;
            var targetduration : Number = 0;

            // first look for target duration
            while (i < lines.length) {
                var line : String = lines[i++];
                if (line.indexOf(TARGETDURATION) == 0) {
                    targetduration = parseFloat(line.substr(TARGETDURATION.length));
                    break;
                }
            }
            return targetduration;
        }

        /** Extract URL (check if absolute or not). **/
        private static function _extractURL(path : String, base : String) : String {
            var _prefix : String = null;
            var _suffix : String = null;
            // trim white space if any
            path.replace(replacespace, "");
            if (path.substr(0, 7) == 'http://' || path.substr(0, 8) == 'https://') {
                return path;
            } else {
                // Remove querystring
                if (base.indexOf('?') > -1) {
                    base = base.substr(0, base.indexOf('?'));
                }
                // domain-absolute
                if (path.charAt(0) == '/') {
                    // base = http[s]://domain/subdomain:1234/otherstuff
                    // prefix = http[s]://
                    // suffix = domain/subdomain:1234/otherstuff
                    _prefix = base.substr(0, base.indexOf("//") + 2);
                    _suffix = base.substr(base.indexOf("//") + 2);
                    // return http[s]://domain/subdomain:1234/path
                    return _prefix + _suffix.substr(0, _suffix.indexOf("/")) + path;
                } else {
                    return base.substr(0, base.lastIndexOf('/') + 1) + path;
                }
            }
        };
    }
}
