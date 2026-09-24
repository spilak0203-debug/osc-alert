package kr.personal.oscalert;

import android.util.LruCache;

import org.json.JSONArray;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/** Daily bars for one stock, from Naver, for the charts. */
final class Bars {
    String[] date;
    double[] open, high, low, close, volume;
    Indicators.Series series;

    private static final String URL = "https://api.finance.naver.com/siseJson.naver?symbol=%s"
            + "&requestType=1&startTime=%s&endTime=%s&timeframe=day";
    private static final LruCache<String, Bars> CACHE = new LruCache<>(30);
    private static final long DAY = 86_400_000L;

    static Bars cached(String ticker) {
        return CACHE.get(ticker);
    }

    /** About 400 calendar days, enough for the 120-day average and a settled RSI. Blocking. */
    static Bars load(String ticker) throws Exception {
        SimpleDateFormat f = new SimpleDateFormat("yyyyMMdd", Locale.ROOT);
        long now = System.currentTimeMillis();
        String text = Net.get(String.format(Locale.ROOT, URL, ticker,
                f.format(new Date(now - 420 * DAY)), f.format(new Date(now))));
        // The response is almost JSON: the header row uses single quotes.
        JSONArray rows = new JSONArray(text.trim().replace('\'', '"'));
        List<double[]> vals = new ArrayList<>();
        List<String> dates = new ArrayList<>();
        for (int i = 1; i < rows.length(); i++) {
            JSONArray r = rows.getJSONArray(i);
            double o = r.optDouble(1), h = r.optDouble(2), l = r.optDouble(3), c = r.optDouble(4), v = r.optDouble(5);
            // Days without trades carry no price information; the scan leaves them out too.
            if (!(v > 0 && o > 0 && h > 0 && l > 0 && c > 0)) continue;
            dates.add(r.getString(0).trim());
            vals.add(new double[]{o, Math.max(h, Math.max(o, c)), Math.min(l, Math.min(o, c)), c, v});
        }
        Bars b = new Bars();
        int n = vals.size();
        b.date = dates.toArray(new String[0]);
        b.open = new double[n]; b.high = new double[n]; b.low = new double[n];
        b.close = new double[n]; b.volume = new double[n];
        for (int i = 0; i < n; i++) {
            double[] v = vals.get(i);
            b.open[i] = v[0]; b.high[i] = v[1]; b.low[i] = v[2]; b.close[i] = v[3]; b.volume[i] = v[4];
        }
        b.series = Indicators.compute(b.high, b.low, b.close);
        CACHE.put(ticker, b);
        return b;
    }

    int size() {
        return close.length;
    }
}
