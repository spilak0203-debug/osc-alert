"""Pre-market briefing (`news.py`): reading feeds, which articles count, the Claude round trip and
what reaches the app. No network — feeds and Claude's answers are written out here."""
import contextlib
import sys
import unittest
from datetime import date, datetime
from pathlib import Path
from types import SimpleNamespace
from zoneinfo import ZoneInfo

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'signal'))
import news  # noqa: E402

SEOUL = ZoneInfo('Asia/Seoul')

RSS = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>경제</title>
<item><title><![CDATA[뉴욕증시, 반도체 강세에 나스닥 1% 상승]]></title>
 <link>https://www.yna.co.kr/view/AKR1</link>
 <description><![CDATA[<p>엔비디아가 3% 오르며 &amp; 기술주를 끌어올렸다.</p>]]></description>
 <pubDate>Sun, 11 Oct 2026 21:10:00 +0000</pubDate></item>
<item><title>지난주 기사</title><link>https://www.yna.co.kr/view/AKR0</link>
 <pubDate>Mon, 05 Oct 2026 01:00:00 +0000</pubDate></item>
<item><title>링크 없는 기사</title></item>
</channel></rss>'''.encode()

GOOGLE = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
<item><title>뉴욕증시, 반도체 강세에 나스닥 1% 상승 - 연합뉴스</title>
 <link>https://news.google.com/rss/articles/abc</link>
 <description>&lt;a href="https://x"&gt;뉴욕증시, 반도체 강세에 나스닥 1% 상승&lt;/a&gt;</description>
 <pubDate>Sun, 11 Oct 2026 21:12:00 GMT</pubDate>
 <source url="https://www.yna.co.kr">연합뉴스</source></item>
<item><title>원·달러 환율 1,380원대 - 머니투데이</title>
 <link>https://news.google.com/rss/articles/def</link>
 <pubDate>Sun, 11 Oct 2026 22:30:00 GMT</pubDate>
 <source url="https://news.mt.co.kr">머니투데이</source></item>
</channel></rss>'''.encode()

ATOM = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"><title>증권</title>
<entry><title>코스피 외국인 순매수 전환</title><link href="https://example.com/a"/>
 <summary>외국인이 사흘 만에 샀다</summary><updated>2026-10-12T06:30:00+09:00</updated></entry>
</feed>'''.encode()


class Feeds(unittest.TestCase):
    def test_rss(self):
        got = news.parse_feed(RSS, '연합뉴스')
        self.assertEqual(len(got), 2)                       # the one without a link is dropped
        a = got[0]
        self.assertEqual(a['title'], '뉴욕증시, 반도체 강세에 나스닥 1% 상승')
        self.assertEqual(a['summary'], '엔비디아가 3% 오르며 & 기술주를 끌어올렸다.')
        self.assertEqual(a['at'], datetime(2026, 10, 12, 6, 10, tzinfo=SEOUL))
        self.assertEqual(a['press'], '연합뉴스')

    def test_google_news_names_the_press(self):
        got = news.parse_feed(GOOGLE, '구글 뉴스')
        self.assertEqual([(a['title'], a['press']) for a in got],
                         [('뉴욕증시, 반도체 강세에 나스닥 1% 상승', '연합뉴스'), ('원·달러 환율 1,380원대', '머니투데이')])
        self.assertEqual(got[0]['summary'], '')             # only repeats the title

    def test_atom_and_broken(self):
        got = news.parse_feed(ATOM, '어딘가')
        self.assertEqual((got[0]['url'], got[0]['summary']), ('https://example.com/a', '외국인이 사흘 만에 샀다'))
        self.assertEqual(news.parse_feed(b'<html>not a feed', 'x'), [])

    def test_collect_keeps_recent_once_and_survives_a_failed_feed(self):
        pages = {'rss': RSS, 'google': GOOGLE, 'atom': ATOM}

        def get(url):
            if url == 'down':
                raise OSError('timeout')
            return pages[url]

        logs = []
        now = datetime(2026, 10, 12, 7, 30, tzinfo=SEOUL)
        got = news.collect(news.since(date(2026, 10, 12)), now, get=get, log=logs.append,
                           feeds=[('연합뉴스', 'rss'), ('x', 'down'), ('구글 뉴스', 'google'), ('어딘가', 'atom')])
        # The weekly-old article is out, the same story from Google is out, newest first.
        self.assertEqual([a['title'] for a in got],
                         ['원·달러 환율 1,380원대', '코스피 외국인 순매수 전환', '뉴욕증시, 반도체 강세에 나스닥 1% 상승'])
        self.assertTrue(any('::warning::' in m and 'down' in m for m in logs))


class Days(unittest.TestCase):
    def test_briefing_day(self):
        at = lambda *a: datetime(*a, tzinfo=SEOUL)
        self.assertEqual(news.briefing_day(at(2026, 10, 12, 7, 20)), date(2026, 10, 12))
        self.assertEqual(news.briefing_day(at(2026, 10, 9, 7, 20)), date(2026, 10, 12))   # 한글날 → 월요일
        self.assertEqual(news.briefing_day(at(2026, 10, 8, 16, 0)), date(2026, 10, 12))   # 장 마감 뒤
        self.assertEqual(news.briefing_day(at(2026, 10, 10, 9, 0)), date(2026, 10, 12))   # 토요일

    def test_since_the_previous_close(self):
        # Monday after the Hangul Day holiday: from Thursday's close, so the long weekend counts.
        self.assertEqual(news.since(date(2026, 10, 12)), datetime(2026, 10, 8, 14, 30, tzinfo=SEOUL))

    def test_prompt(self):
        a = dict(title='제목', url='https://u', press='연합뉴스', summary='요약',
                 at=datetime(2026, 10, 12, 6, 10, tzinfo=SEOUL))
        text = news.prompt([a], date(2026, 10, 12), datetime(2026, 10, 12, 7, 31, tzinfo=SEOUL))
        self.assertIn('오늘은 2026-10-12 (월), 직전 거래일은 2026-10-08 (목)', text)
        self.assertIn('[1] 10-12 06:10 · 연합뉴스 · 제목\n    요약', text)


ARTICLES = [dict(title=f'기사{n}', url=f'https://news/{n}', press='연합뉴스', summary='', at=None) for n in range(1, 4)]

SEARCH = [
    dict(type='server_tool_use', id='s1', name='web_search', input=dict(query='뉴욕증시 마감 https://made.up/q')),
    dict(type='web_search_tool_result', tool_use_id='s1', content=[
        dict(type='web_search_result', url='https://www.reuters.com/markets/us/', title='Wall St closes higher',
             encrypted_content='x', page_age=None)]),
    dict(type='text', text='https://invented.example/ 이라고 썼다', citations=[
        dict(type='web_search_result_location', url='https://cnbc.com/x', title='CNBC', cited_text='…')]),
]

ANSWER = dict(
    headline='반도체 강세 이어질까',
    key=['나스닥 1% 상승', '환율 1,380원대', '외국인 순매수'],
    sections=[
        dict(title='간밤 해외 시장', items=[
            dict(text='나스닥이 1% 올랐다.', articles=[1, 1, 9], urls=['https://www.reuters.com/markets/us']),
            dict(text='지어낸 출처', articles=[], urls=['https://invented.example', 'https://made.up/q']),
            dict(text='   ', articles=[2], urls=[]),
        ]),
        dict(title='국내 이슈', items=[dict(text='외국인이 샀다.', articles=[3, 1], urls=['https://cnbc.com/x'])]),
        dict(title='빈 분야', items=[]),
    ],
    stocks=[dict(name='삼성전자', note='HBM 기대'), dict(name=' ', note='이름 없음')],
)


class Message:
    """What the SDK's `get_final_message()` returns, as much as `ask` reads."""
    def __init__(self, stop, content, model='claude-opus-5-5'):
        self.content = content
        self._d = dict(stop_reason=stop, content=content, model=model,
                       usage=dict(input_tokens=1000, output_tokens=200, server_tool_use=dict(web_search_requests=1)))

    def to_dict(self):
        return self._d


class Messages:
    """`client.beta.messages`: hands out the scripted messages in order and keeps every request."""
    def __init__(self, *messages):
        self.queue, self.requests = list(messages), []

    @contextlib.contextmanager
    def stream(self, **kw):
        self.requests.append(kw)
        yield SimpleNamespace(get_final_message=lambda msg=self.queue.pop(0): msg)


class FakeAnthropic:
    def __init__(self, *messages):
        self.calls = Messages(*messages)
        self.beta = SimpleNamespace(messages=self.calls)


def publish(answer=ANSWER):
    return dict(type='tool_use', id='t1', name='publish_briefing', input=answer)


class Claude(unittest.TestCase):
    def test_search_then_publish(self):
        fake = FakeAnthropic(Message('pause_turn', SEARCH), Message('tool_use', [publish()]))
        raw, found, usage, served = news.ask(fake, 'claude-opus-5-5', '브리핑', log=lambda m: None)
        self.assertEqual(raw, ANSWER)
        self.assertEqual(served, 'claude-opus-5-5')
        self.assertEqual(len(usage), 2)
        req = fake.calls.requests
        self.assertEqual(req[0]['betas'], [news.FALLBACK_BETA])
        self.assertEqual(req[0]['fallbacks'], 'default')
        self.assertEqual([t['name'] for t in req[0]['tools']], ['web_search', 'publish_briefing'])
        self.assertTrue(req[0]['tools'][1]['strict'])
        # A paused turn goes back as is, with no new user message.
        self.assertEqual(req[1]['messages'][-1], {'role': 'assistant', 'content': SEARCH})
        # Only what the search returned counts as a source; queries and Claude's own text do not.
        self.assertEqual(found, {'https://www.reuters.com/markets/us': 'Wall St closes higher', 'https://cnbc.com/x': 'CNBC'})

    def test_asks_again_when_it_forgets_the_tool(self):
        fake = FakeAnthropic(Message('end_turn', [dict(type='text', text='브리핑입니다', citations=None)]),
                             Message('tool_use', [publish()], model='claude-opus-5'))
        logs = []
        _, _, _, served = news.ask(fake, 'claude-opus-5-5', '브리핑', log=logs.append)
        self.assertEqual(fake.calls.requests[1]['messages'][-1]['role'], 'user')
        self.assertEqual(served, 'claude-opus-5')
        self.assertTrue(logs)

    def test_refusal_and_giving_up(self):
        with self.assertRaises(RuntimeError):
            news.ask(FakeAnthropic(Message('refusal', [])), 'm', 'x')
        with self.assertRaises(RuntimeError):
            news.ask(FakeAnthropic(*[Message('end_turn', [])] * news.TURNS), 'm', 'x')


class Shape(unittest.TestCase):
    def test_sources_are_checked_and_shared(self):
        found = news.found_urls(SEARCH)
        now = datetime(2026, 10, 12, 7, 41, tzinfo=SEOUL)
        b = news.shape(ANSWER, ARTICLES, found, date(2026, 10, 12), 'claude-opus-5-5', now)
        self.assertEqual((b['date'], b['generated'], b['articles']), ('2026-10-12', '2026-10-11T22:41:00+00:00', 3))
        self.assertEqual([s['title'] for s in b['sections']], ['간밤 해외 시장', '국내 이슈'])
        first, invented = b['sections'][0]['items']
        self.assertEqual(first['src'], [0, 1])               # article 1 once, 9 does not exist, reuters
        self.assertEqual(invented['src'], [])                # neither address came from a search
        self.assertEqual(b['sources'][1], dict(title='Wall St closes higher', press='reuters.com',
                                               url='https://www.reuters.com/markets/us'))
        # Article 1 is listed once and shared by both sections.
        self.assertEqual(b['sections'][1]['items'][0]['src'], [2, 0, 3])
        self.assertEqual(b['stocks'], [dict(name='삼성전자', note='HBM 기대')])
        self.assertEqual(len(b['key']), 3)
        self.assertIn('■ 간밤 해외 시장', news.render(b))

    def test_spent(self):
        t = news.spent([dict(input_tokens=10, output_tokens=2, server_tool_use=dict(web_search_requests=3)), {}])
        self.assertEqual(t, dict(input=10, output=2, cache=0, searches=3))


if __name__ == '__main__':
    unittest.main()
