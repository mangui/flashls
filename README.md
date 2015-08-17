# flashls

An Open-source HLS Flash plugin that allows you to play HLS streams.

The plugin is compatible with the following players:

  - [Flowplayer](#flowplayer) 3.2.12
  - [OSMF 2.0](#strobe-media-playback-smp-and-other-osmf-based-players) based players (such as SMP and GrindPlayer)
  - [Video.js][1] 4.6, 4.7, 4.8 (adaptation done here [https://github.com/mangui/video-js-swf][2])
  - [MediaElement.js][3] (adaptation done here [https://github.com/mangui/mediaelement][4], now integrated in official MediaElement.js release since 2.15.0)

## Features

  - VoD & Live playlists
    - Sliding window (aka DVR) support on Live playlists
  - Adaptive streaming
    - Manual & Auto switching
    - Serial segment fetching method from http://www.cs.tut.fi/~moncef/publications/rate-adaptation-IC-2011.pdf
  - Configurable seeking method on VoD & Live
    - Accurate seeking to exact requested position
    - Key frame based seeking (nearest key frame)
    - Segment based seeking (beginning of segment)
  - Timed Metadata for HTTP Live Streaming (in ID3 format, carried in MPEG2-TS, as defined in https://developer.apple.com/library/ios/documentation/AudioVideo/Conceptual/HTTP_Live_Streaming_Metadata_Spec/HTTP_Live_Streaming_Metadata_Spec.pdf)
  - AES-128 decryption
  - Buffer progress report
  - Error resilience
    - Retry mechanism on I/O errors 
    - Recovery mechanism on badly segmented TS streams

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
  - `hls_lowbufferlength` (default 3) - Low buffer threshold in _seconds_. When crossing down this threshold, HLS will switch to buffering state, usually the player will report this buffering state through a rotating icon. Playback will still continue.
  - `hls_maxbufferlength` (default 60) - Maximum buffer length in _seconds_ (0 means infinite buffering)
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
  - `hls_seekfromlevel` (default -1) - If set to true, playback will start from lowest non-audio level after any seek operation. If set to false, playback will start from level used before seeking
   - from 0 to 1 : indicates the "normalized" preferred bitrate. As such,
     - if 0, lowest non-audio bitrate is used,
     - if 1, highest bitrate is used,
     - if 0.5, the closest to the middle bitrate will be selected and used first.
   - -1 : automatic seek level selection, keep level before seek.   
  - `hls_live_flushurlcache` (default false) - If set to true, Live playlist will be flushed from URL cache before reloading (this is to workaround some cache issues with some combination of Flash Player / IE version)
  - `hls_seekmode` (default: "KEYFRAME")
    - "ACCURATE" - Seek to exact position
    - "KEYFRAME" - Seek to last keyframe before requested position
    - "SEGMENT" - Seek to beginning of segment containing requested position
  - `hls_manifestloadmaxretry` (default -1): max number of Manifest load retries after I/O Error.
    - if any I/O error is met during initial Manifest load, it will not be reloaded. an HLSError will be triggered immediately.
    - After initial load, any I/O error will trigger retries every 1s,2s,4s,8s (exponential, capped to 64s).  please note specific handling for these 2 values :
        - 0, means no retry, error message will be triggered automatically
        - -1 means infinite retry
  - `hls_keyloadmaxretry` (default -1): max number of key load retries after I/O Error.
      * any I/O error will trigger retries every 1s,2s,4s,8s (exponential, capped to 64s).  please note specific handling for these 2 values :
          * 0, means no retry, error message will be triggered automatically
          * -1 means infinite retry
  - `hls_fragmentloadmaxretry` (default -1): max number of Fragment load retries after I/O Error.
      * any I/O error will trigger retries every 1s,2s,4s,8s (exponential, capped to 64s).  please note specific handling for these 2 values :
          * 0, means no retry, error message will be triggered automatically
          * -1 means infinite retry
  - `hls_capleveltostage` (default false) : limit levels usable in auto-quality by the stage dimensions (width and height)
    - true : level width and height (defined in m3u8 playlist) will be compared with the player width and height (stage.stageWidth and stage.stageHeight). Max level will be set depending on the `hls_maxlevelcappingmode` option. Note: this setting is ignored in manual mode so all the levels could be selected manually.
    - false : levels will not be limited. All available levels could be used in auto-quality mode taking only bandwidth into consideration.
  - `hls_maxlevelcappingmode` (default downscale) : defines the max level capping mode to the one available in HLSMaxLevelCappingMode:
    - "downscale" - max capped level should be the one with the dimensions equal or greater than the stage dimensions (so the video will be downscaled)
    - "upscale" - max capped level should be the one with the dimensions equal or lower than the stage dimensions (so the video will be upscaled)
  - `hls_usehardwarevideodecoder` (default true) : enable/disable hardware video decoding. it could be useful to workaround hardware video decoding issues.


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

---

#### VideoJS

VideoJS/flashls setup is described here : https://github.com/tommyh/videojs-flashls


### Building
---

Run `FLEXPATH=/path/to/flex/sdk sh ./build.sh` inside the `build` directory

`FLEXPATH` should point to your Flex SDK location (i.e. /opt/local/flex/4.6)

After a successful build you will find fresh binaries in the `bin/debug` and `bin/release` directories

## License

  - [MPL 2.0](https://github.com/mangui/flashls/blob/master/LICENSE)

## Donation

If you'd like to support future development and new product features, please make a donation via PayPal. These donations are used to cover my ongoing expenses - web hosting, domain registrations, and software and hardware purchases.

[![Donate](https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=463RB2ALVXJLA)

---

[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/mangui/flashls/trend.png)](https://bitdeli.com/free "Bitdeli Badge")


  [1]: http://www.videojs.com
  [2]: https://github.com/mangui/video-js-swf
  [3]: http://mediaelementjs.com
  [4]: https://github.com/mangui/mediaelement