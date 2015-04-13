/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.utils {
    import by.blooddy.crypto.Base64;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.ProgressEvent;
    import flash.events.TimerEvent;
    import flash.external.ExternalInterface;
    import flash.net.URLRequest;
    import flash.net.URLStream;
    import flash.utils.ByteArray;
    import flash.utils.getTimer;
    import flash.utils.Timer;

    CONFIG::LOGGING {
    import org.mangui.hls.utils.Log;
    }

    // Fragment Loader
    public dynamic class JSURLStream extends URLStream {
        private var _connected : Boolean;
        private var _resource : ByteArray = new ByteArray();
        /** Timer for decode packets **/
        private var _timer : Timer;
        /** base64 read position **/
        private var _read_position : uint;
        /** final length **/
        private var _final_length : uint;
        /** read position **/
        private var _base64_resource : String;
        /* callback names */
        private var _callback_loaded : String;
        private var _callback_failure : String;
        /** chunk size to avoid blocking **/
        private static const CHUNK_SIZE : uint = 65536;
        private static var _instance_count : int = 0;

        public function JSURLStream() {
            addEventListener(Event.OPEN, onOpen);
            super();
            // Connect calls to JS.
            if (ExternalInterface.available) {
                CONFIG::LOGGING {
                    Log.debug("add callback resourceLoaded, id:" + _instance_count);
                }
                _callback_loaded = "resourceLoaded" + _instance_count;
                _callback_failure = "resourceLoadingError" + _instance_count;
                // dynamically register callbacks
                this[_callback_loaded] = function(res,len): void { resourceLoaded(res,len)};
                this[_callback_failure] = function() : void { resourceLoadingError()};
                ExternalInterface.addCallback(_callback_loaded, this[_callback_loaded]);
                ExternalInterface.addCallback(_callback_failure, this[_callback_failure]);
                _instance_count++;
            }
        }

        override public function get connected() : Boolean {
            return _connected;
        }

        override public function get bytesAvailable() : uint {
            return _resource.bytesAvailable;
        }

        override public function readByte() : int {
            return _resource.readByte();
        }

        override public function readUnsignedShort() : uint {
            return _resource.readUnsignedShort();
        }

        override public function readBytes(bytes : ByteArray, offset : uint = 0, length : uint = 0) : void {
            _resource.readBytes(bytes, offset, length);
        }

        override public function close() : void {
        }

        override public function load(request : URLRequest) : void {
            CONFIG::LOGGING {
            Log.debug("JSURLStream.load:" + request.url);
            }
            if (ExternalInterface.available) {
                ExternalInterface.call("JSLoaderFragment.onRequestResource",ExternalInterface.objectID, request.url,_callback_loaded,_callback_failure);
                this.dispatchEvent(new Event(Event.OPEN));
            } else {
                super.load(request);
            }
        }

        private function onOpen(event : Event) : void {
            _connected = true;
        }

        protected function resourceLoaded(base64Resource : String, len : uint) : void {
            CONFIG::LOGGING {
              Log.debug("resourceLoaded");
            }
            _resource = new ByteArray();
            _read_position = 0;
            _final_length = len;
            _timer = new Timer(20, 0);
            _timer.addEventListener(TimerEvent.TIMER, _decodeData);
            _timer.start();
            _base64_resource = base64Resource;
        }

        protected function resourceLoadingError() : void {
            CONFIG::LOGGING {
            Log.debug("resourceLoadingError");
            }
            _timer.stop();
            this.dispatchEvent(new IOErrorEvent(IOErrorEvent.IO_ERROR));
        }

        protected function resourceLoadingSuccess() : void {
            CONFIG::LOGGING {
            Log.debug("resourceLoaded and decoded");
            }
	     _timer.stop();
	     this.dispatchEvent(new Event(Event.COMPLETE));
        }

        /** decrypt a small chunk of packets each time to avoid blocking **/
        private function _decodeData(e : Event) : void {
            var start_time : int = getTimer();
            var decode_completed : Boolean = false;
            // dont spend more than 20ms base64 decoding to avoid fps drop
            while ((!decode_completed) && ((getTimer() - start_time) < 10)) {
                var start_pos : uint = _read_position,end_pos : uint;
                if (_base64_resource.length <= _read_position + CHUNK_SIZE) {
                    end_pos = _base64_resource.length;
                    decode_completed = true;
                } else {
                    end_pos = _read_position + CHUNK_SIZE;
                    _read_position = end_pos;
                }
                var tmpString : String = _base64_resource.substring(start_pos, end_pos);
                var savePosition : uint = _resource.position;
                try {
                    _resource.position = _resource.length;
                    _resource.writeBytes(Base64.decode(tmpString));
                    _resource.position = savePosition;
                } catch (error:Error) {
                    resourceLoadingError();
                }
            }
            this.dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, false, false, _resource.length, _final_length));
            if (decode_completed) {
                resourceLoadingSuccess();
            }
        }
    }
}
