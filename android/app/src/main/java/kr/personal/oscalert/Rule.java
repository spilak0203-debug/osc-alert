package kr.personal.oscalert;

/**
 * Confluence rule from two consecutive days of indicator values. Port of `signal/rule.py`;
 * `RuleTest` checks it against Python's answers. Missing values are NaN, and every
 * comparison with NaN is false — the same as pandas.
 */
public final class Rule {
    private Rule() {}

    public static final class Config {
        public boolean slow = true;
        public boolean stochBand = true, rsiBand = true, cciBand = true;
        public double stochLo = 20, stochHi = 80, rsiLo = 30, rsiHi = 70, cciLevel = 100;
    }

    /** One day of indicator values. */
    public static final class Snap {
        public double kFast = Double.NaN, dFast = Double.NaN, kSlow = Double.NaN, dSlow = Double.NaN;
        public double rsi = Double.NaN, rsiSig = Double.NaN, cci = Double.NaN;

        double k(Config c) { return c.slow ? kSlow : kFast; }
        double d(Config c) { return c.slow ? dSlow : dFast; }
    }

    /** Index order of the three parts. */
    public static final int STOCH = 0, RSI = 1, CCI = 2;

    private static boolean up(double a0, double a1, double b0, double b1) {
        return a1 > b1 && a0 <= b0;
    }

    private static boolean dn(double a0, double a1, double b0, double b1) {
        return a1 < b1 && a0 >= b0;
    }

    /** Golden parts (stoch, rsi, cci) crossing between `prev` and `last`. */
    public static boolean[] golden(Snap prev, Snap last, Config c) {
        double k0 = prev.k(c), k1 = last.k(c), d0 = prev.d(c), d1 = last.d(c);
        double lv = c.cciBand ? c.cciLevel : 0;
        return new boolean[]{
                up(k0, k1, d0, d1) && (!c.stochBand || k0 < c.stochLo),
                up(prev.rsi, last.rsi, prev.rsiSig, last.rsiSig) && (!c.rsiBand || prev.rsi < c.rsiLo),
                up(prev.cci, last.cci, -lv, -lv)};
    }

    public static boolean[] dead(Snap prev, Snap last, Config c) {
        double k0 = prev.k(c), k1 = last.k(c), d0 = prev.d(c), d1 = last.d(c);
        double lv = c.cciBand ? c.cciLevel : 0;
        return new boolean[]{
                dn(k0, k1, d0, d1) && (!c.stochBand || k0 > c.stochHi),
                dn(prev.rsi, last.rsi, prev.rsiSig, last.rsiSig) && (!c.rsiBand || prev.rsi > c.rsiHi),
                dn(prev.cci, last.cci, lv, lv)};
    }

    /** How many of the three indicators are oversold (index 0) and overbought (index 1). */
    public static int[] zones(Snap s, Config c) {
        double k = s.k(c);
        int low = (k < c.stochLo ? 1 : 0) + (s.rsi < c.rsiLo ? 1 : 0) + (s.cci < -c.cciLevel ? 1 : 0);
        int high = (k > c.stochHi ? 1 : 0) + (s.rsi > c.rsiHi ? 1 : 0) + (s.cci > c.cciLevel ? 1 : 0);
        return new int[]{low, high};
    }

    public static int count(boolean[] parts) {
        int n = 0;
        for (boolean b : parts) if (b) n++;
        return n;
    }
}
