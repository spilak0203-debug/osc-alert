// The stock filter's minimum price: 4,000원 by default, on the signal day's close.
import 'package:flutter_test/flutter_test.dart';
import 'package:oscalert/core/settings.dart';
import 'package:oscalert/core/stock.dart';
import 'package:shared_preferences/shared_preferences.dart';

Stock at(double close) => Stock()
  ..ticker = '000001'
  ..market = '코스피'
  ..close = close;

void main() {
  test('cheap stocks are left out unless the minimum is off', () async {
    SharedPreferences.setMockInitialValues({});
    await Settings.init();
    final st = Settings.I;
    expect(st.passes(at(3990)), isFalse);
    expect(st.passes(at(4000)), isTrue);
    expect(st.passes(at(double.nan)), isTrue); // unknown close
    expect(st.filterSummary(), '주가 4,000원↑');
    await st.setNumber(Settings.filterPrice, 0);
    expect(st.passes(at(500)), isTrue);
    expect(st.filterSummary(), '');
  });
}
