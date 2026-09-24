"""Writes the fixtures the Android unit tests compare against.

    python tests/make_java_fixtures.py

`Rule.java` and `Indicators.java` are ports of `rule.py` and `indicators.py`. These files
hold Python's answers so the JVM tests (run in the android workflow) catch any drift.
"""
import json
import math
import random
import sys
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'signal'))
import indicators as ind  # noqa: E402
import rule as rl  # noqa: E402

OUT = HERE.parent / 'android/app/src/test/resources'
CONFIGS = [
    {},
    dict(stoch='fast'),
    dict(stoch_band=False, rsi_band=False),
    dict(cci_band=False),
    dict(stoch_lo=30., stoch_hi=70., rsi_lo=40., rsi_hi=60., cci_level=80.),
]


def clean(v):
    return None if v is None or not math.isfinite(v) else v


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rng = random.Random(7)
    cases = []
    for t in ('005930', '086520'):
        s = ind.series(pd.read_csv(HERE / 'fixtures' / f'{t}.csv', index_col=0, parse_dates=True))
        recs = [{k: clean(v) for k, v in r.items()} for r in s.to_dict('records')]
        for ci, cfg in enumerate(CONFIGS):
            for i in range(1, len(recs)):
                g, d = rl.parts(recs[i - 1], recs[i], cfg)
                if sum(g) >= 2 or sum(d) >= 2 or rng.random() < .03:
                    cases.append(dict(config=ci, prev=recs[i - 1], last=recs[i],
                                      golden=list(g), dead=list(d), zones=list(rl.zones(recs[i], cfg))))
    (OUT / 'rule_cases.json').write_text(json.dumps(dict(configs=CONFIGS, cases=cases)), encoding='utf-8')

    # 앱은 거래 없는 날을 빼고 차트를 그린다 — 같은 입력으로 비교한다.
    f = pd.read_csv(HERE / 'fixtures' / '005930.csv', index_col=0, parse_dates=True).dropna().tail(400)
    s = ind.series(f)
    for n in (5, 20, 60, 120):
        s[f'ma{n}'] = f.Close.rolling(n).mean()
    tail = s.tail(150)
    (OUT / 'indicator_series.json').write_text(json.dumps(dict(
        high=f.High.tolist(), low=f.Low.tolist(), close=f.Close.tolist(),
        expected={k: [clean(v) for v in tail[k].tolist()] for k in tail.columns})), encoding='utf-8')
    print(f'{len(cases)} rule cases, {len(tail)} indicator rows → {OUT}')


if __name__ == '__main__':
    main()
