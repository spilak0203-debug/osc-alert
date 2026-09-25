import 'rule.dart';
import 'settings.dart';
import 'stock.dart';

/// Sorts stocks into signal kinds according to the current settings.
const names = ['스토캐스틱', 'RSI', 'CCI'];

/// A volume surge: at least this many times the previous trading day's volume...
const double surgeTimes = 3;

/// ...on a stock that trades at least this much a day (20-day average, won).
const double surgeLiquidity = 5e8;

/// Dashboard order. The three rising signals (volume surge, golden crossing, moving-average
/// breakout) are stacked: a stock with two or three of them is filed under the overlap only.
enum Kind {
  combo3('강도 매우 높음 (신호 3개)', true, 'COMBO3'),
  combo2('강도 높음 (신호 2개)', true, 'COMBO2'),
  maBreak('이평선 밀집 돌파', true, 'MA_BREAK'),
  gold3('골든 3지표 일치', true, 'GOLD3'),
  gold2('골든 2지표 일치', true, 'GOLD2'),
  surge('거래량 급증 (전일 3배↑)', true, 'SURGE'),
  dead3('데드 3지표 일치', false, 'DEAD3'),
  dead2('데드 2지표 일치', false, 'DEAD2'),
  oversoldIn('과매도 진입', true, 'OVERSOLD_IN'),
  oversoldOut('과매도 탈출', true, 'OVERSOLD_OUT'),
  overboughtIn('과매수 진입', false, 'OVERBOUGHT_IN'),
  overboughtOut('과매수 탈출', false, 'OVERBOUGHT_OUT');

  const Kind(this.label, this.buySide, this.legacyName);

  final String label;
  final bool buySide;

  /// The Java app's enum constant, used in notification payloads.
  final String legacyName;

  /// Oversold/overbought: for reference, shown small on the rows.
  bool get zone => index >= Kind.oversoldIn.index;

  Block get block => zone ? Block.zones : buySide ? Block.rising : Block.falling;

  /// One of the three rising signals whose overlaps are counted.
  bool get rising => this == surge || this == gold3 || this == gold2 || this == maBreak;

  static Kind? byName(String? name) {
    for (final k in Kind.values) {
      if (k.name == name || k.legacyName == name) return k;
    }
    return null;
  }
}

/// The summary's three parts, in order. The kinds of each part are next to each other in `Kind`.
enum Block {
  rising('상승 신호'),
  falling('하락 신호'),
  zones('참고 · 과매도·과매수');

  const Block(this.label);

  final String label;
}

/// What one stock did on the signal day.
class Hit {
  Hit(this.kind, this.parts, [this.times]);

  final Kind kind;

  /// For 2-of-3: which indicators matched.
  final List<bool>? parts;

  /// Volume surge: today's volume ÷ the previous trading day's.
  final double? times;

  /// Full wording, for the detail and notifications.
  String describe() {
    if (kind == Kind.surge) return '거래량 급증 (전일 ${times!.toStringAsFixed(1)}배)';
    if (kind != Kind.gold2 && kind != Kind.dead2) return kind.label;
    return '${kind.label} (${which(parts!)})';
  }

  /// Short wording for the chips on a row.
  String chip() {
    switch (kind) {
      case Kind.surge:
        return '거래량 ${times!.toStringAsFixed(1)}배';
      case Kind.gold3:
        return '골든 3지표';
      case Kind.gold2:
        return '골든 2지표';
      case Kind.dead3:
        return '데드 3지표';
      case Kind.dead2:
        return '데드 2지표';
      case Kind.maBreak:
        return '이평선 돌파';
      default:
        return kind.label;
    }
  }
}

String which(List<bool> parts) => [for (var j = 0; j < 3; j++) if (parts[j]) names[j]].join('·');

/// Every signal the stock shows today, rising ones first in the order volume, golden crossing,
/// moving averages. Zone entry/exit: at least `zoneNeed` indicators in the zone today but not
/// yesterday (entry), or the other way round (exit).
List<Hit> hitsFor(Stock s, RuleConfig c, int zoneNeed) {
  final out = <Hit>[];
  if (surged(s)) out.add(Hit(Kind.surge, null, s.volumeTimes));
  final seq = s.seq;
  final m = seq == null ? null : match(seq, c);
  if (m != null) {
    final g = count(m[0]);
    if (g == 3) {
      out.add(Hit(Kind.gold3, m[0]));
    } else if (g == 2 && c.pairs) {
      out.add(Hit(Kind.gold2, m[0]));
    }
  }
  final mb = s.maBreak;
  if (mb != null && (!c.maUp60 || mb.up60) && (!c.maUp120 || mb.up120)) out.add(Hit(Kind.maBreak, null));
  if (m == null) return out;
  final d = count(m[1]);
  if (d == 3) {
    out.add(Hit(Kind.dead3, m[1]));
  } else if (d == 2 && c.pairs) {
    out.add(Hit(Kind.dead2, m[1]));
  }
  final now = zones(s.last()!, c), before = zones(s.prev()!, c);
  if (now[0] >= zoneNeed && before[0] < zoneNeed) out.add(Hit(Kind.oversoldIn, null));
  if (now[0] < zoneNeed && before[0] >= zoneNeed) out.add(Hit(Kind.oversoldOut, null));
  if (now[1] >= zoneNeed && before[1] < zoneNeed) out.add(Hit(Kind.overboughtIn, null));
  if (now[1] < zoneNeed && before[1] >= zoneNeed) out.add(Hit(Kind.overboughtOut, null));
  return out;
}

List<Hit> hits(Stock s) {
  final st = Settings.I;
  return hitsFor(s, st.config(), st.integer(Settings.zoneNeed));
}

/// Whether the stock traded at least `surgeTimes` its previous day's volume (liquid stocks only).
bool surged(Stock s) => s.volumeTimes >= surgeTimes && s.dv20 >= surgeLiquidity;

/// Lower sorts first within a dashboard group: in the 2-overlap group, pairs that lean on the
/// volume surge go below the golden-crossing + moving-average pair.
int rank(Kind k, Stock s) => k == Kind.combo2 && surged(s) ? 1 : 0;

/// How many of the three rising signals the stock shows.
int overlap(List<Hit> hits) => hits.where((h) => h.kind.rising).length;

/// Stocks per kind for the dashboard. A stock with two or three rising signals goes under the
/// overlap instead of under each signal; falling and zone kinds are listed as they are.
/// Every kind appears, even when empty.
Map<Kind, List<Stock>> group(List<Stock> stocks) {
  final st = Settings.I;
  final c = st.config();
  final need = st.integer(Settings.zoneNeed);
  final out = {for (final k in Kind.values) k: <Stock>[]};
  for (final s in stocks) {
    if (!st.passes(s)) continue;
    final hs = hitsFor(s, c, need);
    final n = overlap(hs);
    if (n >= 2) out[n == 3 ? Kind.combo3 : Kind.combo2]!.add(s);
    for (final h in hs) {
      if (n < 2 || !h.kind.rising) out[h.kind]!.add(s);
    }
  }
  return out;
}

/// Every stock under every kind it shows, overlaps included — what notifications go by, so a
/// 3-indicator alert still lists a stock that also had a volume surge.
Map<Kind, List<Stock>> byKind(List<Stock> stocks) {
  final st = Settings.I;
  final c = st.config();
  final need = st.integer(Settings.zoneNeed);
  final out = {for (final k in Kind.values) k: <Stock>[]};
  for (final s in stocks) {
    if (!st.passes(s)) continue;
    final hs = hitsFor(s, c, need);
    final n = overlap(hs);
    if (n >= 2) out[n == 3 ? Kind.combo3 : Kind.combo2]!.add(s);
    for (final h in hs) {
      out[h.kind]!.add(s);
    }
  }
  return out;
}

/// Whether the user asked to be notified about this kind.
bool alerting(Kind k) {
  final st = Settings.I;
  switch (k) {
    case Kind.combo3:
    case Kind.combo2:
      return st.flag(Settings.alertCombo);
    case Kind.gold3:
    case Kind.dead3:
      return st.flag(Settings.alert3);
    case Kind.gold2:
    case Kind.dead2:
      return st.flag(Settings.alert2);
    case Kind.maBreak:
      return st.flag(Settings.alertMa);
    // Dozens a day; it rings as part of an overlap.
    case Kind.surge:
      return false;
    case Kind.oversoldIn:
    case Kind.overboughtIn:
      return st.flag(Settings.alertZoneIn);
    case Kind.oversoldOut:
    case Kind.overboughtOut:
      return st.flag(Settings.alertZoneOut);
  }
}

/// The subset that should ring.
Map<Kind, List<Stock>> alerts(List<Stock> stocks) {
  final all = byKind(stocks);
  all.removeWhere((k, _) => !alerting(k));
  return all;
}
