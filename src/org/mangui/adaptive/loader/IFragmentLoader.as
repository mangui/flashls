/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.adaptive.loader {


	import org.mangui.adaptive.stream.StreamBuffer;

    public interface IFragmentLoader {
    	function attachStreamBuffer(streamBuffer : StreamBuffer) : void;
		/* dispose method */
		function dispose() : void;

		function get audio_expected() : Boolean;

		function get video_expected() : Boolean;

		function stop() : void;

		function seek(position : Number) : void;

    }
}