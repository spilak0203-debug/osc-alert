import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/repo.dart';
import '../core/settings.dart';
import '../core/signals.dart' as signals;
import '../core/stock.dart';
import '../platform/app_update.dart';
import '../platform/notifier.dart';
import 'list_page.dart';
import 'palette.dart';
import 'settings_page.dart';
import 'stock_tile.dart';
import 'toast.dart';

/// Windows at least this wide get the navigation rail and the side detail pane.
const double wideBreakpoint = 1000;

/// Top bar (which close the signals are from, what the market is doing, refresh), the three
/// tabs, and the bottom navigation — or, on a wide window, a rail and a detail pane.
class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => HomeState();
}

class HomeState extends State<Home> {
  final summaryKey = GlobalKey<ListPageState>();
  final stocksKey = GlobalKey<ListPageState>();
  final settingsScroll = ScrollController();
  int tab = 0;
  Stock? selected;

  @override
  void initState() {
    super.initState();
    Notifier.tapped.addListener(_openTapped);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Repo.I.ensure();
      _openTapped();
      _offerUpdate();
      Notifier.askPermission();
    });
  }

  @override
  void dispose() {
    Notifier.tapped.removeListener(_openTapped);
    settingsScroll.dispose();
    super.dispose();
  }

  /// From a notification: switch to the dashboard and scroll to that signal group.
  void _openTapped() {
    final kind = Notifier.tapped.value;
    if (kind == null) return;
    Notifier.tapped.value = null;
    show(0);
    WidgetsBinding.instance.addPostFrameCallback((_) => summaryKey.currentState?.jumpTo(kind));
  }

  void jumpTo(signals.Kind kind) {
    show(0);
    WidgetsBinding.instance.addPostFrameCallback((_) => summaryKey.currentState?.jumpTo(kind));
  }

  void show(int index) {
    if (index != 0) summaryKey.currentState?.closeSearch();
    setState(() => tab = index);
    // Opening the stocks tab for the first time fetches every price once.
    if (index == 1 && !Repo.I.wantAll) {
      Repo.I.wantAll = true;
      Repo.I.refresh(true);
    }
  }

  /// Quietly checks GitHub once per launch; a snackbar offers the install when there is a newer build.
  Future<void> _offerUpdate() async {
    try {
      final r = await AppUpdate.latest();
      if (!AppUpdate.newer(r) || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('새 버전(${r!.name})이 있습니다'),
        duration: const Duration(days: 1),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: '설치', onPressed: () => AppUpdate.install(r)),
      ));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= wideBreakpoint;
      final pages = [
        ListPage(key: summaryKey, summary: true, wide: wide, selected: selected?.ticker, onSelect: select),
        ListPage(key: stocksKey, summary: false, wide: wide, selected: selected?.ticker, onSelect: select),
        SettingsPage(controller: settingsScroll),
      ];
      final body = IndexedStack(index: tab, children: pages);
      return Scaffold(
        appBar: _topBar(context),
        body: Column(children: [
          const _UpdateProgress(),
          Expanded(child: wide ? _wideBody(context, body) : body),
        ]),
        bottomNavigationBar: wide ? null : _BottomBar(index: tab, onTap: show),
      );
    });
  }

  void select(Stock s) => setState(() => selected = s);

  PreferredSizeWidget _topBar(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppBar(
      // MaterialToolbar with a title and a subtitle, as tall as the Java app's.
      toolbarHeight: 70,
      title: ListenableBuilder(
        listenable: Repo.I,
        builder: (context, _) {
          final sub = Repo.I.subtitle();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(Repo.I.title(), style: t.titleMedium),
            if (sub.isNotEmpty) Text(sub, style: t.bodySmall!.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]);
        },
      ),
      actions: [
        if (tab == 0)
          IconButton(
            tooltip: '요약에서 검색',
            icon: const Icon(Icons.search),
            onPressed: () => summaryKey.currentState?.toggleSearch(),
          ),
        IconButton(
          tooltip: '새로고침',
          icon: const Icon(Icons.refresh),
          onPressed: () {
            Toaster.show('새로고침합니다');
            Repo.I.refresh(tab == 1);
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _wideBody(BuildContext context, Widget pages) {
    final cs = Theme.of(context).colorScheme;
    final rail = NavigationRail(
      selectedIndex: tab,
      onDestinationSelected: show,
      labelType: NavigationRailLabelType.all,
      destinations: const [
        NavigationRailDestination(icon: Icon(Icons.list), label: Text('요약')),
        NavigationRailDestination(icon: Icon(Icons.show_chart), label: Text('종목')),
        NavigationRailDestination(icon: Icon(Icons.tune), label: Text('설정')),
      ],
    );
    if (tab == 2) {
      return Row(children: [rail, const VerticalDivider(width: 1), Expanded(child: pages)]);
    }
    return Row(children: [
      rail,
      const VerticalDivider(width: 1),
      SizedBox(width: 480, child: pages),
      const VerticalDivider(width: 1),
      Expanded(
        child: selected == null
            ? Center(
                child: Text('왼쪽 목록에서 종목을 고르면 여기에 차트가 나옵니다',
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: cs.onSurfaceVariant)),
              )
            : _DetailPane(stock: selected!),
      ),
    ]);
  }
}

/// Under the top bar while an app update downloads: percent, megabytes and a progress bar.
class _UpdateProgress extends StatelessWidget {
  const _UpdateProgress();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: AppUpdate.progress,
      builder: (context, p, _) {
        if (p == null) return const SizedBox.shrink();
        final (got, size) = p;
        final cs = Theme.of(context).colorScheme;
        String mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);
        final text = size > 0
            ? '업데이트 받는 중 · ${got * 100 ~/ size}% (${mb(got)} / ${mb(size)}MB)'
            : '업데이트 받는 중 · ${mb(got)}MB';
        return Material(
          color: cs.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(text, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: size > 0 ? got / size : null, borderRadius: BorderRadius.circular(4)),
            ]),
          ),
        );
      },
    );
  }
}

/// The selected stock beside the list: its row facts on top, then the same detail as the phone.
class _DetailPane extends StatelessWidget {
  const _DetailPane({required this.stock});

  final Stock stock;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Repo.I, Settings.I]),
      builder: (context, _) {
        // Refreshes replace the Stock objects; show the current one.
        final s = Repo.I.stocks.firstWhere((x) => x.ticker == stock.ticker, orElse: () => stock);
        final t = Theme.of(context).textTheme;
        final cs = Theme.of(context).colorScheme;
        final p = Palette.of(context);
        final fav = Settings.I.favorite(s.ticker);
        return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.name, style: t.headlineSmall),
                  Text('${s.ticker} · ${s.market}', style: t.bodyMedium!.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(price(s.price()), style: t.headlineSmall),
                Text('${percent(s.changePct())} · 거래량 ${compact(s.tradedVolume())}',
                    style: t.bodyMedium!.copyWith(color: p.change(s.changePct()))),
              ]),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '즐겨찾기',
                icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Palette.favorite : cs.onSurfaceVariant),
                onPressed: () {
                  final now = Settings.I.toggleFavorite(s.ticker);
                  Toaster.show('${s.name}${now ? ' 즐겨찾기에 추가' : ' 즐겨찾기에서 뺌'}');
                },
              ),
              IconButton(
                tooltip: '종목코드 복사',
                icon: Icon(Icons.content_copy, color: cs.onSurfaceVariant),
                onPressed: () => copyStock(s),
              ),
            ]),
          ),
          StockDetail(stock: s, wide: true, key: ValueKey('pane-${s.ticker}')),
        ]);
      },
    );
  }
}

/// Lower than Material's 80dp bar (67dp), with a slimmer pill (56×26) behind the selected tab,
/// like the Java app's bottom navigation.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.list, '요약'),
    (Icons.show_chart, '종목'),
    (Icons.tune, '설정'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 67,
          child: Row(children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 9, bottom: 6),
                    child: Column(children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 56,
                        height: 26,
                        decoration: BoxDecoration(
                          color: i == index ? cs.secondaryContainer : Colors.transparent,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(_items[i].$1, size: 24, color: i == index ? cs.onSecondaryContainer : cs.onSurfaceVariant),
                      ),
                      const Spacer(),
                      Text(_items[i].$2,
                          style: t.labelMedium!.copyWith(
                            color: i == index ? cs.onSurface : cs.onSurfaceVariant,
                            fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                          )),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
