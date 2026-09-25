import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fmt.dart';
import 'rule.dart';
import 'stock.dart';

/// Everything the settings tab controls, stored in one preferences file. Listeners hear about
/// every change so screens redraw.
class Settings extends ChangeNotifier {
  Settings._();

  static final Settings I = Settings._();
  late SharedPreferences _p;

  static Future<void> init() async {
    I._p = await SharedPreferences.getInstance();
  }

  /// Background work runs in its own isolate; pick up what the app wrote since.
  Future<void> reload() => _p.reload();

  SharedPreferences get prefs => _p;

  // Alerts
  static const alert3 = 'alert3', alert2 = 'alert2';
  static const alertZoneIn = 'alertZoneIn', alertZoneOut = 'alertZoneOut';
  static const alertMa = 'alertMa';
  static const preMarket = 'preMarket', quietDays = 'quietDays';
  static const soundKey = 'sound'; // sound | vibrate | both | silent
  // Rule
  static const windowKey = 'window'; // 0..maxWindow days
  static const zoneNeed = 'zoneNeed'; // 1..3 indicators
  static const stochSlow = 'stochSlow';
  static const stochBand = 'stochBand', stochLo = 'stochLo', stochHi = 'stochHi';
  static const rsiBand = 'rsiBand', rsiLo = 'rsiLo', rsiHi = 'rsiHi';
  static const cciBand = 'cciBand', cciLevel = 'cciLevel';
  // Stock filter: applies to the dashboard, the stocks tab and alerts
  static const filterMarket = 'filterMarket'; // all | 코스피 | 코스닥
  static const filterDv = 'filterDv'; // minimum 20-day average trading value, 억원
  static const filterCap = 'filterCap'; // minimum market cap, 억원
  // Display
  static const themeKey = 'theme'; // system | light | dark
  static const fontScaleKey = 'fontScale';
  static const copyName = 'copyName'; // long press copies the name instead of the code
  static const showMa = 'showMa', showVolume = 'showVolume';
  static const showStoch = 'showStoch', showRsi = 'showRsi', showCci = 'showCci';
  // Desktop
  static const trayOnClose = 'trayOnClose', startWithWindows = 'startWithWindows';
  // Bookkeeping
  static const notified = 'notified', preMarketSent = 'preMarketSent';

  static const double fontMin = 0.7, fontMax = 2.0, fontStep = 0.1;

  bool flag(String key) => _p.getBool(key) ?? defaultFlag(key);

  static bool defaultFlag(String key) {
    switch (key) {
      case alert2:
      case alertZoneIn:
      case alertZoneOut:
      case alertMa:
      case preMarket:
      case quietDays:
      case copyName:
      case startWithWindows:
      // A plain crossing of the two lines is a cross signal; the oversold/overbought
      // condition is optional.
      case stochBand:
      case rsiBand:
        return false;
      default:
        return true;
    }
  }

  double number(String key) => _p.getDouble(key) ?? defaultNumber(key);

  static double defaultNumber(String key) {
    switch (key) {
      case stochLo:
        return 20;
      case stochHi:
        return 80;
      case rsiLo:
        return 30;
      case rsiHi:
        return 70;
      case cciLevel:
        return 100;
      default:
        return 0;
    }
  }

  int integer(String key) => _p.getInt(key) ?? (key == zoneNeed ? 2 : 0);

  String string(String key, String fallback) => _p.getString(key) ?? fallback;

  Future<void> setFlag(String key, bool v) => _save(_p.setBool(key, v));

  Future<void> setNumber(String key, double v) => _save(_p.setDouble(key, v));

  Future<void> setInteger(String key, int v) => _save(_p.setInt(key, v));

  Future<void> setString(String key, String v) => _save(_p.setString(key, v));

  Future<void> _save(Future<bool> write) async {
    notifyListeners();
    await write;
  }

  // ---- favourites -------------------------------------------------------------------------

  static const favoritesKey = 'favorites';

  Set<String> favorites() => (_p.getStringList(favoritesKey) ?? const []).toSet();

  bool favorite(String ticker) => favorites().contains(ticker);

  /// Adds or removes the stock; returns whether it is a favourite now.
  bool toggleFavorite(String ticker) {
    final set = favorites();
    final now = !set.remove(ticker);
    if (now) set.add(ticker);
    _save(_p.setStringList(favoritesKey, set.toList()..sort()));
    return now;
  }

  // ---- stock list order ---------------------------------------------------------------------

  static const sortKey = 'sort';
  static const sorts = ['favorite', 'cap', 'name', 'code', 'rise', 'fall'];
  static const sortLabels = ['즐겨찾기순', '시총순', '가나다순', '종목코드순', '급등순', '급락순'];

  String get sort => string(sortKey, 'favorite');

  String get theme => string(themeKey, 'system');

  String get sound => string(soundKey, 'both');

  double get fontScale => _p.getDouble(fontScaleKey) ?? 1.0;

  String get market => string(filterMarket, 'all');

  /// Whether a stock passes the user's filter.
  bool passes(Stock s) {
    final m = market;
    if (m != 'all' && m != s.market) return false;
    final dv = _p.getDouble(filterDv) ?? 0, cap = _p.getDouble(filterCap) ?? 0;
    if (dv > 0 && !(s.dv20 >= dv * 1e8)) return false;
    return cap <= 0 || s.cap >= cap; // market.json keeps the cap in 억원
  }

  /// "코스닥 · 거래대금 5억↑ · 시총 1,000억↑", or "" when nothing is filtered.
  String filterSummary() {
    final parts = <String>[];
    if (market != 'all') parts.add(market);
    final dv = _p.getDouble(filterDv) ?? 0, cap = _p.getDouble(filterCap) ?? 0;
    if (dv > 0) parts.add('거래대금 ${eok(dv)}↑');
    if (cap > 0) parts.add('시총 ${eok(cap)}↑');
    return parts.join(' · ');
  }

  RuleConfig config() {
    final r = RuleConfig()
      ..slow = flag(stochSlow)
      ..stochBand = flag(stochBand)
      ..rsiBand = flag(rsiBand)
      ..cciBand = flag(cciBand)
      ..stochLo = number(stochLo)
      ..stochHi = number(stochHi)
      ..rsiLo = number(rsiLo)
      ..rsiHi = number(rsiHi)
      ..cciLevel = number(cciLevel);
    r.window = integer(windowKey).clamp(0, maxWindow);
    return r;
  }

  /// Settings the Java app stored in its own preferences file ("osc"), copied over once so an
  /// update keeps the user's choices and favourites.
  Future<void> importLegacy(Map<String, Object?> old) async {
    if (_p.getBool('legacyImported') ?? false) return;
    for (final e in old.entries) {
      final v = e.value;
      if (v is bool) {
        await _p.setBool(e.key, v);
      } else if (v is int) {
        await _p.setInt(e.key, v);
      } else if (v is double) {
        await _p.setDouble(e.key, v);
      } else if (v is String) {
        await _p.setString(e.key, v);
      } else if (v is List) {
        await _p.setStringList(e.key, v.map((x) => '$x').toList());
      }
    }
    await _p.setBool('legacyImported', true);
    notifyListeners();
  }
}
