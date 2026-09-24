import 'package:flutter/material.dart';

import 'palette.dart';

/// Material 3 in Noto Sans KR, like the Java app's Theme.OscAlert. On Android the colours follow
/// the wallpaper (DynamicColors); elsewhere they grow from the brand colour.
ThemeData buildTheme(Brightness brightness, ColorScheme? dynamic) {
  final scheme = dynamic ??
      ColorScheme.fromSeed(
        seedColor: Palette.light.brand,
        brightness: brightness,
      ).copyWith(primary: brightness == Brightness.light ? Palette.light.brand : Palette.dark.brand);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: 'NotoSansKR');
  // Android's text views set no line height of their own: a line is the font's ascent plus
  // descent, which the bundled Noto Sans KR clamps to 1.25 em. Material's type scale in Flutter
  // asks for 1.33–1.5, so every row would come out taller than on the Java app.
  TextStyle line(TextStyle? s, [FontWeight? w]) => s!.copyWith(height: 1.25, fontWeight: w);
  final t = base.textTheme;
  final text = TextTheme(
    displayLarge: line(t.displayLarge),
    displayMedium: line(t.displayMedium),
    displaySmall: line(t.displaySmall),
    headlineLarge: line(t.headlineLarge),
    headlineMedium: line(t.headlineMedium),
    headlineSmall: line(t.headlineSmall),
    titleLarge: line(t.titleLarge),
    // Titles and labels use the medium weight, like M3's own.
    titleMedium: line(t.titleMedium, FontWeight.w500),
    titleSmall: line(t.titleSmall, FontWeight.w500),
    bodyLarge: line(t.bodyLarge),
    bodyMedium: line(t.bodyMedium),
    bodySmall: line(t.bodySmall),
    labelLarge: line(t.labelLarge, FontWeight.w500),
    labelMedium: line(t.labelMedium, FontWeight.w500),
    labelSmall: line(t.labelSmall, FontWeight.w500),
  );
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
    ),
    // 32dp chips like MDC's.
    chipTheme: base.chipTheme.copyWith(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      labelStyle: text.labelLarge,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
  );
}
