package kr.personal.oscalert;

import org.json.JSONArray;
import org.json.JSONObject;

/** One row of market.json plus the live quote, if one has been fetched. */
final class Stock {
    static final double LIQUIDITY = 5e8;

    String ticker, name, market;
    double cap, close = Double.NaN, change = Double.NaN, volume = Double.NaN, dv20 = Double.NaN;
    /** Indicator values on the day before the signal day and on the signal day; null if not traded. */
    Rule.Snap prev, last;

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
        if (o.has("rsi")) {
            s.prev = new Rule.Snap();
            s.last = new Rule.Snap();
            fill(o, "k_fast", s.prev, s.last, 0);
            fill(o, "d_fast", s.prev, s.last, 1);
            fill(o, "k_slow", s.prev, s.last, 2);
            fill(o, "d_slow", s.prev, s.last, 3);
            fill(o, "rsi", s.prev, s.last, 4);
            fill(o, "rsi_sig", s.prev, s.last, 5);
            fill(o, "cci", s.prev, s.last, 6);
        }
        return s;
    }

    private static double num(JSONObject o, String key) {
        return o.isNull(key) ? Double.NaN : o.optDouble(key, Double.NaN);
    }

    private static void fill(JSONObject o, String key, Rule.Snap prev, Rule.Snap last, int field) {
        JSONArray a = o.optJSONArray(key);
        double p = a == null || a.isNull(0) ? Double.NaN : a.optDouble(0, Double.NaN);
        double l = a == null || a.isNull(1) ? Double.NaN : a.optDouble(1, Double.NaN);
        set(prev, field, p);
        set(last, field, l);
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
