package org.mangui.hls.utils {
    import com.hurlant.crypto.symmetric.CBCMode;
    import com.hurlant.crypto.symmetric.ICipher;
    import com.hurlant.crypto.symmetric.IPad;
    import com.hurlant.crypto.symmetric.IVMode;
    import com.hurlant.crypto.symmetric.NullPad;
    import com.hurlant.crypto.symmetric.PKCS5;

    import flash.utils.ByteArray;
    import flash.utils.Timer;
    import flash.events.Event;
    import flash.events.TimerEvent;

    /**
     * Contains Utility functions for Decryption
     */
    public class AES {
        private var _key : FastAESKey;
        private var _mode : ICipher;
        private var _iv : ByteArray;
        /* callback function upon decrypt progress */
        private var _progress : Function;
        /* callback function upon decrypt complete */
        private var _complete : Function;
        /** Timer for decrypting packets **/
        private var _timer : Timer;
        /** Byte data to be decrypt **/
        private var _data : ByteArray;
        /** read position **/
        private var _read_position : uint;
        /** write position **/
        private var _write_position : uint;
        /** chunk size to avoid blocking **/
        private static const CHUNK_SIZE : uint = 2048;
        /** is bytearray full ? **/
        private var _data_complete : Boolean;

        public function AES(key : ByteArray, iv : ByteArray, notifyprogress : Function, notifycomplete : Function) {
            var pad : IPad = new PKCS5;
            _key = new FastAESKey(key);
            _mode = new CBCMode(_key, pad);
            pad.setBlockSize(_mode.getBlockSize());
            _iv = iv;
            if (_mode is IVMode) {
                var ivmode : IVMode = _mode as IVMode;
                ivmode.IV = iv;
            }
            _data = new ByteArray();
            _data_complete = false;
            _progress = notifyprogress;
            _complete = notifycomplete;
            _read_position = 0;
            _write_position = 0;
            _timer = new Timer(0, 0);
            _timer.addEventListener(TimerEvent.TIMER, _decryptTimer);
        }

        public function append(data : ByteArray) : void {
            // CONFIG::LOGGING {
            // Log.info("notify append");
            // }
            _data.position = _write_position;
            _data.writeBytes(data);
            _write_position+= data.length;
            _timer.start();
        }

        public function notifycomplete() : void {
            // CONFIG::LOGGING {
            // Log.info("notify complete");
            // }
            _data_complete = true;
            _timer.start();
        }

        public function cancel() : void {
            if (_timer) {
                _timer.stop();
                _timer = null;
            }
        }

        private function _decryptTimer(e : Event) : void {
            var start_time : Number = new Date().getTime();
            do {
                _decryptData();
                // dont spend more than 20 ms in the decrypt timer to avoid blocking/freezing video
            } while (_timer.running && new Date().getTime() - start_time < 20);
        }

        /** decrypt a small chunk of packets each time to avoid blocking **/
        private function _decryptData() : void {
            _data.position = _read_position;
            if (_data.bytesAvailable) {
                var dumpByteArray : ByteArray = new ByteArray();
                var newIv : ByteArray;
                var pad : IPad;
                if (_data.bytesAvailable <= CHUNK_SIZE) {
                    if (_data_complete) {
                        // CONFIG::LOGGING {
                        // Log.info("data complete, last chunk");
                        // }
                        pad = new PKCS5;
                        _read_position += _data.bytesAvailable;
                        _data.readBytes(dumpByteArray, 0, _data.bytesAvailable);
                    } else {
                        // CONFIG::LOGGING {
                        // Log.info("data not complete, stop timer");
                        // }
                        // data not complete, and available data less than chunk size, stop timer and return
                        _timer.stop();
                        return;
                    }
                } else {
                    // bytesAvailable > CHUNK_SIZE
                    // CONFIG::LOGGING {
                    // Log.info("process chunk");
                    // }
                    pad = new NullPad;
                    _read_position += CHUNK_SIZE;
                    _data.readBytes(dumpByteArray, 0, CHUNK_SIZE);
                    // Save new IV from ciphertext
                    newIv = new ByteArray();
                    dumpByteArray.position = (CHUNK_SIZE - 16);
                    dumpByteArray.readBytes(newIv, 0, 16);
                }
                dumpByteArray.position = 0;
                // CONFIG::LOGGING {
                // Log.info("before decrypt");
                // }
                _mode = new CBCMode(_key, pad);
                pad.setBlockSize(_mode.getBlockSize());
                (_mode as IVMode).IV = _iv;
                _mode.decrypt(dumpByteArray);
                // CONFIG::LOGGING {
                // Log.info("after decrypt");
                // }
                _progress(dumpByteArray);
                // switch IV to new one in case more bytes are available
                if (newIv) {
                    _iv = newIv;
                }
            } else {
                // CONFIG::LOGGING {
                // Log.info("no bytes available, stop timer");
                // }
                _timer.stop();
                if (_data_complete) {
                    CONFIG::LOGGING {
                    Log.debug("AES:data+decrypt completed, callback");
                    }
                    // callback
                    _complete();
                }
            }
        }

        public function destroy() : void {
            _key.dispose();
            // _key = null;
            _mode = null;
        }
    }
}
