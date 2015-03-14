/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.adaptive.loader {
    import org.mangui.adaptive.model.AltAudioTrack;
    import org.mangui.adaptive.model.Level;

    public interface ILevelLoader {
        function load(url:String) : void;

        function get levels() : Vector.<Level>;

        /** Return the stream type. **/
        function get type() : String;

        function get altAudioTracks() : Vector.<AltAudioTrack>;

        /* dispose method */
        function dispose() : void;        
    }
}