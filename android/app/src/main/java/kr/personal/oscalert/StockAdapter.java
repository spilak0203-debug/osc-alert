package kr.personal.oscalert;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;
import androidx.recyclerview.widget.RecyclerView;

import com.google.android.material.chip.Chip;
import com.google.android.material.chip.ChipGroup;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Rows of stocks, optionally with section headers. In the stocks tab a tap expands the row into
 * details and charts; in the summary tab a tap opens the Naver chart.
 */
final class StockAdapter extends RecyclerView.Adapter<RecyclerView.ViewHolder> {
    private static final int HEADER = 0, ROW = 1;
    private static final ExecutorService LOADER = Executors.newFixedThreadPool(2);
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private final boolean expandable;
    private List<Object> items = Collections.emptyList();
    private String expanded;

    StockAdapter(boolean expandable) {
        this.expandable = expandable;
    }

    /** Items are `String` (section header) or `Stock`. */
    void submit(List<Object> items) {
        this.items = new ArrayList<>(items);
        notifyDataSetChanged();
    }

    @Override
    public int getItemCount() {
        return items.size();
    }

    @Override
    public int getItemViewType(int position) {
        return items.get(position) instanceof String ? HEADER : ROW;
    }

    @NonNull
    @Override
    public RecyclerView.ViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int type) {
        LayoutInflater inf = LayoutInflater.from(parent.getContext());
        if (type == HEADER) return new RecyclerView.ViewHolder(inf.inflate(R.layout.item_header, parent, false)) {};
        return new Row(inf.inflate(R.layout.item_stock, parent, false));
    }

    @Override
    public void onBindViewHolder(@NonNull RecyclerView.ViewHolder h, int position) {
        Object item = items.get(position);
        if (h instanceof Row) ((Row) h).bind((Stock) item);
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

    final class Row extends RecyclerView.ViewHolder {
        final View head, detail, open;
        final TextView name, sub, price, change, volume, info;
        final ChipGroup toggles;
        final LinearLayout charts;
        final List<ChartView> panels = new ArrayList<>();
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
            head.setOnClickListener(x -> {
                if (!expandable) { openNaver(x.getContext(), stock); return; }
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
            Rule.Config cfg = Settings.config(c);
            for (Signals.Kind k : Signals.kinds(s, cfg, Settings.flag(c, Settings.ALERT_2), Settings.flag(c, Settings.ALERT_ZONE)))
                tags.append(" · ").append(k.label);
            sub.setText(tags);
            price.setText(price(s.price()));
            change.setText(percent(s.changePct()));
            change.setTextColor(changeColor(c, s.changePct()));
            volume.setText("거래량 " + compact(s.tradedVolume()));
            boolean open = expandable && s.ticker.equals(expanded);
            detail.setVisibility(open ? View.VISIBLE : View.GONE);
            if (open) bindDetail(s, cfg);
        }

        private void bindDetail(Stock s, Rule.Config cfg) {
            Context c = itemView.getContext();
            StringBuilder t = new StringBuilder();
            t.append("시가총액 ").append(compact(s.cap * 1e8)).append("원 · 20일 평균 거래대금 ")
                    .append(compact(s.dv20)).append("원");
            if (s.prev != null) {
                double k0 = cfg.slow ? s.prev.kSlow : s.prev.kFast, k1 = cfg.slow ? s.last.kSlow : s.last.kFast;
                t.append(String.format(Locale.KOREA, "\n%%K %.1f → %.1f · RSI %.1f → %.1f · CCI %.0f → %.0f  (%s 종가)",
                        k0, k1, s.prev.rsi, s.last.rsi, s.prev.cci, s.last.cci, Repo.asof));
            }
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

        private void bindCharts(Bars b) {
            Context c = itemView.getContext();
            Rule.Config cfg = Settings.config(c);
            boolean ma = Settings.flag(c, Settings.SHOW_MA), two = Settings.flag(c, Settings.ALERT_2);
            for (ChartView v : panels) v.bind(b, cfg, ma, two, panels);
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
