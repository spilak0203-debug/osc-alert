"""일치 판정이 기준 구현과 같은 날짜를 내는가.

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
        # 하나만 켜진 날이 일치보다 훨씬 많아야 정상이다
        self.assertGreater(int(ev.stoch_gold.sum()), int(ev.golden.sum()))


class MaBreakout(unittest.TestCase):
    @staticmethod
    def frame(closes):
        idx = pd.bdate_range('2026-01-01', periods=len(closes))
        c = pd.Series(closes, index=idx, dtype=float)
        return pd.DataFrame({'Open': c, 'High': c, 'Low': c, 'Close': c, 'Volume': 1000.0})

    def test_flat_then_break(self):
        mb = ind.ma_breakout(self.frame([100.0] * 130 + [104.0]))
        self.assertEqual(list(mb.index[mb.hit]), [mb.index[-1]])

    def test_needs_convergence(self):
        # 이평선이 넓게 벌어진 채(급락 뒤) 올라서는 날은 아니다
        mb = ind.ma_breakout(self.frame([200.0] * 100 + [100.0] * 30 + [104.0]))
        self.assertFalse(mb.hit.any())

    def test_needs_rising_long_lines(self):
        # 오래 내려온 종목: 이평선이 모여도 120일선이 내려가는 중이면 아니다
        closes = [101.0 - i * 0.01 for i in range(130)] + [102.0]
        mb = ind.ma_breakout(self.frame(closes))
        self.assertLess(mb.spread.iloc[-1], ind.MA_SPREAD * 100)   # 모이기는 했다
        self.assertTrue(mb.cross.iloc[-1])                           # 돌파도 했지만
        self.assertFalse(mb.up120.iloc[-1] or mb.hit.iloc[-1])       # 120일선이 내려가는 중


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
