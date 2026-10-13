import AppKit

// MARK: Finder-Einstellungen (E-01…E-04)

final class PreferencesWindow: NSObject {
    static let shared = PreferencesWindow()
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let tabs = PrefTabs()
    var content = NSView()
    var tab = 0
    var fields: [NSTextField] = []
    let customPane = CustomIconsPane()

    override init() {
        super.init()
        win.isReleasedWhenClosed = false
        tabs.onSelect = { [weak self] i in self?.select(i) }
    }
    func show() { select(UserDefaults.standard.integer(forKey: "prefTab")); win.center(); win.makeKeyAndOrderFront(nil) }
    func select(_ i: Int) {
        tab = i; UserDefaults.standard.set(i, forKey: "prefTab")
        tabs.selected = i; tabs.needsDisplay = true
        let titles = [L("Allgemein", "General"), L("Etiketten", "Labels"), L("Seitenleiste", "Sidebar"), L("Erweitert", "Advanced"), "X-Modus", "Custom Icons"]
        win.title = titles[i]
        let body: NSView
        switch i { case 0: body = general(); case 1: body = labels(); case 2: body = sidebarPane(); case 4: body = xmode(); case 5: body = customPane.build(); default: body = advanced() }
        let size = NSSize(width: 480, height: 66 + body.frame.height)
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        tabs.frame = NSRect(x: 0, y: size.height - 66, width: 480, height: 66); body.frame.origin = .zero
        root.addSubview(body); root.addSubview(tabs)
        win.setContentSize(size); win.contentView = root
    }

    // Hilfen
    private func label(_ s: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 260, bold: Bool = false, align: NSTextAlignment = .left) -> NSTextField { let t = NSTextField(labelWithString: s); t.font = lucida(12, bold: bold); t.frame = NSRect(x: x, y: y, width: w, height: 17); t.alignment = align; return t }
    private func check(_ s: String, _ on: Bool, _ x: CGFloat, _ y: CGFloat, _ f: @escaping (Bool) -> Void) -> NSButton {
        let b = NSButton(checkboxWithTitle: s, target: nil, action: nil); b.font = lucida(12); b.state = on ? .on : .off; b.frame = NSRect(x: x, y: y, width: 330, height: 18)
        let h = ActionHandler { [weak b] in if let b { f(b.state == .on) } }; objc_setAssociatedObject(b, &handlerKey, h, .OBJC_ASSOCIATION_RETAIN); b.target = h; b.action = #selector(ActionHandler.run); return b
    }
    private func popup(_ items: [String], _ sel: Int, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ f: @escaping (Int) -> Void) -> NSPopUpButton {
        let p = NSPopUpButton(frame: NSRect(x: x, y: y, width: w, height: 22), pullsDown: false); p.font = lucida(12); p.addItems(withTitles: items); p.selectItem(at: sel)
        let h = ActionHandler { [weak p] in if let p { f(p.indexOfSelectedItem) } }; objc_setAssociatedObject(p, &handlerKey, h, .OBJC_ASSOCIATION_RETAIN); p.target = h; p.action = #selector(ActionHandler.run); return p
    }
    private func refresh() { BrowserController.all.forEach { $0.reload(); $0.itemView?.reload() } }

    func general() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 440)); var y: CGFloat = 408
        v.addSubview(label(L("Auf dem Schreibtisch anzeigen:", "Show these items on the Desktop:"), 24, y, 300, bold: true)); y -= 24
        for (t, k) in [(L("Festplatten", "Hard disks"), "deskHD"), (L("Externe Festplatten", "External disks"), "deskExt"), (L("CDs, DVDs und iPods", "CDs, DVDs, and iPods"), "deskOpt"), (L("Verbundene Server", "Connected servers"), "deskSrv")] {
            v.addSubview(check(t, Prefs.bool(k, k == "deskHD" || k == "deskSrv"), 44, y, { UserDefaults.standard.set($0, forKey: k) })); y -= 22
        }
        y -= 6
        v.addSubview(label(L("Neue Finder-Fenster zeigen:", "New Finder windows show:"), 24, y + 3, 200, bold: true))
        let targets = ["allfiles", "home", "computer", "path:" + Files.documents.path, "path:" + Files.desktop.path]
        let names = [L("Alle meine Dateien", "All My Files"), L("Benutzerordner", "Home"), L("Computer", "Computer"), L("Dokumente", "Documents"), L("Schreibtisch", "Desktop"), L("Anderes …", "Other…")]
        var sel = targets.firstIndex(of: Prefs.newWindowTarget) ?? (Prefs.newWindowTarget.hasPrefix("path:") ? 5 : 1)
        if sel > 5 { sel = 5 }
        v.addSubview(popup(names, sel, 230, y, 200) { i in
            if i < targets.count { Prefs.newWindowTarget = targets[i] }
            else { let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; if p.runModal() == .OK, let u = p.url { Prefs.newWindowTarget = "path:" + u.path } }
        }); y -= 32
        v.addSubview(check(L("Ordner in neuen Fenstern öffnen", "Always open folders in a new window"), Prefs.foldersInNewWindow, 24, y, { Prefs.foldersInNewWindow = $0 })); y -= 22
        v.addSubview(check(L("Ordner beim Ziehen automatisch öffnen", "Spring-loaded folders and windows"), Prefs.springLoading, 24, y, { Prefs.springLoading = $0 })); y -= 26
        v.addSubview(label(L("Wartezeit:", "Delay:"), 44, y, 60))
        let s = NSSlider(value: Prefs.springDelay, minValue: 0.2, maxValue: 2.0, target: nil, action: nil); s.frame = NSRect(x: 110, y: y - 2, width: 200, height: 20); s.controlSize = .small
        let h = ActionHandler { Prefs.springDelay = s.doubleValue }; objc_setAssociatedObject(s, &handlerKey, h, .OBJC_ASSOCIATION_RETAIN); s.target = h; s.action = #selector(ActionHandler.run); v.addSubview(s)
        v.addSubview(label(L("Kurz", "Short"), 110, y - 18, 40)); v.addSubview(label(L("Lang", "Long"), 270, y - 18, 40, align: .right)); y -= 40
        v.addSubview(label(L("Dateiansicht:", "File display:"), 24, y, 300, bold: true)); y -= 24
        for (t, get, set) in [(L("Ordner „Benutzer ▸ Library“ anzeigen", "Show the user \u{201C}Library\u{201D} folder"), Prefs.showLibrary, { (b: Bool) in Prefs.showLibrary = b }), (L("Versteckte Dateien anzeigen", "Show hidden files"), Prefs.showHidden, { (b: Bool) in Prefs.showHidden = b }), (L("Ordner immer oben anzeigen", "Always show folders on top"), Prefs.foldersFirst, { (b: Bool) in Prefs.foldersFirst = b })] as [(String, Bool, (Bool) -> Void)] {
            v.addSubview(check(t, get, 44, y) { set($0); BrowserController.all.forEach { $0.reload(); $0.rightPane?.reload() } }); y -= 24
        }
        v.addSubview(check(L("Eine Ansicht für alle Ordner (global)", "One view for all folders (global)"), Prefs.globalView, 44, y) { BrowserController.setGlobalView($0, from: BrowserController.all.first(where: { $0.win.isKeyWindow }) ?? BrowserController.all.first) }); y -= 24
        y -= 10
        v.addSubview(label(L("Terminal-Programm:", "Terminal app:"), 24, y + 3, 150, bold: true))
        let apps = TerminalApp.installed()
        v.addSubview(popup(apps.map { $0.name } + [L("Anderes …", "Other…")], apps.firstIndex { $0.id == Prefs.terminalApp } ?? 0, 180, y, 200) { i in
            if i < apps.count { Prefs.terminalApp = apps[i].id }
            else { let pn = NSOpenPanel(); pn.directoryURL = Files.applications; pn.allowedContentTypes = [.application]; if pn.runModal() == .OK, let u = pn.url, let id = Bundle(url: u)?.bundleIdentifier { Prefs.terminalApp = id } ; self.select(0) }
        })
        return v
    }

    func labels() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 290))
        v.addSubview(label(L("Namen der Etiketten:", "Use these label names:"), 120, 258, 320, bold: true)); fields = []
        for i in 1...7 {
            let y = 258 - CGFloat(i) * 32
            let sw = SwatchBar(frame: NSRect(x: 40, y: y, width: 70, height: 22)); sw.color = i - 1; v.addSubview(sw)
            let f = NSTextField(string: Labels.name(i)); f.frame = NSRect(x: 120, y: y, width: 300, height: 22); f.font = lucida(12); f.tag = i
            f.delegate = self; f.bezelStyle = .roundedBezel; v.addSubview(f); fields.append(f)
        }
        return v
    }

    func sidebarPane() -> NSView {
        let cat = SidebarView.catalog()
        let rows = cat.reduce(0) { $0 + $1.items.count + 1 } + 2
        let h = CGFloat(rows) * 22 + 40
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: h)); var y = h - 30
        v.addSubview(label(L("Diese Objekte in der Seitenleiste zeigen:", "Show these items in the Sidebar:"), 24, y, 400, bold: true)); y -= 8
        y -= 24; v.addSubview(check(L("Farbige Symbole verwenden", "Use colored icons"), Prefs.coloredIcons, 24, y) { Prefs.coloredIcons = $0; BrowserController.all.forEach { $0.sidebar.needsDisplay = true } }); y -= 8
        let hid = SidebarView.hidden()
        for sec in cat {
            y -= 22; v.addSubview(label(sec.title, 30, y, 300, bold: true))
            for it in sec.items {
                y -= 22
                let isSearch = it.id == "search:defaults"
                let on = isSearch ? UserDefaults.standard.bool(forKey: "showSearchSection") : !hid.contains(it.id)
                v.addSubview(check(it.title, on, 50, y) { newOn in
                    if isSearch { UserDefaults.standard.set(newOn, forKey: "showSearchSection") }
                    else { var s = SidebarView.hidden(); if newOn { s.remove(it.id) } else { s.insert(it.id) }; Prefs.sidebarHidden = s }
                    BrowserController.all.forEach { $0.sidebar.reload() }
                })
            }
        }
        return v
    }

    func advanced() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 410)); var y: CGFloat = 378
        v.addSubview(check(L("Alle Dateinamen-Erweiterungen einblenden", "Show all filename extensions"), Prefs.showExtensions, 24, y) { Prefs.showExtensions = $0; self.refresh() }); y -= 24
        v.addSubview(check(L("Vor dem Ändern einer Erweiterung warnen", "Show warning before changing an extension"), Prefs.warnExt, 24, y) { Prefs.warnExt = $0 }); y -= 24
        v.addSubview(check(L("Vor dem Entleeren des Papierkorbs warnen", "Show warning before emptying the Trash"), Prefs.warnTrash, 24, y) { Prefs.warnTrash = $0 }); y -= 24
        let sec = check(L("Papierkorb sicher entleeren", "Empty Trash securely"), Prefs.secureEmpty, 24, y) { Prefs.secureEmpty = $0 }; v.addSubview(sec); y -= 18
        v.addSubview({ let t = label(L("Hinweis: Auf APFS/SSD nicht garantierbar – wird als nicht unterstützt behandelt.", "Note: not guaranteeable on APFS/SSD – treated as unsupported."), 44, y, 420); t.font = lucida(10); t.textColor = .secondaryLabelColor; return t }()); y -= 32
        v.addSubview(label(L("Bei einer Suche:", "When performing a search:"), 24, y + 3, 215, bold: true))
        let scopes = ["this", "folder", "previous"]
        v.addSubview(popup([L("Dieser Mac durchsuchen", "Search This Mac"), L("Aktuellen Ordner durchsuchen", "Search the Current Folder"), L("Letzten Suchbereich verwenden", "Use the Previous Search Scope")], scopes.firstIndex(of: Prefs.searchScope) ?? 0, 240, y, 220) { Prefs.searchScope = scopes[$0] }); y -= 38
        v.addSubview(label(L("Sprache (nach Neustart):", "Language (after restart):"), 24, y + 3, 170, bold: true))
        v.addSubview(popup(["Deutsch", "English"], Lang.de ? 0 : 1, 190, y, 160) { UserDefaults.standard.set($0 == 0 ? "de" : "en", forKey: "lang") }); y -= 114
        v.addSubview(label(L("Fensterknöpfe:", "Window buttons:"), 24, y + 80, 120, bold: true))
        v.addSubview(popup([L("System-Ampel", "System traffic lights"), L("Aqua Glow (Originaloptik)", "Aqua Glow (original look)")], Prefs.aquaLights ? 1 : 0, 150, y + 77, 220) { Prefs.aquaLights = $0 == 1; BrowserController.all.forEach { $0.win.placeLights(); $0.layoutAll(); $0.chrome.needsDisplay = true } })
        // Programmsymbol (PNG 256×256)
        v.addSubview(label(L("Programmsymbol:", "App icon:"), 24, y + 30, 150, bold: true))
        let iv = NSImageView(frame: NSRect(x: 190, y: y, width: 64, height: 64)); iv.imageScaling = .scaleProportionallyUpOrDown
        iv.image = AppIcon.hasCustom ? NSImage(contentsOf: AppIcon.file) : NSApp.applicationIconImage; v.addSubview(iv)
        let choose = NSButton(title: L("PNG wählen …", "Choose PNG…"), target: nil, action: nil); choose.bezelStyle = .rounded; choose.frame = NSRect(x: 270, y: y + 34, width: 150, height: 26)
        let h1 = ActionHandler { [weak self] in if AppIcon.choose() { self?.select(3) } }; objc_setAssociatedObject(choose, &handlerKey, h1, .OBJC_ASSOCIATION_RETAIN); choose.target = h1; choose.action = #selector(ActionHandler.run)
        let reset = NSButton(title: L("Zurücksetzen", "Reset"), target: nil, action: nil); reset.bezelStyle = .rounded; reset.frame = NSRect(x: 270, y: y + 4, width: 150, height: 26); reset.isEnabled = AppIcon.hasCustom
        let h2 = ActionHandler { [weak self] in AppIcon.reset(); self?.select(3) }; objc_setAssociatedObject(reset, &handlerKey, h2, .OBJC_ASSOCIATION_RETAIN); reset.target = h2; reset.action = #selector(ActionHandler.run)
        v.addSubview(choose); v.addSubview(reset)
        v.addSubview({ let t = label(L("Genau 256 × 256 Pixel, PNG.", "Exactly 256 × 256 pixels, PNG."), 190, y - 18, 280); t.font = lucida(10); t.textColor = .secondaryLabelColor; return t }())
        return v
    }

    func xmode() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 270)); var y: CGFloat = 236
        let main = check(L("X-Modus aktivieren", "Enable X-Mode"), Prefs.xMode, 24, y) { Prefs.xMode = $0; BrowserController.applyXModeAll(); self.select(4) }
        main.font = lucida(12, bold: true); v.addSubview(main); y -= 20
        v.addSubview({ let t = label(L("Erweitert den Finder um Tabs oder einen Dual-Pane-Modus (entweder – oder).", "Extends the Finder with tabs or a dual-pane mode (either – or)."), 44, y, 420); t.font = lucida(10); t.textColor = .secondaryLabelColor; return t }()); y -= 30
        // Radio-Auswahl: Tabs ODER Dual Pane
        let r1 = NSButton(radioButtonWithTitle: L("Tabs  (⌘T neu, ⌘W schließen, ⇧⌘[ / ⇧⌘] wechseln)", "Tabs  (⌘T new, ⌘W close, ⇧⌘[ / ⇧⌘] switch)"), target: nil, action: nil)
        let r2 = NSButton(radioButtonWithTitle: L("Dual Pane  (zwei Fenster nebeneinander, ⌥⌘P)", "Dual Pane  (two panes side by side, ⌥⌘P)"), target: nil, action: nil)
        for (r, yy) in [(r1, y), (r2, y - 24)] { r.font = lucida(12); r.frame = NSRect(x: 44, y: yy, width: 420, height: 20); r.isEnabled = Prefs.xMode; v.addSubview(r) }
        r1.state = Prefs.xTabs ? .on : .off; r2.state = Prefs.xDual ? .on : .off
        let h1 = ActionHandler { Prefs.xKind = "tabs"; r1.state = .on; r2.state = .off; BrowserController.applyXModeAll() }
        let h2 = ActionHandler { Prefs.xKind = "dual"; r1.state = .off; r2.state = .on; BrowserController.applyXModeAll() }
        objc_setAssociatedObject(r1, &handlerKey, h1, .OBJC_ASSOCIATION_RETAIN); r1.target = h1; r1.action = #selector(ActionHandler.run)
        objc_setAssociatedObject(r2, &handlerKey, h2, .OBJC_ASSOCIATION_RETAIN); r2.target = h2; r2.action = #selector(ActionHandler.run)
        y -= 62
        let hint = label(L("Dual Pane: Fußleiste mit F5 Kopieren, F6 Verschieben, F7 Neuer Ordner, F8 Löschen (Tasten und Schaltflächen); die Tab-Taste wechselt die aktive Hälfte.", "Dual pane: footer with F5 Copy, F6 Move, F7 New Folder, F8 Delete (keys and buttons); the Tab key switches the active pane."), 44, y - 16, 410)
        hint.font = lucida(10); hint.textColor = .secondaryLabelColor; hint.maximumNumberOfLines = 3; hint.lineBreakMode = .byWordWrapping; hint.frame.size.height = 44; v.addSubview(hint)
        let q = check(L("Kopieren/Verschieben über Warteschlange (F5, F6, Einsetzen)", "Copy/move through the transfer queue (F5, F6, Paste)"), Prefs.xQueue, 24, 40) { Prefs.xQueue = $0 }
        q.frame.size.width = 440; q.isEnabled = Prefs.xMode; v.addSubview(q)
        let qh = label(L("Warteschlange anzeigen: ⌥⌘Q · Mehrfach-Umbenennen: ⌥⌘R", "Show queue: ⌥⌘Q · Batch rename: ⌥⌘R"), 44, 18, 420); qh.font = lucida(10); qh.textColor = .secondaryLabelColor; v.addSubview(qh)
        return v
    }
}

extension PreferencesWindow: NSTextFieldDelegate {
    func controlTextDidChange(_ n: Notification) {
        var names = (UserDefaults.standard.stringArray(forKey: "labelNames")) ?? (1...7).map { Labels.name($0) }
        if names.count != 7 { names = (1...7).map { Labels.name($0) } }
        for f in fields { names[f.tag - 1] = f.stringValue }
        Labels.setNames(names); BrowserController.all.forEach { $0.itemView?.needsDisplay = true }
    }
}

final class SwatchBar: NSView {
    var color = 0
    override var isFlipped: Bool { true }
    override func draw(_ r: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11)
        gradient([(0, C.labelFill[color].blended(withFraction: 0.45, of: .white) ?? .white), (1, C.labelFill[color])]).draw(in: p, angle: 90); C.labelPillBorder[color].setStroke(); p.stroke()
    }
}

/// Symbolleiste des Einstellungsfensters (Allgemein / Etiketten / Seitenleiste / Erweitert)
final class PrefTabs: NSView {
    var selected = 0; var onSelect: ((Int) -> Void)?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private func rect(_ i: Int) -> NSRect { NSRect(x: 480 / 2 - 210 + CGFloat(i) * 70, y: 4, width: 70, height: 58) }
    override func draw(_ r: NSRect) {
        gradient([(0, NSColor(gray: 240)), (1, NSColor(gray: 205))]).draw(in: bounds, angle: 90)
        NSColor(gray: 130).setFill(); NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        let titles = [L("Allgemein", "General"), L("Etiketten", "Labels"), L("Seitenleiste", "Sidebar"), L("Erweitert", "Advanced"), "X-Modus", "Custom Icons"]
        for i in 0..<6 {
            let rr = rect(i)
            if i == selected { NSColor(0, 0, 0, 0.14).setFill(); NSBezierPath(roundedRect: rr.insetBy(dx: 2, dy: 1), xRadius: 5, yRadius: 5).fill() }
            let c = NSPoint(x: rr.midX, y: rr.minY + 22)
            switch i {
            case 0:   // Schalterbrett
                NSColor(gray: 80).setFill(); let p = NSBezierPath(roundedRect: NSRect(x: c.x - 13, y: c.y - 15, width: 26, height: 30), xRadius: 3, yRadius: 3); gradient([(0, NSColor(gray: 215)), (1, NSColor(gray: 150))]).draw(in: p, angle: 90); NSColor(gray: 90).setStroke(); p.stroke()
                NSColor(70, 110, 190).setFill(); NSBezierPath(roundedRect: NSRect(x: c.x - 9, y: c.y - 11, width: 18, height: 12), xRadius: 2, yRadius: 2).fill()
            case 1:   // Etikett-Blase
                let p = NSBezierPath(roundedRect: NSRect(x: c.x - 16, y: c.y - 8, width: 32, height: 17), xRadius: 8.5, yRadius: 8.5); gradient([(0, NSColor(150, 200, 250)), (1, NSColor(60, 130, 220))]).draw(in: p, angle: 90); NSColor(50, 110, 200).setStroke(); p.stroke()
            case 2:   // Fenster mit Seitenleiste
                let p = NSBezierPath(roundedRect: NSRect(x: c.x - 15, y: c.y - 14, width: 30, height: 28), xRadius: 3, yRadius: 3); NSColor.white.setFill(); p.fill(); NSColor(gray: 90).setStroke(); p.stroke(); NSColor(200, 210, 225).setFill(); NSRect(x: c.x - 14, y: c.y - 13, width: 10, height: 26).fill()
            case 4:   // X-Modus: zwei Fenster
                for dx in [-14.0, 1.0] as [CGFloat] { let q = NSBezierPath(roundedRect: NSRect(x: c.x + dx, y: c.y - 13, width: 13, height: 26), xRadius: 2, yRadius: 2); NSColor.white.setFill(); q.fill(); NSColor(gray: 90).setStroke(); q.stroke() }
                NSColor(60, 100, 170).setFill(); NSRect(x: c.x - 13, y: c.y - 12, width: 11, height: 4).fill(); NSRect(x: c.x + 2, y: c.y - 12, width: 11, height: 4).fill()
            case 5:   // Custom Icons: Bildraster
                for (dx, dy) in [(-13.0, -12.0), (1.0, -12.0), (-13.0, 2.0), (1.0, 2.0)] as [(CGFloat, CGFloat)] { let q = NSBezierPath(roundedRect: NSRect(x: c.x + dx, y: c.y + dy, width: 12, height: 11), xRadius: 2, yRadius: 2); NSColor(150, 175, 215).setFill(); q.fill(); NSColor(gray: 90).setStroke(); q.stroke() }
            default:  // Zahnrad
                TB.gear(c, color: NSColor(gray: 90))
            }
            Draw.text(titles[i], in: NSRect(x: rr.minX, y: rr.maxY - 18, width: rr.width, height: 14), font: lucida(11), color: .black, align: .center)
        }
    }
    override func mouseDown(with e: NSEvent) { let p = convert(e.locationInWindow, from: nil); for i in 0..<6 where rect(i).contains(p) { onSelect?(i) } }
}
