/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.dash.loader {

    import org.mangui.adaptive.Adaptive;
    import org.mangui.adaptive.loader.IFragmentLoader;
    import org.mangui.adaptive.stream.StreamBuffer;


	public class AudioFragmentLoader implements IFragmentLoader {

		private var _adaptive : Adaptive;
        private var _streamBuffer : StreamBuffer;

        public function AudioFragmentLoader(adaptive : Adaptive) : void {
            _adaptive = adaptive;
        };


        public function attachStreamBuffer(streamBuffer : StreamBuffer) : void {
            _streamBuffer = streamBuffer;
        }

        public function get audio_expected() : Boolean {
        	return true;
        }

        public function get video_expected() : Boolean {
        	return false;
        }

        public function stop() : void {
        	return;
        }

        public function seek(position : Number) : void {

        }

        /* dispose method */
        public function dispose() : void {

        }
	}
}