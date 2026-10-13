import AppKit
import QuickLookThumbnailing

extension Notification.Name { static let thumbReady = Notification.Name("MLThumbReady") }

/// Symbolbeschaffung: eigene Ordnersymbole (Mountain-Lion-Blau), Systemsymbole für Dateien, Vorschaubilder (A-13).
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    private var thumbs: [String: NSImage] = [:]
    private var pending = Set<String>()
    private let q = DispatchQueue(label: "icons")

    func invalidate() { cache.removeAll(); thumbs.removeAll() }

    func folderImage(_ g: Glyph?, size: CGFloat) -> NSImage {
        let key = "folder:\(g?.rawValue ?? "-"):\(Int(size))"
        if let i = cache[key] { return i }
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { r in FolderArt.draw(in: r, badge: g == .folder ? nil : g); return true }
        cache[key] = img; return img
    }

    /// Basis-Symbol (ohne Vorschau). Ordner = eigene Zeichnung.
    func image(for n: FileNode, size: CGFloat) -> NSImage {
        if n.isFolderLike && !n.isVolume {
            let g = Files.glyph(for: n.url)
            if n.url.pathExtension == "savedSearch" { return smartFolder(size) }
            if n.url.pathExtension == Files.burnExt { return cacheOrMake("burn:\(Int(size))") { NSWorkspace.shared.icon(forFile: n.url.path) } }
            return folderImage(g == .home || g == .hardDisk ? .folder : g, size: size)
        }
        let key = (n.isDir ? "d:" : "f:") + (n.url.pathExtension.isEmpty || n.isPackage || n.isVolume ? n.url.path : "ext:" + n.url.pathExtension.lowercased())
        return cacheOrMake(key) { NSWorkspace.shared.icon(forFile: n.url.path) }
    }
    private func cacheOrMake(_ k: String, _ f: () -> NSImage) -> NSImage { if let i = cache[k] { return i }; let i = f(); cache[k] = i; return i }
    func smartFolder(_ size: CGFloat) -> NSImage {
        let key = "smart:\(Int(size))"
        if let i = cache[key] { return i }
        let i = NSImage(size: NSSize(width: size, height: size), flipped: true) { r in FolderArt.draw(in: r, badge: .smartFolder); return true }
        cache[key] = i; return i
    }
    func volumeImage(_ u: URL) -> NSImage { cacheOrMake("vol:" + u.path) { NSWorkspace.shared.icon(forFile: u.path) } }

    static let thumbTypes: Set<String> = ["public.image", "com.adobe.pdf", "public.movie", "public.audiovisual-content", "public.presentation", "public.composite-content"]
    func wantsThumb(_ n: FileNode) -> Bool {
        if n.isDir && !n.isPackage { return false }
        guard let ut = try? n.url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return ut.conforms(to: .image) || ut.conforms(to: .pdf) || ut.conforms(to: .movie)
    }
    func thumb(for n: FileNode, size: CGFloat, scale: CGFloat) -> NSImage? {
        let key = n.url.path + "@\(Int(size))"
        if let t = thumbs[key] { return t }
        if pending.contains(key) { return nil }
        pending.insert(key)
        let req = QLThumbnailGenerator.Request(fileAt: n.url, size: CGSize(width: size, height: size), scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            DispatchQueue.main.async {
                self.pending.remove(key)
                if let cg = rep?.cgImage { self.thumbs[key] = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale)); NotificationCenter.default.post(name: .thumbReady, object: nil) }
                else { self.thumbs[key] = self.image(for: n, size: size) }
            }
        }
        return nil
    }

    /// Fertig komponiertes Symbol (Vorschau im „Foto“-Rahmen, Alias-Pfeil, Sperre).
    func draw(_ n: FileNode, in r: NSRect, preview: Bool, flipped: Bool = true) {
        let ctx = NSGraphicsContext.current!
        var img = image(for: n, size: r.width)
        var isThumb = false
        if preview, wantsThumb(n), let t = thumb(for: n, size: max(r.width, 64), scale: NSScreen.main?.backingScaleFactor ?? 2) { img = t; isThumb = true }
        if n.isVolume && !n.isFolderLike == false { img = volumeImage(n.url) }
        var dr = r
        if isThumb {
            let s = img.size; let k = min(r.width / s.width, r.height / s.height)
            dr = NSRect(x: r.midX - s.width * k / 2, y: r.midY - s.height * k / 2, width: s.width * k, height: s.height * k).integral
            if n.url.pathExtension.lowercased() != "pdf" || true {
                ctx.saveGraphicsState()
                let sh = NSShadow(); sh.shadowColor = NSColor(0, 0, 0, 0.5); sh.shadowOffset = NSSize(width: 0, height: 1.5); sh.shadowBlurRadius = 3; sh.set()
                NSColor.white.setFill(); NSBezierPath(rect: dr.insetBy(dx: -2, dy: -2)).fill()
                ctx.restoreGraphicsState()
                NSColor(gray: 215).setStroke(); NSBezierPath(rect: dr.insetBy(dx: -2.5, dy: -2.5)).stroke()
            }
        }
        img.draw(in: dr, from: .zero, operation: .sourceOver, fraction: n.isHidden ? 0.5 : 1, respectFlipped: flipped, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        if n.isAlias { drawArrow(in: NSRect(x: dr.minX, y: dr.maxY - dr.width * 0.3, width: dr.width * 0.3, height: dr.width * 0.3)) }
        if n.isLocked { drawLock(in: NSRect(x: dr.maxX - dr.width * 0.28, y: dr.maxY - dr.width * 0.28, width: dr.width * 0.28, height: dr.width * 0.28)) }
    }
    private func drawArrow(in r: NSRect) {
        let ctx = NSGraphicsContext.current!; ctx.saveGraphicsState()
        let sh = NSShadow(); sh.shadowColor = NSColor(0, 0, 0, 0.4); sh.shadowOffset = NSSize(width: 0, height: 1); sh.shadowBlurRadius = 1; sh.set()
        NSColor.white.setFill(); NSBezierPath(ovalIn: r).fill()
        ctx.restoreGraphicsState()
        NSColor(60, 60, 60).setFill()
        let p = NSBezierPath(); let c = NSPoint(x: r.midX, y: r.midY); let s = r.width / 4
        p.move(to: NSPoint(x: c.x - s, y: c.y + s)); p.curve(to: NSPoint(x: c.x + s * 0.6, y: c.y - s * 0.4), controlPoint1: NSPoint(x: c.x - s, y: c.y - s * 0.2), controlPoint2: NSPoint(x: c.x, y: c.y - s * 0.4))
        p.line(to: NSPoint(x: c.x + s * 0.6, y: c.y - s * 0.9)); p.line(to: NSPoint(x: c.x + s * 1.4, y: c.y - s * 0.1)); p.line(to: NSPoint(x: c.x + s * 0.6, y: c.y + s * 0.6)); p.line(to: NSPoint(x: c.x + s * 0.6, y: c.y + s * 0.1))
        p.curve(to: NSPoint(x: c.x - s * 0.4, y: c.y + s), controlPoint1: NSPoint(x: c.x, y: c.y + s * 0.1), controlPoint2: NSPoint(x: c.x - s * 0.3, y: c.y + s * 0.5)); p.close(); p.fill()
    }
    private func drawLock(in r: NSRect) {
        NSColor(70, 70, 70).setFill(); NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.midY, width: r.width, height: r.height / 2), xRadius: 1, yRadius: 1).fill()
        NSColor(70, 70, 70).setStroke(); let a = NSBezierPath(); a.lineWidth = 1.4; a.appendArc(withCenter: NSPoint(x: r.midX, y: r.midY), radius: r.width * 0.26, startAngle: 180, endAngle: 360); a.stroke()
    }
}
