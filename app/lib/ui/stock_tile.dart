import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/bars.dart';
import '../core/fmt.dart';
import '../core/holdings.dart';
import '../core/repo.dart';
import '../core/rule.dart' as rule;
import '../core/settings.dart';
import '../core/signals.dart' as signals;
import '../core/stock.dart';
import 'chart.dart';
import 'holdings_page.dart';
import 'palette.dart';
import 'toast.dart';

void openNaver(Stock s) => launchUrl(Uri.parse(s.naverChartUrl()), mode: LaunchMode.externalApplication);

void copyStock(Stock s) {
  final what = Settings.I.flag(Settings.copyName) ? s.name : s.ticker;
  Clipboard.setData(ClipboardData(text: what));
  Toaster.show('복사했습니다: $what');
}

/// One stock: name, code and market (with oversold/overbought in small print) and chips for
/// today's signals on the left; price, change and volume on the right; then the favourite star
/// and the Naver link. A tap opens the detail (below the row
/// on phones, beside the list on wide screens); a long press or right click copies the code.
class StockTile extends StatelessWidget {
  const StockTile({super.key, required this.stock, required this.open, required this.onTap, this.selected = false});

  final Stock stock;

  /// Phones: the detail is shown under this row.
  final bool open;

  /// Wide screens: this row's stock is in the detail pane.
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = Palette.of(context);
    final s = stock;
    final hits = signals.hits(s);
    final sub = [s.ticker, s.market, for (final h in hits) if (h.kind.zone) h.kind.label].join(' · ');
    final fav = Settings.I.favorite(s.ticker);
    final head = InkWell(
      onTap: onTap,
      onLongPress: () => copyStock(s),
      onSecondaryTap: () => copyStock(s),
      child: Container(
        color: selected ? cs.secondaryContainer.withAlpha(0x80) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
              Text(sub, style: t.bodySmall!.copyWith(color: cs.onSurfaceVariant)),
              SignalChips(hits),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(price(s.price()), style: t.titleMedium),
            Text(percent(s.changePct()), style: t.bodyMedium!.copyWith(color: p.change(s.changePct()))),
            Text('거래량 ${compact(s.tradedVolume())}', style: t.bodySmall!.copyWith(color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(width: 4),
          _IconSpot(
            tooltip: '즐겨찾기 별',
            icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Palette.favorite : cs.onSurfaceVariant),
            onTap: () {
              final now = Settings.I.toggleFavorite(s.ticker);
              Toaster.show('${s.name}${now ? ' 즐겨찾기에 추가' : ' 즐겨찾기에서 뺌'}');
            },
          ),
          const SizedBox(width: 4),
          _IconSpot(
            tooltip: '네이버 차트',
            icon: Icon(Icons.open_in_new, color: cs.primary),
            onTap: () => openNaver(s),
          ),
        ]),
      ),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head,
      if (open)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: StockDetail(stock: s, key: ValueKey('detail-${s.ticker}')),
        ),
      const Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
    ]);
  }
}

/// A row's chips for today's signals (oversold/overbought left out), with the strength first.
class SignalChips extends StatelessWidget {
  const SignalChips(this.hits, {super.key});

  final List<signals.Hit> hits;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final chips = [for (final h in hits) if (!h.kind.zone) h];
    if (chips.isEmpty) return const SizedBox.shrink();
    final stacked = signals.overlap(hits);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 4, runSpacing: 4, children: [
        if (stacked >= 2) _Chip(stacked >= 3 ? '매우 높음' : '높음', p.side(true), solid: true),
        for (final h in chips) _Chip(h.chip(), p.side(h.kind.buySide)),
      ]),
    );
  }
}

/// A small rounded label for one signal on a row; `solid` for the overlap count.
class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color, {this.solid = false});

  final String text;
  final Color color;
  final bool solid;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: solid ? color : color.withAlpha(0x24),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: solid ? Colors.white : color,
                  fontWeight: FontWeight.w700,
                )),
      );
}

class _IconSpot extends StatelessWidget {
  const _IconSpot({required this.icon, required this.onTap, required this.tooltip});

  final Widget icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        waitDuration: const Duration(seconds: 1),
        child: InkResponse(
          onTap: onTap,
          radius: 20,
          child: SizedBox(width: 36, height: 36, child: Center(child: icon)),
        ),
      );
}

/// Metrics, the day's signals, the indicator table, the chart legend, the panel toggles, the
/// charts and a link to Naver.
class StockDetail extends StatefulWidget {
  const StockDetail({super.key, required this.stock, this.wide = false});

  final Stock stock;

  /// In the side pane of a wide window (mouse hints instead of touch hints).
  final bool wide;

  @override
  State<StockDetail> createState() => _StockDetailState();
}

class _StockDetailState extends State<StockDetail> {
  /// Zoom and scroll for this stock; a different stock starts from the default view.
  final ChartGroup group = ChartGroup();
  Bars? bars;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(StockDetail old) {
    super.didUpdateWidget(old);
    if (old.stock.ticker != widget.stock.ticker) {
      group.reset();
      bars = null;
      error = null;
      _load();
    }
  }

  @override
  void dispose() {
    group.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ticker = widget.stock.ticker;
    final cached = Bars.cached(ticker);
    if (cached != null) {
      bars = cached;
      return;
    }
    try {
      final b = await Bars.load(ticker);
      if (mounted && widget.stock.ticker == ticker) setState(() => bars = b);
    } catch (e) {
      if (mounted && widget.stock.ticker == ticker) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stock;
    final st = Settings.I;
    final cfg = st.config();
    final p = Palette.of(context);
    final hits = signals.hits(s);
    const gap = SizedBox(height: 10);
    final info = <Widget>[_metrics(context, s)];
    if (hits.isNotEmpty) {
      info
        ..add(gap)
        ..add(Wrap(spacing: 6, runSpacing: 6, children: [
          for (final h in hits) _tag(context, h.describe(), p.side(h.kind.buySide), true),
        ]));
    }
    if (s.seq != null) info..add(gap)..add(_indicatorTable(context, s, cfg));
    info..add(gap)..add(_legend(context, cfg));
    if (error != null) {
      info.add(Text('차트를 불러오지 못했습니다: $error', style: Theme.of(context).textTheme.bodySmall));
    }
    const toggles = [
      [Settings.showMa, '이평선'],
      [Settings.showVolume, '거래량'],
      [Settings.showStoch, '스토캐스틱'],
      [Settings.showRsi, 'RSI'],
      [Settings.showCci, 'CCI'],
    ];
    final panels = <Widget>[
      ChartPanel(type: ChartType.candle, bars: bars, cfg: cfg, group: group, showMa: st.flag(Settings.showMa)),
      if (st.flag(Settings.showVolume)) ChartPanel(type: ChartType.volume, bars: bars, cfg: cfg, group: group),
      if (st.flag(Settings.showStoch)) ChartPanel(type: ChartType.stoch, bars: bars, cfg: cfg, group: group),
      if (st.flag(Settings.showRsi)) ChartPanel(type: ChartType.rsi, bars: bars, cfg: cfg, group: group),
      if (st.flag(Settings.showCci)) ChartPanel(type: ChartType.cci, bars: bars, cfg: cfg, group: group),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: info),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, runSpacing: 4, children: [
          for (final d in toggles)
            FilterChip(
              label: Text(d[1]),
              showCheckmark: false,
              selected: st.flag(d[0]),
              onSelected: (on) => setState(() => st.setFlag(d[0], on)),
            ),
        ]),
      ),
      ...panels,
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => openNaver(s), child: const Text('네이버증권에서 차트 보기'))),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => editHolding(context, s.ticker, s.name, s.price()),
              child: Text(Holdings.of(s.ticker) == null ? '보유종목에 추가' : '보유 수량·평단 수정'),
            ),
          ),
        ]),
      ),
    ]);
  }

  // ---- detail pieces -----------------------------------------------------------------------

  /// A soft rounded panel that groups related lines.
  Widget _panel(BuildContext context, List<Widget> children) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(0x80),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  /// A pill: solid for what counts today, tinted for context.
  Widget _tag(BuildContext context, String text, Color color, bool strong) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: strong ? color : color.withAlpha(0x24),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: Theme.of(context).textTheme.labelMedium!.copyWith(color: strong ? Colors.white : color)),
      );

  /// Market cap and liquidity side by side.
  Widget _metrics(BuildContext context, Stock s) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final items = [
      ['시가총액', '${compact(s.cap * 1e8)}원'],
      ['20일 평균 거래대금', '${compact(s.dv20)}원'],
    ];
    return Row(children: [
      for (final it in items)
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it[0], style: t.bodySmall!.copyWith(color: muted)),
            Text(it[1], style: t.titleMedium),
          ]),
        ),
    ]);
  }

  /// One row per indicator: name, yesterday → today, and what happened, as tags.
  Widget _indicatorTable(BuildContext context, Stock s, rule.RuleConfig cfg) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final pal = Palette.of(context);
    final p = s.prev()!, l = s.last()!;
    final plain = cfg.plain();
    final g = rule.golden(p, l, cfg), d = rule.dead(p, l, cfg);
    final pg = rule.golden(p, l, plain), pd = rule.dead(p, l, plain);
    final v = [
      [cfg.slow ? p.kSlow : p.kFast, cfg.slow ? l.kSlow : l.kFast],
      [p.rsi, l.rsi],
      [p.cci, l.cci],
    ];
    final zone = [
      [cfg.stochLo, cfg.stochHi],
      [cfg.rsiLo, cfg.rsiHi],
      [-cfg.cciLevel, cfg.cciLevel],
    ];
    final rows = <Widget>[
      Text('${Repo.I.asof.replaceAll('-', '.')} 종가 · 전날 → 당일', style: t.labelMedium!.copyWith(color: muted)),
    ];
    for (var j = 0; j < 3; j++) {
      final tags = <Widget>[];
      final zoneText = _zoneEvent(v[j][0], v[j][1], zone[j][0], zone[j][1]);
      if (zoneText.isNotEmpty) {
        final event = zoneText.endsWith('진입') || zoneText.endsWith('탈출');
        tags.add(_tag(context, zoneText, zoneText.startsWith('과매도') ? pal.up : pal.down, event));
      }
      if (g[j]) {
        tags.add(_tag(context, '골든크로스', pal.up, true));
      } else if (j != 2 && pg[j]) {
        tags.add(_tag(context, '골든크로스 · 조건 밖', pal.up, false));
      }
      if (d[j]) {
        tags.add(_tag(context, '데드크로스', pal.down, true));
      } else if (j != 2 && pd[j]) {
        tags.add(_tag(context, '데드크로스 · 조건 밖', pal.down, false));
      }
      if (tags.isEmpty) tags.add(Text('변화 없음', style: t.bodySmall!.copyWith(color: muted)));
      final a = v[j][0], b = v[j][1];
      final value = j == 2 ? '${a.toStringAsFixed(0)} → ${b.toStringAsFixed(0)}' : '${a.toStringAsFixed(1)} → ${b.toStringAsFixed(1)}';
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          SizedBox(
            width: 84,
            child: Text(j == 0 ? (cfg.slow ? '스토캐스틱' : '스토캐스틱 F') : signals.names[j], style: t.titleSmall),
          ),
          SizedBox(
            width: 112,
            child: Text(value, style: t.bodyMedium!.copyWith(color: b > a ? pal.up : b < a ? pal.down : muted)),
          ),
          Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: tags)),
        ]),
      ));
    }
    return _panel(context, rows);
  }

  /// What the marks on the charts mean, and how to move around them.
  Widget _legend(BuildContext context, rule.RuleConfig cfg) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final p = Palette.of(context);
    // Small dots only exist when a band condition filters some crossings out.
    final filtered = cfg.stochBand || cfg.rsiBand;
    final lines = filtered
        ? const [
            ['▲▼', '3지표 일치 · 진한 세로 띠가 일치 구간'],
            ['△▽', '2지표 일치 · 연한 세로 띠'],
            ['●', '큰 점 · 신호가 되는 교차 (밴드 조건 충족)'],
            ['•', '작은 점 · 밴드 조건 밖의 교차 (참고용)'],
            ['○', '고리 · 과매도·과매수 선을 지난 곳'],
          ]
        : const [
            ['▲▼', '3지표 일치 · 진한 세로 띠가 일치 구간'],
            ['△▽', '2지표 일치 · 연한 세로 띠'],
            ['●', '점 · 골든크로스(빨강)·데드크로스(파랑). CCI는 ±기준선 돌파'],
            ['○', '고리 · 과매도·과매수 선을 지난 곳'],
          ];
    final children = <Widget>[
      Text('차트 표시 · 빨강은 골든·과매도 쪽, 파랑은 데드·과매수 쪽', style: t.labelMedium!.copyWith(color: muted)),
    ];
    children.add(Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text.rich(TextSpan(style: t.bodySmall, children: [
        const TextSpan(text: '┊', style: TextStyle(color: Palette.maBreak, fontWeight: FontWeight.w700)),
        TextSpan(text: '  보라 점선 · 이평선 밀집 돌파 (5·20·60·120일선이 ${Settings.I.maSpread}% 안에 모였다가 종가가 넷 다 위로)'),
      ])),
    ));
    for (final line in lines) {
      if (!cfg.pairs && line[0] == '△▽') continue;
      final mark = line[0];
      children.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text.rich(TextSpan(style: t.bodySmall, children: [
          TextSpan(text: mark.substring(0, 1), style: TextStyle(color: p.up)),
          TextSpan(text: mark.length > 1 ? mark.substring(1) : mark, style: TextStyle(color: p.down)),
          TextSpan(text: '  ${line[1]}'),
        ])),
      ));
    }
    children.add(Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        widget.wide
            ? 'Ctrl+휠로 확대 · 끌어서 이동 · 마우스를 올려 값 보기 · 더블클릭하면 처음으로'
            : '두 손가락으로 확대 · 옆으로 밀어 이동 · 탭하거나 길게 눌러 값 보기 · 두 번 탭하면 처음으로',
        style: t.bodySmall!.copyWith(color: muted),
      ),
    ));
    return _panel(context, children);
  }

  String _zoneEvent(double before, double now, double lo, double hi) {
    final wasLow = before < lo, isLow = now < lo, wasHigh = before > hi, isHigh = now > hi;
    if (isLow && !wasLow) return '과매도 진입';
    if (wasLow && !isLow) return '과매도 탈출';
    if (isHigh && !wasHigh) return '과매수 진입';
    if (wasHigh && !isHigh) return '과매수 탈출';
    if (isLow) return '과매도 구간';
    if (isHigh) return '과매수 구간';
    return '';
  }
}
