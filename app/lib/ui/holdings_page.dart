import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  /// The add button steps aside while the list is scrolled down (back on the way up) and while
  /// a stock's chart is open under its row, so it never sits on the chart or its notes.
  bool _scrolledDown = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Repo.I, Settings.I]),
      builder: (context, _) {
        final byTicker = {for (final s in Repo.I.stocks) s.ticker: s};
        final rows = [for (final h in Holdings.all()) (h, byTicker[h.ticker])];
        // Biggest position first; holdings without shares after them, by market cap.
        double value((Holding, Stock?) r) {
          final v = r.$1.complete ? (r.$2 == null ? r.$1.cost : r.$1.value(r.$2!.price())) : double.nan;
          return v.isNaN ? -1 : v;
        }
        rows.sort((a, b) {
          final c = value(b).compareTo(value(a));
          return c != 0 ? c : (b.$2?.cap ?? 0).compareTo(a.$2?.cap ?? 0);
        });
        final priced = rows.where((r) => r.$1.complete).toList();
        final add = FloatingActionButton.extended(
          heroTag: 'holdings-add',
          onPressed: () => addHolding(context),
          icon: const Icon(Icons.add),
          label: const Text('종목 추가'),
        );
        if (rows.isEmpty) return Stack(children: [_empty(context), Positioned(right: 16, bottom: 16, child: add)]);
        final hidden = _scrolledDown || (_expanded != null && !widget.wide);
        return Stack(children: [
          NotificationListener<UserScrollNotification>(
            onNotification: (n) {
              final down = n.direction == ScrollDirection.reverse
                  ? true
                  : n.direction == ScrollDirection.forward
                      ? false
                      : _scrolledDown;
              if (down != _scrolledDown) setState(() => _scrolledDown = down);
              return false;
            },
            child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
              if (priced.isNotEmpty) _total(context, priced, rows.length),
              for (final r in rows) _row(context, r.$1, r.$2),
            ]),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: IgnorePointer(
              ignoring: hidden,
              child: AnimatedSlide(
                offset: hidden ? const Offset(0, 2) : Offset.zero,
                duration: const Duration(milliseconds: 200),
                child: AnimatedOpacity(opacity: hidden ? 0 : 1, duration: const Duration(milliseconds: 200), child: add),
              ),
            ),
          ),
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
          Text('아래 [종목 추가]로 종목을 넣으면 오늘 신호를 여기서 모아 보고, 데드크로스가 뜨면 따로 알려 드립니다.\n'
              '평균 매수가와 수량도 넣으면 수익률과 차트의 평단선까지 (둘 다 선택).',
              textAlign: TextAlign.center, style: t.bodyMedium!.copyWith(color: muted)),
        ]),
      ),
    );
  }

  /// Value, gain and cost of the holdings with shares and an average price, and today's move in
  /// won; `all` counts every holding.
  Widget _total(BuildContext context, List<(Holding, Stock?)> rows, int all) {
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
          if (rows.length < all)
            Text('평단·수량을 넣은 ${rows.length}종목 기준', style: t.bodySmall!.copyWith(color: muted)),
          const SizedBox(height: 12),
          Row(children: [
            cell('매입금액', '${grouped(cost)}원'),
            cell('오늘', won(today), p.change(today)),
            cell('종목 수', '$all종목'),
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
    final change = s?.changePct() ?? double.nan;
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
                    if (h.hasQty) '${grouped(h.qty)}주',
                    if (h.hasAvg) '평단 ${grouped(h.avg)}원',
                    if (!h.hasQty && !h.hasAvg) '${h.ticker} · ${s?.market ?? ''}',
                    if (s == null) '시세 없음',
                    ...zones,
                  ].join(' · '),
                  style: t.bodySmall!.copyWith(color: cs.onSurfaceVariant)),
              SignalChips(hits),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // With shares and an average: value, gain and the price below. Otherwise the price
            // and its change, with the gain over the average when there is one.
            if (h.complete) ...[
              Text(price.isNaN ? '-' : '${grouped(h.value(price))}원', style: t.titleMedium),
              Text(price.isNaN ? '-' : '${won(gain)} (${percent(rate)})',
                  style: t.bodyMedium!.copyWith(color: p.change(gain))),
              Text('현재가 ${price.isNaN ? '-' : grouped(price)} (${percent(change)})',
                  style: t.bodySmall!.copyWith(color: cs.onSurfaceVariant)),
            ] else ...[
              Text(price.isNaN ? '-' : '${grouped(price)}원', style: t.titleMedium),
              Text(percent(change), style: t.bodyMedium!.copyWith(color: p.change(change))),
              if (h.hasAvg)
                Text('평단 대비 ${percent(rate)}', style: t.bodySmall!.copyWith(color: p.change(rate))),
            ],
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

/// Picks a stock by name or code, then asks for the shares and average price (both optional).
Future<void> addHolding(BuildContext context) async {
  final s = await showDialog<Stock>(context: context, builder: (_) => const _PickStock());
  if (s == null || !context.mounted) return;
  await editHolding(context, s.ticker, s.name, s.price());
}

/// Shares and average price for one stock, both optional (`price` is the hint for the average);
/// saving an existing holding replaces it, and it can be removed here.
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

/// Keeps a number field grouped as it is typed: "1000000" shows as "1,000,000". Digits and one
/// decimal point are kept, everything else dropped; the cursor stays after the same digit.
class GroupedDigits extends TextInputFormatter {
  static String format(String raw) {
    final dot = raw.indexOf('.');
    final whole = (dot < 0 ? raw : raw.substring(0, dot)).replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final frac = dot < 0 ? '' : '.${raw.substring(dot + 1).replaceAll('.', '')}';
    final b = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
      b.write(whole[i]);
    }
    return '$b$frac';
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue value) {
    final raw = value.text.replaceAll(RegExp(r'[^0-9.]'), '');
    final text = format(raw);
    // How many digits (or the point) were before the cursor, then find that spot again.
    final cursor = value.selection.baseOffset.clamp(0, value.text.length);
    final kept = value.text.substring(0, cursor).replaceAll(RegExp(r'[^0-9.]'), '').length;
    var at = 0;
    for (var seen = 0; at < text.length && seen < kept; at++) {
      if (text[at] != ',') seen++;
    }
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: at));
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
  late final _avg = TextEditingController(text: _old?.hasAvg ?? false ? _plain(_old!.avg) : '');
  late final _qty = TextEditingController(text: _old?.hasQty ?? false ? _plain(_old!.qty) : '');
  String? _error;

  static String _plain(double v) => GroupedDigits.format(v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v');

  /// Blank is NaN (not given); anything else must be a number above 0, or null.
  static double? _number(String text) {
    final t = text.replaceAll(',', '').trim();
    if (t.isEmpty) return double.nan;
    final v = double.tryParse(t);
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
      setState(() => _error = '비워 두거나 0보다 큰 숫자로 넣어 주세요');
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
    final digits = [GroupedDigits()];
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
            decoration: InputDecoration(
              labelText: '평균 매수가 (선택)',
              suffixText: '원',
              hintText: widget.price.isNaN ? null : '현재가 ${grouped(widget.price)}',
              helperText: '넣으면 차트에 평단선과 수익률',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: digits,
            decoration: InputDecoration(labelText: '수량 (선택)', suffixText: '주', errorText: _error),
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
