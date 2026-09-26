"""장 마감 뒤 코스피+코스닥 전 종목의 일봉을 받아 **오실레이터 3개 일치**를 찾는다.

    python signal/scan.py                 # 오늘 신호 → signals/latest.json
    python signal/scan.py --limit 50      # 시총 상위 50종목만 (시험용)

**저장해 둔 일봉이 없습니다.** 매번 종목마다 최근 `HISTORY_DAYS` 달력일을 네이버에서 새로
받습니다. RSI(와일더 평활)는 과거가 길수록 수렴하므로 넉넉히 받습니다 — 약 200거래일.

**장이 안 끝났으면 신호를 내지 않습니다.** 장중 봉은 아직 정해지지 않은 종가라 10시에
본 신호와 3시에 본 신호가 달라집니다. 15:40(서울) 전이면 오늘 봉을 버립니다.

**휴장일이면** 마지막 거래일이 오늘이 아니므로 `asof`가 전과 같습니다. 앱은 `asof`가
바뀔 때만 알림을 띄우므로 같은 신호가 두 번 울리지 않습니다.
"""
import argparse
import ast
import concurrent.futures
import json
import sys
import threading
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import numpy as np
import pandas as pd
import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import indicators as ind  # noqa: E402
import rule as rl  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'signals'
SEOUL = ZoneInfo('Asia/Seoul')
HEADERS = {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://m.stock.naver.com/'}
MARKET_URL = 'https://m.stock.naver.com/api/stocks/marketValue/{market}?page={page}&pageSize=100'
PRICE_URL = ('https://api.finance.naver.com/siseJson.naver?symbol={symbol}&requestType=1'
             '&startTime={start}&endTime={end}&timeframe=day')
HISTORY_DAYS = 300
LIQUIDITY = 5e8          # 20일 평균 거래대금 하한 — 골든 일치(매수)에만 건다
CLOSE_AT = (15, 40)      # 정규장 15:30 + 종가 단일가 정리 여유
WORKERS = 8
RETRIES = 3


def now_seoul():
    return datetime.now(SEOUL)


def session_complete(now):
    """오늘 봉이 완성됐는가. 주말은 늘 완성으로 본다."""
    return now.weekday() >= 5 or (now.hour, now.minute) >= CLOSE_AT


_local = threading.local()


def _session():
    """스레드마다 세션 하나. `requests.get`은 호출마다 인증서 묶음을 새로 읽어 0.5초씩
    CPU를 쓴다 — 2,600종목이면 20분이 거기서 샌다. 세션은 연결도 재사용한다."""
    if not hasattr(_local, 's'):
        _local.s = requests.Session()
        _local.s.headers.update(HEADERS)
    return _local.s


def _get(url):
    for attempt in range(RETRIES):
        try:
            r = _session().get(url, timeout=30)
            r.raise_for_status()
            return r
        except requests.RequestException:
            if attempt == RETRIES - 1:
                raise
            time.sleep(1 + attempt * 2)


def _num(v):
    try:
        return float(str(v).replace(',', ''))
    except (TypeError, ValueError):
        return float('nan')


def quote(s):
    """오늘 시세(종가·등락률·거래량). 일봉 API는 최근 봉의 전일 종가를 나중에 고치는 일이 있어
    등락률이 어긋난다 — 알림에 쓰는 숫자는 시세 API 값을 쓴다."""
    chg = _num(s.get('fluctuationsRatio'))
    direction = (s.get('compareToPreviousPrice') or {}).get('code')
    if direction in ('4', '5') and chg > 0:      # 하한·하락인데 부호가 없는 응답
        chg = -chg
    return dict(q_close=_num(s.get('closePriceRaw') or s.get('closePrice')), q_chg=chg,
                q_vol=_num(s.get('accumulatedTradingVolumeRaw') or s.get('accumulatedTradingVolume')),
                q_at=str(s.get('localTradedAt', ''))[:10])


def universe():
    """오늘 시총 순위의 보통주. 우선주(코드 끝이 0이 아님)·ETF·리츠는 뺀다."""
    rows = []
    for market in ('KOSPI', 'KOSDAQ'):
        for page in range(1, 60):
            stocks = _get(MARKET_URL.format(market=market, page=page)).json().get('stocks') or []
            if not stocks:
                break
            for s in stocks:
                if not s['itemCode'].endswith('0') or s.get('stockEndType') != 'stock':
                    continue
                rows.append(dict(ticker=s['itemCode'], name=s['stockName'], market=market,
                                 market_cap=float(str(s['marketValue']).replace(',', '')),
                                 **quote(s)))
    frame = pd.DataFrame(rows).drop_duplicates('ticker')
    return frame.sort_values('market_cap', ascending=False).reset_index(drop=True)


def clean(frame):
    """거래가 없거나 가격이 0인 날,
    고저가가 시가·종가를 1원 넘게 벗어나는 봉은 **거래 불가**로 보고 가격을 비운다."""
    valid = frame.Volume > 0
    for c in ('Open', 'High', 'Low', 'Close'):
        valid &= frame[c].gt(0) & np.isfinite(frame[c])
    high = np.fmax(frame.High, np.fmax(frame.Open, frame.Close))
    low = np.fmin(frame.Low, np.fmin(frame.Open, frame.Close))
    rounding = (high - frame.High).clip(lower=0) + (frame.Low - low).clip(lower=0)
    blocked = valid & rounding.gt(1)
    frame = frame.copy()
    frame['Volume'] = frame.Volume.where(~blocked, 0)
    frame['High'] = high
    frame['Low'] = frame.Low.where(~(valid & ~blocked), low)
    tradable = valid & ~blocked
    frame['Tradable'] = tradable
    frame['DollarVolume'] = frame.Close * frame.Volume
    for c in ('Open', 'High', 'Low', 'Close'):
        frame[c] = frame[c].where(tradable)
    return frame


def daily(ticker, start, end, now):
    r = _get(PRICE_URL.format(symbol=ticker, start=start, end=end))
    rows = ast.literal_eval(r.text.strip())
    if len(rows) < 2:
        return None
    f = pd.DataFrame(rows[1:], columns=[str(c).strip() for c in rows[0]][:len(rows[1])])
    f = f.rename(columns={'날짜': 'Date', '시가': 'Open', '고가': 'High', '저가': 'Low',
                          '종가': 'Close', '거래량': 'Volume'})
    f['Date'] = pd.to_datetime(f.Date.astype(str).str.strip(), format='%Y%m%d')
    f = f.set_index('Date').sort_index()[['Open', 'High', 'Low', 'Close', 'Volume']]
    f = f.apply(pd.to_numeric, errors='coerce').dropna(subset=['Close'])
    f = f[~f.index.duplicated(keep='last')]
    if not session_complete(now):
        f = f[f.index.date < now.date()]
    return clean(f) if len(f) else None


def scan_one(args):
    ticker, start, end, now = args
    try:
        f = daily(ticker, start, end, now)
    except Exception as exc:  # 한 종목 실패가 전체를 멈추면 안 된다
        return ticker, None, str(exc)[:120]
    if f is None or len(f) < 60:
        return ticker, None, 'short'
    return ticker, f, None


def row_for(ticker, name, market, f, ev, day):
    """신호일 `day` 한 줄. 그 종목이 그날 거래가 없었으면 None."""
    if day not in ev.index:
        return None
    e = ev.loc[day]
    dv20 = f.DollarVolume.rolling(20).mean().shift(1).get(day, np.nan)   # 전날까지의 20일 평균
    num = lambda v, nd=1: None if not np.isfinite(v) else round(float(v), nd)
    return dict(ticker=ticker, name=name, market=market,
                close=num(f.Close.get(day, np.nan), 0),
                change=num((f.Close / f.Close.shift(1) - 1).get(day, np.nan) * 100, 2),
                k=num(e.k), d=num(e.d), rsi=num(e.rsi), rsi_sig=num(e.rsi_sig), cci=num(e.cci),
                dv20=num(dv20, 0), liquid=bool(np.isfinite(dv20) and dv20 >= LIQUIDITY),
                golden=bool(e.golden), dead=bool(e.dead),
                parts=dict(stoch=bool(e.stoch_gold or e.stoch_dead),
                           rsi=bool(e.rsi_gold or e.rsi_dead),
                           cci=bool(e.cci_gold or e.cci_dead)))


SNAP_KEYS = ('k_fast', 'd_fast', 'k_slow', 'd_slow', 'rsi', 'rsi_sig', 'cci')


def market_row(ticker, info, f, day):
    """`market.json` 한 줄. 앱이 설정대로 일치를 다시 판정하도록 신호일까지 최근 `rl.HISTORY`일의
    지표를 싣는다(오래된 날부터). 일치 허용 기간이 최대 4일이라 6일이면 된다.

    지표는 소수 넷째 자리까지 — 교차 판정에서 두 선이 거의 붙어 있을 때 반올림이 결과를
    뒤집지 않게 넉넉히 둔다. 신호일에 거래가 없던 종목도 목록에는 넣는다(지표는 비어 있음)."""
    s = ind.series(f)
    at = f.index.get_indexer([day])[0]
    num = rl.clean_number
    row = dict(t=ticker, n=info['name'], m='KS' if info['market'] == 'KOSPI' else 'KQ',
               cap=num(info['market_cap'], 0))
    closes = f.Close.dropna()
    if info.get('q_at') == day.strftime('%Y-%m-%d') and np.isfinite(info.get('q_close', np.nan)):
        # 시세 API가 신호일과 같은 날의 값이면 그걸 쓴다 (등락률이 증권사 화면과 같다).
        row['close'], row['chg'], row['vol'] = num(info['q_close'], 0), num(info['q_chg'], 2), num(info['q_vol'], 0)
    else:
        row['close'] = num(closes.iloc[-1], 0) if len(closes) else None
        row['chg'] = num((closes.iloc[-1] / closes.iloc[-2] - 1) * 100, 2) if len(closes) > 1 else None
        row['vol'] = num(f.Volume.iloc[-1], 0)
    dv20 = f.DollarVolume.rolling(20).mean().shift(1)
    row['dv20'] = num(dv20.iloc[at], 0) if at >= 0 else None
    # 전 거래일 대비 거래량 배수 (전날 거래가 없었으면 뺀다)
    traded = f.Volume[f.Volume > 0]
    if at >= 0 and f.Volume.iloc[at] > 0 and traded.index.get_loc(day) >= 1:
        row['vr'] = num(f.Volume.iloc[at] / traded.iloc[traded.index.get_loc(day) - 1], 2)
    mb = ind.ma_breakout(f)
    # 이평선 밀집 돌파. 스팩은 공모가 근처에 붙어 있어 늘 밀집이고, 거래가 적은 종목은 신호가
    # 흔들리므로 백테스트와 같이 거래대금 5억 이상만.
    #   mb:  [전날 이평선 폭 %, 거래량 배수, 60일선 상승 0/1, 120일선 상승 0/1] — 앱 2.48부터, 장기선
    #        조건은 앱 설정대로 고른다
    #   mab: [폭, 거래량 배수] — 60·120일선이 둘 다 상승일 때만 (2.47 이하 앱이 읽는 형식)
    if (at >= 0 and mb.cross.iloc[at] and dv20.iloc[at] >= LIQUIDITY and '스팩' not in info['name']):
        e = mb.iloc[at]
        row['mb'] = [num(e.spread, 2), num(e.volume, 2), int(bool(e.up60)), int(bool(e.up120))]
        if e.hit:
            row['mab'] = [num(e.spread, 2), num(e.volume, 2)]
    if at >= 1:
        lo = max(0, at - rl.HISTORY + 1)
        for key in SNAP_KEYS:
            row[key] = [num(v, 4) for v in s[key].iloc[lo:at + 1]]
    return row


def run(limit=None, now=None, progress=print):
    now = now or now_seoul()
    uni = universe()
    if limit:
        uni = uni.head(limit)
    start = (now.date() - timedelta(days=HISTORY_DAYS)).strftime('%Y%m%d')
    end = now.date().strftime('%Y%m%d')
    frames, failed = {}, []
    jobs = [(t, start, end, now) for t in uni.ticker]
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for n, (t, f, err) in enumerate(pool.map(scan_one, jobs), 1):
            if f is None:
                if err != 'short':
                    failed.append(t)
            else:
                frames[t] = f
            if n % 300 == 0:
                progress(f'  일봉 {n}/{len(jobs)} · 실패 {len(failed)}')
    if not frames:
        raise RuntimeError('일봉을 하나도 못 받았다 — 네이버 접속을 확인하세요')

    # 신호일 = 가장 많은 종목이 가진 마지막 날짜. 한두 종목만 가진 날짜는 자료 오류다.
    last = pd.Series([f.index[-1] for f in frames.values()]).value_counts()
    day = last.index[0]
    info = uni.set_index('ticker')
    rows, market = [], []
    for t, f in frames.items():
        ev = ind.evaluate(f)
        r = row_for(t, info.at[t, 'name'], info.at[t, 'market'], f, ev, day)
        if r and (r['golden'] or r['dead']):
            rows.append(r)
        market.append(market_row(t, info.loc[t], f, day))
    market.sort(key=lambda r: -(r['cap'] or 0))
    golden = sorted([r for r in rows if r['golden']], key=lambda r: -(r['dv20'] or 0))
    dead = sorted([r for r in rows if r['dead']], key=lambda r: -(r['dv20'] or 0))
    return dict(
        asof=day.strftime('%Y-%m-%d'),
        generated=datetime.now(timezone.utc).isoformat(timespec='seconds'),
        scanned=len(frames), universe=len(uni), failed=len(failed), liquidity=LIQUIDITY,
        rules=dict(stochastic='Slow 5-3-3 · %K/%D 교차 · 직전 %K <20 / >80',
                   rsi='RSI(14) · 시그널(9) 교차 · 직전 RSI <30 / >70',
                   cci='CCI(14) · -100 상향 / +100 하향',
                   confluence='세 개가 같은 날 전부'),
        golden=golden, dead=dead), dict(
        asof=day.strftime('%Y-%m-%d'),
        generated=datetime.now(timezone.utc).isoformat(timespec='seconds'),
        liquidity=LIQUIDITY, stocks=market)


def save(payload, market):
    OUT.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, ensure_ascii=False, indent=1)
    (OUT / 'latest.json').write_text(text, encoding='utf-8')
    (OUT / 'history').mkdir(exist_ok=True)
    (OUT / 'history' / f'{payload["asof"]}.json').write_text(text, encoding='utf-8')
    # 전 종목 지표는 커밋하지 않는다(매일 수백 KB가 기록에 쌓인다). 워크플로가 릴리스 자산으로 올린다.
    # market-v2.json: 최근 6일치 (앱 2.10부터). market.json: 마지막 2일만 — 2.9 이하 앱은 배열의
    # 앞 두 값을 전날·신호일로 읽으므로 이 형식을 그대로 둬야 한다.
    dump = lambda m: json.dumps(m, ensure_ascii=False, separators=(',', ':'))
    (OUT / 'market-v2.json').write_text(dump(market), encoding='utf-8')
    legacy = dict(market, stocks=[{k: (v[-2:] if k in SNAP_KEYS else v) for k, v in r.items()}
                                  for r in market['stocks']])
    (OUT / 'market.json').write_text(dump(legacy), encoding='utf-8')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--limit', type=int, help='시총 상위 N종목만 (시험용)')
    p.add_argument('--dry-run', action='store_true', help='파일로 저장하지 않는다')
    a = p.parse_args()
    payload, market = run(limit=a.limit)
    if not a.dry_run:
        save(payload, market)
    liquid = [r for r in payload['golden'] if r['liquid']]
    print(f"{payload['asof']} 종가 기준 · {payload['scanned']}/{payload['universe']}종목 "
          f"(실패 {payload['failed']})")
    print(f"골든 일치 {len(payload['golden'])}건 (거래대금 5억↑ {len(liquid)}건) · "
          f"데드 일치 {len(payload['dead'])}건")
    mb = [r for r in market['stocks'] if 'mb' in r]
    print(f"이평선 밀집 돌파 {len(mb)}건 (60·120 둘 다 상승 {sum('mab' in r for r in mb)}건): "
          + ', '.join(f"{r['n']}{'' if 'mab' in r else '(장기선 ' + ''.join('↑' if u else '↓' for u in r['mb'][2:]) + ')'}"
                      for r in mb[:20]))
    for label, key in (('골든', 'golden'), ('데드', 'dead')):
        for r in payload[key][:30]:
            print(f"  [{label}] {r['ticker']} {r['name']:<12} {r['close']:>10,.0f}원  "
                  f"RSI {r['rsi']}  CCI {r['cci']}  %K {r['k']}"
                  + ('' if key == 'dead' or r['liquid'] else '  (거래대금 미달)'))


if __name__ == '__main__':
    main()
