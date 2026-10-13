import AppKit
import QuartzCore

/// Cover Flow (A-06): perspektivische Vorschauen mit Spiegelung, synchrone Liste, verstellbares Bereichsverhältnis.
final class CoverFlowView: NSView, ItemView {
    weak var host: BrowserHost? { didSet { list.host = host; canvas.owner = self } }
    override var isFlipped: Bool { true }
    let canvas = FlowCanvas()
    let list = ListView(frame: .zero)
    private var splitDrag = false
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(list); addSubview(canvas)
        setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError() }

    var ratio: CGFloat { host?.options.coverSplit ?? 0.5 }
    override func layout() {
        super.layout()
        let top = max(120, min(bounds.height - 60, bounds.height * ratio))
        canvas.frame = NSRect(x: 0, y: 0, width: bounds.width, height: top)
        list.frame = NSRect(x: 0, y: top + 6, width: bounds.width, height: max(0, bounds.height - top - 6))
        canvas.relayout()
    }
    func reload() {
        var o = host?.options; if o?.columns.count ?? 0 > 4 { o?.columns = ["name", "modified", "size", "kind"] }
        list.reload(); canvas.rebuild(); layout()
    }
    func applyOptions() { list.applyOptions(); needsLayout = true }
    func selectionChanged() { list.selectionChanged(); canvas.sync(animated: true) }
    func revealSelection() { list.revealSelection(); canvas.sync(animated: false) }
    func startRename() { list.startRename() }
    override func selectAll(_ sender: Any?) { list.selectAllRows() }

    // Teiler zwischen Flow und Liste
    override func resetCursorRects() { addCursorRect(NSRect(x: 0, y: canvas.frame.maxY, width: bounds.width, height: 6), cursor: .resizeUpDown) }
    override func draw(_ r: NSRect) {
        gradient([(0, NSColor(gray: 205)), (1, NSColor(gray: 150))]).draw(in: NSRect(x: 0, y: canvas.frame.maxY, width: bounds.width, height: 6), angle: 90)
        NSColor(gray: 90).setFill(); NSRect(x: 0, y: canvas.frame.maxY, width: bounds.width, height: 1).fill()
    }
    override func mouseDown(with e: NSEvent) { let p = convert(e.locationInWindow, from: nil); splitDrag = abs(p.y - canvas.frame.maxY - 3) < 5 }
    override func mouseDragged(with e: NSEvent) {
        guard splitDrag, var o = host?.options else { return }
        o.coverSplit = max(0.2, min(0.8, convert(e.locationInWindow, from: nil).y / bounds.height)); host?.options = o; needsLayout = true
    }
    override func mouseUp(with e: NSEvent) { splitDrag = false; window?.invalidateCursorRects(for: self) }
}

final class FlowCanvas: NSView {
    weak var owner: CoverFlowView?
    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var items: [FileNode] = []
    private(set) var index = 0
    private var layers: [Int: CATransformLayer] = [:]
    private let stage = CALayer()
    private let bgLayer = CAGradientLayer()
    private let overlay = FlowOverlay()
    private var dragSlider = false
    private var coverSize: CGFloat { max(50, min(bounds.height - 105, 260)) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer!.masksToBounds = true
        bgLayer.colors = [NSColor(gray: 56).cgColor, NSColor.black.cgColor]; bgLayer.startPoint = CGPoint(x: 0.5, y: 0); bgLayer.endPoint = CGPoint(x: 0.5, y: 1)   // unten heller, oben schwarz
        layer!.addSublayer(bgLayer)
        var t = CATransform3DIdentity; t.m34 = -1 / 900; stage.sublayerTransform = t
        layer!.addSublayer(stage)
        overlay.canvas = self; addSubview(overlay)
        NotificationCenter.default.addObserver(self, selector: #selector(thumb), name: .thumbReady, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func thumb() { for (i, l) in layers { if let n = items[safe: i] { setImage(l, n) } } }
    override func layout() { super.layout(); overlay.frame = bounds }

    func rebuild() {
        items = owner?.host?.nodes ?? []
        layers.values.forEach { $0.removeFromSuperlayer() }; layers = [:]
        sync(animated: false)
    }
    func relayout() {
        CATransaction.begin(); CATransaction.setDisableActions(true); bgLayer.frame = bounds; stage.frame = bounds; CATransaction.commit()
        sync(animated: false)
    }

    func sync(animated: Bool) {
        guard let host = owner?.host else { return }
        items = host.nodes
        if let u = host.selection.last, let i = items.firstIndex(where: { $0.url == u }) { index = i } else { index = max(0, min(index, items.count - 1)) }
        CATransaction.begin(); CATransaction.setDisableActions(!animated); CATransaction.setAnimationDuration(0.3)
        let lo = max(0, index - 8), hi = min(items.count - 1, index + 8)
        for (i, l) in layers where i < lo || i > hi { l.removeFromSuperlayer(); layers[i] = nil }
        if lo <= hi { for i in lo...hi { position(layers[i] ?? makeLayer(i), i) } }
        CATransaction.commit()
        if ProcessInfo.processInfo.environment["MLF_DEBUG"] != nil { print("FLOW index=\(index) n=\(items.count) layers=\(layers.keys.sorted()) pos=\(layers.keys.sorted().map { Int(layers[$0]!.position.x) })") }
        overlay.needsDisplay = true
    }
    private func makeLayer(_ i: Int) -> CATransformLayer {
        let c = CATransformLayer()
        let refl = CALayer(); refl.name = "refl"; refl.opacity = 1
        let m = CAGradientLayer(); m.colors = [NSColor(white: 1, alpha: 0.38).cgColor, NSColor(white: 1, alpha: 0).cgColor]; m.startPoint = CGPoint(x: 0.5, y: 0); m.endPoint = CGPoint(x: 0.5, y: 0.7); refl.mask = m
        let img = CALayer(); img.name = "img"
        for l in [refl, img] { l.contentsGravity = .resizeAspect; l.minificationFilter = .trilinear; l.isDoubleSided = true }
        c.addSublayer(refl); c.addSublayer(img)
        stage.addSublayer(c); layers[i] = c
        if let n = items[safe: i] { setImage(c, n) }
        return c
    }
    private func setImage(_ c: CALayer, _ n: FileNode) {
        let img = IconCache.shared.thumb(for: n, size: 256, scale: 2) ?? IconCache.shared.image(for: n, size: 256)
        var rect = CGRect(origin: .zero, size: img.size)
        let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        for l in c.sublayers ?? [] { l.contents = cg }
    }
    private func position(_ c: CATransformLayer, _ i: Int) {
        let s = coverSize, d = i - index
        let cx = bounds.midX, base = bounds.height * 0.40 - 4         // Unterkante der Cover
        let off: CGFloat = d == 0 ? 0 : CGFloat(d.signum()) * (s * 0.62 + CGFloat(abs(d) - 1) * s * 0.17)
        c.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        c.position = CGPoint(x: cx + off, y: base + s / 2)
        var t = CATransform3DIdentity
        if d == 0 { t = CATransform3DMakeTranslation(0, 0, s * 0.45) }
        else { t = CATransform3DMakeTranslation(0, 0, -s * 0.1); t = CATransform3DRotate(t, d < 0 ? .pi * 0.38 : -.pi * 0.38, 0, 1, 0) }
        c.transform = t
        c.zPosition = d == 0 ? 100 : CGFloat(-abs(d))
        for l in c.sublayers ?? [] {
            if l.name == "img" { l.frame = CGRect(x: 0, y: 0, width: s, height: s); l.opacity = d == 0 ? 1 : 0.78 }
            else { l.frame = CGRect(x: 0, y: -s - 1, width: s, height: s); l.transform = CATransform3DMakeScale(1, -1, 1); l.mask?.frame = l.bounds }
        }
    }

    // MARK: Interaktion
    func select(_ i: Int) {
        guard let host = owner?.host, let n = items[safe: i] else { return }
        host.setSelection([n.url], source: self); sync(animated: true); owner?.list.selectionChanged(); owner?.list.revealSelection()
    }
    var sliderRect: NSRect { NSRect(x: bounds.midX - min(260, bounds.width / 2 - 20), y: 8, width: min(520, bounds.width - 40), height: 10) }
    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(e.locationInWindow, from: nil)
        if sliderRect.insetBy(dx: -4, dy: -6).contains(p) { dragSlider = true; slide(p.x); return }
        let s = coverSize
        for d in [0, -1, 1, -2, 2, -3, 3, -4, 4, -5, 5] { if let l = layers[index + d] {
            let w = d == 0 ? s : s * 0.3; let r = CGRect(x: l.position.x - w / 2 + (d == 0 ? 0 : CGFloat(-d.signum()) * 0), y: l.position.y - s / 2, width: w, height: s)
            if r.contains(p) { if d == 0, e.clickCount == 2, let n = items[safe: index] { owner?.host?.open(n, modifiers: e.modifierFlags) } else { select(index + d) }; return } } }
    }
    override func mouseDragged(with e: NSEvent) { if dragSlider { slide(convert(e.locationInWindow, from: nil).x) } }
    override func mouseUp(with e: NSEvent) { dragSlider = false }
    private func slide(_ x: CGFloat) { let t = sliderRect; guard items.count > 0 else { return }; let f = max(0, min(1, (x - t.minX) / t.width)); select(Int(round(f * CGFloat(items.count - 1)))) }
    override func scrollWheel(with e: NSEvent) { let d = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? e.scrollingDeltaX : -e.scrollingDeltaY; if abs(d) > 2 { select(index + (d > 0 ? 1 : -1)) } }
    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 123, 126: select(index - 1)
        case 124, 125: select(index + 1)
        case 49: owner?.host?.quickLook()
        case 36: if e.modifierFlags.contains(.command) { owner?.host?.openSelection() } else { owner?.startRename() }
        default: super.keyDown(with: e)
        }
    }
    override func rightMouseDown(with e: NSEvent) { if let h = owner?.host { NSMenu.popUpContextMenu(h.contextMenu(for: items[safe: index]), with: e, for: self) } }
}

/// Beschriftung und Schieberegler über den Covern
final class FlowOverlay: NSView {
    weak var canvas: FlowCanvas?
    override var isFlipped: Bool { false }
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
    override func draw(_ dirty: NSRect) {
        guard let c = canvas, let n = c.items[safe: c.index] else { return }
        Draw.text(n.name, in: NSRect(x: 20, y: 34, width: bounds.width - 40, height: 16), font: lucida(12, bold: true), color: .white, align: .center, truncate: .byTruncatingMiddle)
        Draw.text("\(n.displayKind) – \(n.displaySize)   \(Files.dateString(n.modified))", in: NSRect(x: 20, y: 20, width: bounds.width - 40, height: 14), font: lucida(10), color: NSColor(gray: 170), align: .center)
        let t = c.sliderRect
        NSColor(gray: 30).setFill(); NSBezierPath(roundedRect: t, xRadius: 5, yRadius: 5).fill(); NSColor(gray: 85).setStroke(); NSBezierPath(roundedRect: t.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5).stroke()
        let cnt = c.items.count
        let f = cnt > 1 ? CGFloat(c.index) / CGFloat(cnt - 1) : 0
        let kw: CGFloat = max(24, t.width / CGFloat(max(1, min(cnt, 12))))
        let k = NSRect(x: t.minX + f * (t.width - kw), y: t.minY, width: kw, height: t.height)
        gradient([(0, NSColor(gray: 120)), (1, NSColor(gray: 200))]).draw(in: NSBezierPath(roundedRect: k, xRadius: 5, yRadius: 5), angle: 90)
    }
}
