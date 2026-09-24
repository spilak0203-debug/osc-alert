"""오실레이터 3개와 일치 판정. 한 종목 단위로 계산한다.

설정:

    골든 일치 (매수)  세 개가 **같은 날** 전부
        스토캐스틱  Slow 5-3-3 · %K가 %D 상향돌파  +  직전 %K < 20
        RSI(14)    시그널선(9) 상향돌파          +  직전 RSI < 30
        CCI(20)    -100 상향돌파

    데드 일치 (매도)  세 개가 **같은 날** 전부
        스토캐스틱  Slow 5-3-3 · %K가 %D 하향돌파  +  직전 %K > 80
        RSI(14)    시그널선 하향돌파              +  직전 RSI > 70
        CCI(20)    +100 하향돌파
"""
import numpy as np
import pandas as pd

STOCH_N, STOCH_D = 5, 3
STOCH_LO, STOCH_HI = 20, 80
RSI_N, RSI_SIG = 14, 9
RSI_LO, RSI_HI = 30, 70
CCI_N, CCI_BAND = 20, 100


def fast_stochastic(high, low, close, n=STOCH_N, d=STOCH_D):
    """Fast %K = 원값, Fast %D = Fast %K의 d일 평균."""
    hh, ll = high.rolling(n).max(), low.rolling(n).min()
    fast_k = (close - ll) / (hh - ll).replace(0, np.nan) * 100
    return fast_k, fast_k.rolling(d).mean()


def slow_stochastic(high, low, close, n=STOCH_N, d=STOCH_D):
    """Slow %K = Fast %K의 d일 평균, Slow %D = Slow %K의 d일 평균."""
    _, k = fast_stochastic(high, low, close, n, d)
    return k, k.rolling(d).mean()


def series(frame):
    """앱이 일치를 다시 판정하는 데 필요한 지표 일곱 개."""
    h, l, c = frame['High'], frame['Low'], frame['Close']
    fk, fd = fast_stochastic(h, l, c)
    sk, sd = slow_stochastic(h, l, c)
    r, rs = rsi(c)
    return pd.DataFrame({'k_fast': fk, 'd_fast': fd, 'k_slow': sk, 'd_slow': sd,
                         'rsi': r, 'rsi_sig': rs, 'cci': cci(h, l, c)}, index=frame.index)


def cci(high, low, close, n=CCI_N):
    tp = (close + high + low) / 3
    sma = tp.rolling(n).mean()
    mad = (tp - sma).abs().rolling(n).mean()
    return (tp - sma) / (0.015 * mad.replace(0, np.nan))


def rsi(close, n=RSI_N, signal=RSI_SIG):
    """와일더 평활(`ewm(alpha=1/n)`) — HTS 기본과 같은 계산."""
    delta = close.diff()
    up = delta.clip(lower=0).ewm(alpha=1 / n, adjust=False).mean()
    down = (-delta.clip(upper=0)).ewm(alpha=1 / n, adjust=False).mean()
    out = 100 - 100 / (1 + up / down.replace(0, np.nan))
    return out, out.rolling(signal).mean()


def _up(a, b):
    return (a > b) & (a.shift(1) <= (b.shift(1) if isinstance(b, pd.Series) else b))


def _dn(a, b):
    return (a < b) & (a.shift(1) >= (b.shift(1) if isinstance(b, pd.Series) else b))


def evaluate(frame):
    """일봉(`High`·`Low`·`Close`)을 받아 날짜별 지표와 교차 여부를 낸다."""
    h, l, c = frame['High'], frame['Low'], frame['Close']
    k, d = slow_stochastic(h, l, c)
    r, rs = rsi(c)
    cc = cci(h, l, c)
    out = pd.DataFrame({'k': k, 'd': d, 'rsi': r, 'rsi_sig': rs, 'cci': cc}, index=frame.index)
    out['stoch_gold'] = _up(k, d) & (k.shift(1) < STOCH_LO)
    out['rsi_gold'] = _up(r, rs) & (r.shift(1) < RSI_LO)
    out['cci_gold'] = _up(cc, -CCI_BAND)
    out['stoch_dead'] = _dn(k, d) & (k.shift(1) > STOCH_HI)
    out['rsi_dead'] = _dn(r, rs) & (r.shift(1) > RSI_HI)
    out['cci_dead'] = _dn(cc, CCI_BAND)
    for col in ('stoch_gold', 'rsi_gold', 'cci_gold', 'stoch_dead', 'rsi_dead', 'cci_dead'):
        out[col] = out[col].fillna(False).astype(bool)
    out['golden'] = out.stoch_gold & out.rsi_gold & out.cci_gold
    out['dead'] = out.stoch_dead & out.rsi_dead & out.cci_dead
    return out
