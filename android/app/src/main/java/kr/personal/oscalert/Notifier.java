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

        m.createNotificationChannel(both);
        m.createNotificationChannel(sound);
        m.createNotificationChannel(vibrate);
    }

    static String channel(Context c) {
        switch (Settings.sound(c)) {
            case "sound": return "sig_sound";
            case "vibrate": return "sig_vibrate";
            default: return "sig_both";
        }
    }

    static boolean allowed(Context c) {
        return Build.VERSION.SDK_INT < 33
                || c.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED;
    }

    /** One notification per signal kind. `prefix` marks the pre-market repeat. Returns how many were posted. */
    static int post(Context c, String asof, Map<Signals.Kind, List<Stock>> groups, String prefix) {
        if (!allowed(c)) return 0;
        channels(c);
        int posted = 0;
        for (Map.Entry<Signals.Kind, List<Stock>> e : groups.entrySet()) {
            List<Stock> rows = e.getValue();
            if (rows.isEmpty()) continue;
            StringBuilder text = new StringBuilder();
            for (int i = 0; i < rows.size() && i < 15; i++) {
                if (i > 0) text.append('\n');
                text.append(line(rows.get(i)));
            }
            if (rows.size() > 15) text.append("\n… 외 ").append(rows.size() - 15).append("종목");
            show(c, 10 + e.getKey().ordinal(), prefix + e.getKey().label + " " + rows.size() + "종목 · " + asof, text.toString());
            posted++;
        }
        if (posted == 0 && Settings.flag(c, Settings.QUIET_DAYS)) {
            show(c, 9, prefix + asof + " 신호 없음", "설정한 조건에 맞는 종목이 없습니다");
            posted++;
        }
        return posted;
    }

    static void test(Context c) {
        channels(c);
        show(c, 99, "테스트 알림", "알림이 이렇게 옵니다 · " + describe(Settings.sound(c)));
    }

    static String describe(String sound) {
        switch (sound) {
            case "sound": return "소리만";
            case "vibrate": return "진동만";
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
