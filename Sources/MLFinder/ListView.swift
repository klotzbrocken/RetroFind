import AppKit

struct ListCol {
    let id: String; let title: String; let def: CGFloat; let min: CGFloat; let right: Bool
    static let all: [ListCol] = [
        ListCol(id: "name", title: L("Name", "Name"), def: 240, min: 100, right: false),
        ListCol(id: "modified", title: L("Änderungsdatum", "Date Modified"), def: 150, min: 70, right: false),
        ListCol(id: "created", title: L("Erstellungsdatum", "Date Created"), def: 150, min: 70, right: false),
        ListCol(id: "opened", title: L("Datum des letzten Öffnens", "Date Last Opened"), def: 160, min: 70, right: false),
        ListCol(id: "added", title: L("Hinzufügedatum", "Date Added"), def: 150, min: 70, right: false),
        ListCol(id: "size", title: L("Größe", "Size"), def: 80, min: 50, right: true),
        ListCol(id: "kind", title: L("Art", "Kind"), def: 130, min: 50, right: false),
        ListCol(id: "version", title: L("Version", "Version"), def: 80, min: 40, right: false),
        ListCol(id: "comments", title: L("Kommentare", "Comments"), def: 140, min: 50, right: false),
        ListCol(id: "label", title: L("Etikett", "Label"), def: 90, min: 50, right: false),
    ]
    static func by(_ id: String) -> ListCol { all.first { $0.id == id } ?? all[0] }
}

/// Listenansicht (A-03/A-04): aufklappbare Ordner, sortier-, verschieb- und skalierbare Spalten.
final class ListView: NSView, ItemView, NSTextFieldDelegate, NSDraggingSource {
    weak var host: BrowserHost?
    override var isFlipped: Bool { true }
    let header = ListHeader()
    let scroll = NSScrollView()
    let rowsView = RowsView()
    var rowHeight: CGFloat { opts.listIconSize > 16 ? 34 : 19 }
    var idealWidth: CGFloat { cols.reduce(0) { $0 + width(of: $1) } }
    var opts: ViewOptions { host?.options ?? ViewOptions() }
    var cols: [ListCol] { opts.columns.map { ListCol.by($0) } }
    func width(of c: ListCol) -> CGFloat { opts.widths[c.id] ?? c.def }
    var rows: [(node: FileNode, depth: Int)] = []
    var expanded = Set<URL>()
    var sizeCache: [URL: Int64] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        header.list = self; rowsView.list = self
        scroll.documentView = rowsView; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true; scroll.scrollerStyle = .legacy
        scroll.drawsBackground = true; scroll.backgroundColor = .white; scroll.borderType = .noBorder
        addSubview(scroll); addSubview(header)
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        setAccessibilityRole(.table)
        NotificationCenter.default.addObserver(self, selector: #selector(sizesChanged), name: .sizeReady, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    // Kompatibilität mit Browser.buildItemView (alter Tabellenentwurf)
    var table: NSView { rowsView }
    func installHeader(in s: NSScrollView) {}
    func attach(_ s: NSScrollView) {}
    @objc func sizesChanged() { rowsView.needsDisplay = true }
    @objc func scrolled() { header.offsetX = scroll.contentView.bounds.origin.x; header.needsDisplay = true }

    override func layout() {
        super.layout()
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 19)
        scroll.frame = NSRect(x: 0, y: 19, width: bounds.width, height: max(0, bounds.height - 19))
        resizeDoc()
    }
    func resizeDoc() {
        let w = max(idealWidth + 8, scroll.contentSize.width)
        rowsView.frame = NSRect(x: 0, y: 0, width: w, height: max(CGFloat(rows.count) * rowHeight, scroll.contentSize.height))
        header.contentWidth = idealWidth; header.needsDisplay = true; rowsView.needsDisplay = true
    }

    // MARK: Daten
    func reload() { endRename(commit: false); rebuildRows(); resizeDoc(); header.needsDisplay = true; rowsView.needsDisplay = true; computeSizes() }
    func applyOptions() { reload() }
    func rebuildRows() {
        rows = []
        guard let host else { return }
        func add(_ ns: [FileNode], _ d: Int) {
            for n in ns { rows.append((n, d)); if n.isFolderLike, expanded.contains(n.url) { add(host.children(of: n), d + 1) } }
        }
        add(host.nodes, 0)
    }
    func computeSizes() {
        guard opts.calcSizes else { return }
        let todo = rows.map { $0.node }.filter { $0.isDir && !$0.isPackage && $0.size < 0 && !$0.calculating }
        guard !todo.isEmpty else { return }
        SizeService.shared.calculate(todo)
    }
    func toggle(_ n: FileNode, recursive: Bool = false) {
        guard n.isFolderLike, let host else { return }
        if expanded.contains(n.url) {
            expanded.remove(n.url)
            // verdeckte Auswahl entfernen
            host.setSelection(host.selection.filter { !($0.path.hasPrefix(n.url.path + "/")) }, source: self)
        } else { expanded.insert(n.url); n.children = nil; if recursive { for c in host.children(of: n) where c.isFolderLike { expanded.insert(c.url) } } }
        rebuildRows(); resizeDoc(); rowsView.needsDisplay = true
    }
    func selectionChanged() { rowsView.needsDisplay = true }
    func revealSelection() {
        guard let host, let u = host.selection.first, let i = rows.firstIndex(where: { $0.node.url == u }) else { return }
        rowsView.scrollToVisible(NSRect(x: 0, y: CGFloat(i) * rowHeight, width: 10, height: rowHeight))
    }
    func startRename() {
        guard let host, host.selection.count == 1, let i = rows.firstIndex(where: { $0.node.url == host.selection[0] }) else { return }
        endRename(commit: true)
        let n = rows[i].node, nameCol = cols[0]; _ = nameCol
        let x = CGFloat(rows[i].depth) * 16 + 18 + (opts.listIconSize > 16 ? 36 : 20) - 2
        let f = NSTextField(frame: NSRect(x: x, y: CGFloat(i) * rowHeight, width: width(of: ListCol.by("name")) - x, height: rowHeight))
        f.stringValue = n.name; f.font = lucida(opts.listTextSize); f.isBordered = true; f.focusRingType = .exterior; f.delegate = self
        rowsView.addSubview(f); window?.makeFirstResponder(f); renaming = (f, n)
        if !n.isDir, !n.url.pathExtension.isEmpty { f.currentEditor()?.selectedRange = NSRange(location: 0, length: (n.name as NSString).deletingPathExtension.count) } else { f.currentEditor()?.selectAll(nil) }
    }
    var renaming: (field: NSTextField, node: FileNode)?
    func control(_ c: NSControl, textView: NSTextView, doCommandBy s: Selector) -> Bool {
        if s == #selector(NSResponder.insertNewline(_:)) { endRename(commit: true); return true }
        if s == #selector(NSResponder.cancelOperation(_:)) { endRename(commit: false); return true }
        return false
    }
    func controlTextDidEndEditing(_ n: Notification) { if renaming != nil { endRename(commit: (n.userInfo?["NSTextMovement"] as? Int) != NSCancelTextMovement) } }
    func endRename(commit: Bool) {
        guard let r = renaming else { return }; renaming = nil
        let s = r.field.stringValue; r.field.removeFromSuperview(); window?.makeFirstResponder(rowsView)
        if commit, s != r.node.name { host?.rename(r.node, to: s) }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? [.copy, .move, .link, .generic] : [.copy, .link, .generic] }
    func selectAllRows() { host?.setSelection(rows.map { $0.node.url }, source: nil); rowsView.needsDisplay = true }

    // MARK: Zellentext
    func text(_ n: FileNode, _ c: ListCol) -> String {
        switch c.id {
        case "name": return (!Prefs.showExtensions && !n.isDir && !n.url.pathExtension.isEmpty) ? (n.name as NSString).deletingPathExtension : n.name
        case "modified": return Files.dateString(n.modified, long: !opts.useRelativeDates)
        case "created": return Files.dateString(n.created, long: !opts.useRelativeDates)
        case "opened": return Files.dateString(n.opened, long: !opts.useRelativeDates)
        case "added": return Files.dateString(n.added, long: !opts.useRelativeDates)
        case "size": return n.displaySize
        case "kind": return n.displayKind
        case "version": return (Bundle(url: n.url)?.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "--"
        case "comments": let c = n.comment; return c.isEmpty ? "--" : c
        case "label": return n.label == 0 ? "--" : Labels.name(n.label)
        default: return ""
        }
    }

    func setSort(_ id: String) {
        guard let host else { return }
        var o = host.options
        if o.sortKey == id { o.ascending.toggle() } else { o.sortKey = id == "label" ? "label" : id; o.ascending = true }
        host.options = o; host.viewStateChanged()
    }
    func sortKey(for id: String) -> String { id }
    func columnMenu() -> NSMenu {
        let m = NSMenu()
        for c in ListCol.all where c.id != "name" {
            let i = NSMenuItem(title: c.title, action: #selector(toggleCol(_:)), keyEquivalent: ""); i.target = self; i.representedObject = c.id; i.state = opts.columns.contains(c.id) ? .on : .off; m.addItem(i)
        }
        return m
    }
    @objc func toggleCol(_ s: NSMenuItem) {
        guard let id = s.representedObject as? String, let host else { return }
        var o = host.options
        if let k = o.columns.firstIndex(of: id) { o.columns.remove(at: k) } else { o.columns.append(id) }
        host.options = o; resizeDoc(); header.needsDisplay = true; rowsView.needsDisplay = true
    }
    /// Doppelklick auf die Trennlinie: Spalte auf den breitesten Inhalt (inkl. Titel) einpassen
    func autoWidth(_ id: String) {
        let c = ListCol.by(id), f = lucida(opts.listTextSize)
        func tw(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: f]).width }
        var w = tw(c.title) + 24
        for r in rows { w = max(w, tw(text(r.node, c)) + 14 + (id == "name" ? CGFloat(r.depth) * 16 + 12 + CGFloat(opts.listIconSize) + 4 : 0)) }
        setWidth(id, w)
    }
    func setWidth(_ id: String, _ w: CGFloat) {
        guard let host else { return }; var o = host.options; o.widths[id] = max(ListCol.by(id).min, w); host.options = o; resizeDoc()
    }
    func moveColumn(_ id: String, to idx: Int) {
        guard let host else { return }; var o = host.options
        guard let from = o.columns.firstIndex(of: id), id != "name" else { return }
        o.columns.remove(at: from); o.columns.insert(id, at: max(1, min(idx, o.columns.count))); host.options = o; header.needsDisplay = true; rowsView.needsDisplay = true
    }
    override func menu(for event: NSEvent) -> NSMenu? { nil }
}

// MARK: Spaltenkopf

final class ListHeader: NSView {
    weak var list: ListView?
    var offsetX: CGFloat = 0
    var contentWidth: CGFloat = 0
    override var isFlipped: Bool { true }
    private var resizing: (id: String, startX: CGFloat, startW: CGFloat)?
    private var dragging: (id: String, startX: CGFloat, moved: Bool)?
    private var pressedID: String?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func rects() -> [(ListCol, NSRect)] {
        guard let l = list else { return [] }
        var x = -offsetX; var out: [(ListCol, NSRect)] = []
        for c in l.cols { let w = l.width(of: c); out.append((c, NSRect(x: x, y: 0, width: w, height: 19))); x += w }
        return out
    }
    override func draw(_ dirty: NSRect) {
        guard let l = list else { return }
        let active = l.host?.isActive ?? true
        gradient([(0, NSColor(gray: 252)), (0.5, NSColor(gray: 238)), (1, NSColor(gray: 218))]).draw(in: bounds, angle: 90)
        NSColor(gray: active ? 160 : 190).setFill(); NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        let sortKey = l.opts.sortKey
        for (c, r) in rects() {
            if c.id == sortKey { NSColor(0, 0, 0, 0.08).setFill(); NSRect(x: r.minX, y: 0, width: r.width, height: 16).fill() }
            if pressedID == c.id { NSColor(0, 0, 0, 0.12).setFill(); NSRect(x: r.minX, y: 0, width: r.width, height: 16).fill() }
            NSColor(gray: 190).setFill(); NSRect(x: r.maxX - 1, y: 1, width: 1, height: 14).fill()
            NSColor(white: 1, alpha: 0.7).setFill(); NSRect(x: r.maxX, y: 1, width: 1, height: 14).fill()
            let tw = r.width - 22
            Draw.text(c.title, in: NSRect(x: r.minX + 7, y: 3, width: max(0, tw), height: 15), font: lucida(12, bold: c.id == sortKey), color: NSColor(gray: 50), align: .left)
            if c.id == sortKey {   // Sortierpfeil
                let ax = r.maxX - 12, p = NSBezierPath()
                if l.opts.ascending { p.move(to: NSPoint(x: ax - 3.5, y: 9.5)); p.line(to: NSPoint(x: ax + 3.5, y: 9.5)); p.line(to: NSPoint(x: ax, y: 4.5)) }
                else { p.move(to: NSPoint(x: ax - 3.5, y: 5)); p.line(to: NSPoint(x: ax + 3.5, y: 5)); p.line(to: NSPoint(x: ax, y: 10)) }
                p.close(); NSColor(gray: 90).setFill(); p.fill()
            }
        }
    }
    private func dividerHit(_ p: NSPoint) -> String? { rects().first { abs($0.1.maxX - p.x) <= 3 }?.0.id }
    override func resetCursorRects() { for (_, r) in rects() { addCursorRect(NSRect(x: r.maxX - 3, y: 0, width: 6, height: 19), cursor: .resizeLeftRight) } }
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if let id = dividerHit(p), let l = list {
            if e.clickCount == 2 { l.autoWidth(id); needsDisplay = true; discardCursorRects(); return }
            resizing = (id, p.x, l.width(of: ListCol.by(id))); return }
        if let (c, _) = rects().first(where: { $0.1.contains(p) }) { pressedID = c.id; dragging = (c.id, p.x, false); needsDisplay = true }
    }
    override func mouseDragged(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if let r = resizing { list?.setWidth(r.id, r.startW + p.x - r.startX); needsDisplay = true; discardCursorRects(); return }
        if var d = dragging, abs(p.x - d.startX) > 4, d.id != "name" {
            d.moved = true; dragging = d
            if let (c, _) = rects().first(where: { $0.1.contains(p) }), c.id != d.id, c.id != "name", let l = list, let idx = l.opts.columns.firstIndex(of: c.id) { l.moveColumn(d.id, to: idx) }
        }
    }
    override func mouseUp(with e: NSEvent) {
        defer { resizing = nil; dragging = nil; pressedID = nil; needsDisplay = true; window?.invalidateCursorRects(for: self) }
        if let d = dragging, !d.moved, resizing == nil { list?.setSort(d.id) }
    }
    override func menu(for event: NSEvent) -> NSMenu? { list?.columnMenu() }
}

// MARK: Zeilenbereich

final class RowsView: NSView {
    weak var list: ListView?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var downRow: Int?; private var downPoint = NSPoint.zero
    private var anchor: URL?
    private var dropRow: Int?; private var dropBG = false
    private var springTimer: Timer?
    private var typed = ""; private var typedAt = Date.distantPast
    private var dragStarted = false

    init() { super.init(frame: .zero); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }

    private var rh: CGFloat { list?.rowHeight ?? 17 }
    private func rowAt(_ y: CGFloat) -> Int? { guard let l = list, y >= 0 else { return nil }; let i = Int(y / rh); return i < l.rows.count ? i : nil }

    override func draw(_ dirty: NSRect) {
        guard let l = list, let host = l.host else { return }
        let active = host.isActive
        let o = l.opts; let h = rh
        let first = max(0, Int(dirty.minY / h)), last = min(l.rows.count - 1, Int(dirty.maxY / h))
        // Streifen im gesamten sichtbaren Bereich
        let totalRows = Int(ceil(bounds.height / h))
        for i in 0..<totalRows where CGFloat(i + 1) * h >= dirty.minY && CGFloat(i) * h <= dirty.maxY { (i % 2 == 0 ? NSColor.white : C.stripe).setFill(); NSRect(x: dirty.minX, y: CGFloat(i) * h, width: dirty.width, height: h).fill() }
        // Spaltentrenner (senkrecht, fein)
        var x: CGFloat = 0
        for c in l.cols { x += l.width(of: c); NSColor(gray: 0, 0.045).setFill(); NSRect(x: x - 1, y: dirty.minY, width: 1, height: dirty.height).fill() }
        guard first <= last else { return }
        let font = lucida(o.listTextSize)
        for i in first...last {
            let (n, depth) = l.rows[i]
            let y = CGFloat(i) * h
            let sel = host.isSelected(n.url)
            let rowRect = NSRect(x: 0, y: y, width: bounds.width, height: h)
            if n.label > 0 && !sel {   // Etikett färbt die ganze Zeile (Listenansicht)
                let c = C.labelPill[n.label - 1]; c.setFill(); rowRect.fill()
            }
            if sel { Draw.listSelection(rowRect, active: active) }
            if dropRow == i { C.listSel.setStroke(); let p = NSBezierPath(roundedRect: rowRect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3); p.lineWidth = 2; p.stroke() }
            var cx: CGFloat = 0
            for c in l.cols {
                let w = l.width(of: c)
                var tx = cx + 6
                if c.id == "name" {
                    tx = cx + CGFloat(depth) * 16 + 4
                    if n.isFolderLike {   // Aufklapp-Dreieck
                        let open = l.expanded.contains(n.url)
                        let cy = y + h / 2
                        let p = NSBezierPath()
                        if open { p.move(to: NSPoint(x: tx, y: cy - 2.5)); p.line(to: NSPoint(x: tx + 8, y: cy - 2.5)); p.line(to: NSPoint(x: tx + 4, y: cy + 3.5)) }
                        else { p.move(to: NSPoint(x: tx + 1, y: cy - 4)); p.line(to: NSPoint(x: tx + 7, y: cy)); p.line(to: NSPoint(x: tx + 1, y: cy + 4)) }
                        p.close(); (sel ? NSColor.white : NSColor(gray: 90)).setFill(); p.fill()
                    }
                    tx += 12
                    let isz = o.listIconSize
                    IconCache.shared.draw(n, in: NSRect(x: tx, y: y + (h - isz) / 2, width: isz, height: isz), preview: false)
                    tx += isz + 4
                    if l.renaming?.node == n { cx += w; continue }
                }
                let s = l.text(n, c)
                let col: NSColor = sel ? .white : (c.id == "name" ? .black : NSColor(gray: c.id == "kind" || c.id == "size" ? 70 : 60))
                Draw.text(s, in: NSRect(x: tx, y: y + (h - 14) / 2 + (h > 20 ? 0 : 0), width: max(0, cx + w - tx - 6), height: 15), font: font, color: n.isHidden ? col.withAlphaComponent(0.5) : col, align: c.right ? .right : .left, shadow: sel ? Draw.darkShadow(0.4) : nil, truncate: c.id == "name" ? .byTruncatingMiddle : .byTruncatingTail)
                cx += w
            }
        }
        if dropBG { C.listSel.setStroke(); let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5); p.lineWidth = 3; p.stroke() }
    }

    // MARK: Maus
    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        guard let l = list, let host = l.host else { return }
        l.endRename(commit: true)
        let p = convert(e.locationInWindow, from: nil); downPoint = p; dragStarted = false
        guard let i = rowAt(p.y) else { downRow = nil; host.setSelection([], source: self); needsDisplay = true; return }
        downRow = i
        let n = l.rows[i].node, depth = l.rows[i].depth
        let tx = CGFloat(depth) * 16 + 4
        if n.isFolderLike, p.x >= tx - 2 && p.x <= tx + 11 { l.toggle(n, recursive: e.modifierFlags.contains(.option)); return }
        if e.clickCount == 2 { host.open(n, modifiers: e.modifierFlags); return }
        if e.modifierFlags.contains(.command) { var s = host.selection; if let k = s.firstIndex(of: n.url) { s.remove(at: k) } else { s.append(n.url) }; host.setSelection(s, source: self); anchor = n.url }
        else if e.modifierFlags.contains(.shift), let a = anchor, let ai = l.rows.firstIndex(where: { $0.node.url == a }) { host.setSelection((min(ai, i)...max(ai, i)).map { l.rows[$0].node.url }, source: self) }
        else if !host.isSelected(n.url) { host.setSelection([n.url], source: self); anchor = n.url }
        needsDisplay = true
    }
    override func mouseDragged(with e: NSEvent) {
        guard let l = list, let host = l.host, let i = downRow, !dragStarted else { return }
        let p = convert(e.locationInWindow, from: nil)
        guard hypot(p.x - downPoint.x, p.y - downPoint.y) > 4 else { return }
        dragStarted = true
        let n = l.rows[i].node
        if !host.isSelected(n.url) { host.setSelection([n.url], source: self) }
        var items: [NSDraggingItem] = []
        for (k, u) in host.selection.enumerated() {
            guard let nn = host.node(for: u) else { continue }
            let it = NSDraggingItem(pasteboardWriter: u as NSURL)
            let img = NSImage(size: NSSize(width: 160, height: 17), flipped: true) { r in IconCache.shared.draw(nn, in: NSRect(x: 0, y: 0, width: 16, height: 16), preview: false); Draw.text(nn.name, in: NSRect(x: 20, y: 1, width: 138, height: 15), font: lucida(11), color: .black); return true }
            it.setDraggingFrame(NSRect(x: p.x - 10, y: p.y - 8 + CGFloat(k) * 2, width: 160, height: 17), contents: img); items.append(it)
        }
        beginDraggingSession(with: items, event: e, source: l)
    }
    override func mouseUp(with e: NSEvent) {
        guard let l = list, let host = l.host, let i = downRow, !dragStarted else { return }
        let p = convert(e.locationInWindow, from: nil)
        if hypot(p.x - downPoint.x, p.y - downPoint.y) < 4, !e.modifierFlags.contains(.command), !e.modifierFlags.contains(.shift), e.clickCount == 1, host.selection.count > 1 { host.setSelection([l.rows[i].node.url], source: self); anchor = l.rows[i].node.url; needsDisplay = true }
    }
    override func rightMouseDown(with e: NSEvent) {
        guard let l = list, let host = l.host else { return }
        window?.makeFirstResponder(self)
        let p = convert(e.locationInWindow, from: nil)
        let n = rowAt(p.y).map { l.rows[$0].node }
        if let n { if !host.isSelected(n.url) { host.setSelection([n.url], source: self) } } else { host.setSelection([], source: self) }
        needsDisplay = true
        NSMenu.popUpContextMenu(host.contextMenu(for: n), with: e, for: self)
    }

    // MARK: Tastatur
    override func keyDown(with e: NSEvent) {
        guard let l = list, let host = l.host else { return }
        let cur = host.selection.last.flatMap { u in l.rows.firstIndex { $0.node.url == u } }
        func select(_ i: Int, extend: Bool) {
            let c = max(0, min(l.rows.count - 1, i))
            if extend, let a = anchor, let ai = l.rows.firstIndex(where: { $0.node.url == a }) { host.setSelection((min(ai, c)...max(ai, c)).map { l.rows[$0].node.url }, source: self) }
            else { host.setSelection([l.rows[c].node.url], source: self); anchor = l.rows[c].node.url }
            l.revealSelection(); needsDisplay = true
        }
        switch e.keyCode {
        case 125: if l.rows.isEmpty { return }; select((cur ?? -1) + 1, extend: e.modifierFlags.contains(.shift)); return
        case 126: if l.rows.isEmpty { return }; select((cur ?? l.rows.count) - 1, extend: e.modifierFlags.contains(.shift)); return
        case 124: if let c = cur, l.rows[c].node.isFolderLike, !l.expanded.contains(l.rows[c].node.url) { l.toggle(l.rows[c].node, recursive: e.modifierFlags.contains(.option)) }; return
        case 123:
            if let c = cur {
                let n = l.rows[c].node
                if n.isFolderLike && l.expanded.contains(n.url) { l.toggle(n) }
                else if l.rows[c].depth > 0, let p = (0..<c).reversed().first(where: { l.rows[$0].depth < l.rows[c].depth }) { select(p, extend: false) }
            }; return
        case 36, 76: if e.modifierFlags.contains(.command) { host.openSelection() } else { l.startRename() }; return
        case 49: host.quickLook(); return
        case 51, 117: if e.modifierFlags.contains(.command) { host.trashSelection() }; return
        default: break
        }
        if e.modifierFlags.intersection([.command, .control]).isEmpty, let ch = e.charactersIgnoringModifiers, let c = ch.unicodeScalars.first, c.value >= 32, c.value < 0xF700 {
            if Date().timeIntervalSince(typedAt) > 1 { typed = "" }; typed += ch.lowercased(); typedAt = Date()
            if let i = l.rows.firstIndex(where: { $0.node.name.lowercased().hasPrefix(typed) }) { select(i, extend: false) }; return
        }
        super.keyDown(with: e)
    }
    override func selectAll(_ sender: Any?) { list?.selectAllRows() }

    // MARK: Drop
    private func drop(_ s: NSDraggingInfo) -> (urls: [URL], dir: URL?, row: Int?) {
        let urls = (s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let p = convert(s.draggingLocation, from: nil)
        if let i = rowAt(p.y), let l = list { let n = l.rows[i].node; if (n.isFolderLike || n.isVolume), !urls.contains(n.url) { return (urls, n.url, i) } }
        return (urls, list?.host?.currentDir, nil)
    }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { draggingUpdated(s) }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation {
        guard let host = list?.host else { return [] }
        let d = drop(s); let old = dropRow; dropRow = d.row; dropBG = d.row == nil && (s.draggingSource as? ListView) !== list
        if old != d.row { springTimer?.invalidate(); if let r = d.row, Prefs.springLoading, let n = list?.rows[r].node { springTimer = Timer.scheduledTimer(withTimeInterval: Prefs.springDelay, repeats: false) { [weak self] _ in if let l = self?.list { l.toggle(n) } } } }
        needsDisplay = true
        return host.dragOperation(d.urls, into: d.dir, flags: NSEvent.modifierFlags)
    }
    override func draggingExited(_ s: NSDraggingInfo?) { dropRow = nil; dropBG = false; springTimer?.invalidate(); needsDisplay = true }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        defer { dropRow = nil; dropBG = false; springTimer?.invalidate(); needsDisplay = true }
        let d = drop(s); return list?.host?.performDrop(d.urls, into: d.dir, flags: NSEvent.modifierFlags) ?? false
    }
}

extension Draw {
    /// Auswahl in der Listenansicht (blauer Verlauf bzw. grau bei inaktivem Fenster)
    static func listSelection(_ r: NSRect, active: Bool) {
        let top = active ? NSColor(87, 160, 226) : NSColor(176, 186, 202), bot = active ? NSColor(46, 117, 205) : NSColor(140, 152, 172)
        NSGradient(starting: top, ending: bot)?.draw(in: r, angle: 90)
        (active ? NSColor(39, 102, 190) : NSColor(125, 136, 156)).setFill(); NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
    }
}
