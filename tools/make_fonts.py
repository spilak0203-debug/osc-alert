"""Builds the bundled Noto Sans KR fonts in android/app/src/main/res/font.

    pip install fonttools requests
    python tools/make_fonts.py

Downloads Regular/Medium/Bold from Google Fonts (SIL Open Font License), keeps KS X 1001
hangul (2,350 syllables), jamo, Latin and the symbols the app draws — other characters fall
back to the system font — and tightens the vertical metrics. The full font declares a bounding
box of -1048..1808 units, which Android turns into almost three lines of padding per line of
text; 1000/-250 fits hangul (880/-120) with room for accents.
"""
import io
import pathlib
import re

import requests
from fontTools import subset
from fontTools.ttLib import TTFont

OUT = pathlib.Path(__file__).resolve().parents[1] / 'android/app/src/main/res/font'
CSS = 'https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;500;700'
NAMES = {'400': 'noto_sans_kr_regular', '500': 'noto_sans_kr_medium', '700': 'noto_sans_kr_bold'}


def codepoints():
    codes = set(range(0x20, 0x7F)) | set(range(0xA0, 0x100))
    codes |= set(range(0x2010, 0x2060)) | set(range(0x2190, 0x2200)) | {0x2212}
    codes |= set(range(0x25A0, 0x2600)) | set(range(0x3000, 0x3040)) | set(range(0x3131, 0x318F))
    codes |= {0x20A9, 0xFF05, 0xFF08, 0xFF09, 0xFF0C, 0xFF0E}
    for cp in range(0xAC00, 0xD7A4):
        try:
            chr(cp).encode('euc-kr')          # KS X 1001 syllables only
            codes.add(cp)
        except UnicodeEncodeError:
            pass
    return codes


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # A plain user agent makes Google Fonts answer with whole TTF files instead of woff2 slices.
    css = requests.get(CSS, headers={'User-Agent': 'curl/8'}, timeout=30).text
    urls = dict(re.findall(r'font-weight: (\d+);\s*src: url\((\S+?\.ttf)\)', css))
    codes = codepoints()
    for weight, name in NAMES.items():
        raw = requests.get(urls[weight], timeout=120).content
        opts = subset.Options()
        opts.layout_features = ['*']
        opts.name_IDs = ['*']
        opts.notdef_outline = True
        font = TTFont(io.BytesIO(raw))
        s = subset.Subsetter(opts)
        s.populate(unicodes=codes)
        s.subset(font)
        font.recalcBBoxes = False
        font['head'].yMax, font['head'].yMin = 1000, -250
        font['hhea'].ascent, font['hhea'].descent, font['hhea'].lineGap = 1000, -250, 0
        font['OS/2'].usWinAscent, font['OS/2'].usWinDescent = 1000, 250
        path = OUT / f'{name}.ttf'
        font.save(str(path))
        print(path, path.stat().st_size)


if __name__ == '__main__':
    main()
