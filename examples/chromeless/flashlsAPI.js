var flashlsAPI = function(flashObject) {

	this.constructor = function(flashObject) {
		this.flashObject = flashObject;
	}
	this.constructor(flashObject);

	this.load = function(url) {
    this.flashObject.playerLoad(url);
	}

	this.play = function(offset) {
    this.flashObject.playerPlay(offset);
	}

	this.pause = function() {
    this.flashObject.playerPause();
	}

	this.resume = function() {
    this.flashObject.playerResume();
	}

	this.seek = function(offset) {
    this.flashObject.playerSeek(offset);
	}

	this.stop = function() {
    this.flashObject.playerStop();
	}

	this.volume = function(volume) {
    this.flashObject.playerVolume(volume);
	}

	this.setCurrentLevel = function(level) {
    this.flashObject.playerSetCurrentLevel(level);
	}

	this.setNextLevel = function(level) {
    this.flashObject.playerSetNextLevel(level);
	}

	this.setLoadLevel = function(level) {
    this.flashObject.playerSetLoadLevel(level);
	}

	this.setMaxBufferLength = function(len) {
    this.flashObject.playerSetmaxBufferLength(len);
	}

	this.getPosition = function() {
		return this.flashObject.getPosition();
	}

	this.getDuration = function() {
		return this.flashObject.getDuration();
	}

	this.getbufferLength = function() {
		return this.flashObject.getbufferLength();
	}

	this.getbackBufferLength = function() {
		return this.flashObject.getbackBufferLength();
	}

	this.getLowBufferLength = function() {
		return this.flashObject.getlowBufferLength();
	}

	this.getMinBufferLength = function() {
		return this.flashObject.getminBufferLength();
	}

	this.getMaxBufferLength = function() {
		return this.flashObject.getmaxBufferLength();
	}

	this.getLevels = function() {
		return this.flashObject.getLevels();
	}

	this.getAutoLevel = function() {
		return this.flashObject.getAutoLevel();
	}

	this.getCurrentLevel = function() {
		return this.flashObject.getCurrentLevel();
	}

	this.getNextLevel = function() {
		return this.flashObject.getNextLevel();
	}

	this.getLoadLevel = function() {
		return this.flashObject.getLoadLevel();
	}

	this.getAudioTrackList = function() {
		return this.flashObject.getAudioTrackList();
	}

	this.getStats = function() {
		return this.flashObject.getStats();
	}

	this.setAudioTrack = function(trackId) {
    	this.flashObject.playerSetAudioTrack(trackId);
	}

	this.playerSetLogDebug = function(state) {
    	this.flashObject.playerSetLogDebug(state);
	}

	this.getLogDebug = function() {
		return this.flashObject.getLogDebug();
	}

	this.playerSetLogDebug2 = function(state) {
    	this.flashObject.playerSetLogDebug2(state);
	}

	this.getLogDebug2 = function() {
		return this.flashObject.getLogDebug2();
	}

	this.playerSetUseHardwareVideoDecoder = function(state) {
    	this.flashObject.playerSetUseHardwareVideoDecoder(state);
	}

	this.getUseHardwareVideoDecoder = function() {
		return this.flashObject.getUseHardwareVideoDecoder();
	}

	this.playerSetflushLiveURLCache = function(state) {
    	this.flashObject.playerSetflushLiveURLCache(state);
	}

	this.getflushLiveURLCache = function() {
		return this.flashObject.getflushLiveURLCache();
	}

	this.playerSetJSURLStream = function(state) {
    	this.flashObject.playerSetJSURLStream(state);
	}

	this.getJSURLStream = function() {
		return this.flashObject.getJSURLStream();
	}

	this.playerCapLeveltoStage = function(state) {
    	this.flashObject.playerCapLeveltoStage(state);
	}

	this.getCapLeveltoStage = function() {
		return this.flashObject.getCapLeveltoStage();
	}

	this.playerSetAutoLevelCapping = function(level) {
    	this.flashObject.playerSetAutoLevelCapping(level);
	}

	this.getAutoLevelCapping = function() {
		return this.flashObject.getAutoLevelCapping();
	}

}

