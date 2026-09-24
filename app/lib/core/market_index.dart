import 'bars.dart';
import 'live.dart';
import 'net.dart';

/// KOSPI and KOSDAQ for the dashboard: live quote, daily bars, and whether the market is open today.
class MarketIndex {
  MarketIndex(this.code);

  static const codes = ['KOSPI', 'KOSDAQ'];

  final String code;
  double price = double.nan, change = double.nan, changePct = double.nan;
  String status = '', tradedAt = '';
  Bars? bars;

  String get label => code == 'KOSPI' ? '코스피' : '코스닥';

  /// Quote and about a year of daily bars.
  static Future<MarketIndex> load(String code) async {
    final m = MarketIndex(code);
    final root = await Net.json('https://polling.finance.naver.com/api/realtime/domestic/index/$code');
    final datas = root is Map ? root['datas'] : null;
    if (datas is List && datas.isNotEmpty) {
      final d = datas.first as Map<String, dynamic>;
      m.price = Live.raw(d, 'closePriceRaw', 'closePrice');
      m.change = Live.raw(d, 'compareToPreviousClosePriceRaw', 'compareToPreviousClosePrice');
      m.changePct = Live.raw(d, 'fluctuationsRatioRaw', 'fluctuationsRatio');
      final c = Live.direction(d);
      if ((c == '4' || c == '5') && m.changePct > 0) {
        m.changePct = -m.changePct;
        m.change = -m.change.abs();
      }
      m.status = '${d['marketStatus'] ?? ''}';
      m.tradedAt = '${d['localTradedAt'] ?? ''}';
    }
    m.bars = await Bars.load(code);
    return m;
  }

  /// What the market is doing right now, in words. Holidays are recognised because the index's
  /// last trade is not from today even though the session hours have started.
  String session(DateTime now) {
    if (status == 'OPEN') return '장중';
    final today = seoulDate(now);
    if (tradedAt.startsWith(today)) return '장 마감';
    final weekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    if (weekend) return '주말 휴장';
    if (now.hour < 9) return '개장 전';
    return tradedAt.isEmpty ? '' : '휴장';
  }
}

/// Now in Korea (UTC+9, no daylight saving), as a wall-clock DateTime.
DateTime seoulNow() => DateTime.now().toUtc().add(const Duration(hours: 9));

String seoulDate(DateTime seoul) =>
    '${seoul.year}-${seoul.month.toString().padLeft(2, '0')}-${seoul.day.toString().padLeft(2, '0')}';
