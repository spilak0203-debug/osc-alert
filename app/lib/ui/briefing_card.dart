import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/fmt.dart';
import '../core/market_index.dart';
import '../core/news.dart';
import '../core/repo.dart';
import '../core/stock.dart';
import 'palette.dart';

/// The summary's pre-market briefing: the headline and the three key points; unfolded, each
/// section with its sources, the stocks it names (a tap opens the stock), and where it came from.
/// A tap on the title folds or unfolds it.
class BriefingCard extends StatelessWidget {
  const BriefingCard({super.key, required this.briefing, required this.open, required this.onToggle, this.onStock});

  final Briefing briefing;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<Stock>? onStock;

  @override
  Widget build(BuildContext context) {
    final b = briefing;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final age = b.age(seoulDate(seoulNow()));
    final when = age == 0 ? '오늘 ${b.at}'.trim() : (age > 0 ? '지난 브리핑 · ${b.day}' : '${b.day} 장');
    final body = <Widget>[
      if (b.headline.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(b.headline, style: t.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
        ),
      for (final k in b.key) _bullet(context, Text(k, style: t.bodyMedium)),
    ];
    if (open) {
      for (final s in b.sections) {
        body.add(_heading(context, s.title));
        for (final i in s.items) {
          body.add(_bullet(context, _cited(context, i)));
        }
      }
      if (b.stocks.isNotEmpty) {
        body.add(_heading(context, '눈여겨볼 종목'));
        for (final s in b.stocks) {
          body.add(_stock(context, s));
        }
      }
      body.add(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          '${b.modelName}(AI)가 ${b.articles > 0 ? '기사 ${b.articles}건을 읽고' : '웹 검색으로'} 정리 · '
          'AI 요약이라 틀릴 수 있으니 중요한 건 출처 태그로 원문을 확인하세요 · 투자 권유가 아닙니다',
          style: t.bodySmall!.copyWith(color: cs.onSurfaceVariant),
        ),
      ));
    } else if (b.sections.isNotEmpty) {
      body.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('펼치면 ${[for (final s in b.sections) s.title].join(' · ')}${b.stocks.isEmpty ? '' : ' · 종목 ${b.stocks.length}'}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall!.copyWith(color: cs.onSurfaceVariant)),
      ));
    }
    return Card.filled(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.newspaper_outlined, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('장 시작 전 브리핑', style: t.titleSmall!.copyWith(fontWeight: FontWeight.w700))),
              Text(when, style: t.bodySmall!.copyWith(color: cs.onSurfaceVariant)),
              Icon(open ? Icons.expand_less : Icons.expand_more, color: cs.onSurfaceVariant),
            ]),
            ...body,
          ]),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, String text) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Text(text, style: t.labelLarge!.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
    );
  }

  Widget _bullet(BuildContext context, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 4, right: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('•  ', style: Theme.of(context).textTheme.bodyMedium),
          Expanded(child: child),
        ]),
      );

  /// An item's text, then a small tag per source that opens the article.
  Widget _cited(BuildContext context, BriefItem i) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Text.rich(TextSpan(style: t.bodyMedium, children: [
      TextSpan(text: i.text),
      for (final s in briefing.cited(i))
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Tooltip(
              message: s.title,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(s.press.isEmpty ? '출처' : s.press, style: t.labelSmall!.copyWith(color: cs.onSurfaceVariant)),
                ),
              ),
            ),
          ),
        ),
    ]));
  }

  /// A named stock: tappable with today's change when it is on the list, plain text otherwise.
  Widget _stock(BuildContext context, BriefStock b) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final s = Repo.I.stocks.where((x) => x.name == b.name).firstOrNull;
    final p = Palette.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text.rich(TextSpan(children: [
        TextSpan(
            text: b.name,
            style: t.titleSmall!.copyWith(color: s == null ? null : cs.primary, fontWeight: FontWeight.w700)),
        if (s != null) TextSpan(text: '  ${percent(s.changePct())}', style: t.bodySmall!.copyWith(color: p.change(s.changePct()))),
        if (b.note.isNotEmpty) TextSpan(text: '  ${b.note}', style: t.bodyMedium!.copyWith(color: cs.onSurfaceVariant)),
      ])),
    );
    if (s == null || onStock == null) return row;
    return InkWell(onTap: () => onStock!(s), child: row);
  }
}
