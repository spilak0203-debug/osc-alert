"""Indicator-match rule evaluated from the last few days of indicator values.

The Android app runs the same rule (`Rule.java`) on `market.json`, so users can change the
settings (slow/fast stochastic, band conditions and levels, match window, 2-of-3) without a new
scan. This file is the reference implementation; tests pin both it and the Java port.

A snapshot is a dict with `k_fast`, `d_fast`, `k_slow`, `d_slow`, `rsi`, `rsi_sig`, `cci`.
Missing values are NaN and make every comparison false, like pandas.

**Match window.** With window W, an indicator counts if it crossed on the signal day or in the
W days before it, and at least one indicator must cross on the signal day itself — so a signal
fires once, on the day the last indicator joins. W = 0 means all on the same day.
"""
import math

DEFAULTS = dict(stoch='slow', stoch_band=True, stoch_lo=20., stoch_hi=80.,
                rsi_band=True, rsi_lo=30., rsi_hi=70.,
                cci_band=True, cci_level=100., window=0)
MAX_WINDOW = 4
HISTORY = MAX_WINDOW + 2          # days of values the app needs: window + signal day + one before

NAN = float('nan')


def _v(s, key):
    x = s.get(key)
    return NAN if x is None else float(x)


def _up(a0, a1, b0, b1):
    """a crossed above b between yesterday (0) and today (1)."""
    return a1 > b1 and a0 <= b0


def _dn(a0, a1, b0, b1):
    return a1 < b1 and a0 >= b0


def parts(prev, last, cfg=None):
    """Crossings between two consecutive days: (golden, dead), each (stoch, rsi, cci) booleans."""
    c = {**DEFAULTS, **(cfg or {})}
    kk, dd = ('k_slow', 'd_slow') if c['stoch'] == 'slow' else ('k_fast', 'd_fast')
    k0, k1, d0, d1 = _v(prev, kk), _v(last, kk), _v(prev, dd), _v(last, dd)
    r0, r1, s0, s1 = _v(prev, 'rsi'), _v(last, 'rsi'), _v(prev, 'rsi_sig'), _v(last, 'rsi_sig')
    c0, c1 = _v(prev, 'cci'), _v(last, 'cci')

    stoch_g = _up(k0, k1, d0, d1) and (not c['stoch_band'] or k0 < c['stoch_lo'])
    stoch_d = _dn(k0, k1, d0, d1) and (not c['stoch_band'] or k0 > c['stoch_hi'])
    rsi_g = _up(r0, r1, s0, s1) and (not c['rsi_band'] or r0 < c['rsi_lo'])
    rsi_d = _dn(r0, r1, s0, s1) and (not c['rsi_band'] or r0 > c['rsi_hi'])
    lv = c['cci_level'] if c['cci_band'] else 0.
    cci_g = _up(c0, c1, -lv, -lv)
    cci_d = _dn(c0, c1, lv, lv)
    return (stoch_g, rsi_g, cci_g), (stoch_d, rsi_d, cci_d)


def match(snaps, cfg=None):
    """Signal on the last day of `snaps` (oldest first). Returns (golden, dead), each a tuple of
    three booleans: did that indicator cross within the window. A side with no crossing on the
    last day returns all False — the signal belongs to the day the last indicator joined."""
    c = {**DEFAULTS, **(cfg or {})}
    w = int(c['window'])
    days = [parts(snaps[i - 1], snaps[i], c) for i in range(max(1, len(snaps) - 1 - w), len(snaps))]
    out = []
    for side in (0, 1):
        today = days[-1][side]
        wide = tuple(any(d[side][j] for d in days) for j in range(3))
        out.append(wide if any(today) else (False,) * 3)
    return tuple(out)


def zones(snap, cfg=None):
    """(oversold count, overbought count) of the three indicators on one day."""
    c = {**DEFAULTS, **(cfg or {})}
    k = _v(snap, 'k_slow' if c['stoch'] == 'slow' else 'k_fast')
    r, x = _v(snap, 'rsi'), _v(snap, 'cci')
    low = (k < c['stoch_lo']) + (r < c['rsi_lo']) + (x < -c['cci_level'])
    high = (k > c['stoch_hi']) + (r > c['rsi_hi']) + (x > c['cci_level'])
    return int(low), int(high)


def clean_number(x, nd=2):
    return None if x is None or not math.isfinite(x) else round(float(x), nd)
