"""Industries and themes (`sectors.py`): every page of every group, names stored once."""
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'signal'))
import sectors  # noqa: E402


class Fake:
    """Naver's lists: two themes, the second with 150 stocks over two pages."""
    def __init__(self):
        big = [dict(itemCode=f'{i:06d}') for i in range(150)]
        self.pages = {
            ('theme', None, 1): dict(groups=[dict(no=1, name='AI'), dict(no=2, name='2차전지')], totalCount=2),
            ('theme', 1, 1): dict(stocks=[dict(itemCode='000001'), dict(itemCode='000002')], totalCount=2),
            ('theme', 2, 1): dict(stocks=big[:100], totalCount=150),
            ('theme', 2, 2): dict(stocks=big[100:], totalCount=150),
        }

    def __call__(self, url):
        kind = 'theme'
        page = int(url.split('page=')[1].split('&')[0])
        tail = url.split(f'/{kind}')[1]
        no = int(tail[1:].split('?')[0]) if tail.startswith('/') else None
        data = self.pages[(kind, no, page)]
        return type('R', (), {'json': lambda self: data})()


class Groups(unittest.TestCase):
    def test_all_pages_and_several_themes(self):
        got = sectors.groups(Fake(), 'theme')
        self.assertEqual(got['000001'], ['AI', '2차전지'])
        self.assertEqual(got['000149'], ['2차전지'])
        self.assertEqual(len(got), 150)

    def test_table(self):
        names, idx = sectors.table({'A': ['반도체'], 'B': ['AI', '반도체']})
        self.assertEqual(names, ['AI', '반도체'])
        self.assertEqual(idx, {'A': [1], 'B': [0, 1]})


if __name__ == '__main__':
    unittest.main()
