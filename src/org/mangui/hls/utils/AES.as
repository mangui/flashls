package org.mangui.hls.utils {
    import flash.utils.ByteArray;
    import flash.utils.Timer;
    import flash.events.Event;
    import flash.events.TimerEvent;

    /**
     * Contains Utility functions for AES-128 CBC Decryption
     */
    public class AES {
        private var _key : FastAESKey;
        private var iv0 : uint;
        private var iv1 : uint;
        private var iv2 : uint;
        private var iv3 : uint;
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
            _key = new FastAESKey(key);
            iv.position = 0;
            iv0 = iv.readUnsignedInt();
            iv1 = iv.readUnsignedInt();
            iv2 = iv.readUnsignedInt();
            iv3 = iv.readUnsignedInt();
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
            _write_position += data.length;
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
            var decryptdata : ByteArray;
            if (_data.bytesAvailable) {
                if (_data.bytesAvailable <= CHUNK_SIZE) {
                    if (_data_complete) {
                        // CONFIG::LOGGING {
                        // Log.info("data complete, last chunk");
                        // }
                        _read_position += _data.bytesAvailable;
                        decryptdata = _decryptCBC(_data, _data.bytesAvailable);
                        unpad(decryptdata);
                    } else {
                        // data not complete, and available data less than chunk size, stop timer and return
                        // CONFIG::LOGGING {
                        // Log.info("data not complete, stop timer");
                        // }
                        _timer.stop();
                        return;
                    }
                } else {
                    _read_position += CHUNK_SIZE;
                    decryptdata = _decryptCBC(_data, CHUNK_SIZE);
                }
                _progress(decryptdata);
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

        /* Cypher Block Chaining Decryption, refer to 
         * http://en.wikipedia.org/wiki/Block_cipher_mode_of_operation#Cipher-block_chaining_
         * for algorithm description
         */
        private function _decryptCBC(crypt : ByteArray, len : uint) : ByteArray {
            var src : Vector.<uint> = new Vector.<uint>(4);
            var dst : Vector.<uint> = new Vector.<uint>(4);
            var decrypt : ByteArray = new ByteArray();
            decrypt.length = len;

            for (var i : uint = 0; i < len / 16; i++) {
                // read src byte array
                src[0] = crypt.readUnsignedInt();
                src[1] = crypt.readUnsignedInt();
                src[2] = crypt.readUnsignedInt();
                src[3] = crypt.readUnsignedInt();

                // AES decrypt src vector into dst vector
                _key.decrypt128(src, dst);

                // CBC : write output = XOR(decrypted,IV)
                decrypt.writeUnsignedInt(dst[0] ^ iv0);
                decrypt.writeUnsignedInt(dst[1] ^ iv1);
                decrypt.writeUnsignedInt(dst[2] ^ iv2);
                decrypt.writeUnsignedInt(dst[3] ^ iv3);

                // CBC : next IV = (input)
                iv0 = src[0];
                iv1 = src[1];
                iv2 = src[2];
                iv3 = src[3];
            }
            decrypt.position = 0;
            return decrypt;
        }

        public function unpad(a : ByteArray) : void {
            var c : uint = a.length % 16;
            if (c != 0) throw new Error("PKCS#5::unpad: ByteArray.length isn't a multiple of the blockSize");
            c = a[a.length - 1];
            for (var i : uint = c; i > 0; i--) {
                var v : uint = a[a.length - 1];
                a.length--;
                if (c != v) throw new Error("PKCS#5:unpad: Invalid padding value. expected [" + c + "], found [" + v + "]");
            }
        }

        public function destroy() : void {
            _key.dispose();
            // _key = null;
        }
    }
}
