import AppKit

/// Selbstgezeichnete, monochrome Symbole (keine SF Symbols, V-03/V-04). Alle Koordinaten in einem 16×16-Raster, y nach unten.
enum Glyph: String {
    case allFiles, airDrop, desktop, home, applications, documents, movies, music, pictures, utilities, downloads, folder
    case hardDisk, usb, network, computer, eject, trash, disc, timeMachine, smartFolder, library, publicFolder, sites, iDisk, server

    /// Farbe der „farbigen Symbole“ (Einstellung Seitenleiste)
    var color: NSColor {
        switch self {
        case .home: return NSColor(176, 108, 70); case .desktop, .computer, .server, .network, .hardDisk, .usb, .iDisk: return NSColor(86, 112, 150)
        case .downloads: return NSColor(60, 150, 90); case .music: return NSColor(206, 80, 130); case .pictures: return NSColor(70, 140, 190); case .movies: return NSColor(120, 90, 170)
        case .applications, .utilities: return NSColor(200, 110, 50); case .trash: return NSColor(110, 120, 130); case .airDrop: return NSColor(60, 140, 210); case .timeMachine: return NSColor(70, 130, 110)
        case .smartFolder: return NSColor(120, 100, 180); default: return NSColor(78, 118, 176)
        }
    }
    /// Zeichnet das Symbol in `r` (flipped-Koordinaten). `color` = Füllton; selektiert → weiß.
    func draw(in r: NSRect, selected: Bool = false, alpha: CGFloat = 1, tint: NSColor? = nil) {
        let ctx = NSGraphicsContext.current!
        ctx.saveGraphicsState(); defer { ctx.restoreGraphicsState() }
        let t = NSAffineTransform(); t.translateX(by: r.minX, yBy: r.minY); t.scaleX(by: r.width / 16, yBy: r.height / 16); t.concat()
        let dark = tint ?? (selected ? NSColor.white : NSColor(105, 118, 134)), mid = tint?.withAlphaComponent(0.55) ?? (selected ? NSColor(255, 255, 255, 0.85) : NSColor(150, 162, 176)), light = tint?.withAlphaComponent(0.25) ?? (selected ? NSColor(255, 255, 255, 0.55) : NSColor(190, 199, 210))
        let sh = NSShadow(); sh.shadowColor = selected ? NSColor(0, 40, 90, 0.5) : NSColor(255, 255, 255, 0.9); sh.shadowOffset = NSSize(width: 0, height: selected ? 1 : -1); sh.shadowBlurRadius = 0
        sh.set()
        func fill(_ p: NSBezierPath, _ c: NSColor) { c.withAlphaComponent(c.alphaComponent * alpha).setFill(); p.fill() }
        func stroke(_ p: NSBezierPath, _ c: NSColor, _ w: CGFloat = 1) { c.withAlphaComponent(c.alphaComponent * alpha).setStroke(); p.lineWidth = w; p.stroke() }
        func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rad: CGFloat = 1) -> NSBezierPath { NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: rad, yRadius: rad) }
        func line(_ pts: [(CGFloat, CGFloat)], close: Bool = false) -> NSBezierPath { let p = NSBezierPath(); p.move(to: NSPoint(x: pts[0].0, y: pts[0].1)); for q in pts.dropFirst() { p.line(to: NSPoint(x: q.0, y: q.1)) }; if close { p.close() }; return p }
        switch self {
        case .allFiles:
            fill(rr(2.5, 1.5, 11, 7, 1), light); stroke(rr(2.5, 1.5, 11, 7, 1), dark)
            for y in [3.5, 5.5, 7.5] as [CGFloat] { stroke(line([(4.5, y), (11.5, y)]), dark, 0.8) }
            fill(rr(1, 9, 14, 5.5, 1.5), dark)
            fill(rr(3, 11, 10, 1.5, 0.5), light)
        case .airDrop:
            let p = NSBezierPath(); p.move(to: NSPoint(x: 1.5, y: 7)); p.curve(to: NSPoint(x: 14.5, y: 7), controlPoint1: NSPoint(x: 2, y: -0.5), controlPoint2: NSPoint(x: 14, y: -0.5)); p.close()
            fill(p, mid); stroke(p, dark, 0.9)
            stroke(line([(5.5, 2.5), (8, 7), (10.5, 2.5)]), dark, 0.6)
            stroke(line([(1.5, 7), (8, 12)]), dark, 0.7); stroke(line([(14.5, 7), (8, 12)]), dark, 0.7)
            fill(rr(5.8, 11.5, 4.4, 3.4, 0.8), dark)
        case .desktop:
            fill(rr(1.5, 2, 13, 11, 1.2), light); stroke(rr(1.5, 2, 13, 11, 1.2), dark)
            fill(rr(1.5, 10, 13, 3, 0.8), dark)
            for x in [4.5, 6.5, 8.5, 10.5] as [CGFloat] { fill(rr(x, 11, 1.4, 1, 0.3), light) }
        case .home:
            fill(line([(1, 8), (8, 1.5), (15, 8), (13, 8), (13, 14.5), (3, 14.5), (3, 8)], close: true), mid)
            stroke(line([(1, 8), (8, 1.5), (15, 8)]), dark, 1.1)
            stroke(line([(3, 8), (3, 14.5), (13, 14.5), (13, 8)]), dark, 0.9)
            fill(rr(6.8, 9.5, 2.4, 5, 0.3), dark); fill(rr(11, 2.5, 1.6, 3.5, 0), dark)
        case .applications:
            stroke(line([(2.5, 14.5), (8, 1.5), (13.5, 14.5)]), dark, 1.5)
            stroke(line([(4.8, 10.5), (11.2, 10.5)]), dark, 1.2)
            stroke(line([(1.5, 14.5), (6, 11)]), mid, 1.2); fill(rr(11, 8, 2, 7, 0.4), mid)
        case .documents:
            fill(rr(4, 1.5, 9.5, 12, 1), light); stroke(rr(4, 1.5, 9.5, 12, 1), dark)
            fill(rr(2, 3.5, 9, 11.5, 1), mid); stroke(rr(2, 3.5, 9, 11.5, 1), dark)
            for y in [7, 9, 11] as [CGFloat] { stroke(line([(3.8, y), (9.2, y)]), dark, 0.8) }
        case .movies:
            fill(rr(2.5, 1.5, 11, 13, 0.8), light); stroke(rr(2.5, 1.5, 11, 13, 0.8), dark, 1.2)
            for y in [3.0, 6.0, 9.0, 12.0] as [CGFloat] { fill(rr(3.3, y, 1.6, 1.3, 0.2), dark); fill(rr(11.1, y, 1.6, 1.3, 0.2), dark) }
            stroke(line([(5.5, 4), (10.5, 4)]), dark, 0.8); stroke(line([(5.5, 12), (10.5, 12)]), dark, 0.8)
        case .music:
            fill(NSBezierPath(ovalIn: NSRect(x: 3, y: 10.5, width: 4.6, height: 3.6)), dark); fill(NSBezierPath(ovalIn: NSRect(x: 9.6, y: 8.8, width: 4.6, height: 3.6)), dark)
            fill(rr(6.6, 2.5, 1.4, 9.5, 0), dark); fill(rr(13.2, 1, 1.2, 9.5, 0), dark)
            fill(line([(6.6, 2.5), (14.4, 1), (14.4, 3.8), (6.6, 5.4)], close: true), dark)
        case .pictures:
            fill(rr(1, 4, 14, 10, 1.8), mid); stroke(rr(1, 4, 14, 10, 1.8), dark)
            fill(rr(4, 2.5, 4, 2.5, 0.5), dark)
            fill(NSBezierPath(ovalIn: NSRect(x: 4.7, y: 5.7, width: 6.6, height: 6.6)), light); stroke(NSBezierPath(ovalIn: NSRect(x: 4.7, y: 5.7, width: 6.6, height: 6.6)), dark, 1.1)
            fill(NSBezierPath(ovalIn: NSRect(x: 6.5, y: 7.5, width: 3, height: 3)), dark)
        case .utilities:
            stroke(line([(2, 14), (9, 7)]), dark, 2); stroke(line([(3, 3), (13.5, 13.5)]), mid, 1.6)
            fill(NSBezierPath(ovalIn: NSRect(x: 8, y: 1.5, width: 5, height: 5)), dark); stroke(line([(3.5, 2.5), (6.5, 5.5)]), dark, 2.2)
            stroke(line([(13.5, 14), (7, 7.5)]), dark, 1.6)
        case .downloads:
            let o = NSBezierPath(ovalIn: NSRect(x: 1.2, y: 1.2, width: 13.6, height: 13.6)); fill(o, dark)
            let c = selected ? NSColor(60, 140, 215) : NSColor(232, 236, 242)
            c.setFill(); line([(6.2, 3), (9.8, 3), (9.8, 7), (12, 7), (8, 12.2), (4, 7), (6.2, 7)], close: true).fill()
        case .folder, .library, .publicFolder, .sites:
            fill(line([(1.5, 3.5), (6.5, 3.5), (7.5, 5), (14.5, 5), (14.5, 13.5), (1.5, 13.5)], close: true), mid)
            stroke(line([(1.5, 13.5), (1.5, 3.5), (6.5, 3.5), (7.5, 5), (14.5, 5), (14.5, 13.5), (1.5, 13.5)]), dark, 0.9)
            stroke(line([(1.5, 6.5), (14.5, 6.5)]), dark, 0.8)
        case .hardDisk, .usb:
            fill(rr(1, 6.5, 14, 6, 1.5), mid); stroke(rr(1, 6.5, 14, 6, 1.5), dark)
            fill(line([(2.5, 6.5), (4, 3.5), (12, 3.5), (13.5, 6.5)], close: true), light); stroke(line([(2.5, 6.5), (4, 3.5), (12, 3.5), (13.5, 6.5)]), dark, 0.8)
            fill(NSBezierPath(ovalIn: NSRect(x: 11.2, y: 9, width: 2, height: 2)), dark)
        case .server:
            fill(rr(1.5, 3, 13, 4.5, 1), mid); stroke(rr(1.5, 3, 13, 4.5, 1), dark); fill(rr(1.5, 8.5, 13, 4.5, 1), mid); stroke(rr(1.5, 8.5, 13, 4.5, 1), dark)
            fill(NSBezierPath(ovalIn: NSRect(x: 11.5, y: 4.5, width: 1.6, height: 1.6)), dark); fill(NSBezierPath(ovalIn: NSRect(x: 11.5, y: 10, width: 1.6, height: 1.6)), dark)
        case .network:
            fill(rr(1.5, 1.5, 13, 9, 1), light); stroke(rr(1.5, 1.5, 13, 9, 1), dark)
            let c = NSBezierPath(ovalIn: NSRect(x: 4, y: 2.5, width: 8, height: 7)); stroke(c, dark, 0.8)
            stroke(line([(8, 2.5), (8, 9.5)]), dark, 0.6); stroke(line([(4, 6), (12, 6)]), dark, 0.6)
            fill(line([(6, 10.5), (10, 10.5), (11, 14), (5, 14)], close: true), dark)
        case .computer:
            fill(rr(1.5, 1.5, 13, 9.5, 1.2), light); stroke(rr(1.5, 1.5, 13, 9.5, 1.2), dark)
            fill(rr(3, 3, 10, 6.2, 0.5), mid); fill(line([(6.5, 11), (9.5, 11), (10.5, 14.5), (5.5, 14.5)], close: true), dark)
        case .iDisk:
            fill(rr(1.5, 1.5, 13, 13, 2), mid); stroke(rr(1.5, 1.5, 13, 13, 2), dark)
            fill(NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 8, height: 8)), light); fill(NSBezierPath(ovalIn: NSRect(x: 7, y: 7, width: 2, height: 2)), dark)
        case .disc:
            let o = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 14, height: 14)); fill(o, mid); stroke(o, dark)
            let i = NSBezierPath(ovalIn: NSRect(x: 5.5, y: 5.5, width: 5, height: 5)); fill(i, light); stroke(i, dark, 0.8)
            fill(NSBezierPath(ovalIn: NSRect(x: 7.2, y: 7.2, width: 1.6, height: 1.6)), dark)
        case .timeMachine:
            fill(rr(1.5, 1.5, 13, 13, 2), light); stroke(rr(1.5, 1.5, 13, 13, 2), dark)
            let o = NSBezierPath(ovalIn: NSRect(x: 3.8, y: 3.8, width: 8.4, height: 8.4)); stroke(o, dark, 1.2)
            stroke(line([(8, 5.5), (8, 8), (10, 9)]), dark, 1)
        case .smartFolder:
            let g = NSBezierPath()
            for i in 0..<8 { let a = CGFloat(i) * .pi / 4; g.move(to: NSPoint(x: 8 + cos(a) * 3.5, y: 8 + sin(a) * 3.5)); g.line(to: NSPoint(x: 8 + cos(a) * 6.6, y: 8 + sin(a) * 6.6)) }
            stroke(g, dark, 2.2); stroke(NSBezierPath(ovalIn: NSRect(x: 3.8, y: 3.8, width: 8.4, height: 8.4)), dark, 1.8)
            fill(NSBezierPath(ovalIn: NSRect(x: 6.3, y: 6.3, width: 3.4, height: 3.4)), dark.withAlphaComponent(0.01))
        case .eject:
            fill(line([(8, 2.5), (13.5, 9), (2.5, 9)], close: true), dark); fill(rr(2.5, 10.5, 11, 2.6, 0.3), dark)
        case .trash:
            fill(rr(3.5, 4.5, 9, 10, 1.5), mid); stroke(rr(3.5, 4.5, 9, 10, 1.5), dark)
            fill(rr(2.2, 2.8, 11.6, 1.8, 0.8), dark); fill(rr(6, 1.4, 4, 1.6, 0.6), dark)
            for x in [6.2, 8, 9.8] as [CGFloat] { stroke(line([(x, 6.5), (x, 12.8)]), dark, 0.8) }
        }
    }
}

// MARK: Farbige Ordnersymbole (Symbol- und Spaltenansicht, Cover Flow, Info)

enum FolderArt {
    /// Mountain-Lion-Ordner nach Referenz (Verhältnis ≈ 1,34 : 1, Reiter links, helle Vorderseite) mit eingeprägtem Piktogramm.
    static func draw(in r: NSRect, badge: Glyph? = nil, alpha: CGFloat = 1) {
        let ctx = NSGraphicsContext.current!
        ctx.saveGraphicsState(); defer { ctx.restoreGraphicsState() }
        let s = min(r.width, r.height)
        let t = NSAffineTransform(); t.translateX(by: r.midX - s / 2, yBy: r.midY - s / 2); t.scaleX(by: s / 128, yBy: s / 128); t.concat()
        func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: rad, yRadius: rad) }
        // Schatten unter dem Ordner
        let sh = NSShadow(); sh.shadowColor = NSColor(0, 30, 70, 0.5 * alpha); sh.shadowOffset = NSSize(width: 0, height: 2.2); sh.shadowBlurRadius = 2.4
        ctx.saveGraphicsState(); sh.set(); NSColor(150, 186, 218).setFill(); rr(2, 39, 124, 77, 3.6).fill(); ctx.restoreGraphicsState()
        // Rückseite mit Reiter
        let back = NSBezierPath()
        back.move(to: NSPoint(x: 8.4, y: 38)); back.line(to: NSPoint(x: 8.4, y: 36)); back.curve(to: NSPoint(x: 13.7, y: 31.5), controlPoint1: NSPoint(x: 8.4, y: 33.5), controlPoint2: NSPoint(x: 11, y: 31.5))
        back.line(to: NSPoint(x: 12.4, y: 31.5)); back.line(to: NSPoint(x: 15.6, y: 26)); back.curve(to: NSPoint(x: 19.6, y: 24), controlPoint1: NSPoint(x: 16.6, y: 24.4), controlPoint2: NSPoint(x: 18, y: 24))
        back.line(to: NSPoint(x: 49.5, y: 24)); back.curve(to: NSPoint(x: 54.6, y: 28.5), controlPoint1: NSPoint(x: 52, y: 24), controlPoint2: NSPoint(x: 54.6, y: 25.5))
        back.line(to: NSPoint(x: 54.6, y: 33.9)); back.line(to: NSPoint(x: 116, y: 33.9)); back.curve(to: NSPoint(x: 120, y: 38), controlPoint1: NSPoint(x: 118.4, y: 33.9), controlPoint2: NSPoint(x: 120, y: 35.4))
        back.line(to: NSPoint(x: 120, y: 60)); back.line(to: NSPoint(x: 8.4, y: 60)); back.close()
        gradient([(0, NSColor(163, 195, 223)), (1, NSColor(143, 180, 214))]).draw(in: back, angle: 90)
        // Vorderseite
        let front = rr(2, 39.2, 124, 76.8, 3.6)
        gradient([(0, NSColor(184, 213, 236)), (0.45, NSColor(166, 200, 228)), (1, NSColor(142, 178, 213))]).draw(in: front, angle: 90)
        NSColor(255, 255, 255, 0.5).setFill(); NSRect(x: 4, y: 40, width: 120, height: 1.2).fill()      // Lichtkante oben
        NSColor(108, 148, 190, 0.55).setStroke(); front.lineWidth = 0.7; front.stroke()
        if let badge {   // eingeprägtes Piktogramm, mittig auf der Vorderseite
            let g = NSRect(x: 64 - 23, y: 77.6 - 23, width: 46, height: 46)
            ctx.saveGraphicsState()
            badge.draw(in: g.offsetBy(dx: 0, dy: 0.9), selected: false, alpha: 0.55 * alpha, tint: NSColor(255, 255, 255))
            badge.draw(in: g, selected: false, alpha: 0.7 * alpha, tint: NSColor(112, 150, 188))
            ctx.restoreGraphicsState()
        }
    }
}

// MARK: Toolbar-Glyphen

enum TB {
    static func tri(_ c: NSPoint, right: Bool, color: NSColor) {
        let p = NSBezierPath()
        if right { p.move(to: NSPoint(x: c.x - 4, y: c.y - 5)); p.line(to: NSPoint(x: c.x + 4, y: c.y)); p.line(to: NSPoint(x: c.x - 4, y: c.y + 5)) }
        else { p.move(to: NSPoint(x: c.x + 4, y: c.y - 5)); p.line(to: NSPoint(x: c.x - 4, y: c.y)); p.line(to: NSPoint(x: c.x + 4, y: c.y + 5)) }
        p.close(); color.setFill(); p.fill()
    }
    static func caret(_ c: NSPoint, color: NSColor) {
        let p = NSBezierPath(); p.move(to: NSPoint(x: c.x - 3.5, y: c.y - 2)); p.line(to: NSPoint(x: c.x + 3.5, y: c.y - 2)); p.line(to: NSPoint(x: c.x, y: c.y + 2.5)); p.close(); color.setFill(); p.fill()
    }
    /// 0 Symbole, 1 Liste, 2 Spalten, 3 Cover Flow
    static func viewMode(_ i: Int, in r: NSRect, color: NSColor) {
        color.setFill(); color.setStroke()
        let cx = r.midX, cy = r.midY
        switch i {
        case 0: for dx in [-5.5, 0.9] as [CGFloat] { for dy in [-5.5, 0.9] as [CGFloat] { let q = NSBezierPath(rect: NSRect(x: cx + dx, y: cy + dy, width: 4.6, height: 4.6)); q.lineWidth = 1.2; q.stroke() } }
        case 1: for dy in [-5.5, -2.5, 0.5, 3.5] as [CGFloat] { NSRect(x: cx - 6, y: cy + dy, width: 12, height: 1.2).fill() }
        case 2:
            let b = NSBezierPath(rect: NSRect(x: cx - 6.5, y: cy - 4.5, width: 13, height: 9)); b.lineWidth = 1; b.stroke()
            for dx in [-2.1, 2.2] as [CGFloat] { NSRect(x: cx + dx, y: cy - 4.5, width: 1, height: 9).fill() }
        default:
            for dx in [-8, -5.5, 4.5, 7] as [CGFloat] { NSRect(x: cx + dx, y: cy - 4.5, width: 1.1, height: 9).fill() }
            let b = NSBezierPath(rect: NSRect(x: cx - 3.5, y: cy - 5.5, width: 7, height: 11)); b.lineWidth = 1.3; b.stroke()
            NSRect(x: cx - 1.8, y: cy - 3.8, width: 3.6, height: 7.6).fill()
        }
    }
    static func gear(_ c: NSPoint, color: NSColor) {
        color.setFill(); color.setStroke()
        let g = NSBezierPath()
        for i in 0..<8 { let a = CGFloat(i) * .pi / 4; g.move(to: NSPoint(x: c.x + cos(a) * 3.8, y: c.y + sin(a) * 3.8)); g.line(to: NSPoint(x: c.x + cos(a) * 6.8, y: c.y + sin(a) * 6.8)) }
        g.lineWidth = 2.6; g.stroke()
        let o = NSBezierPath(ovalIn: NSRect(x: c.x - 4.6, y: c.y - 4.6, width: 9.2, height: 9.2)); o.lineWidth = 2; o.stroke()
        NSColor(gray: 232).setFill(); NSBezierPath(ovalIn: NSRect(x: c.x - 1.8, y: c.y - 1.8, width: 3.6, height: 3.6)).fill()
    }
    static func arrange(_ c: NSPoint, color: NSColor) {
        color.setFill()
        for row in 0..<3 { for col in 0..<3 { NSRect(x: c.x - 6 + CGFloat(col) * 4.4, y: c.y - 5 + CGFloat(row) * 3.6, width: 3.4, height: 2).fill() } }
    }
    static func share(_ c: NSPoint, color: NSColor) {
        color.setStroke(); color.setFill()
        let b = NSBezierPath(); b.lineWidth = 1.6; b.lineJoinStyle = .round
        b.move(to: NSPoint(x: c.x - 3, y: c.y - 5)); b.line(to: NSPoint(x: c.x - 7, y: c.y - 5)); b.line(to: NSPoint(x: c.x - 7, y: c.y + 6)); b.line(to: NSPoint(x: c.x + 5, y: c.y + 6)); b.line(to: NSPoint(x: c.x + 5, y: c.y + 3)); b.stroke()
        let a = NSBezierPath(); a.move(to: NSPoint(x: c.x - 3, y: c.y + 3)); a.curve(to: NSPoint(x: c.x + 1, y: c.y - 3), controlPoint1: NSPoint(x: c.x - 3, y: c.y - 2), controlPoint2: NSPoint(x: c.x - 1, y: c.y - 3)); a.lineWidth = 1.8; a.stroke()
        let h = NSBezierPath(); h.move(to: NSPoint(x: c.x + 1, y: c.y - 7)); h.line(to: NSPoint(x: c.x + 7.5, y: c.y - 3)); h.line(to: NSPoint(x: c.x + 1, y: c.y + 1)); h.close(); h.fill()
    }
    static func magnifier(_ c: NSPoint, color: NSColor) {
        color.setStroke()
        let o = NSBezierPath(ovalIn: NSRect(x: c.x - 4.5, y: c.y - 4.5, width: 7.5, height: 7.5)); o.lineWidth = 1.7; o.stroke()
        let h = NSBezierPath(); h.move(to: NSPoint(x: c.x + 1.2, y: c.y + 1.2)); h.line(to: NSPoint(x: c.x + 5, y: c.y + 5)); h.lineWidth = 2.2; h.lineCapStyle = .round; h.stroke()
    }
    static func eye(_ c: NSPoint, color: NSColor) {
        color.setStroke(); color.setFill()
        let p = NSBezierPath(); p.move(to: NSPoint(x: c.x - 7, y: c.y)); p.curve(to: NSPoint(x: c.x + 7, y: c.y), controlPoint1: NSPoint(x: c.x - 3, y: c.y - 6), controlPoint2: NSPoint(x: c.x + 3, y: c.y - 6)); p.curve(to: NSPoint(x: c.x - 7, y: c.y), controlPoint1: NSPoint(x: c.x + 3, y: c.y + 6), controlPoint2: NSPoint(x: c.x - 3, y: c.y + 6)); p.lineWidth = 1.3; p.stroke()
        NSBezierPath(ovalIn: NSRect(x: c.x - 2.8, y: c.y - 2.8, width: 5.6, height: 5.6)).fill()
    }
}

// MARK: Ampel

enum Lights {
    enum Kind: Int { case close, mini, zoom }
    /// Mountain-Lion-Ampel: Ø12, glänzende Kugel. hover → Symbol, pressed → dunkler, active=false → graue Kugel.
    static func draw(_ k: Kind, center c: NSPoint, active: Bool, hover: Bool, pressed: Bool) {
        let d = M.lightD, r = NSRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)
        let (hi, lo, rim, sym): (NSColor, NSColor, NSColor, NSColor)
        if active {
            switch k {
            case .close: (hi, lo, rim, sym) = (NSColor(255, 142, 132), NSColor(232, 66, 58), NSColor(152, 64, 58), NSColor(110, 12, 6))
            case .mini: (hi, lo, rim, sym) = (NSColor(255, 228, 140), NSColor(240, 172, 44), NSColor(176, 134, 68), NSColor(120, 70, 0))
            case .zoom: (hi, lo, rim, sym) = (NSColor(192, 236, 152), NSColor(92, 182, 62), NSColor(108, 150, 84), NSColor(20, 80, 0))
            }
        } else { (hi, lo, rim, sym) = (NSColor(gray: 224), NSColor(gray: 190), NSColor(gray: 150), NSColor(gray: 120)) }
        let ctx = NSGraphicsContext.current!
        // Schlagschatten/Lichtkante unten
        NSColor(255, 255, 255, 0.65).setFill(); NSBezierPath(ovalIn: r.offsetBy(dx: 0, dy: 0.8)).fill()
        let base = NSBezierPath(ovalIn: r)
        ctx.saveGraphicsState(); base.addClip()
        gradient([(0, pressed ? lo : hi), (0.55, lo), (1, hi.blended(withFraction: 0.35, of: lo) ?? lo)]).draw(in: r, angle: 90)
        // untere Reflexion
        NSGradient(starting: NSColor(255, 255, 255, 0.0), ending: NSColor(255, 255, 255, 0.45))?.draw(in: NSRect(x: r.minX + 2, y: r.minY + d * 0.55, width: d - 4, height: d * 0.45), angle: 90)
        ctx.restoreGraphicsState()
        // Rand
        rim.setStroke(); base.lineWidth = 0.9; NSBezierPath(ovalIn: r.insetBy(dx: 0.45, dy: 0.45)).stroke()
        // Glanzlicht oben
        let g = NSBezierPath(ovalIn: NSRect(x: r.minX + 2.2, y: r.minY + 0.8, width: d - 4.4, height: d * 0.42))
        NSGradient(starting: NSColor(255, 255, 255, 0.9), ending: NSColor(255, 255, 255, 0.15))?.draw(in: g, angle: -90)
        if hover && active {
            sym.setStroke(); sym.setFill()
            let p = NSBezierPath(); p.lineWidth = 1.5; p.lineCapStyle = .round
            switch k {
            case .close: p.move(to: NSPoint(x: c.x - 2.4, y: c.y - 2.4)); p.line(to: NSPoint(x: c.x + 2.4, y: c.y + 2.4)); p.move(to: NSPoint(x: c.x + 2.4, y: c.y - 2.4)); p.line(to: NSPoint(x: c.x - 2.4, y: c.y + 2.4))
            case .mini: p.move(to: NSPoint(x: c.x - 2.8, y: c.y)); p.line(to: NSPoint(x: c.x + 2.8, y: c.y))
            case .zoom: p.move(to: NSPoint(x: c.x - 2.8, y: c.y)); p.line(to: NSPoint(x: c.x + 2.8, y: c.y)); p.move(to: NSPoint(x: c.x, y: c.y - 2.8)); p.line(to: NSPoint(x: c.x, y: c.y + 2.8))
            }
            p.stroke()
        }
    }
}
