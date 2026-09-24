package kr.personal.oscalert;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.os.Build;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Notification channels fix sound and vibration when they are created, so there is one
 * channel per choice and the setting picks which one to post to.
 */
final class Notifier {
    private Notifier() {}

    private static final long[] PATTERN = {0, 300, 200, 300};

    static void channels(Context c) {
        NotificationManager m = c.getSystemService(NotificationManager.class);
        // Channels from version 1.
        m.deleteNotificationChannel("golden");
        m.deleteNotificationChannel("dead");

        AudioAttributes audio = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build();

        NotificationChannel both = new NotificationChannel("sig_both", "신호 알림 · 소리+진동", NotificationManager.IMPORTANCE_HIGH);
        both.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION), audio);
        both.enableVibration(true);
        both.setVibrationPattern(PATTERN);

        NotificationChannel sound = new NotificationChannel("sig_sound", "신호 알림 · 소리만", NotificationManager.IMPORTANCE_HIGH);
        sound.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION), audio);
        sound.enableVibration(false);
        sound.setVibrationPattern(new long[]{0});

        NotificationChannel vibrate = new NotificationChannel("sig_vibrate", "신호 알림 · 진동만", NotificationManager.IMPORTANCE_HIGH);
        vibrate.setSound(null, null);
        vibrate.enableVibration(true);
        vibrate.setVibrationPattern(PATTERN);

        // Shown in the shade and on the lock screen, but never makes a sound or pops up.
        NotificationChannel silent = new NotificationChannel("sig_silent", "신호 알림 · 무음", NotificationManager.IMPORTANCE_LOW);
        silent.setSound(null, null);
        silent.enableVibration(false);

        m.createNotificationChannel(both);
        m.createNotificationChannel(sound);
        m.createNotificationChannel(vibrate);
        m.createNotificationChannel(silent);
    }

    static String channel(Context c) {
        switch (Settings.sound(c)) {
            case "sound": return "sig_sound";
            case "vibrate": return "sig_vibrate";
            case "silent": return "sig_silent";
            default: return "sig_both";
        }
    }

    static boolean allowed(Context c) {
        return Build.VERSION.SDK_INT < 33
                || c.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED;
    }

    /** One notification per signal kind. `prefix` marks repeats and tests. Returns how many were posted. */
    static int post(Context c, String asof, Map<Signals.Kind, List<Stock>> groups, String prefix) {
        if (!allowed(c)) return 0;
        channels(c);
        int posted = 0;
        String day = asof.length() >= 10 ? asof.substring(5).replace('-', '.') : asof;
        for (Map.Entry<Signals.Kind, List<Stock>> e : groups.entrySet()) {
            List<Stock> rows = e.getValue();
            if (rows.isEmpty()) continue;
            show(c, 10 + e.getKey().ordinal(), prefix + e.getKey().label + " " + rows.size() + "종목 · " + day, lines(c, rows));
            posted++;
        }
        if (posted == 0 && Settings.flag(c, Settings.QUIET_DAYS)) {
            show(c, 9, prefix + day + " 신호 없음", "설정한 조건에 맞는 종목이 없습니다");
            posted++;
        }
        return posted;
    }

    private static String lines(Context c, List<Stock> rows) {
        StringBuilder text = new StringBuilder();
        for (int i = 0; i < rows.size() && i < 15; i++) {
            if (i > 0) text.append('\n');
            text.append(line(rows.get(i)));
        }
        if (rows.size() > 15) text.append("\n… 외 ").append(rows.size() - 15).append("종목");
        return text.toString();
    }

    /**
     * One example per alert kind that is switched on, so the user sees exactly what will arrive.
     * Uses today's real stocks when there are some; otherwise a sample line.
     */
    static int test(Context c) {
        channels(c);
        Map<Signals.Kind, List<Stock>> real = Signals.group(c, Repo.stocks);
        int shown = 0;
        for (Signals.Kind k : Signals.Kind.values()) {
            if (!Signals.alerting(c, k)) continue;
            List<Stock> rows = real.get(k);
            String text;
            int n;
            if (rows != null && !rows.isEmpty()) {
                text = lines(c, rows);
                n = rows.size();
            } else {
                text = "예시종목  12,345원 (+1.23%)\n오늘은 이 조건에 맞는 종목이 없어 예시로 보여 드립니다";
                n = 1;
            }
            show(c, 100 + k.ordinal(), "[테스트] " + k.label + " " + n + "종목", text);
            shown++;
        }
        if (shown == 0) {
            show(c, 99, "[테스트] 켜진 알림이 없습니다", "설정에서 받을 알림 종류를 켜세요 · " + describe(Settings.sound(c)));
            shown = 1;
        }
        return shown;
    }

    static String describe(String sound) {
        switch (sound) {
            case "sound": return "소리만";
            case "vibrate": return "진동만";
            case "silent": return "무음";
            default: return "소리+진동";
        }
    }

    static String line(Stock s) {
        return String.format(Locale.KOREA, "%s  %,.0f원 (%+.2f%%)", s.name, s.price(), s.changePct());
    }

    private static void show(Context c, int id, String title, String text) {
        if (!allowed(c)) return;
        PendingIntent open = PendingIntent.getActivity(c, 0, new Intent(c, MainActivity.class),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification n = new Notification.Builder(c, channel(c))
                .setSmallIcon(R.drawable.ic_notify)
                .setContentTitle(title)
                .setContentText(text.split("\n")[0])
                .setStyle(new Notification.BigTextStyle().bigText(text))
                .setContentIntent(open)
                .setAutoCancel(true)
                .build();
        c.getSystemService(NotificationManager.class).notify(id, n);
    }
}
