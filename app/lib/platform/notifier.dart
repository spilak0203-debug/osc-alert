import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/fmt.dart';
import '../core/repo.dart';
import '../core/settings.dart';
import '../core/signals.dart' as signals;
import '../core/stock.dart';

/// Notifications. On Android, channels fix sound and vibration when they are created, so there
/// is one channel per choice (the same ids as the Java app) and the setting picks which one to
/// post to. Tapping a notification opens the dashboard at its signal group.
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// The kind whose notification was tapped, for the running app to jump to.
  static final ValueNotifier<signals.Kind?> tapped = ValueNotifier(null);

  static const _pattern = [0, 300, 200, 300];

  static Future<void> init({bool background = false}) async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notify'),
        windows: WindowsInitializationSettings(
          appName: '매매 시그널 알림',
          appUserModelId: 'kr.personal.oscalert',
          guid: '6f3d2a8e-5c1b-4e7a-9d42-8b1f0c6e3a57',
        ),
      ),
      onDidReceiveNotificationResponse: (r) => tapped.value = signals.Kind.byName(r.payload),
    );
    _ready = true;
    if (!background) {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        tapped.value = signals.Kind.byName(launch!.notificationResponse?.payload);
      }
    }
    if (Platform.isAndroid) await _channels();
  }

  static Future<void> _channels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    final vibrate = Int64List.fromList(_pattern);
    await android.createNotificationChannel(AndroidNotificationChannel('sig_both', '신호 알림 · 소리+진동',
        importance: Importance.high, playSound: true, enableVibration: true, vibrationPattern: vibrate));
    await android.createNotificationChannel(const AndroidNotificationChannel('sig_sound', '신호 알림 · 소리만',
        importance: Importance.high, playSound: true, enableVibration: false));
    await android.createNotificationChannel(AndroidNotificationChannel('sig_vibrate', '신호 알림 · 진동만',
        importance: Importance.high, playSound: false, enableVibration: true, vibrationPattern: vibrate));
    // Shown in the shade and on the lock screen, but never makes a sound or pops up.
    await android.createNotificationChannel(const AndroidNotificationChannel('sig_silent', '신호 알림 · 무음',
        importance: Importance.low, playSound: false, enableVibration: false));
  }

  static String _channel() {
    switch (Settings.I.sound) {
      case 'sound':
        return 'sig_sound';
      case 'vibrate':
        return 'sig_vibrate';
      case 'silent':
        return 'sig_silent';
      default:
        return 'sig_both';
    }
  }

  static Future<bool> allowed() async {
    if (!Platform.isAndroid) return true;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? true;
  }

  static Future<void> askPermission() async {
    if (!Platform.isAndroid) return;
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }

  /// One notification per signal kind. `prefix` marks repeats and tests. Returns how many were posted.
  static Future<int> post(String asof, Map<signals.Kind, List<Stock>> groups, String prefix) async {
    if (!await allowed()) return 0;
    var posted = 0;
    final day = asof.length >= 10 ? asof.substring(5).replaceAll('-', '.') : asof;
    for (final e in groups.entries) {
      final rows = e.value;
      if (rows.isEmpty) continue;
      await _show(10 + e.key.index, e.key, '$prefix${e.key.label} ${rows.length}종목 · $day', _lines(rows));
      posted++;
    }
    if (posted == 0 && Settings.I.flag(Settings.quietDays)) {
      await _show(9, null, '$prefix$day 신호 없음', '설정한 조건에 맞는 종목이 없습니다');
      posted++;
    }
    return posted;
  }

  static String _lines(List<Stock> rows) {
    final b = <String>[];
    for (var i = 0; i < rows.length && i < 15; i++) {
      b.add(line(rows[i]));
    }
    if (rows.length > 15) b.add('… 외 ${rows.length - 15}종목');
    return b.join('\n');
  }

  /// One example per alert kind that is switched on, so the user sees exactly what will arrive.
  /// Uses today's real stocks when there are some; otherwise a sample line.
  static Future<int> test() async {
    final real = signals.byKind(Repo.I.stocks);
    var shown = 0;
    for (final k in signals.Kind.values) {
      if (!signals.alerting(k)) continue;
      final rows = real[k];
      String text;
      int n;
      if (rows != null && rows.isNotEmpty) {
        text = _lines(rows);
        n = rows.length;
      } else {
        text = '예시종목  12,345원 (+1.23%)\n오늘은 이 조건에 맞는 종목이 없어 예시로 보여 드립니다';
        n = 1;
      }
      await _show(100 + k.index, k, '[테스트] ${k.label} $n종목', text);
      shown++;
    }
    if (shown == 0) {
      await _show(99, null, '[테스트] 켜진 알림이 없습니다', '설정에서 받을 알림 종류를 켜세요 · ${describe(Settings.I.sound)}');
      shown = 1;
    }
    return shown;
  }

  static String describe(String sound) {
    switch (sound) {
      case 'sound':
        return '소리만';
      case 'vibrate':
        return '진동만';
      case 'silent':
        return '무음';
      default:
        return Platform.isAndroid ? '소리+진동' : '소리';
    }
  }

  static String line(Stock s) => '${s.name}  ${grouped(s.price())}원 (${signed(s.changePct(), 2)}%)';

  /// Tapping opens the dashboard at the notification's group (`kind`), or at the top when null.
  static Future<void> _show(int id, signals.Kind? kind, String title, String text) async {
    final channel = _channel();
    await _plugin.show(
      id: id,
      title: title,
      body: text.split('\n').first,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          const {
            'sig_both': '신호 알림 · 소리+진동',
            'sig_sound': '신호 알림 · 소리만',
            'sig_vibrate': '신호 알림 · 진동만',
            'sig_silent': '신호 알림 · 무음',
          }[channel]!,
          styleInformation: BigTextStyleInformation(text),
          autoCancel: true,
          icon: 'ic_notify',
        ),
        windows: WindowsNotificationDetails(
          audio: Settings.I.sound == 'silent' ? WindowsNotificationAudio.silent() : null,
        ),
      ),
      payload: kind?.name,
    );
  }
}
