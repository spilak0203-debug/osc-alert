// indicators.dart must reproduce pandas (fixtures from tests/make_fixtures.py).
import 'package:flutter_test/flutter_test.dart';
import 'package:oscalert/core/fmt.dart';
import 'package:oscalert/core/indicators.dart';

import 'rule_test.dart' show fixture;

List<double> arr(List a) => [for (final v in a) v == null ? double.nan : (v as num).toDouble()];

void same(String name, List<double> want, List<double> got) {
  final offset = got.length - want.length;
  for (var i = 0; i < want.length; i++) {
    final w = want[i], g = got[offset + i];
    if (w.isNaN) {
      expect(g.isNaN, isTrue, reason: '$name @$i expected NaN, got $g');
    } else {
      expect(g, closeTo(w, 1e-6 * (w.abs() > 1 ? w.abs() : 1)), reason: '$name @$i');
    }
  }
}

void main() {
  test('matches pandas', () {
    final data = fixture('indicator_series.json') as Map;
    final s = compute(arr(data['high']), arr(data['low']), arr(data['close']));
    final e = data['expected'] as Map;
    same('k_fast', arr(e['k_fast']), s.kFast);
    same('d_fast', arr(e['d_fast']), s.dFast);
    same('k_slow', arr(e['k_slow']), s.kSlow);
    same('d_slow', arr(e['d_slow']), s.dSlow);
    same('rsi', arr(e['rsi']), s.rsi);
    same('rsi_sig', arr(e['rsi_sig']), s.rsiSig);
    same('cci', arr(e['cci']), s.cci);
    for (var m = 0; m < maPeriods.length; m++) {
      same('ma${maPeriods[m]}', arr(e['ma${maPeriods[m]}']), s.ma[m]);
    }
  });

  test('formats like Java', () {
    expect(price(1863000), '1,863,000원');
    expect(percent(3.62), '+3.62%');
    expect(percent(-0.97), '-0.97%');
    expect(percent(0), '+0.00%');
    expect(compact(19390000), '1,939만');
    expect(compact(4.4e12), '4.4조');
    expect(compact(1675.0 * 1e8 * 1e4), '1675.0조');
    expect(compactNumber(16620000), '1,662만');
    expect(signed(63.01), '+63.01');
    expect(grouped(7080.92, 2), '7,080.92');
    expect(eok(1000), '1,000억');
    expect(eok(10000), '1조');
  });
}
