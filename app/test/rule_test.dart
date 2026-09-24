// rule.dart must give the same answers as signal/rule.py (fixtures from tests/make_fixtures.py).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oscalert/core/rule.dart';

dynamic fixture(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

double val(Map o, String key) => o[key] == null ? double.nan : (o[key] as num).toDouble();

Snap snap(Map o) => Snap()
  ..kFast = val(o, 'k_fast')
  ..dFast = val(o, 'd_fast')
  ..kSlow = val(o, 'k_slow')
  ..dSlow = val(o, 'd_slow')
  ..rsi = val(o, 'rsi')
  ..rsiSig = val(o, 'rsi_sig')
  ..cci = val(o, 'cci');

RuleConfig config(Map o) => RuleConfig()
  ..slow = (o['stoch'] ?? 'slow') != 'fast'
  ..stochBand = o['stoch_band'] ?? true
  ..rsiBand = o['rsi_band'] ?? true
  ..cciBand = o['cci_band'] ?? true
  ..stochLo = (o['stoch_lo'] ?? 20).toDouble()
  ..stochHi = (o['stoch_hi'] ?? 80).toDouble()
  ..rsiLo = (o['rsi_lo'] ?? 30).toDouble()
  ..rsiHi = (o['rsi_hi'] ?? 70).toDouble()
  ..cciLevel = (o['cci_level'] ?? 100).toDouble()
  ..window = o['window'] ?? 0;

void main() {
  test('matches Python', () {
    final data = fixture('rule_cases.json') as Map;
    final configs = data['configs'] as List, cases = data['cases'] as List;
    expect(cases.length, greaterThan(500));
    var fired = 0;
    for (var i = 0; i < cases.length; i++) {
      final k = cases[i] as Map;
      final c = config(configs[k['config']] as Map);
      final seq = [for (final s in k['seq'] as List) snap(s as Map)];
      final m = match(seq, c);
      expect(m[0], List<bool>.from(k['golden']), reason: 'case $i golden');
      expect(m[1], List<bool>.from(k['dead']), reason: 'case $i dead');
      expect(zones(seq.last, c), List<int>.from(k['zones']), reason: 'case $i zones');
      if (count(m[0]) == 3) fired++;
    }
    expect(fired, greaterThan(0), reason: 'fixture should contain full confluences');
  });

  test('NaN never fires', () {
    final empty = Snap();
    final c = RuleConfig();
    expect(count(golden(empty, empty, c)), 0);
    expect(count(dead(empty, empty, c)), 0);
    expect(zones(empty, c), [0, 0]);
  });
}
