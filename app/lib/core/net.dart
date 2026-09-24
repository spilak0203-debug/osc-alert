import 'dart:convert';

import 'package:http/http.dart' as http;

/// Small HTTP GET with the headers Naver expects.
class Net {
  static const maxBytes = 8000000;
  static final _client = http.Client();

  static Future<String> get(String address) async {
    final r = await _client.get(Uri.parse(address), headers: const {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://m.stock.naver.com/',
    }).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw NetException('서버 응답 ${r.statusCode}');
    if (r.bodyBytes.length > maxBytes) throw NetException('응답이 너무 큽니다');
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  static Future<dynamic> json(String address) async => jsonDecode(await get(address));
}

class NetException implements Exception {
  NetException(this.message);

  final String message;

  @override
  String toString() => message;
}
