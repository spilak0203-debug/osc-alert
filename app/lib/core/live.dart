import 'net.dart';
import 'stock.dart';

/// Current prices from Naver. During the session these are live; after the close, the close.
class Quote {
  double price = double.nan, change = double.nan, volume = double.nan;
}

class Live {
  static const _page = 'https://m.stock.naver.com/api/stocks/marketValue/%m?page=%p&pageSize=100';
  static const _poll = 'https://polling.finance.naver.com/api/realtime/domestic/stock/';

  /// Every listed stock, page by page (about 28 requests, four at a time).
  static Future<Map<String, Quote>> all() async {
    final urls = <String>[];
    // KOSPI has about 9 pages and KOSDAQ about 19; ask for a few extra and stop on empty ones.
    for (final market in ['KOSPI', 'KOSDAQ']) {
      final pages = market == 'KOSPI' ? 12 : 22;
      for (var p = 1; p <= pages; p++) {
        urls.add(_page.replaceFirst('%m', market).replaceFirst('%p', '$p'));
      }
    }
    final out = <String, Quote>{};
    for (var i = 0; i < urls.length; i += 4) {
      final batch = urls.sublist(i, i + 4 > urls.length ? urls.length : i + 4);
      final pages = await Future.wait(batch.map(Net.json));
      for (final page in pages) {
        final rows = page is Map ? page['stocks'] : null;
        if (rows is List) {
          for (final o in rows) {
            _put(out, o as Map<String, dynamic>);
          }
        }
      }
    }
    return out;
  }

  /// A handful of stocks in one or a few requests (used by the summary tab).
  static Future<Map<String, Quote>> some(List<String> tickers) async {
    final out = <String, Quote>{};
    for (var from = 0; from < tickers.length; from += 40) {
      final chunk = tickers.sublist(from, from + 40 > tickers.length ? tickers.length : from + 40);
      final root = await Net.json(_poll + chunk.join(','));
      final rows = root is Map ? root['datas'] : null;
      if (rows is List) {
        for (final o in rows) {
          _put(out, o as Map<String, dynamic>);
        }
      }
    }
    return out;
  }

  static void _put(Map<String, Quote> out, Map<String, dynamic> o) {
    final q = Quote()
      ..price = raw(o, 'closePriceRaw', 'closePrice')
      ..volume = raw(o, 'accumulatedTradingVolumeRaw', 'accumulatedTradingVolume')
      ..change = raw(o, 'fluctuationsRatioRaw', 'fluctuationsRatio');
    // Naver sends the ratio unsigned for falls in some responses; the direction code fixes it.
    final code = direction(o);
    if ((code == '4' || code == '5') && q.change > 0) q.change = -q.change;
    if (!q.price.isNaN) out['${o['itemCode']}'] = q;
  }

  static String direction(Map<String, dynamic> o) {
    final dir = o['compareToPreviousPrice'];
    return dir is Map ? '${dir['code'] ?? ''}' : '';
  }

  static double raw(Map<String, dynamic> o, String rawKey, String textKey) {
    var v = '${o[rawKey] ?? ''}';
    if (v.isEmpty || v == 'null') v = '${o[textKey] ?? ''}';
    return double.tryParse(v.replaceAll(',', '')) ?? double.nan;
  }

  static void apply(List<Stock> stocks, Map<String, Quote> quotes) {
    for (final s in stocks) {
      final q = quotes[s.ticker];
      if (q == null) continue;
      s.livePrice = q.price;
      s.liveChange = q.change;
      s.liveVolume = q.volume;
    }
  }
}
