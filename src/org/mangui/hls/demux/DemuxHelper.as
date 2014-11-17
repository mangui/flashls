package org.mangui.hls.demux {
    import flash.display.DisplayObject;
    import flash.utils.ByteArray;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
    public class DemuxHelper {
        public static function probe(data : ByteArray, displayObject : DisplayObject, audioselect : Function, progress : Function, complete : Function, videometadata : Function) : Demuxer {
            data.position = 0;
            CONFIG::LOGGING {
                Log.debug("probe fragment type");
            }
            if (AACDemuxer.probe(data) == true) {
                CONFIG::LOGGING {
                    Log.debug("AAC ES found");
                }
                return new AACDemuxer(audioselect, progress, complete);
            } else if (MP3Demuxer.probe(data) == true) {
                CONFIG::LOGGING {
                    Log.debug("MP3 ES found");
                }
                return new MP3Demuxer(audioselect, progress, complete);
            } else if (TSDemuxer.probe(data) == true) {
                CONFIG::LOGGING {
                    Log.debug("MPEG2-TS found");
                }
                return new TSDemuxer(displayObject, audioselect, progress, complete, videometadata);
            } else {
                CONFIG::LOGGING {
                    Log.debug("probe fails");
                }
                return null;
            }
        }
    }
}
