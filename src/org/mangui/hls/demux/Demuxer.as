package org.mangui.hls.demux {
    import flash.utils.ByteArray;

    public interface Demuxer {
        function append(data : ByteArray) : void;

        function notifycomplete() : void;

        function cancel() : void;

        function  audio_expected() : Boolean;

        function  video_expected() : Boolean;
    }
}
