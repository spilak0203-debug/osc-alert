"""Draws the app icon (app/android/app/src/main/res/drawable/ic_app.xml) as Windows .ico files.

    python tools/make_icons.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent / 'app'
SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]


def draw(px):
    s = 8  # supersample, then shrink for smooth edges
    n = px * s
    k = n / 48
    im = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, n - 1, n - 1], radius=8 * k, fill='#1F3A5F')
    w = max(1, round(3 * k))
    for color, pts in (('#E5484D', [(8, 34), (18, 22), (26, 28), (40, 12)]),
                       ('#FFFFFF', [(8, 14), (18, 26), (26, 20), (40, 36)])):
        xy = [(x * k, y * k) for x, y in pts]
        d.line(xy, fill=color, width=w, joint='curve')
        for x, y in (xy[0], xy[-1]):
            d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=color)
    return im.resize((px, px), Image.LANCZOS)


def main():
    big = draw(256)
    for out in (ROOT / 'assets/tray.ico', ROOT / 'windows/runner/resources/app_icon.ico'):
        out.parent.mkdir(parents=True, exist_ok=True)
        big.save(out, sizes=[(s, s) for s in SIZES], append_images=[draw(s) for s in SIZES])
        print('wrote', out)


if __name__ == '__main__':
    main()
