import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/repo.dart';
import '../core/signals.dart' as signals;
import '../core/stock.dart';
import 'palette.dart';
import 'stock_tile.dart';

/// Every stock of an industry (`theme` false) or a theme, by market cap, in a sheet from the
/// bottom: price, change and today's signals. A tap opens the stock's chart on its own page.
Future<void> showGroup(BuildContext context, String name, {required bool theme}) {
  final stocks = [
    for (final s in Repo.I.stocks)
      if (theme ? s.themes.contains(name) : s.industry == name) s,
  ]..sort((a, b) => (b.cap.isNaN ? 0 : b.cap).compareTo(a.cap.isNaN ? 0 : a.cap));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => _GroupList(name: name, theme: theme, stocks: stocks, scroll: scroll),
    ),
  );
}

class _GroupList extends StatelessWidget {
  const _GroupList({required this.name, required this.theme, required this.stocks, required this.scroll});

  final String name;
  final bool theme;
  final List<Stock> stocks;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = Palette.of(context);
    final up = stocks.where((s) => s.changePct() > 0).length;
    final down = stocks.where((s) => s.changePct() < 0).length;
    final of = signals.hitsNow();
    return ListView.builder(
      controller: scroll,
      itemCount: stocks.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(theme ? '#$name' : name, style: t.titleLarge),
              const SizedBox(height: 2),
              Text.rich(TextSpan(style: t.bodyMedium!.copyWith(color: cs.onSurfaceVariant), children: [
                TextSpan(text: '${theme ? '테마' : '업종'} · ${stocks.length}종목 · '),
                TextSpan(text: '상승 $up', style: TextStyle(color: p.up)),
                const TextSpan(text: ' · '),
                TextSpan(text: '하락 $down', style: TextStyle(color: p.down)),
              ])),
            ]),
          );
        }
        final s = stocks[i - 1];
        return InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StockPage(stock: s))),
          onLongPress: () => copyStock(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withAlpha(0x80)))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                  Text('${s.ticker} · ${s.market} · 시총 ${compact(s.cap * 1e8)}',
                      style: t.bodySmall!.copyWith(color: cs.onSurfaceVariant)),
                  SignalChips(of(s), actions: s.actions),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(price(s.price()), style: t.titleSmall),
                Text(percent(s.changePct()), style: t.bodySmall!.copyWith(color: p.change(s.changePct()))),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

/// One stock on its own page (from a group's list): its numbers on top, then the usual detail.
class StockPage extends StatelessWidget {
  const StockPage({super.key, required this.stock});

  final Stock stock;

  @override
  Widget build(BuildContext context) {
    final s = stock;
    final t = Theme.of(context).textTheme;
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(s.name, style: t.titleMedium),
          Text('${price(s.price())} · ${percent(s.changePct())}',
              style: t.bodySmall!.copyWith(color: p.change(s.changePct()))),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.only(top: 8, bottom: 24), children: [
        StockDetail(stock: s, key: ValueKey('page-${s.ticker}')),
      ]),
    );
  }
}
