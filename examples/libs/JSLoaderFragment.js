var JSLoaderFragment = {

  requestFragment : function(instanceId,url, resourceLoadedFlashCallback, resourceFailureFlashCallback) {
    //console.log("JSURLStream.onRequestResource");
    if(!this.flashObject) {
      this.flashObject = getFlashMovieObject(instanceId);
    }
    this.xhrGET(url,this.xhrReadBytes, this.xhrTransferFailed, resourceLoadedFlashCallback, resourceFailureFlashCallback, "arraybuffer");
  },
  abortFragment : function(instanceId) {
    if(this.xhr &&this.xhr.readyState !== 4) {
      console.log("JSLoaderFragment:abort XHR");
      this.xhr.abort();
    }
  },
  xhrGET : function (url,loadcallback, errorcallback,resourceLoadedFlashCallback, resourceFailureFlashCallback, responseType) {
    var xhr = new XMLHttpRequest();
    this.xhr = xhr;
    xhr.binding = this;
    xhr.resourceLoadedFlashCallback = resourceLoadedFlashCallback;
    xhr.resourceFailureFlashCallback = resourceFailureFlashCallback;
    xhr.open("GET", url, loadcallback? true: false);
    if (responseType) {
      xhr.responseType = responseType;
    }
    if (loadcallback) {
      xhr.onload = loadcallback;
      xhr.onerror= errorcallback;
      xhr.send();
    } else {
      xhr.send();
      return xhr.status == 200? xhr.response: "";
    }
  },
  xhrReadBytes : function(event) {
    //console.log("fragment loaded");
    var len = event.currentTarget.response.byteLength;
    var t0 = new Date();
    var res = base64ArrayBuffer(event.currentTarget.response);
    var t1 = new Date();
    this.binding.flashObject[this.resourceLoadedFlashCallback](res,len);
    var t2 = new Date();
    console.log('encoding/toFlash:' + (t1-t0) + '/' + (t2-t1));
    console.log('encoding speed/toFlash:' + Math.round(len/(t1-t0)) + 'kB/s/' + Math.round(res.length/(t2-t1)) + 'kB/s');
  },
  xhrTransferFailed : function(oEvent) {
    console.log("An error occurred while transferring the file :" + oEvent.target.status);
    this.binding.flashObject[this.resourceFailureFlashCallback](res);
  }
}
