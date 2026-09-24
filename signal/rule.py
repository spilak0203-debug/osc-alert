"""Confluence rule evaluated from two consecutive days of indicator values.

The Android app runs the same rule (`Rule.java`) on `market.json`, so users can change
the settings (slow/fast stochastic, band conditions and levels, 2-of-3) without a new scan.
This file is the reference implementation; tests pin both it and the Java port.

A snapshot is a dict with `k_fast`, `d_fast`, `k_slow`, `d_slow`, `rsi`, `rsi_sig`, `cci`.
Missing values are NaN and make every comparison false, like pandas.
"""
import math

DEFAULTS = dict(stoch='slow', stoch_band=True, stoch_lo=20., stoch_hi=80.,
                rsi_band=True, rsi_lo=30., rsi_hi=70.,
                cci_band=True, cci_level=100.)

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
    """(golden parts, dead parts) — each a tuple of three booleans: stoch, rsi, cci."""
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
