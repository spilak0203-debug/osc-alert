import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../core/fmt.dart';
import '../core/market_index.dart';
import '../core/repo.dart';
import '../core/settings.dart';
import '../core/signals.dart' as signals;
import '../core/stock.dart';
import 'chart.dart';
import 'palette.dart';
import 'stock_tile.dart';

/// A dashboard section title: one signal kind and how many stocks it has.
class _Section {
  _Section(this.kind, this.count);

  final signals.Kind kind;
  final int count;
}

/// The dashboard's tally of stocks per signal kind.
class _Counts {
  _Counts(this.groups);

  final Map<signals.Kind, List<Stock>> groups;
}

/// Both list tabs. The dashboard shows the indices, the tally and each signal group; the stocks
/// tab shows every stock with search, order and favourites first.
class ListPage extends StatefulWidget {
  const ListPage({super.key, required this.summary, this.wide = false, this.selected, this.onSelect});

  final bool summary;

  /// Wide window: a tap selects the stock for the side pane instead of expanding the row.
  final bool wide;
  final String? selected;
  final ValueChanged<Stock>? onSelect;

  @override
  State<ListPage> createState() => ListPageState();
}

class ListPageState extends State<ListPage> {
  final _items = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  final _offsets = ScrollOffsetController();
  final _search = TextEditingController();
  final Map<String, ChartGroup> _indexGroups = {};
  String _query = '';
  String? _expanded;
  bool _far = false;
  List<Object> _list = const [];

  /// Summary: the section title pinned over the top of the list (-1 for none), how far the next
  /// title pushes it up, and the list's height for turning item edges into pixels.
  int _pinned = -1;
  double _pinnedShift = 0;
  double _viewport = 0;
  final _pinnedKey = GlobalKey();

  /// Space above a section title's strip in the list, and above the pinned one.
  static const double _headerGap = 18, _pinnedGap = 4;

  /// A group to scroll to once it is on the list (the data may still be loading).
  signals.Kind? _pendingJump;

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onScroll);
  }

  void _onScroll() {
    final shown = _positions.itemPositions.value.where((p) => p.itemTrailingEdge > 0).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (shown.isEmpty) return;
    final far = shown.first.index > 4;
    final (pinned, shift) = widget.summary ? _pin(shown) : (-1, 0.0);
    if (far != _far || pinned != _pinned || shift != _pinnedShift) {
      setState(() {
        _far = far;
        _pinned = pinned;
        _pinnedShift = shift;
      });
    }
  }

  /// The section whose rows are at the top once its own title has scrolled under the pinned
  /// one, and how far up the next section's title pushes it.
  (int, double) _pin(List<ItemPosition> shown) {
    if (_viewport <= 0 || _list.isEmpty) return (-1, 0);
    var at = -1;
    for (var i = shown.first.index.clamp(0, _list.length - 1); i >= 0; i--) {
      if (_list[i] is _Section) {
        at = i;
        break;
      }
    }
    if (at < 0) return (-1, 0);
    final own = shown.where((p) => p.index == at).firstOrNull;
    if (own != null && own.itemLeadingEdge * _viewport + _headerGap > _pinnedGap) return (-1, 0);
    final next = shown.where((p) => p.index > at && p.index < _list.length && _list[p.index] is _Section).firstOrNull;
    if (next == null) return (at, 0);
    final height = _pinnedKey.currentContext?.size?.height ?? 52;
    final room = next.itemLeadingEdge * _viewport + _headerGap - height;
    return (at, room < 0 ? room : 0);
  }

  @override
  void dispose() {
    _search.dispose();
    for (final g in _indexGroups.values) {
      g.dispose();
    }
    super.dispose();
  }

  void jumpTo(signals.Kind kind) {
    setState(() => _pendingJump = kind);
  }

  // ---- used by the smoke tour --------------------------------------------------------------

  /// The first stock row on the list, if any.
  Stock? get firstStock => _list.whereType<Stock>().firstOrNull;

  void expand(String ticker) => setState(() => _expanded = ticker);

  void search(String q) {
    _search.text = q;
    setState(() => _query = q.trim().toLowerCase());
  }

  /// Scrolls so that the item `offset` rows after the first stock (or `index` if given) is on top.
  void scrollToStock({int offset = 0}) {
    final at = _list.indexWhere((o) => o is Stock);
    if (at >= 0 && _items.isAttached) _items.jumpTo(index: at + offset);
  }

  void scrollToIndex(int index, {double alignment = 0}) {
    if (_items.isAttached) _items.jumpTo(index: index, alignment: alignment);
  }

  /// Moves the list by `pixels` (positive is down).
  Future<void> scrollBy(double pixels) =>
      _offsets.animateScroll(offset: pixels, duration: const Duration(milliseconds: 1));

  void _applyJump() {
    final kind = _pendingJump;
    if (kind == null) return;
    final at = _list.indexWhere((o) => o is _Section && o.kind == kind);
    if (at < 0) {
      // Nothing in that group with the current filters: give up once the data is in.
      if (!Repo.I.loading && Repo.I.stocks.isNotEmpty) _pendingJump = null;
      return;
    }
    _pendingJump = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_items.isAttached) _items.jumpTo(index: at);
    });
  }

  void _toTop() {
    if (!_items.isAttached) return;
    _items.scrollTo(index: 0, duration: const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Repo.I, Settings.I]),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final repo = Repo.I;
    final st = Settings.I;
    final stocks = repo.stocks;
    final items = <Object>[];
    final s = <String>[];
    if (repo.error.isNotEmpty) s.add('불러오기 실패: ${repo.error} · 위의 새로고침을 눌러 보세요');
    if (stocks.isEmpty && !repo.loading && repo.error.isEmpty) s.add('아래로 당기거나 위의 새로고침을 누르세요');

    if (widget.summary) {
      items.addAll(repo.indices);
      final groups = signals.group(stocks);
      items.add(_Counts(groups));
      // Favourites lead each group; the sort is stable so the rest keep their order.
      final favs = st.favorites();
      for (final e in groups.entries) {
        if (e.value.isEmpty) continue;
        final group = [...e.value.where((x) => favs.contains(x.ticker)), ...e.value.where((x) => !favs.contains(x.ticker))];
        items.add(_Section(e.key, group.length));
        items.addAll(group);
      }
      final filter = st.filterSummary();
      if (filter.isNotEmpty) s.add('필터: $filter · 설정 탭에서 변경');
    } else {
      // Filter and search first, then the chosen order. "favorite" keeps favourites in their
      // own group on top, each group by market cap.
      final sort = st.sort;
      final favs = st.favorites();
      final shownStocks = [
        for (final x in stocks)
          if (st.passes(x) && (_query.isEmpty || x.name.toLowerCase().contains(_query) || x.ticker.contains(_query))) x
      ];
      _sort(shownStocks, sort);
      final starred = <Stock>[], rest = <Stock>[];
      for (final x in shownStocks) {
        (sort == 'favorite' && favs.contains(x.ticker) ? starred : rest).add(x);
      }
      final shown = starred.length + rest.length;
      if (starred.isNotEmpty) {
        items.add('★ 즐겨찾기 · ${starred.length}종목');
        items.addAll(starred);
        if (rest.isNotEmpty) items.add('전체 종목 · ${rest.length}종목');
      }
      items.addAll(rest);
      final filter = st.filterSummary();
      if (filter.isNotEmpty) s.add('필터: $filter · $shown종목');
      if (_query.isNotEmpty) {
        s.add('검색 결과 $shown종목');
      } else {
        s.add('${widget.wide ? '길게 누르거나 오른쪽 클릭하면' : '길게 누르면'} ${st.flag(Settings.copyName) ? '종목명' : '종목코드'} 복사');
      }
    }
    _list = items;
    _applyJump();

    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final status = s.join('\n');
    return Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!widget.summary) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '종목명 또는 코드 검색',
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.cancel),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (var i = 0; i < Settings.sorts.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Center(
                      child: ChoiceChip(
                        label: Text(Settings.sortLabels[i]),
                        showCheckmark: false,
                        selected: st.sort == Settings.sorts[i],
                        onSelected: (_) {
                          st.setString(Settings.sortKey, Settings.sorts[i]);
                          if (_items.isAttached) _items.jumpTo(index: 0);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(status, style: t.bodySmall!.copyWith(color: cs.onSurfaceVariant)),
          ),
        if (repo.loading) const LinearProgressIndicator(),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            _viewport = box.maxHeight;
            final pinned = _pinned >= 0 && _pinned < items.length && items[_pinned] is _Section ? items[_pinned] as _Section : null;
            return Stack(children: [
              RefreshIndicator(
                onRefresh: () => repo.refresh(!widget.summary),
                child: ScrollablePositionedList.builder(
                  itemScrollController: _items,
                  itemPositionsListener: _positions,
                  scrollOffsetController: _offsets,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _item(context, items[i]),
                ),
              ),
              if (pinned != null)
                Positioned(
                  top: _pinnedShift,
                  left: 0,
                  right: 0,
                  child: Container(
                    key: _pinnedKey,
                    color: cs.surface,
                    padding: const EdgeInsets.fromLTRB(0, _pinnedGap, 0, 4),
                    child: _sectionHeader(context, pinned, margin: const EdgeInsets.symmetric(horizontal: 12)),
                  ),
                ),
            ]);
          }),
        ),
      ]),
      Positioned(
        left: 0,
        right: 0,
        bottom: 16,
        child: Center(
          child: AnimatedScale(
            scale: _far ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: FloatingActionButton.small(
              heroTag: widget.summary ? 'top-summary' : 'top-stocks',
              tooltip: '맨 위로',
              shape: const CircleBorder(),
              backgroundColor: cs.secondaryContainer,
              foregroundColor: cs.onSecondaryContainer,
              onPressed: _toTop,
              child: const Icon(Icons.arrow_upward),
            ),
          ),
        ),
      ),
    ]);
  }

  /// Stocks without a value for the sort key go last; ties fall back to market cap.
  static void _sort(List<Stock> list, String sort) {
    double nz(double v) => v.isNaN ? double.negativeInfinity : v;
    double pz(double v) => v.isNaN ? double.infinity : v;
    int byCap(Stock a, Stock b) => nz(b.cap).compareTo(nz(a.cap));
    int Function(Stock, Stock) cmp;
    switch (sort) {
      case 'name':
        cmp = (a, b) => _korean(a.name, b.name);
      case 'code':
        cmp = (a, b) => a.ticker.compareTo(b.ticker);
      case 'rise':
        cmp = (a, b) {
          final c = nz(b.changePct()).compareTo(nz(a.changePct()));
          return c != 0 ? c : byCap(a, b);
        };
      case 'fall':
        cmp = (a, b) {
          final c = pz(a.changePct()).compareTo(pz(b.changePct()));
          return c != 0 ? c : byCap(a, b);
        };
      default:
        cmp = byCap;
    }
    // Stable, like Collections.sort.
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((x, y) {
      final c = cmp(x.$2, y.$2);
      return c != 0 ? c : x.$1.compareTo(y.$1);
    });
    for (var i = 0; i < list.length; i++) {
      list[i] = indexed[i].$2;
    }
  }

  /// Korean collation as Java's Collator orders names: digits, then Latin, then Hangul.
  static int _korean(String a, String b) {
    int cls(int c) => c < 0x30 ? 0 : c <= 0x39 ? 1 : c < 0x80 ? 2 : c >= 0xAC00 && c <= 0xD7A3 ? 4 : 3;
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      var x = a.codeUnitAt(i), y = b.codeUnitAt(i);
      if (x >= 0x61 && x <= 0x7A) x -= 32;
      if (y >= 0x61 && y <= 0x7A) y -= 32;
      if (x == y) continue;
      final cx = cls(x), cy = cls(y);
      if (cx != cy) return cx.compareTo(cy);
      return x.compareTo(y);
    }
    return a.length.compareTo(b.length);
  }

  Widget _item(BuildContext context, Object o) {
    if (o is MarketIndex) return _indexCard(context, o);
    if (o is _Counts) return _countsCard(context, o);
    if (o is _Section) return _sectionHeader(context, o);
    if (o is String) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(o, style: Theme.of(context).textTheme.titleSmall),
      );
    }
    final s = o as Stock;
    return StockTile(
      key: ValueKey('row-${s.ticker}'),
      stock: s,
      open: !widget.wide && _expanded == s.ticker,
      selected: widget.wide && widget.selected == s.ticker,
      onTap: () {
        if (widget.wide) {
          widget.onSelect?.call(s);
        } else {
          setState(() => _expanded = _expanded == s.ticker ? null : s.ticker);
        }
      },
    );
  }

  Widget _card(BuildContext context, {required Widget child, EdgeInsets padding = EdgeInsets.zero}) => Card.filled(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      );

  Widget _indexCard(BuildContext context, MarketIndex m) {
    final t = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final group = _indexGroups.putIfAbsent(m.code, ChartGroup.new);
    return _card(
      context,
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            Expanded(child: Text(m.label, style: t.titleMedium)),
            Text(m.price.isNaN ? '-' : grouped(m.price, 2), style: t.titleMedium),
            const SizedBox(width: 8),
            Text(m.change.isNaN ? '' : '${signed(m.change, 2)} (${signed(m.changePct, 2)}%)',
                style: t.bodyMedium!.copyWith(color: p.change(m.changePct))),
          ]),
        ),
        ChartPanel(
          type: ChartType.candle,
          bars: m.bars,
          cfg: Settings.I.config(),
          group: group,
          showSignals: false,
          compact: true,
        ),
      ]),
    );
  }

  Widget _countsCard(BuildContext context, _Counts counts) {
    final t = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final tiles = <Widget>[];
    for (final k in signals.Kind.values) {
      final n = counts.groups[k]?.length ?? 0;
      tiles.add(InkWell(
        onTap: () => jumpTo(k),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n', style: t.headlineSmall!.copyWith(color: n == 0 ? p.flat : p.side(k.buySide))),
            Text('${k.label}${signals.alerting(k) ? ' · 알림' : ''}', style: t.bodySmall),
          ]),
        ),
      ));
    }
    return _card(
      context,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('오늘의 신호 · 누르면 해당 목록으로', style: t.titleSmall),
        for (var r = 0; r < tiles.length; r += 2)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: tiles[r]),
            Expanded(child: r + 1 < tiles.length ? tiles[r + 1] : const SizedBox()),
          ]),
      ]),
    );
  }

  /// Coloured bar, bold title and a count badge, on a tinted strip so sections stand apart.
  Widget _sectionHeader(BuildContext context, _Section s,
      {EdgeInsets margin = const EdgeInsets.fromLTRB(12, _headerGap, 12, 4)}) {
    final t = Theme.of(context).textTheme;
    final color = Palette.of(context).side(s.kind.buySide);
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withAlpha(0x1A), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Container(width: 5, height: 22, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(s.kind.label, style: t.titleMedium!.copyWith(color: color, fontWeight: FontWeight.w700))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
          child: Text('${s.count}종목', style: t.labelLarge!.copyWith(color: Colors.white)),
        ),
      ]),
    );
  }
}
