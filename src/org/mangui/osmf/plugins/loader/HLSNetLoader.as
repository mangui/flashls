package org.mangui.osmf.plugins.loader {
    import flash.net.NetStream;
    import flash.net.NetConnection;

    import org.osmf.net.NetLoader;
    import org.osmf.media.URLResource;
    import org.mangui.hls.HLS;

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