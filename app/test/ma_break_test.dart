// The scan marks moving-average breakouts with `mab`; the app files them under their own kind.
import 'package:flutter_test/flutter_test.dart';
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
    expect(hits.single.describe(), '이평선 밀집 돌파 (거래량 1.8배)');
    expect(Kind.maBreak.zone, isFalse);
    expect(Kind.byName('MA_BREAK'), Kind.maBreak);
  });

  test('no mab, no breakout', () {
    final s = Stock.parse(row());
    expect(s.maBreak, isNull);
    expect(hitsFor(s, RuleConfig(), 1), isEmpty);
  });
}
