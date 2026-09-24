package kr.personal.oscalert;

import android.content.ActivityNotFoundException;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageInstaller;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.work.WorkManager;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * The Flutter app plus the Android pieces Dart can't do: the Java app's old preferences, its
 * old background job, and installing an update. The APK is streamed straight into a
 * PackageInstaller session (no file provider, no shared storage).
 */
public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "kr.personal.oscalert/native";
    private static final String ACTION = "kr.personal.oscalert.INSTALL_RESULT";
    private static volatile boolean installing;
    private BroadcastReceiver installResult;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        installResult = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                int status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE);
                if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                    Intent confirm = intent.getParcelableExtra(Intent.EXTRA_INTENT);
                    if (confirm != null) {
                        confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        try { startActivity(confirm); } catch (Exception ignored) { }
                    }
                    return;
                }
                if (status == PackageInstaller.STATUS_SUCCESS) return;
                String detail = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
                Toast.makeText(MainActivity.this, "설치 실패" + (detail == null ? "" : " · " + detail), Toast.LENGTH_LONG).show();
            }
        };
        IntentFilter filter = new IntentFilter(ACTION);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(installResult, filter, Context.RECEIVER_NOT_EXPORTED);
        else registerReceiver(installResult, filter);
    }

    @Override
    protected void onDestroy() {
        if (installResult != null) unregisterReceiver(installResult);
        super.onDestroy();
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL).setMethodCallHandler(this::handle);
    }

    private void handle(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "legacyPrefs":
                result.success(legacyPrefs());
                break;
            case "cancelLegacyWork":
                WorkManager.getInstance(this).cancelUniqueWork("osc-signals");
                result.success(null);
                break;
            case "launchExtras": {
                Map<String, Object> out = new HashMap<>();
                out.put("smoke", getIntent().getBooleanExtra("smoke", false));
                result.success(out);
                break;
            }
            case "installApk":
                install(call.argument("url"), call.argument("sha256"), result);
                break;
            case "dynamicColors":
                result.success(dynamicColors());
                break;
            default:
                result.notImplemented();
        }
    }

    /**
     * The system's Material You colour roles (Android 14+), exactly what the Java app's
     * DynamicColors applied, as {"light": {role: argb}, "dark": {...}}; null on older versions.
     */
    private Map<String, Object> dynamicColors() {
        if (Build.VERSION.SDK_INT < 34) return null;
        int[][] roles = {
                {android.R.color.system_primary_light, android.R.color.system_primary_dark},
                {android.R.color.system_on_primary_light, android.R.color.system_on_primary_dark},
                {android.R.color.system_primary_container_light, android.R.color.system_primary_container_dark},
                {android.R.color.system_on_primary_container_light, android.R.color.system_on_primary_container_dark},
                {android.R.color.system_secondary_light, android.R.color.system_secondary_dark},
                {android.R.color.system_on_secondary_light, android.R.color.system_on_secondary_dark},
                {android.R.color.system_secondary_container_light, android.R.color.system_secondary_container_dark},
                {android.R.color.system_on_secondary_container_light, android.R.color.system_on_secondary_container_dark},
                {android.R.color.system_tertiary_light, android.R.color.system_tertiary_dark},
                {android.R.color.system_on_tertiary_light, android.R.color.system_on_tertiary_dark},
                {android.R.color.system_tertiary_container_light, android.R.color.system_tertiary_container_dark},
                {android.R.color.system_on_tertiary_container_light, android.R.color.system_on_tertiary_container_dark},
                {android.R.color.system_error_light, android.R.color.system_error_dark},
                {android.R.color.system_on_error_light, android.R.color.system_on_error_dark},
                {android.R.color.system_error_container_light, android.R.color.system_error_container_dark},
                {android.R.color.system_on_error_container_light, android.R.color.system_on_error_container_dark},
                {android.R.color.system_surface_light, android.R.color.system_surface_dark},
                {android.R.color.system_on_surface_light, android.R.color.system_on_surface_dark},
                {android.R.color.system_on_surface_variant_light, android.R.color.system_on_surface_variant_dark},
                {android.R.color.system_outline_light, android.R.color.system_outline_dark},
                {android.R.color.system_outline_variant_light, android.R.color.system_outline_variant_dark},
                {android.R.color.system_surface_dim_light, android.R.color.system_surface_dim_dark},
                {android.R.color.system_surface_bright_light, android.R.color.system_surface_bright_dark},
                {android.R.color.system_surface_container_lowest_light, android.R.color.system_surface_container_lowest_dark},
                {android.R.color.system_surface_container_low_light, android.R.color.system_surface_container_low_dark},
                {android.R.color.system_surface_container_light, android.R.color.system_surface_container_dark},
                {android.R.color.system_surface_container_high_light, android.R.color.system_surface_container_high_dark},
                {android.R.color.system_surface_container_highest_light, android.R.color.system_surface_container_highest_dark},
        };
        String[] names = {"primary", "onPrimary", "primaryContainer", "onPrimaryContainer",
                "secondary", "onSecondary", "secondaryContainer", "onSecondaryContainer",
                "tertiary", "onTertiary", "tertiaryContainer", "onTertiaryContainer",
                "error", "onError", "errorContainer", "onErrorContainer",
                "surface", "onSurface", "onSurfaceVariant", "outline", "outlineVariant",
                "surfaceDim", "surfaceBright", "surfaceContainerLowest", "surfaceContainerLow",
                "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest"};
        Map<String, Object> light = new HashMap<>(), dark = new HashMap<>();
        for (int i = 0; i < roles.length; i++) {
            light.put(names[i], (long) getColor(roles[i][0]) & 0xFFFFFFFFL);
            dark.put(names[i], (long) getColor(roles[i][1]) & 0xFFFFFFFFL);
        }
        Map<String, Object> out = new HashMap<>();
        out.put("light", light);
        out.put("dark", dark);
        return out;
    }

    /** The Java app's "osc" preferences, in types the method channel can carry. */
    private Map<String, Object> legacyPrefs() {
        Map<String, Object> out = new HashMap<>();
        for (Map.Entry<String, ?> e : getSharedPreferences("osc", MODE_PRIVATE).getAll().entrySet()) {
            Object v = e.getValue();
            if (v instanceof Set) out.put(e.getKey(), new ArrayList<>((Set<?>) v));
            else if (v instanceof Float) out.put(e.getKey(), ((Float) v).doubleValue());
            else out.put(e.getKey(), v);
        }
        return out;
    }

    /** Answers null once the system's confirmation screen is on its way, or an error message. */
    private void install(String url, String sha256, MethodChannel.Result result) {
        if (installing) {
            result.success("업데이트를 이미 받는 중입니다");
            return;
        }
        if (!getPackageManager().canRequestPackageInstalls()) {
            try {
                startActivity(new Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + getPackageName())));
            } catch (ActivityNotFoundException ignored) {
            }
            result.success("이 앱의 '알 수 없는 앱 설치'를 허용한 뒤 다시 누르세요");
            return;
        }
        installing = true;
        new Thread(() -> {
            String error = null;
            PackageInstaller installer = getPackageManager().getPackageInstaller();
            int sessionId = -1;
            try {
                HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
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
                                if (total > 200_000_000L) throw new IOException("설치 파일이 너무 큽니다");
                            }
                            session.fsync(out);
                        }
                        if (total == 0) throw new IOException("설치 파일을 받지 못했습니다");
                        StringBuilder hex = new StringBuilder();
                        for (byte b : digest.digest()) hex.append(String.format("%02x", b));
                        if (sha256 != null && !sha256.equalsIgnoreCase(hex.toString()))
                            throw new IOException("설치 파일 검증에 실패했습니다");
                        android.app.PendingIntent pending = android.app.PendingIntent.getBroadcast(this, 0,
                                new Intent(ACTION).setPackage(getPackageName()),
                                android.app.PendingIntent.FLAG_UPDATE_CURRENT | android.app.PendingIntent.FLAG_MUTABLE);
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
            installing = false;
            String message = error;
            runOnUiThread(() -> result.success(message));
        }, "app-update").start();
    }
}
