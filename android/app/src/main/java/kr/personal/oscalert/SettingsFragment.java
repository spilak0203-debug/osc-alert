package kr.personal.oscalert;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.button.MaterialButtonToggleGroup;
import com.google.android.material.divider.MaterialDivider;
import com.google.android.material.materialswitch.MaterialSwitch;
import com.google.android.material.textfield.TextInputEditText;
import com.google.android.material.textfield.TextInputLayout;

import java.util.Locale;

/** Alert choices, indicator rules, font size and app updates. Every change saves immediately. */
public class SettingsFragment extends Fragment {
    private LinearLayout root;
    private TextView version;
    private MaterialButton updateButton;
    private AppUpdate.Release release;

    @Nullable
    @Override
    public View onCreateView(@NonNull LayoutInflater inf, @Nullable ViewGroup parent, @Nullable Bundle state) {
        Context c = requireContext();
        ScrollView scroll = new ScrollView(c);
        root = new LinearLayout(c);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(4), dp(16), dp(32));
        scroll.addView(root);

        section("알림");
        toggle(Settings.ALERT_3, "3지표 일치 알림", "스토캐스틱·RSI·CCI가 모두 골든(또는 데드)크로스");
        toggle(Settings.ALERT_2, "2지표 일치 알림", "셋 중 둘만 일치해도 따로 알림");
        toggle(Settings.ALERT_ZONE_IN, "과매도·과매수 진입 알림", "아래 '구간 판단 지표 수' 이상이 구간에 새로 들어온 날");
        toggle(Settings.ALERT_ZONE_OUT, "과매도·과매수 탈출 알림", "구간에 있던 지표가 빠져나온 날");
        toggle(Settings.PRE_MARKET, "장 시작 전에도 알림", "다음 거래일 08시대에 같은 알림을 한 번 더");
        toggle(Settings.QUIET_DAYS, "신호 없는 날에도 알림", "켜진 알림 종류에 맞는 종목이 없다는 알림");

        label("알림 방식");
        choice(Settings.sound(c), new String[][]{{"sound", "소리"}, {"vibrate", "진동"}, {"both", "소리+진동"}, {"silent", "무음"}},
                v -> prefs().edit().putString(Settings.SOUND, v).apply());
        MaterialButton test = button("테스트 알림 보내기 (켜진 종류별 예시)", true);
        test.setOnClickListener(v -> {
            if (!Notifier.allowed(c)) {
                Toast.makeText(c, "알림 권한을 허용해야 합니다", Toast.LENGTH_LONG).show();
                ((MainActivity) requireActivity()).askNotificationPermission();
                return;
            }
            int n = Notifier.test(c);
            Toast.makeText(c, "테스트 알림 " + n + "개를 보냈습니다", Toast.LENGTH_SHORT).show();
        });

        section("종목 필터");
        label("대시보드·종목 탭·알림에 모두 적용됩니다");
        label("시장");
        choice(Settings.market(c), new String[][]{{"all", "전체"}, {"코스피", "코스피"}, {"코스닥", "코스닥"}},
                v -> prefs().edit().putString(Settings.FILTER_MARKET, v).apply());
        label("20일 평균 거래대금 최소");
        choice(amount(Settings.FILTER_DV), new String[][]{{"0", "없음"}, {"1", "1억"}, {"5", "5억"}, {"10", "10억"}, {"50", "50억"}},
                v -> prefs().edit().putFloat(Settings.FILTER_DV, Float.parseFloat(v)).apply());
        label("시가총액 최소");
        choice(amount(Settings.FILTER_CAP), new String[][]{{"0", "없음"}, {"500", "500억"}, {"1000", "1천억"}, {"5000", "5천억"}, {"10000", "1조"}},
                v -> prefs().edit().putFloat(Settings.FILTER_CAP, Float.parseFloat(v)).apply());

        section("일치 판단");
        label("허용 기간 · 신호일과 그 앞 며칠 안에 교차하면 같이 센다");
        String[][] windows = new String[Rule.MAX_WINDOW + 1][];
        for (int d = 0; d <= Rule.MAX_WINDOW; d++) windows[d] = new String[]{String.valueOf(d), d == 0 ? "당일" : d + "일"};
        choice(String.valueOf(Settings.integer(c, Settings.WINDOW)), windows,
                v -> prefs().edit().putInt(Settings.WINDOW, Integer.parseInt(v)).apply());
        label("과매도·과매수 구간 판단 지표 수 · 이 개수 이상이 구간에 있을 때");
        choice(String.valueOf(Settings.integer(c, Settings.ZONE_NEED)), new String[][]{{"1", "1개"}, {"2", "2개"}, {"3", "3개"}},
                v -> prefs().edit().putInt(Settings.ZONE_NEED, Integer.parseInt(v)).apply());

        section("스토캐스틱");
        choice(Settings.flag(c, Settings.STOCH_SLOW) ? "slow" : "fast",
                new String[][]{{"slow", "Slow 5-3-3"}, {"fast", "Fast 5-3"}},
                v -> prefs().edit().putBoolean(Settings.STOCH_SLOW, v.equals("slow")).apply());
        toggle(Settings.STOCH_BAND, "밴드 조건 사용", "골든은 직전 %K가 과매도 아래, 데드는 과매수 위일 때만");
        numbers(Settings.STOCH_LO, "과매도", Settings.STOCH_HI, "과매수");

        section("RSI (14 · 시그널 9)");
        toggle(Settings.RSI_BAND, "밴드 조건 사용", "골든은 직전 RSI가 과매도 아래, 데드는 과매수 위일 때만");
        numbers(Settings.RSI_LO, "과매도", Settings.RSI_HI, "과매수");

        section("CCI (20)");
        toggle(Settings.CCI_BAND, "밴드 조건 사용", "켜면 ±기준선 돌파, 끄면 0선 돌파");
        numbers(Settings.CCI_LEVEL, "기준선 (±)", null, null);

        section("화면");
        label("테마");
        choice(Settings.theme(c), new String[][]{{"system", "기기 설정"}, {"light", "라이트"}, {"dark", "다크"}},
                v -> {
                    prefs().edit().putString(Settings.THEME, v).apply();
                    Settings.applyTheme(requireContext());
                });
        label("글자 크기");
        LinearLayout font = new LinearLayout(c);
        font.setOrientation(LinearLayout.HORIZONTAL);
        MaterialButton smaller = button("가−", false), larger = button("가+", false);
        root.removeView(smaller);
        root.removeView(larger);
        TextView pct = new TextView(c);
        pct.setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodyLarge);
        pct.setPadding(dp(16), 0, dp(16), 0);
        pct.setText(String.format(Locale.KOREA, "%.0f%%", Settings.fontScale(c) * 100));
        smaller.setOnClickListener(v -> ((MainActivity) requireActivity()).changeFont(-1));
        larger.setOnClickListener(v -> ((MainActivity) requireActivity()).changeFont(1));
        font.setGravity(android.view.Gravity.CENTER_VERTICAL);
        font.addView(smaller);
        font.addView(pct);
        font.addView(larger);
        root.addView(font);
        label("종목을 길게 누르면 복사할 것");
        choice(Settings.flag(c, Settings.COPY_NAME) ? "name" : "code", new String[][]{{"code", "종목코드"}, {"name", "종목명"}},
                v -> prefs().edit().putBoolean(Settings.COPY_NAME, v.equals("name")).apply());

        section("앱");
        version = label("현재 버전 " + BuildConfig.VERSION_NAME);
        updateButton = button("업데이트 확인", true);
        updateButton.setOnClickListener(v -> {
            if (release != null && AppUpdate.newer(release)) AppUpdate.install(requireActivity(), release);
            else checkUpdate(true);
        });
        return scroll;
    }

    private void checkUpdate(boolean tell) {
        Context c = requireContext().getApplicationContext();
        updateButton.setEnabled(false);
        new Thread(() -> {
            AppUpdate.Release r = null;
            String err = null;
            try {
                r = AppUpdate.latest();
            } catch (Exception e) {
                err = e.getMessage();
            }
            AppUpdate.Release found = r;
            String error = err;
            if (!isAdded()) return;
            requireActivity().runOnUiThread(() -> {
                if (!isAdded()) return;
                updateButton.setEnabled(true);
                release = found;
                if (error != null) {
                    Toast.makeText(c, "확인 실패: " + error, Toast.LENGTH_LONG).show();
                } else if (AppUpdate.newer(found)) {
                    version.setText("현재 버전 " + BuildConfig.VERSION_NAME + " · 새 버전 " + found.name);
                    updateButton.setText("새 버전 설치");
                } else if (tell) {
                    Toast.makeText(c, "최신 버전입니다", Toast.LENGTH_SHORT).show();
                }
            });
        }).start();
    }

    // ---- builders -------------------------------------------------------------------------

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }

    private SharedPreferences prefs() {
        return Settings.prefs(requireContext());
    }

    private void section(String title) {
        if (root.getChildCount() > 0) {
            MaterialDivider d = new MaterialDivider(requireContext());
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
            lp.topMargin = dp(16);
            root.addView(d, lp);
        }
        TextView t = new TextView(requireContext());
        t.setText(title);
        t.setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_TitleMedium);
        t.setPadding(0, dp(16), 0, dp(4));
        root.addView(t);
    }

    private TextView label(String text) {
        TextView t = new TextView(requireContext());
        t.setText(text);
        t.setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodyMedium);
        t.setPadding(0, dp(8), 0, dp(4));
        root.addView(t);
        return t;
    }

    private void toggle(String key, String title, String hint) {
        Context c = requireContext();
        LinearLayout row = new LinearLayout(c);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(android.view.Gravity.CENTER_VERTICAL);
        row.setPadding(0, dp(6), 0, dp(6));
        LinearLayout texts = new LinearLayout(c);
        texts.setOrientation(LinearLayout.VERTICAL);
        TextView t = new TextView(c);
        t.setText(title);
        t.setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodyLarge);
        TextView h = new TextView(c);
        h.setText(hint);
        h.setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodySmall);
        texts.addView(t);
        texts.addView(h);
        row.addView(texts, new LinearLayout.LayoutParams(0, -2, 1));
        MaterialSwitch sw = new MaterialSwitch(c);
        sw.setChecked(Settings.flag(c, key));
        sw.setOnCheckedChangeListener((b, on) -> prefs().edit().putBoolean(key, on).apply());
        row.addView(sw);
        row.setOnClickListener(v -> sw.toggle());
        root.addView(row);
    }

    private String amount(String key) {
        return String.format(Locale.ROOT, "%.0f", Settings.prefs(requireContext()).getFloat(key, 0));
    }

    interface Saver {
        void save(String value);
    }

    /** Segmented buttons; `save` receives the chosen option's value. */
    private void choice(String current, String[][] options, Saver save) {
        Context c = requireContext();
        MaterialButtonToggleGroup g = new MaterialButtonToggleGroup(c);
        g.setSingleSelection(true);
        g.setSelectionRequired(true);
        for (String[] o : options) {
            MaterialButton b = new MaterialButton(c, null, com.google.android.material.R.attr.materialButtonOutlinedStyle);
            b.setId(View.generateViewId());
            b.setText(o[1]);
            b.setTag(o[0]);
            b.setPadding(dp(4), b.getPaddingTop(), dp(4), b.getPaddingBottom());
            g.addView(b, new LinearLayout.LayoutParams(0, -2, 1));
            if (o[0].equals(current)) g.check(b.getId());
        }
        g.addOnButtonCheckedListener((group, id, checked) -> {
            if (checked) save.save((String) group.findViewById(id).getTag());
        });
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.topMargin = dp(4);
        root.addView(g, lp);
    }

    private void numbers(String keyA, String labelA, @Nullable String keyB, @Nullable String labelB) {
        LinearLayout row = new LinearLayout(requireContext());
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.addView(number(keyA, labelA), new LinearLayout.LayoutParams(0, -2, 1));
        if (keyB != null) {
            View gap = new View(requireContext());
            row.addView(gap, new LinearLayout.LayoutParams(dp(12), 1));
            row.addView(number(keyB, labelB), new LinearLayout.LayoutParams(0, -2, 1));
        }
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.topMargin = dp(4);
        root.addView(row, lp);
    }

    private View number(String key, String hint) {
        Context c = requireContext();
        TextInputLayout box = new TextInputLayout(c, null, com.google.android.material.R.attr.textInputOutlinedStyle);
        box.setHint(hint);
        TextInputEditText edit = new TextInputEditText(box.getContext());
        edit.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);
        edit.setText(String.format(Locale.ROOT, "%.0f", Settings.number(c, key)));
        edit.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int a, int b, int d) { }
            @Override public void onTextChanged(CharSequence s, int a, int b, int d) { }
            @Override public void afterTextChanged(Editable s) {
                try {
                    float v = Float.parseFloat(s.toString());
                    boolean ok = key.equals(Settings.CCI_LEVEL) ? v > 0 && v <= 500 : v >= 0 && v <= 100;
                    box.setError(ok ? null : key.equals(Settings.CCI_LEVEL) ? "1~500" : "0~100");
                    if (ok) prefs().edit().putFloat(key, v).apply();
                } catch (NumberFormatException e) {
                    box.setError("숫자");
                }
            }
        });
        box.addView(edit);
        return box;
    }

    private MaterialButton button(String text, boolean tonal) {
        MaterialButton b = new MaterialButton(requireContext(), null,
                tonal ? com.google.android.material.R.attr.materialButtonStyle
                        : com.google.android.material.R.attr.materialButtonOutlinedStyle);
        b.setText(text);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(tonal ? -1 : -2, -2);
        lp.topMargin = dp(8);
        root.addView(b, lp);
        return b;
    }
}
