package kr.personal.oscalert;

import android.app.Activity;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.DateFormat;
import java.util.Date;
import java.util.Locale;

/** 마지막 신호 목록과 설정 한 화면. */
public class MainActivity extends Activity {
    private LinearLayout list;
    private TextView status;
    private final Handler ui = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Signals.channels(this);
        SignalWorker.schedule(this);
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS}, 1);
        }

        SharedPreferences p = Signals.prefs(this);
        LinearLayout root = column();
        int pad = dp(16);
        root.setPadding(pad, dp(28), pad, pad);

        TextView title = text("OSC 3지표 합치 알림", 22, true);
        root.addView(title);
        root.addView(text("스토캐스틱 Slow 5-3-3 · RSI(14)/시그널(9) · CCI(20)이 같은 날 모두 "
                + "골든크로스(과매도권) 또는 데드크로스(과매수권)를 낸 종목. 장 마감 뒤 일봉 기준.", 13, false));

        status = text("", 13, false);
        status.setPadding(0, dp(12), 0, dp(4));
        root.addView(status);

        Button check = new Button(this);
        check.setText("지금 확인");
        check.setOnClickListener(v -> refresh());
        root.addView(check);

        list = column();
        root.addView(list);

        root.addView(section("설정"));
        EditText url = new EditText(this);
        url.setHint("신호 JSON 주소 (raw.githubusercontent.com/...)");
        url.setText(Signals.url(this));
        url.setTextSize(13);
        url.setInputType(InputType.TYPE_TEXT_VARIATION_URI);
        root.addView(url);
        EditText token = new EditText(this);
        token.setHint("GitHub 토큰 (비공개 저장소일 때만)");
        token.setText(p.getString("token", ""));
        token.setTextSize(13);
        token.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        root.addView(token);
        CheckBox liquid = new CheckBox(this);
        liquid.setText("매수 알림은 20일 평균 거래대금 5억 이상만");
        liquid.setChecked(p.getBoolean("liquidOnly", true));
        root.addView(liquid);
        CheckBox quiet = new CheckBox(this);
        quiet.setText("합치가 없는 날에도 알림");
        quiet.setChecked(p.getBoolean("quietDays", false));
        root.addView(quiet);
        Button save = new Button(this);
        save.setText("저장");
        save.setOnClickListener(v -> {
            p.edit().putString("url", url.getText().toString().trim())
                    .putString("token", token.getText().toString().trim())
                    .putBoolean("liquidOnly", liquid.isChecked())
                    .putBoolean("quietDays", quiet.isChecked()).apply();
            Toast.makeText(this, "저장했습니다", Toast.LENGTH_SHORT).show();
            render();
        });
        root.addView(save);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(root);
        setContentView(scroll);
        render();
    }

    @Override
    protected void onResume() {
        super.onResume();
        render();
    }

    private void refresh() {
        status.setText("확인 중…");
        new Thread(() -> {
            String msg;
            try {
                boolean fresh = Signals.refresh(this);
                msg = fresh ? "새 신호를 받았습니다" : "새 신호일이 아닙니다 (이미 알림 보냄)";
                Signals.prefs(this).edit().remove("error").apply();
            } catch (Exception e) {
                msg = "실패: " + e.getMessage();
                Signals.prefs(this).edit().putString("error", e.getMessage()).apply();
            }
            String shown = msg;
            ui.post(() -> {
                Toast.makeText(this, shown, Toast.LENGTH_SHORT).show();
                render();
            });
        }).start();
    }

    private void render() {
        SharedPreferences p = Signals.prefs(this);
        list.removeAllViews();
        long checked = p.getLong("checked", 0);
        String error = p.getString("error", "");
        String when = checked == 0 ? "아직 확인 안 함"
                : "마지막 확인 " + DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT, Locale.KOREA).format(new Date(checked));
        status.setText(when + (error.isEmpty() ? "" : "\n오류: " + error));
        String raw = p.getString("latest", "");
        if (raw.isEmpty()) return;
        try {
            JSONObject data = new JSONObject(raw);
            list.addView(text(data.optString("asof") + " 종가 기준 · " + data.optInt("scanned") + "종목 스캔", 15, true));
            JSONArray gold = Signals.golden(this, data), dead = data.optJSONArray("dead");
            group("골든 합치 (매수)", gold, Color.rgb(0xD1, 0x2B, 0x2B));
            group("데드 합치 (매도)", dead == null ? new JSONArray() : dead, Color.rgb(0x1F, 0x5F, 0xBF));
        } catch (Exception e) {
            list.addView(text("저장된 신호를 읽지 못했습니다", 13, false));
        }
    }

    private void group(String label, JSONArray rows, int color) {
        TextView head = section(label + " · " + rows.length());
        head.setTextColor(color);
        list.addView(head);
        if (rows.length() == 0) {
            list.addView(text("없음", 13, false));
            return;
        }
        for (int i = 0; i < rows.length(); i++) {
            JSONObject r = rows.optJSONObject(i);
            String detail = String.format(Locale.KOREA, "%%K %.1f · RSI %.1f · CCI %.0f · 거래대금 %.0f억",
                    r.optDouble("k"), r.optDouble("rsi"), r.optDouble("cci"), r.optDouble("dv20", 0) / 1e8);
            TextView t = text(Signals.line(r) + "\n" + detail, 14, false);
            t.setPadding(0, dp(6), 0, dp(6));
            list.addView(t);
        }
    }

    private LinearLayout column() {
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.VERTICAL);
        l.setLayoutParams(new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return l;
    }

    private TextView section(String s) {
        TextView t = text(s, 17, true);
        t.setPadding(0, dp(20), 0, dp(4));
        return t;
    }

    private TextView text(String s, int sp, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(sp);
        t.setTextColor(Color.rgb(0x22, 0x22, 0x22));
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        return t;
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }
}
