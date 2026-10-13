# Measurement catalog (V-10)

Source: **R1** = “Nik Rawlinson” screenshot (1024×768, 1×, window 770×463 at 139,128), **R2** = “Finder Home” (2070×1432, 2×, cross-check), **R3** = AppleInsider screenshots (691×430, 1×), **R4** = label screenshots (labels, search bar).
All dimensions in points at 1×, origin at the top left of the window. Defined centrally in `Sources/MLFinder/Theme.swift` (`enum M`, `enum C`, `enum Draw`).
Confidence: **measured** (pixel profile), **derived** (from row profile/proportion), **open** (estimate, to be checked against an original installation – specification M1).

| Component | Value | Source | Confidence |
|---|---|---|---|
| Default window size | 770 × 463 | R1 | measured (reference window; original default may differ) |
| Title bar + toolbar | 55 pt (rows 0–53 gradient, row 54 line, gray 106) | R1 | measured |
| Traffic lights | **System traffic lights** by default (client request), optional **Aqua Glow**; original reference size: Ø 12, spacing 20, centers x = 14 / 34 / 54, y = 11.5 | R1, R3 | measured |
| Active title gradient | 241 (highlight edge) → 233 → 222 → 211 → 199 → 189 → 179 | R1 column profile | measured |
| Title | Lucida Grande 13, gray 51, white shadow, 16 pt proxy icon on the left | R1 | measured/derived |
| Navigation group | x 8.5, 52 × 21, y 24 | R1 | measured |
| View group | x 141.5, 111 × 21 (4 segments), selected = dark gradient 104→146 | R1 | measured |
| Action / Arrange / Share | 40 × 21 each, spacing 8.5 (x 261 / 309 / 357) | R1 | measured |
| Search field | height 21, capsule, ≈ 36 % of window width, min 100, right margin 8.5 | R1, R2 | derived |
| Sidebar | 136 pt wide, separator gray 184 at x = 136, gradient (232,236,242) → (209,216,224) over 378 pt | R1 | measured |
| Sidebar row | 24 pt, icon 16 at x = 18, text at x = 42, selection blue (113,185,234) → (53,135,210), edge lines (92,164,223)/(50,122,194) | R1 | measured |
| Group heading | 22 pt, Lucida Grande Bold 11, (112,126,140), x = 9, 6 pt spacing between groups | R1 | measured |
| Status bar | 23 pt (line gray 130 + 22), gradient 225 → 177, text 11 pt centered | R1 | measured |
| Zoom slider | track 77 × 4 at x = width − 101, knob Ø 11 | R1 | derived |
| “All My Files” | group header 19 pt, title 11 pt bold (117,129,148), line gray 209, grid width 142, “Show All (n)” on the right | R1, R3 | measured/derived |
| Icon view | icon 64 (folder fills 124 × 92 of the 128 area, ratio 1.34 : 1 per R2), grid = icon + 40, names 13 pt, max. 2 lines (second truncated in the middle), selection: gray rectangle r = 5 + blue name capsule r = 8 | R1–R4 | derived |
| Label capsules | fill colors see `C.labelPill` (e.g. green 221,236,169), list view colors the whole row | R2, R4 | measured (green), others derived |
| List view | row height 17 (small) / 34 (large), header 17 pt, stripes (243,246,250) | R4 | derived |
| Column view | column width 186, row 18, resize handle bottom right | – | **open** |
| Minimum size | 380 × 200 (toolbar overflows into the » menu below 506 pt) | – | **open** (check item §2.3) |
| Window corners | top r = 5, bottom r = 4 | R1 corner profile | measured |

## Comparison tool

```bash
build/RetroFind.app/Contents/MacOS/RetroFind -fresh -lang=en -status -open=allfiles -snap=/tmp/mlf/a.png -quit
python3 Reference/compare.py /tmp/mlf/a.png 0 0 300 60 4     # reference | app | difference (×4)
```
(`/tmp/fx/a.png` = R1 as PNG; `Reference/compare.py` crops the window at 139,128.)

Geometry (lines, groups, separators, margins) matches R1 on the pixel grid; remaining differences are font rasterization, icon content (host icons), traffic-light gloss and gradient noise.

**Font sizes (after the feedback “everything a bit small”):** sidebar 13 pt, icon labels 13 pt, list 12 pt (row 19), columns 13 pt (row 20), status bar 12 pt – deliberately about +1 pt versus the 1× reference, following the default Finder.
