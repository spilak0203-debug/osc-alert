package kr.personal.oscalert;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.DashPathEffect;
import android.graphics.Paint;
import android.graphics.Path;
import android.util.TypedValue;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
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

    static final int WINDOW = 120, MIN_BARS = 20;

    /** Zoom and scroll, shared by every panel of one stock so they move together. */
    static final class Viewport {
        int visible = WINDOW;              // bars on screen
        int end = Integer.MAX_VALUE;       // one past the last bar on screen; MAX_VALUE = pinned to the latest
    }

    private final Type type;
    private Bars bars;
    private Rule.Config cfg = new Rule.Config();
    private boolean showMa = true, showSignals = true, compact;
    /** Per bar: indicators matched on that signal day (0, 2 or 3) and where the matching span starts. */
    private int[] goldLevel, deadLevel, goldStart, deadStart;
    /** Per bar: which indicators crossed that day (stoch, rsi, cci), under the current rule. */
    private boolean[][] goldPart, deadPart;
    /** Per bar: every crossing of the two lines, band condition or not (stochastic and RSI only). */
    private boolean[][] goldCross, deadCross;
    private List<ChartView> group;
    private int selected = -1;
    private Viewport vp = new Viewport();
    private final ScaleGestureDetector scaler;
    private final GestureDetector gestures;

    private final Paint line = new Paint(Paint.ANTI_ALIAS_FLAG), fill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint text = new Paint(Paint.ANTI_ALIAS_FLAG), dash = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final int up, down, flat, onSurface, muted, grid, band, mainLine, sigLine, surface;
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
        surface = MaterialColors.getColor(c, com.google.android.material.R.attr.colorSurface, 0xFFFFFFFF);
        text.setTextSize(sp(11));
        line.setStyle(Paint.Style.STROKE);
        dash.setStyle(Paint.Style.STROKE);
        dash.setStrokeWidth(dp(1));
        dash.setPathEffect(new DashPathEffect(new float[]{dp(4), dp(3)}, 0));
        scaler = new ScaleGestureDetector(c, new ScaleGestureDetector.SimpleOnScaleGestureListener() {
            @Override
            public boolean onScaleBegin(ScaleGestureDetector d) {
                scaling = true;
                getParent().requestDisallowInterceptTouchEvent(true);
                return bars != null;
            }

            @Override
            public boolean onScale(ScaleGestureDetector d) {
                zoom(d.getScaleFactor(), d.getFocusX());
                return true;
            }
        });
        gestures = new GestureDetector(c, new GestureDetector.SimpleOnGestureListener() {
            @Override
            public boolean onDown(MotionEvent e) {
                return true;
            }

            @Override
            public boolean onSingleTapConfirmed(MotionEvent e) {
                selectAt(e.getX());
                return true;
            }

            @Override
            public boolean onDoubleTap(MotionEvent e) {
                vp.visible = WINDOW;
                vp.end = Integer.MAX_VALUE;
                if (group != null) for (ChartView v : group) v.select(-1); else select(-1);
                return true;
            }

            @Override
            public void onLongPress(MotionEvent e) {
                if (scaling || panning) return;
                crosshair = true;
                getParent().requestDisallowInterceptTouchEvent(true);
                selectAt(e.getX());
            }
        });
    }

    void setViewport(Viewport v) {
        vp = v;
        invalidate();
    }

    void bind(Bars bars, Rule.Config cfg, boolean showMa, boolean showSignals, List<ChartView> group) {
        this.bars = bars;
        this.cfg = cfg;
        this.showMa = showMa;
        this.showSignals = showSignals;
        this.group = group;
        selected = -1;
        if (bars != null && showSignals) annotate();
        invalidate();
    }

    /** A shorter candle panel for the index cards. */
    void setCompact(boolean compact) {
        this.compact = compact;
        requestLayout();
    }

    /** Runs the rule over every day so the chart shows exactly what the alerts would have said. */
    private void annotate() {
        int n = bars.size();
        goldLevel = new int[n]; deadLevel = new int[n]; goldStart = new int[n]; deadStart = new int[n];
        goldPart = new boolean[n][3]; deadPart = new boolean[n][3];
        goldCross = new boolean[n][3]; deadCross = new boolean[n][3];
        Rule.Config plain = new Rule.Config();
        plain.slow = cfg.slow;
        plain.stochBand = plain.rsiBand = false;
        Indicators.Series s = bars.series;
        for (int i = 1; i < n; i++) {
            goldPart[i] = Rule.golden(s.snap(i - 1), s.snap(i), cfg);
            deadPart[i] = Rule.dead(s.snap(i - 1), s.snap(i), cfg);
            goldCross[i] = Rule.golden(s.snap(i - 1), s.snap(i), plain);
            deadCross[i] = Rule.dead(s.snap(i - 1), s.snap(i), plain);
        }
        for (int i = 1; i < n; i++) {
            int from = Math.max(0, i - Rule.HISTORY + 1);
            Rule.Snap[] seq = new Rule.Snap[i - from + 1];
            for (int j = from; j <= i; j++) seq[j - from] = s.snap(j);
            boolean[][] m = Rule.match(seq, cfg);
            goldLevel[i] = level(m[0]);
            deadLevel[i] = level(m[1]);
            goldStart[i] = spanStart(i, m[0], goldPart);
            deadStart[i] = spanStart(i, m[1], deadPart);
        }
    }

    private static int level(boolean[] m) {
        int c = Rule.count(m);
        return c >= 2 ? c : 0;
    }

    /** First day inside the window on which one of the matched indicators crossed. */
    private int spanStart(int i, boolean[] matched, boolean[][] parts) {
        int start = i;
        for (int j = Math.max(1, i - cfg.window); j <= i; j++) {
            for (int p = 0; p < 3; p++) if (matched[p] && parts[j][p]) start = Math.min(start, j);
        }
        return start;
    }

    @Override
    protected void onMeasure(int w, int h) {
        int body = type == Type.CANDLE ? (compact ? 150 : 230) : 110;
        int height = (int) dp(body) + (int) sp(type == Type.CANDLE ? 30 : 16);
        setMeasuredDimension(MeasureSpec.getSize(w), height);
    }

    private float dp(float v) {
        return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics());
    }

    private float sp(float v) {
        return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, v, getResources().getDisplayMetrics());
    }

    // ---- geometry -------------------------------------------------------------------------

    private int shown() { return Math.max(2, Math.min(vp.visible, bars.size())); }

    /** One past the last bar on screen. */
    private int to() { return Math.max(shown(), Math.min(bars.size(), vp.end)); }

    private int from() { return to() - shown(); }

    private float left() { return dp(2); }

    /** The plot runs to the edge; axis labels are drawn inside it on a translucent backing. */
    private float right() { return getWidth() - dp(2); }

    private float top() { return sp(18); }

    private float bottom() { return getHeight() - (type == Type.CANDLE ? sp(16) : dp(4)); }

    private float step() { return (right() - left()) / Math.max(1, to() - from()); }

    private float x(int i) { return left() + (i - from() + 0.5f) * step(); }

    private float y(double v, double lo, double hi) {
        return (float) (bottom() - (v - lo) / (hi - lo) * (bottom() - top()));
    }

    // ---- touch ----------------------------------------------------------------------------

    private float downX, downY, panX;
    private int panEnd;
    private boolean panning, crosshair, scaling;

    /**
     * Two fingers zoom; a sideways drag scrolls through time; a tap or a long press then drag
     * shows a day's values; a double tap resets. A vertical drag is left to the list, so the
     * page still scrolls when the finger starts on a chart.
     */
    @Override
    public boolean onTouchEvent(MotionEvent e) {
        if (bars == null || bars.size() < 2) return false;
        scaler.onTouchEvent(e);
        gestures.onTouchEvent(e);
        int slop = ViewConfiguration.get(getContext()).getScaledTouchSlop();
        switch (e.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                downX = e.getX();
                downY = e.getY();
                panning = crosshair = scaling = false;
                return true;
            case MotionEvent.ACTION_POINTER_DOWN:
                scaling = true;
                getParent().requestDisallowInterceptTouchEvent(true);
                return true;
            case MotionEvent.ACTION_MOVE:
                if (scaling || e.getPointerCount() > 1) return true;
                if (crosshair) {
                    selectAt(e.getX());
                    return true;
                }
                float dx = Math.abs(e.getX() - downX), dy = Math.abs(e.getY() - downY);
                if (!panning && dx > slop && dx > dy) {
                    panning = true;
                    getParent().requestDisallowInterceptTouchEvent(true);
                    panX = e.getX();
                    panEnd = to();
                }
                if (panning) {
                    vp.end = clampEnd(panEnd + Math.round((panX - e.getX()) / step()));
                    redraw();
                }
                return true;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                getParent().requestDisallowInterceptTouchEvent(false);
                panning = crosshair = false;
                return true;
        }
        return super.onTouchEvent(e);
    }

    /** Keeps the day under the fingers in place while the number of bars on screen changes. */
    private void zoom(float factor, float focusX) {
        if (bars == null) return;
        int before = shown();
        int after = Math.max(Math.min(MIN_BARS, bars.size()), Math.min(bars.size(), Math.round(before / factor)));
        if (after == before) return;
        float ratio = Math.max(0, Math.min(1, (focusX - left()) / (right() - left())));
        double focus = from() + ratio * before;
        vp.visible = after;
        vp.end = clampEnd((int) Math.round(focus - ratio * after) + after);
        redraw();
    }

    /** Past the latest bar means "follow the latest". */
    private int clampEnd(int end) {
        if (end >= bars.size()) return Integer.MAX_VALUE;
        return Math.max(shown(), end);
    }

    private void redraw() {
        if (group != null) for (ChartView v : group) v.invalidate();
        else invalidate();
    }

    @Override
    public boolean performClick() {
        return super.performClick();
    }

    private void selectAt(float px) {
        int i = from() + (int) ((px - left()) / step());
        i = Math.max(from(), Math.min(to() - 1, i));
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
        int at = at();
        if (selected >= from() && selected < to()) {
            line.setColor(muted);
            line.setStrokeWidth(dp(1));
            c.drawLine(x(at), top(), x(at), bottom(), line);
        }
    }

    private int at() {
        return selected >= from() && selected < to() ? selected : to() - 1;
    }

    private void drawCandles(Canvas c) {
        int a = from(), n = to();
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
        spans(c);

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
        if (showSignals) markers(c, lo, hi);

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

    /** ▲ under golden matches and ▼ over dead ones: solid for 3 indicators, hollow for 2. */
    private void markers(Canvas c, double lo, double hi) {
        float size = dp(5);
        for (int i = Math.max(1, from()); i < to(); i++) {
            if (goldLevel[i] >= 2) triangle(c, x(i), y(bars.low[i], lo, hi) + dp(3), size, true, up, goldLevel[i] == 3);
            if (deadLevel[i] >= 2) triangle(c, x(i), y(bars.high[i], lo, hi) - dp(3), size, false, down, deadLevel[i] == 3);
        }
    }

    /** Shaded columns from the first matching crossing to the signal day; darker for 3 indicators. */
    private void spans(Canvas c) {
        if (!showSignals || goldLevel == null) return;
        fill.setStyle(Paint.Style.FILL);
        float half = step() / 2;
        for (int i = Math.max(1, from()); i < to(); i++) {
            if (goldLevel[i] >= 2) {
                fill.setColor(withAlpha(up, goldLevel[i] == 3 ? 0x40 : 0x1C));
                c.drawRect(x(Math.max(from(), goldStart[i])) - half, top(), x(i) + half, bottom(), fill);
            }
            if (deadLevel[i] >= 2) {
                fill.setColor(withAlpha(down, deadLevel[i] == 3 ? 0x40 : 0x1C));
                c.drawRect(x(Math.max(from(), deadStart[i])) - half, top(), x(i) + half, bottom(), fill);
            }
        }
    }

    /**
     * Dots on the oscillator's line: red for golden crosses and blue for dead ones — large when
     * the cross meets the band condition (counts toward signals), small otherwise — and hollow
     * rings where the line crosses a band level: red for oversold, blue for overbought.
     */
    private void crossings(Canvas c, int part, double[] v, double lo, double hi, double low, double high) {
        if (!showSignals || goldPart == null) return;
        float r = dp(3.5f);
        for (int i = Math.max(1, from()); i < to(); i++) {
            if (Double.isNaN(v[i]) || Double.isNaN(v[i - 1])) continue;
            float xx = x(i), yy = Math.max(top(), Math.min(bottom(), y(v[i], lo, hi)));
            boolean crossLow = (v[i - 1] < low) != (v[i] < low);
            boolean crossHigh = (v[i - 1] > high) != (v[i] > high);
            fill.setStrokeWidth(dp(1f));
            fill.setStyle(Paint.Style.STROKE);
            if (crossLow) {
                fill.setColor(up);
                c.drawCircle(xx, y(low, lo, hi), r - dp(1), fill);
            }
            if (crossHigh) {
                fill.setColor(down);
                c.drawCircle(xx, y(high, lo, hi), r - dp(1), fill);
            }
            fill.setStyle(Paint.Style.FILL);
            // Crossings that meet the band condition count toward signals: large dots.
            // Other crossings of the two lines: small, faint dots. (CCI's crossing is the band itself.)
            if (goldPart[i][part]) {
                fill.setColor(up);
                c.drawCircle(xx, yy, r, fill);
            } else if (part != Rule.CCI && goldCross[i][part]) {
                fill.setColor(withAlpha(up, 0xA0));
                c.drawCircle(xx, yy, r * 0.55f, fill);
            }
            if (deadPart[i][part]) {
                fill.setColor(down);
                c.drawCircle(xx, yy, r, fill);
            } else if (part != Rule.CCI && deadCross[i][part]) {
                fill.setColor(withAlpha(down, 0xA0));
                c.drawCircle(xx, yy, r * 0.55f, fill);
            }
        }
    }

    private static int withAlpha(int color, int alpha) {
        return (color & 0x00FFFFFF) | (alpha << 24);
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
        spans(c);
        gridAndAxis(c, 0, 100, 0, false);
        polyline(c, k, 0, 100, mainLine, dp(1.5f));
        polyline(c, d, 0, 100, sigLine, dp(1.2f));
        crossings(c, Rule.STOCH, k, 0, 100, cfg.stochLo, cfg.stochHi);
        int i = at();
        header(c, (cfg.slow ? "Slow" : "Fast") + " 스토캐스틱 5-3-3",
                "%K " + fmt(k[i]), mainLine, "%D " + fmt(d[i]), sigLine);
    }

    private void drawRsi(Canvas c) {
        bands(c, 0, 100, cfg.rsiLo, cfg.rsiHi, cfg.rsiBand);
        spans(c);
        gridAndAxis(c, 0, 100, 0, false);
        polyline(c, bars.series.rsi, 0, 100, mainLine, dp(1.5f));
        polyline(c, bars.series.rsiSig, 0, 100, sigLine, dp(1.2f));
        crossings(c, Rule.RSI, bars.series.rsi, 0, 100, cfg.rsiLo, cfg.rsiHi);
        int i = at();
        header(c, "RSI 14 · 시그널 9", "RSI " + fmt(bars.series.rsi[i]), mainLine,
                "시그널 " + fmt(bars.series.rsiSig[i]), sigLine);
    }

    private void drawCci(Canvas c) {
        double[] v = bars.series.cci;
        double level = cfg.cciLevel, m = level * 1.3;
        for (int i = from(); i < to(); i++) if (!Double.isNaN(v[i])) m = Math.max(m, Math.abs(v[i]) * 1.05);
        bands(c, -m, m, -level, level, true);
        spans(c);
        dash.setColor(grid);
        c.drawLine(left(), y(0, -m, m), right(), y(0, -m, m), dash);
        gridAndAxis(c, -m, m, 0, false);
        polyline(c, v, -m, m, mainLine, dp(1.5f));
        crossings(c, Rule.CCI, v, -m, m, -level, level);
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
        axisLabel(c, fmtAxis(high), y(high, lo, hi));
        axisLabel(c, fmtAxis(low), y(low, lo, hi), true);
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
                axisLabel(c, fmtAxis(v), yy);

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
            axisLabel(c, fmtAxis(v), yy);
        }
    }

    /** A value label at the right edge, just above its line, readable over candles and lines. */
    private void axisLabel(Canvas c, String s, float yy) {
        axisLabel(c, s, yy, false);
    }

    /** `below` puts the label under its line (used for the lower band so it never sits on the dashes). */
    private void axisLabel(Canvas c, String s, float yy, boolean below) {
        float w = text.measureText(s), h = sp(11);
        float x1 = right() - w - dp(4), y1 = below ? yy + h + dp(2) : yy - dp(2);
        if (!below && y1 - h < top()) y1 = yy + h + dp(2);        // no room above: put it below
        if (below && y1 > bottom()) y1 = yy - dp(2);
        fill.setStyle(Paint.Style.FILL);
        fill.setColor((surface & 0x00FFFFFF) | 0xCC000000);
        c.drawRect(x1 - dp(2), y1 - h, right() - dp(1), y1 + dp(2), fill);
        text.setColor(muted);
        c.drawText(s, x1, y1, text);
    }

    private void polyline(Canvas c, double[] v, double lo, double hi, int color, float width) {
        Path p = new Path();
        boolean pen = false;
        for (int i = from(); i < to(); i++) {
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
