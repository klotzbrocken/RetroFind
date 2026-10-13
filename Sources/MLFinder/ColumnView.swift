import AppKit
import QuickLookThumbnailing

/// Spaltenansicht (A-05): horizontale Hierarchie, einstellbare Breite, Vorschauspalte, Tastaturnavigation.
final class ColumnView: NSView, ItemView, NSDraggingSource {
    weak var host: BrowserHost?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    let strip = NSScrollView()
    let doc = FlippedView()
    var panes: [ColumnPane] = []
    var preview: PreviewPane?
    var activeIndex = 0
    var colW: CGFloat { host?.options.colWidth ?? 186 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        strip.documentView = doc; strip.hasHorizontalScroller = true; strip.hasVerticalScroller = false; strip.scrollerStyle = .legacy; strip.autohidesScrollers = true; strip.drawsBackground = true; strip.backgroundColor = .white
        addSubview(strip); setAccessibilityRole(.browser)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); strip.frame = bounds; relayout() }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? [.copy, .move, .link, .generic] : [.copy, .link, .generic] }

    func reload() {
        guard let host else { return }
        let sel = host.selection
        panes.forEach { $0.removeFromSuperview() }; panes = []; preview?.removeFromSuperview(); preview = nil
        addPane(dir: host.currentDir, nodes: host.nodes, index: 0)
        if let s = sel.first { showPath(to: s) }
        relayout()
    }
    func applyOptions() { relayout() }

    func addPane(dir: URL?, nodes: [FileNode], index: Int) {
        let p = ColumnPane(owner: self, dir: dir, nodes: nodes, index: index)
        doc.addSubview(p); panes.append(p)
    }
    private func popPanes(after i: Int) {
        while panes.count > i + 1 { panes.removeLast().removeFromSuperview() }
        preview?.removeFromSuperview(); preview = nil
    }
    func showPath(to url: URL) {
        guard let host, let root = host.currentDir else { return }
        let rp = root.standardizedFileURL.path, up = url.standardizedFileURL.path
        guard up.hasPrefix(rp + "/") else { return }
        // Komponenten relativ zum Wurzelordner; Knoten je Spalte über den Namen finden (Symlink-Präfixe, Schrägstrich bei Ordner-URLs)
        let comps = up.dropFirst(rp.count + 1).split(separator: "/").map(String.init)
        popPanes(after: 0)
        for (i, comp) in comps.enumerated() {
            guard let p = panes[safe: i], let n = p.nodes.first(where: { $0.url.lastPathComponent == comp }) else { break }
            p.selected = [n.url]; push(from: i)
        }
    }
    /// Auswahl in Spalte i hat sich geändert → folgende Spalte(n) aufbauen
    func push(from i: Int) {
        popPanes(after: i)
        let p = panes[i]
        activeIndex = i
        if p.selected.count == 1, let n = p.nodes.first(where: { $0.url == p.selected[0] }) {
            var target = n
            if n.isAlias, let t = Alias.resolve(n.url) { target = FileNode(url: t) }
            if target.isFolderLike || target.isVolume {
                let kids = ((try? Files.list(target.url)) ?? []).map { FileNode(url: $0) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                let kids2 = Prefs.foldersFirst ? kids.filter { $0.isFolderLike || $0.isVolume } + kids.filter { !($0.isFolderLike || $0.isVolume) } : kids
                addPane(dir: target.url, nodes: kids2, index: i + 1)
            } else if host?.options.colPreview ?? true {
                let pv = PreviewPane(node: n); doc.addSubview(pv); preview = pv
            }
        }
        relayout()
        host?.setSelection(p.selected, source: self)
        for q in panes { q.needsDisplay = true }
        scrollToEnd()
    }
    func relayout() {
        var x: CGFloat = 0
        let h = max(10, strip.contentSize.height)
        for p in panes { p.frame = NSRect(x: x, y: 0, width: colW, height: h); x += colW }
        if let pv = preview { pv.frame = NSRect(x: x, y: 0, width: max(colW, 230), height: h); x += max(colW, 230) }
        doc.frame = NSRect(x: 0, y: 0, width: max(x, strip.contentSize.width), height: h)
    }
    func scrollToEnd() { let r = NSRect(x: doc.frame.width - 10, y: 0, width: 10, height: 10); doc.scrollToVisible(r) }
    func setColWidth(_ w: CGFloat) { var o = host!.options; o.colWidth = max(80, min(600, w)); host!.options = o; relayout() }

    func selectionChanged() {
        if let u = host?.selection.first, !panes.contains(where: { $0.selected.contains(u) }) { showPath(to: u) }
        else if host?.selection.isEmpty == true, panes.count > 0, !(panes[0].selected.isEmpty) { panes[0].selected = []; popPanes(after: 0); relayout() }
        panes.forEach { $0.rowsDoc.needsDisplay = true }
    }
    func revealSelection() { if let u = host?.selection.first { showPath(to: u) } }
    func startRename() { panes[safe: activeIndex]?.startRename() }
    override func keyDown(with e: NSEvent) { panes[safe: activeIndex]?.keyDown(with: e) }
    override func selectAll(_ sender: Any?) { panes[safe: activeIndex]?.selectAllRows() }
    func focusPane(_ i: Int) { activeIndex = i; panes.forEach { $0.needsDisplay = true }; window?.makeFirstResponder(panes[i]) }
}

extension Array { subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil } }
final class FlippedView: NSView { override var isFlipped: Bool { true } }

// MARK: Eine Spalte

final class ColumnPane: NSView, NSTextFieldDelegate {
    weak var owner: ColumnView?
    let dir: URL?; var nodes: [FileNode]; let index: Int
    var selected: [URL] = []
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    let rh: CGFloat = 20
    private var anchor: URL?; private var scrollY: CGFloat = 0
    private var downRow: Int?; private var downPt = NSPoint.zero; private var dragStarted = false
    private var dropRow: Int?; private var dropBG = false
    private var typed = ""; private var typedAt = Date.distantPast
    private var renaming: (NSTextField, FileNode)?
    private var resizing = false
    let scroller = NSScrollView(); let rowsDoc = ColumnRows()

    init(owner: ColumnView, dir: URL?, nodes: [FileNode], index: Int) {
        self.owner = owner; self.dir = dir; self.nodes = nodes; self.index = index
        super.init(frame: .zero)
        rowsDoc.pane = self
        scroller.documentView = rowsDoc; scroller.hasVerticalScroller = true; scroller.scrollerStyle = .legacy; scroller.autohidesScrollers = true; scroller.drawsBackground = false; scroller.borderType = .noBorder
        addSubview(scroller)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); scroller.frame = NSRect(x: 0, y: 0, width: bounds.width - 1, height: bounds.height); rowsDoc.frame = NSRect(x: 0, y: 0, width: bounds.width - 1, height: max(CGFloat(nodes.count) * rh + 4, scroller.contentSize.height)) }
    override func draw(_ r: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        NSColor(gray: 192).setFill(); NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
        // Anfasser zum Verbreitern (unten rechts)
        NSColor(gray: 160).setStroke()
        for k in 0..<3 { let p = NSBezierPath(); p.lineWidth = 1; p.move(to: NSPoint(x: bounds.width - 4 - CGFloat(k) * 3, y: bounds.height - 2)); p.line(to: NSPoint(x: bounds.width - 2, y: bounds.height - 4 - CGFloat(k) * 3)); p.stroke() }
    }
    private func inHandle(_ p: NSPoint) -> Bool { p.x > bounds.width - 15 && p.y > bounds.height - 15 }
    override func resetCursorRects() { addCursorRect(NSRect(x: bounds.width - 15, y: bounds.height - 15, width: 15, height: 15), cursor: .resizeLeftRight) }
    var isActive: Bool { owner?.activeIndex == index && (owner?.host?.isActive ?? true) }

    func rowAt(_ y: CGFloat) -> Int? { let i = Int(y / rh); return y >= 0 && i < nodes.count ? i : nil }
    func drawRows(_ dirty: NSRect) {
        guard let host = owner?.host else { return }
        let first = max(0, Int(dirty.minY / rh)), last = min(nodes.count - 1, Int(dirty.maxY / rh))
        guard first <= last else { return }
        let active = owner?.activeIndex == index && host.isActive
        for i in first...last {
            let n = nodes[i]; let y = CGFloat(i) * rh
            let r = NSRect(x: 0, y: y, width: rowsDoc.bounds.width, height: rh)
            let sel = selected.contains(n.url)
            if n.label > 0 && !sel { C.labelPill[n.label - 1].setFill(); r.fill() }
            if sel { if active { Draw.listSelection(r, active: true) } else { NSGradient(starting: NSColor(gray: 188), ending: NSColor(gray: 160))?.draw(in: r, angle: 90) } }
            if dropRow == i { C.listSel.setStroke(); let p = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3); p.lineWidth = 2; p.stroke() }
            IconCache.shared.draw(n, in: NSRect(x: 6, y: y + 1, width: 16, height: 16), preview: false)
            let hasArrow = n.isFolderLike || n.isVolume || (n.isAlias && (Alias.resolve(n.url).map { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } ?? false))
            let tw = rowsDoc.bounds.width - 28 - (hasArrow ? 18 : 6)
            Draw.text(n.name, in: NSRect(x: 27, y: y + 2, width: tw, height: 15), font: lucida(host.options.listTextSize + 1), color: sel && active ? .white : .black, shadow: sel && active ? Draw.darkShadow(0.4) : nil, truncate: .byTruncatingMiddle)
            if hasArrow { let c = NSPoint(x: rowsDoc.bounds.width - 11, y: y + rh / 2); let p = NSBezierPath(); p.move(to: NSPoint(x: c.x - 2, y: c.y - 4)); p.line(to: NSPoint(x: c.x + 3, y: c.y)); p.line(to: NSPoint(x: c.x - 2, y: c.y + 4)); p.close(); (sel && active ? NSColor.white : NSColor(gray: 90)).setFill(); p.fill() }
        }
        if dropBG { C.listSel.setStroke(); let p = NSBezierPath(rect: rowsDoc.bounds.insetBy(dx: 1, dy: 1)); p.lineWidth = 2; p.stroke() }
    }

    func select(_ i: Int, extend: Bool = false) {
        guard let o = owner, !nodes.isEmpty else { return }
        let c = max(0, min(nodes.count - 1, i))
        if extend, let a = anchor, let ai = nodes.firstIndex(where: { $0.url == a }) { selected = (min(ai, c)...max(ai, c)).map { nodes[$0].url } } else { selected = [nodes[c].url]; anchor = nodes[c].url }
        o.push(from: index); o.focusPane(index); rowsDoc.scrollToVisible(NSRect(x: 0, y: CGFloat(c) * rh, width: 10, height: rh)); rowsDoc.needsDisplay = true
    }
    func selectAllRows() { selected = nodes.map { $0.url }; owner?.push(from: index); rowsDoc.needsDisplay = true }

    // MARK: Maus in Zeilen
    func rowsMouseDown(_ e: NSEvent, at p: NSPoint) {
        guard let o = owner, let host = o.host else { return }
        window?.makeFirstResponder(self); o.activeIndex = index; endRename(commit: true)
        downPt = p; dragStarted = false
        guard let i = rowAt(p.y) else { downRow = nil; if !e.modifierFlags.contains(.command) { selected = []; o.push(from: index) }; rowsDoc.needsDisplay = true; return }
        downRow = i; let n = nodes[i]
        if e.clickCount == 2 { host.open(n, modifiers: e.modifierFlags); return }
        if e.modifierFlags.contains(.command) { if let k = selected.firstIndex(of: n.url) { selected.remove(at: k) } else { selected.append(n.url) }; anchor = n.url }
        else if e.modifierFlags.contains(.shift), let a = anchor, let ai = nodes.firstIndex(where: { $0.url == a }) { selected = (min(ai, i)...max(ai, i)).map { nodes[$0].url } }
        else if !selected.contains(n.url) || selected.count == 1 { selected = [n.url]; anchor = n.url }
        o.push(from: index); rowsDoc.needsDisplay = true
    }
    func rowsMouseDragged(_ e: NSEvent, at p: NSPoint) {
        guard let o = owner, let i = downRow, !dragStarted, hypot(p.x - downPt.x, p.y - downPt.y) > 4 else { return }
        dragStarted = true
        let n = nodes[i]; if !selected.contains(n.url) { selected = [n.url]; o.push(from: index) }
        var items: [NSDraggingItem] = []
        for u in selected { guard let nn = nodes.first(where: { $0.url == u }) else { continue }
            let it = NSDraggingItem(pasteboardWriter: u as NSURL)
            let img = NSImage(size: NSSize(width: 160, height: 18), flipped: true) { r in IconCache.shared.draw(nn, in: NSRect(x: 0, y: 1, width: 16, height: 16), preview: false); Draw.text(nn.name, in: NSRect(x: 20, y: 2, width: 138, height: 15), font: lucida(11), color: .black); return true }
            it.setDraggingFrame(NSRect(x: p.x - 10, y: p.y - 8, width: 160, height: 18), contents: img); items.append(it) }
        rowsDoc.beginDraggingSession(with: items, event: e, source: o)
    }
    override func mouseDown(with e: NSEvent) { let p = convert(e.locationInWindow, from: nil); if inHandle(p) { resizing = true } }
    override func mouseDragged(with e: NSEvent) { if resizing, let o = owner { o.setColWidth(o.convert(e.locationInWindow, from: nil).x - frame.minX + 6 - 0) } }
    override func mouseUp(with e: NSEvent) { resizing = false }

    // MARK: Tastatur
    override func keyDown(with e: NSEvent) {
        guard let o = owner, let host = o.host else { return }
        let cur = selected.last.flatMap { u in nodes.firstIndex { $0.url == u } }
        switch e.keyCode {
        case 125: select((cur ?? -1) + 1, extend: e.modifierFlags.contains(.shift)); return
        case 126: select((cur ?? nodes.count) - 1, extend: e.modifierFlags.contains(.shift)); return
        case 124:
            if o.panes.count > index + 1 { let next = o.panes[index + 1]; if !next.nodes.isEmpty { next.select(0) } }
            return
        case 123: if index > 0 { let prev = o.panes[index - 1]; o.popPanesPublic(after: index - 1); o.focusPane(index - 1); o.push(from: index - 1); _ = prev }; return
        case 36, 76: if e.modifierFlags.contains(.command) { host.openSelection() } else { startRename() }; return
        case 49: host.quickLook(); return
        case 51, 117: if e.modifierFlags.contains(.command) { host.trashSelection() }; return
        default: break
        }
        if e.modifierFlags.intersection([.command, .control]).isEmpty, let ch = e.charactersIgnoringModifiers, let c = ch.unicodeScalars.first, c.value >= 32, c.value < 0xF700 {
            if Date().timeIntervalSince(typedAt) > 1 { typed = "" }; typed += ch.lowercased(); typedAt = Date()
            if let i = nodes.firstIndex(where: { $0.name.lowercased().hasPrefix(typed) }) { select(i) }; return
        }
        super.keyDown(with: e)
    }

    // MARK: Umbenennen
    func startRename() {
        guard selected.count == 1, let i = nodes.firstIndex(where: { $0.url == selected[0] }) else { return }
        endRename(commit: true)
        let f = NSTextField(frame: NSRect(x: 24, y: CGFloat(i) * rh, width: rowsDoc.bounds.width - 24, height: rh)); f.stringValue = nodes[i].name; f.font = lucida(12); f.isBordered = true; f.focusRingType = .exterior; f.delegate = self
        rowsDoc.addSubview(f); window?.makeFirstResponder(f); renaming = (f, nodes[i])
        if !nodes[i].isDir, !nodes[i].url.pathExtension.isEmpty { f.currentEditor()?.selectedRange = NSRange(location: 0, length: (nodes[i].name as NSString).deletingPathExtension.count) }
    }
    func control(_ c: NSControl, textView: NSTextView, doCommandBy s: Selector) -> Bool {
        if s == #selector(NSResponder.insertNewline(_:)) { endRename(commit: true); return true }
        if s == #selector(NSResponder.cancelOperation(_:)) { endRename(commit: false); return true }
        return false
    }
    func endRename(commit: Bool) {
        guard let (f, n) = renaming else { return }; renaming = nil
        let s = f.stringValue; f.removeFromSuperview(); window?.makeFirstResponder(self)
        if commit, s != n.name { owner?.host?.rename(n, to: s) }
    }

    // MARK: Drop
    private func dropInfo(_ s: NSDraggingInfo) -> (urls: [URL], dir: URL?, row: Int?) {
        let urls = (s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let p = rowsDoc.convert(s.draggingLocation, from: nil)
        if let i = rowAt(p.y), (nodes[i].isFolderLike || nodes[i].isVolume), !urls.contains(nodes[i].url) { return (urls, nodes[i].url, i) }
        return (urls, dir, nil)
    }
    func dragUpdated(_ s: NSDraggingInfo) -> NSDragOperation {
        guard let host = owner?.host else { return [] }
        let d = dropInfo(s); dropRow = d.row; dropBG = d.row == nil; rowsDoc.needsDisplay = true
        return host.dragOperation(d.urls, into: d.dir, flags: NSEvent.modifierFlags)
    }
    func dragExited() { dropRow = nil; dropBG = false; rowsDoc.needsDisplay = true }
    func dragPerform(_ s: NSDraggingInfo) -> Bool { defer { dragExited() }; let d = dropInfo(s); return owner?.host?.performDrop(d.urls, into: d.dir, flags: NSEvent.modifierFlags) ?? false }
    func contextMenu(_ e: NSEvent, at p: NSPoint) {
        guard let o = owner, let host = o.host else { return }
        window?.makeFirstResponder(self); o.activeIndex = index
        if let i = rowAt(p.y) { if !selected.contains(nodes[i].url) { selected = [nodes[i].url]; o.push(from: index) }; NSMenu.popUpContextMenu(host.contextMenu(for: nodes[i]), with: e, for: rowsDoc) }
        else { NSMenu.popUpContextMenu(host.contextMenu(for: nil), with: e, for: rowsDoc) }
    }
}

extension ColumnView { func popPanesPublic(after i: Int) { while panes.count > i + 1 { panes.removeLast().removeFromSuperview() }; preview?.removeFromSuperview(); preview = nil } }

final class ColumnRows: NSView {
    weak var pane: ColumnPane?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirty: NSRect) { NSColor.white.setFill(); dirty.fill(); pane?.drawRows(dirty) }
    override func mouseDown(with e: NSEvent) { pane?.rowsMouseDown(e, at: convert(e.locationInWindow, from: nil)) }
    override func mouseDragged(with e: NSEvent) { pane?.rowsMouseDragged(e, at: convert(e.locationInWindow, from: nil)) }
    override func rightMouseDown(with e: NSEvent) { pane?.contextMenu(e, at: convert(e.locationInWindow, from: nil)) }
    override func keyDown(with e: NSEvent) { pane?.keyDown(with: e) }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { pane?.dragUpdated(s) ?? [] }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation { pane?.dragUpdated(s) ?? [] }
    override func draggingExited(_ s: NSDraggingInfo?) { pane?.dragExited() }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool { pane?.dragPerform(s) ?? false }
    override func viewDidMoveToSuperview() { registerForDraggedTypes([.fileURL]) }
}

// MARK: Vorschauspalte

final class PreviewPane: NSView {
    let node: FileNode
    override var isFlipped: Bool { true }
    private var big: NSImage?
    init(node: FileNode) {
        self.node = node; super.init(frame: .zero)
        NotificationCenter.default.addObserver(self, selector: #selector(thumb), name: .thumbReady, object: nil)
        let req = QLThumbnailGenerator.Request(fileAt: node.url, size: CGSize(width: 200, height: 200), scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            DispatchQueue.main.async { if let cg = rep?.cgImage { self.big = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / (NSScreen.main?.backingScaleFactor ?? 2), height: CGFloat(cg.height) / (NSScreen.main?.backingScaleFactor ?? 2))); self.needsDisplay = true } }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func thumb() { needsDisplay = true }
    override func draw(_ r: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        let w = bounds.width
        let img = big ?? IconCache.shared.image(for: node, size: 128)
        let s = img.size; let k = min(1, min((w - 40) / s.width, 160 / s.height))
        let dr = NSRect(x: w / 2 - s.width * k / 2, y: 20, width: s.width * k, height: s.height * k)
        if big != nil { let sh = NSShadow(); sh.shadowColor = NSColor(0, 0, 0, 0.4); sh.shadowOffset = NSSize(width: 0, height: 2); sh.shadowBlurRadius = 4; NSGraphicsContext.saveGraphicsState(); sh.set(); NSColor.white.setFill(); dr.fill(); NSGraphicsContext.restoreGraphicsState() }
        img.draw(in: dr, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        var y = dr.maxY + 14
        Draw.text(node.name, in: NSRect(x: 12, y: y, width: w - 24, height: 32), font: lucida(12, bold: true), color: .black, align: .center, truncate: .byTruncatingMiddle); y += 16
        Draw.text("\(node.displayKind) – \(node.displaySize)", in: NSRect(x: 12, y: y, width: w - 24, height: 14), font: lucida(11), color: NSColor(gray: 110), align: .center); y += 22
        NSColor(gray: 215).setFill(); NSRect(x: 12, y: y - 4, width: w - 24, height: 1).fill()
        func row(_ k: String, _ v: String) { Draw.text(k, in: NSRect(x: 8, y: y, width: w / 2 - 6, height: 14), font: lucida(10, bold: true), color: NSColor(gray: 120), align: .right); Draw.text(v, in: NSRect(x: w / 2 + 6, y: y, width: w / 2 - 12, height: 14), font: lucida(10), color: .black); y += 16 }
        row(L("Erstellt", "Created"), Files.dateString(node.created)); row(L("Geändert", "Modified"), Files.dateString(node.modified)); row(L("Zuletzt geöffnet", "Last opened"), Files.dateString(node.opened))
        if node.label > 0 { row(L("Etikett", "Label"), Labels.name(node.label)) }
        NSColor(gray: 192).setFill(); NSRect(x: w - 1, y: 0, width: 1, height: bounds.height).fill()
    }
}
