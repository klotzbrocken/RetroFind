# Deviation list (specification §12)

Functions that are unavailable on a current macOS or only reachable through system services. Every deviation requires explicit acceptance by the client (specification §12/M6).

| ID | Historical feature | Status in the recreation | Reason |
|---|---|---|---|
| I-04 / E-04 | Empty Trash securely | Command and setting present; **not supported** – notice dialog, normal deletion | APFS/flash: overwriting does not guarantee destruction (§12) |
| X-04 | FTP writing, AFP | FTP/AFP addresses are handed to the system; writability/AFP availability is decided by macOS | System service NetFS |
| X-07 | AirDrop (10.8 protocol) | View + hand-off to the **system AirDrop service** (drop, selection) | Discovery/transfer is done by the system; the Mountain Lion protocol cannot be reconstructed |
| X-09 | Facebook/Flickr/Vimeo/Twitter | The Share menu shows exactly the services reported by the system (`NSSharingService`) | The old online services/accounts no longer exist; no sending is simulated |
| X-11 | Direct burning | Burn folder (.fpbf, aliases, total size, missing originals) + burn job via `drutil`; notice if there is no burner | No hardware to test with; progress only approximate |
| X-12 | Volume encryption (CoreStorage/FileVault entry) | Context command "Encrypt…" → `diskutil apfs encryptVolume` with the password via stdin | The 10.8 CoreStorage workflows are not transferable |
| E-06 | Services in the context menu, Folder Actions | Services menu in the menu bar; **no** Folder Actions | Folder Actions are no longer part of macOS |
| E-07 | The Finder's AppleScript dictionary | **not implemented** (only the standard "open" events) | The original dictionary is not available; scripts address Apple's Finder |
| S-10 | Quick Look via three-finger tap | Space bar, ⌘Y, menu, toolbar | Trackpad API not available to apps |
| N-14 | Desktop | Optional (View ▸ Desktop icons), **off** by default | In RetroMac the existing desktop component handles the desktop |
| V-02 | Traffic lights Ø 12 pt / spacing 20 pt (original size) | **System traffic lights** (macOS window buttons, larger, with today's gloss) by default; **Aqua Glow** lights (original size) selectable in Preferences ▸ Advanced | Client decision |
| V-05 | Original fonts | Lucida Grande (supplied by the system) | Third-party font rights are not shipped |
| V-07 | Warning/system dialogs in the original style | AppKit `NSAlert`/`NSOpenPanel` | Host dialogs cannot be freely styled (§12) |
| V-09 | File type icons in 10.8 style | Sidebar, folders and toolbar are our own drawings (no Apple material); file icons come from the host. Anyone can install close-to-original icons locally via Preferences ▸ Custom Icons (PNG 64 × 64) | Rights to Apple icons (§13) |
| §2.3 | Minimum window size | 380 × 200 as a working value | Original not measured |
