import 'dart:convert';

import 'settings.dart';
import 'signals.dart' as signals;
import 'stock.dart';

/// One stock the user owns, optionally with how many shares at what average price (NaN when
/// not given: no average-price line, no value). The name is kept so a stock that drops out of
/// market.json still shows.
class Holding {
  Holding(this.ticker, this.name, [this.avg = double.nan, this.qty = double.nan]);

  final String ticker, name;

  /// Average buy price (won) and shares; NaN when left blank.
  final double avg, qty;

  bool get hasAvg => avg > 0;

  bool get hasQty => qty > 0;

  /// Both given: value and gain in won can be worked out.
  bool get complete => hasAvg && hasQty;

  double get cost => avg * qty;

  /// Value at `price` and the gain over the cost (NaN when either is missing).
  double value(double price) => price * qty;

  double gain(double price) => value(price) - cost;

  /// The price's gain over the average, % (needs only the average).
  double rate(double price) => hasAvg ? (price / avg - 1) * 100 : double.nan;

  Map<String, Object> toJson() => {'t': ticker, 'n': name, if (hasAvg) 'a': avg, if (hasQty) 'q': qty};

  static Holding? fromJson(Object? o) {
    if (o is! Map) return null;
    final t = o['t'], a = o['a'], q = o['q'];
    if (t is! String) return null;
    return Holding(t, '${o['n'] ?? t}', a is num ? a.toDouble() : double.nan, q is num ? q.toDouble() : double.nan);
  }
}

/// The user's holdings, stored with the other settings (a JSON list, in the order added).
class Holdings {
  static const key = 'holdings';

  static List<Holding> all() {
    final text = Settings.I.prefs.getString(key);
    if (text == null || text.isEmpty) return [];
    try {
      return [for (final o in jsonDecode(text) as List) ?Holding.fromJson(o)];
    } catch (_) {
      return [];
    }
  }

  static Holding? of(String ticker) => all().where((h) => h.ticker == ticker).firstOrNull;

  static Set<String> tickers() => {for (final h in all()) h.ticker};

  /// Adds the stock, or replaces its average price and shares.
  static Future<void> put(Holding h) {
    final list = all();
    final i = list.indexWhere((x) => x.ticker == h.ticker);
    if (i < 0) {
      list.add(h);
    } else {
      list[i] = h;
    }
    return _save(list);
  }

  static Future<void> remove(String ticker) => _save(all()..removeWhere((h) => h.ticker == ticker));

  static Future<void> _save(List<Holding> list) =>
      Settings.I.setString(key, jsonEncode([for (final h in list) h.toJson()]));

  /// Holdings with a falling signal today (dead crossings), for their own notification. The
  /// stock filter does not apply: a holding is always watched.
  static List<Stock> falling(List<Stock> stocks) {
    final mine = tickers();
    if (mine.isEmpty) return [];
    final st = Settings.I;
    final c = st.config();
    final need = st.integer(Settings.zoneNeed);
    return [
      for (final s in stocks)
        if (mine.contains(s.ticker) && signals.hitsFor(s, c, need).any((h) => h.kind.block == signals.Block.falling)) s,
    ];
  }
}
