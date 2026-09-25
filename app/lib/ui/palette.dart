import 'package:flutter/material.dart';

/// The app's fixed colours (Korean market convention: up is red, down is blue), per brightness.
class Palette {
  const Palette._(this.up, this.down, this.flat, this.brand, this.lineMain);

  static const light = Palette._(Color(0xFFD32F2F), Color(0xFF1565C0), Color(0xFF757575), Color(0xFF1F3A5F), Color(0xFF1F3A5F));
  static const dark = Palette._(Color(0xFFFF6B6B), Color(0xFF64A8FF), Color(0xFF9E9E9E), Color(0xFF9CC3F0), Color(0xFF9CC3F0));

  final Color up, down, flat, brand, lineMain;

  static const lineSignal = Color(0xFFF59E0B);
  static const ma = [Color(0xFFF59E0B), Color(0xFF10B981), Color(0xFF8B5CF6), Color(0xFF6B7280)];
  static const band = Color(0x33888888);
  static const grid = Color(0x22888888);
  static const favorite = Color(0xFFF5B301);

  /// The dashed line on moving-average breakout days: apart from the red/blue signal marks and
  /// the average lines.
  static const maBreak = Color(0xFFD946EF);

  static Palette of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;

  Color change(double v) => v.isNaN || v == 0 ? flat : v > 0 ? up : down;

  Color side(bool buy) => buy ? up : down;
}

/// `(color & 0x00FFFFFF) | alpha << 24`
Color withAlpha(Color c, int alpha) => c.withAlpha(alpha);
