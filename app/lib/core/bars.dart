import 'dart:convert';
import 'dart:math' as math;

import 'fmt.dart';
import 'indicators.dart';
import 'net.dart';

/// Daily bars for one stock (or index), from Naver, for the charts.
class Bars {
  List<String> date = [];
  List<double> open = [], high = [], low = [], close = [], volume = [];
  late Series series;

  static const _url = 'https://api.finance.naver.com/siseJson.naver?symbol=%s'
      '&requestType=1&startTime=%from&endTime=%to&timeframe=day';
  static final Map<String, Bars> _cache = {};
  static const _cacheSize = 30;

  /// Forget every stock's bars so the next expand loads today's.
  static void clear() => _cache.clear();

  static Bars? cached(String ticker) => _cache[ticker];

  static String _day(DateTime t) => '${t.year}${two(t.month)}${two(t.day)}';

  /// About 400 calendar days, enough for the 120-day average and a settled RSI.
  static Future<Bars> load(String ticker) async {
    final now = DateTime.now();
    final text = await Net.get(_url
        .replaceFirst('%s', ticker)
        .replaceFirst('%from', _day(now.subtract(const Duration(days: 420))))
        .replaceFirst('%to', _day(now)));
    // The response is almost JSON: the header row uses single quotes.
    final rows = jsonDecode(text.trim().replaceAll("'", '"')) as List;
    final b = Bars();
    for (var i = 1; i < rows.length; i++) {
      final r = rows[i] as List;
      double v(int j) => j < r.length && r[j] is num ? (r[j] as num).toDouble() : double.nan;
      final o = v(1), h = v(2), l = v(3), c = v(4), vol = v(5);
      // Days without trades carry no price information; the scan leaves them out too.
      if (!(vol > 0 && o > 0 && h > 0 && l > 0 && c > 0)) continue;
      b.date.add('${r[0]}'.trim());
      b.open.add(o);
      b.high.add(math.max(h, math.max(o, c)));
      b.low.add(math.min(l, math.min(o, c)));
      b.close.add(c);
      b.volume.add(vol);
    }
    b.series = compute(b.high, b.low, b.close);
    if (_cache.length >= _cacheSize) _cache.remove(_cache.keys.first);
    _cache[ticker] = b;
    return b;
  }

  int get size => close.length;
}
