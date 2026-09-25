// The scan marks moving-average breakouts with `mab`; the app files them under their own kind.
import 'package:flutter_test/flutter_test.dart';
import 'package:oscalert/core/indicators.dart';
import 'package:oscalert/core/rule.dart';
import 'package:oscalert/core/signals.dart';
import 'package:oscalert/core/stock.dart';

Map<String, dynamic> row([List<num>? mab]) => {
      't': '033780',
      'n': 'KT&G',
      'm': 'KS',
      'k_fast': [50, 52], 'd_fast': [50, 51], 'k_slow': [50, 51], 'd_slow': [50, 51],
      'rsi': [50, 51], 'rsi_sig': [50, 50], 'cci': [0, 10],
      'mab': ?mab,
    };

void main() {
  test('mab becomes a breakout hit with the volume', () {
    final s = Stock.parse(row([1.87, 1.78]));
    expect(s.maBreak, (1.87, 1.78));
    final hits = hitsFor(s, RuleConfig(), 1);
    expect(hits.map((h) => h.kind), [Kind.maBreak]);
    expect(hits.single.describe(), '이평선 밀집 돌파');
    expect(hits.single.chip(), '이평선 돌파');
    expect(Kind.maBreak.zone, isFalse);
    expect(Kind.byName('MA_BREAK'), Kind.maBreak);
  });

  test('volume surge counts only for liquid stocks, and overlaps stack', () {
    final s = Stock.parse({...row([1.0, 1.0]), 'vr': 4.2, 'dv20': 6e8});
    final hits = hitsFor(s, RuleConfig(), 1);
    expect(hits.map((h) => h.kind), [Kind.surge, Kind.maBreak]);
    expect(hits.first.chip(), '거래량 4.2배');
    expect(overlap(hits), 2);
    expect(rank(Kind.combo2, s), 1);
    final thin = Stock.parse({...row(), 'vr': 4.2, 'dv20': 1e8});
    expect(hitsFor(thin, RuleConfig(), 1), isEmpty);
  });

  // Same cases as tests/test_indicators.py MaBreakout, for the chart's ◆.
  List<bool> marks(List<double> close) =>
      maBreakouts([for (final n in maPeriods) sma(close, n)], close, List.filled(close.length, 1e7));

  test('chart: flat then a break is marked on that day only', () {
    final m = marks([...List.filled(130, 100.0), 104.0]);
    expect([for (var i = 0; i < m.length; i++) if (m[i]) i], [130]);
  });

  test('chart: no mark without convergence or with falling long averages', () {
    expect(marks([...List.filled(100, 200.0), ...List.filled(30, 100.0), 104.0]).contains(true), isFalse);
    expect(marks([for (var i = 0; i < 130; i++) 103.0 - i * 0.025, 104.0]).last, isFalse);
  });

  test('no mab, no breakout', () {
    final s = Stock.parse(row());
    expect(s.maBreak, isNull);
    expect(hitsFor(s, RuleConfig(), 1), isEmpty);
  });
}
