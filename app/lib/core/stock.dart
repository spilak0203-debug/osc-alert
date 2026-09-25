import 'rule.dart';

/// One row of market.json plus the live quote, if one has been fetched.
class Stock {
  static const _keys = ['k_fast', 'd_fast', 'k_slow', 'd_slow', 'rsi', 'rsi_sig', 'cci'];

  String ticker = '', name = '', market = '';
  double cap = double.nan, close = double.nan, change = double.nan, volume = double.nan, dv20 = double.nan;

  /// Indicator values for the last few days up to the signal day, oldest first; null if not traded.
  List<Snap>? seq;

  /// Moving-average breakout on the signal day (worked out by the scan): the four averages'
  /// spread the day before (% of the close), the day's volume ÷ its 20-day average, and whether
  /// the 60- and 120-day averages are rising (the settings pick which of those must hold).
  ({double spread, double volume, bool up60, bool up120})? maBreak;

  /// Signal-day volume ÷ the previous trading day's (NaN if unknown).
  double volumeTimes = double.nan;

  // Live quote (NaN until fetched)
  double livePrice = double.nan, liveChange = double.nan, liveVolume = double.nan;

  static Stock parse(Map<String, dynamic> o) {
    final s = Stock()
      ..ticker = '${o['t'] ?? ''}'
      ..name = '${o['n'] ?? ''}'
      ..market = o['m'] == 'KS' ? '코스피' : '코스닥'
      ..cap = value(o['cap'])
      ..close = value(o['close'])
      ..change = value(o['chg'])
      ..volume = value(o['vol'])
      ..dv20 = value(o['dv20']);
    // `mb` (every breakout, with the rising flags); older snapshots only have `mab`, which is a
    // breakout with both long averages rising.
    final mb = o['mb'], mab = o['mab'];
    if (mb is List && mb.length >= 4) {
      s.maBreak = (spread: value(mb[0]), volume: value(mb[1]), up60: mb[2] == 1, up120: mb[3] == 1);
    } else if (mab is List && mab.length >= 2) {
      s.maBreak = (spread: value(mab[0]), volume: value(mab[1]), up60: true, up120: true);
    }
    s.volumeTimes = value(o['vr']);
    final first = o['rsi'];
    if (first is List && first.length >= 2) {
      final n = first.length;
      final seq = List.generate(n, (_) => Snap());
      for (var f = 0; f < _keys.length; f++) {
        final a = o[_keys[f]];
        for (var i = 0; i < n; i++) {
          final v = a is List && i < a.length ? value(a[i]) : double.nan;
          _set(seq[i], f, v);
        }
      }
      s.seq = seq;
    }
    return s;
  }

  static double value(Object? v) => v is num ? v.toDouble() : double.nan;

  static void _set(Snap s, int field, double v) {
    switch (field) {
      case 0:
        s.kFast = v;
      case 1:
        s.dFast = v;
      case 2:
        s.kSlow = v;
      case 3:
        s.dSlow = v;
      case 4:
        s.rsi = v;
      case 5:
        s.rsiSig = v;
      default:
        s.cci = v;
    }
  }

  Snap? prev() => seq == null ? null : seq![seq!.length - 2];

  Snap? last() => seq == null ? null : seq![seq!.length - 1];

  double price() => livePrice.isNaN ? close : livePrice;

  double changePct() => livePrice.isNaN ? change : liveChange;

  double tradedVolume() => livePrice.isNaN ? volume : liveVolume;

  String naverChartUrl() => 'https://m.stock.naver.com/fchart/domestic/stock/$ticker';
}
