package org.mangui.osmf.plugins {
    import flash.display.Sprite;
    import flash.system.Security;

    import org.osmf.media.PluginInfo;

    public class HLSDynamicPlugin extends Sprite {
        private var _pluginInfo : PluginInfo;

        public function HLSDynamicPlugin() {
            super();
            Security.allowDomain("*");
            _pluginInfo = new HLSPlugin();
        }

        public function get pluginInfo() : PluginInfo {
            return _pluginInfo;
        }
    }
}