package kr.personal.oscalert;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Locale;

/** 신호 JSON을 받아 오고, 새 신호일이면 알림을 띄운다. 워커와 "지금 확인" 버튼이 같이 쓴다. */
final class Signals {
    static final String CHANNEL_GOLDEN = "golden";
    static final String CHANNEL_DEAD = "dead";
    private static final int MAX_BYTES = 2_000_000;

    private Signals() {}

    static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences("osc", Context.MODE_PRIVATE);
    }

    static String url(Context c) {
        String saved = prefs(c).getString("url", "");
        return saved.isEmpty() ? BuildConfig.SIGNALS_URL : saved;
    }

    static void channels(Context c) {
        NotificationManager m = c.getSystemService(NotificationManager.class);
        m.createNotificationChannel(new NotificationChannel(CHANNEL_GOLDEN, "골든 합치 (매수)", NotificationManager.IMPORTANCE_HIGH));
        m.createNotificationChannel(new NotificationChannel(CHANNEL_DEAD, "데드 합치 (매도)", NotificationManager.IMPORTANCE_HIGH));
    }

    /** 받아 와서 저장하고, 새 신호일이면 알림. 새 신호일이었으면 true. */
    static boolean refresh(Context c) throws IOException {
        String address = url(c);
        if (address.isEmpty()) throw new IOException("신호 주소가 비어 있습니다");
        JSONObject data;
        try {
            // raw.githubusercontent.com은 몇 분 캐시한다. 쿼리를 붙여 늘 새로 받는다.
            String sep = address.contains("?") ? "&" : "?";
            data = new JSONObject(fetch(address + sep + "t=" + System.currentTimeMillis(), prefs(c).getString("token", "")));
        } catch (org.json.JSONException e) {
            throw new IOException("신호 파일 형식이 잘못됐습니다");
        }
        String asof = data.optString("asof");
        SharedPreferences p = prefs(c);
        p.edit().putString("latest", data.toString()).putLong("checked", System.currentTimeMillis()).apply();
        if (asof.isEmpty() || asof.equals(p.getString("notified", ""))) return false;
        announce(c, data);
        p.edit().putString("notified", asof).apply();
        return true;
    }

    private static String fetch(String address, String token) throws IOException {
        HttpURLConnection conn = (HttpURLConnection) new URL(address).openConnection();
        conn.setConnectTimeout(15000);
        conn.setReadTimeout(20000);
        if (!token.isEmpty()) conn.setRequestProperty("Authorization", "token " + token);
        try {
            int code = conn.getResponseCode();
            if (code != 200) throw new IOException("서버 응답 " + code);
            try (BufferedReader in = new BufferedReader(new InputStreamReader(conn.getInputStream(), "UTF-8"))) {
                StringBuilder body = new StringBuilder();
                String line;
                while ((line = in.readLine()) != null) {
                    body.append(line).append('\n');
                    if (body.length() > MAX_BYTES) throw new IOException("신호 파일이 너무 큽니다");
                }
                return body.toString();
            }
        } finally {
            conn.disconnect();
        }
    }

    /** 매수는 거래대금 5억 이상만 알림 목록에 올린다(설정에서 끌 수 있음). 매도는 전부. */
    static JSONArray golden(Context c, JSONObject data) {
        JSONArray all = data.optJSONArray("golden"), out = new JSONArray();
        boolean liquidOnly = prefs(c).getBoolean("liquidOnly", true);
        for (int i = 0; all != null && i < all.length(); i++) {
            JSONObject r = all.optJSONObject(i);
            if (r != null && (!liquidOnly || r.optBoolean("liquid"))) out.put(r);
        }
        return out;
    }

    static String line(JSONObject r) {
        String change = r.isNull("change") ? "" : String.format(Locale.KOREA, " (%+.2f%%)", r.optDouble("change"));
        return String.format(Locale.KOREA, "%s %s  %,.0f원%s", r.optString("name"), r.optString("ticker"),
                r.optDouble("close", 0), change);
    }

    private static void announce(Context c, JSONObject data) {
        if (Build.VERSION.SDK_INT >= 33
                && c.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            return;
        }
        channels(c);
        String asof = data.optString("asof");
        JSONArray gold = golden(c, data), dead = data.optJSONArray("dead");
        int nDead = dead == null ? 0 : dead.length();
        if (gold.length() > 0) post(c, 1, CHANNEL_GOLDEN, "골든 합치 " + gold.length() + "종목 · " + asof, gold);
        if (nDead > 0) post(c, 2, CHANNEL_DEAD, "데드 합치 " + nDead + "종목 · " + asof, dead);
        if (gold.length() == 0 && nDead == 0 && prefs(c).getBoolean("quietDays", false)) {
            post(c, 3, CHANNEL_GOLDEN, asof + " 합치 없음", new JSONArray());
        }
    }

    private static void post(Context c, int id, String channel, String title, JSONArray rows) {
        StringBuilder text = new StringBuilder();
        for (int i = 0; i < rows.length() && i < 15; i++) {
            if (i > 0) text.append('\n');
            text.append(line(rows.optJSONObject(i)));
        }
        if (rows.length() > 15) text.append("\n… 외 ").append(rows.length() - 15).append("종목");
        if (rows.length() == 0) text.append("스토캐스틱·RSI·CCI가 같은 날 겹친 종목이 없습니다");
        PendingIntent open = PendingIntent.getActivity(c, 0, new Intent(c, MainActivity.class),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        android.app.Notification n = new android.app.Notification.Builder(c, channel)
                .setSmallIcon(R.drawable.ic_notify)
                .setContentTitle(title)
                .setContentText(text.toString().split("\n")[0])
                .setStyle(new android.app.Notification.BigTextStyle().bigText(text))
                .setContentIntent(open)
                .setAutoCancel(true)
                .build();
        c.getSystemService(NotificationManager.class).notify(id, n);
    }
}
