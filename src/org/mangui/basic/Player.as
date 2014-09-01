package org.mangui.basic {
    import org.mangui.hls.HLS;
    import org.mangui.hls.event.HLSEvent;

    import flash.display.Sprite;
    import flash.media.Video;


    public class Player extends Sprite {
        private var hls : HLS = null;
        private var video : Video = null;

        public function Player() {
            hls = new HLS();

            video = new Video(640, 480);
            addChild(video);
            video.x = 0;
            video.y = 0;
            video.smoothing = true;
            video.attachNetStream(hls.stream);
            hls.addEventListener(HLSEvent.MANIFEST_LOADED, manifestHandler);
            hls.load("http://domain.com/hls/m1.m3u8");
        }

        public function manifestHandler(event : HLSEvent) : void {
            hls.stream.play();
        };
    }
}
