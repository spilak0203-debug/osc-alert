import '../core/market_index.dart';
import '../core/repo.dart';
import '../core/settings.dart';
import '../core/signals.dart' as signals;
import 'notifier.dart';

DateTime seoulNowForChecker() => seoulNow();

/// Every 30 minutes (Android's background job, or the running Windows app): fetch market.json.
/// When the signal day changes (after the close), evaluate the user's rule and notify. With the
/// pre-market option, repeat the same alerts once between 08:00 and 09:00 on the next weekday.
class Checker {
  static Future<void> check(DateTime now) async {
    final st = Settings.I;
    final stocks = await Repo.I.download();
    final asof = Repo.I.asof;
    if (asof.isEmpty) return;
    if (asof != st.string(Settings.notified, '')) {
      await Notifier.post(asof, signals.alerts(stocks), '');
      await st.prefs.setString(Settings.notified, asof);
      return;
    }
    final weekday = now.weekday != DateTime.saturday && now.weekday != DateTime.sunday;
    final morning = now.hour == 8;
    // Only repeat signals from a previous day — never on the evening they were first sent.
    final fromBefore = asof.compareTo(seoulDate(now)) < 0;
    if (st.flag(Settings.preMarket) && weekday && morning && fromBefore && asof != st.string(Settings.preMarketSent, '')) {
      await Notifier.post(asof, signals.alerts(stocks), '[장 시작 전] ');
      await st.prefs.setString(Settings.preMarketSent, asof);
    }
  }
}
