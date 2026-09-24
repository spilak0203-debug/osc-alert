package kr.personal.oscalert;

import android.content.Context;
import android.content.SharedPreferences;

/** Everything the settings tab controls, stored in one preferences file. */
final class Settings {
    private Settings() {}

    // Alerts
    static final String ALERT_3 = "alert3", ALERT_2 = "alert2", ALERT_ZONE = "alertZone";
    static final String PRE_MARKET = "preMarket", LIQUID_ONLY = "liquidOnly", QUIET_DAYS = "quietDays";
    static final String SOUND = "sound";                     // sound | vibrate | both
    // Indicators
    static final String STOCH_SLOW = "stochSlow";
    static final String STOCH_BAND = "stochBand", STOCH_LO = "stochLo", STOCH_HI = "stochHi";
    static final String RSI_BAND = "rsiBand", RSI_LO = "rsiLo", RSI_HI = "rsiHi";
    static final String CCI_BAND = "cciBand", CCI_LEVEL = "cciLevel";
    // Display
    static final String FONT_SCALE = "fontScale";
    static final String SHOW_MA = "showMa", SHOW_STOCH = "showStoch", SHOW_RSI = "showRsi", SHOW_CCI = "showCci";

    static final float FONT_MIN = 0.7f, FONT_MAX = 2.0f, FONT_STEP = 0.1f;

    static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences("osc", Context.MODE_PRIVATE);
    }

    static boolean flag(Context c, String key) {
        return prefs(c).getBoolean(key, defaultFlag(key));
    }

    static boolean defaultFlag(String key) {
        switch (key) {
            case ALERT_2: case ALERT_ZONE: case PRE_MARKET: case QUIET_DAYS: return false;
            default: return true;
        }
    }

    static float number(Context c, String key) {
        return prefs(c).getFloat(key, defaultNumber(key));
    }

    static float defaultNumber(String key) {
        switch (key) {
            case STOCH_LO: return 20;
            case STOCH_HI: return 80;
            case RSI_LO: return 30;
            case RSI_HI: return 70;
            case CCI_LEVEL: return 100;
            default: return 0;
        }
    }

    static String sound(Context c) {
        return prefs(c).getString(SOUND, "both");
    }

    static float fontScale(Context c) {
        return prefs(c).getFloat(FONT_SCALE, 1f);
    }

    static Rule.Config config(Context c) {
        Rule.Config r = new Rule.Config();
        r.slow = flag(c, STOCH_SLOW);
        r.stochBand = flag(c, STOCH_BAND);
        r.rsiBand = flag(c, RSI_BAND);
        r.cciBand = flag(c, CCI_BAND);
        r.stochLo = number(c, STOCH_LO);
        r.stochHi = number(c, STOCH_HI);
        r.rsiLo = number(c, RSI_LO);
        r.rsiHi = number(c, RSI_HI);
        r.cciLevel = number(c, CCI_LEVEL);
        return r;
    }
}
