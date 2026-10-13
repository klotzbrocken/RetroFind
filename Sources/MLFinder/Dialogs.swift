import AppKit

// MARK: Gehe zum Ordner / Mit Server verbinden (N-07, X-03)

enum Dialogs {
    static func goToFolder(window: NSWindow, _ done: @escaping (URL) -> Void) {
        let a = NSAlert(); a.messageText = L("Gehe zum Ordner:", "Go to the folder:")
        a.informativeText = L("Geben Sie den Pfad zum Ordner ein, z. B. /Library oder ~/Documents.", "Type the pathname of the folder, e.g. /Library or ~/Documents.")
        let f = PathField(frame: NSRect(x: 0, y: 0, width: 320, height: 22)); f.stringValue = "/"; f.font = lucida(12)
        a.accessoryView = f; a.addButton(withTitle: L("Öffnen", "Go")); a.addButton(withTitle: L("Abbrechen", "Cancel"))
        a.window.initialFirstResponder = f
        a.beginSheetModal(for: window) { r in
            guard r == .alertFirstButtonReturn else { return }
            let raw = f.stringValue.trimmingCharacters(in: .whitespaces)
            var p = (raw as NSString).expandingTildeInPath
            if !p.hasPrefix("/") { p = Files.home.appendingPathComponent(p).path }
            var isDir: ObjCBool = false
            if Files.fm.fileExists(atPath: p, isDirectory: &isDir) { done(URL(fileURLWithPath: p).standardizedFileURL) }
            else { let e = NSAlert(); e.messageText = L("Der Ordner „\(raw)“ konnte nicht gefunden werden.", "The folder can\u{2019}t be found."); e.informativeText = L("Prüfen Sie den Pfad und versuchen Sie es erneut.", "Check the spelling and try again."); e.addButton(withTitle: "OK"); e.beginSheetModal(for: window, completionHandler: nil) }
        }
    }

    static func connect(window: NSWindow, from: BrowserController) {
        let sheet = ConnectSheet(from: from); sheet.present(on: window)
    }
}

/// Pfadfeld mit Ergänzung per Tab/Esc (Ergänzungsvorschläge aus dem Dateisystem)
final class PathField: NSTextField, NSTextFieldDelegate {
    override init(frame: NSRect) { super.init(frame: frame); delegate = self }
    required init?(coder: NSCoder) { fatalError() }
    func control(_ control: NSControl, textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
        let s = (textView.string as NSString)
        let expanded = (s as String as NSString).expandingTildeInPath
        let dir = (expanded as NSString).deletingLastPathComponent.isEmpty ? "/" : (expanded as NSString).deletingLastPathComponent
        let prefix = (expanded as NSString).lastPathComponent
        let kids = ((try? Files.fm.contentsOfDirectory(atPath: dir)) ?? []).filter { !$0.hasPrefix(".") && $0.lowercased().hasPrefix(prefix.lowercased()) }.sorted()
        let base = (s as NSString).deletingLastPathComponent
        index.pointee = -1
        return kids.map { (base.isEmpty ? "/" : (base == "/" ? "/" : base + "/")) + $0 }.map { $0 }
    }
    func controlTextDidChange(_ obj: Notification) {
        if let tv = currentEditor() as? NSTextView, !tv.string.isEmpty, NSApp.currentEvent?.keyCode != 51 { tv.complete(nil) }
    }
}

final class ConnectSheet: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let from: BrowserController
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
    let field = NSTextField(); let table = NSTableView(); var parent: NSWindow?
    init(from: BrowserController) { self.from = from; super.init() }
    func present(on w: NSWindow) {
        parent = w
        let v = win.contentView!
        let l1 = NSTextField(labelWithString: L("Serveradresse:", "Server Address:")); l1.frame = NSRect(x: 20, y: 264, width: 400, height: 17); l1.font = lucida(12, bold: true)
        field.frame = NSRect(x: 20, y: 236, width: 400, height: 22); field.placeholderString = "smb://server/freigabe"; field.font = lucida(12)
        let l2 = NSTextField(labelWithString: L("Bevorzugte Server:", "Favorite Servers:")); l2.frame = NSRect(x: 20, y: 212, width: 400, height: 17); l2.font = lucida(11); l2.textColor = .secondaryLabelColor
        let sc = NSScrollView(frame: NSRect(x: 20, y: 64, width: 400, height: 142)); sc.hasVerticalScroller = true; sc.borderType = .bezelBorder
        let col = NSTableColumn(identifier: .init("s")); col.width = 380; table.addTableColumn(col); table.headerView = nil; table.dataSource = self; table.delegate = self; table.doubleAction = #selector(pick); table.target = self; table.rowHeight = 18
        sc.documentView = table
        let add = NSButton(title: "+", target: self, action: #selector(addFav)); add.frame = NSRect(x: 20, y: 36, width: 28, height: 24); add.bezelStyle = .smallSquare
        let rem = NSButton(title: "−", target: self, action: #selector(removeFav)); rem.frame = NSRect(x: 48, y: 36, width: 28, height: 24); rem.bezelStyle = .smallSquare
        let browse = NSButton(title: L("Durchsuchen", "Browse"), target: self, action: #selector(browse)); browse.frame = NSRect(x: 190, y: 12, width: 100, height: 24); browse.bezelStyle = .rounded
        let cancel = NSButton(title: L("Abbrechen", "Cancel"), target: self, action: #selector(cancel)); cancel.frame = NSRect(x: 296, y: 12, width: 60, height: 24); cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: L("Verbinden", "Connect"), target: self, action: #selector(connect)); ok.frame = NSRect(x: 360, y: 12, width: 70, height: 24); ok.bezelStyle = .rounded; ok.keyEquivalent = "\r"
        [l1, field, l2, sc, add, rem, browse, cancel, ok].forEach { v.addSubview($0) }
        w.beginSheet(win, completionHandler: nil)
    }
    var servers: [String] { Prefs.servers }
    func numberOfRows(in t: NSTableView) -> Int { servers.count }
    func tableView(_ t: NSTableView, objectValueFor c: NSTableColumn?, row: Int) -> Any? { servers[row] }
    func tableViewSelectionDidChange(_ n: Notification) { if table.selectedRow >= 0 { field.stringValue = servers[table.selectedRow] } }
    @objc func pick() { if table.clickedRow >= 0 { field.stringValue = servers[table.clickedRow]; connect() } }
    @objc func addFav() { let s = field.stringValue.trimmingCharacters(in: .whitespaces); guard !s.isEmpty, !servers.contains(s) else { return }; Prefs.servers = servers + [s]; table.reloadData() }
    @objc func removeFav() { guard table.selectedRow >= 0 else { return }; var s = servers; s.remove(at: table.selectedRow); Prefs.servers = s; table.reloadData() }
    @objc func browse() { close(); from.navigate(.network) }
    @objc func cancel() { close() }
    func close() { parent?.endSheet(win); win.orderOut(nil) }
    /// X-03/X-04: smb://, afp://, vnc://, ftp://, http(s):// (WebDAV). Das System bindet Freigaben ein.
    @objc func connect() {
        var s = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        if !s.contains("://") { s = "smb://" + s }
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased(), ["smb", "afp", "vnc", "ftp", "http", "https", "nfs", "cifs"].contains(scheme) else {
            close(); FileOps.shared.alert(L("Die Serveradresse ist ungültig.", "The server address is not valid."), L("Verwenden Sie z. B. smb://server/freigabe.", "Use e.g. smb://server/share.")); return
        }
        close()
        var recent = Prefs.servers; if !recent.contains(s) { recent.append(s); Prefs.servers = recent }
        if scheme == "ftp" { FileOps.shared.alert(L("FTP-Server werden nur zum Lesen vom System eingebunden; das Schreiben ist – wie im Original – nicht möglich.", "FTP servers are not mounted for writing by the system, as in the original."), "") }
        NSWorkspace.shared.open(u)
    }
}

// MARK: Etikett-Zeile im Kontextmenü (I-11)

final class LabelRowView: NSView {
    weak var target: BrowserController?
    private var hover: Int?
    init(target: BrowserController) { self.target = target; super.init(frame: NSRect(x: 0, y: 0, width: 190, height: 46)); addTrackingArea(NSTrackingArea(rect: NSRect(x: 0, y: 0, width: 190, height: 46), options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self)) }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    private func rect(_ i: Int) -> NSRect { NSRect(x: 12 + CGFloat(i) * 23, y: 18, width: 16, height: 16) }
    override func draw(_ r: NSRect) {
        let t = hover.map { $0 == 0 ? L("Keines", "None") : Labels.name($0) } ?? L("Etikett:", "Label:")
        Draw.text(t, in: NSRect(x: 12, y: 3, width: 170, height: 14), font: lucida(11), color: NSColor(gray: 70))
        for i in 0...7 {
            let rr = rect(i)
            if i == 0 { NSColor(gray: 150).setStroke(); let p = NSBezierPath(ovalIn: rr.insetBy(dx: 1, dy: 1)); p.lineWidth = 1; p.stroke(); let x = NSBezierPath(); x.move(to: NSPoint(x: rr.minX + 4, y: rr.maxY - 4)); x.line(to: NSPoint(x: rr.maxX - 4, y: rr.minY + 4)); NSColor(gray: 160).setStroke(); x.stroke() }
            else { gradient([(0, C.labelFill[i - 1].blended(withFraction: 0.5, of: .white) ?? C.labelFill[i - 1]), (1, C.labelFill[i - 1])]).draw(in: NSBezierPath(ovalIn: rr), angle: 90); C.labelPillBorder[i - 1].setStroke(); NSBezierPath(ovalIn: rr.insetBy(dx: 0.5, dy: 0.5)).stroke() }
            if hover == i { NSColor(0, 0, 0, 0.35).setStroke(); let p = NSBezierPath(ovalIn: rr.insetBy(dx: -2, dy: -2)); p.lineWidth = 1.5; p.stroke() }
            // aktueller Zustand
            if let n = target?.selectedNodes, !n.isEmpty, n.allSatisfy({ $0.label == i }) { NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: rr.midX - 2, y: rr.midY - 2, width: 4, height: 4)).fill() }
        }
    }
    override func mouseMoved(with e: NSEvent) { let p = convert(e.locationInWindow, from: nil); let h = (0...7).first { rect($0).insetBy(dx: -3, dy: -3).contains(p) }; if h != hover { hover = h; needsDisplay = true } }
    override func mouseExited(with e: NSEvent) { hover = nil; needsDisplay = true }
    override func mouseUp(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if let i = (0...7).first(where: { rect($0).insetBy(dx: -3, dy: -3).contains(p) }) { target?.setLabel(i); enclosingMenuItem?.menu?.cancelTracking() }
    }
}

// MARK: Ablage anzeigen (F-20)

final class ClipboardWindow {
    static var win: NSWindow?
    static func show() {
        let w = win ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 260), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        w.title = L("Ablage", "Clipboard"); w.isReleasedWhenClosed = false
        let pb = NSPasteboard.general
        var text = ""
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty { text = L("Dateien:\n", "Files:\n") + urls.map { $0.path }.joined(separator: "\n") }
        else if let s = pb.string(forType: .string) { text = L("Text:\n", "Text:\n") + s }
        else if pb.canReadObject(forClasses: [NSImage.self], options: nil) { text = L("Bild in der Ablage", "Image on the clipboard") }
        else { text = L("Die Ablage ist leer.", "The Clipboard is empty.") }
        let sc = NSScrollView(frame: w.contentView!.bounds); sc.autoresizingMask = [.width, .height]; sc.hasVerticalScroller = true
        let tv = NSTextView(frame: sc.bounds); tv.isEditable = false; tv.string = text; tv.font = lucida(12); tv.autoresizingMask = [.width]
        sc.documentView = tv; w.contentView?.subviews.forEach { $0.removeFromSuperview() }; w.contentView?.addSubview(sc)
        win = w; w.center(); w.makeKeyAndOrderFront(nil)
    }
}

// MARK: Symbolleiste anpassen (N-12)

final class CustomizeSheet: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static var current: CustomizeSheet?
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 380), styleMask: [.titled], backing: .buffered, defer: false)
    let table = NSTableView(); var items: [String] = []; weak var parent: NSWindow?
    let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    static func show(from c: BrowserController) { let s = CustomizeSheet(); current = s; s.present(c.win) }
    func present(_ w: NSWindow) {
        parent = w; items = Prefs.toolbarItems
        let v = win.contentView!
        let h = NSTextField(wrappingLabelWithString: L("Wählen Sie die Objekte der Symbolleiste. Mit den Pfeilen ändern Sie die Reihenfolge.", "Choose the items for the toolbar. Use the arrows to change the order.")); h.frame = NSRect(x: 20, y: 334, width: 380, height: 34); h.font = lucida(11)
        let sc = NSScrollView(frame: NSRect(x: 20, y: 90, width: 300, height: 240)); sc.hasVerticalScroller = true; sc.borderType = .bezelBorder
        let c1 = NSTableColumn(identifier: .init("on")); c1.width = 30; let c2 = NSTableColumn(identifier: .init("name")); c2.width = 250
        table.addTableColumn(c1); table.addTableColumn(c2); table.headerView = nil; table.dataSource = self; table.delegate = self; table.rowHeight = 20; sc.documentView = table
        let up = NSButton(title: "↑", target: self, action: #selector(moveUp)); up.frame = NSRect(x: 330, y: 300, width: 60, height: 26); up.bezelStyle = .rounded
        let dn = NSButton(title: "↓", target: self, action: #selector(moveDown)); dn.frame = NSRect(x: 330, y: 268, width: 60, height: 26); dn.bezelStyle = .rounded
        let l = NSTextField(labelWithString: L("Zeigen:", "Show:")); l.frame = NSRect(x: 20, y: 58, width: 50, height: 17); l.font = lucida(11)
        popup.frame = NSRect(x: 72, y: 54, width: 180, height: 24); popup.addItems(withTitles: [L("Nur Symbol", "Icon Only"), L("Symbol und Text", "Icon & Text"), L("Nur Text", "Text Only")]); popup.selectItem(at: Prefs.toolbarMode)
        let def = NSButton(title: L("Standardsatz", "Default Set"), target: self, action: #selector(reset)); def.frame = NSRect(x: 20, y: 14, width: 110, height: 28); def.bezelStyle = .rounded
        let done = NSButton(title: L("Fertig", "Done"), target: self, action: #selector(finish)); done.frame = NSRect(x: 320, y: 14, width: 80, height: 28); done.bezelStyle = .rounded; done.keyEquivalent = "\r"
        [h, sc, up, dn, l, popup, def, done].forEach { v.addSubview($0) }
        w.beginSheet(win, completionHandler: nil)
    }
    var all: [String] { var r = items; for it in Toolbar.catalog where !items.contains(it.id) && it.id != "space" && it.id != "flex" { r.append(it.id) }; return r }
    func numberOfRows(in t: NSTableView) -> Int { all.count }
    func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let id = all[row]
        if col?.identifier.rawValue == "on" { let b = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggle(_:))); b.tag = row; b.state = items.contains(id) ? .on : .off; return b }
        let tf = NSTextField(labelWithString: id == "lead" ? L("Abstand (Seitenleistenbreite)", "Leading Space") : (Toolbar.item(id)?.title ?? id)); tf.font = lucida(12); return tf
    }
    @objc func toggle(_ s: NSButton) {
        let id = all[s.tag]
        if s.state == .on { if !items.contains(id) { items.append(id) } } else { items.removeAll { $0 == id } }
        table.reloadData()
    }
    func moveRow(_ d: Int) {
        let r = table.selectedRow; guard r >= 0 else { return }; let id = all[r]
        guard let i = items.firstIndex(of: id), i + d >= 0, i + d < items.count else { return }
        items.swapAt(i, i + d); table.reloadData(); if let n = all.firstIndex(of: id) { table.selectRowIndexes([n], byExtendingSelection: false) }
    }
    @objc func moveUp() { moveRow(-1) }
    @objc func moveDown() { moveRow(1) }
    @objc func reset() { items = Toolbar.defaultItems; popup.selectItem(at: 0); table.reloadData() }
    @objc func finish() {
        Prefs.toolbarItems = items.isEmpty ? ["search"] : items; Prefs.toolbarMode = popup.indexOfSelectedItem
        parent?.endSheet(win); win.orderOut(nil)
        BrowserController.all.forEach { $0.chrome.ids = Prefs.toolbarItems; $0.layoutAll(); $0.chrome.needsDisplay = true }
        CustomizeSheet.current = nil
    }
}

// MARK: Darstellungsoptionen (⌘J, A-01…A-04, A-10)

final class ViewOptionsPanel: NSObject {
    static let shared = ViewOptionsPanel()
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 380), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
    weak var c: BrowserController?
    override init() {
        super.init(); panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .locationChanged, object: nil)
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { [weak self] n in if let bc = (n.object as? NSWindow)?.windowController as? BrowserController, self?.panel.isVisible == true { self?.c = bc; self?.build() } }
    }
    func show(for c: BrowserController) { self.c = c; build(); panel.makeKeyAndOrderFront(nil) }
    @objc func refresh() { if panel.isVisible { c = BrowserController.all.first { $0.win.isMainWindow } ?? c; build() } }
    private var opts: ViewOptions { c?.options ?? ViewOptions() }
    private func set(_ f: (inout ViewOptions) -> Void) { guard let c else { return }; var o = c.options; f(&o); c.options = o; c.itemView?.applyOptions(); c.viewStateChanged(); c.updateStatus() }

    func build() {
        guard let c else { return }
        panel.title = c.location.title + " " + L("Darstellungsoptionen", "View Options")
        let v = NSView(frame: panel.contentRect(forFrameRect: panel.frame)); var y: CGFloat = 0
        var views: [NSView] = []
        func label(_ t: String, bold: Bool = false) -> NSTextField { let l = NSTextField(labelWithString: t); l.font = lucida(11, bold: bold); return l }
        func row(_ l: String, _ ctl: NSView, h: CGFloat = 22) { let lab = label(l); lab.frame = NSRect(x: 12, y: y + 3, width: 100, height: 16); lab.alignment = .right; ctl.frame.origin = NSPoint(x: 120, y: y); ctl.frame.size.height = h; views += [lab, ctl]; y += h + 8 }
        func check(_ t: String, _ on: Bool, _ f: @escaping (inout ViewOptions, Bool) -> Void) -> NSButton {
            let b = NSButton(checkboxWithTitle: t, target: nil, action: nil); b.font = lucida(11); b.state = on ? .on : .off; b.frame.size.width = 150
            let h = ActionHandler { [weak self, weak b] in guard let b else { return }; self?.set { f(&$0, b.state == .on) } }; objc_setAssociatedObject(b, &handlerKey, h, .OBJC_ASSOCIATION_RETAIN); b.target = h; b.action = #selector(ActionHandler.run); return b }
        func slider(_ v: CGFloat, _ lo: Double, _ hi: Double, _ f: @escaping (inout ViewOptions, CGFloat) -> Void) -> NSSlider {
            let s = NSSlider(value: Double(v), minValue: lo, maxValue: hi, target: nil, action: nil); s.frame.size.width = 150; s.controlSize = .small
            let h = ActionHandler { [weak self, weak s] in guard let s else { return }; self?.set { f(&$0, CGFloat(s.doubleValue.rounded())) } }; objc_setAssociatedObject(s, &handlerKey, h, .OBJC_ASSOCIATION_RETAIN); s.target = h; s.action = #selector(ActionHandler.run); return s }
        func popup(_ items: [String], _ sel: Int, _ f: @escaping (inout ViewOptions, Int) -> Void) -> NSPopUpButton {
            let p = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 150, height: 22), pullsDown: false); p.controlSize = .small; p.font = lucida(11); p.addItems(withTitles: items); p.selectItem(at: sel)
            let h = ActionHandler { [weak self, weak p] in guard let p else { return }; self?.set { f(&$0, p.indexOfSelectedItem) } }; objc_setAssociatedObject(p, &handlerKey, h, .OBJC_ASSOCIATION_RETAIN); p.target = h; p.action = #selector(ActionHandler.run); return p }

        let o = opts
        y = 14
        // von unten nach oben aufbauen (flipped=false) – daher Reihenfolge invertiert
        let keys = SortKey.allCases
        switch o.mode {
        case .icon:
            row(L("Symbolgröße:", "Icon size:"), slider(o.iconSize, 16, 512) { $0.iconSize = $1 })
            row(L("Rasterabstand:", "Grid spacing:"), slider(o.gridSpacing, 24, 100) { $0.gridSpacing = $1 })
            row(L("Textgröße:", "Text size:"), popup(["10 pt", "11 pt", "12 pt", "13 pt", "14 pt", "15 pt", "16 pt"], Int(o.textSize) - 10) { $0.textSize = CGFloat(10 + $1) })
            row(L("Beschriftungsposition:", "Label position:"), popup([L("Unten", "Bottom"), L("Rechts", "Right")], o.labelRight ? 1 : 0) { $0.labelRight = $1 == 1 })
            row("", check(L("Objektinformationen zeigen", "Show item info"), o.showInfo) { $0.showInfo = $1 })
            row("", check(L("Symbolvorschau zeigen", "Show icon preview"), o.showPreview) { $0.showPreview = $1 })
            row(L("Hintergrund:", "Background:"), popup([L("Weiß", "White"), L("Farbe …", "Color"), L("Bild …", "Picture…")], o.bgImage != nil ? 2 : (o.bgColor == nil ? 0 : 1)) { [weak self] o, i in
                if i == 0 { o.bgColor = nil; o.bgImage = nil } else if i == 1 { o.bgImage = nil; o.bgColor = o.bgColor ?? [0.93, 0.95, 0.98]; self?.pickColor() }
                else { let p = NSOpenPanel(); p.allowedContentTypes = [.image]; if p.runModal() == .OK, let u = p.url { o.bgImage = u.path } } })
            row(L("Anordnen nach:", "Arrange by:"), popup(keys.map { $0.title }, keys.firstIndex { $0.rawValue == o.arrange } ?? 0) { $0.arrange = SortKey.allCases[$1].rawValue; $0.userPositions = [:] })
        case .list:
            row(L("Symbolgröße:", "Icon size:"), popup([L("Klein (16)", "Small (16)"), L("Groß (32)", "Large (32)")], o.listIconSize > 16 ? 1 : 0) { $0.listIconSize = $1 == 1 ? 32 : 16 })
            row(L("Textgröße:", "Text size:"), popup(["10 pt", "11 pt", "12 pt", "13 pt", "14 pt"], Int(o.listTextSize) - 10) { $0.listTextSize = CGFloat(10 + $1) })
            for col in ListCol.all.reversed() where col.id != "name" { row("", check(col.title, o.columns.contains(col.id)) { opt, on in if on { if !opt.columns.contains(col.id) { opt.columns.append(col.id) } } else { opt.columns.removeAll { $0 == col.id } } }) }
            row("", check(L("Relative Datumsangaben", "Use relative dates"), o.useRelativeDates) { $0.useRelativeDates = $1 })
            row("", check(L("Alle Größen berechnen", "Calculate all sizes"), o.calcSizes) { $0.calcSizes = $1 })
        case .column:
            row("", check(L("Vorschauspalte zeigen", "Show preview column"), o.colPreview) { $0.colPreview = $1 })
            row(L("Textgröße:", "Text size:"), popup(["10 pt", "11 pt", "12 pt", "13 pt", "14 pt"], Int(o.listTextSize) - 10) { $0.listTextSize = CGFloat(10 + $1) })
            row(L("Spaltenbreite:", "Column width:"), slider(o.colWidth, 80, 400) { $0.colWidth = $1 })
        case .coverFlow:
            row(L("Textgröße:", "Text size:"), popup(["10 pt", "11 pt", "12 pt", "13 pt", "14 pt"], Int(o.listTextSize) - 10) { $0.listTextSize = CGFloat(10 + $1) })
            row(L("Flow-Anteil:", "Flow share:"), slider(o.coverSplit * 100, 20, 80) { $0.coverSplit = $1 / 100 })
        }
        if o.mode != .icon || true {
            let names = [L("Symbole", "Icon"), L("Liste", "List"), L("Spalten", "Column"), L("Cover Flow", "Cover Flow")]
            views.append(contentsOf: [])
            let always = NSButton(checkboxWithTitle: L("Immer in \(names[o.mode.rawValue])-Ansicht öffnen", "Always open in \(names[o.mode.rawValue]) view"), target: nil, action: nil); always.font = lucida(11); always.state = o.forcedMode != nil ? .on : .off; always.frame = NSRect(x: 40, y: y, width: 240, height: 18)
            let h1 = ActionHandler { [weak self, weak always] in guard let a = always else { return }; self?.set { $0.forcedMode = a.state == .on ? $0.mode.rawValue : nil } }; objc_setAssociatedObject(always, &handlerKey, h1, .OBJC_ASSOCIATION_RETAIN); always.target = h1; always.action = #selector(ActionHandler.run)
            y += 22
            let glob = NSButton(checkboxWithTitle: L("Diese Ansicht für alle Ordner verwenden (global)", "Use this view for all folders (global)"), target: nil, action: nil); glob.font = lucida(11); glob.state = Prefs.globalView ? .on : .off; glob.frame = NSRect(x: 40, y: y, width: 250, height: 18)
            let h2 = ActionHandler { [weak self, weak glob] in guard let a = glob, let c = self?.c else { return }; BrowserController.setGlobalView(a.state == .on, from: c) }; objc_setAssociatedObject(glob, &handlerKey, h2, .OBJC_ASSOCIATION_RETAIN); glob.target = h2; glob.action = #selector(ActionHandler.run)
            let browse = glob
            y += 22; views += [always, browse]
        }
        let defBtn = NSButton(title: L("Als Standard verwenden", "Use as Defaults"), target: self, action: #selector(useDefaults)); defBtn.bezelStyle = .rounded; defBtn.controlSize = .small; defBtn.frame = NSRect(x: 60, y: y, width: 160, height: 24); views.append(defBtn); y += 32
        let h = y + 6
        // Koordinaten: unten beginnend – wir drehen die Reihenfolge, damit die erste Zeile oben steht
        for sv in views { sv.frame.origin.y = h - sv.frame.origin.y - sv.frame.height; v.addSubview(sv) }
        v.frame = NSRect(x: 0, y: 0, width: 290, height: h)
        panel.contentView = v; panel.setContentSize(NSSize(width: 290, height: h))
        if !panel.isVisible { panel.center() }
    }
    func pickColor() {
        let cp = NSColorPanel.shared; cp.setTarget(self); cp.setAction(#selector(colorChanged(_:))); cp.showsAlpha = false; cp.orderFront(nil)
        if let b = opts.bgColor, b.count == 3 { cp.color = NSColor(srgbRed: b[0], green: b[1], blue: b[2], alpha: 1) }
    }
    @objc func colorChanged(_ s: NSColorPanel) { let c = s.color.usingColorSpace(.sRGB) ?? s.color; set { $0.bgColor = [c.redComponent, c.greenComponent, c.blueComponent] } }
    @objc func useDefaults() { guard let c else { return }; ViewStore.save(c.options, for: c.location, asDefault: true) }
}
