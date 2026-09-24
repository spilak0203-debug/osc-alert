package kr.personal.oscalert;

import android.content.Context;
import android.content.SharedPreferences;

import androidx.annotation.NonNull;
import androidx.work.Constraints;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

import java.time.DayOfWeek;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;

/**
 * Every 30 minutes: fetch market.json. When the signal day changes (after the close), evaluate
 * the user's rule and notify. With the pre-market option, repeat the same alerts once between
 * 08:00 and 09:00 on the next weekday.
 */
public class SignalWorker extends Worker {
    private static final String NAME = "osc-signals";
    private static final ZoneId SEOUL = ZoneId.of("Asia/Seoul");

    public SignalWorker(@NonNull Context context, @NonNull WorkerParameters params) {
        super(context, params);
    }

    static void schedule(Context c) {
        Constraints net = new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build();
        PeriodicWorkRequest req = new PeriodicWorkRequest.Builder(SignalWorker.class, 30, TimeUnit.MINUTES)
                .setConstraints(net).build();
        // UPDATE so a new app version replaces the worker from version 1.
        WorkManager.getInstance(c).enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.UPDATE, req);
    }

    @NonNull
    @Override
    public Result doWork() {
        Context c = getApplicationContext();
        try {
            check(c, ZonedDateTime.now(SEOUL));
            return Result.success();
        } catch (Exception e) {
            return Result.retry();
        }
    }

    static void check(Context c, ZonedDateTime now) throws Exception {
        SharedPreferences p = Settings.prefs(c);
        List<Stock> stocks = Repo.download(c);
        String asof = Repo.asof;
        if (asof.isEmpty()) return;
        if (!asof.equals(p.getString("notified", ""))) {
            Notifier.post(c, asof, Signals.alerts(c, stocks), "");
            p.edit().putString("notified", asof).apply();
            return;
        }
        boolean weekday = now.getDayOfWeek() != DayOfWeek.SATURDAY && now.getDayOfWeek() != DayOfWeek.SUNDAY;
        boolean morning = now.getHour() == 8;
        // Only repeat signals from a previous day — never on the evening they were first sent.
        boolean fromBefore = asof.compareTo(now.toLocalDate().toString()) < 0;
        if (Settings.flag(c, Settings.PRE_MARKET) && weekday && morning && fromBefore
                && !asof.equals(p.getString("preMarketSent", ""))) {
            Map<Signals.Kind, List<Stock>> alerts = Signals.alerts(c, stocks);
            Notifier.post(c, asof, alerts, "[장 시작 전] ");
            p.edit().putString("preMarketSent", asof).apply();
        }
    }
}
