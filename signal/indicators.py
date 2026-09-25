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
MA_SPANS = (5, 20, 60, 120)
MA_SPREAD = 0.015    # 전날 이평선 넷의 폭이 종가의 1.5% 안
MA_SLOPE = 5         # 60·120일선이 5거래일 전보다 낮지 않음


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


def ma_breakout(frame):
    """이평선 밀집 돌파: 전날 5·20·60·120일선이 종가의 `MA_SPREAD` 안에 모여 있다가 오늘 종가가
    넷 모두 위로 처음 올라서고, 60·120일선이 `MA_SLOPE`거래일 전보다 낮지 않은 날.

    `spread`는 전날 이평선 폭(종가 대비 %), `volume`은 오늘 거래량 ÷ 직전 20일 평균.
    과거 1년 백테스트(34건)에서 10거래일 뒤 오른 비율 69% (아무 종목·아무 날은 42%). 3%로 두면
    거의 안 움직이는 종목이 이평선을 들락거릴 때마다 찍혀 1.5%로 좁혔다."""
    c = frame['Close'].ffill()
    ma = pd.concat([c.rolling(n).mean() for n in MA_SPANS], axis=1, ignore_index=True)
    top = ma.max(axis=1).where(ma.notna().all(axis=1))
    spread = (top - ma.min(axis=1)) / c
    rising = (ma[2] >= ma[2].shift(MA_SLOPE)) & (ma[3] >= ma[3].shift(MA_SLOPE))
    hit = (spread.shift(1) <= MA_SPREAD) & (c > top) & (c.shift(1) <= top.shift(1)) & rising
    if 'Tradable' in frame:
        hit &= frame['Tradable'].astype(bool)
    vol = frame['Volume']
    return pd.DataFrame({'hit': hit, 'spread': spread.shift(1) * 100,
                         'volume': vol / vol.rolling(20).mean().shift(1)}, index=frame.index)


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
