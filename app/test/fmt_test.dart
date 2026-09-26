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
}
