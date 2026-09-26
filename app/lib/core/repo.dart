import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'bars.dart';
import 'fmt.dart';
import 'holdings.dart';
import 'live.dart';
import 'market_index.dart';
import 'net.dart';
import 'signals.dart' as signals;
import 'stock.dart';

const repoName = String.fromEnvironment('REPO', defaultValue: 'spilak0203-debug/osc-alert');
/// `--dart-define=MARKET_URL=...` points a local build at a test snapshot.
const marketUrl = String.fromEnvironment('MARKET_URL',
    defaultValue: 'https://github.com/$repoName/releases/download/market-data/market-v2.json');

/// The market snapshot every screen shows. market.json is fetched from the repository's release
/// asset and kept on disk; live quotes and the two indices are layered on top on refresh.
class Repo extends ChangeNotifier {
  Repo._();

  static final Repo I = Repo._();

  List<Stock> stocks = const [];
  List<MarketIndex> indices = const [];
  String asof = '', error = '';
  DateTime? quotesAt;
  bool loading = false;

  /// Set once the stocks tab has been opened: from then on every refresh fetches all prices.
  bool wantAll = false;

  /// Tells every screen to redraw, e.g. after a settings change.
  void changed() => notifyListeners();

  static Future<File> file() async => File('${(await getApplicationSupportDirectory()).path}/market.json');

  /// Fetches market.json and stores it. Returns the parsed stocks.
  Future<List<Stock>> download() async {
    final text = await Net.get('$marketUrl?t=${DateTime.now().millisecondsSinceEpoch}');
    final parsed = parse(text); // validate before overwriting the cache
    await (await file()).writeAsString(text);
    return parsed;
  }

  List<Stock> parse(String text) {
    final root = jsonDecode(text) as Map<String, dynamic>;
    final rows = root['stocks'] as List;
    final out = [for (final r in rows) Stock.parse(r as Map<String, dynamic>)];
    asof = '${root['asof'] ?? ''}';
    return out;
  }

  /// Loads the cached file if nothing is in memory yet, then refreshes.
  Future<void> ensure() async {
    if (stocks.isNotEmpty || loading) return;
    try {
      final f = await file();
      if (await f.exists()) {
        stocks = parse(await f.readAsString());
        changed();
      }
    } catch (_) {}
    await refresh(false);
  }

  /// Re-downloads market.json, the indices and live quotes. `allQuotes` fetches every stock's
  /// price (stocks tab); otherwise only the stocks that currently signal (dashboard) and the
  /// user's holdings.
  Future<void> refresh(bool allQuotes) async {
    if (loading) return;
    loading = true;
    changed();
    var err = '';
    try {
      final fresh = await download();
      stocks = fresh;
      Bars.clear();
      changed();
      final idx = <MarketIndex>[];
      for (final code in MarketIndex.codes) {
        try {
          idx.add(await MarketIndex.load(code));
        } catch (_) {}
      }
      indices = idx;
      changed();
      if (allQuotes || wantAll) {
        Live.apply(fresh, await Live.all());
      } else {
        final codes = Holdings.tickers();
        for (final l in signals.group(fresh).values) {
          for (final s in l) {
            codes.add(s.ticker);
          }
        }
        if (codes.isNotEmpty) Live.apply(fresh, await Live.some(codes.toList()));
      }
      quotesAt = DateTime.now();
    } catch (e) {
      err = '$e';
    }
    error = err;
    loading = false;
    changed();
  }

  /// Title for the top bar: which close the signals are from, and what the market is doing.
  String title() {
    if (asof.isEmpty) return loading ? '불러오는 중…' : '신호 없음';
    return '${asof.substring(0, 4)}.${asof.substring(5, 7)}.${asof.substring(8)} 종가 기준';
  }

  String subtitle() {
    final b = StringBuffer();
    if (indices.isNotEmpty) {
      final now = seoulNow();
      final s = indices.first.session(now);
      if (s.isNotEmpty) b.write(s);
      // After a holiday the latest signals are from the last trading day — say so.
      if (s.contains('휴장')) b.write(' · 가장 최근 거래일 신호');
      // The scan runs around 15:50–16:40; until then the latest signals are from the day before.
      if ((s == '장 마감' || s == '장중') && asof != seoulDate(now)) b.write(' · 오늘 신호는 장 마감 후');
    }
    final at = quotesAt;
    if (at != null) {
      if (b.isNotEmpty) b.write(' · ');
      b.write('시세 ${two(at.hour)}:${two(at.minute)}');
    }
    if (loading) b.write(b.isNotEmpty ? ' · 갱신 중' : '갱신 중');
    return b.toString();
  }
}
