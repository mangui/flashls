/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.utils {
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.ProgressEvent;
    import flash.events.TimerEvent;
    import flash.external.ExternalInterface;
    import flash.net.URLRequest;
    import flash.net.URLLoader;

    CONFIG::LOGGING {
    import org.mangui.hls.utils.Log;
    }

    // Playlist Loader
    public dynamic class JSURLLoader extends URLLoader {
        private var _resource : String = new String();
        /* callback names */
        private var _callback_loaded : String;
        private var _callback_failure : String;
        private static var _instance_count : int = 0;

        public function JSURLLoader() {
            super();
            // Connect calls to JS.
            if (ExternalInterface.available) {
                CONFIG::LOGGING {
                    Log.debug("add callback resourceLoaded, id:" + _instance_count);
                }
                _callback_loaded = "textLoaded" + _instance_count;
                _callback_failure = "textLoadingError" + _instance_count;
                // dynamically register callbacks
                this[_callback_loaded] = function(res): void { resourceLoaded(res)};
                this[_callback_failure] = function() : void { resourceLoadingError()};
                ExternalInterface.addCallback(_callback_loaded, this[_callback_loaded]);
                ExternalInterface.addCallback(_callback_failure, this[_callback_failure]);
                _instance_count++;
            }
        }

        override public function close() : void {
        }

        override public function load(request : URLRequest) : void {
            CONFIG::LOGGING {
            Log.debug("JSURLLoader.load:" + request.url);
            }
            bytesLoaded = bytesTotal = 0;
            data = null;
            if (ExternalInterface.available) {
                ExternalInterface.call("JSLoaderPlaylist.onRequestResource",ExternalInterface.objectID, request.url,_callback_loaded,_callback_failure);
                this.dispatchEvent(new Event(Event.OPEN));
            } else {
                super.load(request);
            }
        }

        protected function resourceLoaded(resource : String) : void {
            CONFIG::LOGGING {
              Log.debug("resourceLoaded");
            }
            data = resource;
            bytesLoaded = bytesTotal = resource.length;
            this.dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, false, false, bytesLoaded, bytesTotal));
            this.dispatchEvent(new Event(Event.COMPLETE));
        }

        protected function resourceLoadingError() : void {
            CONFIG::LOGGING {
                Log.debug("resourceLoadingError");
            }
            this.dispatchEvent(new IOErrorEvent(IOErrorEvent.IO_ERROR));
        }
    }
}
