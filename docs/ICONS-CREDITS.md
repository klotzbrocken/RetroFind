# Artwork origin

All artwork except the app icon is original and covered by the GPL-3.0 of this project:

- **Sidebar, toolbar and file-type glyphs** – vector drawings in `Sources/MLFinder/Glyphs.swift`.
- **Folder icon** – drawn in `FolderArt` (`Glyphs.swift`).
- **Traffic lights (Aqua option)** – drawn in `Lights` (`Glyphs.swift`).
- **App icon** – `Resources/AppIcon.icns` is a user-supplied, AI-generated image (cut out by `Reference/make_icon_from_image.py`), **not** GPL-covered, all rights reserved by the author; it resembles the former Apple Finder icon. `Reference/make_icon.py` draws an original, GPL-covered alternative icon (window with sidebar and folder).

No third-party icon sets, Apple artwork or reference-screenshot cut-outs are bundled with the app or stored in this repository.
(Earlier internal builds contained such material; it was removed for release 1.1.)

## User-supplied icons
Preferences ▸ **Custom Icons** lets every user replace sidebar icons with their own PNGs (transparent, exactly 64 × 64 px).
They are stored locally in `~/Library/Application Support/RetroFind/CustomIcons/` and never leave the machine.
Make sure you have the rights to any artwork you import.
