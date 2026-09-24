package kr.personal.oscalert;

import org.json.JSONArray;
import org.json.JSONObject;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZonedDateTime;

/** KOSPI and KOSDAQ for the dashboard: live quote, daily bars, and whether the market is open today. */
final class MarketIndex {
    static final String[] CODES = {"KOSPI", "KOSDAQ"};
    static final ZoneId SEOUL = ZoneId.of("Asia/Seoul");

    final String code;
    double price = Double.NaN, change = Double.NaN, changePct = Double.NaN;
    String status = "", tradedAt = "";
    Bars bars;

    MarketIndex(String code) {
        this.code = code;
    }

    String label() {
        return code.equals("KOSPI") ? "코스피" : "코스닥";
    }

    /** Blocking: quote and about a year of daily bars. */
    static MarketIndex load(String code) throws Exception {
        MarketIndex m = new MarketIndex(code);
        JSONObject root = new JSONObject(Net.get("https://polling.finance.naver.com/api/realtime/domestic/index/" + code));
        JSONArray datas = root.optJSONArray("datas");
        if (datas != null && datas.length() > 0) {
            JSONObject d = datas.getJSONObject(0);
            m.price = parse(d.optString("closePriceRaw", d.optString("closePrice")));
            m.change = parse(d.optString("compareToPreviousClosePriceRaw", d.optString("compareToPreviousClosePrice")));
            m.changePct = parse(d.optString("fluctuationsRatioRaw", d.optString("fluctuationsRatio")));
            JSONObject dir = d.optJSONObject("compareToPreviousPrice");
            String c = dir == null ? "" : dir.optString("code");
            if ((c.equals("4") || c.equals("5")) && m.changePct > 0) { m.changePct = -m.changePct; m.change = -Math.abs(m.change); }
            m.status = d.optString("marketStatus");
            m.tradedAt = d.optString("localTradedAt");
        }
        m.bars = Bars.load(code);
        return m;
    }

    private static double parse(String s) {
        try {
            return Double.parseDouble(s.replace(",", ""));
        } catch (Exception e) {
            return Double.NaN;
        }
    }

    /**
     * What the market is doing right now, in words. Holidays are recognised because the index's
     * last trade is not from today even though the session hours have started.
     */
    String session(ZonedDateTime now) {
        if ("OPEN".equals(status)) return "장중";
        LocalDate today = now.toLocalDate();
        boolean tradedToday = tradedAt.startsWith(today.toString());
        if (tradedToday) return "장 마감";
        boolean weekend = now.getDayOfWeek() == DayOfWeek.SATURDAY || now.getDayOfWeek() == DayOfWeek.SUNDAY;
        if (weekend) return "주말 휴장";
        if (now.getHour() < 9) return "개장 전";
        return tradedAt.isEmpty() ? "" : "휴장";
    }
}
