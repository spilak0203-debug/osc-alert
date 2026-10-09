import '../core/holdings.dart';
import '../core/market_index.dart';
import '../core/news.dart';
import '../core/repo.dart';
import '../core/settings.dart';
import '../core/signals.dart' as signals;
import '../core/stock.dart';
import 'notifier.dart';

DateTime seoulNowForChecker() => seoulNow();

/// Every 30 minutes (Android's background job, or the running Windows app): fetch market.json.
/// When the signal day changes (after the close), evaluate the user's rule and notify. With the
/// pre-market option, repeat the same alerts once between 08:00 and 09:00 on the next trading day —
/// never on a weekend or KRX holiday morning. Between 07:00 and 09:00 on trading days, also
/// announce the morning's briefing once it is up.
class Checker {
  static Future<void> check(DateTime now) async {
    final st = Settings.I;
    try {
      await _briefing(now);
    } catch (_) {} // optional: never in the way of the signals
    final stocks = await Repo.I.download();
    final asof = Repo.I.asof;
    if (asof.isEmpty) return;
    if (asof != st.string(Settings.notified, '')) {
      await Notifier.post(asof, signals.alerts(stocks), '', _holdings(stocks), _corporate(stocks));
      await st.prefs.setString(Settings.notified, asof);
      return;
    }
    final open = krxOpen(now);
    final morning = now.hour == 8;
    // Only repeat signals from a previous day — never on the evening they were first sent.
    final fromBefore = asof.compareTo(seoulDate(now)) < 0;
    if (st.flag(Settings.preMarket) && open && morning && fromBefore && asof != st.string(Settings.preMarketSent, '')) {
      await Notifier.post(asof, signals.alerts(stocks), '[장 시작 전] ', _holdings(stocks), _corporate(stocks));
      await st.prefs.setString(Settings.preMarketSent, asof);
    }
  }

  /// The pre-market briefing, once per trading day, between 07:00 and the open.
  static Future<void> _briefing(DateTime now) async {
    final st = Settings.I;
    if (!st.flag(Settings.alertBriefing) || !krxOpen(now) || now.hour < 7 || now.hour >= 9) return;
    final sent = st.string(Settings.briefingSent, '');
    if (sent == seoulDate(now)) return;
    final b = await News.download();
    Repo.I
      ..briefing = b
      ..changed();
    if (!b.due(now, sent)) return;
    await Notifier.briefing(b);
    await st.prefs.setString(Settings.briefingSent, b.date);
  }

  static List<Stock> _holdings(List<Stock> stocks) =>
      Settings.I.flag(Settings.alertHoldings) ? Holdings.falling(stocks) : const [];

  static List<Stock> _corporate(List<Stock> stocks) =>
      Settings.I.flag(Settings.alertCorporate) ? Holdings.corporate(stocks) : const [];
}
