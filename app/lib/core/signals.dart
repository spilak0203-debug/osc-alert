import 'rule.dart';
import 'settings.dart';
import 'stock.dart';

/// Sorts stocks into signal kinds according to the current settings.
const names = ['스토캐스틱', 'RSI', 'CCI'];

enum Kind {
  gold3('골든 3지표 일치', true),
  dead3('데드 3지표 일치', false),
  gold2('골든 2지표 일치', true),
  dead2('데드 2지표 일치', false),
  oversoldIn('과매도 진입', true),
  oversoldOut('과매도 탈출', true),
  overboughtIn('과매수 진입', false),
  overboughtOut('과매수 탈출', false);

  const Kind(this.label, this.buySide);

  final String label;
  final bool buySide;

  bool get zone => index >= Kind.oversoldIn.index;

  /// The Java app's enum constant, used in notification payloads.
  String get legacyName => const [
        'GOLD3', 'DEAD3', 'GOLD2', 'DEAD2', 'OVERSOLD_IN', 'OVERSOLD_OUT', 'OVERBOUGHT_IN', 'OVERBOUGHT_OUT'
      ][index];

  static Kind? byName(String? name) {
    for (final k in Kind.values) {
      if (k.name == name || k.legacyName == name) return k;
    }
    return null;
  }
}

/// What one stock did on the signal day.
class Hit {
  Hit(this.kind, this.parts);

  final Kind kind;

  /// For 2-of-3: which indicators matched.
  final List<bool>? parts;

  String describe() {
    if (kind != Kind.gold2 && kind != Kind.dead2) return kind.label;
    return '${kind.label} (${which(parts!)})';
  }
}

String which(List<bool> parts) => [for (var j = 0; j < 3; j++) if (parts[j]) names[j]].join('·');

/// Every kind the stock shows today. Zone entry/exit: at least `zoneNeed` indicators in the
/// zone today but not yesterday (entry), or the other way round (exit).
List<Hit> hitsFor(Stock s, RuleConfig c, int zoneNeed) {
  final out = <Hit>[];
  final seq = s.seq;
  if (seq == null) return out;
  final m = match(seq, c);
  final g = count(m[0]), d = count(m[1]);
  if (g == 3) {
    out.add(Hit(Kind.gold3, m[0]));
  } else if (g == 2) {
    out.add(Hit(Kind.gold2, m[0]));
  }
  if (d == 3) {
    out.add(Hit(Kind.dead3, m[1]));
  } else if (d == 2) {
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

/// Stocks per kind for the dashboard. Every kind appears, even when empty.
Map<Kind, List<Stock>> group(List<Stock> stocks) {
  final st = Settings.I;
  final c = st.config();
  final need = st.integer(Settings.zoneNeed);
  final out = {for (final k in Kind.values) k: <Stock>[]};
  for (final s in stocks) {
    if (!st.passes(s)) continue;
    for (final h in hitsFor(s, c, need)) {
      out[h.kind]!.add(s);
    }
  }
  return out;
}

/// Whether the user asked to be notified about this kind.
bool alerting(Kind k) {
  final st = Settings.I;
  switch (k) {
    case Kind.gold3:
    case Kind.dead3:
      return st.flag(Settings.alert3);
    case Kind.gold2:
    case Kind.dead2:
      return st.flag(Settings.alert2);
    case Kind.oversoldIn:
    case Kind.overboughtIn:
      return st.flag(Settings.alertZoneIn);
    default:
      return st.flag(Settings.alertZoneOut);
  }
}

/// The subset that should ring.
Map<Kind, List<Stock>> alerts(List<Stock> stocks) {
  final all = group(stocks);
  all.removeWhere((k, _) => !alerting(k));
  return all;
}
