import AppKit
import QuickLookThumbnailing

extension Notification.Name { static let selectionChangedNote = Notification.Name("MLSelectionChanged") }

/// Informationsfenster (I-05…I-10): Einzelobjekt, Mehrfachauswahl, Inspektor, Volume.
final class InfoWindow: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSTextViewDelegate {
    static var open: [String: InfoWindow] = [:]
    static var inspector: InfoWindow?
    var urls: [URL]; let panel: NSPanel
    weak var controller: BrowserController?
    var isInspector = false
    private var collapsed: Set<String> { get { Set(UserDefaults.standard.stringArray(forKey: "infoCollapsed") ?? ["more", "preview", "name"]) } set { UserDefaults.standard.set(Array(newValue), forKey: "infoCollapsed") } }
    private var commentView: NSTextView?; private var nameField: NSTextField?; private var sizeLabel: NSTextField?
    private var sizeTask = 0

    static func show(_ urls: [URL], from c: BrowserController) {
        guard !urls.isEmpty else { return }
        // pro Objekt ein Fenster (bei Mehrfachauswahl: ein Fenster je Objekt, wie im Original ein Fenster je Auswahlobjekt)
        let list = urls.count > 12 ? [urls] : urls.map { [$0] }
        for u in list {
            let key = u.map { $0.path }.joined(separator: "|")
            if let w = open[key] { w.panel.makeKeyAndOrderFront(nil); continue }
            let w = InfoWindow(urls: u); w.controller = c; open[key] = w; c.infoWindows.append(w)
            w.panel.setFrameTopLeftPoint(NSPoint(x: c.win.frame.maxX + 16 + CGFloat(open.count % 6) * 22, y: c.win.frame.maxY - CGFloat(open.count % 6) * 22))
            w.panel.makeKeyAndOrderFront(nil)
        }
        if urls.count > 1 && urls.count <= 12 { /* mehrere Einzelfenster */ }
    }
    static func showInspector(from c: BrowserController) {
        if let w = inspector { w.panel.makeKeyAndOrderFront(nil); w.urls = c.selection.isEmpty ? (c.currentDir.map { [$0] } ?? []) : c.selection; w.build(); return }
        let w = InfoWindow(urls: c.selection.isEmpty ? (c.currentDir.map { [$0] } ?? []) : c.selection); w.isInspector = true; w.controller = c; inspector = w
        NotificationCenter.default.addObserver(w, selector: #selector(inspectorUpdate), name: .selectionChangedNote, object: nil)
        w.panel.makeKeyAndOrderFront(nil)
    }
    @objc func inspectorUpdate() {
        guard isInspector, let c = (NSApp.keyWindow?.windowController as? BrowserController) ?? BrowserController.all.first(where: { $0.win.isMainWindow }) else { return }
        urls = c.selection.isEmpty ? (c.currentDir.map { [$0] } ?? []) : c.selection; build()
    }
    func close() { panel.close() }

    init(urls: [URL]) {
        self.urls = urls
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 270, height: 400), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false; panel.delegate = self; panel.hidesOnDeactivate = false; panel.isFloatingPanel = false
        build()
    }
    func windowWillClose(_ n: Notification) {
        InfoWindow.open = InfoWindow.open.filter { $0.value !== self }; if InfoWindow.inspector === self { InfoWindow.inspector = nil }
        NotificationCenter.default.removeObserver(self); controller?.infoWindows.removeAll { $0 === self }
    }

    // MARK: Aufbau
    func build() {
        let v = FlippedView(); var y: CGFloat = 12; let W: CGFloat = 270
        commentView = nil; nameField = nil
        let single = urls.count == 1 ? urls[0] : nil
        let node = single.map { FileNode(url: $0) }
        if let n = node, n.isPackage { n.size = FileNode.packageSize(n.url) }
        panel.title = single.map { L("\($0.lastPathComponent) Informationen", "\($0.lastPathComponent) Info") } ?? (isInspector ? L("Inspektor", "Inspector") : L("\(urls.count) Objekte Informationen", "\(urls.count) Items Info"))
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, bold: Bool = false, size: CGFloat = 11, color: NSColor = .black, align: NSTextAlignment = .left, lines: Int = 1) -> NSTextField {
            let t = NSTextField(labelWithString: s); t.font = lucida(size, bold: bold); t.textColor = color; t.alignment = align; t.frame = NSRect(x: x, y: y, width: w, height: CGFloat(lines) * (size + 5)); t.lineBreakMode = lines > 1 ? .byWordWrapping : .byTruncatingMiddle; t.maximumNumberOfLines = lines; v.addSubview(t); return t
        }
        // Kopf: Symbol + Name
        let iconV = NSImageView(frame: NSRect(x: 14, y: y, width: 32, height: 32))
        iconV.image = node.map { n in NSImage(size: NSSize(width: 32, height: 32), flipped: true) { r in IconCache.shared.draw(n, in: r, preview: false); return true } } ?? NSImage(size: NSSize(width: 32, height: 32), flipped: true) { r in FolderArt.draw(in: r); return true }
        v.addSubview(iconV)
        if let n = node {
            let nf = NSTextField(string: n.name); nf.font = lucida(12, bold: true); nf.frame = NSRect(x: 54, y: y - 1, width: W - 68, height: 18); nf.isBordered = false; nf.drawsBackground = false; nf.focusRingType = .exterior; nf.delegate = self; nf.lineBreakMode = .byTruncatingMiddle; nf.tag = 1
            v.addSubview(nf); nameField = nf
            let sub = n.isVolume ? "" : (n.isDir && !n.isPackage ? n.displayKind : "\(n.displayKind) – \(Files.sizeString(n.size))")
            _ = text(sub, 54, y + 17, W - 68, color: NSColor(gray: 90))
            _ = text(L("Geändert: ", "Modified: ") + Files.dateString(n.modified, long: true), 54, y + 31, W - 68, size: 10, color: NSColor(gray: 110))
            y += 56
            // Etikett-Leiste
            y = labelRow(v, y, n)
        } else {
            _ = text(L("\(urls.count) Objekte", "\(urls.count) items"), 54, y + 2, W - 68, bold: true, size: 12)
            let total = urls.reduce(0) { $0 + max(0, FileNode(url: $1).size) }
            sizeLabel = text(Files.sizeString(Int64(total)) + L(" (Ordner werden berechnet …)", " (calculating folders…)"), 54, y + 19, W - 68, color: NSColor(gray: 90))
            let us = urls; DispatchQueue.global().async { let t = FileOps.totalSize(us); DispatchQueue.main.async { self.sizeLabel?.stringValue = Files.sizeString(t) } }
            y += 52
        }
        y = divider(v, y)
        // Abschnitte
        func section(_ id: String, _ title: String, _ body: (inout CGFloat) -> Void) {
            let open = !collapsed.contains(id)
            let b = DisclosureButton(frame: NSRect(x: 8, y: y, width: W - 16, height: 16)); b.title = title; b.open = open
            let h = ActionHandler { [weak self] in guard let s = self else { return }; var c = s.collapsed; if c.contains(id) { c.remove(id) } else { c.insert(id) }; s.collapsed = c; s.build() }
            objc_setAssociatedObject(b, &handlerKey, h, .OBJC_ASSOCIATION_RETAIN); b.target = h; b.action = #selector(ActionHandler.run)
            v.addSubview(b); y += 20
            if open { body(&y); y += 4 }
            y += 2
        }
        func kv(_ k: String, _ val: String, _ yy: inout CGFloat, lines: Int = 1) { _ = text(k + ":", 10, yy, 78, size: 11, color: NSColor(gray: 100), align: .right); let t = text(val, 94, yy, W - 104, lines: lines); t.lineBreakMode = lines > 1 ? .byCharWrapping : .byTruncatingMiddle; yy += CGFloat(lines) * 16 }
        if let n = node {
            section("general", L("Allgemein", "General")) { yy in
                if n.isVolume { let i = Files.volumeInfo(n.url); kv(L("Format", "Format"), i.format, &yy); kv(L("Kapazität", "Capacity"), Files.sizeString(i.capacity), &yy); kv(L("Verfügbar", "Available"), Files.sizeString(i.available), &yy); kv(L("Belegt", "Used"), Files.sizeString(i.capacity - i.available), &yy); kv(L("Ort", "Mount Point"), n.url.path, &yy) }
                else {
                    kv(L("Art", "Kind"), n.displayKind, &yy)
                    if n.isDir && !n.isPackage {
                        let key = n.url
                        sizeTask += 1; let tk = sizeTask
                        let sl = text(L("Berechne …", "Calculating…"), 94, yy, W - 104); sizeLabel = sl
                        DispatchQueue.global().async { let t = FileOps.totalSize([key]); DispatchQueue.main.async { if self.sizeTask == tk { sl.stringValue = Files.sizeString(t) + (t > 1024 ? " (" + Files.num(Int(t)) + L(" Byte)", " bytes)") : "") } } }
                        _ = text(L("Größe", "Size") + ":", 10, yy, 78, color: NSColor(gray: 100), align: .right); yy += 16
                    } else {
                        let alloc = (try? n.url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0
                        kv(L("Größe", "Size"), "\(Files.sizeString(Int64(alloc))) \(L("auf dem Datenträger", "on disk")) (\(Files.num(Int(max(0, n.size)))) \(L("Byte", "bytes")))", &yy, lines: 2)
                    }
                    kv(L("Ort", "Where"), n.url.deletingLastPathComponent().path, &yy, lines: 2)
                }
                kv(L("Erstellt", "Created"), Files.dateString(n.created, long: true), &yy)
                kv(L("Geändert", "Modified"), Files.dateString(n.modified, long: true), &yy)
                kv(L("Zuletzt geöffnet", "Last opened"), Files.dateString(n.opened, long: true), &yy)
                if n.isAlias, let t = Alias.resolve(n.url) { kv(L("Original", "Original"), t.path, &yy, lines: 2) }
                let lock = NSButton(checkboxWithTitle: L("Geschützt", "Locked"), target: nil, action: nil); lock.font = lucida(11); lock.frame = NSRect(x: 94, y: yy, width: 100, height: 16); lock.state = n.isLocked ? .on : .off
                let h = ActionHandler { [weak lock] in guard let lock else { return }; try? (n.url as NSURL).setResourceValue(lock.state == .on, forKey: .isUserImmutableKey); FileOps.shared.changed() }
                objc_setAssociatedObject(lock, &handlerKey, h, .OBJC_ASSOCIATION_RETAIN); lock.target = h; lock.action = #selector(ActionHandler.run); v.addSubview(lock); yy += 20
            }
            section("more", L("Weitere Informationen", "More Info")) { yy in
                let md = MDItemCreate(nil, n.url.path as CFString)
                func attr(_ k: String) -> Any? { md.flatMap { MDItemCopyAttribute($0, k as CFString) } }
                var any = false
                if let w = attr("kMDItemPixelWidth") as? Int, let h = attr("kMDItemPixelHeight") as? Int { kv(L("Abmessungen", "Dimensions"), "\(w) × \(h)", &yy); any = true }
                if let d = attr("kMDItemDurationSeconds") as? Double { kv(L("Dauer", "Duration"), String(format: "%d:%02d", Int(d) / 60, Int(d) % 60), &yy); any = true }
                if let a = attr("kMDItemAuthors") as? [String], !a.isEmpty { kv(L("Autoren", "Authors"), a.joined(separator: ", "), &yy); any = true }
                if let c = attr("kMDItemContentType") as? String { kv("UTI", c, &yy, lines: 1); any = true }
                if let v = Bundle(url: n.url)?.infoDictionary?["CFBundleShortVersionString"] as? String { kv("Version", v, &yy); any = true }
                if !any { kv("", L("Keine weiteren Informationen", "No more information"), &yy) }
            }
            if !n.isVolume {
                section("name", L("Name & Erweiterung", "Name & Extension")) { yy in
                    let f = NSTextField(string: n.name); f.font = lucida(11); f.frame = NSRect(x: 12, y: yy, width: W - 24, height: 20); f.delegate = self; f.tag = 2; v.addSubview(f); yy += 24
                    let hide = NSButton(checkboxWithTitle: L("Erweiterung ausblenden", "Hide extension"), target: nil, action: nil); hide.font = lucida(11); hide.frame = NSRect(x: 12, y: yy, width: W - 24, height: 16)
                    hide.state = ((try? n.url.resourceValues(forKeys: [.hasHiddenExtensionKey]).hasHiddenExtension) ?? false) ? .on : .off; hide.isEnabled = !n.url.pathExtension.isEmpty
                    let h = ActionHandler { [weak hide] in guard let hide else { return }; try? (n.url as NSURL).setResourceValue(hide.state == .on, forKey: .hasHiddenExtensionKey); FileOps.shared.changed() }
                    objc_setAssociatedObject(hide, &handlerKey, h, .OBJC_ASSOCIATION_RETAIN); hide.target = h; hide.action = #selector(ActionHandler.run); v.addSubview(hide); yy += 20
                }
                section("comments", L("Spotlight-Kommentare", "Spotlight Comments")) { yy in
                    let sc = NSScrollView(frame: NSRect(x: 12, y: yy, width: W - 24, height: 52)); sc.hasVerticalScroller = true; sc.borderType = .bezelBorder
                    let tv = NSTextView(frame: sc.bounds); tv.string = n.comment; tv.font = lucida(11); tv.delegate = self; tv.isRichText = false; tv.autoresizingMask = [.width]; sc.documentView = tv; v.addSubview(sc); commentView = tv; yy += 58
                }
                if !n.isDir || n.isPackage {
                    section("openwith", L("Öffnen mit", "Open with")) { yy in
                        let p = NSPopUpButton(frame: NSRect(x: 12, y: yy, width: W - 24, height: 22), pullsDown: false); p.controlSize = .small; p.font = lucida(11)
                        let apps = NSWorkspace.shared.urlsForApplications(toOpen: n.url); let def = NSWorkspace.shared.urlForApplication(toOpen: n.url)
                        for a in apps.prefix(20) { p.addItem(withTitle: Files.displayName(a).replacingOccurrences(of: ".app", with: "") + (a == def ? L(" (Standard)", " (default)") : "")); p.lastItem?.representedObject = a; let ic = NSWorkspace.shared.icon(forFile: a.path); ic.size = NSSize(width: 16, height: 16); p.lastItem?.image = ic }
                        if let d = def, let i = apps.firstIndex(of: d) { p.selectItem(at: i) }
                        v.addSubview(p); yy += 26
                        let b = NSButton(title: L("Alle ändern …", "Change All…"), target: nil, action: nil); b.bezelStyle = .rounded; b.controlSize = .small; b.frame = NSRect(x: 12, y: yy, width: 110, height: 22)
                        let h = ActionHandler { [weak p] in guard let app = p?.selectedItem?.representedObject as? URL else { return }
                            let a = NSAlert(); a.messageText = L("Möchten Sie wirklich alle Dokumente dieser Art mit diesem Programm öffnen?", "Are you sure you want to change all documents like this to open with this application?"); a.addButton(withTitle: L("Fortfahren", "Continue")); a.addButton(withTitle: L("Abbrechen", "Cancel"))
                            if a.runModal() == .alertFirstButtonReturn, let ut = try? n.url.resourceValues(forKeys: [.contentTypeKey]).contentType { NSWorkspace.shared.setDefaultApplication(at: app, toOpen: ut) { _ in } } }
                        objc_setAssociatedObject(b, &handlerKey, h, .OBJC_ASSOCIATION_RETAIN); b.target = h; b.action = #selector(ActionHandler.run); v.addSubview(b)
                        let p2 = p; let h2 = ActionHandler { guard let app = p2.selectedItem?.representedObject as? URL else { return }; self.openWith = app }
                        objc_setAssociatedObject(p, &handlerKey, h2, .OBJC_ASSOCIATION_RETAIN); p.target = h2; p.action = #selector(ActionHandler.run)
                        yy += 26
                    }
                }
                section("preview", L("Vorschau", "Preview")) { yy in
                    let iv = NSImageView(frame: NSRect(x: 12, y: yy, width: W - 24, height: 150)); iv.imageScaling = .scaleProportionallyUpOrDown
                    let req = QLThumbnailGenerator.Request(fileAt: n.url, size: CGSize(width: 240, height: 150), scale: 2, representationTypes: .all)
                    QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { r, _ in DispatchQueue.main.async { if let cg = r?.cgImage { iv.image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2)) } } }
                    v.addSubview(iv); yy += 156
                }
            }
            section("perm", L("Anwender & Zugriffsrechte", "Sharing & Permissions")) { yy in permissions(v, &yy, n, W) }
        } else {
            section("general", L("Allgemein", "General")) { yy in
                let kinds = Set(urls.map { FileNode(url: $0).displayKind }); kv(L("Art", "Kind"), kinds.count == 1 ? kinds.first! : L("Verschiedene", "Multiple"), &yy)
                y = labelRow(v, yy, nil, urls: urls); yy = y
            }
            section("perm", L("Anwender & Zugriffsrechte", "Sharing & Permissions")) { yy in kv("", L("Gemeinsame Zugriffsrechte nur bei Einzelobjekten", "Permissions are shown per item"), &yy, lines: 2) }
        }
        v.frame = NSRect(x: 0, y: 0, width: W, height: y + 10)
        panel.contentView = v
        let sz = NSSize(width: W, height: min(y + 10, (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 900 - 80))
        panel.setContentSize(sz)
    }
    var openWith: URL?

    func labelRow(_ v: NSView, _ y: CGFloat, _ n: FileNode?, urls us: [URL]? = nil) -> CGFloat {
        let l = NSTextField(labelWithString: L("Etikett:", "Label:")); l.font = lucida(11); l.textColor = NSColor(gray: 100); l.frame = NSRect(x: 10, y: y, width: 78, height: 16); l.alignment = .right; v.addSubview(l)
        let cur = n?.label ?? -1
        for i in 0...7 {
            let b = SwatchButton(frame: NSRect(x: 94 + CGFloat(i) * 21, y: y - 1, width: 18, height: 18)); b.index = i; b.selected = i == cur
            let targets = us ?? [n!.url]
            b.onClick = { [weak self] in for u in targets { Labels.set(i, for: u) }; FileOps.shared.changed(); self?.build() }
            v.addSubview(b)
        }
        return y + 26
    }
    func divider(_ v: NSView, _ y: CGFloat) -> CGFloat { let d = NSBox(frame: NSRect(x: 10, y: y, width: 250, height: 1)); d.boxType = .separator; v.addSubview(d); return y + 8 }

    func permissions(_ v: NSView, _ yy: inout CGFloat, _ n: FileNode, _ W: CGFloat) {
        let attrs = (try? Files.fm.attributesOfItem(atPath: n.url.path)) ?? [:]
        let perm = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let owner = attrs[.ownerAccountName] as? String ?? "?", group = attrs[.groupOwnerAccountName] as? String ?? "?"
        let writable = Files.fm.isWritableFile(atPath: n.url.path)
        let you = NSTextField(labelWithString: writable ? L("Sie können lesen und schreiben", "You can Read & Write") : L("Sie können nur lesen", "You can Read only")); you.font = lucida(11); you.frame = NSRect(x: 12, y: yy, width: W - 24, height: 16); v.addSubview(you); yy += 22
        let canEdit = owner == NSUserName()
        let rows: [(String, Int, Int)] = [(L("\(owner) (Ich)", "\(owner) (Me)"), 6, 6), (L("\(group)", "\(group)"), 3, 3), (L("Jeder", "everyone"), 0, 0)]
        for (i, r) in rows.enumerated() {
            let t = NSTextField(labelWithString: r.0); t.font = lucida(11); t.frame = NSRect(x: 12, y: yy + 2, width: 100, height: 16); t.lineBreakMode = .byTruncatingTail; v.addSubview(t)
            let p = NSPopUpButton(frame: NSRect(x: 116, y: yy, width: 140, height: 20), pullsDown: false); p.controlSize = .small; p.font = lucida(11)
            p.addItems(withTitles: [L("Lesen & Schreiben", "Read & Write"), L("Nur lesen", "Read only"), L("Nur schreiben", "Write only"), L("Kein Zugriff", "No Access")])
            let bits = (perm >> (6 - i * 3)) & 7
            p.selectItem(at: (bits & 6) == 6 ? 0 : (bits & 4) != 0 ? 1 : (bits & 2) != 0 ? 2 : 3); p.isEnabled = canEdit
            let h = ActionHandler { [weak p] in guard let p else { return }
                var cur = (try? Files.fm.attributesOfItem(atPath: n.url.path))?[.posixPermissions] as? Int ?? perm
                let b: Int = [6 | (n.isDir ? 1 : 0), 4 | (n.isDir ? 1 : 0), 2, 0][p.indexOfSelectedItem]
                cur = (cur & ~(7 << (6 - i * 3))) | (b << (6 - i * 3))
                do { try Files.fm.setAttributes([.posixPermissions: cur], ofItemAtPath: n.url.path) } catch { FileOps.shared.alert(error.localizedDescription) } }
            objc_setAssociatedObject(p, &handlerKey, h, .OBJC_ASSOCIATION_RETAIN); p.target = h; p.action = #selector(ActionHandler.run); v.addSubview(p); yy += 24
        }
        if n.isDir {
            let b = NSButton(title: L("Auf enthaltene Objekte anwenden …", "Apply to enclosed items…"), target: nil, action: nil); b.bezelStyle = .rounded; b.controlSize = .small; b.font = lucida(11); b.frame = NSRect(x: 12, y: yy, width: 210, height: 22); b.isEnabled = canEdit
            let h = ActionHandler {
                let a = NSAlert(); a.messageText = L("Möchten Sie die Zugriffsrechte auf alle enthaltenen Objekte anwenden?", "Are you sure you want to apply these permissions to all enclosed items?"); a.addButton(withTitle: L("Anwenden", "OK")); a.addButton(withTitle: L("Abbrechen", "Cancel"))
                guard a.runModal() == .alertFirstButtonReturn else { return }
                let p = (try? Files.fm.attributesOfItem(atPath: n.url.path))?[.posixPermissions] as? Int ?? perm
                if let e = Files.fm.enumerator(at: n.url, includingPropertiesForKeys: [.isDirectoryKey]) { for case let f as URL in e { let d = (try? f.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true; try? Files.fm.setAttributes([.posixPermissions: d ? p : (p & ~0o111)], ofItemAtPath: f.path) } } }
            objc_setAssociatedObject(b, &handlerKey, h, .OBJC_ASSOCIATION_RETAIN); b.target = h; b.action = #selector(ActionHandler.run); v.addSubview(b); yy += 26
        }
    }

    // MARK: Bearbeiten
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let f = obj.object as? NSTextField, (f.tag == 1 || f.tag == 2), urls.count == 1 else { return }
        if f.stringValue != urls[0].lastPathComponent, let d = FileOps.shared.rename(urls[0], to: f.stringValue) { urls = [d]; build() } else { f.stringValue = urls[0].lastPathComponent }
    }
    func textDidEndEditing(_ n: Notification) { if let tv = n.object as? NSTextView, tv === commentView, urls.count == 1 { Files.setComment(urls[0], tv.string); FileOps.shared.changed() } }
}

final class DisclosureButton: NSButton {
    var open = true { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); isBordered = false; setButtonType(.momentaryChange) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        let p = NSBezierPath()
        if open { p.move(to: NSPoint(x: 3, y: 5)); p.line(to: NSPoint(x: 11, y: 5)); p.line(to: NSPoint(x: 7, y: 11)) } else { p.move(to: NSPoint(x: 4, y: 3)); p.line(to: NSPoint(x: 10, y: 8)); p.line(to: NSPoint(x: 4, y: 13)) }
        p.close(); NSColor(gray: 90).setFill(); p.fill()
        Draw.text(title, in: NSRect(x: 16, y: 1, width: bounds.width - 16, height: 14), font: lucida(11, bold: true), color: NSColor(gray: 60))
    }
}

final class SwatchButton: NSView {
    var index = 0, selected = false; var onClick: () -> Void = {}
    override var isFlipped: Bool { true }
    override func draw(_ r: NSRect) {
        let rr = bounds.insetBy(dx: 2, dy: 2)
        if index == 0 { NSColor(gray: 150).setStroke(); let p = NSBezierPath(ovalIn: rr); p.lineWidth = 1; p.stroke(); let x = NSBezierPath(); x.move(to: NSPoint(x: rr.minX + 3, y: rr.maxY - 3)); x.line(to: NSPoint(x: rr.maxX - 3, y: rr.minY + 3)); x.stroke() }
        else { gradient([(0, C.labelFill[index - 1].blended(withFraction: 0.5, of: .white) ?? .white), (1, C.labelFill[index - 1])]).draw(in: NSBezierPath(ovalIn: rr), angle: 90); C.labelPillBorder[index - 1].setStroke(); NSBezierPath(ovalIn: rr.insetBy(dx: 0.5, dy: 0.5)).stroke() }
        if selected { NSColor(0, 0, 0, 0.5).setStroke(); let p = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)); p.lineWidth = 1.5; p.stroke() }
    }
    override func mouseDown(with e: NSEvent) { onClick() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
