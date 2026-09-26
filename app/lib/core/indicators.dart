/// Indicator series for the charts. Port of `signal/indicators.py`; `test/indicators_test.dart`
/// checks it against pandas. Windows that contain a missing value give NaN, like
/// `rolling(n).mean()`.
library;

import 'rule.dart';

const int stochN = 5, stochD = 3, rsiN = 14, rsiSig = 9, cciN = 14;
const List<int> maPeriods = [5, 20, 60, 120];

class Series {
  late List<double> kFast, dFast, kSlow, dSlow, rsi, rsiSig, cci;
  final List<List<double>> ma = [];

  Snap snap(int i) => Snap()
    ..kFast = kFast[i]
    ..dFast = dFast[i]
    ..kSlow = kSlow[i]
    ..dSlow = dSlow[i]
    ..rsi = rsi[i]
    ..rsiSig = rsiSig[i]
    ..cci = cci[i];
}

Series compute(List<double> high, List<double> low, List<double> close) {
  final s = Series();
  s.kFast = fastK(high, low, close, stochN);
  s.dFast = sma(s.kFast, stochD);
  s.kSlow = s.dFast;
  s.dSlow = sma(s.kSlow, stochD);
  s.rsi = rsiLine(close, rsiN);
  s.rsiSig = sma(s.rsi, rsiSig);
  s.cci = cciLine(high, low, close, cciN);
  for (final m in maPeriods) {
    s.ma.add(sma(close, m));
  }
  return s;
}

/// Moving-average breakout, as the scan marks it (`ma_breakout` in signal/indicators.py): the
/// day before, the four averages sat within `spread` (a fraction) of the close; today the close is above
/// all four for the first time; the 60- and/or 120-day average (as `up60`/`up120` ask) is not
/// lower than `maSlope` days ago; and the stock trades at least `maLiquidity` won a day
/// (20-day average before today).
const double maSpread = 0.015, maLiquidity = 5e8;
const int maSlope = 5;

List<bool> maBreakouts(List<List<double>> ma, List<double> close, List<double> volume,
    {bool up60 = true, bool up120 = true, double spread = maSpread}) {
  final n = close.length;
  final out = List<bool>.filled(n, false);
  double top(int i) => [for (final m in ma) m[i]].reduce((a, b) => a > b ? a : b);
  double bottom(int i) => [for (final m in ma) m[i]].reduce((a, b) => a < b ? a : b);
  bool ready(int i) => i >= 0 && ma.every((m) => !m[i].isNaN);
  final traded = [for (var i = 0; i < n; i++) close[i] * volume[i]];
  final dv20 = sma(traded, 20);
  for (var i = maSlope; i < n; i++) {
    if (!ready(i) || !ready(i - 1) || !ready(i - maSlope)) continue;
    if (!(dv20[i - 1] >= maLiquidity)) continue;
    final gathered = (top(i - 1) - bottom(i - 1)) / close[i - 1] <= spread;
    final crossed = close[i] > top(i) && close[i - 1] <= top(i - 1);
    final rising = (!up60 || ma[2][i] >= ma[2][i - maSlope]) && (!up120 || ma[3][i] >= ma[3][i - maSlope]);
    out[i] = gathered && crossed && rising;
  }
  return out;
}

List<double> _nan(int n) => List<double>.filled(n, double.nan);

List<double> sma(List<double> x, int n) {
  final out = _nan(x.length);
  for (var i = n - 1; i < x.length; i++) {
    var sum = 0.0;
    var ok = true;
    for (var j = i - n + 1; j <= i; j++) {
      if (x[j].isNaN) {
        ok = false;
        break;
      }
      sum += x[j];
    }
    if (ok) out[i] = sum / n;
  }
  return out;
}

List<double> fastK(List<double> h, List<double> l, List<double> c, int n) {
  final out = _nan(c.length);
  for (var i = n - 1; i < c.length; i++) {
    var hh = double.negativeInfinity, ll = double.infinity;
    var ok = true;
    for (var j = i - n + 1; j <= i; j++) {
      if (h[j].isNaN || l[j].isNaN) {
        ok = false;
        break;
      }
      if (h[j] > hh) hh = h[j];
      if (l[j] < ll) ll = l[j];
    }
    final range = hh - ll;
    if (ok && range != 0) out[i] = (c[i] - ll) / range * 100;
  }
  return out;
}

/// Wilder smoothing: `ewm(alpha=1/n, adjust=False)` starting at the first difference.
List<double> rsiLine(List<double> c, int n) {
  final out = _nan(c.length);
  final a = 1.0 / n;
  var up = double.nan, down = double.nan;
  for (var i = 1; i < c.length; i++) {
    final delta = c[i] - c[i - 1];
    if (delta.isNaN) continue;
    final u = delta > 0 ? delta : 0.0, d = delta < 0 ? -delta : 0.0;
    if (up.isNaN) {
      up = u;
      down = d;
    } else {
      up = (1 - a) * up + a * u;
      down = (1 - a) * down + a * d;
    }
    if (down != 0) out[i] = 100 - 100 / (1 + up / down);
  }
  return out;
}

/// Matches `(tp - sma) / (0.015 * mean(|tp - sma|))` where each deviation uses its own day's sma.
/// Lambert's CCI, as brokers' charts draw it: the mean deviation is how far each of the last n
/// typical prices is from **today's** n-day average.
List<double> cciLine(List<double> h, List<double> l, List<double> c, int n) {
  final tp = List<double>.generate(c.length, (i) => (c[i] + h[i] + l[i]) / 3);
  final mean = sma(tp, n);
  final out = _nan(c.length);
  for (var i = n - 1; i < c.length; i++) {
    if (mean[i].isNaN) continue;
    var dev = 0.0;
    for (var j = i - n + 1; j <= i; j++) {
      dev += (tp[j] - mean[i]).abs();
    }
    dev /= n;
    if (dev != 0) out[i] = (tp[i] - mean[i]) / (0.015 * dev);
  }
  return out;
}
