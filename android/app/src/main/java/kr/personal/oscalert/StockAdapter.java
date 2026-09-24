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
    private static final int HEADER = 0, ROW = 1, INDEX = 2, COUNTS = 3, SECTION = 4;
    private static final ExecutorService LOADER = Executors.newFixedThreadPool(2);
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    /** The dashboard's tally of stocks per signal kind. */
    static final class Counts {
        final Map<Signals.Kind, List<Stock>> groups;

        Counts(Map<Signals.Kind, List<Stock>> groups) {
            this.groups = groups;
        }
    }

    /** A dashboard section title: one signal kind and how many stocks it has. */
    static final class Section {
        final Signals.Kind kind;
        final int count;

        Section(Signals.Kind kind, int count) {
            this.kind = kind;
            this.count = count;
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
        if (o instanceof Section) return SECTION;
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
            case SECTION: return new SectionHeader(parent.getContext());
            default: return new Row(inf.inflate(R.layout.item_stock, parent, false));
        }
    }

    @Override
    public void onBindViewHolder(@NonNull RecyclerView.ViewHolder h, int position) {
        Object item = items.get(position);
        if (h instanceof Row) ((Row) h).bind((Stock) item);
        else if (h instanceof IndexCard) ((IndexCard) h).bind((MarketIndex) item);
        else if (h instanceof CountsCard) ((CountsCard) h).bind((Counts) item);
        else if (h instanceof SectionHeader) ((SectionHeader) h).bind((Section) item);
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
        lp.setMargins(dp(c, 8), dp(c, 6), dp(c, 8), dp(c, 6));
        card.setLayoutParams(lp);
        return card;
    }

    // ---- section header --------------------------------------------------------------------

    /** Coloured bar, bold title and a count badge, on a tinted strip so sections stand apart. */
    static final class SectionHeader extends RecyclerView.ViewHolder {
        final View bar;
        final TextView title, count;

        SectionHeader(Context c) {
            super(new LinearLayout(c));
            LinearLayout row = (LinearLayout) itemView;
            row.setGravity(Gravity.CENTER_VERTICAL);
            RecyclerView.LayoutParams lp = new RecyclerView.LayoutParams(-1, -2);
            lp.setMargins(dp(c, 12), dp(c, 18), dp(c, 12), dp(c, 4));
            row.setLayoutParams(lp);
            row.setPadding(dp(c, 12), dp(c, 10), dp(c, 12), dp(c, 10));
            bar = new View(c);
            row.addView(bar, new LinearLayout.LayoutParams(dp(c, 5), dp(c, 22)));
            title = label(c, R.style.TextAppearance_Osc_TitleMedium);
            title.setTypeface(androidx.core.content.res.ResourcesCompat.getFont(c, R.font.noto_sans_kr_bold));
            LinearLayout.LayoutParams tl = new LinearLayout.LayoutParams(0, -2, 1);
            tl.leftMargin = dp(c, 10);
            row.addView(title, tl);
            count = label(c, R.style.TextAppearance_Osc_LabelLarge);
            count.setPadding(dp(c, 10), dp(c, 3), dp(c, 10), dp(c, 3));
            count.setTextColor(0xFFFFFFFF);
            row.addView(count);
        }

        void bind(Section s) {
            Context c = itemView.getContext();
            int color = ContextCompat.getColor(c, s.kind.buySide ? R.color.up : R.color.down);
            android.graphics.drawable.GradientDrawable strip = new android.graphics.drawable.GradientDrawable();
            strip.setCornerRadius(dp(c, 10));
            strip.setColor((color & 0x00FFFFFF) | 0x1A000000);
            itemView.setBackground(strip);
            bar.setBackgroundColor(color);
            title.setText(s.kind.label);
            title.setTextColor(color);
            android.graphics.drawable.GradientDrawable pill = new android.graphics.drawable.GradientDrawable();
            pill.setCornerRadius(dp(c, 12));
            pill.setColor(color);
            count.setBackground(pill);
            count.setText(s.count + "종목");
        }
    }

    // ---- index card ------------------------------------------------------------------------

    static final class IndexCard extends RecyclerView.ViewHolder {
        final TextView name, value, change;
        final ChartView chart;

        IndexCard(Context c) {
            super(card(c));
            LinearLayout box = new LinearLayout(c);
            box.setOrientation(LinearLayout.VERTICAL);
            box.setPadding(dp(c, 2), dp(c, 10), dp(c, 2), dp(c, 6));
            LinearLayout head = new LinearLayout(c);
            head.setGravity(Gravity.CENTER_VERTICAL);
            head.setPadding(dp(c, 10), 0, dp(c, 10), 0);
            name = label(c, R.style.TextAppearance_Osc_TitleMedium);
            value = label(c, R.style.TextAppearance_Osc_TitleMedium);
            change = label(c, R.style.TextAppearance_Osc_BodyMedium);
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
            TextView title = label(c, R.style.TextAppearance_Osc_TitleSmall);
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
                TextView count = label(c, R.style.TextAppearance_Osc_HeadlineSmall);
                count.setText(String.valueOf(n));
                count.setTextColor(n == 0 ? ContextCompat.getColor(c, R.color.flat)
                        : ContextCompat.getColor(c, k.buySide ? R.color.up : R.color.down));
                TextView name = label(c, R.style.TextAppearance_Osc_BodySmall);
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
        final android.widget.ImageView star;
        final TextView name, sub, price, change, volume;
        /** Metrics, the day's signals, the indicator table and the chart legend, built in code. */
        final LinearLayout info;
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
            star = v.findViewById(R.id.star);
            star.setOnClickListener(x -> {
                boolean now = Settings.toggleFavorite(x.getContext(), stock.ticker);
                paintStar(now);
                Toast.makeText(x.getContext(), stock.name + (now ? " 즐겨찾기에 추가" : " 즐겨찾기에서 뺌"), Toast.LENGTH_SHORT).show();
            });
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
            paintStar(Settings.favorite(c, s.ticker));
            boolean open = s.ticker.equals(expanded);
            detail.setVisibility(open ? View.VISIBLE : View.GONE);
            if (open) bindDetail(s);
        }

        private void paintStar(boolean on) {
            Context c = itemView.getContext();
            star.setImageResource(on ? R.drawable.ic_star : R.drawable.ic_star_border);
            star.setImageTintList(android.content.res.ColorStateList.valueOf(on
                    ? ContextCompat.getColor(c, R.color.favorite)
                    : com.google.android.material.color.MaterialColors.getColor(c,
                            com.google.android.material.R.attr.colorOnSurfaceVariant, 0xFF888888)));
        }

        private void bindDetail(Stock s) {
            Context c = itemView.getContext();
            Rule.Config cfg = Settings.config(c);
            info.removeAllViews();
            info.addView(metrics(c, s));
            List<Signals.Hit> hits = Signals.hits(c, s);
            if (!hits.isEmpty()) {
                ChipGroup today = flow(c);
                for (Signals.Hit h : hits) {
                    int color = ContextCompat.getColor(c, h.kind.buySide ? R.color.up : R.color.down);
                    today.addView(tag(c, h.describe(), color, true));
                }
                info.addView(today, spaced(c, 10));
            }
            if (s.seq != null) info.addView(indicatorTable(c, s, cfg), spaced(c, 10));
            info.addView(legend(c, cfg), spaced(c, 10));
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
                        if (stock == null || !stock.ticker.equals(ticker)) return;
                        TextView err = label(c, R.style.TextAppearance_Osc_BodySmall);
                        err.setText("차트를 불러오지 못했습니다: " + e.getMessage());
                        info.addView(err);
                    });
                }
            });
        }

        // ---- detail pieces -----------------------------------------------------------------

        private LinearLayout.LayoutParams spaced(Context c, int topDp) {
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
            lp.topMargin = dp(c, topDp);
            return lp;
        }

        private int muted(Context c) {
            return com.google.android.material.color.MaterialColors.getColor(c,
                    com.google.android.material.R.attr.colorOnSurfaceVariant, 0xFF666666);
        }

        private android.graphics.drawable.GradientDrawable rounded(int color, float radius) {
            android.graphics.drawable.GradientDrawable d = new android.graphics.drawable.GradientDrawable();
            d.setColor(color);
            d.setCornerRadius(radius);
            return d;
        }

        /** A soft rounded panel that groups related lines. */
        private LinearLayout panel(Context c) {
            LinearLayout box = new LinearLayout(c);
            box.setOrientation(LinearLayout.VERTICAL);
            box.setPadding(dp(c, 12), dp(c, 10), dp(c, 12), dp(c, 10));
            int base = com.google.android.material.color.MaterialColors.getColor(c,
                    com.google.android.material.R.attr.colorSurfaceVariant, 0xFFE7E0EC);
            box.setBackground(rounded((base & 0x00FFFFFF) | 0x80000000, dp(c, 12)));
            return box;
        }

        private ChipGroup flow(Context c) {
            ChipGroup g = new ChipGroup(c);
            g.setChipSpacingHorizontal(dp(c, 6));
            g.setChipSpacingVertical(dp(c, 6));
            return g;
        }

        /** A pill: solid for what counts today, tinted for context. */
        private TextView tag(Context c, String text, int color, boolean strong) {
            TextView t = label(c, R.style.TextAppearance_Osc_LabelMedium);
            t.setText(text);
            t.setPadding(dp(c, 9), dp(c, 3), dp(c, 9), dp(c, 3));
            t.setTextColor(strong ? 0xFFFFFFFF : color);
            t.setBackground(rounded(strong ? color : (color & 0x00FFFFFF) | 0x24000000, dp(c, 10)));
            return t;
        }

        /** Market cap and liquidity side by side. */
        private View metrics(Context c, Stock s) {
            LinearLayout row = new LinearLayout(c);
            String[][] items = {{"시가총액", compact(s.cap * 1e8) + "원"}, {"20일 평균 거래대금", compact(s.dv20) + "원"}};
            for (String[] it : items) {
                LinearLayout col = new LinearLayout(c);
                col.setOrientation(LinearLayout.VERTICAL);
                TextView k = label(c, R.style.TextAppearance_Osc_BodySmall);
                k.setText(it[0]);
                k.setTextColor(muted(c));
                TextView v = label(c, R.style.TextAppearance_Osc_TitleMedium);
                v.setText(it[1]);
                col.addView(k);
                col.addView(v);
                row.addView(col, new LinearLayout.LayoutParams(0, -2, 1));
            }
            return row;
        }

        /** One row per indicator: name, yesterday → today, and what happened, as tags. */
        private View indicatorTable(Context c, Stock s, Rule.Config cfg) {
            LinearLayout box = panel(c);
            TextView head = label(c, R.style.TextAppearance_Osc_LabelMedium);
            head.setText(Repo.asof.replace('-', '.') + " 종가 · 전날 → 당일");
            head.setTextColor(muted(c));
            box.addView(head);
            Rule.Snap p = s.prev(), l = s.last();
            Rule.Config plain = new Rule.Config();
            plain.slow = cfg.slow;
            plain.stochBand = plain.rsiBand = false;
            boolean[] g = Rule.golden(p, l, cfg), d = Rule.dead(p, l, cfg);
            boolean[] pg = Rule.golden(p, l, plain), pd = Rule.dead(p, l, plain);
            double[][] v = {{cfg.slow ? p.kSlow : p.kFast, cfg.slow ? l.kSlow : l.kFast}, {p.rsi, l.rsi}, {p.cci, l.cci}};
            double[][] zone = {{cfg.stochLo, cfg.stochHi}, {cfg.rsiLo, cfg.rsiHi}, {-cfg.cciLevel, cfg.cciLevel}};
            int up = ContextCompat.getColor(c, R.color.up), down = ContextCompat.getColor(c, R.color.down);
            for (int j = 0; j < 3; j++) {
                LinearLayout row = new LinearLayout(c);
                row.setGravity(Gravity.CENTER_VERTICAL);
                row.setPadding(0, dp(c, 8), 0, 0);
                TextView name = label(c, R.style.TextAppearance_Osc_TitleSmall);
                name.setText(j == 0 ? (cfg.slow ? "스토캐스틱" : "스토캐스틱 F") : Signals.NAMES[j]);
                row.addView(name, new LinearLayout.LayoutParams(dp(c, 84), -2));
                TextView value = label(c, R.style.TextAppearance_Osc_BodyMedium);
                String fmt = j == 2 ? "%.0f → %.0f" : "%.1f → %.1f";
                value.setText(String.format(Locale.KOREA, fmt, v[j][0], v[j][1]));
                value.setTextColor(v[j][1] > v[j][0] ? up : v[j][1] < v[j][0] ? down : muted(c));
                row.addView(value, new LinearLayout.LayoutParams(dp(c, 112), -2));
                ChipGroup tags = flow(c);
                String zoneText = zoneEvent(v[j][0], v[j][1], zone[j][0], zone[j][1]);
                if (!zoneText.isEmpty()) {
                    boolean event = zoneText.endsWith("진입") || zoneText.endsWith("탈출");
                    tags.addView(tag(c, zoneText, zoneText.startsWith("과매도") ? up : down, event));
                }
                if (g[j]) tags.addView(tag(c, "골든크로스", up, true));
                else if (j != 2 && pg[j]) tags.addView(tag(c, "골든크로스 · 조건 밖", up, false));
                if (d[j]) tags.addView(tag(c, "데드크로스", down, true));
                else if (j != 2 && pd[j]) tags.addView(tag(c, "데드크로스 · 조건 밖", down, false));
                if (tags.getChildCount() == 0) {
                    TextView none = label(c, R.style.TextAppearance_Osc_BodySmall);
                    none.setText("변화 없음");
                    none.setTextColor(muted(c));
                    tags.addView(none);
                }
                row.addView(tags, new LinearLayout.LayoutParams(0, -2, 1));
                box.addView(row);
            }
            return box;
        }

        /** What the marks on the charts mean, and how to move around them. */
        private View legend(Context c, Rule.Config cfg) {
            LinearLayout box = panel(c);
            int up = ContextCompat.getColor(c, R.color.up), down = ContextCompat.getColor(c, R.color.down);
            // Small dots only exist when a band condition filters some crossings out.
            boolean filtered = cfg.stochBand || cfg.rsiBand;
            Object[][] lines = filtered ? new Object[][]{
                    {"▲▼", "3지표 일치 · 진한 세로 띠가 일치 구간"},
                    {"△▽", "2지표 일치 · 연한 세로 띠"},
                    {"●", "큰 점 · 신호가 되는 교차 (밴드 조건 충족)"},
                    {"•", "작은 점 · 밴드 조건 밖의 교차 (참고용)"},
                    {"○", "고리 · 과매도·과매수 선을 지난 곳"},
            } : new Object[][]{
                    {"▲▼", "3지표 일치 · 진한 세로 띠가 일치 구간"},
                    {"△▽", "2지표 일치 · 연한 세로 띠"},
                    {"●", "점 · 골든크로스(빨강)·데드크로스(파랑). CCI는 ±기준선 돌파"},
                    {"○", "고리 · 과매도·과매수 선을 지난 곳"},
            };
            TextView head = label(c, R.style.TextAppearance_Osc_LabelMedium);
            head.setText("차트 표시 · 빨강은 골든·과매도 쪽, 파랑은 데드·과매수 쪽");
            head.setTextColor(muted(c));
            box.addView(head);
            for (Object[] line : lines) {
                android.text.SpannableStringBuilder b = new android.text.SpannableStringBuilder();
                String mark = (String) line[0];
                int from = b.length();
                b.append(mark.substring(0, 1));
                b.setSpan(new android.text.style.ForegroundColorSpan(up), from, b.length(), 0);
                if (mark.length() > 1) {
                    from = b.length();
                    b.append(mark.substring(1));
                    b.setSpan(new android.text.style.ForegroundColorSpan(down), from, b.length(), 0);
                } else {
                    from = b.length();
                    b.append(mark);
                    b.setSpan(new android.text.style.ForegroundColorSpan(down), from, b.length(), 0);
                }
                b.append("  ").append((String) line[1]);
                TextView t = label(c, R.style.TextAppearance_Osc_BodySmall);
                t.setText(b);
                t.setPadding(0, dp(c, 4), 0, 0);
                box.addView(t);
            }
            TextView hint = label(c, R.style.TextAppearance_Osc_BodySmall);
            hint.setText("두 손가락으로 확대 · 옆으로 밀어 이동 · 탭하거나 길게 눌러 값 보기 · 두 번 탭하면 처음으로");
            hint.setTextColor(muted(c));
            hint.setPadding(0, dp(c, 8), 0, 0);
            box.addView(hint);
            return box;
        }

        private String zoneEvent(double before, double now, double lo, double hi) {
            boolean wasLow = before < lo, isLow = now < lo, wasHigh = before > hi, isHigh = now > hi;
            if (isLow && !wasLow) return "과매도 진입";
            if (wasLow && !isLow) return "과매도 탈출";
            if (isHigh && !wasHigh) return "과매수 진입";
            if (wasHigh && !isHigh) return "과매수 탈출";
            if (isLow) return "과매도 구간";
            if (isHigh) return "과매수 구간";
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
            String[][] defs = {{Settings.SHOW_MA, "이평선"}, {Settings.SHOW_VOLUME, "거래량"},
                    {Settings.SHOW_STOCH, "스토캐스틱"}, {Settings.SHOW_RSI, "RSI"}, {Settings.SHOW_CCI, "CCI"}};
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
            for (ChartView v : panels) {
                String key;
                switch (v.type()) {
                    case VOLUME: key = Settings.SHOW_VOLUME; break;
                    case STOCH: key = Settings.SHOW_STOCH; break;
                    case RSI: key = Settings.SHOW_RSI; break;
                    case CCI: key = Settings.SHOW_CCI; break;
                    default: continue;
                }
                v.setVisibility(Settings.flag(c, key) ? View.VISIBLE : View.GONE);
            }
        }
    }
}
