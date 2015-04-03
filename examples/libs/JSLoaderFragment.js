var JSLoaderFragment = {

  onRequestResource : function(instanceId,url, resourceLoadedFlashCallback, resourceFailureFlashCallback) {
    //console.log("JSURLStream.onRequestResource");
    if(!this.flashObject) {
      this.flashObject = getFlashMovieObject(instanceId);
    }
    this.xhrGET(url,this.xhrReadBytes, this.xhrTransferFailed, resourceLoadedFlashCallback, resourceFailureFlashCallback, "arraybuffer");
  },
  xhrGET : function (url,loadcallback, errorcallback,resourceLoadedFlashCallback, resourceFailureFlashCallback, responseType) {
    var xhr = new XMLHttpRequest();
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
    var res = this.binding.base64ArrayBuffer(event.currentTarget.response);
    var t1 = new Date();
    this.binding.flashObject[this.resourceLoadedFlashCallback](res,len);
    var t2 = new Date();
    console.log('encoding/toFlash:' + (t1-t0) + '/' + (t2-t1));
    console.log('encoding speed/toFlash:' + Math.round(len/(t1-t0)) + 'kB/s/' + Math.round(res.length/(t2-t1)) + 'kB/s');
  },
  xhrTransferFailed : function(oEvent) {
    console.log("An error occurred while transferring the file :" + oEvent.target.status);
    this.binding.flashObject[this.resourceFailureFlashCallback](res);
  },
  base64ArrayBuffer : function(arrayBuffer) {
    var bytes = new Uint8Array(arrayBuffer),byteLength = bytes.byteLength;
    if(window.btoa) {
      var binary = '';
      for (var i = 0; i < byteLength; i++) {
          binary += String.fromCharCode(bytes[i]);
      }
      return window.btoa(binary);
    } else {
      var base64 = ''
      var encodings = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
      var byteRemainder = byteLength % 3
      var mainLength = byteLength - byteRemainder
      var a, b, c, d, chunk

      for (var i = 0; i < mainLength; i = i + 3) {
        chunk = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2]
        a = (chunk & 16515072) >> 18 // 16515072 = (2^6 - 1) << 18
        b = (chunk & 258048) >> 12 // 258048 = (2^6 - 1) << 12
        c = (chunk & 4032) >> 6 // 4032 = (2^6 - 1) << 6
        d = chunk & 63 // 63 = 2^6 - 1
        base64 += encodings[a] + encodings[b] + encodings[c] + encodings[d]
      }

      if (byteRemainder == 1) {
        chunk = bytes[mainLength]
        a = (chunk & 252) >> 2 // 252 = (2^6 - 1) << 2
        b = (chunk & 3) << 4 // 3 = 2^2 - 1
        base64 += encodings[a] + encodings[b] + '=='
      } else if (byteRemainder == 2) {
        chunk = (bytes[mainLength] << 8) | bytes[mainLength + 1]
        a = (chunk & 64512) >> 10 // 64512 = (2^6 - 1) << 10
        b = (chunk & 1008) >> 4 // 1008 = (2^6 - 1) << 4
        c = (chunk & 15) << 2 // 15 = 2^4 - 1
        base64 += encodings[a] + encodings[b] + encodings[c] + '='
      }
      return base64;
    }
  }
}
