package kr.personal.oscalert;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

/** Current prices from Naver. During the session these are live; after the close, the close. */
final class Live {
    private Live() {}

    static final class Quote {
        double price, change, volume;
    }

    private static final String PAGE =
            "https://m.stock.naver.com/api/stocks/marketValue/%s?page=%d&pageSize=100";
    private static final String POLL = "https://polling.finance.naver.com/api/realtime/domestic/stock/";

    /** Every listed stock, page by page (about 28 requests). */
    static Map<String, Quote> all() throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(4);
        try {
            List<Future<List<JSONObject>>> jobs = new ArrayList<>();
            // KOSPI has about 9 pages and KOSDAQ about 19; ask for a few extra and stop on empty ones.
            for (String market : new String[]{"KOSPI", "KOSDAQ"}) {
                int pages = market.equals("KOSPI") ? 12 : 22;
                for (int p = 1; p <= pages; p++) {
                    String url = String.format(java.util.Locale.ROOT, PAGE, market, p);
                    jobs.add(pool.submit(() -> {
                        JSONArray a = new JSONObject(Net.get(url)).optJSONArray("stocks");
                        List<JSONObject> rows = new ArrayList<>();
                        for (int i = 0; a != null && i < a.length(); i++) rows.add(a.getJSONObject(i));
                        return rows;
                    }));
                }
            }
            Map<String, Quote> out = new HashMap<>();
            for (Future<List<JSONObject>> f : jobs) {
                for (JSONObject o : f.get()) put(out, o, "itemCode");
            }
            return out;
        } finally {
            pool.shutdownNow();
        }
    }

    /** A handful of stocks in one or a few requests (used by the summary tab). */
    static Map<String, Quote> some(List<String> tickers) throws Exception {
        Map<String, Quote> out = new HashMap<>();
        for (int from = 0; from < tickers.size(); from += 40) {
            List<String> chunk = tickers.subList(from, Math.min(tickers.size(), from + 40));
            JSONArray a = new JSONObject(Net.get(POLL + String.join(",", chunk))).optJSONArray("datas");
            for (int i = 0; a != null && i < a.length(); i++) put(out, a.getJSONObject(i), "itemCode");
        }
        return out;
    }

    private static void put(Map<String, Quote> out, JSONObject o, String codeKey) {
        Quote q = new Quote();
        q.price = raw(o, "closePriceRaw", "closePrice");
        q.volume = raw(o, "accumulatedTradingVolumeRaw", "accumulatedTradingVolume");
        q.change = raw(o, "fluctuationsRatioRaw", "fluctuationsRatio");
        // Naver sends the ratio unsigned for falls in some responses; the direction code fixes it.
        JSONObject dir = o.optJSONObject("compareToPreviousPrice");
        String code = dir == null ? "" : dir.optString("code");
        if ((code.equals("4") || code.equals("5")) && q.change > 0) q.change = -q.change;
        if (!Double.isNaN(q.price)) out.put(o.optString(codeKey), q);
    }

    private static double raw(JSONObject o, String rawKey, String textKey) {
        String v = o.optString(rawKey, "");
        if (v.isEmpty()) v = o.optString(textKey, "");
        try {
            return Double.parseDouble(v.replace(",", ""));
        } catch (NumberFormatException e) {
            return Double.NaN;
        }
    }

    static void apply(List<Stock> stocks, Map<String, Quote> quotes) {
        for (Stock s : stocks) {
            Quote q = quotes.get(s.ticker);
            if (q == null) continue;
            s.livePrice = q.price;
            s.liveChange = q.change;
            s.liveVolume = q.volume;
        }
    }
}
