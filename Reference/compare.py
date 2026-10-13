#!/usr/bin/env python3
"""Referenz (1×, Nik Rawlinson 1024×768, Fenster bei 139,128, 770×463) | App | Differenz → /tmp/mlf/cmp.png.
Aufruf: compare.py app.png [x0 y0 x1 y1 zoom]"""
import sys, numpy as np
from PIL import Image, ImageChops
ref = Image.open('/tmp/fx/a.png').convert('RGB').crop((139, 128, 909, 591))
app = Image.open(sys.argv[1]).convert('RGB')
box = tuple(int(v) for v in sys.argv[2:6]) if len(sys.argv) > 5 else (0, 0, 770, 463)
z = int(sys.argv[6]) if len(sys.argv) > 6 else 1
r, a = ref.crop(box), app.crop(box)
d = ImageChops.difference(r, a)
n = np.asarray(d).max(axis=2); print('>12/255: %.1f%%  mittl. Abw. %.1f' % ((n > 12).mean() * 100, n.mean()))
W, H = r.size; out = Image.new('RGB', (W * z, H * z * 3 + 8))
for i, im in enumerate((r, a, d.point(lambda v: min(255, v * 4)))): out.paste(im.resize((W * z, H * z), Image.NEAREST), (0, i * (H * z + 4)))
out.save('/tmp/mlf/cmp.png')
