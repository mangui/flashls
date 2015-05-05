/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.demux {
    /** Video Frame **/
    public class ID3Tag {
        public var id : String;
        public var flag : int;
        public var value : *;

        public function ID3Tag(id : String, flag : int, value : *) {
            this.id = id;
            this.flag = flag;
            this.value = value;
        }
    }
}