import AppKit

extension Prefs {
    static var coloredIcons: Bool { get { bool("coloredIcons", false) } set { d.set(newValue, forKey: "coloredIcons") } }
    static var customWhiteOnSelect: Bool { get { bool("customWhiteSel", true) } set { d.set(newValue, forKey: "customWhiteSel") } }
}

/// Eigene Seitenleistensymbole (Einstellungen ▸ Custom Icons): je Eintrag ein PNG, transparent, genau 64 × 64 Pixel.
/// Ablage: ~/Library/Application Support/RetroFind/CustomIcons/<Schlüssel>.png (Schlüssel = Glyph-Name, z. B. allFiles).
enum CustomIcons {
    /// Austauschbare Symbole der Seitenleiste (Reihenfolge wie in der Seitenleiste)
    static let slots: [(glyph: Glyph, de: String, en: String)] = [
        (.allFiles, "Alle meine Dateien", "All My Files"), (.airDrop, "AirDrop", "AirDrop"), (.applications, "Programme", "Applications"), (.desktop, "Schreibtisch", "Desktop"),
        (.documents, "Dokumente", "Documents"), (.downloads, "Downloads", "Downloads"), (.movies, "Filme", "Movies"), (.music, "Musik", "Music"), (.pictures, "Bilder", "Pictures"),
        (.home, "Benutzerordner", "Home folder"), (.utilities, "Dienstprogramme", "Utilities"), (.trash, "Papierkorb", "Trash"), (.folder, "Ordner (eigene Favoriten)", "Folder (your favorites)"),
        (.library, "Library", "Library"), (.publicFolder, "Öffentlich", "Public"), (.sites, "Websites", "Sites"),
        (.computer, "Computer", "Computer"), (.hardDisk, "Festplatte", "Hard disk"), (.usb, "Externes Laufwerk", "External drive"), (.disc, "CD/DVD", "CD/DVD"), (.timeMachine, "Time Machine", "Time Machine"),
        (.server, "Server / Freigabe", "Server / share"), (.network, "Netzwerk „Alle …“", "Network \u{201C}All…\u{201D}"), (.smartFolder, "Intelligenter Ordner", "Smart folder"), (.eject, "Auswerfen-Knopf", "Eject button")]
    static var dirOverride: URL?       // nur für Tests
    static var dir: URL { if let o = dirOverride { return o }; return Files.fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RetroFind/CustomIcons") }
    static func file(_ g: Glyph) -> URL { dir.appendingPathComponent(g.rawValue + ".png") }
    static func has(_ g: Glyph) -> Bool { Files.fm.fileExists(atPath: file(g).path) }
    private static var cache: [String: NSImage] = [:]
    static func invalidate() { cache.removeAll() }

    /// Eigenes Symbol (normal) oder weiße Silhouette (bei Auswahl, wenn eingestellt)
    static func image(_ g: Glyph, selected: Bool) -> NSImage? {
        let key = g.rawValue + (selected && Prefs.customWhiteOnSelect ? ":w" : "")
        if let i = cache[key] { return i }
        guard has(g), let base = NSImage(contentsOf: file(g)) else { return nil }
        base.size = NSSize(width: 64, height: 64)
        var out = base
        if selected && Prefs.customWhiteOnSelect {
            out = NSImage(size: base.size, flipped: false) { r in
                base.draw(in: r); NSColor.white.setFill(); r.fill(using: .sourceAtop); return true
            }
        }
        cache[key] = out; return out
    }

    /// Prüft: PNG, genau 64 × 64 Pixel, mit Alphakanal und mindestens einem transparenten Pixel
    static func validate(_ data: Data) -> String? {
        guard data.starts(with: [0x89, 0x50, 0x4E, 0x47]), let rep = NSBitmapImageRep(data: data) else { return L("Die Datei ist kein PNG.", "The file is not a PNG.") }
        guard rep.pixelsWide == 64, rep.pixelsHigh == 64 else { return L("Das Bild ist \(rep.pixelsWide) × \(rep.pixelsHigh) Pixel groß – erforderlich sind genau 64 × 64.", "The image is \(rep.pixelsWide) × \(rep.pixelsHigh) pixels – exactly 64 × 64 is required.") }
        guard rep.hasAlpha else { return L("Das PNG hat keinen Alphakanal (Transparenz).", "The PNG has no alpha channel (transparency).") }
        var transparent = false
        outer: for y in 0..<64 { for x in 0..<64 { if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 1) < 0.99 { transparent = true; break outer } } }
        return transparent ? nil : L("Das PNG hat keine transparenten Pixel – bitte mit transparentem Hintergrund speichern.", "The PNG has no transparent pixels – please save it with a transparent background.")
    }
    @discardableResult static func set(_ g: Glyph, from url: URL, quiet: Bool = false) -> String? {
        guard let d = try? Data(contentsOf: url) else { return L("Die Datei konnte nicht gelesen werden.", "The file couldn\u{2019}t be read.") }
        if let e = validate(d) { if !quiet { FileOps.shared.alert(L("Das Symbol kann nicht verwendet werden.", "The icon can\u{2019}t be used."), e) }; return e }
        try? Files.fm.createDirectory(at: dir, withIntermediateDirectories: true)
        do { try d.write(to: file(g), options: .atomic) } catch { return error.localizedDescription }
        invalidate(); changed(); return nil
    }
    static func reset(_ g: Glyph) { try? Files.fm.removeItem(at: file(g)); invalidate(); changed() }
    static func resetAll() { for s in slots { try? Files.fm.removeItem(at: file(s.glyph)) }; invalidate(); changed() }
    static func changed() { BrowserController.all.forEach { $0.sidebar.needsDisplay = true; $0.sidebar.reload() }; NotificationCenter.default.post(name: .customIconsChanged, object: nil) }

    /// Vorlage: aktuelle Standardsymbole als 64 × 64-PNG mit Transparenz (zum Bearbeiten und Wiederimportieren)
    static func exportTemplates(to folder: URL) -> Int {
        var n = 0
        for s in slots {
            let img = NSImage(size: NSSize(width: 64, height: 64), flipped: true) { r in s.glyph.draw(in: r.insetBy(dx: 6, dy: 6), selected: false); return true }
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            rep.size = NSSize(width: 64, height: 64)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor.clear.set(); NSRect(x: 0, y: 0, width: 64, height: 64).fill(using: .copy)
            let t = NSAffineTransform(); t.translateX(by: 0, yBy: 64); t.scaleX(by: 1, yBy: -1); t.concat()
            s.glyph.draw(in: NSRect(x: 6, y: 6, width: 52, height: 52), selected: false, tint: nil)
            NSGraphicsContext.restoreGraphicsState()
            if let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: folder.appendingPathComponent(s.glyph.rawValue + ".png"))) != nil { n += 1 }
        }
        return n
    }
    /// Ordner importieren: Dateien heißen `<Schlüssel>.png` (Groß-/Kleinschreibung egal). Rückgabe: (importiert, abgelehnt)
    static func importFolder(_ folder: URL) -> (ok: Int, rejected: [String]) {
        var ok = 0; var bad: [String] = []
        for f in (try? Files.fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension.lowercased() == "png" {
            let name = f.deletingPathExtension().lastPathComponent.lowercased()
            guard let s = slots.first(where: { $0.glyph.rawValue.lowercased() == name }) else { bad.append(f.lastPathComponent + " – " + L("kein bekannter Name", "unknown name")); continue }
            if let e = set(s.glyph, from: f, quiet: true) { bad.append(f.lastPathComponent + " – " + e) } else { ok += 1 }
        }
        return (ok, bad)
    }
}
extension Notification.Name { static let customIconsChanged = Notification.Name("MLCustomIconsChanged") }

// MARK: Einstellungsseite „Custom Icons“

final class CustomIconsPane: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    func build() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 520))
        func lab(_ s: String, _ y: CGFloat, _ h: CGFloat, size: CGFloat = 11, bold: Bool = false) -> NSTextField { let t = NSTextField(wrappingLabelWithString: s); t.font = lucida(size, bold: bold); t.frame = NSRect(x: 20, y: y, width: 440, height: h); t.textColor = bold ? .labelColor : .secondaryLabelColor; v.addSubview(t); return t }
        _ = lab(L("Seitenleistensymbole austauschen", "Replace sidebar icons"), 488, 18, size: 12, bold: true)
        _ = lab(L("Vorgabe: PNG, transparenter Hintergrund, genau 64 × 64 Pixel. Datei auf eine Zeile ziehen oder „Wählen …“. Ohne eigenes Symbol gilt die Standardzeichnung.", "Requirement: PNG, transparent background, exactly 64 × 64 pixels. Drop a file onto a row or use \u{201C}Choose…\u{201D}. Without a custom icon the built-in drawing is used."), 440, 44)
        let sc = NSScrollView(frame: NSRect(x: 20, y: 84, width: 440, height: 352)); sc.hasVerticalScroller = true; sc.borderType = .bezelBorder
        let c = NSTableColumn(identifier: .init("c")); c.width = 420; table.addTableColumn(c); table.headerView = nil; table.dataSource = self; table.delegate = self; table.rowHeight = 38
        table.registerForDraggedTypes([.fileURL]); table.draggingDestinationFeedbackStyle = .regular
        sc.documentView = table; v.addSubview(sc)
        func btn(_ t: String, _ x: CGFloat, _ w: CGFloat, _ a: Selector) { let b = NSButton(title: t, target: self, action: a); b.bezelStyle = .rounded; b.font = lucida(11); b.frame = NSRect(x: x, y: 50, width: w, height: 26); v.addSubview(b) }
        btn(L("Vorlage exportieren …", "Export Templates…"), 20, 150, #selector(exportTemplates)); btn(L("Ordner importieren …", "Import Folder…"), 176, 140, #selector(importFolder)); btn(L("Alle zurücksetzen", "Reset All"), 322, 138, #selector(resetAll))
        let w = NSButton(checkboxWithTitle: L("Bei Auswahl weiß darstellen (für einfarbige Symbole)", "Show white when selected (for monochrome icons)"), target: self, action: #selector(whiteChanged(_:))); w.state = Prefs.customWhiteOnSelect ? .on : .off; w.font = lucida(11); w.frame = NSRect(x: 20, y: 20, width: 440, height: 20); v.addSubview(w)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .customIconsChanged, object: nil)
        return v
    }
    @objc func reload() { table.reloadData() }
    func numberOfRows(in t: NSTableView) -> Int { CustomIcons.slots.count }
    func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let s = CustomIcons.slots[row]; let v = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 38))
        let img = NSImageView(frame: NSRect(x: 8, y: 3, width: 32, height: 32)); img.imageScaling = .scaleProportionallyUpOrDown
        img.image = CustomIcons.image(s.glyph, selected: false) ?? NSImage(size: NSSize(width: 32, height: 32), flipped: true) { r in s.glyph.draw(in: r.insetBy(dx: 4, dy: 4)); return true }
        v.addSubview(img)
        let name = NSTextField(labelWithString: Lang.de ? s.de : s.en); name.font = lucida(12); name.frame = NSRect(x: 48, y: 19, width: 190, height: 15); v.addSubview(name)
        let custom = CustomIcons.has(s.glyph)
        let st = NSTextField(labelWithString: custom ? L("Eigenes Symbol", "Custom icon") : L("Standard", "Default")); st.font = lucida(10); st.textColor = custom ? NSColor(40, 120, 60) : .secondaryLabelColor; st.frame = NSRect(x: 48, y: 4, width: 190, height: 13); v.addSubview(st)
        let ch = NSButton(title: L("Wählen …", "Choose…"), target: self, action: #selector(choose(_:))); ch.tag = row; ch.bezelStyle = .rounded; ch.font = lucida(11); ch.frame = NSRect(x: 244, y: 6, width: 84, height: 24); v.addSubview(ch)
        let rs = NSButton(title: L("Zurücksetzen", "Reset"), target: self, action: #selector(resetOne(_:))); rs.tag = row; rs.bezelStyle = .rounded; rs.font = lucida(11); rs.frame = NSRect(x: 330, y: 6, width: 86, height: 24); rs.isEnabled = custom; v.addSubview(rs)
        return v
    }
    @objc func choose(_ s: NSButton) {
        let p = NSOpenPanel(); p.allowedContentTypes = [.png]; p.message = L("PNG, transparent, 64 × 64 Pixel", "PNG, transparent, 64 × 64 pixels")
        if p.runModal() == .OK, let u = p.url { CustomIcons.set(CustomIcons.slots[s.tag].glyph, from: u) }
    }
    @objc func resetOne(_ s: NSButton) { CustomIcons.reset(CustomIcons.slots[s.tag].glyph) }
    @objc func resetAll() {
        let a = NSAlert(); a.messageText = L("Alle eigenen Symbole zurücksetzen?", "Reset all custom icons?"); a.addButton(withTitle: L("Zurücksetzen", "Reset")); a.addButton(withTitle: L("Abbrechen", "Cancel"))
        if a.runModal() == .alertFirstButtonReturn { CustomIcons.resetAll() }
    }
    @objc func whiteChanged(_ s: NSButton) { Prefs.customWhiteOnSelect = s.state == .on; CustomIcons.invalidate(); CustomIcons.changed() }
    @objc func exportTemplates() {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true; p.prompt = L("Hierher exportieren", "Export Here"); p.message = L("Ordner für die 64 × 64-Vorlagen wählen", "Choose a folder for the 64 × 64 templates")
        guard p.runModal() == .OK, let u = p.url else { return }
        let n = CustomIcons.exportTemplates(to: u)
        FileOps.shared.alert(L("\(n) Vorlagen exportiert.", "\(n) templates exported."), L("Bearbeite die PNGs (Name = Schlüssel, Größe und Transparenz beibehalten) und importiere den Ordner wieder.", "Edit the PNGs (name = key; keep size and transparency) and import the folder again."))
        NSWorkspace.shared.activateFileViewerSelecting([u])
    }
    @objc func importFolder() {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.prompt = L("Importieren", "Import"); p.message = L("Ordner mit <Schlüssel>.png (64 × 64, transparent)", "Folder with <key>.png files (64 × 64, transparent)")
        guard p.runModal() == .OK, let u = p.url else { return }
        let r = CustomIcons.importFolder(u)
        FileOps.shared.alert(L("\(r.ok) Symbole importiert.", "\(r.ok) icons imported."), r.rejected.isEmpty ? "" : L("Abgelehnt:\n", "Rejected:\n") + r.rejected.prefix(8).joined(separator: "\n"))
    }
    // Drop einer PNG-Datei auf eine Zeile
    func tableView(_ t: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        guard (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.count == 1 else { return [] }
        t.setDropRow(row, dropOperation: .on); return .copy
    }
    func tableView(_ t: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation op: NSTableView.DropOperation) -> Bool {
        guard let u = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first else { return false }
        return CustomIcons.set(CustomIcons.slots[row].glyph, from: u) == nil
    }
}
