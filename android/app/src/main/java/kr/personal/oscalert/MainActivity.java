package kr.personal.oscalert;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.os.Build;
import android.os.Bundle;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsControllerCompat;
import androidx.fragment.app.Fragment;
import androidx.fragment.app.FragmentManager;

import com.google.android.material.appbar.MaterialToolbar;
import com.google.android.material.bottomnavigation.BottomNavigationView;
import com.google.android.material.snackbar.Snackbar;

import java.util.Locale;

public class MainActivity extends AppCompatActivity implements Repo.Listener {
    private static final String[] TAGS = {"summary", "stocks", "settings"};
    private static final String TAB = "tab";

    private BroadcastReceiver installResult;
    private MaterialToolbar toolbar;
    private int tab;
    /** Any settings change redraws every screen, hidden ones included. */
    private final SharedPreferences.OnSharedPreferenceChangeListener settingsChanged = (p, key) -> Repo.changed();

    /** The user's font size multiplies the system one, so accessibility settings still count. */
    @Override
    protected void attachBaseContext(Context base) {
        Configuration config = new Configuration(base.getResources().getConfiguration());
        config.fontScale = config.fontScale * Settings.fontScale(base);
        super.attachBaseContext(base.createConfigurationContext(config));
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_main);
        // Dark status-bar icons on the light theme, light ones on the dark theme.
        boolean night = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                == Configuration.UI_MODE_NIGHT_YES;
        WindowInsetsControllerCompat bars = WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
        bars.setAppearanceLightStatusBars(!night);
        bars.setAppearanceLightNavigationBars(!night);
        Notifier.channels(this);
        SignalWorker.schedule(this);

        // No app title: the top bar says which close the signals are from and what the market is doing.
        toolbar = findViewById(R.id.toolbar);
        toolbar.inflateMenu(R.menu.toolbar);
        toolbar.setOnMenuItemClickListener(item -> {
            if (item.getItemId() == R.id.refresh) {
                Toast.makeText(this, "새로고침합니다", Toast.LENGTH_SHORT).show();
                Repo.refresh(this, tab == 1);
                Repo.changed();
            }
            return true;
        });
        updateTitle();

        FragmentManager fm = getSupportFragmentManager();
        if (state == null) {
            fm.beginTransaction()
                    .add(R.id.content, ListFragment.create(true), TAGS[0])
                    .add(R.id.content, ListFragment.create(false), TAGS[1])
                    .add(R.id.content, new SettingsFragment(), TAGS[2])
                    .commitNow();
        }
        tab = state == null ? 0 : state.getInt(TAB, 0);
        BottomNavigationView nav = findViewById(R.id.nav);
        nav.setOnItemSelectedListener(item -> {
            int id = item.getItemId();
            show(id == R.id.tab_stocks ? 1 : id == R.id.tab_settings ? 2 : 0);
            return true;
        });
        nav.setSelectedItemId(tab == 1 ? R.id.tab_stocks : tab == 2 ? R.id.tab_settings : R.id.tab_summary);
        show(tab);

        installResult = AppUpdate.receiver(this);
        ContextCompat.registerReceiver(this, installResult, AppUpdate.filter(), ContextCompat.RECEIVER_NOT_EXPORTED);

        if (state == null) {
            askNotificationPermission();
            offerUpdate();
        }
    }

    @Override
    protected void onStart() {
        super.onStart();
        Repo.listen(this);
        Settings.prefs(this).registerOnSharedPreferenceChangeListener(settingsChanged);
        updateTitle();
    }

    @Override
    protected void onStop() {
        Repo.unlisten(this);
        Settings.prefs(this).unregisterOnSharedPreferenceChangeListener(settingsChanged);
        super.onStop();
    }

    @Override
    public void onChanged() {
        updateTitle();
    }

    private void updateTitle() {
        if (toolbar == null) return;
        toolbar.setTitle(Repo.title());
        String sub = Repo.subtitle();
        toolbar.setSubtitle(sub.isEmpty() ? null : sub);
    }

    @Override
    protected void onDestroy() {
        if (installResult != null) unregisterReceiver(installResult);
        super.onDestroy();
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        out.putInt(TAB, tab);
    }

    private void show(int index) {
        tab = index;
        FragmentManager fm = getSupportFragmentManager();
        androidx.fragment.app.FragmentTransaction tx = fm.beginTransaction();
        for (int i = 0; i < TAGS.length; i++) {
            Fragment f = fm.findFragmentByTag(TAGS[i]);
            if (f == null) continue;
            if (i == index) tx.show(f); else tx.hide(f);
        }
        tx.commitNow();
    }

    void changeFont(int direction) {
        float now = Settings.fontScale(this);
        float next = Math.round((now + direction * Settings.FONT_STEP) * 10) / 10f;
        next = Math.max(Settings.FONT_MIN, Math.min(Settings.FONT_MAX, next));
        if (next == now) {
            Toast.makeText(this, direction > 0 ? "가장 큰 글자입니다" : "가장 작은 글자입니다", Toast.LENGTH_SHORT).show();
            return;
        }
        Settings.prefs(this).edit().putFloat(Settings.FONT_SCALE, next).commit();
        Toast.makeText(this, String.format(Locale.KOREA, "글자 크기 %.0f%%", next * 100), Toast.LENGTH_SHORT).show();
        recreate();
    }

    void askNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS}, 1);
        }
    }

    /** Quietly checks GitHub once per launch; a snackbar offers the install when there is a newer build. */
    private void offerUpdate() {
        new Thread(() -> {
            try {
                AppUpdate.Release r = AppUpdate.latest();
                if (!AppUpdate.newer(r)) return;
                runOnUiThread(() -> {
                    if (isFinishing()) return;
                    Snackbar.make(findViewById(R.id.content), "새 버전(" + r.name + ")이 있습니다", Snackbar.LENGTH_INDEFINITE)
                            .setAnchorView(R.id.nav)
                            .setAction("설치", v -> AppUpdate.install(this, r))
                            .show();
                });
            } catch (Exception ignored) {
            }
        }).start();
    }
}
