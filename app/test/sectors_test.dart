// Industries and themes: read from the snapshot's name lists, searchable, and a tag lists the
// whole group.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oscalert/core/repo.dart';
import 'package:oscalert/core/settings.dart';
import 'package:oscalert/ui/group_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const snapshot = '''{"asof":"2026-10-02","industries":["반도체와반도체장비","제약"],"themes":["AI","HBM","2차전지"],
"stocks":[
 {"t":"005930","n":"삼성전자","m":"KS","cap":5000000,"close":80000,"chg":1.5,"ind":0,"th":[0,1]},
 {"t":"000660","n":"SK하이닉스","m":"KS","cap":3000000,"close":300000,"chg":-2.0,"ind":0,"th":[1]},
 {"t":"068270","n":"셀트리온","m":"KS","cap":400000,"close":180000,"chg":0.5,"ind":1},
 {"t":"999999","n":"옛스냅샷","m":"KQ","cap":100,"close":1000,"ind":7,"th":[9]}
]}''';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
    Repo.I.stocks = Repo.I.parse(snapshot);
  });

  test('parsed from the name lists', () {
    final s = Repo.I.stocks;
    expect(s[0].industry, '반도체와반도체장비');
    expect(s[0].themes, ['AI', 'HBM']);
    expect(s[2].themes, isEmpty);
    expect(s[3].industry, ''); // out of range: left empty
    expect(s[3].themes, isEmpty);
  });

  test('search finds industries and themes', () {
    List<String> names(String q) => [for (final s in Repo.I.stocks) if (s.matches(q)) s.name];
    expect(names('반도체'), ['삼성전자', 'SK하이닉스']);
    expect(names('hbm'), ['삼성전자', 'SK하이닉스']);
    expect(names('제약'), ['셀트리온']);
  });

  testWidgets('a group lists its stocks by market cap', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (c) => TextButton(onPressed: () => showGroup(c, 'HBM', theme: true), child: const Text('열기'))),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('#HBM'), findsOneWidget);
    expect(find.textContaining('테마 · 2종목'), findsOneWidget);
    expect(tester.getTopLeft(find.text('삼성전자')).dy, lessThan(tester.getTopLeft(find.text('SK하이닉스')).dy));
    expect(find.text('셀트리온'), findsNothing);
  });
}
