import AppKit

/// Symbolansicht (A-01, A-02, A-08): Raster/freie Positionen, Gruppierung, Auswahlrechteck, Drag & Drop, Umbenennen.
final class IconView: NSView, ItemView, NSTextFieldDelegate, NSDraggingSource {
    weak var host: BrowserHost?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private struct Cell { var node: FileNode; var frame: NSRect; var icon: NSRect; var lines: [String]; var labelRect: NSRect; var group: Int }
    private var cells: [Cell] = []
    private var headers: [(rect: NSRect, title: String, group: Int, total: Int, shown: Int)] = []
    func axCells() -> [(node: FileNode, frame: NSRect)] { cells.map { ($0.node, $0.frame) } }
    private var rubber: NSRect?
    private var rubberBase: [URL] = []
    private var dropIndex: Int?
    private var dropBackground = false
    private var typed = ""; private var typedAt = Date.distantPast
    private var renaming: (field: NSTextField, node: FileNode)?
    private var anchor: URL?
    private var springTimer: Timer?
    private var downIndex: Int?
    private var downPoint = NSPoint.zero
    private var draggedPositions: [String: NSPoint] = [:]
    var desktop = false
    private var amf: Bool { if case .allMyFiles = host?.location ?? .computer { return true }; return false }
    private var opts: ViewOptions { host?.options ?? ViewOptions() }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityRole(.list)
        NotificationCenter.default.addObserver(self, selector: #selector(thumb), name: .thumbReady, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(thumb), name: .sizeReady, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func thumb() { needsDisplay = true }

    // MARK: Layout
    func reload() { endRename(commit: false); relayout(); needsDisplay = true }
    func applyOptions() { relayout(); needsDisplay = true }
    override func setFrameSize(_ s: NSSize) { let old = frame.width; super.setFrameSize(s); if abs(old - s.width) > 0.5 { relayout() } }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); relayout() }

    private var availableWidth: CGFloat { enclosingScrollView?.contentSize.width ?? bounds.width }
    private var availableHeight: CGFloat { enclosingScrollView?.contentSize.height ?? bounds.height }

    func relayout() {
        guard let host else { return }
        cells = []; headers = []
        let o = opts
        let isz = amf ? 64 : o.iconSize
        let font = lucida(o.textSize)
        let labelW: CGFloat = amf ? 132 : max(isz, o.labelRight ? 100 : 0) + (o.labelRight ? 0 : max(8, o.gridSpacing - 12))
        let cellW: CGFloat = o.labelRight ? isz + 8 + 100 + 14 : (amf ? 142 : isz + o.gridSpacing)
        let lineH = ceil(o.textSize * 1.25)
        let infoLines = o.showInfo ? 1 : 0
        let cellH: CGFloat = o.labelRight ? max(isz + 12, 40) : 6 + isz + 4 + lineH * CGFloat(2 + infoLines) + 8
        let W = max(availableWidth, 50)
        let margin: CGFloat = 8
        var y: CGFloat = 4
        let grouped = host.groups.count > 1 || host.groups.first?.title != nil
        var frames: [String: NSRect] = [:]
        let free = !grouped && o.arrange == "none" && !amf && !o.snapToGrid
        var occupied: [NSRect] = []
        if free { for g in host.groups { for n in g.nodes { if let p = o.userPositions[n.url.path] { occupied.append(NSRect(x: p[0], y: p[1], width: cellW, height: cellH)) } } } }
        for (gi, g) in host.groups.enumerated() {
            if let t = g.title {
                let hh: CGFloat = 19
                let exp = host.expandedGroups.contains(t)
                let perRow = max(1, Int((W - margin * 2) / cellW))
                let shown = amf ? (exp ? g.nodes.count : min(g.nodes.count, perRow)) : g.nodes.count
                headers.append((NSRect(x: 0, y: y, width: W, height: hh), t, gi, g.total, shown)); y += hh + 1
                if g.nodes.isEmpty { continue }
                let cols = max(1, Int((W - margin * 2) / cellW))
                let list = Array(g.nodes.prefix(shown))
                for (i, n) in list.enumerated() {
                    let c = i % cols, r = i / cols
                    let f = NSRect(x: margin + CGFloat(c) * cellW, y: y + CGFloat(r) * cellH, width: cellW, height: cellH)
                    cells.append(makeCell(n, f, isz, font, labelW, lineH, gi))
                }
                y += CGFloat((list.count + cols - 1) / cols) * cellH + (amf ? 6 : 10)
            } else {
                let cols = max(1, Int((W - margin * 2) / cellW))
                var slot = 0
                for n in g.nodes {
                    var f: NSRect
                    if free, let p = o.userPositions[n.url.path] { f = NSRect(x: p[0], y: p[1], width: cellW, height: cellH) }
                    else if desktop && n.isVolume { let k = occupied.count; f = NSRect(x: W - cellW - 12, y: 30 + CGFloat(k) * cellH, width: cellW, height: cellH); occupied.append(f) }
                    else {
                        repeat { f = NSRect(x: margin + CGFloat(slot % cols) * cellW, y: y + CGFloat(slot / cols) * cellH, width: cellW, height: cellH); slot += 1 } while free && occupied.contains(where: { $0.intersects(f.insetBy(dx: 4, dy: 4)) })
                        if free { occupied.append(f) }
                    }
                    frames[n.url.path] = f
                    cells.append(makeCell(n, f, isz, font, labelW, lineH, gi))
                }
            }
        }
        let maxY = max(cells.map { $0.frame.maxY }.max() ?? 0, headers.last.map { $0.rect.maxY } ?? 0) + 12
        let maxX = max(W, (cells.map { $0.frame.maxX }.max() ?? 0) + 8)
        let newSize = NSSize(width: free ? maxX : W, height: max(maxY, availableHeight))
        if newSize != frame.size { super.setFrameSize(newSize) }
        if let r = renaming { r.field.frame = labelEditRect(for: r.node) }
    }

    private func makeCell(_ n: FileNode, _ f: NSRect, _ isz: CGFloat, _ font: NSFont, _ labelW: CGFloat, _ lineH: CGFloat, _ g: Int) -> Cell {
        let o = opts
        let name = displayName(n)
        let lw = o.labelRight ? 100 : min(f.width - 2, labelW)
        let lines = wrapLabel(name, width: lw - 8, font: font)
        let icon: NSRect, label: NSRect
        if o.labelRight {
            icon = NSRect(x: f.minX + 4, y: f.midY - isz / 2, width: isz, height: isz)
            let h = lineH * CGFloat(lines.count) + 4
            label = NSRect(x: icon.maxX + 6, y: f.midY - h / 2, width: min(lw, textWidth(lines, font) + 12), height: h)
        } else {
            icon = NSRect(x: f.midX - isz / 2, y: f.minY + 6, width: isz, height: isz)
            let tw = min(lw, textWidth(lines, font) + 12)
            let h = lineH * CGFloat(lines.count) + 3
            label = NSRect(x: f.midX - tw / 2, y: icon.maxY + 4, width: tw, height: h)
        }
        return Cell(node: n, frame: f, icon: icon, lines: lines, labelRect: label, group: g)
    }
    private func textWidth(_ lines: [String], _ font: NSFont) -> CGFloat { lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0 }
    private func displayName(_ n: FileNode) -> String {
        if !Prefs.showExtensions && !n.isDir, !n.url.pathExtension.isEmpty { return (n.name as NSString).deletingPathExtension }
        return n.name
    }

    // MARK: Zeichnen
    override func draw(_ dirty: NSRect) {
        if !desktop { bgColor().setFill(); dirty.fill() }
        if let p = opts.bgImage, let img = bgPicture(p) { drawBGTiled(img, dirty) }
        guard let host else { return }
        let o = opts, active = host.isActive
        let font = lucida(o.textSize)
        for h in headers where h.rect.intersects(dirty) {
            Draw.text(h.title, in: NSRect(x: 8, y: h.rect.minY + 3, width: 300, height: 14), font: lucida(11, bold: true), color: C.secHeader)
            NSColor(gray: 209).setFill(); NSRect(x: 0, y: h.rect.maxY - 1, width: bounds.width, height: 1).fill()
            if amf, h.total > h.shown || host.expandedGroups.contains(h.title) {
                let exp = host.expandedGroups.contains(h.title)
                Draw.text(exp ? L("Weniger anzeigen", "Show Less") : L("Alle anzeigen (\(Files.num(h.total)))", "Show All (\(Files.num(h.total)))"), in: NSRect(x: bounds.width - 220, y: h.rect.minY + 3, width: 212, height: 14), font: lucida(11), color: NSColor(gray: 120), align: .right)
            }
        }
        for (i, c) in cells.enumerated() where c.frame.insetBy(dx: -4, dy: -4).intersects(dirty) {
            let sel = host.isSelected(c.node.url)
            let dropHi = dropIndex == i
            // Symbol-Hintergrund bei Auswahl (graues Rechteck, Radius 5)
            if sel || dropHi {
                let p = NSBezierPath(roundedRect: c.icon.insetBy(dx: -3, dy: -3), xRadius: 5, yRadius: 5)
                (dropHi ? NSColor(54, 110, 196, 0.35) : NSColor(gray: active ? 170 : 200, 0.75)).setFill(); p.fill()
                if dropHi { NSColor(54, 110, 196).setStroke(); p.lineWidth = 2; p.stroke() }
            }
            IconCache.shared.draw(c.node, in: c.icon, preview: o.showPreview)
            drawLabel(c, sel: sel, active: active, font: font, drop: dropHi)
            if o.showInfo, !o.labelRight {   // Objektinformationen (z. B. Anzahl/Größe)
                let info = c.node.isDir ? (c.node.childCount >= 0 ? L("\(c.node.childCount) Objekte", "\(c.node.childCount) items") : "") : c.node.displaySize
                Draw.text(info, in: NSRect(x: c.frame.minX, y: c.labelRect.maxY + 1, width: c.frame.width, height: 13), font: lucida(max(9, o.textSize - 2)), color: NSColor(gray: 110), align: .center)
            }
        }
        if dropBackground { let r = bounds.insetBy(dx: 2, dy: 2); NSColor(54, 110, 196).setStroke(); let p = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6); p.lineWidth = 3; p.stroke() }
        if let r = rubber { NSColor(60, 120, 215, 0.22).setFill(); r.fill(); NSColor(60, 120, 215, 0.8).setStroke(); NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke() }
    }
    private var bgCache: (String, NSImage)?
    private func bgPicture(_ p: String) -> NSImage? { if bgCache?.0 == p { return bgCache?.1 }; guard let im = NSImage(contentsOfFile: p) else { return nil }; bgCache = (p, im); return im }
    private func drawBGTiled(_ img: NSImage, _ dirty: NSRect) {
        let s = img.size; guard s.width > 0, s.height > 0 else { return }
        var y = floor(dirty.minY / s.height) * s.height
        while y < dirty.maxY { var x = floor(dirty.minX / s.width) * s.width; while x < dirty.maxX { img.draw(in: NSRect(x: x, y: y, width: s.width, height: s.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil); x += s.width }; y += s.height }
    }
    private func bgColor() -> NSColor {
        if let c = opts.bgColor, c.count == 3 { return NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1) }
        return .white
    }
    private func drawLabel(_ c: Cell, sel: Bool, active: Bool, font: NSFont, drop: Bool) {
        if renaming?.node == c.node { return }
        let o = opts
        let lab = c.node.label
        let r = c.labelRect
        let ctx = NSGraphicsContext.current!
        var color = desktop ? NSColor.white : NSColor.black, shadow: NSShadow? = desktop && !sel ? { let s = NSShadow(); s.shadowColor = NSColor(0, 0, 0, 0.9); s.shadowOffset = NSSize(width: 0, height: 1); s.shadowBlurRadius = 3; return s }() : nil
        if sel {
            let p = NSBezierPath(roundedRect: r, xRadius: min(8, r.height / 2), yRadius: min(8, r.height / 2))
            (active ? NSColor(59, 114, 200) : NSColor(gray: 150)).setFill(); p.fill()
            color = .white
        } else if lab > 0 {
            let p = NSBezierPath(roundedRect: r, xRadius: min(8, r.height / 2), yRadius: min(8, r.height / 2))
            gradient([(0, C.labelPill[lab - 1].blended(withFraction: 0.35, of: .white) ?? C.labelPill[lab - 1]), (1, C.labelPill[lab - 1])]).draw(in: p, angle: 90)
            C.labelPillBorder[lab - 1].withAlphaComponent(0.55).setStroke(); p.lineWidth = 0.7; p.stroke()
        } else if drop { color = .black }
        _ = ctx
        if c.node.isHidden { color = color.withAlphaComponent(0.5) }
        let lineH = ceil(o.textSize * 1.25)
        for (i, l) in c.lines.enumerated() {
            let ps = NSMutableParagraphStyle(); ps.alignment = o.labelRight ? .left : .center; ps.lineBreakMode = .byClipping
            var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: ps]
            if let shadow { a[.shadow] = shadow }
            (l as NSString).draw(in: NSRect(x: r.minX + 4, y: r.minY + 1.5 + CGFloat(i) * lineH, width: r.width - 8, height: lineH + 2), withAttributes: a)
        }
        if sel && lab > 0 { // Etikettfarbe bleibt als Punkt sichtbar
            C.labelFill[lab - 1].setFill(); NSBezierPath(ovalIn: NSRect(x: r.maxX - 3, y: r.minY - 2, width: 6, height: 6)).fill()
        }
    }

    // MARK: Hit-Test
    private func index(at p: NSPoint) -> Int? {
        for (i, c) in cells.enumerated().reversed() where c.icon.insetBy(dx: -2, dy: -2).contains(p) || c.labelRect.contains(p) { return i }
        return nil
    }
    private func headerIndex(at p: NSPoint) -> Int? { headers.firstIndex { $0.rect.contains(p) } }

    // MARK: Maus
    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        endRename(commit: true)
        guard let host else { return }
        let p = convert(e.locationInWindow, from: nil)
        downPoint = p
        if let hi = headerIndex(at: p), amf {
            let h = headers[hi]
            if p.x > bounds.width - 230 { var s = host.expandedGroups; if s.contains(h.title) { s.remove(h.title) } else { s.insert(h.title) }; host.expandedGroups = s; relayout(); needsDisplay = true }
            return
        }
        if let i = index(at: p) {
            downIndex = i
            let n = cells[i].node
            if e.clickCount == 2 { host.open(n, modifiers: e.modifierFlags); return }
            if e.modifierFlags.contains(.command) { var s = host.selection; if let k = s.firstIndex(of: n.url) { s.remove(at: k) } else { s.append(n.url) }; host.setSelection(s, source: self); anchor = n.url }
            else if e.modifierFlags.contains(.shift), let a = anchor, let ai = cells.firstIndex(where: { $0.node.url == a }) {
                let r = min(ai, i)...max(ai, i); host.setSelection(r.map { cells[$0].node.url }, source: self)
            } else if !host.isSelected(n.url) { host.setSelection([n.url], source: self); anchor = n.url }
            // Klick in bereits gewählte Auswahl: erst bei mouseUp neu wählen (Drag bleibt möglich)
            needsDisplay = true
            // Umbenennen per Klick auf ausgewählten Namen (ohne Doppelklick) – nach kurzer Pause
            if host.selection.count == 1 && host.isSelected(n.url) && cells[i].labelRect.contains(p) && e.clickCount == 1 && lastClick?.url == n.url && Date().timeIntervalSince(lastClick!.t) > 0.5 && Date().timeIntervalSince(lastClick!.t) < 2 { renameTimer?.invalidate(); renameTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in self?.startRename() } }
            lastClick = (n.url, Date())
        } else {
            downIndex = nil
            renameTimer?.invalidate()
            if !e.modifierFlags.contains(.command) && !e.modifierFlags.contains(.shift) { host.setSelection([], source: self) }
            rubberBase = host.selection; rubber = NSRect(origin: p, size: .zero)
        }
    }
    private var lastClick: (url: URL, t: Date)?
    private var renameTimer: Timer?

    override func mouseDragged(with e: NSEvent) {
        guard let host else { return }
        let p = convert(e.locationInWindow, from: nil)
        if rubber != nil {
            let r = NSRect(x: min(downPoint.x, p.x), y: min(downPoint.y, p.y), width: abs(p.x - downPoint.x), height: abs(p.y - downPoint.y)); rubber = r
            var sel = e.modifierFlags.contains(.command) || e.modifierFlags.contains(.shift) ? rubberBase : []
            for c in cells where c.icon.intersects(r) || c.labelRect.intersects(r) { if !sel.contains(c.node.url) { sel.append(c.node.url) } }
            host.setSelection(sel, source: self); autoscroll(with: e); needsDisplay = true; return
        }
        guard let di = downIndex, hypot(p.x - downPoint.x, p.y - downPoint.y) > 4 else { return }
        renameTimer?.invalidate()
        let n = cells[di].node
        if !host.isSelected(n.url) { host.setSelection([n.url], source: self) }
        let urls = host.selection
        var items: [NSDraggingItem] = []
        for u in urls {
            guard let c = cells.first(where: { $0.node.url == u }) else { continue }
            let it = NSDraggingItem(pasteboardWriter: u as NSURL)
            let img = NSImage(size: c.icon.size, flipped: true) { r in IconCache.shared.draw(c.node, in: r, preview: self.opts.showPreview); return true }
            it.setDraggingFrame(c.icon, contents: img)
            items.append(it)
        }
        if items.isEmpty { return }
        dragStartOrigins = Dictionary(uniqueKeysWithValues: cells.filter { urls.contains($0.node.url) }.map { ($0.node.url.path, $0.frame.origin) })
        beginDraggingSession(with: items, event: e, source: self)
    }
    private var dragStartOrigins: [String: NSPoint] = [:]
    override func mouseUp(with e: NSEvent) {
        if rubber != nil { rubber = nil; needsDisplay = true; return }
        guard let host else { return }
        let p = convert(e.locationInWindow, from: nil)
        if let i = downIndex, hypot(p.x - downPoint.x, p.y - downPoint.y) < 4, !e.modifierFlags.contains(.command), !e.modifierFlags.contains(.shift), e.clickCount == 1, host.selection.count > 1 { host.setSelection([cells[i].node.url], source: self); anchor = cells[i].node.url }
        downIndex = nil
    }
    override func rightMouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        guard let host else { return }
        let p = convert(e.locationInWindow, from: nil)
        if let i = index(at: p) { if !host.isSelected(cells[i].node.url) { host.setSelection([cells[i].node.url], source: self) } }
        else { host.setSelection([], source: self) }
        NSMenu.popUpContextMenu(host.contextMenu(for: index(at: p).map { cells[$0].node }), with: e, for: self)
    }
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    // MARK: Auswahl-Update von außen
    func selectionChanged() { needsDisplay = true }
    func revealSelection() {
        guard let host, let u = host.selection.first, let c = cells.first(where: { $0.node.url == u }) else { return }
        scrollToVisible(c.frame.insetBy(dx: 0, dy: -4))
    }

    // MARK: Tastatur
    override func keyDown(with e: NSEvent) {
        guard let host else { return }
        let ch = e.charactersIgnoringModifiers ?? ""
        switch e.keyCode {
        case 123, 124, 125, 126: arrow(e.keyCode, extend: e.modifierFlags.contains(.shift)); return
        case 36, 76: if e.modifierFlags.contains(.command) { host.openSelection() } else { startRename() }; return
        case 49: host.quickLook(); return
        case 53: return
        case 48: tab(back: e.modifierFlags.contains(.shift)); return
        case 51, 117: if e.modifierFlags.contains(.command) { host.trashSelection(); return }
        default: break
        }
        if e.modifierFlags.intersection([.command, .control]).isEmpty, let c = ch.unicodeScalars.first, c.value >= 32, c.value != 127, c.value < 0xF700 {
            if Date().timeIntervalSince(typedAt) > 1 { typed = "" }
            typed += ch.lowercased(); typedAt = Date()
            if let m = cells.first(where: { $0.node.name.lowercased().hasPrefix(typed) }) { host.setSelection([m.node.url], source: self); anchor = m.node.url; revealSelection() }
            return
        }
        super.keyDown(with: e)
    }
    private func tab(back: Bool) {
        guard let host, !cells.isEmpty else { return }
        let cur = host.selection.first.flatMap { u in cells.firstIndex { $0.node.url == u } } ?? (back ? 0 : -1)
        let n = (cur + (back ? -1 : 1) + cells.count) % cells.count
        host.setSelection([cells[n].node.url], source: self); anchor = cells[n].node.url; revealSelection()
    }
    private func arrow(_ code: UInt16, extend: Bool) {
        guard let host, !cells.isEmpty else { return }
        let curURL = host.selection.last ?? host.selection.first
        guard let cur = curURL.flatMap({ u in cells.firstIndex { $0.node.url == u } }) else { host.setSelection([cells[0].node.url], source: self); anchor = cells[0].node.url; revealSelection(); return }
        let c = cells[cur].frame
        var best: Int?; var bestScore = CGFloat.infinity
        for (i, o) in cells.enumerated() where i != cur {
            let f = o.frame
            let dx = f.midX - c.midX, dy = f.midY - c.midY
            var ok = false, score: CGFloat = 0
            switch code {
            case 123: ok = dx < -1 && abs(dy) < c.height * 0.6; score = abs(dx) + abs(dy) * 3
            case 124: ok = dx > 1 && abs(dy) < c.height * 0.6; score = abs(dx) + abs(dy) * 3
            case 125: ok = dy > 1; score = abs(dy) * 3 + abs(dx)
            default: ok = dy < -1; score = abs(dy) * 3 + abs(dx)
            }
            if ok && score < bestScore { bestScore = score; best = i }
        }
        if best == nil && code == 125 { best = nil }
        if let b = best {
            if extend, let a = anchor, let ai = cells.firstIndex(where: { $0.node.url == a }) { host.setSelection((min(ai, b)...max(ai, b)).map { cells[$0].node.url }, source: self) }
            else { host.setSelection([cells[b].node.url], source: self); anchor = cells[b].node.url }
            revealSelection()
        }
    }
    override func selectAll(_ sender: Any?) { host?.setSelection(cells.map { $0.node.url }, source: self) }

    // MARK: Umbenennen
    private func labelEditRect(for n: FileNode) -> NSRect {
        guard let c = cells.first(where: { $0.node == n }) else { return .zero }
        let w = max(c.labelRect.width + 20, 100)
        return opts.labelRight ? NSRect(x: c.labelRect.minX - 2, y: c.labelRect.midY - 9, width: w, height: 18) : NSRect(x: c.frame.midX - w / 2, y: c.labelRect.minY - 1, width: w, height: 18)
    }
    func startRename() {
        guard let host, host.selection.count == 1, let u = host.selection.first, let c = cells.first(where: { $0.node.url == u }) else { return }
        endRename(commit: true)
        let f = NSTextField(frame: labelEditRect(for: c.node))
        f.stringValue = c.node.name; f.font = lucida(opts.textSize); f.alignment = opts.labelRight ? .left : .center
        f.isBordered = true; f.bezelStyle = .squareBezel; f.focusRingType = .exterior; f.delegate = self; f.usesSingleLineMode = true
        f.cell?.isScrollable = true
        addSubview(f); window?.makeFirstResponder(f)
        // Namensteil ohne Erweiterung markieren (F-05)
        let ext = (c.node.name as NSString).pathExtension
        if !c.node.isDir, !ext.isEmpty { f.currentEditor()?.selectedRange = NSRange(location: 0, length: (c.node.name as NSString).deletingPathExtension.count) }
        else { f.currentEditor()?.selectAll(nil) }
        renaming = (f, c.node); needsDisplay = true
    }
    func control(_ c: NSControl, textView: NSTextView, doCommandBy s: Selector) -> Bool {
        if s == #selector(NSResponder.insertNewline(_:)) { endRename(commit: true); return true }
        if s == #selector(NSResponder.cancelOperation(_:)) { endRename(commit: false); return true }
        return false
    }
    func controlTextDidEndEditing(_ obj: Notification) { if renaming != nil { endRename(commit: (obj.userInfo?["NSTextMovement"] as? Int) != NSCancelTextMovement) } }
    func endRename(commit: Bool) {
        guard let r = renaming else { return }
        renaming = nil
        let s = r.field.stringValue
        r.field.removeFromSuperview(); window?.makeFirstResponder(self)
        if commit, s != r.node.name { host?.rename(r.node, to: s) }
        needsDisplay = true
    }

    // MARK: Drag-Quelle
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? [.copy, .move, .link, .generic] : [.copy, .link, .generic] }
    func draggingSession(_ session: NSDraggingSession, endedAt p: NSPoint, operation: NSDragOperation) { dropIndex = nil; dropBackground = false; springTimer?.invalidate(); needsDisplay = true }

    // MARK: Drag-Ziel (F-07…F-09)
    private func dropInfo(_ s: NSDraggingInfo) -> (urls: [URL], idx: Int?) {
        let urls = (s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let p = convert(s.draggingLocation, from: nil)
        var idx = index(at: p)
        if let i = idx, !(cells[i].node.isFolderLike || cells[i].node.isVolume || cells[i].node.isAlias && false) || urls.contains(cells[i].node.url) { idx = nil }
        if let i = idx, !cells[i].node.isFolderLike && !cells[i].node.isVolume && cells[i].node.url.pathExtension != Files.burnExt { idx = nil }
        return (urls, idx)
    }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { draggingUpdated(s) }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation {
        guard let host else { return [] }
        let (urls, idx) = dropInfo(s)
        let old = dropIndex; dropIndex = idx
        let internalSource = (s.draggingSource as? IconView) === self
        dropBackground = idx == nil && !(internalSource) && host.currentDir != nil
        if old != idx {
            springTimer?.invalidate()
            if let i = idx, Prefs.springLoading { let n = cells[i].node; springTimer = Timer.scheduledTimer(withTimeInterval: Prefs.springDelay, repeats: false) { [weak self] _ in self?.host?.springOpen(n) } }
        }
        needsDisplay = true
        if idx == nil && internalSource && host.options.arrange == "none" { return .generic }       // freies Umpositionieren
        return host.dragOperation(urls, into: idx.map { cells[$0].node.url } ?? host.currentDir, flags: NSEvent.modifierFlags)
    }
    override func draggingExited(_ s: NSDraggingInfo?) { dropIndex = nil; dropBackground = false; springTimer?.invalidate(); needsDisplay = true }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        guard let host else { return false }
        defer { dropIndex = nil; dropBackground = false; springTimer?.invalidate(); needsDisplay = true }
        let (urls, idx) = dropInfo(s)
        if idx == nil, (s.draggingSource as? IconView) === self, host.options.arrange == "none" {
            // freie Positionierung: Versatz der gezogenen Auswahl übernehmen
            let p = convert(s.draggingLocation, from: nil); var o = host.options
            let first = urls.first.flatMap { dragStartOrigins[$0.path] }
            guard let f0 = first else { return false }
            let base = NSPoint(x: p.x - downPoint.x, y: p.y - downPoint.y)
            for u in urls { if let org = dragStartOrigins[u.path] {
                var np = NSPoint(x: org.x + base.x, y: org.y + base.y)
                if o.snapToGrid { let cw = o.iconSize + o.gridSpacing; np.x = round(np.x / cw) * cw + 8; np.y = round(np.y / 100) * 100 + 4 }
                o.userPositions[u.path] = [max(0, np.x), max(0, np.y)]
            } }
            _ = f0
            host.options = o; relayout(); return true
        }
        return host.performDrop(urls, into: idx.map { cells[$0].node.url } ?? host.currentDir, flags: NSEvent.modifierFlags)
    }

    /// Aufräumen (A-08): freie Positionen verwerfen bzw. am Raster ausrichten
    func cleanUp() { var o = opts; o.userPositions = [:]; host?.options = o; relayout(); needsDisplay = true }

    /// Idealgröße für „Zoom“ (Inhalt)
    func idealContentSize() -> NSSize {
        NSSize(width: max(cells.map { $0.frame.maxX }.max() ?? 300, 300) + 16, height: (cells.map { $0.frame.maxY }.max() ?? 100) + 12)
    }
}
