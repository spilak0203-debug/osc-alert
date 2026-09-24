"""The two-day rule (`rule.py`, used by the app) must agree with the full-series evaluation."""
import sys
import unittest
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'signal'))
import indicators as ind  # noqa: E402
import rule as rl  # noqa: E402

FIX = HERE / 'fixtures'
TICKERS = ('005930', '247540', '086520')


def load(t):
    return pd.read_csv(FIX / f'{t}.csv', index_col=0, parse_dates=True)


class TwoDayRule(unittest.TestCase):
    def test_default_matches_series(self):
        for t in TICKERS:
            f = load(t)
            ev, s = ind.evaluate(f), ind.series(f)
            recs = s.to_dict('records')
            for i in range(1, len(recs)):
                g, d = rl.parts(recs[i - 1], recs[i])
                self.assertEqual(all(g), bool(ev.golden.iloc[i]), (t, s.index[i]))
                self.assertEqual(all(d), bool(ev.dead.iloc[i]), (t, s.index[i]))
                self.assertEqual(g, (bool(ev.stoch_gold.iloc[i]), bool(ev.rsi_gold.iloc[i]),
                                     bool(ev.cci_gold.iloc[i])))

    def test_loosening_only_adds_signals(self):
        loose = dict(stoch_band=False, rsi_band=False, cci_band=False)
        s = ind.series(load('086520')).to_dict('records')
        strict_n = loose_n = 0
        for i in range(1, len(s)):
            a = sum(rl.parts(s[i - 1], s[i])[0])
            b = sum(rl.parts(s[i - 1], s[i], {**loose, 'cci_band': True})[0])
            self.assertGreaterEqual(b, a)
            strict_n += a == 3
            loose_n += b == 3
        self.assertGreater(loose_n, strict_n)

    def test_missing_values_never_fire(self):
        empty = {k: None for k in ('k_fast', 'd_fast', 'k_slow', 'd_slow', 'rsi', 'rsi_sig', 'cci')}
        self.assertEqual(rl.parts(empty, empty), ((False,) * 3, (False,) * 3))
        self.assertEqual(rl.zones(empty), (0, 0))


if __name__ == '__main__':
    unittest.main()
