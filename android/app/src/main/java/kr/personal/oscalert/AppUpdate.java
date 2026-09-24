package kr.personal.oscalert;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.ActivityNotFoundException;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageInstaller;
import android.net.Uri;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;

/**
 * Updates from the repository's GitHub releases. Each app build is published as release
 * `v<versionCode>` with `osc-alert.apk` attached; the APK is streamed straight into a
 * PackageInstaller session (no file provider, no shared storage).
 */
final class AppUpdate {
    private AppUpdate() {}

    static final class Release {
        int code;
        String name, apkUrl, sha256, notes;
    }

    private static final String ACTION = "kr.personal.oscalert.INSTALL_RESULT";
    private static volatile boolean running;

    /** Latest published release, or null if there is none. Blocking. */
    static Release latest() throws Exception {
        JSONObject r = new JSONObject(Net.get("https://api.github.com/repos/" + BuildConfig.REPO + "/releases/latest"));
        String tag = r.optString("tag_name");
        if (!tag.startsWith("v")) return null;
        Release out = new Release();
        try {
            out.code = Integer.parseInt(tag.substring(1));
        } catch (NumberFormatException e) {
            return null;
        }
        out.name = r.optString("name", tag);
        out.notes = r.optString("body", "");
        JSONArray assets = r.optJSONArray("assets");
        for (int i = 0; assets != null && i < assets.length(); i++) {
            JSONObject a = assets.getJSONObject(i);
            if (a.optString("name").endsWith(".apk")) {
                out.apkUrl = a.optString("browser_download_url");
                String digest = a.optString("digest", "");
                if (digest.startsWith("sha256:")) out.sha256 = digest.substring(7);
            }
        }
        return out.apkUrl == null ? null : out;
    }

    static boolean newer(Release r) {
        return r != null && r.code > BuildConfig.VERSION_CODE;
    }

    static void install(Activity a, Release r) {
        if (running) {
            Toast.makeText(a, "업데이트를 이미 받는 중입니다", Toast.LENGTH_SHORT).show();
            return;
        }
        if (!a.getPackageManager().canRequestPackageInstalls()) {
            Toast.makeText(a, "이 앱의 '알 수 없는 앱 설치'를 허용한 뒤 다시 누르세요", Toast.LENGTH_LONG).show();
            try {
                a.startActivity(new Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + a.getPackageName())));
            } catch (ActivityNotFoundException ignored) {
            }
            return;
        }
        running = true;
        Toast.makeText(a, "업데이트를 받는 중입니다…", Toast.LENGTH_SHORT).show();
        new Thread(() -> {
            String error = null;
            PackageInstaller installer = a.getPackageManager().getPackageInstaller();
            int sessionId = -1;
            try {
                HttpURLConnection c = (HttpURLConnection) new URL(r.apkUrl).openConnection();
                c.setConnectTimeout(15000);
                c.setReadTimeout(60000);
                try {
                    if (c.getResponseCode() != 200) throw new IOException("서버 응답 " + c.getResponseCode());
                    sessionId = installer.createSession(new PackageInstaller.SessionParams(
                            PackageInstaller.SessionParams.MODE_FULL_INSTALL));
                    MessageDigest digest = MessageDigest.getInstance("SHA-256");
                    try (PackageInstaller.Session session = installer.openSession(sessionId)) {
                        long total = 0;
                        // The installer refuses to commit while the write stream is open ("Files still open").
                        try (InputStream in = c.getInputStream(); OutputStream out = session.openWrite("app", 0, -1)) {
                            byte[] buf = new byte[65536];
                            int n;
                            while ((n = in.read(buf)) > 0) {
                                out.write(buf, 0, n);
                                digest.update(buf, 0, n);
                                total += n;
                                if (total > 100_000_000L) throw new IOException("설치 파일이 너무 큽니다");
                            }
                            session.fsync(out);
                        }
                        if (total == 0) throw new IOException("설치 파일을 받지 못했습니다");
                        StringBuilder hex = new StringBuilder();
                        for (byte b : digest.digest()) hex.append(String.format("%02x", b));
                        if (r.sha256 != null && !r.sha256.equalsIgnoreCase(hex.toString()))
                            throw new IOException("설치 파일 검증에 실패했습니다");
                        PendingIntent pending = PendingIntent.getBroadcast(a, 0,
                                new Intent(ACTION).setPackage(a.getPackageName()),
                                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE);
                        session.commit(pending.getIntentSender());
                    }
                    sessionId = -1;
                } finally {
                    c.disconnect();
                }
            } catch (Exception e) {
                error = e.getMessage() == null ? "업데이트를 받지 못했습니다" : e.getMessage();
                if (sessionId >= 0) {
                    try { installer.abandonSession(sessionId); } catch (Exception ignored) { }
                }
            }
            running = false;
            String message = error;
            if (message != null) a.runOnUiThread(() -> Toast.makeText(a, message, Toast.LENGTH_LONG).show());
        }, "app-update").start();
    }

    /** The installer answers asynchronously; the confirmation screen arrives as an intent to launch. */
    static BroadcastReceiver receiver(Activity a) {
        return new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                int status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE);
                if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                    Intent confirm = intent.getParcelableExtra(Intent.EXTRA_INTENT);
                    if (confirm != null) {
                        confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        try { a.startActivity(confirm); } catch (Exception ignored) { }
                    }
                    return;
                }
                if (status == PackageInstaller.STATUS_SUCCESS) return;
                String detail = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
                Toast.makeText(a, "설치 실패" + (detail == null ? "" : " · " + detail), Toast.LENGTH_LONG).show();
            }
        };
    }

    static IntentFilter filter() {
        return new IntentFilter(ACTION);
    }
}
