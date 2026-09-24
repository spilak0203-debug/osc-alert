package kr.personal.oscalert;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * The market snapshot every screen shows. market.json is fetched from the repository's release
 * asset and kept on disk; live quotes and the two indices are layered on top on refresh.
 */
final class Repo {
    private Repo() {}

    interface Listener {
        void onChanged();
    }

    static volatile List<Stock> stocks = Collections.emptyList();
    static volatile List<MarketIndex> indices = Collections.emptyList();
    static volatile String asof = "", error = "";
    static volatile long quotesAt = 0;
    static volatile boolean loading = false;
    /** Set once the stocks tab has been opened: from then on every refresh fetches all prices. */
    static volatile boolean wantAll = false;

    private static final List<Listener> LISTENERS = new CopyOnWriteArrayList<>();
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    static void listen(Listener l) { LISTENERS.add(l); }

    static void unlisten(Listener l) { LISTENERS.remove(l); }

    /** Tells every screen to redraw, e.g. after a settings change. */
    static void changed() {
        MAIN.post(() -> { for (Listener l : LISTENERS) l.onChanged(); });
    }

    static File file(Context c) {
        return new File(c.getFilesDir(), "market.json");
    }

    /** Fetches market.json and stores it. Returns the parsed stocks. Blocking. */
    static List<Stock> download(Context c) throws Exception {
        String text = Net.get(BuildConfig.MARKET_URL + "?t=" + System.currentTimeMillis());
        List<Stock> parsed = parse(text);          // validate before overwriting the cache
        try (FileOutputStream out = new FileOutputStream(file(c))) {
            out.write(text.getBytes(StandardCharsets.UTF_8));
        }
        return parsed;
    }

    static List<Stock> parse(String text) throws Exception {
        JSONObject root = new JSONObject(text);
        JSONArray rows = root.getJSONArray("stocks");
        List<Stock> out = new ArrayList<>(rows.length());
        for (int i = 0; i < rows.length(); i++) out.add(Stock.parse(rows.getJSONObject(i)));
        asof = root.optString("asof");
        return out;
    }

    /** Loads the cached file if nothing is in memory yet, then refreshes. */
    static void ensure(Context c) {
        if (!stocks.isEmpty() || loading) return;
        File f = file(c);
        if (f.exists()) {
            IO.execute(() -> {
                try {
                    stocks = parse(new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8));
                    changed();
                } catch (Exception ignored) {
                }
            });
        }
        refresh(c, false);
    }

    /**
     * Re-downloads market.json, the indices and live quotes. `allQuotes` fetches every stock's
     * price (stocks tab); otherwise only the stocks that currently signal (dashboard).
     */
    static void refresh(Context context, boolean allQuotes) {
        Context c = context.getApplicationContext();
        if (loading) return;
        loading = true;
        changed();
        IO.execute(() -> {
            String err = "";
            try {
                List<Stock> fresh = download(c);
                stocks = fresh;
                Bars.clear();
                changed();
                List<MarketIndex> idx = new ArrayList<>();
                for (String code : MarketIndex.CODES) {
                    try { idx.add(MarketIndex.load(code)); } catch (Exception ignored) { }
                }
                indices = idx;
                changed();
                if (allQuotes || wantAll) {
                    Live.apply(fresh, Live.all());
                } else {
                    List<String> codes = new ArrayList<>();
                    for (List<Stock> l : Signals.group(c, fresh).values())
                        for (Stock s : l) if (!codes.contains(s.ticker)) codes.add(s.ticker);
                    if (!codes.isEmpty()) Live.apply(fresh, Live.some(codes));
                }
                quotesAt = System.currentTimeMillis();
            } catch (Exception e) {
                err = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
            }
            error = err;
            loading = false;
            changed();
        });
    }

    /** Title for the top bar: which close the signals are from, and what the market is doing. */
    static String title() {
        if (asof.isEmpty()) return loading ? "불러오는 중…" : "신호 없음";
        return asof.substring(0, 4) + "." + asof.substring(5, 7) + "." + asof.substring(8) + " 종가 기준";
    }

    static String subtitle() {
        StringBuilder b = new StringBuilder();
        if (!indices.isEmpty()) {
            String s = indices.get(0).session(ZonedDateTime.now(MarketIndex.SEOUL));
            if (!s.isEmpty()) b.append(s);
            // After a holiday the latest signals are from the last trading day — say so.
            if (s.contains("휴장")) b.append(" · 가장 최근 거래일 신호");
            // The scan runs around 15:50–16:40; until then the latest signals are from the day before.
            String today = ZonedDateTime.now(MarketIndex.SEOUL).toLocalDate().toString();
            if ((s.equals("장 마감") || s.equals("장중")) && !asof.equals(today)) b.append(" · 오늘 신호는 장 마감 후");
        }
        if (quotesAt > 0) {
            if (b.length() > 0) b.append(" · ");
            b.append("시세 ").append(new java.text.SimpleDateFormat("HH:mm", java.util.Locale.KOREA).format(new java.util.Date(quotesAt)));
        }
        if (loading) b.append(b.length() > 0 ? " · " : "").append("갱신 중");
        return b.toString();
    }
}
