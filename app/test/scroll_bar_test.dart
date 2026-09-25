// Grabbing the scroll bar on the right moves the list and names where it is.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oscalert/core/repo.dart';
import 'package:oscalert/core/settings.dart';
import 'package:oscalert/core/stock.dart';
import 'package:oscalert/ui/list_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('dragging the bar scrolls and shows a bubble', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
    Repo.I.stocks = [
      for (var i = 0; i < 300; i++)
        Stock()
          ..ticker = '${100000 + i}'
          ..name = '종목${i.toString().padLeft(3, '0')}'
          ..market = '코스피'
          ..cap = 1000.0 - i
    ];
    await tester.binding.setSurfaceSize(const Size(420, 800));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ListPage(summary: false))));
    await tester.pump();
    expect(find.text('종목000'), findsOneWidget);

    // Nudge the list so the bar shows, then grab it at the right edge and drag halfway down.
    await tester.drag(find.byType(ListPage), const Offset(0, -50));
    await tester.pump();
    final box = tester.getRect(find.byType(ListPage));
    final grab = await tester.startGesture(Offset(box.right - 6, box.top + 200));
    await grab.moveBy(const Offset(0, 20));
    await grab.moveBy(const Offset(0, 250));
    await tester.pump();

    expect(find.text('종목000'), findsNothing);
    final bubble = find.textContaining(RegExp(r'^종목1\d\d$'));
    expect(bubble, findsWidgets);
    await grab.up();
    await tester.pump(const Duration(seconds: 2));
  });
}
