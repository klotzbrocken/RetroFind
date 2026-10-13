import AppKit

// MARK: Toolbar-Katalog (N-12)

enum Toolbar {
    static let defaultItems = ["nav", "lead", "view", "action", "arrange", "share", "flex", "search"]
    struct Item { let id: String; let title: String; let width: CGFloat }
    static let catalog: [Item] = [
        Item(id: "nav", title: L("Zurück/Vorwärts", "Back/Forward"), width: 52),
        Item(id: "view", title: L("Darstellung", "View"), width: 111),
        Item(id: "action", title: L("Aktion", "Action"), width: 40),
        Item(id: "arrange", title: L("Anordnen", "Arrange"), width: 40),
        Item(id: "share", title: L("Teilen", "Share"), width: 40),
        Item(id: "path", title: L("Pfad", "Path"), width: 40),
        Item(id: "dual", title: L("Dual Pane", "Dual Pane"), width: 40),
        Item(id: "terminal", title: L("Terminal hier", "Terminal Here"), width: 40),
        Item(id: "newfolder", title: L("Neuer Ordner", "New Folder"), width: 40),
        Item(id: "delete", title: L("Löschen", "Delete"), width: 40),
        Item(id: "info", title: L("Informationen", "Get Info"), width: 40),
        Item(id: "quicklook", title: L("Übersicht", "Quick Look"), width: 40),
        Item(id: "connect", title: L("Verbinden", "Connect"), width: 40),
        Item(id: "burn", title: L("Brennen", "Burn"), width: 40),
        Item(id: "eject", title: L("Auswerfen", "Eject"), width: 40),
        Item(id: "search", title: L("Suchen", "Search"), width: 0),
        Item(id: "space", title: L("Abstand", "Space"), width: 16),
        Item(id: "flex", title: L("Flexibler Abstand", "Flexible Space"), width: 0),
    ]
    static func item(_ id: String) -> Item? { id == "lead" ? Item(id: "lead", title: "", width: 0) : catalog.first { $0.id == id } }

    struct Placed { let id: String; let rect: NSRect }
    static let chevronW: CGFloat = 26
    /// „lead“ füllt bis x = 141,5 (Referenzabstand), „flex“ verteilt Restbreite, Suchfeld ≈ 36 % der Breite (min 100).
    /// Passt nicht alles, wandern Objekte von rechts nach links in ein »-Menü (wie die Symbolleiste im Original).
    static func layout(width w: CGFloat, ids idsIn: [String], sidebarW: CGFloat) -> (placed: [Placed], overflow: [String]) {
        var ids = idsIn
        if let si = ids.firstIndex(of: "search"), !ids.contains("flex") { ids.insert("flex", at: si) }
        func place(_ vis: [String], _ searchW: CGFloat, _ flexW: CGFloat, leadFull: Bool, chevron: Bool) -> ([Placed], CGFloat) {
            var x = M.navX, prevItem = false; var out: [Placed] = []
            var chevronDone = !chevron
            for id in vis {
                if (id == "flex" || id == "search") && !chevronDone { x += M.btnGap; out.append(Placed(id: "overflow", rect: NSRect(x: x, y: M.tbY, width: chevronW, height: M.tbH))); x += chevronW; chevronDone = true; prevItem = true }
                switch id {
                case "lead": x = leadFull ? max(x + M.btnGap, M.viewX) : x + M.btnGap; prevItem = false
                case "flex": x += flexW; prevItem = false
                case "space": x += 16; prevItem = false
                default:
                    if prevItem { x += M.btnGap }
                    let wd = id == "search" ? searchW : (item(id)?.width ?? 40)
                    out.append(Placed(id: id, rect: NSRect(x: x, y: M.tbY, width: wd, height: M.tbH))); x += wd; prevItem = true
                }
            }
            return (out, x)
        }
        var vis = ids, hidden: [String] = []
        func minEnd(_ v: [String]) -> CGFloat { place(v, M.searchMin, 0, leadFull: false, chevron: !hidden.isEmpty).1 }
        while minEnd(vis) + M.navX > w, let k = vis.lastIndex(where: { !["nav", "view", "search", "flex", "lead", "space"].contains($0) }) {
            hidden.insert(vis.remove(at: k), at: 0)
        }
        let chev = !hidden.isEmpty
        let fullLead = place(vis, M.searchMin, 0, leadFull: true, chevron: chev).1 + M.navX <= w
        let minEnd2 = place(vis, M.searchMin, 0, leadFull: fullLead, chevron: chev).1
        let slack = max(0, w - M.navX - minEnd2)
        let flexN = CGFloat(vis.filter { $0 == "flex" }.count)
        var sw = M.searchMin
        if vis.contains("search") { sw = min(max(M.searchMin, w * 0.36), M.searchMin + slack) }
        let flexW = flexN > 0 ? max(0, slack - (sw - M.searchMin)) / flexN : 0
        return (place(vis, sw, flexW, leadFull: fullLead, chevron: chev).0, hidden)
    }
}

// MARK: Suchfeld (Kapsel mit Lupe)

final class SearchPill: NSView, NSTextFieldDelegate {
    let field = NSTextField()
    var onChange: ((String) -> Void)?
    var onCommit: ((String) -> Void)?
    var onFocus: (() -> Void)?
    var onEscape: (() -> Void)?
    override var isFlipped: Bool { true }
    var active = true { didSet { needsDisplay = true } }
    var focused = false { didSet { needsDisplay = true } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none; field.font = lucida(12); field.delegate = self
        field.cell?.isScrollable = true; field.cell?.usesSingleLineMode = true; field.lineBreakMode = .byClipping
        field.placeholderString = ""
        addSubview(field)
        setAccessibilityRole(.textField); setAccessibilityLabel(L("Suchen", "Search"))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); field.frame = NSRect(x: 22, y: 3.5, width: bounds.width - 22 - 22, height: 15) }
    var text: String { get { field.stringValue } set { field.stringValue = newValue; needsDisplay = true } }
    func controlTextDidChange(_ n: Notification) { needsDisplay = true; onChange?(field.stringValue) }
    func controlTextDidBeginEditing(_ obj: Notification) { focused = true; onFocus?() }
    func controlTextDidEndEditing(_ obj: Notification) { focused = false }
    func control(_ c: NSControl, textView: NSTextView, doCommandBy s: Selector) -> Bool {
        if s == #selector(NSResponder.insertNewline(_:)) { onCommit?(field.stringValue); return true }
        if s == #selector(NSResponder.cancelOperation(_:)) { if field.stringValue.isEmpty { onEscape?() } else { text = ""; onChange?("") }; return true }
        return false
    }
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if !field.stringValue.isEmpty && p.x > bounds.width - 20 { text = ""; onChange?(""); return }
        window?.makeFirstResponder(field)
    }
    override func draw(_ dirty: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let p = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        // Außenschatten (weiß, unten)
        NSColor(white: 1, alpha: 0.7).setStroke(); let sh = NSBezierPath(roundedRect: r.offsetBy(dx: 0, dy: 1), xRadius: r.height / 2, yRadius: r.height / 2); sh.lineWidth = 1; sh.stroke()
        NSGraphicsContext.saveGraphicsState(); p.addClip()
        NSColor.white.setFill(); bounds.fill()
        gradient([(0, NSColor(gray: 226)), (0.18, NSColor(gray: 244)), (0.5, NSColor(gray: 252)), (1, NSColor(gray: 255))]).draw(in: bounds, angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        (focused ? NSColor(88, 140, 205) : NSColor(gray: active ? 128 : 170)).setStroke(); p.lineWidth = focused ? 1.5 : 1; p.stroke()
        TB.magnifier(NSPoint(x: 11.5, y: 10.2), color: NSColor(gray: active ? 70 : 150))
        if !field.stringValue.isEmpty {   // Löschen-Knopf
            let c = NSPoint(x: bounds.width - 11, y: bounds.height / 2)
            NSColor(gray: 150).setFill(); NSBezierPath(ovalIn: NSRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)).fill()
            NSColor.white.setStroke(); let x = NSBezierPath(); x.lineWidth = 1.4; x.move(to: NSPoint(x: c.x - 2.2, y: c.y - 2.2)); x.line(to: NSPoint(x: c.x + 2.2, y: c.y + 2.2)); x.move(to: NSPoint(x: c.x + 2.2, y: c.y - 2.2)); x.line(to: NSPoint(x: c.x - 2.2, y: c.y + 2.2)); x.stroke()
        }
    }
}

// MARK: Titelleiste + Toolbar (55 pt)

protocol ChromeDelegate: AnyObject {
    func chromeAction(_ id: String, sub: Int)
    func chromeMenu(for id: String) -> NSMenu?
    func chromePathMenu() -> NSMenu?
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    var viewModeIndex: Int { get }
    var titleText: String { get }
    var titleIcon: NSImage? { get }
    var titleURL: URL? { get }
    func chromeClose(); func chromeMiniaturize(); func chromeZoom()
    func chromeToolbarEnabled(_ id: String) -> Bool
    var tabInfos: [TabInfo] { get }
    var tabIndex: Int { get }
    func chromeTab(_ a: TabAction)
}
struct TabInfo { var title: String; var icon: NSImage? }
enum TabAction { case select(Int), close(Int), new, move(Int, Int) }

final class ChromeBar: NSView {
    weak var delegate: ChromeDelegate?
    let search = SearchPill(frame: .zero)
    override var isFlipped: Bool { true }
    var active = true { didSet { search.active = active; needsDisplay = true } }
    var ids: [String] = Prefs.toolbarItems { didSet { relayout() } }
    var sidebarW: CGFloat = M.sidebarW
    private(set) var placed: [Toolbar.Placed] = []
    var extraTop: CGFloat = 0 { didSet { needsLayout = true; needsDisplay = true } }   // Tab-Zeile (X-Modus)
    var showTabs = false { didSet { needsLayout = true; needsDisplay = true } }
    private var hoverTab: Int?
    var aqua = false { didSet { needsDisplay = true } }
    private var hoverLights = false
    private var pressedLight: Lights.Kind?
    private var tabDrag: (index: Int, startX: CGFloat)?
    private var pressedItem: (id: String, sub: Int)?
    private var hoverTitle = false
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var tracking: NSTrackingArea?
    var showToolbar = true { didSet { needsLayout = true; needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(search)
        wantsLayer = false
    }
    required init?(coder: NSCoder) { fatalError() }

    var minToolbarWidth: CGFloat { 0 }
    private(set) var overflow: [String] = []
    func relayout() { needsLayout = true; needsDisplay = true }

    override func layout() {
        super.layout()
        let lay = showToolbar ? Toolbar.layout(width: bounds.width, ids: ids, sidebarW: sidebarW) : (placed: [], overflow: [])
        placed = lay.placed.map { Toolbar.Placed(id: $0.id, rect: $0.rect.offsetBy(dx: 0, dy: extraTop)) }; overflow = lay.overflow
        if let s = placed.first(where: { $0.id == "search" }) { search.isHidden = false; search.frame = s.rect } else { search.isHidden = true }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self); addTrackingArea(tracking!)
    }
    private var lightCY: CGFloat { (23 + extraTop) / 2 - 0.5 }
    private func lightCenter(_ k: Lights.Kind) -> NSPoint { NSPoint(x: M.lightX0 + CGFloat(k.rawValue) * M.lightPitch, y: lightCY) }
    private var lightsRect: NSRect { NSRect(x: 6, y: lightCY - 9, width: 60, height: 18) }
    override func mouseMoved(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if aqua { let h = lightsRect.contains(p); if h != hoverLights { hoverLights = h; needsDisplay = true } }
        let h = showTabs ? tabRects().firstIndex { $0.contains(p) } : nil
        if h != hoverTab { hoverTab = h; needsDisplay = true }
    }
    override func mouseExited(with e: NSEvent) { hoverTab = nil; hoverLights = false; needsDisplay = true }

    // MARK: Tabs (X-Modus)
    static let tabX0: CGFloat = 82, tabH: CGFloat = 26
    var tabBandY: CGFloat { extraTop + 23 - Self.tabH + 3 }          // Tabs sitzen auf der Oberkante der Toolbar
    func tabRects() -> [NSRect] {
        guard showTabs, let d = delegate else { return [] }
        let n = d.tabInfos.count
        let avail = bounds.width - Self.tabX0 - 14 - 34
        let w = max(60, min(210, avail / CGFloat(max(1, n))))
        return (0..<n).map { NSRect(x: Self.tabX0 + CGFloat($0) * (w - 1), y: tabBandY, width: w, height: Self.tabH) }
    }
    var newTabRect: NSRect { let r = tabRects().last ?? NSRect(x: Self.tabX0 - 22, y: tabBandY, width: 0, height: Self.tabH); return NSRect(x: r.maxX + 4, y: tabBandY + 3, width: 30, height: Self.tabH - 5) }
    private func closeRect(_ r: NSRect) -> NSRect { NSRect(x: r.maxX - 22, y: r.midY - 6, width: 12, height: 12) }

    private func hit(_ p: NSPoint) -> (id: String, sub: Int)? {
        for pl in placed where pl.rect.contains(p) && pl.id != "search" && pl.id != "flex" && pl.id != "space" {
            switch pl.id {
            case "nav": return (pl.id, p.x < pl.rect.midX ? 0 : 1)
            case "view": return (pl.id, min(3, Int((p.x - pl.rect.minX) / (pl.rect.width / 4))))
            case "overflow": return (pl.id, 0)
            default: return (pl.id, 0)
            }
        }
        return nil
    }
    private var titleRect: NSRect {
        let s = titleSize
        let w = s.w; return NSRect(x: (bounds.width - w) / 2, y: 3 + (showTabs ? -100 : 0), width: w, height: 17)
    }
    private var titleSize: (w: CGFloat, text: CGFloat) {
        let t = delegate?.titleText ?? ""
        let tw = (t as NSString).size(withAttributes: [.font: lucida(13)]).width
        let maxW = max(40, bounds.width - 150)
        let text = min(tw, maxW - 20)
        return (text + 20, text)
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if active == false { window?.makeKeyAndOrderFront(nil) }
        if aqua, lightsRect.contains(p) {
            for k in [Lights.Kind.close, .mini, .zoom] where hypot(p.x - lightCenter(k).x, p.y - lightCenter(k).y) <= 8 { pressedLight = k; needsDisplay = true; return }
        }
        if showTabs {
            let rs = tabRects()
            if let i = rs.firstIndex(where: { $0.contains(p) }) {
                if closeRect(rs[i]).insetBy(dx: -3, dy: -3).contains(p) && (rs.count > 1 || true) { delegate?.chromeTab(.close(i)); return }
                if e.clickCount == 1 { delegate?.chromeTab(.select(i)); tabDrag = (i, p.x) }
                return
            }
            if newTabRect.contains(p) { delegate?.chromeTab(.new); return }
            if p.y < extraTop + 23 && e.clickCount == 2 { delegate?.chromeTab(.new); return }
        }
        if showToolbar, let h = hit(p) {
            let enabled = delegate?.chromeToolbarEnabled(h.id) ?? true
            if h.id == "nav" && !(h.sub == 0 ? delegate?.canGoBack ?? false : delegate?.canGoForward ?? false) { return }
            if !enabled { return }
            pressedItem = h; needsDisplay = true
            if h.id == "overflow" {
                let m = NSMenu(); m.autoenablesItems = false
                for id in overflow { let it = NSMenuItem(title: Toolbar.item(id)?.title ?? id, action: #selector(overflowPick(_:)), keyEquivalent: ""); it.target = self; it.representedObject = id; it.isEnabled = delegate?.chromeToolbarEnabled(id) ?? true; if let sub = delegate?.chromeMenu(for: id), ["action", "arrange", "share"].contains(id) { it.submenu = sub; it.action = nil }; m.addItem(it) }
                let pl = placed.first { $0.id == "overflow" }!
                m.popUp(positioning: nil, at: NSPoint(x: pl.rect.minX, y: pl.rect.maxY + 2), in: self); pressedItem = nil; needsDisplay = true; return
            }
            if ["action", "arrange", "share"].contains(h.id) || (h.id == "path"), let m = delegate?.chromeMenu(for: h.id) {
                let pl = placed.first { $0.id == h.id }!
                pressedItem = h; needsDisplay = true
                m.popUp(positioning: nil, at: NSPoint(x: pl.rect.minX, y: pl.rect.maxY + 2), in: self)
                pressedItem = nil; needsDisplay = true; return
            }
            return
        }
        if !showTabs, titleRect.contains(p) && p.y < 22, let u = delegate?.titleURL {
            if e.modifierFlags.contains(.command) || e.clickCount == 1 && e.modifierFlags.contains(.control) { showPath(e); return }
            // Proxy-Symbol: ziehen = Datei-Referenz (N-06)
            if p.x < titleRect.minX + 20 {
                let item = NSDraggingItem(pasteboardWriter: u as NSURL)
                item.setDraggingFrame(NSRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32), contents: delegate?.titleIcon)
                beginDraggingSession(with: [item], event: e, source: self); return
            }
        }
        if e.clickCount == 2 && p.y < M.chromeH && !showToolbar || (e.clickCount == 2 && p.y < 23 + extraTop) { delegate?.chromeZoom(); return }
        window?.performDrag(with: e)
    }
    @objc func overflowPick(_ s: NSMenuItem) { if let id = s.representedObject as? String { delegate?.chromeAction(id, sub: 0) } }
    private func showPath(_ e: NSEvent) {
        guard let m = delegate?.chromePathMenu() else { return }
        let r = titleRect; m.popUp(positioning: nil, at: NSPoint(x: r.minX, y: r.maxY + 2), in: self)
    }
    override func mouseDragged(with e: NSEvent) {
        guard var d = tabDrag else { return }
        let p = convert(e.locationInWindow, from: nil), rs = tabRects()
        if let j = rs.firstIndex(where: { $0.contains(p) }), j != d.index { delegate?.chromeTab(.move(d.index, j)); d.index = j; tabDrag = d }
    }
    override func mouseUp(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if let k = pressedLight {
            pressedLight = nil; needsDisplay = true
            if hypot(p.x - lightCenter(k).x, p.y - lightCenter(k).y) <= 8 { switch k { case .close: delegate?.chromeClose(); case .mini: delegate?.chromeMiniaturize(); case .zoom: delegate?.chromeZoom() } }
            return
        }
        tabDrag = nil
        if let pi = pressedItem {
            pressedItem = nil; needsDisplay = true
            if let h = hit(p), h.id == pi.id, h.sub == pi.sub { delegate?.chromeAction(h.id, sub: h.sub) }
        }
    }
    override func rightMouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if p.y < 22 || !showToolbar { return }
    }

    // MARK: Zeichnen
    override func draw(_ dirty: NSRect) {
        Draw.chrome(bounds, active: active)
        if aqua { for k in [Lights.Kind.close, .mini, .zoom] { Lights.draw(k, center: lightCenter(k), active: active, hover: hoverLights, pressed: pressedLight == k) } }
        if showTabs { drawTabs() } else { drawTitle() }
        guard showToolbar else { return }
        for pl in placed { drawItem(pl) }
    }
    private func drawTabs() {
        guard let d = delegate else { return }
        let rs = tabRects(); let infos = d.tabInfos
        // inaktive zuerst (dunkler, mit Trennlinie), die aktive zuletzt: gleiche Farbe wie das Chrome → fließender Übergang in die Toolbar
        for pass in 0..<2 { for (i, r) in rs.enumerated() where (i == d.tabIndex) == (pass == 1) {
            let act = i == d.tabIndex
            let rad: CGFloat = 7
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX, y: r.maxY + (act ? 1 : 0))); p.curve(to: NSPoint(x: r.minX + rad, y: r.minY + 1), controlPoint1: NSPoint(x: r.minX + rad * 0.4, y: r.maxY), controlPoint2: NSPoint(x: r.minX + rad * 0.2, y: r.minY + 1))
            p.line(to: NSPoint(x: r.maxX - rad, y: r.minY + 1)); p.curve(to: NSPoint(x: r.maxX, y: r.maxY + (act ? 1 : 0)), controlPoint1: NSPoint(x: r.maxX - rad * 0.2, y: r.minY + 1), controlPoint2: NSPoint(x: r.maxX - rad * 0.4, y: r.maxY))
            let fill = p.copy() as! NSBezierPath; fill.close()
            NSGraphicsContext.saveGraphicsState(); fill.addClip()
            if act { Draw.chrome(bounds, active: active) }                // exakt der Chrome-Verlauf
            else { gradient([(0, NSColor(gray: active ? 206 : 222)), (1, NSColor(gray: active ? 184 : 204))]).draw(in: r, angle: 90) }
            if hoverTab == i && !act { NSColor(white: 1, alpha: 0.22).setFill(); r.fill() }
            NSGraphicsContext.restoreGraphicsState()
            NSColor(gray: active ? 126 : 170).setStroke(); p.lineWidth = 1
            if act { p.stroke() }                                          // oben und seitlich, unten offen
            else { let cl = fill; cl.lineWidth = 1; cl.stroke(); NSColor(white: 1, alpha: 0.35).setFill(); NSRect(x: r.minX + 1, y: r.minY + 2, width: r.width - 2, height: 1).fill() }
            if let ic = infos[i].icon { ic.draw(in: NSRect(x: r.minX + 10, y: r.midY - 7, width: 14, height: 14), from: .zero, operation: .sourceOver, fraction: act ? 1 : 0.8, respectFlipped: true, hints: nil) }
            Draw.text(infos[i].title, in: NSRect(x: r.minX + 28, y: r.midY - 7.5, width: r.width - 54, height: 15), font: lucida(11, bold: act), color: NSColor(gray: act ? 40 : 90), shadow: act ? Draw.whiteShadow(0.7) : nil)
            if act || hoverTab == i { let cr = closeRect(r); NSColor(gray: 120).setStroke(); let x = NSBezierPath(); x.lineWidth = 1.6; x.lineCapStyle = .round; x.move(to: NSPoint(x: cr.minX + 3, y: cr.minY + 3)); x.line(to: NSPoint(x: cr.maxX - 3, y: cr.maxY - 3)); x.move(to: NSPoint(x: cr.maxX - 3, y: cr.minY + 3)); x.line(to: NSPoint(x: cr.minX + 3, y: cr.maxY - 3)); x.stroke() }
        } }
        // „+“-Karte
        let n = newTabRect; let np = NSBezierPath(roundedRect: n, xRadius: 6, yRadius: 6)
        gradient([(0, NSColor(gray: 222)), (1, NSColor(gray: 205))]).draw(in: np, angle: 90); NSColor(gray: 150).setStroke(); np.lineWidth = 0.8; np.stroke()
        Draw.text("+", in: NSRect(x: n.minX, y: n.minY + 2, width: n.width, height: n.height - 4), font: lucida(14, bold: true), color: NSColor(gray: 90), align: .center)
    }
    private func drawTitle() {
        let t = delegate?.titleText ?? ""
        let r = titleRect
        var x = r.minX
        if let icon = delegate?.titleIcon {
            icon.draw(in: NSRect(x: x, y: 3.5, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: active ? 1 : 0.6, respectFlipped: true, hints: nil)
            x += 20
        }
        let w = titleSize.text
        Draw.text(t, in: NSRect(x: x, y: 4.5, width: w + 2, height: 16), font: lucida(13), color: active ? NSColor(gray: 51) : NSColor(gray: 128), shadow: Draw.whiteShadow(active ? 0.8 : 0.5))
    }

    private func drawItem(_ pl: Toolbar.Placed) {
        let r = pl.rect, a = active
        let ink = NSColor(gray: a ? 34 : 150), dis = NSColor(gray: a ? 168 : 190)
        switch pl.id {
        case "nav":
            Draw.button(r, active: a)
            Draw.divider(x: r.midX - 0.5, in: r, gray: a ? 140 : 180)
            if pressedItem?.id == "nav" { let half = pressedItem!.sub == 0 ? NSRect(x: r.minX, y: r.minY, width: r.width / 2, height: r.height) : NSRect(x: r.midX, y: r.minY, width: r.width / 2, height: r.height); NSColor(0, 0, 0, 0.12).setFill(); half.insetBy(dx: 1, dy: 1).fill() }
            TB.tri(NSPoint(x: r.minX + r.width / 4 + 0.5, y: r.midY), right: false, color: (delegate?.canGoBack ?? false) ? ink : dis)
            TB.tri(NSPoint(x: r.minX + r.width * 3 / 4 - 0.5, y: r.midY), right: true, color: (delegate?.canGoForward ?? false) ? ink : dis)
        case "view":
            Draw.button(r, active: a)
            let w = r.width / 4, cur = delegate?.viewModeIndex ?? 0
            for i in 0..<4 {
                let seg = NSRect(x: r.minX + CGFloat(i) * w, y: r.minY, width: w, height: r.height)
                if i == cur || (pressedItem?.id == "view" && pressedItem?.sub == i) {
                    NSGraphicsContext.saveGraphicsState(); NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).addClip()
                    gradient([(0, NSColor(gray: 104)), (0.12, NSColor(gray: 121)), (1, NSColor(gray: 146))]).draw(in: seg.insetBy(dx: i == 0 ? 0 : 0, dy: 0), angle: 90)
                    NSGraphicsContext.restoreGraphicsState()
                }
                if i > 0 && i != cur && i - 1 != cur { Draw.divider(x: seg.minX, in: r, gray: a ? 148 : 185) }
                TB.viewMode(i, in: seg, color: i == cur ? NSColor.white : ink)
            }
            NSColor(gray: a ? 118 : 160).setStroke(); let p = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4); p.lineWidth = 1; p.stroke()
        case "action", "arrange", "share", "path", "dual", "terminal", "newfolder", "delete", "info", "quicklook", "connect", "burn", "eject":
            let en = delegate?.chromeToolbarEnabled(pl.id) ?? true
            Draw.button(r, pressed: pressedItem?.id == pl.id, active: a)
            let c = NSPoint(x: r.midX - ((pl.id == "action" || pl.id == "arrange") ? 4 : 0), y: r.midY)
            let col = pressedItem?.id == pl.id ? NSColor.white : (en ? ink : dis)
            switch pl.id {
            case "action": TB.gear(c, color: col); TB.caret(NSPoint(x: r.maxX - 10, y: r.midY), color: col)
            case "arrange": TB.arrange(c, color: col); TB.caret(NSPoint(x: r.maxX - 10, y: r.midY), color: col)
            case "share": TB.share(c, color: col)
            case "quicklook": TB.eye(c, color: col)
            case "dual":
                col.setStroke(); for dx in [-8.0, 0.6] as [CGFloat] { let q = NSBezierPath(rect: NSRect(x: c.x + dx, y: c.y - 6, width: 7.4, height: 12)); q.lineWidth = 1.3; q.stroke() }
            default:
                col.setStroke(); col.setFill()
                let t: String = ["terminal": ">_", "path": "⌘", "newfolder": "＋", "delete": "⊖", "info": "ⓘ", "connect": "⇄", "burn": "◉", "eject": "⏏"][pl.id] ?? "?"
                Draw.text(t, in: NSRect(x: r.minX, y: r.minY + 2, width: r.width, height: 17), font: .systemFont(ofSize: 13), color: col, align: .center)
            }
        case "overflow":
            Draw.button(r, pressed: pressedItem?.id == "overflow", active: a)
            Draw.text("»", in: NSRect(x: r.minX, y: r.minY + 1, width: r.width, height: 18), font: lucida(15, bold: true), color: ink, align: .center)
        case "space", "flex", "lead", "search": break
        default: break
        }
        if Prefs.toolbarMode != 0 && pl.id != "search" && pl.id != "flex" && pl.id != "space" {
            Draw.text(Toolbar.item(pl.id)?.title ?? "", in: NSRect(x: pl.rect.minX - 12, y: pl.rect.maxY + 3, width: pl.rect.width + 24, height: 11), font: lucida(9), color: NSColor(gray: 70), align: .center)
        }
    }
}

extension ChromeBar: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [.copy, .link, .generic] }
}

// MARK: Fenster

final class FinderWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var userFrame: NSRect?
    var onMouseDown: ((NSEvent) -> Void)?
    var onKeyEquivalent: ((NSEvent) -> Bool)?
    var titleZoneH: CGFloat = 23 { didSet { placeLights() } }
    /// System-Ampel (Wunsch): Standardknöpfe des Systems, in die 23-pt-Titelzone eingemittet; Inhalt reicht unter die transparente Titelleiste.
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        titlebarAppearsTransparent = true; titleVisibility = .hidden; isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        collectionBehavior = [.managed, .participatesInCycle]
        backgroundColor = NSColor(gray: 232)
        let nc = NotificationCenter.default
        for n in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didExposeNotification, NSWindow.didEndLiveResizeNotification] { nc.addObserver(forName: n, object: self, queue: .main) { [weak self] _ in self?.placeLights() } }
    }
    func placeLights() {
        for (i, t) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let b = standardWindowButton(t), let sv = b.superview else { continue }
            b.isHidden = Prefs.aquaLights
            let step = b.frame.width + 7
            let y = sv.isFlipped ? titleZoneH / 2 - b.frame.height / 2 - 0.5 : sv.frame.height - titleZoneH / 2 - b.frame.height / 2 + 0.5
            b.setFrameOrigin(NSPoint(x: 12 + CGFloat(i) * step, y: y))
        }
    }
    override func makeKeyAndOrderFront(_ sender: Any?) { super.makeKeyAndOrderFront(sender); placeLights() }
    override func sendEvent(_ e: NSEvent) { if e.type == .leftMouseDown || e.type == .rightMouseDown { onMouseDown?(e) }; super.sendEvent(e) }
    override func performKeyEquivalent(with e: NSEvent) -> Bool { if onKeyEquivalent?(e) == true { return true }; return super.performKeyEquivalent(with: e) }
    /// Mindestgröße gilt auch für programmgesteuerte Änderungen.
    private func clamp(_ r: NSRect) -> NSRect { var f = r; if f.width < minSize.width { f.size.width = minSize.width }; if f.height < minSize.height { f.origin.y -= minSize.height - f.height; f.size.height = minSize.height }; return f }
    override func setFrame(_ frameRect: NSRect, display flag: Bool) { super.setFrame(clamp(frameRect), display: flag) }
    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) { super.setFrame(clamp(frameRect), display: displayFlag, animate: animateFlag) }
    override func setContentSize(_ size: NSSize) { super.setContentSize(NSSize(width: max(size.width, minSize.width), height: max(size.height, minSize.height))) }
}

final class RootView: NSView {
    override var isFlipped: Bool { true }
    var onLayout: (() -> Void)?
    /// Eingebettete Fensterhälfte (Dual Pane): Aktionen laufen über den Controller der Hälfte.
    weak var paneResponder: NSResponder?
    override var nextResponder: NSResponder? { get { paneResponder ?? super.nextResponder } set { super.nextResponder = newValue } }
    override func layout() { super.layout(); onLayout?() }
}
