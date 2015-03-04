/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.adaptive {

    import flash.display.Stage;
    import flash.events.IEventDispatcher;
    import flash.net.NetStream;
    import flash.net.URLStream;
    import org.mangui.adaptive.model.AltAudioTrack;
    import org.mangui.adaptive.model.AudioTrack;
    import org.mangui.adaptive.model.Level;

    public interface Adaptive extends IEventDispatcher {

        /** Load and parse a new Adaptive URL **/
        function load(url : String) : void;

        /** Return the quality level used when starting a fresh playback **/
        function get startlevel() : int;

        /** Return the quality level used after a seek operation **/
        function get seeklevel() : int;

        /** Return the quality level of the currently played fragment **/
        function get playbacklevel() : int;

        /** Return the quality level of last loaded fragment **/
        function get level() : int;

        /*  set quality level for next loaded fragment (-1 for automatic level selection) */
        function set level(level : int) : void;

        /* check if we are in automatic level selection mode */
        function get autolevel() : Boolean;

        /* return manual level */
        function get manuallevel() : int;

        /** Return a Vector of quality level **/
        function get levels() : Vector.<Level>;

        /** Return the current playback position. **/
        function get position() : Number;

        /** Return the current playback state. **/
        function get playbackState() : String;

        /** Return the current seek state. **/
        function get seekState() : String;

        /** Return the type of stream (VOD/LIVE). **/
        function get type() : String;

        /** return NetStream **/
        function get stream() : NetStream;

        function get client() : Object;

        function set client(value : Object) : void;

        /** get current Buffer Length  **/
        function get bufferLength() : Number;

        /** get audio tracks list**/
        function get audioTracks() : Vector.<AudioTrack>;

        /** get alternate audio tracks list from playlist **/
        function get altAudioTracks() : Vector.<AltAudioTrack>;

        /** get index of the selected audio track (index in audio track lists) **/
        function get audioTrack() : int;

        /** select an audio track, based on its index in audio track lists**/
        function set audioTrack(val : int) : void;

        /* set stage */
        function set stage(stage : Stage) : void;

        /* get stage */
        function get stage() : Stage;

        /* set URL stream loader */
        function set URLstream(urlstream : Class) : void;

        /* retrieve URL stream loader */
        function get URLstream() : Class;

		/* dispose method */
		function dispose() : void;
    }
}