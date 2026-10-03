/// A corporate action from DART, as the scan sends it (`ca` in market-v2.json, signal/corporate.py):
/// a bonus or rights issue, a capital reduction, a stock split or merge that is still under way.
class CorpAction {
  CorpAction._(this.kind, this.decided, this.base, this.change, this.haltFrom, this.haltTo, this.listing,
      this.ratio, this.method, this.affects, this.isNew, this.soon);

  /// 무상증자, 유무상증자, 유상증자, 감자, 주식분할 or 주식병합.
  final String kind;

  /// Dates as yyyy-mm-dd, or null when the filing did not say: decided (first filing), record
  /// date, the day the price basis changes (ex-rights, or relisting), the trading halt and the
  /// new shares' listing.
  final String? decided, base, change, haltFrom, haltTo, listing;

  /// New shares per share (bonus issues), the rate (reductions), how a rights issue is offered.
  final String? ratio, method;

  /// The signal day is the day the price basis changed, or the trading day after: the day's
  /// signals may come from that, not from trading.
  final bool affects;

  /// Decided within the last three days.
  final bool isNew;

  /// What happens on the next trading day: 권리락, 매매정지 시작, 재상장.
  final List<String> soon;

  static CorpAction? parse(Object? o) {
    if (o is! Map || o['k'] is! String) return null;
    String? s(String k) => o[k] is String ? o[k] as String : null;
    return CorpAction._(o['k'] as String, s('d'), s('b'), s('c'), s('hf'), s('ht'), s('l'), s('r'), s('m'),
        o['w'] == 1, o['n'] == 1, [for (final x in (o['s'] is List ? o['s'] as List : const [])) '$x']);
  }

  bool get issue => kind.contains('증자');

  /// "10/13".
  static String md(String? iso) =>
      iso == null || iso.length < 10 ? '?' : '${int.parse(iso.substring(5, 7))}/${int.parse(iso.substring(8, 10))}';

  /// For a row's chip: the kind and its next date ("무상증자 · 권리락 10/13").
  String chip() {
    if (change != null) return '$kind · ${issue ? '권리락' : '재상장'} ${md(change)}';
    if (haltFrom != null) return '$kind · 정지 ${md(haltFrom)}';
    if (listing != null) return '$kind · 상장 ${md(listing)}';
    return kind;
  }

  /// Full wording: "무상증자 1주당 0.5주 · 권리락 10/13 · 신주 상장 11/5 (9/30 결정)".
  String describe() {
    final parts = <String>[
      kind +
          (ratio != null && issue ? ' 1주당 $ratio주' : '') +
          (method != null && kind == '유상증자' ? ' ($method)' : ''),
      if (change != null && issue) '권리락 ${md(change)}',
      if (haltFrom != null) '매매정지 ${md(haltFrom)}~${md(haltTo)}',
      if (listing != null) '신주 상장 ${md(listing)}',
    ];
    return '${parts.join(' · ')} (${md(decided)} 결정)';
  }
}
