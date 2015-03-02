/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.player.flowplayer {

    import flash.display.Sprite;
    import org.flowplayer.model.PluginFactory;

    public class HLSPluginFactory extends Sprite implements PluginFactory {
        public function HLSPluginFactory() {
        }

        public function newPlugin() : Object {
            return new HLSStreamProvider();
        }
    }
}