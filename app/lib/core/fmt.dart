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

/// Filter amounts in 억원: "1조" or "5,000억".
String eok(double v) => v >= 10000 ? '${grouped(v / 10000)}조' : '${grouped(v)}억';

String two(int v) => v.toString().padLeft(2, '0');
