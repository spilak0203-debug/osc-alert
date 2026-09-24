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
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * The market snapshot both tabs show. market.json is fetched from the repository's release
 * asset and kept on disk; live quotes are layered on top when the user refreshes.
 */
final class Repo {
    private Repo() {}

    interface Listener {
        void onChanged();
    }

    static volatile List<Stock> stocks = Collections.emptyList();
    static volatile String asof = "", error = "";
    static volatile long quotesAt = 0;
    static volatile boolean loading = false;

    private static final List<Listener> LISTENERS = new CopyOnWriteArrayList<>();
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    static void listen(Listener l) { LISTENERS.add(l); }

    static void unlisten(Listener l) { LISTENERS.remove(l); }

    private static void changed() {
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

    /** Loads the cached file if nothing is in memory yet. */
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
        refresh(c, true);
    }

    /**
     * Re-downloads market.json and then live quotes. `allQuotes` fetches every stock's price
     * (stocks tab); otherwise only the stocks that currently signal (summary tab).
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
                changed();
                if (allQuotes) {
                    Live.apply(fresh, Live.all());
                } else {
                    List<String> codes = new ArrayList<>();
                    for (List<Stock> l : Signals.group(c, fresh).values())
                        for (Stock s : l) codes.add(s.ticker);
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
}
