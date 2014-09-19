package org.mangui.hls.demux {
    import flash.utils.ByteArray;
    public class ExpGolomb {
        private var _data : ByteArray;
        private var _bit : int;
        private var _curByte : uint;

        public function ExpGolomb(data : ByteArray) {
            _data = data;
            _bit = -1;
        }

        private function _readBit() : uint {
            var res : uint;
            if (_bit == -1) {
                // read next
                _curByte = _data.readByte();
                _bit = 7;
            }
            res = _curByte & (1 << _bit) ? 1 : 0;
            _bit--;
            return res;
        }

        private function _readBits(nbBits : uint) : int {
            var val : int = 0;
            for (var i : uint = 0; i < nbBits; ++i)
                val = (val << 1) + _readBit();
            return val;
        }

        public function readUE() : uint {
            var nbZero : uint = 0;
            while (_readBit() == 0)
                ++nbZero;
            var x : uint = _readBits(nbZero);
            return x + (1 << nbZero) - 1;
        }
    }
}
