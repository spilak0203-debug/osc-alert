import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'fmt.dart';
import 'market_index.dart';
import 'net.dart';
import 'repo.dart' show repoName;

/// `--dart-define=NEWS_URL=...` points a local build at a test briefing.
const newsUrl = String.fromEnvironment('NEWS_URL',
    defaultValue: 'https://github.com/$repoName/releases/download/market-data/news.json');

/// The pre-market briefing: Claude's reading of the news since the last close, written on trading
/// days around 07:30 KST by the daily-news workflow (`signal/news.py`) and uploaded next to
/// market-v2.json.
class Briefing {
  Briefing({
    required this.date,
    this.generated,
    this.model = '',
    this.articles = 0,
    this.headline = '',
    this.key = const [],
    this.sections = const [],
    this.stocks = const [],
    this.sources = const [],
  });

  /// The trading day it is for, "2026-10-12".
  final String date;
  final DateTime? generated;
  final String model;

  /// How many articles Claude was given.
  final int articles;
  final String headline;

  /// The three things that matter most, one line each.
  final List<String> key;
  final List<BriefSection> sections;
  final List<BriefStock> stocks;
  final List<BriefSource> sources;

  static Briefing parse(Map<String, dynamic> o) {
    List<Map<String, dynamic>> maps(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];
    List<String> strings(Object? v) => v is List ? [for (final x in v) if (x is String && x.isNotEmpty) x] : const [];
    return Briefing(
      date: '${o['date'] ?? ''}',
      generated: DateTime.tryParse('${o['generated'] ?? ''}'),
      model: '${o['model'] ?? ''}',
      articles: o['articles'] is int ? o['articles'] as int : 0,
      headline: '${o['headline'] ?? ''}',
      key: strings(o['key']),
      sections: [
        for (final s in maps(o['sections']))
          BriefSection('${s['title'] ?? ''}', [
            for (final i in maps(s['items']))
              BriefItem('${i['text'] ?? ''}', [for (final n in (i['src'] is List ? i['src'] as List : const [])) if (n is int) n]),
          ]),
      ],
      stocks: [for (final s in maps(o['stocks'])) BriefStock('${s['name'] ?? ''}', '${s['note'] ?? ''}')],
      sources: [
        for (final s in maps(o['sources'])) BriefSource('${s['title'] ?? ''}', '${s['press'] ?? ''}', '${s['url'] ?? ''}'),
      ],
    );
  }

  /// "10.12 (월)".
  String get day {
    final d = DateTime.tryParse(date);
    if (d == null) return date;
    return '${two(d.month)}.${two(d.day)} (${'월화수목금토일'[d.weekday - 1]})';
  }

  /// When it was written, "07:41" in Seoul, or ''.
  String get at {
    final g = generated;
    if (g == null) return '';
    final s = g.toUtc().add(const Duration(hours: 9));
    return '${two(s.hour)}:${two(s.minute)}';
  }

  /// "Claude Opus 5.5" from "claude-opus-5-5".
  String get modelName {
    final parts = model.split('-').where((p) => p.isNotEmpty).toList();
    final words = parts.takeWhile((p) => int.tryParse(p) == null).map((p) => p[0].toUpperCase() + p.substring(1));
    final version = parts.skipWhile((p) => int.tryParse(p) == null).join('.');
    final name = words.isEmpty ? 'Claude' : words.join(' ');
    return version.isEmpty ? name : '$name $version';
  }

  /// The sources an item cites (an index that does not exist is skipped).
  List<BriefSource> cited(BriefItem i) => [for (final n in i.src) if (n >= 0 && n < sources.length) sources[n]];

  /// Days from the trading day it is for to `today` ("YYYY-MM-DD"): 0 today, 1 for yesterday's,
  /// negative for a later day's.
  int age(String today) {
    final a = DateTime.tryParse(date), b = DateTime.tryParse(today);
    return a == null || b == null ? 1 << 20 : b.difference(a).inDays;
  }

  /// Whether to notify it at `seoul` (Seoul wall clock): it is for today, KRX trades today, the
  /// market has not opened yet, and it has not been sent (`sent` is the last day notified).
  bool due(DateTime seoul, String sent) =>
      krxOpen(seoul) && seoul.hour < 9 && date == seoulDate(seoul) && sent != date && headline.isNotEmpty;

  /// The notification's text: the headline, then the key points.
  String notificationText() => [headline, for (final k in key) '· $k'].join('\n');
}

class BriefSection {
  BriefSection(this.title, this.items);

  final String title;
  final List<BriefItem> items;
}

class BriefItem {
  BriefItem(this.text, this.src);

  final String text;

  /// Indices into the briefing's sources.
  final List<int> src;
}

class BriefStock {
  BriefStock(this.name, this.note);

  /// The KRX name, as on the stocks tab (matched by name; Claude does not know the codes).
  final String name;
  final String note;
}

class BriefSource {
  BriefSource(this.title, this.press, this.url);

  final String title, press, url;
}

/// Downloads the briefing and keeps the last one on disk.
class News {
  static Future<File> file() async => File('${(await getApplicationSupportDirectory()).path}/news.json');

  static Future<Briefing> download() async {
    final text = await Net.get('$newsUrl?t=${DateTime.now().millisecondsSinceEpoch}');
    final b = Briefing.parse(jsonDecode(text) as Map<String, dynamic>); // validate before overwriting the cache
    await (await file()).writeAsString(text);
    return b;
  }

  static Future<Briefing?> cached() async {
    try {
      final f = await file();
      if (await f.exists()) return Briefing.parse(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {}
    return null;
  }
}
