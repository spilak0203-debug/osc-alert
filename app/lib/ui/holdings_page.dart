import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fmt.dart';
import '../core/holdings.dart';
import '../core/repo.dart';
import '../core/settings.dart';
import '../core/signals.dart' as signals;
import '../core/stock.dart';
import 'palette.dart';
import 'stock_tile.dart';
import 'toast.dart';

/// The user's holdings: the total value and gain on top, then each stock with its shares,
/// average price, gain and today's signals. A tap opens the chart (below the row on phones,
/// beside the list on wide screens); the pencil edits the shares and average price.
class HoldingsPage extends StatefulWidget {
  const HoldingsPage({super.key, this.wide = false, this.selected, this.onSelect});

  final bool wide;
  final String? selected;
  final ValueChanged<Stock>? onSelect;

  @override
  State<HoldingsPage> createState() => _HoldingsPageState();
}

class _HoldingsPageState extends State<HoldingsPage> {
  String? _expanded;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Repo.I, Settings.I]),
      builder: (context, _) {
        final byTicker = {for (final s in Repo.I.stocks) s.ticker: s};
        final rows = [for (final h in Holdings.all()) (h, byTicker[h.ticker])];
        // Biggest position first.
        double value((Holding, Stock?) r) => r.$2 == null ? r.$1.cost : r.$1.value(r.$2!.price());
        rows.sort((a, b) => value(b).compareTo(value(a)));
        final add = FloatingActionButton.extended(
          heroTag: 'holdings-add',
          onPressed: () => addHolding(context),
          icon: const Icon(Icons.add),
          label: const Text('종목 추가'),
        );
        if (rows.isEmpty) return Stack(children: [_empty(context), Positioned(right: 16, bottom: 16, child: add)]);
        return Stack(children: [
          ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            _total(context, rows),
            for (final r in rows) _row(context, r.$1, r.$2),
          ]),
          Positioned(right: 16, bottom: 16, child: add),
        ]);
      },
    );
  }

  Widget _empty(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.account_balance_wallet_outlined, size: 48, color: muted),
          const SizedBox(height: 12),
          Text('보유종목이 없습니다', style: t.titleMedium),
          const SizedBox(height: 6),
          Text('아래 [종목 추가]로 매수가와 수량을 넣으면 수익률과 오늘 신호를 여기서 봅니다.\n'
              '보유종목에 데드크로스가 뜨면 따로 알려 드립니다.',
              textAlign: TextAlign.center, style: t.bodyMedium!.copyWith(color: muted)),
        ]),
      ),
    );
  }

  /// Value, gain and cost of everything, and today's move in won.
  Widget _total(BuildContext context, List<(Holding, Stock?)> rows) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final p = Palette.of(context);
    var cost = 0.0, value = 0.0, today = 0.0;
    for (final (h, s) in rows) {
      cost += h.cost;
      final price = s?.price() ?? double.nan;
      if (price.isNaN) {
        value += h.cost;
        continue;
      }
      value += h.value(price);
      final pct = s!.changePct();
      if (!pct.isNaN) today += h.value(price) - h.value(price / (1 + pct / 100));
    }
    final gain = value - cost, rate = cost > 0 ? gain / cost * 100 : double.nan;
    Widget cell(String label, String text, [Color? color]) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: t.bodySmall!.copyWith(color: muted)),
            Text(text, style: t.titleSmall!.copyWith(color: color, fontWeight: FontWeight.w700)),
          ]),
        );
    return Card.filled(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('평가금액', style: t.bodySmall!.copyWith(color: muted)),
          Text('${grouped(value)}원', style: t.headlineSmall!.copyWith(fontWeight: FontWeight.w700)),
          Text('${won(gain)} (${percent(rate)})', style: t.titleMedium!.copyWith(color: p.change(gain))),
          const SizedBox(height: 12),
          Row(children: [
            cell('매입금액', '${grouped(cost)}원'),
            cell('오늘', won(today), p.change(today)),
            cell('종목 수', '${rows.length}종목'),
          ]),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, Holding h, Stock? s) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = Palette.of(context);
    final price = s?.price() ?? double.nan;
    final gain = h.gain(price), rate = h.rate(price);
    final hits = s == null ? const <signals.Hit>[] : signals.hits(s);
    final zones = [for (final x in hits) if (x.kind.zone) x.kind.label];
    final open = !widget.wide && _expanded == h.ticker;
    final head = InkWell(
      onTap: s == null
          ? null
          : () {
              if (widget.wide) {
                widget.onSelect?.call(s);
              } else {
                setState(() => _expanded = open ? null : h.ticker);
              }
            },
      onLongPress: s == null ? null : () => copyStock(s),
      child: Container(
        color: widget.wide && widget.selected == h.ticker ? cs.secondaryContainer.withAlpha(0x80) : null,
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
              Text(
                  [
                    '${grouped(h.qty)}주 · 평단 ${grouped(h.avg)}원',
                    if (s == null) '시세 없음',
                    ...zones,
                  ].join(' · '),
                  style: t.bodySmall!.copyWith(color: cs.onSurfaceVariant)),
              SignalChips(hits),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(price.isNaN ? '-' : '${grouped(h.value(price))}원', style: t.titleMedium),
            Text(price.isNaN ? '-' : '${won(gain)} (${percent(rate)})',
                style: t.bodyMedium!.copyWith(color: p.change(gain))),
            Text('현재가 ${price.isNaN ? '-' : grouped(price)} (${percent(s?.changePct() ?? double.nan)})',
                style: t.bodySmall!.copyWith(color: cs.onSurfaceVariant)),
          ]),
          IconButton(
            tooltip: '수량·평단 수정',
            icon: Icon(Icons.edit_outlined, color: cs.onSurfaceVariant),
            onPressed: () => editHolding(context, h.ticker, h.name, price),
          ),
        ]),
      ),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head,
      if (open && s != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: StockDetail(stock: s, key: ValueKey('holding-${s.ticker}')),
        ),
      const Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
    ]);
  }
}

/// "+12,345원" / "-1,000원".
String won(double v) => v.isNaN ? '-' : '${signed(v, 0)}원';

/// Picks a stock by name or code, then asks for the shares and average price.
Future<void> addHolding(BuildContext context) async {
  final s = await showDialog<Stock>(context: context, builder: (_) => const _PickStock());
  if (s == null || !context.mounted) return;
  await editHolding(context, s.ticker, s.name, s.price());
}

/// Shares and average price for one stock (`price` fills in a new one's average); saving an
/// existing holding replaces it, and it can be removed here.
Future<void> editHolding(BuildContext context, String ticker, String name, double price) =>
    showDialog(context: context, builder: (_) => _EditHolding(ticker: ticker, name: name, price: price));

class _PickStock extends StatefulWidget {
  const _PickStock();

  @override
  State<_PickStock> createState() => _PickStockState();
}

class _PickStockState extends State<_PickStock> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final found = q.isEmpty
        ? const <Stock>[]
        : (Repo.I.stocks.where((s) => s.name.toLowerCase().contains(q) || s.ticker.contains(q)).toList()
              ..sort((a, b) => b.cap.compareTo(a.cap)))
            .take(50)
            .toList();
    final mine = Holdings.tickers();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return AlertDialog(
      title: const Text('보유종목 추가'),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '종목명 또는 종목코드'),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              for (final s in found)
                ListTile(
                  title: Text(s.name),
                  subtitle: Text('${s.ticker} · ${s.market}${mine.contains(s.ticker) ? ' · 보유 중' : ''}'),
                  trailing: Text(price(s.price())),
                  onTap: () => Navigator.of(context).pop(s),
                ),
              if (q.isNotEmpty && found.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('찾는 종목이 없습니다', textAlign: TextAlign.center, style: TextStyle(color: muted)),
                ),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('닫기'))],
    );
  }
}

class _EditHolding extends StatefulWidget {
  const _EditHolding({required this.ticker, required this.name, required this.price});

  final String ticker, name;
  final double price;

  @override
  State<_EditHolding> createState() => _EditHoldingState();
}

class _EditHoldingState extends State<_EditHolding> {
  late final Holding? _old = Holdings.of(widget.ticker);
  late final _avg = TextEditingController(
      text: _old != null ? _plain(_old.avg) : (widget.price.isNaN ? '' : _plain(widget.price)));
  late final _qty = TextEditingController(text: _old != null ? _plain(_old.qty) : '');
  String? _error;

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  static double? _number(String text) {
    final v = double.tryParse(text.replaceAll(',', '').trim());
    return v != null && v > 0 ? v : null;
  }

  @override
  void dispose() {
    _avg.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final avg = _number(_avg.text), qty = _number(_qty.text);
    if (avg == null || qty == null) {
      setState(() => _error = '평균 매수가와 수량을 0보다 큰 숫자로 넣어 주세요');
      return;
    }
    await Holdings.put(Holding(widget.ticker, widget.name, avg, qty));
    if (!mounted) return;
    Navigator.of(context).pop();
    Toaster.show('${widget.name} ${_old == null ? '보유종목에 추가' : '수정'}했습니다');
  }

  Future<void> _remove() async {
    await Holdings.remove(widget.ticker);
    if (!mounted) return;
    Navigator.of(context).pop();
    Toaster.show('${widget.name} 보유종목에서 뺐습니다');
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return AlertDialog(
      title: Text(widget.name),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _avg,
            autofocus: _old == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: digits,
            decoration: const InputDecoration(labelText: '평균 매수가', suffixText: '원'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: digits,
            decoration: InputDecoration(labelText: '수량', suffixText: '주', errorText: _error),
            onSubmitted: (_) => _save(),
          ),
        ]),
      ),
      actions: [
        if (_old != null)
          TextButton(
            onPressed: _remove,
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('보유종목에서 빼기'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
        FilledButton(onPressed: _save, child: const Text('저장')),
      ],
    );
  }
}
