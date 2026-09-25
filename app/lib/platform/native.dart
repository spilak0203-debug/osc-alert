import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android pieces that live in MainActivity.java: the Java app's old preferences, the old
/// background job, and installing an update through PackageInstaller.
class Native {
  static const _ch = MethodChannel('kr.personal.oscalert/native');

  /// Everything the Java app stored in its "osc" preferences file (empty on other platforms).
  static Future<Map<String, Object?>> legacyPrefs() async {
    if (!Platform.isAndroid) return const {};
    final m = await _ch.invokeMapMethod<String, Object?>('legacyPrefs');
    return m ?? const {};
  }

  /// Stops the Java app's WorkManager job; the Flutter app schedules its own.
  static Future<void> cancelLegacyWork() async {
    if (Platform.isAndroid) await _ch.invokeMethod('cancelLegacyWork');
  }

  /// Streams the APK into a PackageInstaller session, reporting bytes received and the total
  /// (0 if unknown). Returns an error message, or null once the system's confirmation screen is
  /// on its way.
  static Future<String?> installApk(String url, String? sha256, void Function(int got, int size) onProgress) async {
    _ch.setMethodCallHandler((call) async {
      if (call.method != 'installProgress') return;
      final a = call.arguments as List;
      final size = (a[1] as num).toInt();
      onProgress((a[0] as num).toInt(), size < 0 ? 0 : size);
    });
    try {
      return await _ch.invokeMethod<String>('installApk', {'url': url, 'sha256': sha256});
    } finally {
      _ch.setMethodCallHandler(null);
    }
  }

  /// Android 14+: the system's Material You roles, the same colours the Java app got from
  /// DynamicColors. Null elsewhere.
  static Future<(ColorScheme, ColorScheme)?> dynamicColors() async {
    if (!Platform.isAndroid) return null;
    final m = await _ch.invokeMapMethod<String, Object?>('dynamicColors');
    if (m == null) return null;
    ColorScheme scheme(Brightness b, Map roles) {
      Color c(String k) => Color((roles[k] as num).toInt());
      return ColorScheme(
        brightness: b,
        primary: c('primary'),
        onPrimary: c('onPrimary'),
        primaryContainer: c('primaryContainer'),
        onPrimaryContainer: c('onPrimaryContainer'),
        secondary: c('secondary'),
        onSecondary: c('onSecondary'),
        secondaryContainer: c('secondaryContainer'),
        onSecondaryContainer: c('onSecondaryContainer'),
        tertiary: c('tertiary'),
        onTertiary: c('onTertiary'),
        tertiaryContainer: c('tertiaryContainer'),
        onTertiaryContainer: c('onTertiaryContainer'),
        error: c('error'),
        onError: c('onError'),
        errorContainer: c('errorContainer'),
        onErrorContainer: c('onErrorContainer'),
        surface: c('surface'),
        onSurface: c('onSurface'),
        onSurfaceVariant: c('onSurfaceVariant'),
        outline: c('outline'),
        outlineVariant: c('outlineVariant'),
        surfaceDim: c('surfaceDim'),
        surfaceBright: c('surfaceBright'),
        surfaceContainerLowest: c('surfaceContainerLowest'),
        surfaceContainerLow: c('surfaceContainerLow'),
        surfaceContainer: c('surfaceContainer'),
        surfaceContainerHigh: c('surfaceContainerHigh'),
        surfaceContainerHighest: c('surfaceContainerHighest'),
        inverseSurface: c('onSurface'),
        onInverseSurface: c('surface'),
        inversePrimary: c('primaryContainer'),
      );
    }

    return (scheme(Brightness.light, m['light'] as Map), scheme(Brightness.dark, m['dark'] as Map));
  }

  /// Extras the app was launched with (the smoke test's tour flag).
  static Future<Map<String, Object?>> launchExtras() async {
    if (!Platform.isAndroid) return const {};
    return await _ch.invokeMapMethod<String, Object?>('launchExtras') ?? const {};
  }
}
