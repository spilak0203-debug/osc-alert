// Chart gestures: a mouse drag pans, the wheel is left to the page unless Ctrl is held, and a
// slow pinch zooms smoothly (small moves add up instead of rounding away).
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oscalert/core/bars.dart';
import 'package:oscalert/core/indicators.dart';
import 'package:oscalert/core/rule.dart';
import 'package:oscalert/ui/chart.dart';

Bars bars(int n) {
  final b = Bars();
  for (var i = 0; i < n; i++) {
    final c = 100 + 10 * math.sin(i / 7);
    b.date.add('2026${(1 + i ~/ 28).toString().padLeft(2, '0')}${(1 + i % 28).toString().padLeft(2, '0')}');
    b.open.add(c - 1);
    b.high.add(c + 2);
    b.low.add(c - 2);
    b.close.add(c);
    b.volume.add(1000);
  }
  b.series = compute(b.high, b.low, b.close);
  return b;
}

void main() {
  late ChartGroup group;

  Future<Offset> pump(WidgetTester tester) async {
    group = ChartGroup();
    await tester.binding.setSurfaceSize(const Size(600, 400));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChartPanel(type: ChartType.candle, bars: bars(250), cfg: RuleConfig(), group: group),
      ),
    ));
    return tester.getCenter(find.byType(ChartPanel));
  }

  testWidgets('mouse drag pans without zooming', (tester) async {
    final c = await pump(tester);
    await tester.dragFrom(c, const Offset(150, 0), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(group.visible, chartWindow);
    expect(group.end, lessThan(250)); // moved back in time
    await tester.pump(const Duration(seconds: 1)); // let the double-tap timer run out
  });

  testWidgets('the wheel zooms only with Ctrl', (tester) async {
    final c = await pump(tester);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(c));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(group.visible, chartWindow);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(group.visible, lessThan(chartWindow));
  });

  testWidgets('the average-price line draws inside and off the range', (tester) async {
    for (final avg in [100.0, 1000.0, 1.0]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChartPanel(type: ChartType.candle, bars: bars(250), cfg: RuleConfig(), group: ChartGroup(), avgPrice: avg),
        ),
      ));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a slow pinch adds up', (tester) async {
    final c = await pump(tester);
    final a = await tester.startGesture(c - const Offset(40, 0), pointer: 1);
    final b = await tester.startGesture(c + const Offset(40, 0), pointer: 2);
    // Spread the fingers by a quarter pixel at a time: each step alone is far less than a bar,
    // which the old per-step rounding threw away (the zoom stood still, then jumped).
    var last = group.visible, biggestJump = 0;
    for (var i = 0; i < 240; i++) {
      await a.moveBy(const Offset(-0.25, 0));
      await b.moveBy(const Offset(0.25, 0));
      await tester.pump();
      biggestJump = math.max(biggestJump, (group.visible - last).abs());
      last = group.visible;
    }
    await a.up();
    await b.up();
    await tester.pump(const Duration(seconds: 1));
    expect(group.visible, lessThan(chartWindow - 15)); // zoomed in well past the gesture slop
    expect(biggestJump, lessThanOrEqualTo(2)); // one bar at a time, no jumps
  });
}
