// Searching the summary keeps the matching stocks in their groups and lists the rest as quiet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oscalert/core/repo.dart';
import 'package:oscalert/core/settings.dart';
import 'package:oscalert/core/stock.dart';
import 'package:oscalert/ui/list_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Stock stock(String ticker, String name, {bool surge = false}) => Stock()
  ..ticker = ticker
  ..name = name
  ..market = '코스피'
  ..dv20 = 1e9
  ..volumeTimes = surge ? 4 : 1;

void main() {
  testWidgets('summary search filters groups and closes back', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
    Repo.I.stocks = [
      stock('000001', '삼성알파', surge: true),
      stock('000002', '엘지베타', surge: true),
      stock('000003', '삼성감마'),
    ];
    final key = GlobalKey<ListPageState>();
    await tester.binding.setSurfaceSize(const Size(420, 800));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListPage(key: key, summary: true))));
    await tester.pump();
    expect(find.text('2종목'), findsNWidgets(2)); // the rising part and its volume-surge group
    expect(find.text('삼성감마'), findsNothing);

    key.currentState!.toggleSearch();
    await tester.pump();
    await tester.enterText(find.byType(TextField), '삼성');
    await tester.pumpAndSettle();
    expect(find.text('삼성알파'), findsOneWidget);
    expect(find.text('엘지베타'), findsNothing);
    expect(find.text('1/2종목'), findsOneWidget);
    expect(find.text('오늘 신호 없음'), findsOneWidget);
    expect(find.text('삼성감마'), findsOneWidget);

    key.currentState!.closeSearch();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('엘지베타'), findsOneWidget);
    expect(find.text('오늘 신호 없음'), findsNothing);
  });
}
