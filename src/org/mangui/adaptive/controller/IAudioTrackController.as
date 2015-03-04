/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.adaptive.controller {

   import org.mangui.adaptive.model.AudioTrack;
   
    public interface IAudioTrackController {

        function set audioTrack(num : int) : void;

        function get audioTrack() : int;

        function get audioTracks() : Vector.<AudioTrack>;

        function audioTrackSelectionHandler(audioTrackList : Vector.<AudioTrack>) : AudioTrack;

		/* dispose method */
		function dispose() : void;
    }
}