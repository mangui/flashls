/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.hls {
    import org.mangui.hls.model.AudioTrack;

    import flash.display.Stage;
    import flash.net.NetConnection;
    import flash.net.NetStream;
    import flash.net.URLStream;
    import flash.events.EventDispatcher;
    import flash.events.Event;

    import org.mangui.hls.model.Level;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.playlist.AltAudioTrack;
    import org.mangui.hls.loader.ManifestLoader;
    import org.mangui.hls.controller.AudioTrackController;
    import org.mangui.hls.loader.FragmentLoader;
    import org.mangui.hls.stream.HLSNetStream;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
    /** Class that manages the streaming process. **/
    public class HLS extends EventDispatcher {
        private var _fragmentLoader : FragmentLoader;
        private var _manifestLoader : ManifestLoader;
        private var _audioTrackController : AudioTrackController;
        /** HLS NetStream **/
        private var _hlsNetStream : HLSNetStream;
        /** HLS URLStream **/
        private var _hlsURLStream : Class;
        private var _client : Object = {};
        private var _stage : Stage;

        /** Create and connect all components. **/
        public function HLS() {
            var connection : NetConnection = new NetConnection();
            connection.connect(null);
            _manifestLoader = new ManifestLoader(this);
            _audioTrackController = new AudioTrackController(this);
            _hlsURLStream = URLStream as Class;
            // default loader
            _fragmentLoader = new FragmentLoader(this, _audioTrackController);
            _hlsNetStream = new HLSNetStream(connection, this, _fragmentLoader);
        };

        /** Forward internal errors. **/
        override public function dispatchEvent(event : Event) : Boolean {
            if (event.type == HLSEvent.ERROR) {
                CONFIG::LOGGING {
                    Log.error((event as HLSEvent).error);
                }
                _hlsNetStream.close();
            }
            return super.dispatchEvent(event);
        };

        public function dispose() : void {
            _fragmentLoader.dispose();
            _manifestLoader.dispose();
            _audioTrackController.dispose();
            _hlsNetStream.dispose_();
            _fragmentLoader = null;
            _manifestLoader = null;
            _audioTrackController = null;
            _hlsNetStream = null;
            _client = null;
            _stage = null;
            _hlsNetStream = null;
        }

        /** Return the quality level used when starting a fresh playback **/
        public function get startlevel() : int {
            return _manifestLoader.startlevel;
        };

        /** Return the quality level used after a seek operation **/
        public function get seeklevel() : int {
            return _manifestLoader.seeklevel;
        };

        /** Return the quality level of the currently played fragment **/
        public function get playbacklevel() : int {
            return _hlsNetStream.playbackLevel;
        };

        /** Return the quality level of last loaded fragment **/
        public function get level() : int {
            return _fragmentLoader.level;
        };

        /*  set quality level for next loaded fragment (-1 for automatic level selection) */
        public function set level(level : int) : void {
            _fragmentLoader.level = level;
        };

        /* check if we are in automatic level selection mode */
        public function get autolevel() : Boolean {
            return _fragmentLoader.autolevel;
        };

        /** Return a Vector of quality level **/
        public function get levels() : Vector.<Level> {
            return _manifestLoader.levels;
        };

        /** Return the current playback position. **/
        public function get position() : Number {
            return _hlsNetStream.position;
        };

        /** Return the current playback state. **/
        public function get playbackState() : String {
            return _hlsNetStream.playbackState;
        };

        /** Return the current seek state. **/
        public function get seekState() : String {
            return _hlsNetStream.seekState;
        };

        /** Return the type of stream (VOD/LIVE). **/
        public function get type() : String {
            return _manifestLoader.type;
        };

        /** Load and parse a new HLS URL **/
        public function load(url : String) : void {
            _hlsNetStream.close();
            _manifestLoader.load(url);
        };

        /** return HLS NetStream **/
        public function get stream() : NetStream {
            return _hlsNetStream;
        }

        public function get client() : Object {
            return _client;
        }

        public function set client(value : Object) : void {
            _client = value;
        }

        /** get current Buffer Length  **/
        public function get bufferLength() : Number {
            return _hlsNetStream.bufferLength;
        };

        /** get audio tracks list**/
        public function get audioTracks() : Vector.<AudioTrack> {
            return _audioTrackController.audioTracks;
        };

        /** get alternate audio tracks list from playlist **/
        public function get altAudioTracks() : Vector.<AltAudioTrack> {
            return _manifestLoader.altAudioTracks;
        };

        /** get index of the selected audio track (index in audio track lists) **/
        public function get audioTrack() : int {
            return _audioTrackController.audioTrack;
        };

        /** select an audio track, based on its index in audio track lists**/
        public function set audioTrack(val : int) : void {
            _audioTrackController.audioTrack = val;
        }

        /* set stage */
        public function set stage(stage : Stage) : void {
            _stage = stage;
        }

        /* get stage */
        public function get stage() : Stage {
            return _stage;
        }

        /* set URL stream loader */
        public function set URLstream(urlstream : Class) : void {
            _hlsURLStream = urlstream;
        }

        /* retrieve URL stream loader */
        public function get URLstream() : Class {
            return _hlsURLStream;
        }
    }
    ;
}