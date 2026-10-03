"""Corporate actions (`corporate.py`): titles, corrections, dates read from a filing, and what the
app is told on a signal day. No network — DART answers are written out here."""
import sys
import unittest
from datetime import date
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'signal'))
import corporate as corp  # noqa: E402


def row(no, dt, name, code='000001', corp_code='00100001'):
    return dict(rcept_no=no, rcept_dt=dt, report_nm=name, stock_code=code, corp_code=corp_code)


class Titles(unittest.TestCase):
    def test_kinds(self):
        self.assertEqual(corp.kind_of('주요사항보고서(무상증자결정)')[:2], ('무상증자', 'fricDecsn'))
        self.assertEqual(corp.kind_of('[기재정정]주요사항보고서(유무상증자결정)')[0], '유무상증자')
        self.assertEqual(corp.kind_of('주식분할결정')[0], '주식분할')
        self.assertEqual(corp.kind_of('주요사항보고서(감자결정)')[0], '감자')
        self.assertTrue(corp.kind_of('유상증자결정(취소)')[2])
        self.assertIsNone(corp.kind_of('유상증자결정(자회사의 주요경영사항)'))
        self.assertIsNone(corp.kind_of('유상증자 결과'))
        self.assertIsNone(corp.kind_of('자기주식취득결정'))

    def test_corrections_keep_the_first_date_and_the_last_filing(self):
        got = corp.pick([
            row('20260901000100', '20260901', '주요사항보고서(무상증자결정)'),
            row('20260905000200', '20260905', '[기재정정]주요사항보고서(무상증자결정)'),
            row('20260910000300', '20260910', '주요사항보고서(유상증자결정)'),
            row('20260912000400', '20260912', '유상증자결정(철회)'),
        ])
        self.assertEqual(got, {'무상증자': ('20260901', '20260905000200', 'fricDecsn')})


class Dates(unittest.TestCase):
    def test_sessions_skip_weekends_and_holidays(self):
        self.assertEqual(corp.next_session(date(2026, 10, 2)), date(2026, 10, 6))      # 10/5 대체공휴일
        self.assertEqual(corp.previous_session(date(2026, 10, 12)), date(2026, 10, 8))  # 10/9 한글날

    def test_reads_a_filing(self):
        text = ('1.신주의종류와수 보통주식(주)1,000,000 … 신주배정기준일2026년10월14일 … '
                '매매거래정지예정기간 2026.10.13 ~ 2026.10.30 … 신주의상장예정일2026-11-02 증자방식 주주배정후실권주일반공모')
        d = corp.parse_document(text.replace(' ', ''))
        self.assertEqual(d['base'], date(2026, 10, 14))
        self.assertEqual((d['halt_from'], d['halt_to']), (date(2026, 10, 13), date(2026, 10, 30)))
        self.assertEqual(d['listing'], date(2026, 11, 2))
        self.assertIn('주주배정', d['method'])


class Shape(unittest.TestCase):
    def test_bonus_issue(self):
        # 기준일 10/14 → 권리락은 그 전 거래일 10/13.
        d = dict(base=date(2026, 10, 14), listing=date(2026, 11, 5), ratio='0.5')
        e = corp.shape('무상증자', date(2026, 9, 30), d, asof=date(2026, 10, 2))
        self.assertEqual((e['c'], e['e'], e['r']), ('2026-10-13', '2026-11-06', '0.5'))
        self.assertNotIn('w', e)
        self.assertNotIn('s', e)
        self.assertEqual(e['n'], 1)                               # 결정 뒤 3일 안
        # 신호일이 권리락 전날: 다음 거래일 권리락.
        self.assertEqual(corp.shape('무상증자', date(2026, 9, 30), d, asof=date(2026, 10, 12))['s'], ['권리락'])
        # 권리락 당일과 다음 거래일의 신호는 영향 표시.
        self.assertEqual(corp.shape('무상증자', date(2026, 9, 30), d, asof=date(2026, 10, 13))['w'], 1)
        self.assertEqual(corp.shape('무상증자', date(2026, 9, 30), d, asof=date(2026, 10, 14))['w'], 1)
        self.assertNotIn('w', corp.shape('무상증자', date(2026, 9, 30), d, asof=date(2026, 10, 15)))

    def test_split_changes_on_relisting(self):
        d = dict(halt_from=date(2026, 10, 6), halt_to=date(2026, 10, 20), listing=date(2026, 10, 21))
        e = corp.shape('주식분할', date(2026, 9, 1), d, asof=date(2026, 10, 2))
        self.assertEqual(e['c'], '2026-10-21')
        self.assertEqual(e['s'], ['매매정지 시작'])                # 10/2 다음 거래일이 10/6
        self.assertNotIn('n', e)

    def test_third_party_offering_moves_no_price_basis(self):
        d = dict(listing=date(2026, 11, 1), method='제3자배정')
        e = corp.shape('유상증자', date(2026, 9, 25), d, asof=date(2026, 10, 2))
        self.assertNotIn('c', e)
        self.assertNotIn('w', e)

    def test_unknown_dates_run_for_a_while(self):
        e = corp.shape('유상증자', date(2026, 9, 1), {}, asof=date(2026, 10, 2))
        self.assertEqual(e['e'], '2026-11-30')


class Events(unittest.TestCase):
    def test_only_our_stocks_and_ongoing_ones(self):
        rows = [row('20260901000100', '20260901', '주요사항보고서(무상증자결정)'),
                row('20260601000100', '20260601', '주요사항보고서(감자결정)', code='000002', corp_code='00100002'),
                row('20260902000100', '20260902', '주식분할결정', code='999999', corp_code='00999999')]
        found = {'fricDecsn': dict(base=date(2026, 10, 14), listing=date(2026, 11, 5)),
                 'crDecsn': dict(base=date(2026, 7, 1), listing=date(2026, 7, 20))}
        with mock.patch.object(corp, 'details', lambda api, c, no, dec: found[api]):
            got = corp.events(['000001', '000002'], date(2026, 10, 2), rows, log=lambda *_: None)
        self.assertEqual(list(got), ['000001'])                   # 감자는 끝났고, 999999는 대상 밖
        self.assertEqual(got['000001'][0]['k'], '무상증자')

    def test_no_rows_no_events(self):
        self.assertEqual(corp.events(['000001'], date(2026, 10, 2), None), {})
        with mock.patch.dict('os.environ', {'DART_API_KEY': ''}):
            self.assertIsNone(corp.fetch_rows(log=lambda *_: None))


if __name__ == '__main__':
    unittest.main()
