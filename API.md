## creating an HLS instance

first thing you need to do to integrate HLS playback into your application is to instanciate an HLS object, that will be used as entry point to interact with flashls.

see example below

```as3
	import org.mangui.hls.HLS;
    import flash.media.Video;

	// create instance
	var hls : HLS = new HLS();
	// setting stage
	hls.stage = this.stage;
	// creating video (or StageVideo)
	video = new Video(640,480);
    video.x = 0;
    video.y = 0;
    video.smoothing = true;
    video.attachNetStream(hls.stream);
```
you can also refer to [Basic] (src/org/mangui/basic/Player.as) or [Chromeless](src/org/mangui/chromeless/ChromelessPlayer.as) players source code to get inspiration and see how to deal with StageVideo for example.

## Loading a m3u8 manifest

loading is peformed asynchronously.
below API should be used

```as3
hls.load(url)
```
flashls will fire below upon completion of manifest loading:

```as3
HLSEvent.MANIFEST_PARSED
HLSEvent.MANIFEST_LOADED
```
see [events below](##Events)

## retrieving playlist type

```as3
	hls.type (VOD/LIVE)
```

## controlling playback

playback control should be performed through a [flash.net.NetStream](http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/flash/net/NetStream.html) instance, which can be retrieved using hls.stream getter


```as3
	hls.stream.play(null, -1);
	hls.stream.seek(50);
	hls.stream.pause();
	hls.stream.resume();
	...

```

## retrieving/monitoring player state

### playback state

there are 2 ways to retrieve playback state :

  - synchronously, using a getter
```as3
	hls.playbackState (IDLE/PLAYING/PAUSED/PLAYING_BUFFERING/PAUSED_BUFFERING)
```
  - asynchronously

by monitoring the below event, that will be triggered for every playback state change.
```as3
HLSEvent.PLAYBACK_STATE
```

### seek state

there are 2 ways to retrieve seek state :

  - synchronously, using a getter
```as3
	hls.seekState (IDLE/SEEKING/SEEKED)
```
  - asynchronously

by monitoring the below event, that will be triggered for every seek state change.
```as3
HLSEvent.SEEK_STATE
```

## Controlling Quality Switch

by default flashls handles quality switch automatically, using heuristics.
It is however also possible to manually control quality swith using below API:


#### hls.levels
return array of available quality levels

#### hls.firstLevel

get :  first level index (index of first level appearing in Manifest. it is usually defined as start level hint for player)

#### hls.startLevel

get/set :  start level index (level of first fragment that will be played back)

  - if not overrided by user : first level appearing in manifest will be used as start level.
  -  if -1 : automatic start level selection, playback will start from level matching download bandwidth (determined from download of first segment)

default value is firstLevel

#### hls.seekLevel
get : return quality level used to load first fragment after a seek operation

#### hls.currentLevel
get : return current playback quality level

set : trigger an immediate quality level switch to new quality level. this will pause the video if it was playing, flush the whole buffer, and fetch fragment matching with current position and requested quality level. then resume the video if needed once fetched fragment will have been buffered.
set to -1 for automatic level selection

#### hls.nextLevel
get : return next playback quality level (playback quality level for next buffered fragment). return -1 if next fragment not buffered yet

set : trigger a quality level switch for next fragment. this could eventually flush already buffered next fragment
set to -1 for automatic level selection

#### hls.loadLevel
get : return last loaded fragment quality level.

set : set quality level for next loaded fragment
set to -1 for automatic level selection


#### hls.autoLevel
getter : tell whether auto level selection is enabled or not

#### hls.autoLevelCapping
get/set : capping/max level value that could be used by automatic level selection algorithm

default value is -1 (no level capping)


#### hls.stats
get : return playback session stats

```js
{
  tech : 'flashls',
  levelNb : total nb of quality level referenced in Manifest
  levelStart : first quality level experienced by End User
  autoLevelMin : min quality level experienced by End User (in auto mode)
  autoLevelMax : max quality level experienced by End User (in auto mode)
  autoLevelAvg : avg quality level experienced by End User (in auto mode)
  autoLevelLast : last quality level experienced by End User (in auto mode)
  autoLevelSwitch : nb of quality level switch in auto mode
  autoLevelCappingMin : min auto quality level capping value
  autoLevelCappingMax : max auto quality level capping value
  autoLevelCappingLast : last auto quality level capping value
  manualLevelMin : min quality level experienced by End User (in manual mode)
  manualLevelMax : max quality level experienced by End User (in manual mode)
  manualLevelLast : last quality level experienced by End User (in manual mode)
  manualLevelSwitch : nb of quality level switch in manual mode
  fragLastKbps : last fragment load bandwidth  
  fragMinKbps : min fragment load bandwidth
  fragMaxKbps : max fragment load bandwidth
  fragAvgKbps : avg fragment load bandwidth
  fragLastLatency : last fragment load latency
  fragMinLatency : min fragment load latency
  fragMaxLatency : max fragment load latency
  fragAvgLatency : avg fragment load latency
  fragBuffered : total nb of buffered fragments
  fragBufferedBytes : total nb of buffered bytes
  fragSkipped : total nb of skipped fragments
  fragChangedAuto : nb of frag played (loaded in auto mode)
  fragChangedManual : nb of frag played (loaded in manual mode)
}
```

#### ```hls.startLoad()```
start/restart playlist/fragment loading. this is only effective if MANIFEST_PARSED event has been triggered

##Events

flashls fires a bunch of events, that could be registered as highlighted below:

```as3
	hls.addEventListener(HLSEvent.MANIFEST_LOADED, _manifestLoadedHandler);


	private function _manifestLoadedHandler(event : HLSEvent) : void {
         var duration : Number = event.levels[_hls.startLevel].duration;
    };

```
full list of Events is described below :

  - `HLSEvent.MANIFEST_LOADING`  - triggered when a manifest starts loading, triggered after a call to hls.load(url)
  	-  data: {url : manifest URL}
  - `HLSEvent.MANIFEST_PARSED`  - triggered after main manifest has been retrieved and parsed. playlist may not be playable yet, in case of adaptive streaming, start level playlist is not downloaded yet at that stage
  	-  data: { levels : array of quality level object }
  - `HLSEvent.MANIFEST_LOADED`  - when this event is received, main manifest and start level has been retrieved (playlist duration is available)
  	-  data: { levels : array of quality level object }
  - `HLSEvent.LEVEL_LOADING`  - triggered when a quality level starts loading
  	-  data: { level : level index}
  - `HLSEvent.LEVEL_LOADED`  - triggered when a quality level has been successfully loaded
  	-  data: { loadMetrics : HLSLoadMetrics }
  - `HLSEvent.LEVEL_SWITCH`  - triggered when a loading quality switch occurs (quality of next loaded fragment is switching. which is different from playback quality switch)
  	-  data: { level : level index}
  - `HLSEvent.LEVEL_ENDLIST`  - triggered when a live playlist is ended (i.e. a #EXT-X-ENDLIST tag is appearing)
  	-  data: none
  - `HLSEvent.FRAGMENT_LOADING`  - triggered when a fragment loading starts
  	-  data: {url : manifest URL}
  - `HLSEvent.FRAGMENT_LOADED`  - triggered after a fragment has been succesfully loaded
  	-  data: { loadMetrics : HLSLoadMetrics }
  - `HLSEvent.FRAGMENT_LOAD_EMERGENCY_ABORTED`  - triggered when fragment loading is aborted because of a sudden bandwidth drop
    -  data: { loadMetrics : HLSLoadMetrics }
  - `HLSEvent.FRAGMENT_PLAYING`  - triggered when playback switches to a new fragment
  	-  data: { playMetrics : HLSPlayMetrics }
  - `HLSEvent.FRAGMENT_SKIPPED`  - triggered when a fragment has been skipped because of fragment load I/O error
    -  data: { duration : skipped fragment duration }
  - `HLSEvent.AUDIO_TRACKS_LIST_CHANGE`  - triggered when available audio tracks list changes
  	-  data: none
  - `HLSEvent.AUDIO_TRACK_SWITCH`  - triggered when switching to a different audio track
  	-  data: none
  - `HLSEvent.AUDIO_LEVEL_LOADING`  - triggered when an alternate audio rendition playlist starts loading
  	-  data: { level : alternate audio track index}
  - `HLSEvent.AUDIO_LEVEL_LOADED`  - triggered when an alternate audio rendition playlist has been successfully loaded
  	-  data: { loadMetrics : HLSLoadMetrics }
  - `HLSEvent.TAGS_LOADED`  - triggered when FLV tags have been demultiplexed from loaded fragments
  	-  data: { loadMetrics : HLSLoadMetrics }
  - `HLSEvent.LAST_VOD_FRAGMENT_LOADED`  - triggered when last fragment of a VoD playlist has been successfully loaded
  	-  data: none
  - `HLSEvent.ERROR`  - triggered when any error occurs
  	-  data: { error : HLSError}
  - `HLSEvent.MEDIA_TIME`  - triggered when media position gets updated
  	-  data: { mediatime : HLSMediatime}
  - `HLSEvent.PLAYBACK_STATE`  - triggered when playback state gets changed
  	-  data: { state : HLSPlayStates}
  - `HLSEvent.SEEK_STATE`  - triggered when seek state gets changed
  	-  data: { state : HLSSeekStates}
  - `HLSEvent.PLAYBACK_COMPLETE`  - triggered when playback is completed (reach end of playback)
  	-  data: none
  - `HLSEvent.PLAYLIST_DURATION_UPDATED` - triggered when playlist duration changes
  	-  data: { duration : new duration}
  - `HLSEvent.ID3_UPDATED` - triggered when new ID3 tag is available (fired during playback at the right playback timestamp)
  	-  data: { ID3Data : Hex String of ID3 representation }
  - `HLSEvent.STAGE_SET` - triggered when Stage object has been attached to hls instance
    -  data: none
  - `HLSEvent.FPS_DROP` - triggered when FPS drop in last monitoring period is higher than given threshold
    -  data: { level : current playback quality level}
  - `HLSEvent.FPS_DROP_LEVEL_CAPPING` - triggered when FPS drop triggers auto level capping
    -  data: { level : max autolevel }
  - `HLSEvent.FPS_DROP_SMOOTH_LEVEL_SWITCH` - triggered when FPS drop triggers a smooth auto level down switching
    -  data: none
  - `HLSEvent.LIVE_LOADING_STALLED` - triggered when fragment loading stalls when playing back live content
    -  data: none
