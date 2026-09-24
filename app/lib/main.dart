import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'core/settings.dart';
import 'platform/app_update.dart';
import 'platform/background.dart';
import 'platform/desktop.dart';
import 'platform/native.dart';
import 'platform/notifier.dart';
import 'ui/home.dart';
import 'ui/theme.dart';
import 'ui/toast.dart';
import 'ui/tour.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Settings.init();
  try {
    await Settings.I.importLegacy(await Native.legacyPrefs());
    await Native.cancelLegacyWork();
  } catch (_) {}
  await AppUpdate.init();
  // Neither may keep the app from starting.
  try {
    await Notifier.init();
  } catch (_) {}
  try {
    await Background.schedule();
  } catch (_) {}
  await Desktop.init(args);

  String? smokeDir;
  final flag = args.where((a) => a.startsWith('--smoke=')).firstOrNull;
  if (flag != null) {
    smokeDir = flag.substring('--smoke='.length);
  } else if ((await Native.launchExtras())['smoke'] == true) {
    smokeDir = '${(await getExternalStorageDirectory())!.path}/smoke';
  }
  (ColorScheme, ColorScheme)? system;
  try {
    system = await Native.dynamicColors();
  } catch (_) {}
  runApp(OscApp(smokeDir: smokeDir, system: system));
}

class OscApp extends StatefulWidget {
  const OscApp({super.key, this.smokeDir, this.system});

  final String? smokeDir;

  /// Android 14+: the system's own Material You colours (light, dark).
  final (ColorScheme, ColorScheme)? system;

  @override
  State<OscApp> createState() => _OscAppState();
}

class _OscAppState extends State<OscApp> {
  final _home = GlobalKey<HomeState>();
  final _boundary = GlobalKey();

  @override
  void initState() {
    super.initState();
    final dir = widget.smokeDir;
    if (dir != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final ctx = _home.currentContext!;
        final wide = MediaQuery.sizeOf(ctx).width >= wideBreakpoint;
        await Tour(_home.currentState!, _boundary, dir, wide: wide).run();
        if (Desktop.supported) exit(0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(builder: (lightDynamic, darkDynamic) {
      // Android 12+ follows the wallpaper like the Java app did; Windows keeps the brand colour.
      final useDynamic = Platform.isAndroid;
      return ListenableBuilder(
        listenable: Settings.I,
        builder: (context, _) {
          final st = Settings.I;
          return MaterialApp(
            title: '매매 시그널 알림',
            debugShowCheckedModeBanner: false,
            navigatorKey: Toaster.navigator,
            theme: buildTheme(Brightness.light, widget.system?.$1 ?? (useDynamic ? lightDynamic : null)),
            darkTheme: buildTheme(Brightness.dark, widget.system?.$2 ?? (useDynamic ? darkDynamic : null)),
            themeMode: switch (st.theme) {
              'light' => ThemeMode.light,
              'dark' => ThemeMode.dark,
              _ => ThemeMode.system,
            },
            // The user's font size multiplies the system one, so accessibility settings still count.
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * st.fontScale)),
                child: RepaintBoundary(key: _boundary, child: child!),
              );
            },
            home: Home(key: _home),
          );
        },
      );
    });
  }
}
