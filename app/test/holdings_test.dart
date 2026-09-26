// Holdings: stored with the settings, valued at the current price, alerted on falling signals,
// and shown on their own tab.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oscalert/core/holdings.dart';
import 'package:oscalert/core/repo.dart';
import 'package:oscalert/core/rule.dart';
import 'package:oscalert/core/settings.dart';
import 'package:oscalert/core/stock.dart';
import 'package:oscalert/ui/holdings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Stock stock(String ticker, String name, double close, {bool dead = false}) {
  final s = Stock()
    ..ticker = ticker
    ..name = name
    ..market = '코스피'
    ..close = close
    ..change = 10
    ..dv20 = 1e9;
  // Yesterday above, today below: stochastic, RSI and CCI all cross down (a dead 3-of-3).
  Snap snap(double k, double d, double r, double rs, double cci) => Snap()
    ..kSlow = k
    ..dSlow = d
    ..rsi = r
    ..rsiSig = rs
    ..cci = cci;
  s.seq = dead
      ? [snap(90, 85, 75, 70, 150), snap(80, 84, 68, 70, 90)]
      : [snap(50, 50, 50, 50, 0), snap(50, 50, 50, 50, 0)];
  return s;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
  });

  test('stored, replaced and removed', () async {
    await Holdings.put(Holding('005930', '삼성전자', 70000, 10));
    await Holdings.put(Holding('000660', 'SK하이닉스', 150000, 2));
    await Holdings.put(Holding('005930', '삼성전자', 65000, 20));
    expect(Holdings.all().map((h) => h.ticker), ['005930', '000660']);
    expect(Holdings.of('005930')!.qty, 20);
    await Holdings.remove('000660');
    expect(Holdings.tickers(), {'005930'});
  });

  test('gain and rate', () {
    final h = Holding('005930', '삼성전자', 50000, 10);
    expect(h.cost, 500000);
    expect(h.gain(60000), 100000);
    expect(h.rate(60000), closeTo(20, 1e-9));
    expect(h.rate(double.nan).isNaN, isTrue);
  });

  test('only holdings with a falling signal are alerted, whatever the filter', () async {
    final a = stock('000001', '가', 100, dead: true), b = stock('000002', '나', 100, dead: true);
    final c = stock('000003', '다', 100);
    await Holdings.put(Holding('000001', '가', 100, 1));
    await Holdings.put(Holding('000003', '다', 100, 1));
    await Settings.I.setNumber(Settings.filterCap, 1e9); // filters every stock out
    expect(Holdings.falling([a, b, c]), [a]);
  });

  testWidgets('the tab totals the holdings and edits one', (tester) async {
    Repo.I.stocks = [stock('000001', '가나전자', 12000), stock('000002', '다라화학', 9000)];
    await Holdings.put(Holding('000001', '가나전자', 10000, 10)); // 120,000 now, +20,000
    await Holdings.put(Holding('000002', '다라화학', 10000, 5)); // 45,000 now, -5,000
    await tester.binding.setSurfaceSize(const Size(420, 800));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HoldingsPage())));
    expect(find.text('165,000원'), findsOneWidget);
    expect(find.text('+15,000원 (+10.00%)'), findsOneWidget);
    expect(find.text('+20,000원 (+20.00%)'), findsOneWidget);
    expect(find.text('-5,000원 (-10.00%)'), findsOneWidget);

    await tester.tap(find.byTooltip('수량·평단 수정').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '수량 (선택)'), '1,000');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(Holdings.of('000002')!.qty, 1000);
    await tester.pump(const Duration(seconds: 5)); // let the toast go
  });

  testWidgets('adding a stock by search', (tester) async {
    Repo.I.stocks = [stock('000001', '가나전자', 12000), stock('000002', '다라화학', 9000)];
    await tester.binding.setSurfaceSize(const Size(420, 800));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HoldingsPage())));
    expect(find.text('보유종목이 없습니다'), findsOneWidget);
    await tester.tap(find.text('종목 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '다라');
    await tester.pumpAndSettle();
    await tester.tap(find.text('다라화학'));
    await tester.pumpAndSettle();
    // Both fields may stay blank: the stock is held, with no value and no average line.
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    final h = Holdings.of('000002')!;
    expect(h.hasAvg || h.hasQty, isFalse);
    expect(find.text('평가금액'), findsNothing); // no total without amounts
    expect(find.text('9,000원'), findsOneWidget); // the row shows the price
    await tester.pump(const Duration(seconds: 5));

    // An average alone: the gain over it, still no total.
    await tester.tap(find.byTooltip('수량·평단 수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '평균 매수가 (선택)'), '10000');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('평단 대비 -10.00%'), findsOneWidget);
    expect(find.text('평가금액'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  test('saved without amounts, read back', () async {
    await Holdings.put(Holding('000001', '가'));
    final h = Holdings.all().single;
    expect(h.avg.isNaN && h.qty.isNaN, isTrue);
    expect(h.rate(100).isNaN, isTrue);
    expect(Holding('000001', '가', 80).rate(100), closeTo(25, 1e-9));
  });
}
