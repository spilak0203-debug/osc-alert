// Settings sit in cards; the signal rules start folded to one summary line.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oscalert/core/settings.dart';
import 'package:oscalert/ui/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the rule card unfolds', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SettingsPage())));
    await tester.pump();
    expect(find.text('신호 겹침'), findsOneWidget);
    expect(find.textContaining('허용 기간 당일'), findsOneWidget); // the folded summary
    expect(find.text('2지표 일치도 신호로 보기'), findsNothing);

    await tester.tap(find.text('펼치기'));
    await tester.pumpAndSettle();
    expect(find.text('2지표 일치도 신호로 보기'), findsOneWidget);
    expect(find.text('밴드 조건 사용'), findsNWidgets(3));
  });
}
