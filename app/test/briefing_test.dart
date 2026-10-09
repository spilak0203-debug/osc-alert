// The pre-market briefing: read from news.json, when it is announced, and its card on the summary.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oscalert/core/market_index.dart';
import 'package:oscalert/core/news.dart';
import 'package:oscalert/core/repo.dart';
import 'package:oscalert/core/settings.dart';
import 'package:oscalert/core/stock.dart';
import 'package:oscalert/ui/briefing_card.dart';
import 'package:oscalert/ui/list_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// As signal/news.py writes it (through JSON, so the types are what the app gets).
Map<String, dynamic> sample([Map<String, dynamic> change = const {}]) => jsonDecode(jsonEncode({
      'date': '2026-10-12',
      'generated': '2026-10-11T22:41:00+00:00',
      'model': 'claude-opus-5-5',
      'articles': 73,
      'headline': '반도체 강세 이어질까',
      'key': ['나스닥 1% 상승', '원/달러 1,380원대', '외국인 순매수 전환'],
      'sections': [
        {
          'title': '간밤 해외 시장',
          'items': [
            {'text': '나스닥이 1% 올랐다.', 'src': [0, 7]},
          ],
        },
        {
          'title': '국내 이슈',
          'items': [
            {'text': '외국인이 샀다.', 'src': []},
          ],
        },
      ],
      'stocks': [
        {'name': '삼성전자', 'note': 'HBM 기대'},
        {'name': '없는종목', 'note': '목록에 없음'},
      ],
      'sources': [
        {'title': 'Wall St closes higher', 'press': '연합뉴스', 'url': 'https://www.yna.co.kr/view/1'},
      ],
      ...change,
    })) as Map<String, dynamic>;

void main() {
  test('reads news.json', () {
    final b = Briefing.parse(sample());
    expect(b.day, '10.12 (월)');
    expect(b.at, '07:41');
    expect(b.modelName, 'Claude Opus 5.5');
    expect(Briefing.parse(sample({'model': 'claude-sonnet-5'})).modelName, 'Claude Sonnet 5');
    // Source 7 does not exist.
    expect(b.cited(b.sections.first.items.first).map((s) => s.press), ['연합뉴스']);
    expect(b.age('2026-10-12'), 0);
    expect(b.age('2026-10-13'), 1);
    final odd = Briefing.parse({'date': '2026-10-12', 'key': [1, '둘'], 'sections': 'x', 'articles': '3'});
    expect(odd.key, ['둘']);
    expect(odd.sections, isEmpty);
    expect((odd.articles, odd.headline), (0, ''));
  });

  test('announced once, on the morning it is for', () {
    final b = Briefing.parse(sample());
    DateTime at(int day, int hour) => DateTime(2026, 10, day, hour);
    expect(b.due(at(12, 7), '2026-10-08'), isTrue);
    expect(b.due(at(12, 8), '2026-10-12'), isFalse); // already sent
    expect(b.due(at(12, 9), ''), isFalse); // the market is open
    expect(b.due(at(13, 7), ''), isFalse); // yesterday's
    expect(Briefing.parse(sample({'date': '2026-10-09'})).due(at(9, 7), ''), isFalse); // a holiday
    expect(b.notificationText(), '반도체 강세 이어질까\n· 나스닥 1% 상승\n· 원/달러 1,380원대\n· 외국인 순매수 전환');
  });

  testWidgets('the card folds, unfolds and opens a stock it names', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
    Repo.I.stocks = [
      Stock()
        ..ticker = '005930'
        ..name = '삼성전자'
        ..market = '코스피',
    ];
    final b = Briefing.parse(sample());
    final opened = <String>[];
    var open = false;
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => ListView(children: [
            BriefingCard(
              briefing: b,
              open: open,
              onToggle: () => set(() => open = !open),
              onStock: (s) => opened.add(s.ticker),
            ),
          ]),
        ),
      ),
    ));
    expect(find.text('반도체 강세 이어질까'), findsOneWidget);
    expect(find.text('나스닥 1% 상승'), findsOneWidget);
    expect(find.text('간밤 해외 시장'), findsNothing);
    expect(find.text('펼치면 간밤 해외 시장 · 국내 이슈 · 종목 2'), findsOneWidget);

    await tester.tap(find.text('장 시작 전 브리핑'));
    await tester.pump();
    expect(find.text('간밤 해외 시장'), findsOneWidget);
    expect(find.text('연합뉴스'), findsOneWidget); // the source tag
    expect(find.textContaining('Claude Opus 5.5(AI)가 기사 73건을 읽고 정리'), findsOneWidget);
    await tester.tap(find.textContaining('삼성전자'));
    await tester.tap(find.textContaining('없는종목')); // not on the list: plain text
    expect(opened, ['005930']);
  });

  testWidgets('on top of the summary until switched off or a week old', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
    Repo.I.stocks = const [];
    Repo.I.briefing = Briefing.parse(sample({'date': seoulDate(seoulNow())}));
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ListPage(summary: true))));
    await tester.pump();
    expect(find.text('장 시작 전 브리핑'), findsOneWidget);
    expect(find.text('오늘 07:41'), findsOneWidget);

    await Settings.I.setFlag(Settings.showBriefing, false);
    await tester.pump();
    expect(find.text('장 시작 전 브리핑'), findsNothing);

    await Settings.I.setFlag(Settings.showBriefing, true);
    Repo.I.briefing = Briefing.parse(sample({'date': '2026-01-02'}));
    Repo.I.changed();
    await tester.pump();
    expect(find.text('장 시작 전 브리핑'), findsNothing);
    Repo.I.briefing = null;
  });
}
