// The summary pins the current section's title; tapping it goes to the top of that section.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oscalert/core/repo.dart';
import 'package:oscalert/core/settings.dart';
import 'package:oscalert/core/stock.dart';
import 'package:oscalert/ui/list_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Stock stock(int i, {bool surge = false, bool ma = false}) {
  final s = Stock()
    ..ticker = '${100000 + i}'
    ..name = '종목${i.toString().padLeft(3, '0')}'
    ..market = '코스피'
    ..dv20 = 1e9
    ..volumeTimes = surge ? 4 : 1;
  if (ma) s.maBreak = (spread: 1.0, volume: 1.0, up60: true, up120: true);
  return s;
}

void main() {
  testWidgets('tapping the pinned title scrolls to its section', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
    Repo.I.stocks = [
      for (var i = 0; i < 30; i++) stock(i, ma: true),
      for (var i = 30; i < 60; i++) stock(i, surge: true),
    ];
    await tester.binding.setSurfaceSize(const Size(420, 800));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ListPage(summary: true))));
    await tester.pump();

    // Well into the volume-surge section: its title is pinned, the first rows are gone.
    await tester.drag(find.byType(ListPage), const Offset(0, -3700));
    await tester.pumpAndSettle();
    expect(find.text('종목030'), findsNothing);
    final pinned = find.text('거래량 급증 (전일 3배↑)');
    expect(pinned, findsOneWidget);

    await tester.tap(pinned);
    await tester.pumpAndSettle();
    expect(find.text('종목030'), findsOneWidget);
    expect(find.text('종목029'), findsNothing);
  });

  testWidgets('oversold/overbought groups fold away and open with a tap', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
    // All three indicators drop into oversold today without crossing their signal lines.
    Repo.I.stocks = [
      Stock.parse({
        't': '000009', 'n': '과매도종목', 'm': 'KS', 'dv20': 1e9,
        'k_fast': [30, 10], 'd_fast': [35, 15], 'k_slow': [30, 10], 'd_slow': [35, 15],
        'rsi': [40, 20], 'rsi_sig': [45, 25], 'cci': [0, -150],
      }),
    ];
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ListPage(summary: true))));
    await tester.pump();
    expect(find.text('참고 · 과매도·과매수'), findsOneWidget);
    expect(find.text('과매도종목'), findsNothing);

    await tester.tap(find.text('펼치기'));
    await tester.pumpAndSettle();
    expect(find.text('과매도 진입'), findsOneWidget);
    expect(find.text('과매도종목'), findsOneWidget);
  });

  testWidgets('the tally counts stocks moved up into an overlap', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
    Repo.I.stocks = [stock(1, surge: true, ma: true)];
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ListPage(summary: true))));
    await tester.pump();
    // Listed once, under the 2-signal overlap; the breakout and surge tiles still count it.
    expect(find.text('종목001'), findsOneWidget);
    expect(find.text('강도 높음 (신호 2개)'), findsWidgets);
    expect(find.text('높음'), findsOneWidget); // the row's chip
    expect(find.text('높음 이상 칸에 1'), findsNWidgets(2));
    expect(find.text('이평선 밀집 돌파'), findsOneWidget); // the tile only: no section of its own
  });
}
