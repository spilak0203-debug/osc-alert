"""업종 · 테마 — 네이버 증권의 분류(업종 79개, 테마 260여 개).

종목마다 물으면 2,600번이라, 업종 · 테마마다 그 종목 목록을 받는다(쪽당 100종목, 합쳐 400번 안팎).
한 종목은 업종 하나, 테마는 여럿(없을 수도). 실패하면 그만큼 빈 채로 둔다 — 스캔은 그대로 돈다.
"""
import concurrent.futures
import time

GROUPS_URL = 'https://m.stock.naver.com/api/stocks/{kind}?page={page}&pageSize=100'
MEMBERS_URL = 'https://m.stock.naver.com/api/stocks/{kind}/{no}?page={page}&pageSize=100'
WORKERS = 4


def _pages(get, url, key, **fmt):
    """한 목록의 모든 쪽에서 `key` 항목들."""
    out, page = [], 1
    while True:
        j = get(url.format(page=page, **fmt)).json()
        items = j.get(key) or []
        out += items
        if not items or len(out) >= int(j.get('totalCount') or 0):
            return out
        page += 1


def groups(get, kind):
    """{종목코드: [이름]} — `kind`는 'industry' 또는 'theme'. 이름은 네이버가 주는 순서(인기순)."""
    names = [(g['no'], g['name']) for g in _pages(get, GROUPS_URL, 'groups', kind=kind)]

    def members(item):
        no, name = item
        try:
            return name, [s['itemCode'] for s in _pages(get, MEMBERS_URL, 'stocks', kind=kind, no=no)]
        except Exception:
            return name, []

    out = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for name, codes in pool.map(members, names):
            for c in codes:
                out.setdefault(c, []).append(name)
    return out


def fetch(get, log=print):
    """(업종, 테마) — 각각 {종목코드: [이름]}. 실패한 쪽은 {}."""
    started = time.time()
    found = []
    for kind in ('industry', 'theme'):
        try:
            found.append(groups(get, kind))
        except Exception as exc:
            log(f'  업종·테마: {kind} 실패 - {str(exc)[:120]}')
            found.append({})
    industry, theme = found
    log(f'  업종·테마: 업종 {len(industry)}종목 · 테마 {len(theme)}종목 · {time.time() - started:.0f}초')
    return industry, theme


def table(by_code):
    """{종목: [이름]} → (이름 목록, {종목: [번호]}). market-v2.json엔 이름을 한 번씩만 싣는다."""
    names = sorted({n for ns in by_code.values() for n in ns})
    index = {n: i for i, n in enumerate(names)}
    return names, {c: [index[n] for n in ns] for c, ns in by_code.items()}
