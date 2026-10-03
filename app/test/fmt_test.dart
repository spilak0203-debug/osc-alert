// Shared helpers in core/fmt.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:oscalert/core/fmt.dart';

void main() {
  test('stableSort keeps equal items in their order', () {
    final list = [for (var i = 0; i < 40; i++) (i % 3, i)];
    stableSort<(int, int)>(list, (a, b) => a.$1.compareTo(b.$1));
    for (var i = 1; i < list.length; i++) {
      final a = list[i - 1], b = list[i];
      expect(a.$1 < b.$1 || (a.$1 == b.$1 && a.$2 < b.$2), isTrue, reason: '$a before $b');
    }
  });

  test('won amounts read out as they are said', () {
    expect(wonReading(5000000), '5백만원');
    expect(wonReading(4000), '4천원');
    expect(wonReading(2500), '2,500원');
    expect(wonReading(500000), '50만원');
    expect(wonReading(1234500), '123만 4,500원');
    expect(wonReading(5e8), '5억원');
    expect(wonReading(0.5e8), '5천만원');
    expect(wonReading(12345e8), '1조 2,345억원');
    expect(wonReading(1e12), '1조원');
    expect(wonReading(0), '');
    expect(wonReading(double.nan), '');
  });
}
