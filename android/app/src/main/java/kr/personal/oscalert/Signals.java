package kr.personal.oscalert;

import android.content.Context;

import java.util.ArrayList;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;

/** Sorts stocks into signal kinds according to the current settings. */
final class Signals {
    private Signals() {}

    enum Kind {
        GOLD3("골든 합치 (3/3)", true),
        DEAD3("데드 합치 (3/3)", false),
        GOLD2("골든 2/3", true),
        DEAD2("데드 2/3", false),
        OVERSOLD("과매도 구간 진입", true),
        OVERBOUGHT("과매수 구간 진입", false);

        final String label;
        final boolean buySide;

        Kind(String label, boolean buySide) {
            this.label = label;
            this.buySide = buySide;
        }
    }

    /** What a stock does today under the given rule. Empty if it was not traded on the signal day. */
    static List<Kind> kinds(Stock s, Rule.Config c, boolean twoOfThree, boolean zones) {
        List<Kind> out = new ArrayList<>();
        if (s.prev == null) return out;
        int g = Rule.count(Rule.golden(s.prev, s.last, c));
        int d = Rule.count(Rule.dead(s.prev, s.last, c));
        if (g == 3) out.add(Kind.GOLD3);
        if (d == 3) out.add(Kind.DEAD3);
        if (twoOfThree && g == 2) out.add(Kind.GOLD2);
        if (twoOfThree && d == 2) out.add(Kind.DEAD2);
        if (zones) {
            // "Entering" = at least `need` indicators in the zone today but not yesterday,
            // so a stock that stays oversold for a week is reported once.
            int need = twoOfThree ? 2 : 3;
            int[] now = Rule.zones(s.last, c), before = Rule.zones(s.prev, c);
            if (now[0] >= need && before[0] < need) out.add(Kind.OVERSOLD);
            if (now[1] >= need && before[1] < need) out.add(Kind.OVERBOUGHT);
        }
        return out;
    }

    /** Stocks per kind for display (summary tab). Every enabled kind appears, even when empty. */
    static Map<Kind, List<Stock>> group(Context ctx, List<Stock> stocks) {
        Rule.Config c = Settings.config(ctx);
        boolean two = Settings.flag(ctx, Settings.ALERT_2);
        boolean zones = Settings.flag(ctx, Settings.ALERT_ZONE);
        boolean liquidOnly = Settings.flag(ctx, Settings.LIQUID_ONLY);
        Map<Kind, List<Stock>> out = new EnumMap<>(Kind.class);
        out.put(Kind.GOLD3, new ArrayList<>());
        out.put(Kind.DEAD3, new ArrayList<>());
        if (two) { out.put(Kind.GOLD2, new ArrayList<>()); out.put(Kind.DEAD2, new ArrayList<>()); }
        if (zones) { out.put(Kind.OVERSOLD, new ArrayList<>()); out.put(Kind.OVERBOUGHT, new ArrayList<>()); }
        for (Stock s : stocks) {
            for (Kind k : kinds(s, c, two, zones)) {
                // Buying needs liquidity; selling never waits for it.
                if (k.buySide && liquidOnly && !s.liquid()) continue;
                out.get(k).add(s);
            }
        }
        return out;
    }

    /** The subset that should ring: kinds the user switched on for notifications. */
    static Map<Kind, List<Stock>> alerts(Context ctx, List<Stock> stocks) {
        Map<Kind, List<Stock>> all = group(ctx, stocks);
        if (!Settings.flag(ctx, Settings.ALERT_3)) {
            all.remove(Kind.GOLD3);
            all.remove(Kind.DEAD3);
        }
        return all;
    }

    static int total(Map<Kind, List<Stock>> m) {
        int n = 0;
        for (List<Stock> l : m.values()) n += l.size();
        return n;
    }
}
