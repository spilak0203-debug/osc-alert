package kr.personal.oscalert;

import android.content.Context;

import java.util.ArrayList;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;

/** Sorts stocks into signal kinds according to the current settings. */
final class Signals {
    private Signals() {}

    static final String[] NAMES = {"스토캐스틱", "RSI", "CCI"};

    enum Kind {
        GOLD3("골든 3지표 일치", true),
        DEAD3("데드 3지표 일치", false),
        GOLD2("골든 2지표 일치", true),
        DEAD2("데드 2지표 일치", false),
        OVERSOLD_IN("과매도 진입", true),
        OVERSOLD_OUT("과매도 탈출", true),
        OVERBOUGHT_IN("과매수 진입", false),
        OVERBOUGHT_OUT("과매수 탈출", false);

        final String label;
        final boolean buySide;

        Kind(String label, boolean buySide) {
            this.label = label;
            this.buySide = buySide;
        }

        boolean zone() {
            return ordinal() >= OVERSOLD_IN.ordinal();
        }
    }

    /** What one stock did on the signal day. */
    static final class Hit {
        final Kind kind;
        /** For 2-of-3: which indicators matched. */
        final boolean[] parts;

        Hit(Kind kind, boolean[] parts) {
            this.kind = kind;
            this.parts = parts;
        }

        String describe() {
            if (kind != Kind.GOLD2 && kind != Kind.DEAD2) return kind.label;
            return kind.label + " (" + which(parts) + ")";
        }
    }

    static String which(boolean[] parts) {
        StringBuilder b = new StringBuilder();
        for (int j = 0; j < 3; j++) {
            if (!parts[j]) continue;
            if (b.length() > 0) b.append('·');
            b.append(NAMES[j]);
        }
        return b.toString();
    }

    /**
     * Every kind the stock shows today. Zone entry/exit: at least `zoneNeed` indicators in the
     * zone today but not yesterday (entry), or the other way round (exit).
     */
    static List<Hit> hits(Stock s, Rule.Config c, int zoneNeed) {
        List<Hit> out = new ArrayList<>();
        if (s.seq == null) return out;
        boolean[][] m = Rule.match(s.seq, c);
        int g = Rule.count(m[0]), d = Rule.count(m[1]);
        if (g == 3) out.add(new Hit(Kind.GOLD3, m[0]));
        else if (g == 2) out.add(new Hit(Kind.GOLD2, m[0]));
        if (d == 3) out.add(new Hit(Kind.DEAD3, m[1]));
        else if (d == 2) out.add(new Hit(Kind.DEAD2, m[1]));
        int[] now = Rule.zones(s.last(), c), before = Rule.zones(s.prev(), c);
        if (now[0] >= zoneNeed && before[0] < zoneNeed) out.add(new Hit(Kind.OVERSOLD_IN, null));
        if (now[0] < zoneNeed && before[0] >= zoneNeed) out.add(new Hit(Kind.OVERSOLD_OUT, null));
        if (now[1] >= zoneNeed && before[1] < zoneNeed) out.add(new Hit(Kind.OVERBOUGHT_IN, null));
        if (now[1] < zoneNeed && before[1] >= zoneNeed) out.add(new Hit(Kind.OVERBOUGHT_OUT, null));
        return out;
    }

    static List<Hit> hits(Context ctx, Stock s) {
        return hits(s, Settings.config(ctx), Settings.integer(ctx, Settings.ZONE_NEED));
    }

    /** Stocks per kind for the dashboard. Every kind appears, even when empty. */
    static Map<Kind, List<Stock>> group(Context ctx, List<Stock> stocks) {
        Rule.Config c = Settings.config(ctx);
        int need = Settings.integer(ctx, Settings.ZONE_NEED);
        Map<Kind, List<Stock>> out = new EnumMap<>(Kind.class);
        for (Kind k : Kind.values()) out.put(k, new ArrayList<>());
        for (Stock s : stocks) {
            if (!Settings.passes(ctx, s)) continue;
            for (Hit h : hits(s, c, need)) out.get(h.kind).add(s);
        }
        return out;
    }

    /** Whether the user asked to be notified about this kind. */
    static boolean alerting(Context ctx, Kind k) {
        switch (k) {
            case GOLD3: case DEAD3: return Settings.flag(ctx, Settings.ALERT_3);
            case GOLD2: case DEAD2: return Settings.flag(ctx, Settings.ALERT_2);
            case OVERSOLD_IN: case OVERBOUGHT_IN: return Settings.flag(ctx, Settings.ALERT_ZONE_IN);
            default: return Settings.flag(ctx, Settings.ALERT_ZONE_OUT);
        }
    }

    /** The subset that should ring. */
    static Map<Kind, List<Stock>> alerts(Context ctx, List<Stock> stocks) {
        Map<Kind, List<Stock>> all = group(ctx, stocks);
        all.keySet().removeIf(k -> !alerting(ctx, k));
        return all;
    }
}
