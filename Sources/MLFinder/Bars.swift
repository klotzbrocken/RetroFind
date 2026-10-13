import AppKit

// MARK: Statusleiste (Linie + 22 pt, Text zentriert, Symbolgrößenregler)

final class StatusBarView: NSView {
    override var isFlipped: Bool { true }
    var text = "" { didSet { needsDisplay = true } }
    var active = true { didSet { needsDisplay = true } }
    var showSlider = true
    var sliderValue: CGFloat = 64
    var onSlider: ((CGFloat) -> Void)?
    private var dragging = false
    static let range: ClosedRange<CGFloat> = 16...512
    private var trackRect: NSRect { NSRect(x: bounds.width - 101, y: 8, width: 77, height: 8) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirty: NSRect) {
        Draw.statusBar(bounds, active: active)
        Draw.text(text, in: NSRect(x: 6, y: 5.5, width: bounds.width - (showSlider ? 120 : 12), height: 14), font: lucida(12), color: NSColor(gray: active ? 55 : 120), align: .center, shadow: Draw.whiteShadow(0.6))
        if showSlider {
            let t = trackRect
            let g = NSBezierPath(roundedRect: NSRect(x: t.minX, y: t.midY - 2, width: t.width, height: 4), xRadius: 2, yRadius: 2)
            gradient([(0, NSColor(gray: 120)), (1, NSColor(gray: 170))]).draw(in: g, angle: 90); NSColor(gray: 95).setStroke(); g.lineWidth = 0.7; g.stroke()
            let f = (sliderValue - Self.range.lowerBound) / (Self.range.upperBound - Self.range.lowerBound)
            let kx = t.minX + 6 + f * (t.width - 12)
            let k = NSBezierPath(ovalIn: NSRect(x: kx - 5.5, y: t.midY - 5.5, width: 11, height: 11))
            NSColor(white: 1, alpha: 0.7).setStroke(); NSBezierPath(ovalIn: NSRect(x: kx - 5.5, y: t.midY - 4.7, width: 11, height: 11)).stroke()
            gradient([(0, NSColor(gray: 252)), (1, NSColor(gray: 188))]).draw(in: k, angle: 90); NSColor(gray: 110).setStroke(); k.lineWidth = 0.9; k.stroke()
        }
    }
    private func set(_ x: CGFloat) {
        let t = trackRect; let f = max(0, min(1, (x - t.minX - 6) / (t.width - 12)))
        let v = (Self.range.lowerBound + f * (Self.range.upperBound - Self.range.lowerBound)).rounded()
        sliderValue = v; onSlider?(v); needsDisplay = true
    }
    override func mouseDown(with e: NSEvent) { let p = convert(e.locationInWindow, from: nil); if showSlider && trackRect.insetBy(dx: -8, dy: -6).contains(p) { dragging = true; set(p.x) } else { window?.performDrag(with: e) } }
    override func mouseDragged(with e: NSEvent) { if dragging { set(convert(e.locationInWindow, from: nil).x) } }
    override func mouseUp(with e: NSEvent) { dragging = false }
}

// MARK: Pfadleiste (N-05)

final class PathBarView: NSView {
    override var isFlipped: Bool { true }
    var url: URL?
    var active = true { didSet { needsDisplay = true } }
    var highlight = false { didSet { needsDisplay = true } }
    var onNavigate: ((URL) -> Void)?
    var onDrop: (([URL], URL) -> Bool)?
    var dropOp: (([URL], URL) -> NSDragOperation)?
    private var dropSeg: Int?
    private var segs: [(rect: NSRect, url: URL)] = []
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirty: NSRect) {
        if highlight { gradient([(0, NSColor(222, 236, 252)), (1, NSColor(196, 218, 246))]).draw(in: bounds, angle: 90) }
        else { gradient([(0, NSColor(gray: 250)), (1, NSColor(gray: 232))]).draw(in: bounds, angle: 90) }
        NSColor(gray: 170).setFill(); NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        if highlight { gradient([(0, NSColor(98, 160, 228)), (1, NSColor(60, 130, 205))]).draw(in: NSRect(x: 0, y: 0, width: bounds.width, height: 3), angle: 90) }
        segs = []
        guard let u = url?.standardizedFileURL else { return }
        var chain: [URL] = []; var cur: URL? = u
        while let c = cur { chain.insert(c, at: 0); let p = c.deletingLastPathComponent(); cur = (c.path == "/" || p.path == c.path) ? nil : p }
        var x: CGFloat = 8
        for (i, c) in chain.enumerated() {
            let name = Files.displayName(c)
            let w = (name as NSString).size(withAttributes: [.font: lucida(11)]).width
            IconCache.shared.folderImage(Files.glyph(for: c) == .hardDisk ? .folder : Files.glyph(for: c), size: 14).draw(in: NSRect(x: x, y: 4.5, width: 14, height: 14), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            Draw.text(name, in: NSRect(x: x + 18, y: 5.5, width: w + 4, height: 14), font: lucida(11), color: i == chain.count - 1 ? .black : NSColor(gray: 60))
            segs.append((NSRect(x: x, y: 0, width: w + 22, height: bounds.height), c))
            if dropSeg == segs.count - 1 { C.listSel.setStroke(); let b = NSBezierPath(roundedRect: NSRect(x: x - 2, y: 2, width: w + 24, height: bounds.height - 4), xRadius: 4, yRadius: 4); b.lineWidth = 2; b.stroke() }
            x += w + 24
            if i < chain.count - 1 { Draw.text("▸", in: NSRect(x: x - 2, y: 5, width: 12, height: 14), font: lucida(9), color: NSColor(gray: 130)); x += 10 }
            if x > bounds.width { break }
        }
    }
    override func mouseDown(with e: NSEvent) { let p = convert(e.locationInWindow, from: nil); if let s = segs.first(where: { $0.rect.contains(p) }) { if e.clickCount == 2 { onNavigate?(s.url) } } }
    override func viewDidMoveToSuperview() { registerForDraggedTypes([.fileURL]) }
    private func dropInfo(_ s: NSDraggingInfo) -> ([URL], Int?) {
        let urls = (s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let p = convert(s.draggingLocation, from: nil); return (urls, segs.firstIndex { $0.rect.contains(p) })
    }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { draggingUpdated(s) }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation {
        let (u, i) = dropInfo(s); dropSeg = i; needsDisplay = true
        guard let i else { return [] }; return dropOp?(u, segs[i].url) ?? []
    }
    override func draggingExited(_ s: NSDraggingInfo?) { dropSeg = nil; needsDisplay = true }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool { defer { dropSeg = nil; needsDisplay = true }; let (u, i) = dropInfo(s); guard let i else { return false }; return onDrop?(u, segs[i].url) ?? false }
}

// MARK: Suchleiste (S-01…S-06)

final class SearchBarView: NSView, NSTextFieldDelegate {
    override var isFlipped: Bool { true }
    var spec = SearchSpec() { didSet { sync() } }
    var onChange: (() -> Void)?
    var onSave: (() -> Void)?
    var folderName: String?
    var showCriteria = false
    private var rowViews: [NSView] = []
    private var hits: [(NSRect, () -> Void)] = []
    var preferredHeight: CGFloat { 24 + (spec.criteria.isEmpty && !showCriteria ? 0 : CGFloat(max(1, spec.criteria.count)) * 27) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func sync() { rebuildRows(); needsDisplay = true }

    private func rebuildRows() {
        rowViews.forEach { $0.removeFromSuperview() }; rowViews = []
        guard !spec.criteria.isEmpty || showCriteria else { return }
        if spec.criteria.isEmpty { spec.criteria = [Criterion(attr: "kind", op: "is", value: "doc")] }
        for (i, c) in spec.criteria.enumerated() {
            let row = NSView(frame: NSRect(x: 0, y: 24 + CGFloat(i) * 27, width: bounds.width, height: 27)); row.autoresizingMask = [.width]
            func popup(_ items: [(String, String)], sel: String, x: CGFloat, w: CGFloat, f: @escaping (String) -> Void) -> NSPopUpButton {
                let p = NSPopUpButton(frame: NSRect(x: x, y: 3, width: w, height: 21), pullsDown: false); p.controlSize = .small; p.font = lucida(11)
                for it in items { p.addItem(withTitle: it.1); p.lastItem?.representedObject = it.0 }
                if let k = items.firstIndex(where: { $0.0 == sel }) { p.selectItem(at: k) }
                let h = ActionHandler { [weak p] in if let v = p?.selectedItem?.representedObject as? String { f(v) } }; objc_setAssociatedObject(p, &handlerKey, h, .OBJC_ASSOCIATION_RETAIN); p.target = h; p.action = #selector(ActionHandler.run); return p
            }
            let a = popup(Criterion.attrs, sel: c.attr, x: 8, w: 150) { [weak self] v in guard let s = self else { return }; s.spec.criteria[i].attr = v; s.spec.criteria[i].op = Criterion.ops(for: v)[0].0; s.spec.criteria[i].value = v == "kind" ? "doc" : (v == "label" ? "1" : (["modified", "created", "opened"].contains(v) ? "7" : "")); s.rebuildRows(); s.onChange?() }
            row.addSubview(a)
            let o = popup(Criterion.ops(for: c.attr), sel: c.op, x: 164, w: 150) { [weak self] v in self?.spec.criteria[i].op = v; self?.rebuildRows(); self?.onChange?() }
            row.addSubview(o)
            if c.attr == "kind" { row.addSubview(popup(Criterion.kinds, sel: c.value, x: 320, w: 140) { [weak self] v in self?.spec.criteria[i].value = v; self?.onChange?() }) }
            else if c.attr == "label" { row.addSubview(popup((1...7).map { (String($0), Labels.name($0)) }, sel: c.value, x: 320, w: 140) { [weak self] v in self?.spec.criteria[i].value = v; self?.onChange?() }) }
            else if c.op != "today" {
                let f = NSTextField(frame: NSRect(x: 320, y: 3, width: 160, height: 21)); f.stringValue = c.value; f.controlSize = .small; f.font = lucida(11); f.delegate = self; f.tag = i; row.addSubview(f)
            }
            let minus = NSButton(frame: NSRect(x: bounds.width - 62, y: 3, width: 24, height: 21)); minus.title = "−"; minus.bezelStyle = .smallSquare; minus.controlSize = .small
            let mh = ActionHandler { [weak self] in guard let s = self else { return }; if s.spec.criteria.count > 0 { s.spec.criteria.remove(at: i) }; if s.spec.criteria.isEmpty { s.showCriteria = false }; s.rebuildRows(); s.superview.map { _ in () }; s.onChange?(); (s.window?.windowController as? BrowserController)?.layoutAll() }
            objc_setAssociatedObject(minus, &handlerKey, mh, .OBJC_ASSOCIATION_RETAIN); minus.target = mh; minus.action = #selector(ActionHandler.run); minus.autoresizingMask = [.minXMargin]
            let plus = NSButton(frame: NSRect(x: bounds.width - 34, y: 3, width: 24, height: 21)); plus.title = "+"; plus.bezelStyle = .smallSquare; plus.controlSize = .small
            let ph = ActionHandler { [weak self] in guard let s = self else { return }; s.spec.criteria.insert(Criterion(attr: "kind", op: "is", value: "doc"), at: i + 1); s.rebuildRows(); s.onChange?(); (s.window?.windowController as? BrowserController)?.layoutAll() }
            objc_setAssociatedObject(plus, &handlerKey, ph, .OBJC_ASSOCIATION_RETAIN); plus.target = ph; plus.action = #selector(ActionHandler.run); plus.autoresizingMask = [.minXMargin]
            row.addSubview(minus); row.addSubview(plus)
            addSubview(row); rowViews.append(row)
        }
    }
    func controlTextDidChange(_ n: Notification) { if let f = n.object as? NSTextField, f.tag < spec.criteria.count { spec.criteria[f.tag].value = f.stringValue; onChange?() } }

    override func draw(_ dirty: NSRect) {
        gradient([(0, NSColor(gray: 238)), (1, NSColor(gray: 222))]).draw(in: NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height), angle: 90)
        NSColor(gray: 178).setFill(); NSRect(x: 0, y: 23, width: bounds.width, height: 1).fill()
        NSColor(gray: 150).setFill(); NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        hits = []
        var x: CGFloat = 8
        Draw.text(L("Suchen:", "Search:"), in: NSRect(x: x, y: 5, width: 60, height: 14), font: lucida(11, bold: true), color: NSColor(gray: 110), shadow: Draw.whiteShadow())
        x += (L("Suchen:", "Search:") as NSString).size(withAttributes: [.font: lucida(11, bold: true)]).width + 10
        func pill(_ t: String, on: Bool, _ f: @escaping () -> Void) {
            let w = (t as NSString).size(withAttributes: [.font: lucida(11, bold: true)]).width + 14
            let r = NSRect(x: x, y: 3, width: w, height: 18)
            if on { let p = NSBezierPath(roundedRect: r, xRadius: 9, yRadius: 9); gradient([(0, NSColor(gray: 110)), (1, NSColor(gray: 150))]).draw(in: p, angle: 90); NSColor(gray: 95).setStroke(); p.lineWidth = 0.7; p.stroke() }
            Draw.text(t, in: NSRect(x: r.minX, y: 5, width: w, height: 14), font: lucida(11, bold: true), color: on ? .white : NSColor(gray: 60), align: .center, shadow: on ? Draw.darkShadow(0.4) : Draw.whiteShadow())
            hits.append((r, f)); x += w + 6
        }
        pill(L("Dieser Mac", "This Mac"), on: spec.scope == "this") { [weak self] in self?.spec.scope = "this"; self?.onChange?() }
        if let f = folderName { pill("„\(f)“", on: spec.scope.hasPrefix("folder:")) { [weak self] in if let p = self?.folderPath { self?.spec.scope = "folder:" + p; self?.onChange?() } } }
        pill(L("Geteilt", "Shared"), on: spec.scope == "shared") { [weak self] in self?.spec.scope = "shared"; self?.onChange?() }
        x += 10
        pill(L("Inhalt", "Contents"), on: spec.contents) { [weak self] in self?.spec.contents = true; self?.onChange?() }
        pill(L("Dateiname", "File Name"), on: !spec.contents) { [weak self] in self?.spec.contents = false; self?.onChange?() }
        // Speichern / +
        let sr = NSRect(x: bounds.width - 70, y: 3, width: 48, height: 18)
        Draw.button(sr, active: true); Draw.text(L("Sichern", "Save"), in: NSRect(x: sr.minX, y: 4.5, width: sr.width, height: 14), font: lucida(11), color: .black, align: .center)
        hits.append((sr, { [weak self] in self?.onSave?() }))
        let pr = NSRect(x: bounds.width - 18, y: 3, width: 18, height: 18)
        Draw.button(pr, active: true); Draw.text(spec.criteria.isEmpty && !showCriteria ? "+" : "−", in: NSRect(x: pr.minX, y: 3.5, width: pr.width, height: 14), font: lucida(13, bold: true), color: .black, align: .center)
        hits.append((pr, { [weak self] in guard let s = self else { return }; if s.spec.criteria.isEmpty && !s.showCriteria { s.showCriteria = true } else { s.spec.criteria = []; s.showCriteria = false }; s.rebuildRows(); s.onChange?(); (s.window?.windowController as? BrowserController)?.layoutAll() }))
    }
    var folderPath: String?
    override func mouseDown(with e: NSEvent) { let p = convert(e.locationInWindow, from: nil); if p.y < 24, let h = hits.first(where: { $0.0.contains(p) }) { h.1(); needsDisplay = true } }
    override func layout() { super.layout(); for (i, r) in rowViews.enumerated() { r.frame = NSRect(x: 0, y: 24 + CGFloat(i) * 27, width: bounds.width, height: 27) } }
}

var handlerKey: UInt8 = 0
final class ActionHandler: NSObject { let f: () -> Void; init(_ f: @escaping () -> Void) { self.f = f }; @objc func run() { f() } }

/// Schmale Leiste über einer Dual-Pane-Hälfte: aktive Hälfte blau eingefärbt, sonst grau (ohne Pfadanzeige)
final class PaneStrip: NSView {
    override var isFlipped: Bool { true }
    var active = false { didSet { needsDisplay = true } }
    var isFavorite = false { didSet { needsDisplay = true } }
    var onHistory: ((NSRect) -> Void)?
    var onFavorites: ((NSRect) -> Void)?
    var onDropFavorite: (([URL]) -> Bool)?
    private var pressed: Int?                // 0 Favoriten, 1 Verlauf
    private var histBtn: NSRect { NSRect(x: bounds.width - 30, y: 1, width: 28, height: bounds.height - 2) }
    private var favBtn: NSRect { NSRect(x: bounds.width - 58, y: 1, width: 26, height: bounds.height - 2) }
    private var dropHi = false
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        if active { gradient([(0, NSColor(122, 178, 236)), (0.5, NSColor(84, 150, 224)), (1, NSColor(58, 124, 204))]).draw(in: bounds, angle: 90); NSColor(40, 100, 180).setFill() }
        else { gradient([(0, NSColor(gray: 232)), (1, NSColor(gray: 205))]).draw(in: bounds, angle: 90); NSColor(gray: 150).setFill() }
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        NSColor(white: 1, alpha: active ? 0.45 : 0.7).setFill(); NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        let ink = active ? NSColor.white : NSColor(gray: 70)
        // Favoriten: Stern (gefüllt, wenn der aktuelle Ordner Favorit ist)
        let fb = favBtn
        if pressed == 0 || dropHi { NSColor(0, 0, 0, dropHi ? 0.28 : 0.18).setFill(); NSBezierPath(roundedRect: fb, xRadius: 3, yRadius: 3).fill() }
        let sc = NSPoint(x: fb.midX - 3, y: fb.midY + 0.5)
        let star = NSBezierPath()
        for i in 0..<10 { let ang = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5, rad: CGFloat = i % 2 == 0 ? 5.6 : 2.4; let p = NSPoint(x: sc.x + cos(ang) * rad, y: sc.y + sin(ang) * rad); i == 0 ? star.move(to: p) : star.line(to: p) }
        star.close()
        if isFavorite { (active ? NSColor(255, 226, 110) : NSColor(222, 170, 30)).setFill(); star.fill() }
        ink.setStroke(); star.lineWidth = 1; star.stroke()
        ink.setFill(); let ft = NSBezierPath(); ft.move(to: NSPoint(x: fb.maxX - 9, y: fb.midY - 1.6)); ft.line(to: NSPoint(x: fb.maxX - 3, y: fb.midY - 1.6)); ft.line(to: NSPoint(x: fb.maxX - 6, y: fb.midY + 2.2)); ft.close(); ft.fill()
        // Verlauf: Uhr ▾
        let b = histBtn
        if pressed == 1 { NSColor(0, 0, 0, 0.18).setFill(); NSBezierPath(roundedRect: b, xRadius: 3, yRadius: 3).fill() }
        let c = NSPoint(x: b.minX + 9, y: b.midY)
        ink.setStroke(); let o = NSBezierPath(ovalIn: NSRect(x: c.x - 4.2, y: c.y - 4.2, width: 8.4, height: 8.4)); o.lineWidth = 1.1; o.stroke()
        let h = NSBezierPath(); h.lineWidth = 1.1; h.move(to: NSPoint(x: c.x, y: c.y - 2.6)); h.line(to: NSPoint(x: c.x, y: c.y)); h.line(to: NSPoint(x: c.x + 2, y: c.y + 1.2)); h.stroke()
        ink.setFill(); let t = NSBezierPath(); t.move(to: NSPoint(x: b.minX + 17, y: c.y - 1.6)); t.line(to: NSPoint(x: b.minX + 23, y: c.y - 1.6)); t.line(to: NSPoint(x: b.minX + 20, y: c.y + 2.2)); t.close(); t.fill()
    }
    override func hitTest(_ p: NSPoint) -> NSView? { let q = convert(p, from: superview); return histBtn.contains(q) || favBtn.contains(q) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if favBtn.contains(p) { pressed = 0; needsDisplay = true; onFavorites?(favBtn) }
        else if histBtn.contains(p) { pressed = 1; needsDisplay = true; onHistory?(histBtn) }
        pressed = nil; needsDisplay = true
    }
    override func viewDidMoveToSuperview() { toolTip = L("Favoriten (⌥⌘B) und Verlauf (⌥↓) dieser Hälfte", "Favorites (⌥⌘B) and history (⌥↓) of this pane") }
    // Ordner auf den Stern ziehen = als Favorit merken
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { dropHi = true; needsDisplay = true; return .link }
    override func draggingExited(_ s: NSDraggingInfo?) { dropHi = false; needsDisplay = true }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        dropHi = false; needsDisplay = true
        let urls = (s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        return onDropFavorite?(urls) ?? false
    }
}

/// Trennlinie zwischen den Hälften: 5 pt breite, plastische Rille im Finder-Grau
final class PaneDivider: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ r: NSRect) {
        let cols: [NSColor] = [NSColor(gray: 128), NSColor(gray: 214), NSColor(gray: 238), NSColor(gray: 200), NSColor(gray: 120)]
        for (i, c) in cols.enumerated() where CGFloat(i) < bounds.width { c.setFill(); NSRect(x: CGFloat(i), y: 0, width: 1, height: bounds.height).fill() }
    }
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
}
