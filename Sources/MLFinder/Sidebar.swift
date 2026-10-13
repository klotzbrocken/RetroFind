import AppKit

struct SideItem {
    var id: String
    var title: String
    var glyph: Glyph
    var location: Location
    var eject: URL? = nil
    var removable = false      // Favorit/Suche vom Nutzer
    var secondary: String? = nil
}

protocol SidebarHost: AnyObject {
    var location: Location { get }
    func sidebarNavigate(_ loc: Location, newWindow: Bool)
    func sidebarDrop(_ urls: [URL], to dir: URL, flags: NSEvent.ModifierFlags)
    func sidebarInfo(_ url: URL)
}

// MARK: Netzwerk-Entdeckung (X-05)

final class ServerBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    static let shared = ServerBrowser()
    struct Server: Hashable { var name: String; var scheme: String; var host: String }
    private(set) var servers: [Server] = []
    private var browsers: [NetServiceBrowser] = []
    private var pending: [NetService] = []
    func start() {
        guard browsers.isEmpty else { return }
        for (t, sch) in [("_smb._tcp.", "smb"), ("_afpovertcp._tcp.", "afp")] {
            let b = NetServiceBrowser(); b.delegate = self; b.searchForServices(ofType: t, inDomain: "local."); browsers.append(b); _ = sch
        }
    }
    func netServiceBrowser(_ b: NetServiceBrowser, didFind s: NetService, moreComing: Bool) {
        let scheme = s.type.contains("smb") ? "smb" : "afp"
        let sv = Server(name: s.name, scheme: scheme, host: s.name.replacingOccurrences(of: " ", with: "-") + ".local")
        if !servers.contains(where: { $0.name == sv.name }) && s.name != Host.current().localizedName { servers.append(sv); NotificationCenter.default.post(name: .fsChanged, object: nil) }
    }
    func netServiceBrowser(_ b: NetServiceBrowser, didRemove s: NetService, moreComing: Bool) {
        servers.removeAll { $0.name == s.name }; NotificationCenter.default.post(name: .fsChanged, object: nil)
    }
}

// MARK: Seitenleiste (V-04, N-08, N-11)

final class SidebarView: NSView {
    weak var host: SidebarHost?
    override var isFlipped: Bool { true }
    var active = true { didSet { needsDisplay = true } }
    private(set) var sections: [(key: String, title: String, items: [SideItem])] = []
    private var rows: [(rect: NSRect, section: Int, item: Int?)] = []
    func axRows() -> [(title: String, rect: NSRect, isHeader: Bool, selected: Bool)] { rows.map { r in let s = sections[r.section]; if let i = r.item { return (s.items[i].title, r.rect, false, isSelected(s.items[i])) }; return (s.title, r.rect, true, false) } }
    private var hoverSection: Int?
    private var dropTarget: Int?            // Zeilenindex
    private var dropInsert: (section: Int, index: Int)?
    private var pressed: Int?
    private var track: NSTrackingArea?
    private var sectionDragging: Int?

    static let internalType = NSPasteboard.PasteboardType("de.maik.retrofinder.sideitem")

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, SidebarView.internalType])
        setAccessibilityRole(.list); setAccessibilityLabel(L("Seitenleiste", "Sidebar"))
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .fsChanged, object: nil)
        for n in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] { NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(reload), name: n, object: nil) }
        ServerBrowser.shared.start()
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Time-Machine-Volume: Name enthält „Time Machine“ oder es enthält Backups.backupdb
    static func isTimeMachine(_ v: URL) -> Bool { Files.displayName(v).lowercased().contains("time machine") || Files.fm.fileExists(atPath: v.appendingPathComponent("Backups.backupdb").path) }
    static let defaultHidden: Set<String> = ["fav:home", "fav:utilities", "dev:computer", "fav:trash"]
    static func hidden() -> Set<String> { UserDefaults.standard.object(forKey: "sideHidden") == nil ? defaultHidden : Prefs.sidebarHidden }

    // Katalog aller möglichen Einträge (für die Einstellungen > Seitenleiste)
    static func catalog() -> [(section: String, title: String, items: [(id: String, title: String)])] {
        [("fav", L("Favoriten", "Favorites"), [("fav:allfiles", L("Alle meine Dateien", "All My Files")), ("fav:airdrop", "AirDrop"), ("fav:apps", L("Programme", "Applications")), ("fav:desktop", L("Schreibtisch", "Desktop")), ("fav:documents", L("Dokumente", "Documents")), ("fav:downloads", L("Downloads", "Downloads")), ("fav:movies", L("Filme", "Movies")), ("fav:music", L("Musik", "Music")), ("fav:pictures", L("Bilder", "Pictures")), ("fav:home", L("Benutzerordner", "Home folder")), ("fav:utilities", L("Dienstprogramme", "Utilities")), ("fav:trash", L("Papierkorb", "Trash"))]),
         ("shared", L("Geteilt", "Shared"), [("shared:bonjour", L("Bonjour-Computer", "Bonjour computers")), ("shared:servers", L("Verbundene Server", "Connected servers"))]),
         ("devices", L("Geräte", "Devices"), [("dev:computer", L("Dieser Computer", "This computer")), ("dev:internal", L("Festplatten", "Hard disks")), ("dev:external", L("Externe Festplatten", "External disks")), ("dev:optical", L("CDs, DVDs und iPods", "CDs, DVDs, and iPods"))]),
         ("search", L("Suchen nach", "Search For"), [("search:defaults", L("Heute, Gestern, Letzte Woche, Alle …", "Today, Yesterday, Past Week, All …")), ("search:saved", L("Gespeicherte Suchen", "Saved searches"))])]
    }

    func build() -> [(key: String, title: String, items: [SideItem])] {
        let hid = SidebarView.hidden()
        func vis(_ id: String) -> Bool { !hid.contains(id) }
        var fav: [SideItem] = []
        let std: [(String, String, Glyph, Location)] = [("allfiles", L("Alle meine Dateien", "All My Files"), .allFiles, .allMyFiles), ("airdrop", "AirDrop", .airDrop, .airDrop), ("apps", L("Programme", "Applications"), .applications, .folder(Files.applications)), ("desktop", L("Schreibtisch", "Desktop"), .desktop, .folder(Files.desktop)), ("documents", L("Dokumente", "Documents"), .documents, .folder(Files.documents)), ("downloads", "Downloads", .downloads, .folder(Files.downloads)), ("movies", L("Filme", "Movies"), .movies, .folder(Files.movies)), ("music", L("Musik", "Music"), .music, .folder(Files.music)), ("pictures", L("Bilder", "Pictures"), .pictures, .folder(Files.pictures)), ("home", NSUserName(), .home, .folder(Files.home)), ("utilities", L("Dienstprogramme", "Utilities"), .utilities, .folder(Files.utilities)), ("trash", L("Papierkorb", "Trash"), .trash, .folder(Files.trash))]
        let order = UserDefaults.standard.stringArray(forKey: "favOrder") ?? std.map { $0.0 } + []
        var byID: [String: SideItem] = [:]
        for s in std where vis("fav:" + s.0) { byID[s.0] = SideItem(id: "fav:" + s.0, title: s.1, glyph: s.2, location: s.3) }
        for p in Prefs.favorites { let u = URL(fileURLWithPath: p); if Files.exists(u) { byID["u:" + p] = SideItem(id: "u:" + p, title: Files.displayName(u), glyph: Files.glyph(for: u), location: .folder(u), removable: true) } }
        var seen = Set<String>()
        for k in order { if let i = byID[k] { fav.append(i); seen.insert(k) } }
        for k in byID.keys.sorted() where !seen.contains(k) { fav.append(byID[k]!) }
        // Standardreihenfolge für nicht gespeicherte Einträge
        if UserDefaults.standard.stringArray(forKey: "favOrder") == nil { fav = std.compactMap { byID[$0.0] } + Prefs.favorites.compactMap { byID["u:" + $0] } }

        var shared: [SideItem] = []
        if AppDelegate.demo {   // synthetische Seitenleiste für Screenshots (keine echten Rechner-/Volume-Namen)
            let sh = [SideItem(id: "d1", title: "Castle", glyph: .server, location: .network), SideItem(id: "d2", title: "Studio iMac", glyph: .computer, location: .network), SideItem(id: "all", title: L("Alle …", "All…"), glyph: .network, location: .network)]
            let dv = [SideItem(id: "d3", title: "Macintosh HD", glyph: .hardDisk, location: .folder(URL(fileURLWithPath: "/"))), SideItem(id: "d4", title: "Time Machine", glyph: .timeMachine, location: .network, eject: nil)]
            var o: [(String, String, [SideItem])] = []
            let favs = fav
            for k in Prefs.sectionOrder { switch k { case "fav": o.append((k, L("FAVORITEN", "FAVORITES"), favs)); case "shared": o.append((k, L("GETEILT", "SHARED"), sh)); case "devices": o.append((k, L("GERÄTE", "DEVICES"), dv)); default: break } }
            return o
        }
        let vols = Files.volumes()
        if vis("shared:servers") { for v in vols where Files.isNetwork(v) { shared.append(SideItem(id: "vol:" + v.path, title: Files.displayName(v), glyph: .server, location: .folder(v), eject: v)) } }
        if vis("shared:bonjour") { for s in ServerBrowser.shared.servers.prefix(8) { shared.append(SideItem(id: "bonjour:" + s.name, title: s.name, glyph: .computer, location: .network, secondary: "\(s.scheme)://\(s.host)")) } }
        shared.append(SideItem(id: "all", title: L("Alle …", "All…"), glyph: .network, location: .network))

        var dev: [SideItem] = []
        if vis("dev:computer") { dev.append(SideItem(id: "computer", title: Host.current().localizedName ?? "Computer", glyph: .computer, location: .computer)) }
        for v in vols where !Files.isNetwork(v) {
            let isRoot = v.path == "/"; let ej = Files.isEjectable(v)
            let ext = !isRoot && !ej
            let optical = (try? v.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal == true && ej && FileManager.default.fileExists(atPath: v.appendingPathComponent(".TemporaryItems").path) == false && (try? v.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal) == false && false
            _ = optical
            if isRoot && !vis("dev:internal") { continue }
            if !isRoot && ej && !vis("dev:external") && !vis("dev:optical") { continue }
            if ext && !vis("dev:external") { continue }
            dev.append(SideItem(id: "vol:" + v.path, title: Files.displayName(v), glyph: SidebarView.isTimeMachine(v) ? .timeMachine : (isRoot ? .hardDisk : (ej ? .usb : .hardDisk)), location: .folder(v), eject: ej ? v : nil))
        }
        var sr: [SideItem] = []
        let showAll = UserDefaults.standard.bool(forKey: "showSearchSection")
        if showAll {   // „Suchen nach“: vordefinierte und gespeicherte Suchen (Einstellungen > Seitenleiste)
            for s in SavedSearches.defaults() { sr.append(SideItem(id: "search:" + s.name, title: s.name, glyph: .smartFolder, location: .search(s))) }
            for u in SavedSearches.list() { if let s = SavedSearches.load(u) { sr.append(SideItem(id: "saved:" + u.path, title: s.name, glyph: .smartFolder, location: .search(s), removable: true)) } }
        } else {      // nur ausdrücklich in die Seitenleiste gelegte gespeicherte Suchen
            for p in UserDefaults.standard.stringArray(forKey: "sideSaved") ?? [] { if let s = SavedSearches.load(URL(fileURLWithPath: p)) { sr.append(SideItem(id: "saved:" + p, title: s.name, glyph: .smartFolder, location: .search(s), removable: true)) } }
        }
        var all: [String: (String, [SideItem])] = ["fav": (L("FAVORITEN", "FAVORITES"), fav), "shared": (L("GETEILT", "SHARED"), shared), "devices": (L("GERÄTE", "DEVICES"), dev), "search": (L("SUCHEN NACH", "SEARCH FOR"), sr)]
        var out: [(String, String, [SideItem])] = []
        for k in Prefs.sectionOrder { if let s = all[k], !s.1.isEmpty { out.append((k, s.0, s.1)) } }
        return out
    }

    @objc func reload() {
        sections = build()
        layoutRows(); needsDisplay = true
    }
    private func layoutRows() {
        rows = []; var y: CGFloat = 0
        let w = bounds.width
        for (si, s) in sections.enumerated() {
            if si > 0 { y += 6 }
            rows.append((NSRect(x: 0, y: y, width: w, height: M.sideHeaderH), si, nil)); y += M.sideHeaderH
            if Prefs.sidebarCollapsed.contains(s.key) { continue }
            for (ii, _) in s.items.enumerated() { rows.append((NSRect(x: 0, y: y, width: w, height: M.sideRowH), si, ii)); y += M.sideRowH }
        }
    }
    override func layout() { super.layout(); layoutRows() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let t = track { removeTrackingArea(t) }
        track = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self); addTrackingArea(track!)
    }
    override func mouseMoved(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let h = rows.first { $0.item == nil && $0.rect.contains(p) }?.section
        if h != hoverSection { hoverSection = h; needsDisplay = true }
    }
    override func mouseExited(with e: NSEvent) { hoverSection = nil; needsDisplay = true }

    private func isSelected(_ it: SideItem) -> Bool {
        guard let loc = (host as? BrowserController)?.focus.location ?? host?.location else { return false }
        switch (it.location, loc) {
        case (.folder(let a), .folder(let b)): return a.standardizedFileURL.path == b.standardizedFileURL.path
        case (.search(let a), .search(let b)): return a.id == b.id
        case (.network, .network) where it.id.hasPrefix("bonjour"): return false
        default: return it.location == loc
        }
    }

    override func draw(_ dirty: NSRect) {
        Draw.sidebarBG(bounds)
        for (ri, row) in rows.enumerated() where row.rect.intersects(dirty) {
            let s = sections[row.section]
            if let ii = row.item {
                let it = s.items[ii]; let sel = isSelected(it)
                let r = row.rect
                if sel { Draw.selection(r, active: active) }
                if dropTarget == ri { let b = NSBezierPath(roundedRect: r.insetBy(dx: 2, dy: 1), xRadius: 4, yRadius: 4); b.lineWidth = 2; C.listSel.setStroke(); b.stroke() }
                else if pressed == ri && !sel { NSColor(0, 0, 0, 0.08).setFill(); r.fill() }
                if let img = CustomIcons.image(it.glyph, selected: sel) {
                    let ir = NSRect(x: 26 - 9, y: r.midY - 9, width: 18, height: 18).integral
                    NSGraphicsContext.saveGraphicsState()
                    let sh = NSShadow(); sh.shadowColor = sel ? NSColor(0, 40, 90, 0.45) : NSColor(255, 255, 255, 0.8); sh.shadowOffset = NSSize(width: 0, height: sel ? 1 : -1); sh.shadowBlurRadius = 0; sh.set()
                    img.draw(in: ir, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
                    NSGraphicsContext.restoreGraphicsState()
                } else { it.glyph.draw(in: NSRect(x: 18, y: r.minY + 3, width: 17, height: 17), selected: sel, tint: !sel && Prefs.coloredIcons ? it.glyph.color : nil) }
                let tw = r.width - 42 - (it.eject != nil ? 28 : 8)
                let sh: NSShadow? = sel ? Draw.darkShadow(0.5) : nil
                Draw.text(it.title, in: NSRect(x: 42, y: r.minY + 4, width: tw, height: 16), font: lucida(13), color: sel ? .white : .black, shadow: sh)
                if it.eject != nil { if let e = CustomIcons.image(.eject, selected: sel) { e.draw(in: NSRect(x: r.maxX - 25, y: r.minY + 5, width: 14, height: 14), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) } else { Glyph.eject.draw(in: NSRect(x: r.maxX - 25, y: r.minY + 5, width: 14, height: 14), selected: sel) } }
            } else {
                let r = row.rect
                let collapsed = Prefs.sidebarCollapsed.contains(s.key)
                Draw.text(s.title, in: NSRect(x: 9, y: r.minY + 5.5, width: r.width - 50, height: 14), font: lucida(12, bold: true), color: C.sideHeader, shadow: Draw.whiteShadow(0.9))
                if hoverSection == row.section { Draw.text(collapsed ? L("Einblenden", "Show") : L("Ausblenden", "Hide"), in: NSRect(x: r.maxX - 56, y: r.minY + 6, width: 50, height: 13), font: lucida(10), color: NSColor(140, 152, 168), align: .right) }
            }
        }
        if let ins = dropInsert, let r = rowRect(section: ins.section, index: ins.index) {
            C.listSel.setFill(); NSRect(x: 4, y: r.minY - 1, width: bounds.width - 8, height: 2).fill()
        }
    }
    private func rowRect(section: Int, index: Int) -> NSRect? {
        if let r = rows.first(where: { $0.section == section && $0.item == index }) { return r.rect }
        if let last = rows.last(where: { $0.section == section }) { return NSRect(x: 0, y: last.rect.maxY, width: bounds.width, height: M.sideRowH) }
        return nil
    }

    // MARK: Maus
    private func rowIndex(at p: NSPoint) -> Int? { rows.firstIndex { $0.rect.contains(p) } }
    private var downPoint = NSPoint.zero
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil); downPoint = p
        guard let ri = rowIndex(at: p) else { return }
        pressed = ri; needsDisplay = true
        if rows[ri].item == nil { sectionDragging = rows[ri].section }
    }
    override func mouseDragged(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard hypot(p.x - downPoint.x, p.y - downPoint.y) > 4, let ri = pressed else { return }
        let row = rows[ri]
        if let ii = row.item {
            let it = sections[row.section].items[ii]
            let pb = NSPasteboardItem(); pb.setString("\(row.section):\(ii)", forType: SidebarView.internalType)
            var items: [NSPasteboardWriting] = [pb]
            if case .folder(let u) = it.location { pb.setString(u.absoluteString, forType: .fileURL); items = [pb] }
            let di = NSDraggingItem(pasteboardWriter: pb)
            let img = NSImage(size: NSSize(width: 120, height: 24), flipped: true) { r in it.glyph.draw(in: NSRect(x: 0, y: 4, width: 16, height: 16)); Draw.text(it.title, in: NSRect(x: 22, y: 4, width: 96, height: 16), font: lucida(12), color: .black); return true }
            di.setDraggingFrame(NSRect(x: p.x - 10, y: p.y - 12, width: 120, height: 24), contents: img)
            pressed = nil; needsDisplay = true
            beginDraggingSession(with: [di], event: e, source: self)
        } else if let sd = sectionDragging {
            // Gruppen per Ziehen der Überschrift umordnen (N-11, 10.8)
            if let tr = rows.first(where: { $0.item == nil && $0.rect.contains(p) }), tr.section != sd {
                var order = Prefs.sectionOrder; let a = sections[sd].key, b = sections[tr.section].key
                if let ia = order.firstIndex(of: a), let ib = order.firstIndex(of: b) { order.swapAt(ia, ib); Prefs.sectionOrder = order; sectionDragging = tr.section; reload() ; pressed = rows.firstIndex { $0.item == nil && $0.section == tr.section } }
            }
        }
    }
    override func mouseUp(with e: NSEvent) {
        defer { pressed = nil; sectionDragging = nil; needsDisplay = true }
        let p = convert(e.locationInWindow, from: nil)
        guard let ri = rowIndex(at: p), ri == pressed else { return }
        let row = rows[ri]
        if let ii = row.item {
            let it = sections[row.section].items[ii]
            if let ej = it.eject, p.x > bounds.width - 30 { FileOps.shared.eject(ej); return }
            if let sec = it.secondary, it.id.hasPrefix("bonjour") { if let u = URL(string: sec) { NSWorkspace.shared.open(u) }; return }
            host?.sidebarNavigate(it.location, newWindow: e.modifierFlags.contains(.command))
        } else {
            var c = Prefs.sidebarCollapsed; let k = sections[row.section].key
            if c.contains(k) { c.remove(k) } else { c.insert(k) }; Prefs.sidebarCollapsed = c; reload()
        }
    }
    override func menu(for e: NSEvent) -> NSMenu? {
        let p = convert(e.locationInWindow, from: nil)
        guard let ri = rowIndex(at: p), let ii = rows[ri].item else { return nil }
        let it = sections[rows[ri].section].items[ii]
        let m = NSMenu()
        func add(_ t: String, _ f: @escaping () -> Void) { let i = NSMenuItem(title: t, action: #selector(menuRun(_:)), keyEquivalent: ""); i.target = self; i.representedObject = f as AnyObject; m.addItem(i) }
        add(L("In neuem Fenster öffnen", "Open in New Window")) { self.host?.sidebarNavigate(it.location, newWindow: true) }
        if case .folder(let u) = it.location { add(L("Informationen", "Get Info")) { self.host?.sidebarInfo(u) } }
        if let ej = it.eject { add(L("Auswerfen", "Eject")) { FileOps.shared.eject(ej) } }
        if it.removable || it.id.hasPrefix("fav:") || it.id.hasPrefix("saved:") { m.addItem(.separator()); add(L("Aus der Seitenleiste entfernen", "Remove from Sidebar")) { self.remove(it) } }
        return m
    }
    @objc func menuRun(_ s: NSMenuItem) { (s.representedObject as? () -> Void)?() }
    func remove(_ it: SideItem) {
        if it.id.hasPrefix("u:") { Prefs.favorites = Prefs.favorites.filter { "u:" + $0 != it.id } }
        else if it.id.hasPrefix("fav:") { var h = SidebarView.hidden(); h.insert(it.id); Prefs.sidebarHidden = h }
        else if it.id.hasPrefix("saved:") { UserDefaults.standard.set((UserDefaults.standard.stringArray(forKey: "sideSaved") ?? []).filter { "saved:" + $0 != it.id }, forKey: "sideSaved") }
        reload()
    }
    func addFavorite(_ u: URL, at index: Int? = nil) {
        guard !Prefs.favorites.contains(u.path) else { return }
        var f = Prefs.favorites; f.append(u.path); Prefs.favorites = f; reload()
    }

    // MARK: Drag & Drop
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { draggingUpdated(s) }
    override func draggingExited(_ s: NSDraggingInfo?) { dropTarget = nil; dropInsert = nil; needsDisplay = true }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation {
        let p = convert(s.draggingLocation, from: nil)
        dropTarget = nil; dropInsert = nil
        defer { needsDisplay = true }
        let internal_ = s.draggingPasteboard.types?.contains(SidebarView.internalType) == true
        guard let ri = rowIndex(at: p) else { return [] }
        let row = rows[ri]
        if internal_ || (row.item == nil || sections[row.section].key == "fav") && !internal_ && urls(s).allSatisfy({ isDir($0) }) && (row.item == nil || p.y.truncatingRemainder(dividingBy: M.sideRowH) < 5) {
            if sections[row.section].key == "fav" { dropInsert = (row.section, row.item ?? 0); return internal_ ? .move : .link }
        }
        if let ii = row.item, case .folder(let u) = sections[row.section].items[ii].location {
            dropTarget = ri
            return operation(s, to: u)
        }
        if let ii = row.item, sections[row.section].items[ii].id == "fav:trash" { dropTarget = ri; return .move }
        return []
    }
    private func urls(_ s: NSDraggingInfo) -> [URL] { (s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? [] }
    private func isDir(_ u: URL) -> Bool { (try? u.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]))?.isDirectory == true }
    private func operation(_ s: NSDraggingInfo, to dir: URL) -> NSDragOperation {
        let f = NSEvent.modifierFlags
        if f.contains(.control) && f.contains(.option) { return .link }
        if f.contains(.option) { return .copy }
        if f.contains(.command) { return .move }
        let us = urls(s); guard let first = us.first else { return [] }
        let sameVol = (try? first.resourceValues(forKeys: [.volumeURLKey]).volume) == (try? dir.resourceValues(forKeys: [.volumeURLKey]).volume)
        return sameVol ? .move : .copy
    }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let p = convert(s.draggingLocation, from: nil)
        defer { dropTarget = nil; dropInsert = nil; needsDisplay = true }
        if let str = s.draggingPasteboard.string(forType: SidebarView.internalType), let ins = dropInsert {   // Umordnen
            let parts = str.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2, sections[parts[0]].key == "fav" {
                var ids = sections[ins.section].items.map { $0.id.hasPrefix("fav:") ? String($0.id.dropFirst(4)) : $0.id }
                let moved = ids.remove(at: parts[1]); ids.insert(moved, at: min(max(0, ins.index - (parts[1] < ins.index ? 1 : 0)), ids.count))
                UserDefaults.standard.set(ids, forKey: "favOrder"); reload(); return true
            }
        }
        if let ins = dropInsert, sections[ins.section].key == "fav" { for u in urls(s) where isDir(u) { addFavorite(u) }; return true }
        guard let ri = rowIndex(at: p), let ii = rows[ri].item else { return false }
        let it = sections[rows[ri].section].items[ii]
        if it.id == "fav:trash" { FileOps.shared.trash(urls(s)); return true }
        guard case .folder(let u) = it.location else { return false }
        host?.sidebarDrop(urls(s), to: u, flags: NSEvent.modifierFlags); return true
    }
}

extension SidebarView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? [.move, .copy, .link, .generic] : [.copy, .link, .generic] }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // Heraus aus der Seitenleiste ziehen entfernt den Eintrag (Rauchwolke)
        guard operation == [] , let w = window else { return }
        let r = w.convertFromScreen(NSRect(origin: screenPoint, size: .zero)); let p = convert(r.origin, from: nil)
        if !bounds.contains(p) {
            // welcher Eintrag? ursprünglicher Pasteboardeintrag
            if let str = session.draggingPasteboard.string(forType: SidebarView.internalType) {
                let parts = str.split(separator: ":").compactMap { Int($0) }
                if parts.count == 2, parts[0] < sections.count, parts[1] < sections[parts[0]].items.count {
                    let it = sections[parts[0]].items[parts[1]]
                    if it.id.hasPrefix("u:") || it.id.hasPrefix("fav:") || it.id.hasPrefix("saved:") { NSAnimationEffect.poof.show(centeredAt: screenPoint, size: .zero); remove(it) }
                }
            }
        }
    }
}
