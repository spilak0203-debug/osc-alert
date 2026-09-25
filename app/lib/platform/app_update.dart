import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import '../core/net.dart';
import '../core/repo.dart';
import '../ui/toast.dart';
import 'native.dart';

class Release {
  int code = 0;
  String name = '', notes = '', url = '';
  String? sha256;
}

/// Updates from the repository's GitHub releases. Each build is published as release
/// `v<build number>` with `osc-alert.apk` and `osc-alert-setup.exe` attached.
class AppUpdate {
  static int versionCode = 0;
  static String versionName = '';
  static bool _running = false;

  /// While an update downloads: bytes received and the total (0 if unknown). Null otherwise.
  static final progress = ValueNotifier<(int, int)?>(null);

  static Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    versionCode = int.tryParse(info.buildNumber) ?? 0;
    versionName = info.version.split('.').take(2).join('.');
  }

  /// Latest published release for this platform, or null if there is none.
  static Future<Release?> latest() async {
    final r = await Net.json('https://api.github.com/repos/$repoName/releases/latest') as Map<String, dynamic>;
    final tag = '${r['tag_name'] ?? ''}';
    if (!tag.startsWith('v')) return null;
    final code = int.tryParse(tag.substring(1));
    if (code == null) return null;
    final out = Release()
      ..code = code
      ..name = '${r['name'] ?? tag}'
      ..notes = '${r['body'] ?? ''}';
    final suffix = Platform.isAndroid ? '.apk' : '-setup.exe';
    for (final a in (r['assets'] as List? ?? const [])) {
      final m = a as Map<String, dynamic>;
      if ('${m['name']}'.endsWith(suffix)) {
        out.url = '${m['browser_download_url']}';
        final digest = '${m['digest'] ?? ''}';
        if (digest.startsWith('sha256:')) out.sha256 = digest.substring(7);
      }
    }
    return out.url.isEmpty ? null : out;
  }

  static bool newer(Release? r) => r != null && r.code > versionCode;

  static Future<void> install(Release r) async {
    if (_running) {
      Toaster.show('업데이트를 이미 받는 중입니다');
      return;
    }
    _running = true;
    progress.value = (0, 0);
    try {
      if (Platform.isAndroid) {
        final error = await Native.installApk(r.url, r.sha256, (got, size) => progress.value = (got, size));
        if (error != null) Toaster.show(error, long: true);
      } else {
        // Windows: download the installer and run it quietly; it closes this app and starts the new one.
        final file = File('${(await getTemporaryDirectory()).path}/osc-alert-setup-${r.code}.exe');
        final client = http.Client();
        try {
          final res = await client.send(http.Request('GET', Uri.parse(r.url)));
          if (res.statusCode != 200) throw NetException('서버 응답 ${res.statusCode}');
          final size = res.contentLength ?? 0;
          final sink = file.openWrite();
          var got = 0;
          try {
            await for (final chunk in res.stream) {
              sink.add(chunk);
              got += chunk.length;
              progress.value = (got, size);
            }
          } finally {
            await sink.close();
          }
        } finally {
          client.close();
        }
        await Process.start(file.path, ['/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'], mode: ProcessStartMode.detached);
      }
    } catch (e) {
      Toaster.show('$e', long: true);
    } finally {
      _running = false;
      progress.value = null;
    }
  }
}
