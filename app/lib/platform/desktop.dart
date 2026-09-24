import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/repo.dart';
import '../core/settings.dart';
import 'checker.dart';

/// Windows: a normal window that closes to the tray, keeps checking for signals every 30 minutes
/// like the phone's background job, and can start with Windows.
class Desktop with WindowListener, TrayListener {
  Desktop._();

  static final Desktop _i = Desktop._();

  static bool get supported => !kIsWeb && Platform.isWindows;

  static Timer? _timer;

  static Future<void> init(List<String> args) async {
    if (!supported) return;
    await windowManager.ensureInitialized();
    final hidden = args.contains('--hidden');
    const options = WindowOptions(
      size: Size(1280, 860),
      minimumSize: Size(420, 560),
      center: true,
      title: '매매 시그널 알림',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (!hidden) {
        await windowManager.show();
        await windowManager.focus();
      }
    });
    await windowManager.setPreventClose(true);
    windowManager.addListener(_i);

    await trayManager.setIcon('assets/tray.ico');
    await trayManager.setToolTip('매매 시그널 알림');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'open', label: '열기'),
      MenuItem(key: 'refresh', label: '새로고침'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: '종료'),
    ]));
    trayManager.addListener(_i);

    launchAtStartup.setup(appName: '매매 시그널 알림', appPath: Platform.resolvedExecutable, args: ['--hidden']);

    // Same schedule as the phone: check now, then every 30 minutes.
    unawaited(_check());
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => _check());
  }

  static Future<void> _check() async {
    try {
      await Checker.check(seoulNowForChecker());
    } catch (_) {}
  }

  static Future<void> setStartWithWindows(bool on) async {
    if (!supported) return;
    if (on) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }

  static Future<void> showWindow() async {
    if (!supported) return;
    await windowManager.show();
    await windowManager.focus();
  }

  static Future<void> quit() async {
    _timer?.cancel();
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    if (Settings.I.flag(Settings.trayOnClose)) {
      windowManager.hide();
    } else {
      quit();
    }
  }

  @override
  void onTrayIconMouseDown() => showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem item) {
    switch (item.key) {
      case 'open':
        showWindow();
      case 'refresh':
        Repo.I.refresh(Repo.I.wantAll);
      case 'quit':
        quit();
    }
  }
}
