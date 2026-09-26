// Settings sit in folded cards, the signal rules first, each saying in one line how it is set.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oscalert/core/settings.dart';
import 'package:oscalert/ui/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('cards start folded and unfold with a tap', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SettingsPage())));
    await tester.pump();
    // Folded: summaries only, rules on top; two of three is off by default.
    expect(find.textContaining('3지표만 신호'), findsOneWidget);
    expect(find.textContaining('장기선 60·120일선 둘 다'), findsOneWidget);
    expect(find.textContaining('받음: 강도 높음 이상 · 3지표'), findsOneWidget);
    expect(find.text('2지표 일치도 신호로 보기'), findsNothing);
    expect(tester.getTopLeft(find.text('신호 조건')).dy, lessThan(tester.getTopLeft(find.text('알림')).dy));

    await tester.tap(find.text('신호 조건'));
    await tester.pumpAndSettle();
    expect(find.text('2지표 일치도 신호로 보기'), findsOneWidget);
    expect(find.text('밴드 조건 사용'), findsNWidgets(3));
    // Moving-average breakout: which rising long averages it needs, both by default.
    await tester.tap(find.text('60일선만'));
    await tester.pumpAndSettle();
    expect(Settings.I.maRising, '60');
    expect(Settings.I.config().maUp120, isFalse);
    await tester.tap(find.text('2%'));
    await tester.pumpAndSettle();
    expect(Settings.I.config().maSpread, 2);

    await tester.tap(find.text('알림'));
    await tester.pumpAndSettle();
    expect(find.text('강도 높음 이상'), findsOneWidget);
    expect(find.text('2지표 일치'), findsNothing); // hidden while two of three is off
  });
}
