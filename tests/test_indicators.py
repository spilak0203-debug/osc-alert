"""합치 판정이 기준 구현과 같은 날짜를 내는가.

`fixtures/expected.json`은 기준 구현으로 같은 일봉을 돌려 얻은 날짜다. 네트워크를 쓰지 않는다.
"""
import json
import sys
import unittest
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'signal'))
import indicators as ind  # noqa: E402
import scan  # noqa: E402

FIX = HERE / 'fixtures'


class MatchesOriginal(unittest.TestCase):
    def test_dates(self):
        expected = json.loads((FIX / 'expected.json').read_text(encoding='utf-8'))
        for ticker, want in expected.items():
            f = pd.read_csv(FIX / f'{ticker}.csv', index_col=0, parse_dates=True)
            ev = ind.evaluate(f)
            got = dict(golden=[str(d.date()) for d in ev.index[ev.golden]],
                       dead=[str(d.date()) for d in ev.index[ev.dead]])
            self.assertEqual(got, want, ticker)

    def test_confluence_needs_all_three(self):
        f = pd.read_csv(FIX / '086520.csv', index_col=0, parse_dates=True)
        ev = ind.evaluate(f)
        self.assertTrue((ev.golden == (ev.stoch_gold & ev.rsi_gold & ev.cci_gold)).all())
        # 하나만 켜진 날이 합치보다 훨씬 많아야 정상이다
        self.assertGreater(int(ev.stoch_gold.sum()), int(ev.golden.sum()))


class Session(unittest.TestCase):
    def test_partial_bar_dropped_before_close(self):
        at = lambda h, m: pd.Timestamp(2026, 9, 24, h, m, tz=scan.SEOUL).to_pydatetime()  # 목요일
        self.assertFalse(scan.session_complete(at(15, 30)))
        self.assertTrue(scan.session_complete(at(15, 40)))
        self.assertTrue(scan.session_complete(pd.Timestamp(2026, 9, 26, 10, 0, tz=scan.SEOUL).to_pydatetime()))

    def test_clean_blocks_untradable_day(self):
        f = pd.DataFrame({'Open': [100., 100.], 'High': [110., 105.], 'Low': [90., 95.],
                          'Close': [105., 100.], 'Volume': [1000, 0]},
                         index=pd.to_datetime(['2026-09-01', '2026-09-02']))
        c = scan.clean(f)
        self.assertTrue(c.Tradable.iloc[0])
        self.assertFalse(c.Tradable.iloc[1])
        self.assertTrue(pd.isna(c.Close.iloc[1]))


if __name__ == '__main__':
    unittest.main()
