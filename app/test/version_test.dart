// The version rule (README "Releases"): pubspec.yaml's `<name>+<build>` and the changelog's top
// entry agree, so the release title, the app's version and its notes match.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oscalert/platform/app_update.dart';

void main() {
  final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
  final m = RegExp(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$').firstMatch(line);

  test('pubspec has a three-part name and a build number', () {
    expect(m, isNotNull, reason: line);
    expect(int.parse(m!.group(4)!), greaterThan(54), reason: 'builds continue after v54');
    // From 3.0 on, every part is one digit (2.1–2.55 came before the rule).
    if (int.parse(m.group(1)!) >= 3) {
      for (final g in [m.group(2)!, m.group(3)!]) {
        expect(int.parse(g), lessThanOrEqualTo(9), reason: '$line: after x.9 the part to the left goes up');
      }
    }
  });

  test('the changelog\'s top entry is this version', () {
    final log = jsonDecode(File('assets/changelog.json').readAsStringSync()) as List;
    final name = '${m!.group(1)}.${m.group(2)}.${m.group(3)}';
    // Changes waiting for the next release sit in an entry with no version on top; the release
    // gives it the new name in the same commit that raises pubspec's version.
    final released = (log.first as Map)['version'] == null ? log[1] as Map : log.first as Map;
    expect(released['version'], AppUpdate.displayVersion(name));
    final versions = [for (final e in log) (e as Map)['version']].whereType<String>().toList();
    expect(versions.toSet().length, versions.length, reason: 'each version once');
  });

  test('a zero patch is left off', () {
    expect(AppUpdate.displayVersion('2.55.0'), '2.55');
    expect(AppUpdate.displayVersion('2.55.1'), '2.55.1');
    expect(AppUpdate.displayVersion('3.0.0'), '3.0');
  });
}
