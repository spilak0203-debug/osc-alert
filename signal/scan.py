"""장 마감 뒤 코스피+코스닥 전 종목의 일봉을 받아 **오실레이터 3개 합치**를 찾는다.

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

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'signals'
SEOUL = ZoneInfo('Asia/Seoul')
HEADERS = {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://m.stock.naver.com/'}
MARKET_URL = 'https://m.stock.naver.com/api/stocks/marketValue/{market}?page={page}&pageSize=100'
PRICE_URL = ('https://api.finance.naver.com/siseJson.naver?symbol={symbol}&requestType=1'
             '&startTime={start}&endTime={end}&timeframe=day')
HISTORY_DAYS = 300
LIQUIDITY = 5e8          # 20일 평균 거래대금 하한 — 골든 합치(매수)에만 건다
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
                                 market_cap=float(str(s['marketValue']).replace(',', ''))))
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
    rows = []
    for t, f in frames.items():
        ev = ind.evaluate(f)
        r = row_for(t, info.at[t, 'name'], info.at[t, 'market'], f, ev, day)
        if r and (r['golden'] or r['dead']):
            rows.append(r)
    golden = sorted([r for r in rows if r['golden']], key=lambda r: -(r['dv20'] or 0))
    dead = sorted([r for r in rows if r['dead']], key=lambda r: -(r['dv20'] or 0))
    return dict(
        asof=day.strftime('%Y-%m-%d'),
        generated=datetime.now(timezone.utc).isoformat(timespec='seconds'),
        scanned=len(frames), universe=len(uni), failed=len(failed), liquidity=LIQUIDITY,
        rules=dict(stochastic='Slow 5-3-3 · %K/%D 교차 · 직전 %K <20 / >80',
                   rsi='RSI(14) · 시그널(9) 교차 · 직전 RSI <30 / >70',
                   cci='CCI(20) · -100 상향 / +100 하향',
                   confluence='세 개가 같은 날 전부'),
        golden=golden, dead=dead)


def save(payload):
    OUT.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, ensure_ascii=False, indent=1)
    (OUT / 'latest.json').write_text(text, encoding='utf-8')
    (OUT / 'history').mkdir(exist_ok=True)
    (OUT / 'history' / f'{payload["asof"]}.json').write_text(text, encoding='utf-8')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--limit', type=int, help='시총 상위 N종목만 (시험용)')
    p.add_argument('--dry-run', action='store_true', help='파일로 저장하지 않는다')
    a = p.parse_args()
    payload = run(limit=a.limit)
    if not a.dry_run:
        save(payload)
    liquid = [r for r in payload['golden'] if r['liquid']]
    print(f"{payload['asof']} 종가 기준 · {payload['scanned']}/{payload['universe']}종목 "
          f"(실패 {payload['failed']})")
    print(f"골든 합치 {len(payload['golden'])}건 (거래대금 5억↑ {len(liquid)}건) · "
          f"데드 합치 {len(payload['dead'])}건")
    for label, key in (('골든', 'golden'), ('데드', 'dead')):
        for r in payload[key][:30]:
            print(f"  [{label}] {r['ticker']} {r['name']:<12} {r['close']:>10,.0f}원  "
                  f"RSI {r['rsi']}  CCI {r['cci']}  %K {r['k']}"
                  + ('' if key == 'dead' or r['liquid'] else '  (거래대금 미달)'))


if __name__ == '__main__':
    main()
