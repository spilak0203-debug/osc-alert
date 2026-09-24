import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../core/settings.dart';
import 'checker.dart';
import 'notifier.dart';

const _task = 'osc-signals-v3';

/// Runs in a background isolate started by WorkManager.
@pragma('vm:entry-point')
void backgroundMain() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Settings.init();
      await Settings.I.reload();
      await Notifier.init(background: true);
      await Checker.check(seoulNowForChecker());
      return true;
    } catch (_) {
      return false; // WorkManager retries
    }
  });
}

/// Android: every 30 minutes with a network connection, like the Java app's worker.
class Background {
  static Future<void> schedule() async {
    if (!Platform.isAndroid) return;
    await Workmanager().initialize(backgroundMain);
    await Workmanager().registerPeriodicTask(
      _task,
      _task,
      frequency: const Duration(minutes: 30),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }
}
