# flashls

An Open-source HLS Flash plugin that allows you to play HLS streams.

The plugin is compatible with the following players:

  - [Clappr](https://github.com/globocom/clappr) - a very easy open source player to use and to extend.
  - [Flowplayer Flash](#flowplayer) 3.2.12
  - [Flowplayer 6.x](https://flowplayer.org/news/)
  - [MediaElement.js][3] (integrated in MediaElement.js since 2.15.0)  
  - [OSMF 2.0](#strobe-media-playback-smp-and-other-osmf-based-players) based players (such as SMP and GrindPlayer)
  - [Video.js][1] 4.6, 4.7, 4.8 (adaptation done here [https://github.com/mangui/video-js-swf][2])

## Features

  - VoD & Live playlists
    - Sliding window (aka DVR) support on Live playlists
  - Adaptive streaming
    - Manual & Auto quality switching
    - 3 switching modes are available:
      - instant switching : playback will be paused, whole buffer will be flushed, and fragments matching with new quality level and current playback position will be fetched, then playback will resume.
      - smooth switching : buffer will be flushed on next fragment boundary, and fragments matching with new quality level and next fragment position will be fetched. this allows a smooth (and still fast) quality switch, usually without interrupting the playback.
      - bandwidth conservative switching : buffer will not be flushed, but next fragment to be buffered will use the newly selected quality level.
    - ABR algorithm : Serial segment fetching method from [Rate adaptation for dynamic adaptive streaming over HTTP in
content distribution network, Chenghao Liu,Imed Bouazizi, Miska M. Hannuksela,Moncef Gabbouj](docs/10.1.1.300.5957.pdf)
    - Emergency quality switch-down to avoid buffering in case of sudden bandwidth drop
  - Alternate Audio Track Rendition
    - Master Playlist with alternative Audio
  - Configurable seeking method on VoD & Live
    - Accurate seeking to exact requested position
    - Key frame based seeking (nearest key frame)
    - ability to seek in buffer and back buffer without redownloading segments
  - Timed Metadata for HTTP Live Streaming (in ID3 format, carried in MPEG2-TS, as defined in https://developer.apple.com/library/ios/documentation/AudioVideo/Conceptual/HTTP_Live_Streaming_Metadata_Spec/HTTP_Live_Streaming_Metadata_Spec.pdf)
  - AES-128 decryption
  - Buffer progress report
  - Error resilience
    - Retry mechanism on I/O errors
    - Recovery mechanism on badly segmented TS streams
    - Failover on [alternate redundant streams](https://developer.apple.com/library/ios/documentation/networkinginternet/conceptual/streamingmediaguide/UsingHTTPLiveStreaming/UsingHTTPLiveStreaming.html#//apple_ref/doc/uid/TP40008332-CH102-SW22)
  - frame drop detection
    -  if the device is not powerful enough to decode content, an event will be triggered.
  - max quality level selectable by auto switch algorithm could be capped
    - to player dimension
    - upon frame drop detection

### Supported M3U8 tags

  - `#EXTM3U`
  - `#EXTINF`
  - `#EXT-X-STREAM-INF` (Multiple bitrate)
  - `#EXT-X-ENDLIST` (VoD / Live playlist)
  - `#EXT-X-MEDIA-SEQUENCE`
  - `#EXT-X-TARGETDURATION`
  - `#EXT-X-DISCONTINUITY`
  - `#EXT-X-DISCONTINUITY-SEQUENCE`
  - `#EXT-X-PROGRAM-DATE-TIME` (optional, used to synchronize time-stamps and sequence number when switching from one level to another)
  - `#EXT-X-KEY` (AES-128 method supported only)
  - `#EXT-X-BYTERANGE`

## Configuration

The plugin accepts several **optional** configuration options, such as:

  - `hls_debug` (default false) - Toggle _debug_ traces, outputted on JS console
  - `hls_debug2` (default false) - Toggle _verbose debug_ traces, outputted on JS console
  - `hls_minbufferlength` (default -1) - Minimum buffer length in _seconds_ that needs to be reached before playback can start (after seeking) or restart (in case of empty buffer)
    - If set to `-1` some heuristics based on past metrics are used to define an accurate value that should prevent buffer to stall
  - `minBufferLengthCapping` (default -1) - minimum buffer length capping value (max value) if minBufferLength is set to -1
  - `hls_lowbufferlength` (default 3) - Low buffer threshold in _seconds_. When crossing down this threshold, HLS will switch to buffering state, usually the player will report this buffering state through a rotating icon. Playback will still continue.
  - `hls_maxbufferlength` (default 300) - Maximum buffer length in _seconds_ (0 means infinite buffering)
  - `hls_maxbackbufferlength` (default 30) - Maximum back buffer length in _seconds_ (0 means infinite back buffering). back buffer is seekable without redownloading segments.
  - `hls_startfrombitrate` (default -1)
   - If greater than 0, specifies the preferred bitrate to start with.
   - If -1, and hls_startfromlevel is not specified, automatic start level selection will be used.
   - This parameter, if set, will take priority over hls_startfromlevel.
  - `hls_startfromlevel` (default -1)
   - from 0 to 1 : indicates the "normalized" preferred bitrate. As such,
     - if 0, lowest non-audio bitrate is used,
     - if 1, highest bitrate is used,
     - if 0.5, the closest to the middle bitrate will be selected and used first.
   - -1 : automatic start level selection, playback will start from level matching download bandwidth (determined from download of first segment)
   - -2 : playback will start from the first level appearing in Manifest (regardless of its bitrate)
  - `hls_autoStartMaxDuration` (default -1) max fragment loading duration ( bw test + fragment loading) in automatic start level selection mode (in ms)
     - If -1 : max duration not capped
     - If greater than 0 : max duration is capped to given value. this will avoid long playback starting time. basically if set to 2000ms, and download bandwidth test took 1500ms, we only have 500ms left to load the proper fragment ... which is not enough ... this means that flashls will stick to level 0 in that case, even if download bandwidth would be enough to select an higher bitrate
  - `hls_seekfromlevel` (default -1) - If set to true, playback will start from lowest non-audio level after any seek operation. If set to false, playback will start from level used before seeking
   - from 0 to 1 : indicates the "normalized" preferred bitrate. As such,
     - if 0, lowest non-audio bitrate is used,
     - if 1, highest bitrate is used,
     - if 0.5, the closest to the middle bitrate will be selected and used first.
   - -1 : automatic seek level selection, keep level before seek.
  - `hls_flushliveurlcache` (default false) - If set to true, Live playlist will be flushed from URL cache before reloading (this is to workaround some cache issues with some combination of Flash Player / IE version)
  - `hls_initiallivemanifestsize` (default 1) - Number of segments needed to start playback of Live stream.
  - `hls_seekmode`
    - "ACCURATE" - Seek to exact position
    - "KEYFRAME" - Seek to last keyframe before requested position
  - `hls_manifestloadmaxretry` (default -1): max number of Manifest load retries after I/O Error.
    - if any I/O error is met during initial Manifest load, it will not be reloaded. an HLSError will be triggered immediately.
    - After initial load, any I/O error will trigger retries every 1s,2s,4s,8s (exponential, capped to 64s).  please note specific handling for these 2 values:
        - 0, means no retry, error message will be triggered automatically
        - -1 means infinite retry
  - `hls_keyloadmaxretry` (default -1): max number of key load retries after I/O Error.
    - any I/O error will trigger retries every 1s,2s,4s,8s (exponential, capped to 64s).  Please note specific handling for these 2 values:
        - 0, means no retry, error message will be triggered automatically
        - -1 means infinite retry
  - `hls_fragmentloadmaxretry` (default 4s): max number of Fragment load retries after I/O Error. 
    - Any I/O error will trigger retries every 1s,2s,4s,8s (exponential, capped to 64s). Please note specific handling for these 2 values:
        - 0, means no retry, error message will be triggered automatically
        - -1 means infinite retry
  - `hls_fragmentloadskipaftermaxretry` (default true): control behaviour in case fragment load still fails after max retry timeout
        - true : fragment will be skipped and next one will be loaded.
        - false : an I/O Error will be raised.
  - `hls_maxskippedfragments` (default 5): Maximum count of skipped fragments in a row before an I/O Error will be raised.
    - 0 - no skip (same as fragmentLoadSkipAfterMaxRetry = false).
    - -1 - no limit for skipping, skip till the end of the playlist.
  - `hls_capleveltostage` (default false) : limit levels usable in auto-quality by the stage dimensions (width and height)
    - true : level width and height (defined in m3u8 playlist) will be compared with the player width and height (stage.stageWidth and stage.stageHeight). Max level will be set depending on the `hls_maxlevelcappingmode` option. Note: this setting is ignored in manual mode so all the levels could be selected manually.
    - false : levels will not be limited. All available levels could be used in auto-quality mode taking only bandwidth into consideration.
  - `hls_maxlevelcappingmode` (default downscale) : defines the max level capping mode to the one available in HLSMaxLevelCappingMode:
    - "downscale" - max capped level should be the one with the dimensions equal or greater than the stage dimensions (so the video will be downscaled)
    - "upscale" - max capped level should be the one with the dimensions equal or lower than the stage dimensions (so the video will be upscaled)
  - `hls_usehardwarevideodecoder` (default true) : enable/disable hardware video decoding. disabling it could be useful to workaround hardware video decoding issues.
  - `hls_fpsdroppedmonitoringperiod` (default 5000ms) : dropped FPS Monitor Period in ms. period at which number of dropped FPS will be checked.
  - `hls_fpsdroppedmonitoringthreshold` (default 0.2) : every fpsDroppedMonitoringPeriod, dropped FPS will be compared to displayed FPS. if during that period, ratio of (dropped FPS/displayed FPS) is greater or equal than hls_fpsdroppedmonitoringthreshold, HLSEvent.FPS_DROP event will be fired.
  - `hls_caplevelonfpsdrop` (default true) : Limit levels usable in auto-quality when FPS drop is detected.i.e. if frame drop is detected on level 5, auto level will be capped to level 4. Note: this setting is ignored in manual mode so all the levels could be selected manually.
  - `hls_smoothautoswitchonfpsdrop` (default true) : force a smooth level switch Limit when FPS drop is detected in auto-quality. i.e. if frame drop is detected on level 5, it will trigger an auto quality level switch to level 4 for next fragment. Note: this setting is active only if capLevelonFPSDrop==true.
  - `hls_switchdownonlevelerror` (default true) : if level loading fails, and if in auto mode, and we are not on lowest level, don't report Level loading error straight-away, try to switch down first

## hls API
hls API and events are described [here](API.md)

## Examples :

* http://www.flashls.org/latest/examples/chromeless
* http://www.flashls.org/latest/examples/osmf/GrindPlayer.html
* http://www.flashls.org/latest/examples/osmf/StrobeMediaPlayback.html
* http://www.flashls.org/latest/examples/flowplayer/index.html
* http://www.flashls.org/mediaelement/demo/mediaelementplayer-hls.html
* http://www.flashls.org/videojs/flash_demo.html



## Usage

  - Download flashls from https://github.com/mangui/flashls/releases
  - Unzip, extract and upload the appropiate version to your server
  - In the `examples` directory you will find examples for ChromelessPlayer, Flowplayer, Strobe Media Playback (SMP) and GrindPlayer

### Setup
---


#### Flowplayer

FlowPlayer/flashls setup is described here : http://flash.flowplayer.org/plugins/streaming/flashls.html
please also refer to example below if you want to use specific configuration options:


```javascript
flowplayer("player", 'http://releases.flowplayer.org/swf/flowplayer-3.2.12.swf', {
  // Flowplayer configuration options
  // ...
  plugins: {
    httpstreaming: {
      // flashls configuration options
      url: 'flashlsFlowPlayer.swf',
      hls_debug: false,
      hls_debug2: false,
      hls_lowbufferlength: 3,
      hls_minbufferlength: 8,
      hls_maxbufferlength: 60,
      hls_startfromlowestlevel: false,
      hls_seekfromlowestlevel: false,
      hls_live_flushurlcache: false,
      hls_seekmode: 'ACCURATE',
      hls_capleveltostage: false,
      hls_maxlevelcappingmode: 'downscale'
    }
  }
});
```
---

#### Strobe Media Playback (SMP) and other OSMF based players

```javascript
var playerOptions = {
  // Strobe Media Playback configuration options
  // ...
  source: 'http://example.com/stream.m3u8',
  // flashls configuration options
  plugin_hls: "flashlsOSMF.swf",
  hls_debug: false,
  hls_debug2: false,
  hls_minbufferlength: -1,
  hls_lowbufferlength: 2,
  hls_maxbufferlength: 60,
  hls_startfromlowestlevel: false,
  hls_seekfromlowestlevel: false,
  hls_live_flushurlcache: false,
  hls_seekmode: 'ACCURATE',
  hls_capleveltostage: false,
  hls_maxlevelcappingmode: 'downscale'
};

swfobject.embedSWF('StrobeMediaPlayback.swf', 'player', 640, 360, '10.2', null, playerOptions, {
  allowFullScreen: true,
  allowScriptAccess: 'always',
  bgColor: '#000000',
  wmode: 'opaque'
}, {
  name: 'player'
});
```

### Project branches
---

  * The [master][] branch holds the most recent minor release.
  * Most development work happens on the [dev][] branch.
  * Additional development branches may be established for major features.

[master]: https://github.com/mangui/flashls/tree/master
[dev]: https://github.com/mangui/flashls/tree/dev


### Building
---

Run `FLEXPATH=/path/to/flex/sdk sh ./build.sh` inside the `build` directory

`FLEXPATH` should point to your Flex SDK location (i.e. /opt/local/flex/4.6)

After a successful build you will find fresh binaries in the `bin/debug` and `bin/release` directories

## License

  - [MPL 2.0](https://github.com/mangui/flashls/blob/master/LICENSE)


## they use flashls in production !


|Logo|Company|
|:-:|:-:|
|<img src="https://s3.amazonaws.com/BURC_Pages/downloads/a-smile_color.jpg" width="80">   |   [Amazon](http://www.amazon.com)|
|<img src="https://bitdash-a.akamaihd.net/webpages/bitmovin-logo.png" width="160">   |[Bitmovin](http://www.bitmovin.com)|
|<img src="http://press.dailymotion.com/fr/wp-content/uploads/sites/4/2010/06/LOGO-PRESS-BLOG.png" width="80">   |[Dailymotion](http://www.dailymotion.com)|
|<img src="https://flowplayer.org/media/img/logo-blue.png" width="160">  |[FlowPlayer](http://www.flowplayer.org/)|
|<img src="https://cloud.githubusercontent.com/assets/244265/12556435/dfaceb48-c353-11e5-971b-2c4429725469.png" width="160">  |[globo.com](https://www.globo.com)|
|<img src="https://cloud.githubusercontent.com/assets/244265/12556385/999aa884-c353-11e5-9102-79df54384498.png" width="160">  |[The New York Times](https://www.nytimes.com)|
|<img src="https://www.radiantmediaplayer.com/images/radiantmediaplayer-new-logo-640.jpg" width="160">  |[Radiant Media Player](https://www.radiantmediaplayer.com/)|
|<img src="http://tidal.com/images/tidal-large-black.c8af31d9.png" width="160">  |[Tidal](https://listen.tidal.com/)|
|<img src="https://www.ubicast.eu/static/website/img/header/logo_ubicast.svg" width="160">  |[Ubicast](https://www.ubicast.eu)|

## Donation

If you'd like to support future development and new product features, please make a donation via PayPal. These donations are used to cover my ongoing expenses - web hosting, domain registrations, and software and hardware purchases.

[![Donate](https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=463RB2ALVXJLA)

---

  [1]: http://www.videojs.com
  [2]: https://github.com/mangui/video-js-swf
  [3]: http://mediaelementjs.com
