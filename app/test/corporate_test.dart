// Corporate actions from the scan (`ca`): parsed, worded for chips and notes, and which
// holdings get a notification.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oscalert/core/holdings.dart';
import 'package:oscalert/core/settings.dart';
import 'package:oscalert/core/stock.dart';
import 'package:oscalert/platform/notifier.dart';
import 'package:oscalert/ui/stock_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

Stock stock(String t, String name, List<Map<String, Object>> ca) =>
    Stock.parse({'t': t, 'n': name, 'm': 'KS', 'close': 10000, 'ca': ca});

const bonus = {'k': '무상증자', 'd': '2026-09-30', 'r': '0.5', 'b': '2026-10-14', 'c': '2026-10-13', 'l': '2026-11-05', 'e': '2026-11-06'};
const split = {'k': '주식분할', 'd': '2026-09-01', 'hf': '2026-10-06', 'ht': '2026-10-20', 'l': '2026-10-21', 'c': '2026-10-21', 'e': '2026-10-22'};

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
  });

  test('parsed and worded', () {
    final s = stock('000001', '가나전자', [bonus, split]);
    expect(s.actions.map((a) => a.chip()), ['무상증자 · 권리락 10/13', '주식분할 · 재상장 10/21']);
    expect(s.actions.first.describe(), '무상증자 1주당 0.5주 · 권리락 10/13 · 신주 상장 11/5 (9/30 결정)');
    expect(s.actions.last.describe(), '주식분할 · 매매정지 10/6~10/20 · 신주 상장 10/21 (9/1 결정)');
    expect(s.affected, isFalse);
    expect(stock('000001', '가', [{...bonus, 'w': 1}]).affected, isTrue);
    expect(Stock.parse({'t': '000001'}).actions, isEmpty); // older snapshots
  });

  test('holdings with something new or due next', () async {
    final a = stock('000001', '가나전자', [{...bonus, 'n': 1}]);
    final b = stock('000002', '다라화학', [{...split, 's': ['매매정지 시작']}]);
    final c = stock('000003', '마바', [bonus]); // nothing to tell today
    final d = stock('000004', '사아', [{...bonus, 'n': 1}]); // not held
    for (final x in [a, b, c]) {
      await Holdings.put(Holding(x.ticker, x.name));
    }
    final rows = Holdings.corporate([a, b, c, d]);
    expect(rows, [a, b]);
    expect(Notifier.corporateLines(rows).split('\n'), [
      '가나전자 · 새 공시 · 무상증자 1주당 0.5주 · 권리락 10/13 · 신주 상장 11/5 (9/30 결정)',
      '다라화학 · 10/6 매매정지 시작 · 주식분할 · 매매정지 10/6~10/20 · 신주 상장 10/21 (9/1 결정)',
    ]);
  });

  testWidgets('a row warns when today\'s signal may come from it', (tester) async {
    // A stock whose 3-indicator dead crossing falls on its ex-rights day.
    final s = Stock.parse({
      't': '000001', 'n': '가나전자', 'm': 'KS', 'close': 10000, 'ca': [{...bonus, 'w': 1}],
      'k_slow': [90, 80], 'd_slow': [85, 84], 'rsi': [75, 68], 'rsi_sig': [70, 70], 'cci': [150, 90],
      'k_fast': [90, 80], 'd_fast': [85, 84],
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StockTile(stock: s, open: false, onTap: () {}))));
    expect(find.text('기업행위 영향'), findsOneWidget);
    expect(find.text('데드 3지표'), findsOneWidget);
    expect(find.text('무상증자 · 권리락 10/13'), findsOneWidget);
  });
}
