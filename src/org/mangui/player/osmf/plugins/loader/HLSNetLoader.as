/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.player.osmf.plugins.loader {

    import flash.net.NetConnection;
    import flash.net.NetStream;
    import org.mangui.hls.HLS;
    import org.osmf.media.URLResource;
    import org.osmf.net.NetLoader;

    public class HLSNetLoader extends NetLoader {
        private var _hls : HLS;
        private var _connection : NetConnection;
        private var _resource : URLResource;

        public function HLSNetLoader(hls : HLS) {
            _hls = hls;
            super();
        }

        override protected function createNetStream(connection : NetConnection, resource : URLResource) : NetStream {
            _connection = connection;
            _resource = resource;
            return _hls.stream;
        }
    }
}