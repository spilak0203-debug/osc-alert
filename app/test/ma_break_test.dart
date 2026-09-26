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
    final s = Stock.parse(row([1.2, 1.78]));
    expect(s.maBreak, (spread: 1.2, volume: 1.78, up60: true, up120: true));
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
    expect(marks([for (var i = 0; i < 130; i++) 101.0 - i * 0.01, 102.0]).last, isFalse);
  });

  test('two of three counts only while pairs are on', () {
    // Stochastic and RSI cross up, CCI does not.
    final s = Stock.parse({
      't': '000001', 'n': 'x', 'm': 'KS',
      'k_fast': [40, 55], 'd_fast': [50, 50], 'k_slow': [40, 55], 'd_slow': [50, 50],
      'rsi': [50, 51], 'rsi_sig': [50, 50], 'cci': [0, 10],
    });
    final c = RuleConfig()
      ..stochBand = false
      ..rsiBand = false;
    expect(hitsFor(s, c, 3).map((h) => h.kind), [Kind.gold2]);
    expect(hitsFor(s, c..pairs = false, 3), isEmpty);
  });

  test('the long-average condition comes from the settings', () {
    // A breakout with the 60-day average rising and the 120-day one falling.
    final s = Stock.parse({...row(), 'mb': [1.2, 1.0, 1, 0]});
    expect(hitsFor(s, RuleConfig(), 1), isEmpty); // default: both must rise
    expect(hitsFor(s, RuleConfig()..maUp120 = false, 1).map((h) => h.kind), [Kind.maBreak]);
    expect(hitsFor(s, RuleConfig()..maUp60 = false, 1), isEmpty);
    expect(hitsFor(s, RuleConfig()..maUp60 = false..maUp120 = false, 1).map((h) => h.kind), [Kind.maBreak]);
  });

  test('chart: falling long averages are marked once the condition is off', () {
    final close = [for (var i = 0; i < 130; i++) 101.0 - i * 0.01, 102.0];
    final ma = [for (final n in maPeriods) sma(close, n)];
    final volume = List.filled(close.length, 1e7);
    expect(maBreakouts(ma, close, volume).last, isFalse);
    expect(maBreakouts(ma, close, volume, up60: false, up120: false).last, isTrue);
  });

  test('the spread comes from the settings', () {
    final s = Stock.parse({...row(), 'mb': [2.4, 1.0, 1, 1]});
    expect(hitsFor(s, RuleConfig(), 1), isEmpty); // default 1.5%
    expect(hitsFor(s, RuleConfig()..maSpread = 3, 1).map((h) => h.kind), [Kind.maBreak]);
    // The chart: a 2.9% gap between the averages the day before.
    final close = [...List.filled(125, 100.0), 104.0, 104.0, 104.0, 104.0, 104.0, 99.0, 108.0];
    final ma = [for (final n in maPeriods) sma(close, n)];
    final volume = List.filled(close.length, 1e7);
    expect(maBreakouts(ma, close, volume, up60: false, up120: false).last, isFalse);
    expect(maBreakouts(ma, close, volume, up60: false, up120: false, spread: 0.03).last, isTrue);
  });

  test('no mab, no breakout', () {
    final s = Stock.parse(row());
    expect(s.maBreak, isNull);
    expect(hitsFor(s, RuleConfig(), 1), isEmpty);
  });
}
