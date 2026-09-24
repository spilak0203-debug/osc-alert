package kr.personal.oscalert;

/**
 * Indicator series for the charts. Port of `signal/indicators.py`; `IndicatorsTest` checks
 * it against pandas. Windows that contain a missing value give NaN, like `rolling(n).mean()`.
 */
public final class Indicators {
    private Indicators() {}

    public static final int STOCH_N = 5, STOCH_D = 3, RSI_N = 14, RSI_SIG = 9, CCI_N = 20;
    public static final int[] MA = {5, 20, 60, 120};

    public static final class Series {
        public double[] kFast, dFast, kSlow, dSlow, rsi, rsiSig, cci;
        public double[][] ma = new double[MA.length][];

        public Rule.Snap snap(int i) {
            Rule.Snap s = new Rule.Snap();
            s.kFast = kFast[i]; s.dFast = dFast[i]; s.kSlow = kSlow[i]; s.dSlow = dSlow[i];
            s.rsi = rsi[i]; s.rsiSig = rsiSig[i]; s.cci = cci[i];
            return s;
        }
    }

    public static Series compute(double[] high, double[] low, double[] close) {
        Series s = new Series();
        s.kFast = fastK(high, low, close, STOCH_N);
        s.dFast = sma(s.kFast, STOCH_D);
        s.kSlow = s.dFast;
        s.dSlow = sma(s.kSlow, STOCH_D);
        double[][] r = rsi(close, RSI_N);
        s.rsi = r[0];
        s.rsiSig = sma(s.rsi, RSI_SIG);
        s.cci = cci(high, low, close, CCI_N);
        for (int m = 0; m < MA.length; m++) s.ma[m] = sma(close, MA[m]);
        return s;
    }

    public static double[] sma(double[] x, int n) {
        double[] out = nan(x.length);
        for (int i = n - 1; i < x.length; i++) {
            double sum = 0;
            boolean ok = true;
            for (int j = i - n + 1; j <= i; j++) {
                if (Double.isNaN(x[j])) { ok = false; break; }
                sum += x[j];
            }
            if (ok) out[i] = sum / n;
        }
        return out;
    }

    static double[] fastK(double[] h, double[] l, double[] c, int n) {
        double[] out = nan(c.length);
        for (int i = n - 1; i < c.length; i++) {
            double hh = Double.NEGATIVE_INFINITY, ll = Double.POSITIVE_INFINITY;
            boolean ok = true;
            for (int j = i - n + 1; j <= i; j++) {
                if (Double.isNaN(h[j]) || Double.isNaN(l[j])) { ok = false; break; }
                hh = Math.max(hh, h[j]);
                ll = Math.min(ll, l[j]);
            }
            double range = hh - ll;
            if (ok && range != 0) out[i] = (c[i] - ll) / range * 100;
        }
        return out;
    }

    /** Wilder smoothing: `ewm(alpha=1/n, adjust=False)` starting at the first difference. */
    static double[][] rsi(double[] c, int n) {
        double[] out = nan(c.length);
        double a = 1.0 / n, up = Double.NaN, down = Double.NaN;
        for (int i = 1; i < c.length; i++) {
            double delta = c[i] - c[i - 1];
            if (Double.isNaN(delta)) continue;
            double u = Math.max(delta, 0), d = Math.max(-delta, 0);
            if (Double.isNaN(up)) { up = u; down = d; }
            else { up = (1 - a) * up + a * u; down = (1 - a) * down + a * d; }
            if (down != 0) out[i] = 100 - 100 / (1 + up / down);
        }
        return new double[][]{out};
    }

    /** Matches `(tp - sma) / (0.015 * mean(|tp - sma|))` where each deviation uses its own day's sma. */
    static double[] cci(double[] h, double[] l, double[] c, int n) {
        double[] tp = new double[c.length];
        for (int i = 0; i < c.length; i++) tp[i] = (c[i] + h[i] + l[i]) / 3;
        double[] mean = sma(tp, n);
        double[] dev = new double[c.length];
        for (int i = 0; i < c.length; i++) dev[i] = Math.abs(tp[i] - mean[i]);
        double[] mad = sma(dev, n);
        double[] out = nan(c.length);
        for (int i = 0; i < c.length; i++) {
            if (!Double.isNaN(mad[i]) && mad[i] != 0) out[i] = (tp[i] - mean[i]) / (0.015 * mad[i]);
        }
        return out;
    }

    private static double[] nan(int n) {
        double[] out = new double[n];
        java.util.Arrays.fill(out, Double.NaN);
        return out;
    }
}
