"""기업행위 — 무상 · 유상증자, 감자, 주식 분할 · 병합을 DART 전자공시로 미리 안다.

권리락 · 재상장 날은 가격 기준이 바뀌어 일봉이 뚝 떨어진(또는 뛴) 것처럼 보인다. 그날과 다음 거래일의
신호는 가짜일 수 있어 앱이 "기업행위 영향"으로 표시하고, 보유종목엔 새 결정 공시와 다음 거래일의
권리락 · 매매정지 · 재상장을 따로 알린다. (ChatGPT/investment `osc/corporate.py`의 판단을 옮겼다.)

    자료   DART 공시 목록(list.json)을 **회사를 정하지 않고** 날짜로 받는다 — 종목마다 물으면 하루 5천 번이
           넘는다. 회사 없이 물으면 기간이 3개월까지라 `LOOKBACK`을 두 번에 나눠 받는다. 주요사항보고(B)와
           거래소 수시공시(I001)에서 제목으로 고르고, 무상증자 · 감자 · 유무상증자는 상세 API, 유상증자 ·
           분할 · 병합은 공시 원문에서 기준일 · 매매정지 기간 · 신주 상장일을 읽는다. 정정 공시는 마지막 것.
    키     환경변수 `DART_API_KEY`(저장소 비밀값). 없거나 DART가 안 되면 빈 결과 — 스캔은 그대로 돈다.
"""
import concurrent.futures
import io
import os
import re
import time
import zipfile
from datetime import date, timedelta

import requests

API = 'https://opendart.fss.or.kr/api'
LOOKBACK = 120                 # 달력일. 결정부터 신주 상장까지 분할 · 병합 · 감자는 두세 달
WINDOW = 60                    # 회사 없이 묻는 목록은 3개월까지 — 넉넉히 두 달씩
FALLBACK = 90                  # 날짜를 못 읽은 사건은 결정 뒤 이만큼 진행 중으로 본다
NEW_DAYS = 3                   # 결정 공시 뒤 이 달력일 동안 "새 공시"
TIMEOUT = 20
WORKERS = 3
KINDS = [                      # (이름, 제목, 상세 API) — 순서대로 본다(유무상증자가 먼저)
    ('유무상증자', r'유무상증자결정', 'pifricDecsn'),
    ('무상증자', r'무상증자결정', 'fricDecsn'),
    ('유상증자', r'유상증자결정', None),
    ('감자', r'감자결정', 'crDecsn'),
    ('주식분할', r'주식분할결정', None),
    ('주식병합', r'주식병합결정', None),
]
SKIP = r'취소|철회|결과|첨부|자회사|종속회사'
DATE = re.compile(r'(\d{4})\s*[-.년]\s*(\d{1,2})\s*[-.월]\s*(\d{1,2})')
# 평일 휴장일 — 앱 app/lib/core/market_index.dart의 krxHolidays와 같게 둔다.
HOLIDAYS = {
    '2026-01-01', '2026-02-16', '2026-02-17', '2026-02-18', '2026-03-02', '2026-05-01', '2026-05-05',
    '2026-05-25', '2026-06-03', '2026-08-17', '2026-09-24', '2026-09-25', '2026-10-05', '2026-10-09',
    '2026-12-25', '2026-12-31',
    '2027-01-01', '2027-02-08', '2027-02-09', '2027-03-01', '2027-05-05', '2027-05-13', '2027-08-16',
    '2027-09-14', '2027-09-15', '2027-09-16', '2027-10-04', '2027-10-11', '2027-12-27', '2027-12-31',
}


class Quota(Exception):
    pass


def key():
    return os.environ.get('DART_API_KEY', '').strip()


def safe(exc):
    """An error's text without the key: a failed request's message carries its URL, which has
    `crtfc_key=` in it (the Actions log is public; GitHub masks the secret too, this is the
    second lock)."""
    text = re.sub(r"crtfc_key=[^&\s'\")]*", 'crtfc_key=***', str(exc))
    return text.replace(key(), '***') if key() else text


def _get(path, **params):
    j = requests.get(f'{API}/{path}', params=dict(crtfc_key=key(), **params), timeout=TIMEOUT).json()
    status = str(j.get('status'))
    if status == '020':
        raise Quota(j.get('message'))
    if status not in ('000', '013'):          # 013: 조회된 자료 없음
        raise RuntimeError(f"DART {status} {j.get('message')}")
    return j


# ---- 거래일 --------------------------------------------------------------------------------------

def is_session(d):
    return d.weekday() < 5 and d.isoformat() not in HOLIDAYS


def previous_session(d):
    d -= timedelta(days=1)
    while not is_session(d):
        d -= timedelta(days=1)
    return d


def next_session(d):
    d += timedelta(days=1)
    while not is_session(d):
        d += timedelta(days=1)
    return d


# ---- 공시 읽기 -----------------------------------------------------------------------------------

def _date(text):
    m = DATE.search(text or '')
    if not m:
        return None
    try:
        return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    except ValueError:
        return None


def _after(text, label, n=1, span=70):
    """`label` 뒤 `span`자 안의 날짜 n개. 원문은 공백을 지운 채로 받는다."""
    m = re.search(label, text)
    if not m:
        return []
    out = []
    for g in DATE.finditer(text[m.end():m.end() + span]):
        try:
            out.append(date(int(g.group(1)), int(g.group(2)), int(g.group(3))))
        except ValueError:
            pass
    return out[:n]


def document(rcept_no):
    """공시 원문(태그 · 공백 지움)."""
    r = requests.get(f'{API}/document.xml', params=dict(crtfc_key=key(), rcept_no=rcept_no), timeout=TIMEOUT)
    try:
        z = zipfile.ZipFile(io.BytesIO(r.content))
    except zipfile.BadZipFile:
        return ''
    parts = []
    for name in z.namelist():
        b = z.read(name)
        for enc in ('utf-8', 'cp949'):
            try:
                parts.append(b.decode(enc))
                break
            except UnicodeDecodeError:
                continue
    return re.sub(r'\s+', '', re.sub(r'<[^>]+>', ' ', ' '.join(parts)))


def parse_document(text):
    """원문 → 기준일 · 매매정지 · 신주 상장일 · 증자 방식."""
    base = _after(text, r'신주배정기준일|배정기준일|감자기준일|병합기준일|분할기준일')
    halt = _after(text, r'매매거래정지(예정)?기간', 2, 90)
    listing = _after(text, r'신주권?의?상장예정일|상장예정일')
    method = re.search(r'증자방식(.{0,20}?배정|.{0,20}?공모)', text)
    return dict(base=base[0] if base else None, halt_from=halt[0] if len(halt) > 0 else None,
                halt_to=halt[1] if len(halt) > 1 else None, listing=listing[0] if listing else None,
                method=method.group(1) if method else None)


def details(api, corp, rcept_no, decided):
    if api:
        d = decided.strftime('%Y%m%d')
        rows = [r for r in _get(f'{api}.json', corp_code=corp, bgn_de=d, end_de=d).get('list', [])
                if r.get('rcept_no') == rcept_no]
        if rows:
            r = rows[-1]
            if api == 'fricDecsn':
                return dict(base=_date(r.get('nstk_asstd')), listing=_date(r.get('nstk_lstprd')),
                            ratio=r.get('nstk_ascnt_ps_ostk'))
            if api == 'pifricDecsn':
                return dict(base=_date(r.get('fric_nstk_asstd')), listing=_date(r.get('fric_nstk_lstprd')),
                            ratio=r.get('fric_nstk_ascnt_ps_ostk'), method=r.get('piic_ic_mthn'))
            if api == 'crDecsn':
                return dict(base=_date(r.get('cr_std')), halt_from=_date(r.get('crsc_trspprpd_bgd')),
                            halt_to=_date(r.get('crsc_trspprpd_edd')), listing=_date(r.get('crsc_nstklstprd')),
                            ratio=r.get('cr_rt_ostk'))
    return parse_document(document(rcept_no))


def kind_of(report_nm):
    """공시 제목 → (사건 종류, 상세 API, 취소인가). 해당 없으면 None."""
    full = re.sub(r'\s+', '', report_nm)
    norm = re.sub(r'^주요사항보고서\((.*)\)$', r'\1', re.sub(r'^\[[^\]]*\]', '', full))
    for kind, pat, api in KINDS:
        if re.search(pat, norm):
            if re.search(r'취소|철회', full):
                return kind, api, True
            if re.search(SKIP, full):
                return None
            return kind, api, False
    return None


def pick(rows):
    """한 회사의 공시들 → {종류: (첫 결정일, 마지막 접수번호, 상세 API)}. 취소된 종류는 뺀다."""
    latest, cancelled = {}, set()
    for r in sorted(rows, key=lambda r: r['rcept_no']):
        k = kind_of(r['report_nm'])
        if not k:
            continue
        kind, api, cancel = k
        if cancel:
            cancelled.add(kind)
            continue
        first = latest.get(kind, (r['rcept_dt'],))[0]          # 결정일은 첫 공시, 내용은 마지막 정정
        latest[kind] = (first, r['rcept_no'], api)
    return {k: v for k, v in latest.items() if k not in cancelled}


def shape(kind, decided, d, asof):
    """사건 한 건 — 가격 기준이 바뀌는 날(`c`)과 진행 끝(`e`), 신호일 기준 표시.

    무상 · 유무상증자 · 주주배정 유상증자는 권리락(기준일 전 거래일)에, 분할 · 병합 · 감자는 재상장일에
    가격 기준이 바뀐다.
        w  신호일이 그날이거나 그 다음 거래일 — 그날 신호는 가격 기준 변화 탓일 수 있다
        n  결정 공시가 `NEW_DAYS`일 안에 나왔다
        s  다음 거래일에 벌어지는 일 (권리락 · 매매정지 시작 · 재상장)"""
    base, listing = d.get('base'), d.get('listing')
    rights = kind in ('무상증자', '유무상증자') or (kind == '유상증자' and '주주배정' in (d.get('method') or ''))
    change = previous_session(base) if rights and base else (listing if kind in ('감자', '주식분할', '주식병합') else None)
    known = [x for x in (base, listing, d.get('halt_to')) if x]
    end = max(known) + timedelta(days=1) if known else decided + timedelta(days=FALLBACK)
    tomorrow = next_session(asof)
    soon = [label for label, x in (('권리락', change if '증자' in kind else None),
                                   ('매매정지 시작', d.get('halt_from')),
                                   ('재상장', change if kind in ('감자', '주식분할', '주식병합') else None))
            if x == tomorrow]
    iso = lambda x: x.isoformat() if x else None
    out = dict(k=kind, d=iso(decided), r=d.get('ratio'), m=d.get('method'), b=iso(base), c=iso(change),
               hf=iso(d.get('halt_from')), ht=iso(d.get('halt_to')), l=iso(listing), e=iso(end))
    if change and asof in (change, next_session(change)):
        out['w'] = 1
    if 0 <= (asof - decided).days <= NEW_DAYS:
        out['n'] = 1
    if soon:
        out['s'] = soon
    return {k: v for k, v in out.items() if v not in (None, '', '-')}


def listing_rows(today):
    """최근 `LOOKBACK`일의 주요사항보고 · 거래소 수시공시 중 기업행위 제목만 (회사 구분 없이).
    첫 쪽으로 쪽수를 알고 나머지 쪽은 나눠 받는다."""
    queries, end = [], today
    start = today - timedelta(days=LOOKBACK)
    while end > start:
        bgn = max(start, end - timedelta(days=WINDOW - 1))
        for ty in (dict(pblntf_ty='B'), dict(pblntf_detail_ty='I001')):
            queries.append(dict(bgn_de=bgn.strftime('%Y%m%d'), end_de=end.strftime('%Y%m%d'), page_count=100, **ty))
        end = bgn - timedelta(days=1)
    keep = lambda j: [r for r in j.get('list', []) if r.get('stock_code') and kind_of(r.get('report_nm', ''))]
    rows, rest = [], []
    for q in queries:
        j = _get('list.json', page_no=1, **q)
        rows += keep(j)
        rest += [dict(q, page_no=p) for p in range(2, int(j.get('total_page') or 1) + 1)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for got in pool.map(lambda q: keep(_get('list.json', **q)), rest):
            rows += got
    return rows


def fetch_rows(today=None, log=print):
    """공시 목록 — 키가 없거나 실패하면 None. 스캔이 일봉을 받는 동안 따로 돌린다."""
    if not key():
        log('  기업행위: DART_API_KEY 없음 - 건너뜀')
        return None
    started = time.time()
    try:
        rows = listing_rows(today or date.today())
    except Exception as exc:
        log(f'  기업행위: 공시 목록 실패 - {safe(exc)[:160]}')
        return None
    log(f'  기업행위: 공시 목록 {len(rows)}건 · {time.time() - started:.0f}초')
    return rows


def events(codes, asof, rows, log=print):
    """{종목코드: [사건]} — 진행이 안 끝난(끝 ≥ 신호일) 것만. `rows`가 없으면 {}."""
    if not rows:
        return {}
    started = time.time()
    codes = set(codes)
    by_corp = {}
    for r in rows:
        if r['stock_code'] in codes:
            by_corp.setdefault((r['stock_code'], r['corp_code']), []).append(r)
    jobs = [(code, corp, kind, v) for (code, corp), rs in by_corp.items() for kind, v in pick(rs).items()]

    def one(job):
        code, corp, kind, (first, rcept_no, api) = job
        decided = date(int(first[:4]), int(first[4:6]), int(first[6:]))
        try:
            d = details(api, corp, rcept_no, decided)
        except Quota:
            raise
        except Exception:
            d = {}
        return code, shape(kind, decided, d, asof)

    out = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        try:
            for code, e in pool.map(one, jobs):
                if (e.get('e') or '') >= asof.isoformat():
                    out.setdefault(code, []).append(e)
        except Quota as exc:
            log(f'  기업행위: DART 하루 한도 - {safe(exc)}')
    log(f'  기업행위: 사건 {len(jobs)}건 · 진행 중 {sum(map(len, out.values()))}건 '
        f'({len(out)}종목) · 상세 {time.time() - started:.0f}초')
    return out
