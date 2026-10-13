#!/usr/bin/env python3
"""Builds Resources/AppIcon.icns from a supplied image (white background and shadow are cut out).
Usage: make_icon_from_image.py <image.jpg|png>
Note: a user-supplied icon is NOT covered by the project's GPL (see README, License & legal)."""
import os, subprocess, sys
import numpy as np
from PIL import Image, ImageFilter, ImageDraw
src = Image.open(sys.argv[1]).convert('RGB')
a = np.asarray(src).astype(int); sat = a.max(axis=2) - a.min(axis=2)
mask = ((sat > 14) | (a.max(axis=2) < 120)).astype(np.uint8) * 255
m = Image.fromarray(mask).filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))
inv = m.copy(); ImageDraw.floodfill(inv, (0, 0), 128)
m = Image.fromarray(np.where(np.asarray(inv) == 128, 0, 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.6))
rgba = src.convert('RGBA'); rgba.putalpha(m)
icon = rgba.crop(m.point(lambda v: 255 if v > 40 else 0).getbbox())
S = 1024; k = int(S * 0.84) / max(icon.size)
icon = icon.resize((int(icon.width * k), int(icon.height * k)), Image.LANCZOS)
out = Image.new('RGBA', (S, S), (0, 0, 0, 0)); out.paste(icon, ((S - icon.width) // 2, (S - icon.height) // 2), icon)
tmp = '/tmp/mlf-icon2.iconset'; os.makedirs(tmp, exist_ok=True)
for sz in (16, 32, 64, 128, 256, 512, 1024):
    out.resize((sz, sz), Image.LANCZOS).save(f'{tmp}/icon_{sz}x{sz}.png')
    if sz <= 512: out.resize((sz * 2, sz * 2), Image.LANCZOS).save(f'{tmp}/icon_{sz}x{sz}@2x.png')
here = os.path.dirname(os.path.abspath(__file__))
subprocess.run(['iconutil', '-c', 'icns', tmp, '-o', os.path.join(here, '..', 'Resources', 'AppIcon.icns')], check=True)
print('ok')
