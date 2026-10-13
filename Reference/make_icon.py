#!/usr/bin/env python3
"""Draws the original RetroFind app icon (a window with traffic lights, sidebar and a blue folder) → Resources/AppIcon.icns.
Own artwork, no third-party or Apple material."""
import os, subprocess
from PIL import Image, ImageDraw, ImageFilter
S = 1024
def grad(box, c0, c1, horizontal=False):
    x0, y0, x1, y1 = box; w, h = x1 - x0, y1 - y0
    g = Image.new('RGBA', (w, h))
    px = g.load()
    for y in range(h):
        for x in range(w):
            t = (x / max(1, w - 1)) if horizontal else (y / max(1, h - 1))
            px[x, y] = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3)) + (255,)
    return g
def rrmask(size, r, box=None):
    m = Image.new('L', size, 0); ImageDraw.Draw(m).rounded_rectangle(box or (0, 0, size[0] - 1, size[1] - 1), r, fill=255); return m
out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
body = (92, 84, 932, 920)
# shadow
sh = Image.new('RGBA', (S, S), (0, 0, 0, 0)); sh.paste((0, 0, 0, 150), mask=rrmask((S, S), 120, body)); sh = sh.filter(ImageFilter.GaussianBlur(26)); out.alpha_composite(sh, (0, 22))
win = Image.new('RGBA', (S, S), (0, 0, 0, 0))
win.alpha_composite(grad((0, 0, S, S), (240, 242, 246), (190, 196, 206)), (0, 0))
d = ImageDraw.Draw(win)
# title/toolbar band
band = grad((0, 0, S, 250), (246, 247, 249), (200, 204, 212)); win.alpha_composite(band, (0, body[1]))
d.rectangle((0, body[1] + 248, S, body[1] + 252), fill=(110, 116, 128))
for i, c in enumerate([(236, 84, 72), (246, 190, 60), (96, 200, 80)]):
    cx, cy = 190 + i * 88, body[1] + 96
    d.ellipse((cx - 32, cy - 32, cx + 32, cy + 32), fill=c, outline=tuple(int(v * .62) for v in c), width=6)
    d.ellipse((cx - 18, cy - 28, cx + 18, cy - 4), fill=(255, 255, 255, 110))
# toolbar buttons
for bx in (190, 360, 440, 520): d.rounded_rectangle((bx, body[1] + 150, bx + 56 if bx != 360 else bx + 56, body[1] + 214), 14, fill=(236, 238, 242), outline=(120, 126, 138), width=4)
# sidebar
sb = grad((body[0], body[1] + 252, body[0] + 280, body[3]), (226, 231, 240), (200, 208, 222)); win.alpha_composite(sb, (body[0], body[1] + 252))
d.rectangle((body[0] + 278, body[1] + 252, body[0] + 284, body[3]), fill=(150, 156, 168))
for i in range(5):
    y = body[1] + 300 + i * 92
    if i == 1: d.rectangle((body[0], y - 34, body[0] + 278, y + 40), fill=(70, 140, 214))
    d.rounded_rectangle((body[0] + 36, y - 14, body[0] + 82, y + 22), 8, fill=(255, 255, 255) if i == 1 else (120, 130, 148))
    d.rounded_rectangle((body[0] + 104, y - 8, body[0] + 190 + (i % 3) * 22, y + 16), 8, fill=(255, 255, 255) if i == 1 else (96, 104, 120))
# content area with folder
d.rectangle((body[0] + 284, body[1] + 252, body[2], body[3]), fill=(255, 255, 255))
fx0, fy0, fx1, fy1 = body[0] + 360, body[1] + 400, body[2] - 80, body[3] - 90
back = grad((fx0, fy0, fx1, fy1), (150, 186, 220), (118, 158, 204)); m = Image.new('L', (S, S), 0); md = ImageDraw.Draw(m)
md.rounded_rectangle((fx0, fy0 + 40, fx1, fy1), 26, fill=255); md.rounded_rectangle((fx0, fy0, fx0 + 170, fy0 + 90), 24, fill=255)
bk = Image.new('RGBA', (S, S), (0, 0, 0, 0)); bk.paste(grad((fx0, fy0, fx1, fy1), (150, 186, 220), (118, 158, 204)), (fx0, fy0)); win.paste(bk, (0, 0), m)
fm = Image.new('L', (S, S), 0); ImageDraw.Draw(fm).rounded_rectangle((fx0 - 10, fy0 + 90, fx1 + 10, fy1 + 4), 26, fill=255)
fr = Image.new('RGBA', (S, S), (0, 0, 0, 0)); fr.paste(grad((fx0 - 10, fy0 + 90, fx1 + 10, fy1 + 4), (190, 218, 242), (136, 176, 214)), (fx0 - 10, fy0 + 90)); win.paste(fr, (0, 0), fm)
ImageDraw.Draw(win).line((fx0 + 6, fy0 + 96, fx1 - 6, fy0 + 96), fill=(235, 246, 255), width=6)
out.paste(win, (0, 0), rrmask((S, S), 120, body))
ImageDraw.Draw(out).rounded_rectangle(body, 120, outline=(90, 96, 108), width=8)
here = os.path.dirname(os.path.abspath(__file__)); tmp = '/tmp/mlf-icon.iconset'; os.makedirs(tmp, exist_ok=True)
for sz in (16, 32, 64, 128, 256, 512, 1024):
    out.resize((sz, sz), Image.LANCZOS).save(f'{tmp}/icon_{sz}x{sz}.png')
    if sz <= 512: out.resize((sz * 2, sz * 2), Image.LANCZOS).save(f'{tmp}/icon_{sz}x{sz}@2x.png')
out.save('/tmp/mlf-icon-preview.png')
subprocess.run(['iconutil', '-c', 'icns', tmp, '-o', os.path.join(here, '..', 'Resources', 'AppIcon.icns')], check=True)
print('ok')
