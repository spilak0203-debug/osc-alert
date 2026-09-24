package kr.personal.oscalert;

import org.json.JSONArray;
import org.json.JSONObject;

/** One row of market.json plus the live quote, if one has been fetched. */
final class Stock {
    static final double LIQUIDITY = 5e8;
    private static final String[] KEYS = {"k_fast", "d_fast", "k_slow", "d_slow", "rsi", "rsi_sig", "cci"};

    String ticker, name, market;
    double cap, close = Double.NaN, change = Double.NaN, volume = Double.NaN, dv20 = Double.NaN;
    /** Indicator values for the last few days up to the signal day, oldest first; null if not traded. */
    Rule.Snap[] seq;

    // Live quote (NaN until fetched)
    double livePrice = Double.NaN, liveChange = Double.NaN, liveVolume = Double.NaN;

    static Stock parse(JSONObject o) {
        Stock s = new Stock();
        s.ticker = o.optString("t");
        s.name = o.optString("n");
        s.market = "KS".equals(o.optString("m")) ? "코스피" : "코스닥";
        s.cap = num(o, "cap");
        s.close = num(o, "close");
        s.change = num(o, "chg");
        s.volume = num(o, "vol");
        s.dv20 = num(o, "dv20");
        JSONArray first = o.optJSONArray("rsi");
        if (first != null && first.length() >= 2) {
            int n = first.length();
            s.seq = new Rule.Snap[n];
            for (int i = 0; i < n; i++) s.seq[i] = new Rule.Snap();
            for (int f = 0; f < KEYS.length; f++) {
                JSONArray a = o.optJSONArray(KEYS[f]);
                for (int i = 0; i < n; i++) {
                    double v = a == null || i >= a.length() || a.isNull(i) ? Double.NaN : a.optDouble(i, Double.NaN);
                    set(s.seq[i], f, v);
                }
            }
        }
        return s;
    }

    private static double num(JSONObject o, String key) {
        return o.isNull(key) ? Double.NaN : o.optDouble(key, Double.NaN);
    }

    private static void set(Rule.Snap s, int field, double v) {
        switch (field) {
            case 0: s.kFast = v; break;
            case 1: s.dFast = v; break;
            case 2: s.kSlow = v; break;
            case 3: s.dSlow = v; break;
            case 4: s.rsi = v; break;
            case 5: s.rsiSig = v; break;
            default: s.cci = v;
        }
    }

    Rule.Snap prev() {
        return seq == null ? null : seq[seq.length - 2];
    }

    Rule.Snap last() {
        return seq == null ? null : seq[seq.length - 1];
    }

    boolean liquid() {
        return dv20 >= LIQUIDITY;
    }

    double price() {
        return Double.isNaN(livePrice) ? close : livePrice;
    }

    double changePct() {
        return Double.isNaN(livePrice) ? change : liveChange;
    }

    double tradedVolume() {
        return Double.isNaN(livePrice) ? volume : liveVolume;
    }

    String naverChartUrl() {
        return "https://m.stock.naver.com/fchart/domestic/stock/" + ticker;
    }
}
