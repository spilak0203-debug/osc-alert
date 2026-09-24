package kr.personal.oscalert;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.DashPathEffect;
import android.graphics.Paint;
import android.graphics.Path;
import android.util.TypedValue;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;

import androidx.core.content.ContextCompat;

import com.google.android.material.color.MaterialColors;

import java.util.List;
import java.util.Locale;

/**
 * One panel of the stock detail: candles with moving averages, or one oscillator.
 * Panels in the same group share a crosshair — touching any panel selects that day in all.
 */
final class ChartView extends View {
    enum Type { CANDLE, STOCH, RSI, CCI }

    static final int WINDOW = 120;

    private final Type type;
    private Bars bars;
    private Rule.Config cfg = new Rule.Config();
    private boolean showMa = true, twoOfThree;
    private List<ChartView> group;
    private int selected = -1;

    private final Paint line = new Paint(Paint.ANTI_ALIAS_FLAG), fill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint text = new Paint(Paint.ANTI_ALIAS_FLAG), dash = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final int up, down, flat, onSurface, muted, grid, band, mainLine, sigLine;
    private final int[] maColors;

    ChartView(Context c, Type type) {
        super(c);
        this.type = type;
        up = ContextCompat.getColor(c, R.color.up);
        down = ContextCompat.getColor(c, R.color.down);
        flat = ContextCompat.getColor(c, R.color.flat);
        grid = ContextCompat.getColor(c, R.color.grid);
        band = ContextCompat.getColor(c, R.color.band);
        mainLine = ContextCompat.getColor(c, R.color.line_main);
        sigLine = ContextCompat.getColor(c, R.color.line_signal);
        maColors = new int[]{ContextCompat.getColor(c, R.color.ma5), ContextCompat.getColor(c, R.color.ma20),
                ContextCompat.getColor(c, R.color.ma60), ContextCompat.getColor(c, R.color.ma120)};
        onSurface = MaterialColors.getColor(c, com.google.android.material.R.attr.colorOnSurface, 0xFF222222);
        muted = MaterialColors.getColor(c, com.google.android.material.R.attr.colorOnSurfaceVariant, 0xFF666666);
        text.setTextSize(sp(11));
        line.setStyle(Paint.Style.STROKE);
        dash.setStyle(Paint.Style.STROKE);
        dash.setStrokeWidth(dp(1));
        dash.setPathEffect(new DashPathEffect(new float[]{dp(4), dp(3)}, 0));
    }

    void bind(Bars bars, Rule.Config cfg, boolean showMa, boolean twoOfThree, List<ChartView> group) {
        this.bars = bars;
        this.cfg = cfg;
        this.showMa = showMa;
        this.twoOfThree = twoOfThree;
        this.group = group;
        selected = -1;
        invalidate();
    }

    @Override
    protected void onMeasure(int w, int h) {
        int height = (int) dp(type == Type.CANDLE ? 230 : 110) + (int) sp(type == Type.CANDLE ? 30 : 16);
        setMeasuredDimension(MeasureSpec.getSize(w), height);
    }

    private float dp(float v) {
        return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics());
    }

    private float sp(float v) {
        return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, v, getResources().getDisplayMetrics());
    }

    // ---- geometry -------------------------------------------------------------------------

    private int from() { return Math.max(0, bars.size() - WINDOW); }

    private float left() { return dp(4); }

    private float right() { return getWidth() - text.measureText("000,000,000") - dp(6); }

    private float top() { return sp(18); }

    private float bottom() { return getHeight() - (type == Type.CANDLE ? sp(16) : dp(4)); }

    private float step() { return (right() - left()) / Math.max(1, bars.size() - from()); }

    private float x(int i) { return left() + (i - from() + 0.5f) * step(); }

    private float y(double v, double lo, double hi) {
        return (float) (bottom() - (v - lo) / (hi - lo) * (bottom() - top()));
    }

    // ---- touch ----------------------------------------------------------------------------

    private float downX, downY;
    private boolean dragging;

    /**
     * A tap or a sideways drag moves the crosshair. A vertical drag is left to the list, so the
     * page still scrolls when the finger starts on a chart.
     */
    @Override
    public boolean onTouchEvent(MotionEvent e) {
        if (bars == null || bars.size() == 0) return false;
        int slop = ViewConfiguration.get(getContext()).getScaledTouchSlop();
        switch (e.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                downX = e.getX();
                downY = e.getY();
                dragging = false;
                return true;
            case MotionEvent.ACTION_MOVE:
                float dx = Math.abs(e.getX() - downX), dy = Math.abs(e.getY() - downY);
                if (!dragging && dx > slop && dx > dy) {
                    dragging = true;
                    getParent().requestDisallowInterceptTouchEvent(true);
                }
                if (dragging) selectAt(e.getX());
                return true;
            case MotionEvent.ACTION_UP:
                if (!dragging && Math.abs(e.getX() - downX) <= slop && Math.abs(e.getY() - downY) <= slop) {
                    selectAt(e.getX());
                    performClick();
                }
                // fall through
            case MotionEvent.ACTION_CANCEL:
                dragging = false;
                getParent().requestDisallowInterceptTouchEvent(false);
                return true;
        }
        return super.onTouchEvent(e);
    }

    @Override
    public boolean performClick() {
        return super.performClick();
    }

    private void selectAt(float px) {
        int i = from() + (int) ((px - left()) / step());
        i = Math.max(from(), Math.min(bars.size() - 1, i));
        if (group != null) for (ChartView v : group) v.select(i);
        else select(i);
    }

    void select(int i) {
        selected = i;
        invalidate();
    }

    // ---- drawing --------------------------------------------------------------------------

    @Override
    protected void onDraw(Canvas c) {
        if (bars == null || bars.size() < 2) {
            text.setColor(muted);
            c.drawText("차트를 불러오는 중…", dp(8), getHeight() / 2f, text);
            return;
        }
        switch (type) {
            case CANDLE: drawCandles(c); break;
            case STOCH: drawStoch(c); break;
            case RSI: drawRsi(c); break;
            default: drawCci(c);
        }
        int at = selected >= 0 ? selected : bars.size() - 1;
        if (selected >= 0) {
            line.setColor(muted);
            line.setStrokeWidth(dp(1));
            c.drawLine(x(at), top(), x(at), bottom(), line);
        }
    }

    private int at() {
        return selected >= 0 ? selected : bars.size() - 1;
    }

    private void drawCandles(Canvas c) {
        int a = from(), n = bars.size();
        double lo = Double.MAX_VALUE, hi = -Double.MAX_VALUE;
        for (int i = a; i < n; i++) {
            lo = Math.min(lo, bars.low[i]);
            hi = Math.max(hi, bars.high[i]);
            if (showMa) for (double[] m : bars.series.ma) {
                if (!Double.isNaN(m[i])) { lo = Math.min(lo, m[i]); hi = Math.max(hi, m[i]); }
            }
        }
        double pad = (hi - lo) * 0.08 + 1e-9;
        lo -= pad;
        hi += pad;
        gridAndAxis(c, lo, hi, 0, false);
        priceTicks(c, lo, hi);

        float w = Math.max(1f, step() * 0.62f);
        for (int i = a; i < n; i++) {
            boolean rising = bars.close[i] >= bars.open[i];
            int color = bars.close[i] == bars.open[i] ? flat : rising ? up : down;
            line.setColor(color);
            line.setStrokeWidth(Math.max(1f, dp(1)));
            c.drawLine(x(i), y(bars.high[i], lo, hi), x(i), y(bars.low[i], lo, hi), line);
            fill.setColor(color);
            fill.setStyle(Paint.Style.FILL);
            float y1 = y(Math.max(bars.open[i], bars.close[i]), lo, hi);
            float y2 = y(Math.min(bars.open[i], bars.close[i]), lo, hi);
            c.drawRect(x(i) - w / 2, y1, x(i) + w / 2, Math.max(y2, y1 + 1), fill);
        }
        if (showMa) {
            for (int m = 0; m < bars.series.ma.length; m++) polyline(c, bars.series.ma[m], lo, hi, maColors[m], dp(1.3f));
        }
        markers(c, lo, hi);

        // Header: selected day, then moving-average legend.
        int i = at();
        String d = bars.date[i];
        String head = String.format(Locale.KOREA, "%s.%s.%s  시 %,.0f  고 %,.0f  저 %,.0f  종 %,.0f",
                d.substring(0, 4), d.substring(4, 6), d.substring(6), bars.open[i], bars.high[i], bars.low[i], bars.close[i]);
        text.setColor(onSurface);
        c.drawText(head, left(), sp(13), text);
        if (showMa) {
            float xx = left();
            float yy = top() + sp(12);
            for (int m = 0; m < Indicators.MA.length; m++) {
                String label = "MA" + Indicators.MA[m] + " ";
                text.setColor(maColors[m]);
                c.drawText(label, xx, yy, text);
                xx += text.measureText(label) + dp(4);
            }
        }
        // Dates under the axis.
        text.setColor(muted);
        float base = getHeight() - dp(3);
        c.drawText(label(a), left(), base, text);
        String last = label(n - 1);
        c.drawText(last, right() - text.measureText(last), base, text);
    }

    private String label(int i) {
        String d = bars.date[i];
        return d.substring(2, 4) + "." + d.substring(4, 6) + "." + d.substring(6);
    }

    /** ▲ under golden confluences and ▼ over dead ones; hollow for 2 of 3 when that alert is on. */
    private void markers(Canvas c, double lo, double hi) {
        Indicators.Series s = bars.series;
        float size = dp(5);
        for (int i = Math.max(1, from()); i < bars.size(); i++) {
            Rule.Snap p = s.snap(i - 1), l = s.snap(i);
            int g = Rule.count(Rule.golden(p, l, cfg)), d = Rule.count(Rule.dead(p, l, cfg));
            if (g == 3 || (twoOfThree && g == 2)) {
                float yy = y(bars.low[i], lo, hi) + dp(3);
                triangle(c, x(i), yy, size, true, up, g == 3);
            }
            if (d == 3 || (twoOfThree && d == 2)) {
                float yy = y(bars.high[i], lo, hi) - dp(3);
                triangle(c, x(i), yy, size, false, down, d == 3);
            }
        }
    }

    private void triangle(Canvas c, float cx, float tipY, float size, boolean pointUp, int color, boolean solid) {
        Path p = new Path();
        float dir = pointUp ? 1 : -1;
        p.moveTo(cx, tipY);
        p.lineTo(cx - size, tipY + dir * size * 1.6f);
        p.lineTo(cx + size, tipY + dir * size * 1.6f);
        p.close();
        fill.setColor(color);
        fill.setStyle(solid ? Paint.Style.FILL : Paint.Style.STROKE);
        fill.setStrokeWidth(dp(1.2f));
        c.drawPath(p, fill);
    }

    private void drawStoch(Canvas c) {
        double[] k = cfg.slow ? bars.series.kSlow : bars.series.kFast;
        double[] d = cfg.slow ? bars.series.dSlow : bars.series.dFast;
        bands(c, 0, 100, cfg.stochLo, cfg.stochHi, cfg.stochBand);
        gridAndAxis(c, 0, 100, 0, false);
        polyline(c, k, 0, 100, mainLine, dp(1.5f));
        polyline(c, d, 0, 100, sigLine, dp(1.2f));
        int i = at();
        header(c, (cfg.slow ? "Slow" : "Fast") + " 스토캐스틱 5-3-3",
                "%K " + fmt(k[i]), mainLine, "%D " + fmt(d[i]), sigLine);
    }

    private void drawRsi(Canvas c) {
        bands(c, 0, 100, cfg.rsiLo, cfg.rsiHi, cfg.rsiBand);
        gridAndAxis(c, 0, 100, 0, false);
        polyline(c, bars.series.rsi, 0, 100, mainLine, dp(1.5f));
        polyline(c, bars.series.rsiSig, 0, 100, sigLine, dp(1.2f));
        int i = at();
        header(c, "RSI 14 · 시그널 9", "RSI " + fmt(bars.series.rsi[i]), mainLine,
                "시그널 " + fmt(bars.series.rsiSig[i]), sigLine);
    }

    private void drawCci(Canvas c) {
        double[] v = bars.series.cci;
        double level = cfg.cciLevel, m = level * 1.3;
        for (int i = from(); i < bars.size(); i++) if (!Double.isNaN(v[i])) m = Math.max(m, Math.abs(v[i]) * 1.05);
        bands(c, -m, m, -level, level, true);
        dash.setColor(grid);
        c.drawLine(left(), y(0, -m, m), right(), y(0, -m, m), dash);
        gridAndAxis(c, -m, m, 0, false);
        polyline(c, v, -m, m, mainLine, dp(1.5f));
        header(c, "CCI 20", "CCI " + fmt(v[at()]), mainLine, null, 0);
    }

    /** Shaded zones beyond the two levels, with dashed lines and their labels on the axis. */
    private void bands(Canvas c, double lo, double hi, double low, double high, boolean active) {
        fill.setStyle(Paint.Style.FILL);
        fill.setColor(band);
        c.drawRect(left(), y(hi, lo, hi), right(), y(high, lo, hi), fill);
        c.drawRect(left(), y(low, lo, hi), right(), y(lo, lo, hi), fill);
        dash.setColor(active ? muted : grid);
        c.drawLine(left(), y(high, lo, hi), right(), y(high, lo, hi), dash);
        c.drawLine(left(), y(low, lo, hi), right(), y(low, lo, hi), dash);
        text.setColor(muted);
        c.drawText(fmtAxis(high), right() + dp(4), y(high, lo, hi) + sp(4), text);
        c.drawText(fmtAxis(low), right() + dp(4), y(low, lo, hi) + sp(4), text);
    }

    private void gridAndAxis(Canvas c, double lo, double hi, int lines, boolean labels) {
        line.setColor(grid);
        line.setStrokeWidth(dp(1));
        c.drawRect(left(), top(), right(), bottom(), line);
        for (int g = 1; g <= lines; g++) {
            double v = lo + (hi - lo) * g / (lines + 1);
            float yy = y(v, lo, hi);
            c.drawLine(left(), yy, right(), yy, line);
            if (labels) {
                text.setColor(muted);
                c.drawText(fmtAxis(v), right() + dp(4), yy + sp(4), text);
            }
        }
    }

    /** Grid lines at round prices (1, 2 or 5 × 10ⁿ apart), about four of them. */
    private void priceTicks(Canvas c, double lo, double hi) {
        double raw = (hi - lo) / 4, mag = Math.pow(10, Math.floor(Math.log10(raw))), f = raw / mag;
        double step = (f < 1.5 ? 1 : f < 3 ? 2 : f < 7 ? 5 : 10) * mag;
        line.setColor(grid);
        line.setStrokeWidth(dp(1));
        text.setColor(muted);
        for (double v = Math.ceil(lo / step) * step; v < hi; v += step) {
            float yy = y(v, lo, hi);
            c.drawLine(left(), yy, right(), yy, line);
            c.drawText(fmtAxis(v), right() + dp(4), yy + sp(4), text);
        }
    }

    private void polyline(Canvas c, double[] v, double lo, double hi, int color, float width) {
        Path p = new Path();
        boolean pen = false;
        for (int i = from(); i < bars.size(); i++) {
            if (Double.isNaN(v[i])) { pen = false; continue; }
            float yy = Math.max(top(), Math.min(bottom(), y(v[i], lo, hi)));
            if (pen) p.lineTo(x(i), yy); else p.moveTo(x(i), yy);
            pen = true;
        }
        line.setColor(color);
        line.setStrokeWidth(width);
        c.drawPath(p, line);
    }

    private void header(Canvas c, String title, String a, int ca, String b, int cb) {
        float yy = sp(13), xx = left();
        text.setColor(onSurface);
        text.setFakeBoldText(true);
        c.drawText(title, xx, yy, text);
        xx += text.measureText(title) + dp(10);
        text.setFakeBoldText(false);
        text.setColor(ca);
        c.drawText(a, xx, yy, text);
        if (b != null) {
            xx += text.measureText(a) + dp(8);
            text.setColor(cb);
            c.drawText(b, xx, yy, text);
        }
    }

    private static String fmt(double v) {
        return Double.isNaN(v) ? "-" : String.format(Locale.KOREA, "%.1f", v);
    }

    private static String fmtAxis(double v) {
        return Math.abs(v) >= 1000 ? String.format(Locale.KOREA, "%,.0f", v) : String.format(Locale.KOREA, "%.0f", v);
    }
}
