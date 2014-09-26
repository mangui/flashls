package org.mangui.hls.utils {
    import org.mangui.hls.HLSSettings;

    import flash.utils.getQualifiedClassName;
    import flash.utils.getDefinitionByName;
    import flash.utils.Dictionary;

    /**
     * Params2Settings is an helper class that holds every legal external params names 
     * which can be used to customize HLSSettings and maps them to the relevant HLSSettings values
     */
    public class Params2Settings {
        /**
         * HLSSettings <-> params maping
         */
        private static var _paramMap : Dictionary = new Dictionary();
        _paramMap["minbufferlength"] = "minBufferLength";
        _paramMap["maxbufferlength"] = "maxBufferLength";
        _paramMap["lowbufferlength"] = "lowBufferLength";
        _paramMap["seekmode"] = "seekMode";
        _paramMap["startfromlevel"] = "startFromLevel";
        _paramMap["seekfromlevel"] = "seekFromLevel";
        _paramMap["live_flushurlcache"] = "flushLiveURLCache";
        _paramMap["manifestloadmaxretry"] = "manifestLoadMaxRetry";
        _paramMap["manifestloadmaxretrytimeout"] = "manifestLoadMaxRetryTimeout";
        _paramMap["fragmentloadmaxretry"] = "fragmentLoadMaxRetry";
        _paramMap["fragmentloadmaxretrytimeout"] = "fragmentLoadMaxRetryTimeout";
        _paramMap["capleveltostage"] = "capLevelToStage";
        _paramMap["maxlevelcappingmode"] = "maxLevelCappingMode";
        _paramMap["info"] = "logInfo";
        _paramMap["debug"] = "logDebug";
        _paramMap["debug2"] = "logDebug2";
        _paramMap["warn"] = "logWarn";
        _paramMap["error"] = "logError";
        public static function set(key : String, value : Object) : void {
            var param : String = _paramMap[key];
            if (param) {
                // try to assign value with proper object type
                try {
                    var cName:String = getQualifiedClassName(HLSSettings[param]);
					// AS3 bug: "getDefinitionByName" considers var value, not type, and wrongly (e.g. 3.0 >> "int"; 3.1 >> "Number").
                    var c : Class = cName === "int" ? Number : getDefinitionByName(cName) as Class;
                    // get HLSSetting type
                    HLSSettings[param] = c(value);
                    CONFIG::LOGGING {
                    Log.info("HLSSettings." + param + " = " + HLSSettings[param]);
                    }
                } catch(error : Error) {
                    CONFIG::LOGGING {
                    Log.warn("Can't set HLSSettings." + param);
                    }
                }
            }
        }
    }
}
