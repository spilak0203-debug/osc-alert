package kr.personal.oscalert;

import android.content.Context;

import androidx.annotation.NonNull;
import androidx.work.Constraints;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

import java.util.concurrent.TimeUnit;

/**
 * 30분마다 신호 파일을 확인한다. 신호는 장 마감(15:40) 뒤 GitHub Actions가 만들고,
 * 앱은 신호일(`asof`)이 바뀌었을 때만 알림을 띄운다 — 같은 날 여러 번 확인해도 한 번만 울린다.
 *
 * 정확히 몇 시에 울리는지는 Actions 실행 지연(보통 수 분~30분)과 이 주기에 달려 있다.
 */
public class SignalWorker extends Worker {
    private static final String NAME = "osc-signals";

    public SignalWorker(@NonNull Context context, @NonNull WorkerParameters params) {
        super(context, params);
    }

    static void schedule(Context c) {
        Constraints net = new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build();
        PeriodicWorkRequest req = new PeriodicWorkRequest.Builder(SignalWorker.class, 30, TimeUnit.MINUTES)
                .setConstraints(net)
                .build();
        WorkManager.getInstance(c).enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, req);
    }

    @NonNull
    @Override
    public Result doWork() {
        try {
            Signals.refresh(getApplicationContext());
            return Result.success();
        } catch (Exception e) {
            Signals.prefs(getApplicationContext()).edit().putString("error", e.getMessage()).apply();
            return Result.retry();
        }
    }
}
