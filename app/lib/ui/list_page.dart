import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  _Section(this.kind, this.count, {this.of, String? label}) : label = label ?? kind!.label;

  /// Null for the search results that have no signal today.
  final signals.Kind? kind;
  final String label;
  final int count;

  /// While searching: how many the whole group has.
  final int? of;
}

/// A part of the dashboard (rising, falling, reference) and how many stocks it lists. The
/// reference part can be folded away.
class _Block {
  _Block(this.block, this.count, {this.open = true});

  final signals.Block block;
  final int count;
  final bool open;
}

/// The dashboard's tally of stocks per signal kind.
class _Counts {
  _Counts(this.groups) {
    // Rising signals whose stocks were moved up into an overlap group: count them too, and
    // remember which overlap group to go to (the 3-overlap first).
    for (final combo in [signals.Kind.combo3, signals.Kind.combo2]) {
      for (final s in groups[combo] ?? const <Stock>[]) {
        for (final h in signals.hits(s)) {
          if (!h.kind.rising) continue;
          inOverlap[h.kind] = (inOverlap[h.kind] ?? 0) + 1;
          overlapGroup[h.kind] ??= combo;
        }
      }
    }
  }

  final Map<signals.Kind, List<Stock>> groups;
  final Map<signals.Kind, int> inOverlap = {};
  final Map<signals.Kind, signals.Kind> overlapGroup = {};
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

  /// Scrolled far enough for the "to the top" button. Scroll-driven state lives in notifiers so
  /// scrolling redraws only the overlays, never the list and its signal tally.
  final _far = ValueNotifier<bool>(false);
  List<Object> _list = const [];

  /// Summary: the section title pinned over the top of the list (-1 for none), how far the next
  /// title pushes it up, and the list's height for turning item edges into pixels.
  final _pinned = ValueNotifier<(int, double)>((-1, 0));
  double _viewport = 0;
  final _pinnedKey = GlobalKey();

  /// Space above a section title's strip in the list, and above the pinned one.
  static const double _headerGap = 18, _pinnedGap = 4;

  /// Space above a part's title ("상승 신호" …).
  static const double _blockGap = 26;

  /// The scroll bar on the right: where its thumb is (0..1), whether it is showing (while the
  /// list moves, and always on Windows), and the bubble beside it — the section (or stock) at
  /// that point — while it is dragged. Notifiers, so moving it does not rebuild the list.
  final _thumbAt = ValueNotifier<double>(0);
  final _barShown = ValueNotifier<bool>(false);
  final _bubble = ValueNotifier<String?>(null);
  Timer? _barHide;
  int _visible = 1;
  static const double _thumbHeight = 48;

  /// Summary: the search field under the top bar is open, and the item that was on top before
  /// it opened (to go back to when it closes).
  bool _searching = false;
  int _beforeSearch = 0;

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
    _visible = shown.length;
    // While the bar is dragged the thumb follows the finger, not the list.
    if (_bubble.value == null) {
      _thumbAt.value = _fraction(shown);
      _showBar();
    }
    _far.value = shown.first.index > 4;
    if (widget.summary) _pinned.value = _pin(shown);
  }

  /// How far down the list the top of the screen is, by items (0..1).
  double _fraction(List<ItemPosition> shown) {
    final first = shown.first, last = shown.last;
    if (last.index >= _list.length - 1 && last.itemTrailingEdge <= 1.0) return first.index == 0 && first.itemLeadingEdge >= 0 ? 0 : 1;
    final span = first.itemTrailingEdge - first.itemLeadingEdge;
    final at = first.index + (span > 0 ? (-first.itemLeadingEdge / span).clamp(0.0, 1.0) : 0.0);
    return (at / math.max(1, _list.length - shown.length)).clamp(0.0, 1.0);
  }

  void _showBar() {
    _barShown.value = true;
    _barHide?.cancel();
    _barHide = Timer(const Duration(milliseconds: 1500), () => _barShown.value = false);
  }

  /// Dragging the bar: jump to the matching item and name where that is.
  void _dragBar(double y, double track) {
    final f = ((y - _thumbHeight / 2) / track).clamp(0.0, 1.0);
    _thumbAt.value = f;
    if (_list.isEmpty) return;
    final i = (f * math.max(0, _list.length - _visible)).round().clamp(0, _list.length - 1);
    if (_items.isAttached) _items.jumpTo(index: i);
    _bubble.value = _labelAt(i);
    _showBar();
  }

  void _dropBar() {
    _bubble.value = null;
    _showBar();
  }

  /// Summary: the section the item is in. Stocks tab: the stock at that point.
  String _labelAt(int i) {
    if (widget.summary) {
      for (var j = i; j >= 0; j--) {
        final o = _list[j];
        if (o is _Section) return o.label;
      }
      return '지수 · 오늘의 신호';
    }
    for (var j = i; j < _list.length; j++) {
      final o = _list[j];
      if (o is Stock) return o.name;
    }
    return '';
  }

  /// The section whose rows are at the top once its own title has scrolled under the pinned
  /// one, and how far up the next section's title pushes it.
  (int, double) _pin(List<ItemPosition> shown) {
    if (_viewport <= 0 || _list.isEmpty) return (-1, 0);
    var at = -1;
    for (var i = shown.first.index.clamp(0, _list.length - 1); i >= 0; i--) {
      // A part's title ends the groups above it: nothing to pin until the next group.
      if (_list[i] is _Block) return (-1, 0);
      if (_list[i] is _Section) {
        at = i;
        break;
      }
    }
    if (at < 0) return (-1, 0);
    final own = shown.where((p) => p.index == at).firstOrNull;
    if (own != null && own.itemLeadingEdge * _viewport + _headerGap > _pinnedGap) return (-1, 0);
    // The next group's title, or the next part's, pushes the pinned one up.
    final next = shown
        .where((p) => p.index > at && p.index < _list.length && (_list[p.index] is _Section || _list[p.index] is _Block))
        .firstOrNull;
    if (next == null) return (at, 0);
    final height = _pinnedKey.currentContext?.size?.height ?? 52;
    final gap = _list[next.index] is _Block ? _blockGap : _headerGap;
    final room = next.itemLeadingEdge * _viewport + gap - height;
    return (at, room < 0 ? room : 0);
  }

  @override
  void dispose() {
    _barHide?.cancel();
    _far.dispose();
    _pinned.dispose();
    _thumbAt.dispose();
    _barShown.dispose();
    _bubble.dispose();
    _search.dispose();
    for (final g in _indexGroups.values) {
      g.dispose();
    }
    super.dispose();
  }

  void jumpTo(signals.Kind kind) {
    if (_searching) closeSearch();
    if (kind.zone && !Settings.I.flag(Settings.showZones)) Settings.I.setFlag(Settings.showZones, true);
    setState(() => _pendingJump = kind);
  }

  /// Summary: opens the search field, or closes it.
  void toggleSearch() {
    if (_searching) return closeSearch();
    final shown = _positions.itemPositions.value.where((p) => p.itemTrailingEdge > 0).map((p) => p.index);
    _beforeSearch = shown.isEmpty ? 0 : shown.reduce(math.min);
    setState(() => _searching = true);
  }

  /// Closes the summary's search and returns to where the list was.
  void closeSearch() {
    if (!_searching) return;
    _search.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
    final back = _beforeSearch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_items.isAttached && _list.isNotEmpty) _items.jumpTo(index: back.clamp(0, _list.length - 1));
    });
  }

  void _setQuery(String v) {
    setState(() => _query = v.trim().toLowerCase());
    // The summary's results start at the top.
    if (widget.summary) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_items.isAttached && _list.isNotEmpty) _items.jumpTo(index: 0);
      });
    }
  }

  // ---- used by the smoke tour --------------------------------------------------------------

  /// The first stock row on the list, if any.
  Stock? get firstStock => _list.whereType<Stock>().firstOrNull;

  void expand(String ticker) => setState(() => _expanded = ticker);

  void search(String q) {
    _search.text = q;
    _setQuery(q);
  }

  /// Scrolls so that the item `offset` rows after the first stock (or `index` if given) is on top.
  void scrollToStock({int offset = 0}) {
    final at = _list.indexWhere((o) => o is Stock);
    if (at >= 0 && _items.isAttached) _items.jumpTo(index: at + offset);
  }

  /// Summary: puts the signal tally, or a part's title, at the top.
  void showTally() => scrollToIndex(math.max(0, _list.indexWhere((o) => o is _Counts)));

  void showBlock(signals.Block b) {
    final at = _list.indexWhere((o) => o is _Block && o.block == b);
    if (at >= 0) scrollToIndex(at);
  }

  void scrollToIndex(int index, {double alignment = 0}) {
    if (_items.isAttached) _items.jumpTo(index: index, alignment: alignment);
  }

  /// Holds the scroll bar `fraction` of the way down as if dragged there; null lets go.
  void holdBar(double? fraction) {
    if (fraction == null) return _dropBar();
    final track = math.max(1.0, _viewport - _thumbHeight);
    _dragBar(fraction * track + _thumbHeight / 2, track);
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

    bool matches(Stock x) => x.name.toLowerCase().contains(_query) || x.ticker.contains(_query);
    if (widget.summary) {
      // Searching keeps only the matching stocks in each group (and hides the indices and the
      // tally); matches with no signal today are listed last so the answer is always visible.
      final searching = _query.isNotEmpty;
      final groups = signals.group(stocks);
      if (!searching) {
        items.addAll(repo.indices);
        items.add(_Counts(groups));
      }
      // Within a group: the group's own order first (volume-surge pairs last among the 2-signal
      // overlaps), then favourites; the sort is stable so the rest keep their order.
      final favs = st.favorites();
      final listed = <String>{};
      final zonesOpen = searching || st.flag(Settings.showZones);
      for (final block in signals.Block.values) {
        final part = <Object>[];
        final inPart = <String>{};
        for (final e in groups.entries) {
          if (e.key.block != block || e.value.isEmpty) continue;
          int key(Stock x) => signals.rank(e.key, x) * 2 + (favs.contains(x.ticker) ? 0 : 1);
          final indexed = [for (var i = 0; i < e.value.length; i++) (i, e.value[i])]
            ..sort((a, b) {
              final c = key(a.$2).compareTo(key(b.$2));
              return c != 0 ? c : a.$1.compareTo(b.$1);
            });
          final group = [for (final x in indexed) x.$2];
          final shown = searching ? group.where(matches).toList() : group;
          if (shown.isEmpty) continue;
          inPart.addAll(shown.map((x) => x.ticker));
          part
            ..add(_Section(e.key, shown.length, of: searching ? group.length : null))
            ..addAll(shown);
        }
        if (inPart.isEmpty) continue;
        listed.addAll(inPart);
        final open = block != signals.Block.zones || zonesOpen;
        items.add(_Block(block, inPart.length, open: open));
        if (open) items.addAll(part);
      }
      if (searching) {
        final quiet = [for (final x in stocks) if (st.passes(x) && matches(x) && !listed.contains(x.ticker)) x];
        if (quiet.isNotEmpty) {
          items.add(_Section(null, quiet.length, label: '오늘 신호 없음'));
          items.addAll(quiet);
        }
        final found = listed.length + quiet.length;
        s.add(found == 0 ? '검색 결과가 없습니다' : '검색 결과 $found종목 · 신호 있는 종목 ${listed.length}');
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
          if (st.passes(x) && (_query.isEmpty || matches(x))) x
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

    final status = s.join('\n');
    // Back (or Esc) closes the summary's search before it leaves the app.
    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) closeSearch();
      },
      child: _page(context, items, status),
    );
  }

  Widget _page(BuildContext context, List<Object> items, String status) {
    final repo = Repo.I;
    final st = Settings.I;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.summary && _searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.escape): closeSearch},
              child: TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '요약에서 종목명 또는 코드 검색',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(tooltip: '검색 닫기', icon: const Icon(Icons.close), onPressed: closeSearch),
                ),
                onChanged: _setQuery,
              ),
            ),
          ),
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
              onChanged: _setQuery,
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
            return Stack(children: [
              RefreshIndicator(
                onRefresh: () => repo.refresh(!widget.summary),
                // Our own bar replaces the platform's.
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
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
              ),
              Positioned.fill(
                child: ValueListenableBuilder(
                  valueListenable: _pinned,
                  builder: (context, pin, _) {
                    final (at, shift) = pin;
                    if (at < 0 || at >= items.length || items[at] is! _Section) return const SizedBox.shrink();
                    // Tapping the pinned title goes to the top of its section.
                    return Stack(children: [
                      Positioned(
                        top: shift,
                        left: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () => _items.scrollTo(
                              index: at, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                          child: Container(
                            key: _pinnedKey,
                            color: cs.surface,
                            padding: const EdgeInsets.fromLTRB(0, _pinnedGap, 0, 4),
                            child: _sectionHeader(context, items[at] as _Section,
                                margin: const EdgeInsets.symmetric(horizontal: 12)),
                          ),
                        ),
                      ),
                    ]);
                  },
                ),
              ),
              Positioned.fill(child: _scrollBar(context, box.maxHeight)),
            ]);
          }),
        ),
      ]),
      Positioned(
        left: 0,
        right: 0,
        bottom: 16,
        child: Center(
          child: ValueListenableBuilder(
            valueListenable: _far,
            builder: (context, far, child) => AnimatedScale(
              scale: far ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: child,
            ),
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

  /// A thin thumb on the right edge that can be grabbed; while dragged it widens and a bubble
  /// beside it names the section (summary) or stock (stocks tab) at that point.
  Widget _scrollBar(BuildContext context, double height) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final desktop = Theme.of(context).platform == TargetPlatform.windows;
    final track = math.max(1.0, height - _thumbHeight);
    return ListenableBuilder(
      listenable: Listenable.merge([_thumbAt, _barShown, _bubble]),
      builder: (context, _) {
        final label = _bubble.value;
        final dragging = label != null;
        final active = dragging || _barShown.value;
        final top = _thumbAt.value * track;
        return Stack(children: [
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: 18,
            child: IgnorePointer(
              ignoring: !(active || desktop),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (d) => _dragBar(d.localPosition.dy, track),
                onVerticalDragUpdate: (d) => _dragBar(d.localPosition.dy, track),
                onVerticalDragEnd: (_) => _dropBar(),
                onVerticalDragCancel: _dropBar,
                child: AnimatedOpacity(
                  opacity: active ? 1 : (desktop ? 0.4 : 0),
                  duration: const Duration(milliseconds: 200),
                  child: Stack(children: [
                    Positioned(
                      top: top,
                      right: 3,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: dragging ? 8 : 5,
                        height: _thumbHeight,
                        decoration: BoxDecoration(
                          color: dragging ? cs.primary : cs.onSurfaceVariant.withAlpha(0xA0),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          if (dragging && label.isNotEmpty)
            Positioned(
              top: (top + _thumbHeight / 2 - 18).clamp(0.0, math.max(0.0, height - 36)),
              right: 26,
              child: IgnorePointer(
                child: Material(
                  elevation: 3,
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Text(label, style: t.titleSmall!.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
        ]);
      },
    );
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
    if (o is _Block) return _blockHeader(context, o);
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

  /// Rising and falling tiles, two a row, and the oversold/overbought counts in one small line.
  Widget _countsCard(BuildContext context, _Counts counts) {
    final t = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final pairs = Settings.I.flag(Settings.pairSignals);
    int total(signals.Kind k) => (counts.groups[k]?.length ?? 0) + (counts.inOverlap[k] ?? 0);

    Widget tile(signals.Kind k) {
      // Every stock with the signal, those listed under an overlap included; a tap goes to the
      // signal's own group, or to the overlap group when all of them are there.
      final own = counts.groups[k]?.length ?? 0;
      final moved = counts.inOverlap[k] ?? 0;
      final n = own + moved;
      return InkWell(
        onTap: () => jumpTo(own == 0 && moved > 0 ? counts.overlapGroup[k]! : k),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n', style: t.headlineSmall!.copyWith(color: n == 0 ? p.flat : p.side(k.buySide))),
            Text('${k.label}${signals.alerting(k) ? ' · 알림' : ''}', style: t.bodySmall),
            if (moved > 0) Text('높음 이상 칸에 $moved', style: t.labelSmall!.copyWith(color: muted)),
          ]),
        ),
      );
    }

    final body = <Widget>[Text('오늘의 신호 · 누르면 해당 목록으로', style: t.titleSmall)];
    for (final block in [signals.Block.rising, signals.Block.falling]) {
      final kinds = [
        for (final k in signals.Kind.values)
          if (k.block == block && (pairs || (k != signals.Kind.gold2 && k != signals.Kind.dead2))) k
      ];
      body.add(Padding(
        padding: const EdgeInsets.only(top: 10, left: 4),
        child: Text(block.label, style: t.labelMedium!.copyWith(color: muted)),
      ));
      for (var r = 0; r < kinds.length; r += 2) {
        body.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: tile(kinds[r])),
          Expanded(child: r + 1 < kinds.length ? tile(kinds[r + 1]) : const SizedBox()),
        ]));
      }
    }
    final zones = [for (final k in signals.Kind.values) if (k.zone) k];
    body.add(InkWell(
      onTap: () => jumpTo(zones.firstWhere((k) => total(k) > 0, orElse: () => zones.first)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
        child: Text('참고 · ${[for (final k in zones) '${k.label} ${total(k)}'].join(' · ')}',
            style: t.bodySmall!.copyWith(color: muted)),
      ),
    ));
    return _card(
      context,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
    );
  }

  /// A part's title above its groups; the reference part folds and unfolds with a tap.
  Widget _blockHeader(BuildContext context, _Block b) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final foldable = b.block == signals.Block.zones && !_searching;
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, _blockGap, 12, 0),
      child: Row(children: [
        Text(b.block.label, style: t.titleLarge!.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Text('${b.count}종목', style: t.bodyMedium!.copyWith(color: muted)),
        const Spacer(),
        if (foldable) ...[
          Text(b.open ? '접기' : '펼치기', style: t.labelLarge!.copyWith(color: muted)),
          Icon(b.open ? Icons.expand_less : Icons.expand_more, color: muted),
        ],
      ]),
    );
    if (!foldable) return row;
    return InkWell(onTap: () => Settings.I.setFlag(Settings.showZones, !b.open), child: row);
  }

  /// Coloured bar, bold title and a count badge, on a tinted strip so sections stand apart.
  Widget _sectionHeader(BuildContext context, _Section s,
      {EdgeInsets margin = const EdgeInsets.fromLTRB(12, _headerGap, 12, 4)}) {
    final t = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final kind = s.kind;
    final color = kind == null ? p.flat : p.side(kind.buySide);
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withAlpha(0x1A), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Container(width: 5, height: 22, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(s.label, style: t.titleMedium!.copyWith(color: color, fontWeight: FontWeight.w700))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
          child: Text(s.of == null ? '${s.count}종목' : '${s.count}/${s.of}종목', style: t.labelLarge!.copyWith(color: Colors.white)),
        ),
      ]),
    );
  }
}
