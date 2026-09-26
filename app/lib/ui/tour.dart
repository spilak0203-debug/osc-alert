import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';

import '../core/holdings.dart';
import '../core/repo.dart';
import '../core/settings.dart';
import '../core/signals.dart' as signals;
import '../platform/app_update.dart';
import '../platform/notifier.dart';
import 'home.dart';
import 'settings_page.dart';

/// Smoke test: walks through every screen and saves a screenshot of each into `dir`, then
/// writes `done`. Started by the CI emulator (`--ez smoke true`) or on Windows (`--smoke=<dir>`).
class Tour {
  Tour(this.home, this.boundary, this.dir, {required this.wide});

  final HomeState home;
  final GlobalKey boundary;
  final String dir;
  final bool wide;

  Future<void> _pause(int ms) => Future.delayed(Duration(milliseconds: ms));

  Future<void> shot(String name) async {
    await _pause(600);
    await WidgetsBinding.instance.endOfFrame;
    final ctx = boundary.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderRepaintBoundary;
    final image = await box.toImage(pixelRatio: View.of(ctx).devicePixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$dir/$name.png').writeAsBytes(png!.buffer.asUint8List());
  }

  Future<void> _waitData() async {
    for (var i = 0; i < 120 && (Repo.I.loading || Repo.I.stocks.isEmpty || Repo.I.indices.isEmpty); i++) {
      await _pause(500);
    }
    await _pause(1500);
  }

  Future<void> run() async {
    await Directory(dir).create(recursive: true);
    try {
      await _run();
    } catch (e, st) {
      await File('$dir/error.txt').writeAsString('$e\n$st');
    }
    await File('$dir/done').writeAsString('ok');
  }

  Future<void> _run() async {
    // Compare at 100% even when the Java app's smoke test left a larger font behind.
    await Settings.I.setNumber(Settings.fontScaleKey, 1.0);
    await _waitData();
    await shot('1-summary');
    final summary = home.summaryKey.currentState!;
    await summary.scrollBy(900);
    await shot('1b-summary-lower');
    summary.holdBar(0.55);
    await shot('1e-summary-scrollbar');
    summary.holdBar(null);
    summary.showTally();
    await shot('1g-summary-tally');
    summary.showBlock(signals.Block.falling);
    await shot('1h-summary-falling');
    summary.toggleSearch();
    summary.search('삼성');
    await shot('1f-summary-search');
    summary.closeSearch();
    final first = summary.firstStock;
    if (first != null) {
      if (wide) {
        home.select(first);
      } else {
        summary.expand(first.ticker);
        summary.scrollToStock();
      }
      await _pause(8000);
      await shot('1c-summary-expanded');
      if (!wide) {
        await summary.scrollBy(700);
        await shot('1d-summary-charts');
      }
    }

    home.show(1);
    await _pause(1000);
    await _waitData();
    await shot('2-stocks');
    final stocks = home.stocksKey.currentState!;
    if (!Settings.I.favorite('005930')) Settings.I.toggleFavorite('005930');
    await shot('2b-favorite');
    await Settings.I.setString(Settings.sortKey, 'rise');
    await shot('2c-sort-rise');
    await Settings.I.setString(Settings.sortKey, 'name');
    await shot('2d-sort-name');
    await Settings.I.setString(Settings.sortKey, 'favorite');
    await _pause(300);
    final samsung = Repo.I.stocks.where((s) => s.ticker == '005930').firstOrNull;
    if (samsung != null) {
      if (wide) {
        home.select(samsung);
      } else {
        stocks.expand(samsung.ticker);
        stocks.scrollToStock();
      }
      await _pause(8000);
      await shot('3-stock-expanded');
      if (!wide) {
        await stocks.scrollBy(650);
        await shot('4-stock-charts');
        await stocks.scrollBy(650);
        await shot('4b-stock-oscillators');
        stocks.scrollToIndex(0);
      }
    }
    // A moving-average breakout, for the ◆ on its candles (wide windows: the side pane).
    final ma = Repo.I.stocks.where((s) => s.maBreak != null).firstOrNull;
    if (wide && ma != null) {
      home.select(ma);
      await _pause(8000);
      await shot('3b-ma-breakout');
    }

    // The holdings tab with sample holdings: one with an average and shares, one with an average
    // only, one with neither (the user's own are put back afterwards).
    final kept = Settings.I.prefs.getString(Holdings.key);
    final sample = Repo.I.stocks.where((s) => const {'005930', '000660', '035420'}.contains(s.ticker)).toList();
    for (var i = 0; i < sample.length; i++) {
      final s = sample[i];
      final avg = i < 2 ? (s.price() * 0.9).roundToDouble() : double.nan;
      await Holdings.put(Holding(s.ticker, s.name, avg, i == 0 ? 10 : double.nan));
    }
    home.show(HomeState.holdingsTab);
    if (wide && sample.isNotEmpty) home.select(sample.first);
    await _pause(wide ? 6000 : 0);
    await shot('4c-holdings');
    await (kept == null ? Settings.I.prefs.remove(Holdings.key) : Settings.I.setString(Holdings.key, kept));
    Repo.I.changed();
    await shot('4d-holdings-empty');

    home.show(HomeState.settingsTab);
    await shot('5-settings');
    final s = home.settingsScroll;
    if (s.hasClients) {
      s.jumpTo(s.position.maxScrollExtent / 2);
      await shot('5c-settings-middle');
      s.jumpTo(s.position.maxScrollExtent);
      await shot('5d-settings-bottom');
    }
    final dialog = showChangelog(home.context);
    await _pause(800);
    await shot('6-changelog');
    Navigator.of(home.context).pop();
    await dialog;
    await Settings.I.setNumber(Settings.fontScaleKey, 1.2);
    await shot('7-larger-font');
    await Settings.I.setNumber(Settings.fontScaleKey, 1.0);

    await Settings.I.setString(Settings.themeKey, 'dark');
    home.show(0);
    await shot('8-dark-summary');
    await Settings.I.setString(Settings.themeKey, 'system');

    home.show(HomeState.settingsTab);
    await _pause(500);
    // Same path as tapping a notification.
    Notifier.tapped.value = signals.Kind.dead3;
    await _pause(1500);
    await shot('9-notification-jump');

    // The bar an update download shows (values only — nothing is downloaded).
    AppUpdate.progress.value = (5767168, 18874368);
    await shot('10-update-progress');
    AppUpdate.progress.value = null;
  }
}
