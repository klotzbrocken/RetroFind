#!/usr/bin/env python3
"""Erzeugt synthetische Demo-Daten (/tmp/mlf-demo) für Screenshots: Ordner, Bilder (generierte Farbverläufe), Textdateien, Etiketten."""
import os, random, subprocess, shutil
from PIL import Image, ImageDraw, ImageFilter
R = '/tmp/mlf-demo'; shutil.rmtree(R, ignore_errors=True)
random.seed(7)
def d(p): os.makedirs(os.path.join(R, p), exist_ok=True)
def txt(p, s='Demo'): open(os.path.join(R, p), 'w').write(s + '\n')
for f in ['Projects/Atlas Launch', 'Projects/Harbor Redesign', 'Projects/Archive', 'Photos/Iceland', 'Photos/City', 'Invoices/2025', 'Invoices/2026', 'Music', 'Public', 'Backups']: d(f)
def pic(name, c1, c2, kind=0, size=(900, 600)):
    im = Image.new('RGB', size); px = im.load()
    for y in range(size[1]):
        t = y / size[1]
        for x in range(size[0]):
            s = x / size[0]; k = 0.65 * t + 0.35 * s
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * k) for i in range(3))
    dr = ImageDraw.Draw(im)
    if kind == 0: dr.ellipse((560, 80, 760, 280), fill=(255, 236, 170))           # Sonne
    if kind == 1:
        for i in range(5): dr.polygon([(i * 200 - 60, 600), (i * 200 + 60, 300 + (i % 2) * 80), (i * 200 + 190, 600)], fill=(40 + i * 12, 60 + i * 10, 90))
    if kind == 2:
        for i in range(9): dr.rectangle((40 + i * 95, 600 - random.randint(160, 420), 100 + i * 95, 600), fill=(30, 38, 58))
    im.filter(ImageFilter.GaussianBlur(0.6)).save(os.path.join(R, name))
pic('Photos/Sunset.jpg', (255, 142, 90), (60, 40, 110), 0); pic('Photos/Fjord.jpg', (110, 170, 220), (20, 60, 90), 1)
pic('Photos/Skyline.jpg', (250, 200, 130), (40, 50, 90), 2); pic('Photos/Meadow.jpg', (170, 220, 140), (30, 110, 70), 1)
pic('Photos/Glacier.jpg', (200, 230, 250), (70, 110, 160), 1); pic('Photos/Harbor.jpg', (255, 170, 120), (30, 80, 120), 2)
pic('Photos/Aurora.jpg', (60, 220, 170), (20, 20, 70), 1); pic('Photos/Dunes.jpg', (245, 205, 140), (150, 80, 50), 0)
for f in ['Photos/Iceland/ring-road.jpg', 'Photos/City/rooftops.jpg']: pic(f, (140, 180, 230), (30, 50, 90), 2, (600, 400))
for n in ['Notes.txt', 'Roadmap.txt', 'Meeting 2026-10-12.txt', 'Ideas.txt', 'Shopping list.txt', 'Release checklist.txt', 'Contacts export.csv', 'Budget.csv', 'Readme.md']: txt('Projects/' + n, n)
for n in ['Invoice 0412.txt', 'Invoice 0413.txt', 'Invoice 0414.txt', 'Receipt Hotel.txt']: txt('Invoices/2026/' + n, n)
subprocess.run(['dd', 'if=/dev/zero', f'of={R}/Backups/archive-2025.bin', 'bs=1m', 'count=6'], capture_output=True)
for n in ['Project Atlas.txt', 'Quarterly review.txt', 'Travel plan.txt', 'Recipes.txt', 'Passwords (not really).txt', 'Taxes 2025.txt']: txt(n, n)
subprocess.run(['ditto', '-c', '-k', '--keepParent', R + '/Projects/Archive', R + '/Backups/Archive.zip'], capture_output=True)
# Etiketten (Finder-Systemnummern: 6 rot, 7 orange, 5 gelb, 2 grün, 4 blau, 3 violett, 1 grau)
for name, n in [('Project Atlas.txt', 6), ('Quarterly review.txt', 7), ('Travel plan.txt', 5), ('Recipes.txt', 2), ('Taxes 2025.txt', 4), ('Passwords (not really).txt', 3)]:
    subprocess.run(['xattr', '-wx', 'com.apple.FinderInfo', bytes([0] * 9 + [n << 1] + [0] * 22).hex(), f'{R}/{name}'])
print('ok', R)
