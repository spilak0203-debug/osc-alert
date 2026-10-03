import 'package:flutter/services.dart';

/// Keeps a number field grouped as it is typed: "1000000" shows as "1,000,000". Digits and one
/// decimal point are kept, everything else dropped; the cursor stays after the same digit.
class GroupedDigits extends TextInputFormatter {
  static String format(String raw) {
    final dot = raw.indexOf('.');
    final whole = (dot < 0 ? raw : raw.substring(0, dot)).replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final frac = dot < 0 ? '' : '.${raw.substring(dot + 1).replaceAll('.', '')}';
    final b = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
      b.write(whole[i]);
    }
    return '$b$frac';
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue value) {
    final raw = value.text.replaceAll(RegExp(r'[^0-9.]'), '');
    final text = format(raw);
    // How many digits (or the point) were before the cursor, then find that spot again.
    final cursor = value.selection.baseOffset.clamp(0, value.text.length);
    final kept = value.text.substring(0, cursor).replaceAll(RegExp(r'[^0-9.]'), '').length;
    var at = 0;
    for (var seen = 0; at < text.length && seen < kept; at++) {
      if (text[at] != ',') seen++;
    }
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: at));
  }
}
