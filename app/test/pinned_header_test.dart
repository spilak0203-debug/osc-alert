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
  if (ma) s.maBreak = (1.0, 1.0);
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
    await tester.drag(find.byType(ListPage), const Offset(0, -3200));
    await tester.pumpAndSettle();
    expect(find.text('종목030'), findsNothing);
    final pinned = find.text('거래량 급증 (전일 3배↑)');
    expect(pinned, findsOneWidget);

    await tester.tap(pinned);
    await tester.pumpAndSettle();
    expect(find.text('종목030'), findsOneWidget);
    expect(find.text('종목029'), findsNothing);
  });
}
