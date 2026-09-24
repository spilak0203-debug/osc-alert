package kr.personal.oscalert;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.GridLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;
import androidx.recyclerview.widget.RecyclerView;

import com.google.android.material.card.MaterialCardView;
import com.google.android.material.chip.Chip;
import com.google.android.material.chip.ChipGroup;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Rows for both tabs. Items are a `MarketIndex` (index card), a `Counts` (signal tally),
 * a `String` (section header) or a `Stock`. Tapping a stock expands its charts; the arrow
 * opens Naver; a long press copies the code (or the name, per settings).
 */
final class StockAdapter extends RecyclerView.Adapter<RecyclerView.ViewHolder> {
    private static final int HEADER = 0, ROW = 1, INDEX = 2, COUNTS = 3;
    private static final ExecutorService LOADER = Executors.newFixedThreadPool(2);
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    /** The dashboard's tally of stocks per signal kind. */
    static final class Counts {
        final Map<Signals.Kind, List<Stock>> groups;

        Counts(Map<Signals.Kind, List<Stock>> groups) {
            this.groups = groups;
        }
    }

    interface JumpListener {
        void jump(Signals.Kind kind);
    }

    private List<Object> items = Collections.emptyList();
    private String expanded;
    private JumpListener jumpListener;

    void onJump(JumpListener l) {
        jumpListener = l;
    }

    void submit(List<Object> items) {
        this.items = new ArrayList<>(items);
        notifyDataSetChanged();
    }

    int indexOf(Object item) {
        return items.indexOf(item);
    }

    @Override
    public int getItemCount() {
        return items.size();
    }

    @Override
    public int getItemViewType(int position) {
        Object o = items.get(position);
        if (o instanceof String) return HEADER;
        if (o instanceof MarketIndex) return INDEX;
        if (o instanceof Counts) return COUNTS;
        return ROW;
    }

    @NonNull
    @Override
    public RecyclerView.ViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int type) {
        LayoutInflater inf = LayoutInflater.from(parent.getContext());
        switch (type) {
            case HEADER: return new RecyclerView.ViewHolder(inf.inflate(R.layout.item_header, parent, false)) {};
            case INDEX: return new IndexCard(parent.getContext());
            case COUNTS: return new CountsCard(parent.getContext());
            default: return new Row(inf.inflate(R.layout.item_stock, parent, false));
        }
    }

    @Override
    public void onBindViewHolder(@NonNull RecyclerView.ViewHolder h, int position) {
        Object item = items.get(position);
        if (h instanceof Row) ((Row) h).bind((Stock) item);
        else if (h instanceof IndexCard) ((IndexCard) h).bind((MarketIndex) item);
        else if (h instanceof CountsCard) ((CountsCard) h).bind((Counts) item);
        else ((TextView) h.itemView).setText((String) item);
    }

    // ---- formatting shared with other screens ----------------------------------------------

    static String price(double v) {
        return Double.isNaN(v) ? "-" : String.format(Locale.KOREA, "%,.0f원", v);
    }

    static String percent(double v) {
        return Double.isNaN(v) ? "-" : String.format(Locale.KOREA, "%+.2f%%", v);
    }

    static String compact(double v) {
        if (Double.isNaN(v)) return "-";
        if (v >= 1e12) return String.format(Locale.KOREA, "%.1f조", v / 1e12);
        if (v >= 1e8) return String.format(Locale.KOREA, "%,.0f억", v / 1e8);
        if (v >= 1e4) return String.format(Locale.KOREA, "%,.0f만", v / 1e4);
        return String.format(Locale.KOREA, "%,.0f", v);
    }

    static int changeColor(Context c, double v) {
        return ContextCompat.getColor(c, Double.isNaN(v) || v == 0 ? R.color.flat : v > 0 ? R.color.up : R.color.down);
    }

    static void openNaver(Context c, Stock s) {
        c.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(s.naverChartUrl())));
    }

    static void copy(Context c, Stock s) {
        String what = Settings.flag(c, Settings.COPY_NAME) ? s.name : s.ticker;
        ClipboardManager cm = c.getSystemService(ClipboardManager.class);
        cm.setPrimaryClip(ClipData.newPlainText(s.name, what));
        Toast.makeText(c, "복사했습니다: " + what, Toast.LENGTH_SHORT).show();
    }

    private static int dp(Context c, float v) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, c.getResources().getDisplayMetrics()));
    }

    private static TextView label(Context c, int appearance) {
        TextView t = new TextView(c);
        t.setTextAppearance(appearance);
        return t;
    }

    private static MaterialCardView card(Context c) {
        MaterialCardView card = new MaterialCardView(c, null, com.google.android.material.R.attr.materialCardViewFilledStyle);
        RecyclerView.LayoutParams lp = new RecyclerView.LayoutParams(-1, -2);
        lp.setMargins(dp(c, 12), dp(c, 6), dp(c, 12), dp(c, 6));
        card.setLayoutParams(lp);
        return card;
    }

    // ---- index card ------------------------------------------------------------------------

    static final class IndexCard extends RecyclerView.ViewHolder {
        final TextView name, value, change;
        final ChartView chart;

        IndexCard(Context c) {
            super(card(c));
            LinearLayout box = new LinearLayout(c);
            box.setOrientation(LinearLayout.VERTICAL);
            box.setPadding(dp(c, 12), dp(c, 10), dp(c, 12), dp(c, 8));
            LinearLayout head = new LinearLayout(c);
            head.setGravity(Gravity.CENTER_VERTICAL);
            name = label(c, com.google.android.material.R.style.TextAppearance_Material3_TitleMedium);
            value = label(c, com.google.android.material.R.style.TextAppearance_Material3_TitleMedium);
            change = label(c, com.google.android.material.R.style.TextAppearance_Material3_BodyMedium);
            head.addView(name, new LinearLayout.LayoutParams(0, -2, 1));
            head.addView(value);
            LinearLayout.LayoutParams gap = new LinearLayout.LayoutParams(-2, -2);
            gap.leftMargin = dp(c, 8);
            head.addView(change, gap);
            box.addView(head);
            chart = new ChartView(c, ChartView.Type.CANDLE);
            chart.setCompact(true);
            box.addView(chart);
            ((MaterialCardView) itemView).addView(box);
        }

        void bind(MarketIndex m) {
            Context c = itemView.getContext();
            name.setText(m.label());
            value.setText(Double.isNaN(m.price) ? "-" : String.format(Locale.KOREA, "%,.2f", m.price));
            change.setText(Double.isNaN(m.change) ? "" : String.format(Locale.KOREA, "%+,.2f (%+.2f%%)", m.change, m.changePct));
            change.setTextColor(changeColor(c, m.changePct));
            chart.bind(m.bars, Settings.config(c), true, false, null);
        }
    }

    // ---- signal tally ----------------------------------------------------------------------

    final class CountsCard extends RecyclerView.ViewHolder {
        final GridLayout grid;

        CountsCard(Context c) {
            super(card(c));
            LinearLayout box = new LinearLayout(c);
            box.setOrientation(LinearLayout.VERTICAL);
            box.setPadding(dp(c, 12), dp(c, 10), dp(c, 12), dp(c, 10));
            TextView title = label(c, com.google.android.material.R.style.TextAppearance_Material3_TitleSmall);
            title.setText("오늘의 신호 · 누르면 해당 목록으로");
            box.addView(title);
            grid = new GridLayout(c);
            grid.setColumnCount(2);
            box.addView(grid);
            ((MaterialCardView) itemView).addView(box);
        }

        void bind(Counts counts) {
            Context c = itemView.getContext();
            grid.removeAllViews();
            for (Signals.Kind k : Signals.Kind.values()) {
                List<Stock> l = counts.groups.get(k);
                int n = l == null ? 0 : l.size();
                LinearLayout tile = new LinearLayout(c);
                tile.setOrientation(LinearLayout.VERTICAL);
                tile.setPadding(dp(c, 4), dp(c, 8), dp(c, 4), dp(c, 8));
                TypedValue ripple = new TypedValue();
                c.getTheme().resolveAttribute(android.R.attr.selectableItemBackground, ripple, true);
                tile.setBackgroundResource(ripple.resourceId);
                TextView count = label(c, com.google.android.material.R.style.TextAppearance_Material3_HeadlineSmall);
                count.setText(String.valueOf(n));
                count.setTextColor(n == 0 ? ContextCompat.getColor(c, R.color.flat)
                        : ContextCompat.getColor(c, k.buySide ? R.color.up : R.color.down));
                TextView name = label(c, com.google.android.material.R.style.TextAppearance_Material3_BodySmall);
                name.setText(k.label + (Signals.alerting(c, k) ? " · 알림" : ""));
                tile.addView(count);
                tile.addView(name);
                tile.setOnClickListener(v -> { if (jumpListener != null) jumpListener.jump(k); });
                GridLayout.LayoutParams lp = new GridLayout.LayoutParams(
                        GridLayout.spec(GridLayout.UNDEFINED), GridLayout.spec(GridLayout.UNDEFINED, 1f));
                lp.width = 0;
                grid.addView(tile, lp);
            }
        }
    }

    // ---- stock row -------------------------------------------------------------------------

    final class Row extends RecyclerView.ViewHolder {
        final View head, detail, open;
        final TextView name, sub, price, change, volume, info;
        final ChipGroup toggles;
        final LinearLayout charts;
        final List<ChartView> panels = new ArrayList<>();
        /** Zoom and scroll for the stock currently shown; a different stock starts from the default view. */
        ChartView.Viewport viewport = new ChartView.Viewport();
        String viewportFor;
        Stock stock;

        Row(View v) {
            super(v);
            head = v.findViewById(R.id.head);
            detail = v.findViewById(R.id.detail);
            open = v.findViewById(R.id.open);
            name = v.findViewById(R.id.name);
            sub = v.findViewById(R.id.sub);
            price = v.findViewById(R.id.price);
            change = v.findViewById(R.id.change);
            volume = v.findViewById(R.id.volume);
            info = v.findViewById(R.id.info);
            toggles = v.findViewById(R.id.toggles);
            charts = v.findViewById(R.id.charts);
            open.setOnClickListener(x -> openNaver(x.getContext(), stock));
            v.findViewById(R.id.naver).setOnClickListener(x -> openNaver(x.getContext(), stock));
            head.setOnLongClickListener(x -> {
                copy(x.getContext(), stock);
                return true;
            });
            head.setOnClickListener(x -> {
                String before = expanded;
                expanded = stock.ticker.equals(expanded) ? null : stock.ticker;
                for (int i = 0; i < items.size(); i++) {
                    Object it = items.get(i);
                    if (it instanceof Stock && (((Stock) it).ticker.equals(before) || ((Stock) it).ticker.equals(expanded)))
                        notifyItemChanged(i);
                }
            });
        }

        void bind(Stock s) {
            stock = s;
            Context c = itemView.getContext();
            name.setText(s.name);
            StringBuilder tags = new StringBuilder(s.ticker + " · " + s.market);
            for (Signals.Hit h : Signals.hits(c, s)) tags.append(" · ").append(h.describe());
            sub.setText(tags);
            price.setText(price(s.price()));
            change.setText(percent(s.changePct()));
            change.setTextColor(changeColor(c, s.changePct()));
            volume.setText("거래량 " + compact(s.tradedVolume()));
            boolean open = s.ticker.equals(expanded);
            detail.setVisibility(open ? View.VISIBLE : View.GONE);
            if (open) bindDetail(s);
        }

        private void bindDetail(Stock s) {
            Context c = itemView.getContext();
            Rule.Config cfg = Settings.config(c);
            StringBuilder t = new StringBuilder();
            t.append("시가총액 ").append(compact(s.cap * 1e8)).append("원 · 20일 평균 거래대금 ")
                    .append(compact(s.dv20)).append("원");
            if (s.seq != null) t.append('\n').append(states(s, cfg));
            t.append("\n차트: 두 손가락으로 확대 · 옆으로 밀어 이동 · 탭하거나 길게 눌러 값 보기 · 두 번 탭하면 처음으로");
            info.setText(t);
            bindToggles(c);
            if (panels.isEmpty()) {
                for (ChartView.Type type : ChartView.Type.values()) {
                    ChartView v = new ChartView(c, type);
                    panels.add(v);
                    charts.addView(v);
                }
            }
            applyVisibility(c);
            if (!s.ticker.equals(viewportFor)) {
                viewport = new ChartView.Viewport();
                viewportFor = s.ticker;
            }
            for (ChartView v : panels) v.setViewport(viewport);
            Bars cached = Bars.cached(s.ticker);
            if (cached != null) {
                bindCharts(cached);
                return;
            }
            bindCharts(null);
            String ticker = s.ticker;
            LOADER.execute(() -> {
                try {
                    Bars b = Bars.load(ticker);
                    MAIN.post(() -> { if (stock != null && stock.ticker.equals(ticker)) bindCharts(b); });
                } catch (Exception e) {
                    MAIN.post(() -> {
                        if (stock != null && stock.ticker.equals(ticker)) info.append("\n차트를 불러오지 못했습니다: " + e.getMessage());
                    });
                }
            });
        }

        /** One line per indicator: value, zone, and what happened on the signal day. */
        private String states(Stock s, Rule.Config cfg) {
            Rule.Snap p = s.prev(), l = s.last();
            boolean[] g = Rule.golden(p, l, cfg), d = Rule.dead(p, l, cfg);
            double[][] v = {{cfg.slow ? p.kSlow : p.kFast, cfg.slow ? l.kSlow : l.kFast},
                    {p.rsi, l.rsi}, {p.cci, l.cci}};
            double[][] zone = {{cfg.stochLo, cfg.stochHi}, {cfg.rsiLo, cfg.rsiHi}, {-cfg.cciLevel, cfg.cciLevel}};
            StringBuilder b = new StringBuilder(Repo.asof).append(" 종가");
            for (int j = 0; j < 3; j++) {
                b.append('\n').append(Signals.NAMES[j]).append(' ')
                        .append(String.format(Locale.KOREA, j == 2 ? "%.0f → %.0f" : "%.1f → %.1f", v[j][0], v[j][1]));
                String event = zoneEvent(v[j][0], v[j][1], zone[j][0], zone[j][1]);
                if (!event.isEmpty()) b.append(" · ").append(event);
                if (g[j]) b.append(" · 골든크로스");
                if (d[j]) b.append(" · 데드크로스");
            }
            return b.toString();
        }

        private String zoneEvent(double before, double now, double lo, double hi) {
            boolean wasLow = before < lo, isLow = now < lo, wasHigh = before > hi, isHigh = now > hi;
            if (isLow && !wasLow) return "과매도 진입";
            if (wasLow && !isLow) return "과매도 탈출";
            if (isHigh && !wasHigh) return "과매수 진입";
            if (wasHigh && !isHigh) return "과매수 탈출";
            if (isLow) return "과매도";
            if (isHigh) return "과매수";
            return "";
        }

        private void bindCharts(Bars b) {
            Context c = itemView.getContext();
            Rule.Config cfg = Settings.config(c);
            boolean ma = Settings.flag(c, Settings.SHOW_MA);
            for (ChartView v : panels) v.bind(b, cfg, ma, true, panels);
        }

        private void bindToggles(Context c) {
            if (toggles.getChildCount() > 0) {
                for (int i = 0; i < toggles.getChildCount(); i++) {
                    Chip chip = (Chip) toggles.getChildAt(i);
                    chip.setChecked(Settings.flag(c, (String) chip.getTag()));
                }
                return;
            }
            String[][] defs = {{Settings.SHOW_MA, "이평선"}, {Settings.SHOW_STOCH, "스토캐스틱"},
                    {Settings.SHOW_RSI, "RSI"}, {Settings.SHOW_CCI, "CCI"}};
            for (String[] d : defs) {
                Chip chip = new Chip(c, null, com.google.android.material.R.attr.chipStyle);
                chip.setCheckable(true);
                chip.setText(d[1]);
                chip.setTag(d[0]);
                chip.setChecked(Settings.flag(c, d[0]));
                chip.setOnCheckedChangeListener((btn, on) -> {
                    Settings.prefs(c).edit().putBoolean(d[0], on).apply();
                    applyVisibility(c);
                    if (d[0].equals(Settings.SHOW_MA) && stock != null) bindCharts(Bars.cached(stock.ticker));
                });
                toggles.addView(chip);
            }
        }

        private void applyVisibility(Context c) {
            if (panels.size() < 4) return;
            panels.get(1).setVisibility(Settings.flag(c, Settings.SHOW_STOCH) ? View.VISIBLE : View.GONE);
            panels.get(2).setVisibility(Settings.flag(c, Settings.SHOW_RSI) ? View.VISIBLE : View.GONE);
            panels.get(3).setVisibility(Settings.flag(c, Settings.SHOW_CCI) ? View.VISIBLE : View.GONE);
        }
    }
}
