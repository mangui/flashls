function onRequestResource0(URL) {
  appendLog("loading fragment "+ URL + " for instance 0");
  URL_request(URL,URL_readBytes0, transferFailed0, "arraybuffer");
}

function onRequestResource1(URL) {
  appendLog("loading fragment "+ URL + " for instance 1");
  URL_request(URL,URL_readBytes1,transferFailed1, "arraybuffer");
}

function URL_request(url, loadcallback, errorcallback,responseType) {
    var xhr = new XMLHttpRequest();
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
}
function transferFailed0(oEvent) {
    appendLog("An error occurred while transferring the file :" + oEvent.target.status);
  var obj = getFlashMovieObject(player_id);
  if(obj != null) {
    obj.resourceLoadingError0();
  }
}

function transferFailed1(oEvent) {
    appendLog("An error occurred while transferring the file :" + oEvent.target.status);
  var obj = getFlashMovieObject(player_id);
  if(obj != null) {
    obj.resourceLoadingError1();
  }
}


function URL_readBytes0(event) {
  appendLog("fragment loaded");
  var res = base64ArrayBuffer(event.currentTarget.response);
  resourceLoaded0(res);
}

function URL_readBytes1(event) {
  appendLog("fragment loaded");
  var res = base64ArrayBuffer(event.currentTarget.response);
  resourceLoaded1(res);
}


function resourceLoaded0(res) {
  var obj = getFlashMovieObject(player_id);
  if(obj != null) {
    obj.resourceLoaded0(res);
  }
}

function resourceLoaded1(res) {
  var obj = getFlashMovieObject(player_id);
  if(obj != null) {
    obj.resourceLoaded1(res);
  }
}

function base64ArrayBuffer(arrayBuffer) {
    var base64 = ''
    var encodings = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    var bytes = new Uint8Array(arrayBuffer)
    var byteLength = bytes.byteLength
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