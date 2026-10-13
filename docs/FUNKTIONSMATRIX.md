# Function Matrix (requirements specification → implementation)

✅ implemented · 🟡 partial / with restrictions · ❌ deviation (see `ABWEICHUNGEN.md`)
Verification: **ST** = `-selftest` (file core, automated), **UT** = `-uitest` (UI paths without crashing), **SS** = screenshot comparison (`Reference/compare.py`), **M** = to be checked manually (no automated evidence).

## Design (V)
| ID | Status | Implementation | Verification |
|---|---|---|---|
| V-01 | ✅ | borderless window, custom frame, top r=5/bottom r=4, active/inactive | SS |
| V-02 | 🟡 | **System traffic lights** at the client's request (instead of a custom Ø12 drawing); states/hover are provided by macOS | M |
| V-03 | ✅ | toolbar gradients, embossed buttons, custom glyphs (no SF Symbols) | SS |
| V-04 | ✅ | Sidebar: groups, monochrome icons, selection, eject | SS |
| V-05 | 🟡 | Lucida Grande 11–13 pt, line wrapping max. 2 lines, middle truncation | SS |
| V-06 | ✅ | Selection ≠ label (gray icon + blue capsule vs. color capsule; list row) | SS |
| V-07 | 🟡 | Menus/popups/Info/Preferences in the style; system dialogs = host | M |
| V-08 | 🟡 | `scrollerStyle = .legacy`; behavior follows system setting | M |
| V-09 | 🟡 | Sidebar, folders, toolbar are custom drawings; file/app icons from the host; custom sidebar icons via "Custom Icons" | SS, ST |
| V-10 | ✅ | `docs/MESSKATALOG.md`, dimensions centralized in `Theme.swift` | ST (toolbar geometry) |

## Windows & Navigation (N)
| ID | Status | Implementation | Verification |
|---|---|---|---|
| N-01 | ✅ | multiple windows, minimize, zoom (ideal size), switch windows, bring all to front; edge dragging with minimum size | ST, UT |
| N-02 | ✅ | Preferences ▸ New windows show (All My Files, user folder, Computer, path) | M |
| N-03 | ✅ | Back/Forward per window | UT |
| N-04 | ✅ | double-click; ⌘ = new window; ⌥ = new window + close old one; "always new window" setting | M |
| N-05 | ✅ | Path bar: double-click navigates, drop on segments copies/moves | M |
| N-06 | ✅ | Proxy icon (draggable), ⌘-click path menu; vanished targets → nearest existing folder | M |
| N-07 | ✅ | Go to Folder with ~, relative paths, tab completion, error message | M |
| N-08 | ✅ | All destinations in the "Go" menu and sidebar | UT |
| N-09 | ✅ | Library only with ⌥ held in the "Go" menu | M |
| N-10 | ✅ | "Recent Folders" incl. clear list | M |
| N-11 | ✅ | Add favorites (drop), reorder, remove by dragging (puff of smoke), expand/collapse and reorder groups | M |
| N-12 | ✅ | Customize toolbar (selection, order, icon/text, default set), overflow menu | ST, UT |
| N-13 | ✅ | Show/hide toolbar, sidebar, path bar and status bar | UT |
| N-14 | 🟡 | Optional desktop (`Desktop.swift`), free positions, volumes per setting | M |
| N-15 | ✅ | Window frame, view options per folder, sidebar width, toolbar saved | ST |
| N-16 | ✅ | `DispatchSource` per folder + mount/unmount observation | M |

## Views (A)
| ID | Status | Implementation | Verification |
|---|---|---|---|
| A-01 | ✅ | Icon view: free grid, icon size 16–512, grid spacing, text size, label bottom/right, item info, preview | SS, UT |
| A-02 | ✅ | Background white/color/image | M |
| A-03 | ✅ | List: expandable folders, multiple selection, sortable/movable/resizable columns | SS, UT |
| A-04 | ✅ | Columns: Name, Date Modified, Date Created, Date Last Opened, Date Added, Size, Kind, Version, Comments, Label | UT |
| A-05 | ✅ | Column view with preview, adjustable width, arrow keys | SS, UT |
| A-06 | ✅ | Cover Flow (3D, reflection, slider, divider, synchronized list) | SS |
| A-07 | ✅ | View switching preserves target and selection | UT |
| A-08 | ✅ | Group (Arrange By), sort (column header), clean up (by …) kept separate | UT |
| A-09 | ✅ | Keys: Name, Kind, Date Last Opened, Date Added, Date Modified, Date Created, Size, Label, None; ascending/descending | UT |
| A-10 | ✅ | Options per folder, "always open in …", "browse in …", "Use as Defaults" | ST |
| A-11 | ✅ | readable sizes (base 10), relative dates, item count, free space | SS |
| A-12 | ✅ | "Calculate all sizes" in the background; **folder sizes on demand** (⌥⇧⌘S, context menu "Calculate Size"): recursive, parallel, cancelable (change of location), cached until the folder changes; sum of the selection in the status bar | ST, M |
| A-13 | ✅ | Thumbnails (QuickLookThumbnailing), fallback file icon | SS |

## File operations (F, §7.1)
| ID | Status | Implementation | Verification |
|---|---|---|---|
| F-01 | ✅ | Single/range/discontiguous selection, rectangle, Select All, name entry | M |
| F-02 | ✅ | Open: folders, documents, applications, aliases, packages, disk images | M |
| F-03 | ✅ | Open With (context + Info), "Change All …" | M |
| F-04 | ✅ | New Folder, New Folder with Selection, unique names, Undo | ST |
| F-05 | ✅ | Rename inline/Info, extension selected, invalid names, case-only changes, extension warning | ST |
| F-06 | ✅ | Copy/Paste, Move Item Here (⌥⌘V) | ST |
| F-07 | ✅ | Drag & drop between windows, sidebar, path bar, columns, list, desktop, other apps | M |
| F-08 | ✅ | same volume = move, otherwise copy; ⌥ copy, ⌘ move, ⌃⌥ alias; cursor display via `NSDragOperation` | M |
| F-09 | ✅ | spring-loaded folders (delay adjustable) | M |
| F-10 | ✅ | Duplicate, real aliases (bookmark files), Show Original | ST |
| F-11 | ✅ | missing target detected; "Fix Alias …/Delete"; symlinks remain symlinks | ST |
| F-12 | ✅ | Show Package Contents | M |
| F-13 | ✅ | Replace, Keep Both, Skip, Stop, "apply to all"; replace is atomic with fallback | ST |
| F-14 | ✅ | Merge folders (recursive, conflicts individually) | ST |
| F-15 | ✅ | Progress window (after 0.5 s), cancel, error messages | M |
| F-16 | ✅ | Undo/Redo with accurate label | ST |
| F-17 | ✅ | ZIP via `ditto` (single/multiple), extract via Archive Utility | ST |
| F-18 | ✅ | Permissions, locked items, full disk (ENOSPC text), read-only | M |
| F-19 | 🟡 | Print via `lpr` | M |
| F-20 | ✅ | "Show Clipboard" (files/text/image) | M |
| §7.1 | ✅ | `copyfile(COPYFILE_ALL|RECURSIVE|NOFOLLOW_SRC)`: content, timestamps, xattr, permissions, resource forks; source deleted only after success; recursion rejected | ST |

## Trash, Info, Labels (I)
| ID | Status | Implementation | Verification |
|---|---|---|---|
| I-01 | ✅ | `trashItem` (per volume); fallback "delete immediately" with warning | ST |
| I-02 | ✅ | Put Back (original location remembered, conflicts) | ST |
| I-03 | ✅ | Empty with warning, partial errors, cancel | M |
| I-04 | ❌ | Secure empty: honest notice | M |
| I-05 | ✅ | Info per item; multiple selection; Inspector (⌥⌘I) follows the selection | UT |
| I-06 | ✅ | Kind, Size (on disk/bytes), Where, date fields, lock, metadata (MDItem) | UT |
| I-07 | ✅ | Name & Extension, Hide extension, Spotlight comment, label, Locked | ST |
| I-08 | ✅ | Open With in the Info window | M |
| I-09 | ✅ | Owner/Group/Everyone (POSIX), apply to enclosed items | M |
| I-10 | ✅ | Volume: Format, Capacity, Available, Used | UT |
| I-11 | ✅ | 7 color labels + None, names editable, search by label, sort by label | ST |
| I-12 | ✅ | only `labelNumber` is changed; tags are preserved | ST |

## Search, Quick Look (S)
| ID | Status | Implementation | Verification |
|---|---|---|---|
| S-01 | ✅ | Search field with focus, clear button, ⎋, ⌘F, progress indicator, "No Results" | UT |
| S-02 | ✅ | This Mac / Folder / Shared; default scope adjustable | UT |
| S-03 | ✅ | File name vs. contents | ST |
| S-04 | ✅ | Criteria: Kind, Name, Contents, Extension, date fields, Size, Label; "+"/"−" | ST, UT |
| S-05 | ✅ | System paths/invisible files hidden; permissions respected | M |
| S-06 | ✅ | Save (`.savedSearch`), reopen/edit, in sidebar | ST |
| S-07 | ✅ | Results = real files | M |
| S-08 | ✅ | All My Files, grouped by kind, "Show All (n)" | SS |
| S-09 | ✅ | all views + file actions on results | UT |
| S-10 | 🟡 | Space bar/⌘Y/menu/toolbar (no three-finger tap) | M |
| S-11/12 | ✅ | `QLPreviewPanel` (multiple selection, index, slideshow, full screen, media, share) | M |

## Volumes, Network (X)
| ID | Status | Implementation | Verification |
|---|---|---|---|
| X-01 | ✅ | Detect/open/eject volumes | M |
| X-02 | ✅ | Disk images via system (`open`) | M |
| X-03 | ✅ | Connect to Server: address, favorites (+/−), browse, error dialog | UT |
| X-04 | 🟡 | smb/afp/vnc/ftp/http(s) handed over to the system | M |
| X-05 | ✅ | Bonjour (SMB/AFP) in "Shared" and "Network" | M |
| X-06 | ✅ | "Share Screen …" → vnc:// | M |
| X-07 | 🟡 | AirDrop view + system service | M |
| X-08 | ✅ | Share menu from system services, file-type dependent | UT |
| X-09 | ❌ | see Deviations | – |
| X-10 | ✅ | Burn folders (.fpbf) with aliases, scope, missing originals | M |
| X-11 | 🟡 | `drutil burn`; no hardware tested | M |
| X-12 | 🟡 | `diskutil apfs encryptVolume` | M |
| X-13 | ✅ | Eject with error message when in use | M |

## Preferences, Menus (E)
| ID | Status | Implementation | Verification |
|---|---|---|---|
| E-01 | ✅ | General, Labels, Sidebar, Advanced | SS, UT |
| E-02 | ✅ | Desktop volumes, new window target, folders in new windows, spring-loaded folders | M |
| E-03 | ✅ | Sidebar categories, label names | M |
| E-04 | 🟡 | Extensions, warnings, Trash warning, search scope; secure empty ❌ | M |
| E-05 | ✅ | Context menus: empty area, file, folder, package, alias, volume, Trash, multiple selection, search result | UT |
| E-06 | ❌ | see Deviations | – |
| E-07 | ❌ | see Deviations | – |
| E-08 | 🟡 | Help + shortcuts + system search in the Help menu | M |
| E-09 | ✅ | Dock menu, open Time Machine, default applications | M |
| E-10 | ✅ | German/English (date formats, menus, shortcuts) | SS |

## X-Mode (extension beyond the requirements specification)
| Feature | Status | Implementation | Verification |
|---|---|---|---|
| X-Mode setting (on/off, Tabs, Dual Pane) | ✅ | Preferences ▸ X-Mode; "X-Mode" menu only when the mode is active | UT |
| Tabs | ✅ | Tab row in the title bar (Mavericks/TotalFinder look), new/close/switch/reorder, own navigation history and selection per tab | ST |
| Dual Pane | ✅ | two full-featured halves (own view, path bar, status bar), active half marked, actions/menus act on the active half | ST |
| F-key footer bar | ✅ | F5 Copy, F6 Move, F7 New Folder, F8 Delete as button and key (the choice of F5–F8 follows the Total Commander standard) | ST |
| App icon setting | ✅ | Preferences ▸ Advanced: PNG exactly 256 × 256 px, validation, storage in Application Support, reset | M |
| Radio: Tabs OR Dual Pane | ✅ | `Prefs.xKind`; toggle ⌥⌘P | ST |
| Options Library / Hidden / Folders on top | ✅ | general preferences (General), in all four views, independent of X-Mode | ST |
| Aqua traffic lights (option) | ✅ | custom Ø-12 traffic lights, system buttons hidden | SS |
| Colored icons (option) | ✅ | Sidebar colored (Lion theme) or monochrome | SS |
| Remember tabs across restart | ✅ | first window saves locations + active tab (`savedTabs`) | M |
| ⌘⇧T restore tab, ⌥⌘1–9 select tab | ✅ | "X-Mode" menu | ST |
| Dual Pane: other half = this one (⌥⌘=), swap halves (⌥⌘X) | ✅ | "X-Mode" menu | ST |
| Select by pattern (⌘+) / deselect (⌘−) | ✅ | wildcards `*` `?`, multiple patterns separated by comma | ST |
| Multi-rename (⌥⌘R) | ✅ | replace/add text, numbering with format `{name} {n}`, upper/lower case, regular expression; live preview with conflict display; two-stage (swap without loss), single undo step | ST |
| Copy/move with queue (⌥⌘Q) | ✅ | sequential, progress, speed, remaining time, pause, cancel per operation, conflict rule (ask/replace/keep/skip/newer only), optional verification (size + SHA-256) | ST |
| History per half (⌥↓ / button in the header bar) | ✅ | own list of recently visited locations per half (max. 30, no duplicates), selection navigates only this half, "Clear History", persists across restarts | ST |
| Favorites per half (⌥⌘B, star in the header bar) | ✅ | own hotlist per half; star filled when the folder is a favorite; ⇧⌥⌘B toggles; drag a folder onto the star = add; management (reorder by dragging/arrows, remove); "Copy to the other half"; persists across restarts | ST |
| Terminal here (⇧⌥⌘T, context menu, toolbar item) / Copy path (⌥⌘C) | ✅ | opens the chosen terminal application (Preferences ▸ General: Terminal, iTerm, Ghostty, Warp, WezTerm, Hyper, kitty, Alacritty or other) in the selected folder or the current folder; without automation permissions | ST |
| Custom Icons (Preferences ▸ Custom Icons) | ✅ | choose/drop one PNG per sidebar icon (transparent, exactly 64 × 64); validation of format, size, alpha channel; export templates, import folder, reset; white selection variant optional | ST, SS |
