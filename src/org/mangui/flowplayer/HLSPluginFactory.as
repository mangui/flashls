package org.mangui.flowplayer {
    import org.flowplayer.model.PluginFactory;

    import flash.display.Sprite;

    public class HLSPluginFactory extends Sprite implements PluginFactory {
        public function HLSPluginFactory() {
        }

        public function newPlugin() : Object {
            return new HLSProvider();
        }
    }
}