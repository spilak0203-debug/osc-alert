/// Confluence rule from consecutive days of indicator values. Port of `signal/rule.py`;
/// `test/rule_test.dart` checks it against Python's answers. Missing values are NaN, and every
/// comparison with NaN is false — the same as pandas.
library;

const int maxWindow = 4;

/// Days of values needed to evaluate the largest window: window + signal day + the day before.
const int history = maxWindow + 2;

/// Index order of the three parts.
const int stoch = 0, rsiPart = 1, cciPart = 2;

class RuleConfig {
  bool slow = true;
  bool stochBand = true, rsiBand = true, cciBand = true;
  double stochLo = 20, stochHi = 80, rsiLo = 30, rsiHi = 70, cciLevel = 100;

  /// An indicator counts if it crossed on the signal day or up to this many days before.
  int window = 0;

  /// Two of the three indicators are a signal too; off, only all three are.
  bool pairs = true;

  /// Fewest indicators that make a golden or dead signal.
  int get need => pairs ? 2 : 3;

  RuleConfig copy() => RuleConfig()
    ..slow = slow
    ..stochBand = stochBand
    ..rsiBand = rsiBand
    ..cciBand = cciBand
    ..stochLo = stochLo
    ..stochHi = stochHi
    ..rsiLo = rsiLo
    ..rsiHi = rsiHi
    ..cciLevel = cciLevel
    ..window = window
    ..pairs = pairs;

  /// The same rule without the stochastic and RSI band conditions: every crossing of the lines.
  RuleConfig plain() => copy()
    ..stochBand = false
    ..rsiBand = false;
}

/// One day of indicator values.
class Snap {
  double kFast = double.nan, dFast = double.nan, kSlow = double.nan, dSlow = double.nan;
  double rsi = double.nan, rsiSig = double.nan, cci = double.nan;

  double k(RuleConfig c) => c.slow ? kSlow : kFast;
  double d(RuleConfig c) => c.slow ? dSlow : dFast;
}

bool _up(double a0, double a1, double b0, double b1) => a1 > b1 && a0 <= b0;

bool _dn(double a0, double a1, double b0, double b1) => a1 < b1 && a0 >= b0;

/// Golden parts (stoch, rsi, cci) crossing between `prev` and `last`.
List<bool> golden(Snap prev, Snap last, RuleConfig c) {
  final k0 = prev.k(c), k1 = last.k(c), d0 = prev.d(c), d1 = last.d(c);
  final lv = c.cciBand ? c.cciLevel : 0.0;
  return [
    _up(k0, k1, d0, d1) && (!c.stochBand || k0 < c.stochLo),
    _up(prev.rsi, last.rsi, prev.rsiSig, last.rsiSig) && (!c.rsiBand || prev.rsi < c.rsiLo),
    _up(prev.cci, last.cci, -lv, -lv),
  ];
}

List<bool> dead(Snap prev, Snap last, RuleConfig c) {
  final k0 = prev.k(c), k1 = last.k(c), d0 = prev.d(c), d1 = last.d(c);
  final lv = c.cciBand ? c.cciLevel : 0.0;
  return [
    _dn(k0, k1, d0, d1) && (!c.stochBand || k0 > c.stochHi),
    _dn(prev.rsi, last.rsi, prev.rsiSig, last.rsiSig) && (!c.rsiBand || prev.rsi > c.rsiHi),
    _dn(prev.cci, last.cci, lv, lv),
  ];
}

/// Signal on the last day of `seq` (oldest first): [golden, dead], each three booleans telling
/// whether that indicator crossed within the window. A side with no crossing on the last day
/// is all false, so a signal fires once — on the day the last indicator joins.
List<List<bool>> match(List<Snap> seq, RuleConfig c) {
  final n = seq.length;
  final out = [List.filled(3, false), List.filled(3, false)];
  if (n < 2) return out;
  final first = (n - 1 - c.window) < 1 ? 1 : n - 1 - c.window;
  final today = [golden(seq[n - 2], seq[n - 1], c), dead(seq[n - 2], seq[n - 1], c)];
  for (var i = first; i < n; i++) {
    final g = i == n - 1 ? today[0] : golden(seq[i - 1], seq[i], c);
    final d = i == n - 1 ? today[1] : dead(seq[i - 1], seq[i], c);
    for (var j = 0; j < 3; j++) {
      out[0][j] = out[0][j] || g[j];
      out[1][j] = out[1][j] || d[j];
    }
  }
  for (var side = 0; side < 2; side++) {
    if (count(today[side]) == 0) out[side] = List.filled(3, false);
  }
  return out;
}

/// How many of the three indicators are oversold (index 0) and overbought (index 1).
List<int> zones(Snap s, RuleConfig c) {
  final k = s.k(c);
  final low = (k < c.stochLo ? 1 : 0) + (s.rsi < c.rsiLo ? 1 : 0) + (s.cci < -c.cciLevel ? 1 : 0);
  final high = (k > c.stochHi ? 1 : 0) + (s.rsi > c.rsiHi ? 1 : 0) + (s.cci > c.cciLevel ? 1 : 0);
  return [low, high];
}

int count(List<bool> parts) => parts.where((b) => b).length;
