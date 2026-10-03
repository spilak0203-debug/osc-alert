/// Number formatting shared by every screen, matching Java's `String.format(Locale.KOREA, …)`.
library;

/// `%,.{digits}f`: fixed decimals with comma grouping.
String grouped(double v, [int digits = 0]) {
  final s = v.abs().toStringAsFixed(digits);
  final dot = s.indexOf('.');
  final whole = dot < 0 ? s : s.substring(0, dot);
  final frac = dot < 0 ? '' : s.substring(dot);
  final b = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
    b.write(whole[i]);
  }
  final negative = v < 0 && double.parse(s) != 0;
  return '${negative ? '-' : ''}$b$frac';
}

/// `%+,.{digits}f`
String signed(double v, [int digits = 2]) {
  final g = grouped(v, digits);
  return g.startsWith('-') ? g : '+$g';
}

String price(double v) => v.isNaN ? '-' : '${grouped(v)}원';

String percent(double v) => v.isNaN ? '-' : '${signed(v, 2)}%';

/// 1.2조, 3,400억, 56만.
String compact(double v) {
  if (v.isNaN) return '-';
  if (v >= 1e12) return '${(v / 1e12).toStringAsFixed(1)}조';
  if (v >= 1e8) return '${grouped(v / 1e8)}억';
  if (v >= 1e4) return '${grouped(v / 1e4)}만';
  return grouped(v);
}

/// The charts' volume labels: 1.2억 keeps a decimal.
String compactNumber(double v) {
  if (v.isNaN) return '-';
  if (v >= 1e8) return '${grouped(v / 1e8, 1)}억';
  if (v >= 1e4) return '${grouped(v / 1e4)}만';
  return grouped(v);
}

String fixed1(double v) => v.isNaN ? '-' : v.toStringAsFixed(1);

String axis(double v) => v.abs() >= 1000 ? grouped(v) : v.toStringAsFixed(0);

/// Filter amounts in 억원: "1조", "5,000억", "12,345억" (조 only when it is whole), "0.5억".
String eok(double v) =>
    v >= 10000 && v % 10000 == 0 ? '${grouped(v / 10000)}조' : '${grouped(v, v == v.roundToDouble() ? 0 : 1)}억';

/// An amount of won as it is said: 5,000,000 → "5백만원", 12,345억 → "1조 2,345억원",
/// 4,000 → "4천원", 1,234,500 → "123만 4,500원". Each 4-digit group (조, 억, 만, the rest) is a
/// round 천 or 백 in words, otherwise in digits. "" for nothing.
String wonReading(double won) {
  var n = won.isNaN ? 0 : won.round();
  if (n <= 0) return '';
  String group(int g) => g % 1000 == 0 && g < 10000
      ? '${g ~/ 1000}천'
      : g % 100 == 0 && g < 1000
          ? '${g ~/ 100}백'
          : grouped(g.toDouble());
  final parts = <String>[];
  for (final unit in ['', '만', '억', '조']) {
    final g = unit == '조' ? n : n % 10000;
    if (g > 0) parts.insert(0, '${group(g)}$unit');
    n ~/= 10000;
    if (n == 0) break;
  }
  return '${parts.join(' ')}원';
}

String two(int v) => v.toString().padLeft(2, '0');

/// Sorts `list` in place keeping equal items in their order (Dart's own sort does not; Java's
/// Collections.sort, which the lists used to follow, does).
void stableSort<T>(List<T> list, int Function(T a, T b) cmp) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])]
    ..sort((x, y) {
      final c = cmp(x.$2, y.$2);
      return c != 0 ? c : x.$1.compareTo(y.$1);
    });
  for (var i = 0; i < list.length; i++) {
    list[i] = indexed[i].$2;
  }
}
