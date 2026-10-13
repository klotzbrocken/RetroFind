import AppKit

extension NSColor {
    convenience init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) { self.init(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }
    convenience init(gray g: CGFloat, _ a: CGFloat = 1) { self.init(srgbRed: g / 255, green: g / 255, blue: g / 255, alpha: a) }
}

// MARK: Sprache

enum Lang {
    static var de: Bool = {
        if let o = UserDefaults.standard.string(forKey: "lang") { return o == "de" }
        return Locale.preferredLanguages.first?.hasPrefix("de") ?? false
    }()
}
/// Zweisprachiger Text (E-10): L("Ablage", "File")
func L(_ de: String, _ en: String) -> String { Lang.de ? de : en }

// MARK: Maße (Punkte bei 1×, gemessen an der 1×-Referenz „Nik Rawlinson“, 1024×768, Fenster 770×463)

enum M {
    static let chromeH: CGFloat = 55            // Titelleiste + Toolbar inkl. Trennlinie (Zeile 54)
    static let lightCY: CGFloat = 11.5          // Ampel-Mittelpunkt y
    static let lightD: CGFloat = 12             // Ampel Ø
    static let lightPitch: CGFloat = 20         // Ampel-Abstand (Mitte–Mitte)
    static let lightX0: CGFloat = 14            // Mitte der roten Kugel
    static let tbY: CGFloat = 24, tbH: CGFloat = 21
    static let navX: CGFloat = 8.5, navW: CGFloat = 52
    static let viewX: CGFloat = 141.5, viewW: CGFloat = 111
    static let btnW: CGFloat = 40, btnGap: CGFloat = 8.5
    static let searchH: CGFloat = 21
    static let sidebarW: CGFloat = 136          // 0…135, Trennlinie bei Spalte 136
    static let statusH: CGFloat = 23            // Linie + 22
    static let sideRowH: CGFloat = 24
    static let sideHeaderH: CGFloat = 22
    static let pathH: CGFloat = 23
    static let stripH: CGFloat = 16           // Dual Pane: Kopfstreifen je Hälfte
    static let fbarH: CGFloat = 30           // Dual-Pane-Fußleiste mit F-Tasten
    static let corner: CGFloat = 5
    /// Standardgröße = Referenzfenster (1×).
    static let defaultSize = NSSize(width: 770, height: 463)
    /// Mindestgröße: Seitenleiste 136 + Inhalt ≥ 240 breit; Toolbar läuft darunter in das »-Menü über. Höhe: Titelleiste/Toolbar 55 + mind. 6 Zeilen.
    /// Prüfpunkt (Lastenheft §2.3): Originalwert an einer 10.8-Installation messen – zentral hier änderbar.
    static let minSize = NSSize(width: 380, height: 200)
    static let searchMin: CGFloat = 100
}

func lucida(_ s: CGFloat, bold: Bool = false) -> NSFont {
    NSFont(name: bold ? "LucidaGrande-Bold" : "LucidaGrande", size: s) ?? .systemFont(ofSize: s, weight: bold ? .bold : .regular)
}

// MARK: Farben

enum C {
    static let sidebarLine = NSColor(gray: 184)
    static let chromeLine = NSColor(gray: 106)
    static let chromeLineInactive = NSColor(gray: 150)
    static let sideHeader = NSColor(112, 126, 140)
    static let secHeader = NSColor(117, 129, 148)
    static let selTop = NSColor(113, 185, 234), selBot = NSColor(53, 135, 210)
    static let selLine = NSColor(50, 122, 194), selLineTop = NSColor(92, 164, 223)
    static let listSel = NSColor(62, 128, 205)
    static let stripe = NSColor(243, 246, 250)
    /// Historische Etiketten (Index 1…7): Rot, Orange, Gelb, Grün, Blau, Violett, Grau – wie Finder labelNumber.
    static let labelNames_de = ["Rot", "Orange", "Gelb", "Grün", "Blau", "Violett", "Grau"]
    static let labelNames_en = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"]
    static let labelFill: [NSColor] = [NSColor(250, 138, 124), NSColor(250, 190, 108), NSColor(244, 227, 104), NSColor(190, 218, 92), NSColor(110, 172, 245), NSColor(204, 150, 222), NSColor(180, 180, 180)]
    static let labelPill: [NSColor] = [NSColor(246, 183, 176), NSColor(250, 213, 160), NSColor(244, 232, 142), NSColor(221, 236, 169), NSColor(173, 205, 250), NSColor(222, 192, 236), NSColor(206, 206, 206)]
    static let labelPillBorder: [NSColor] = [NSColor(226, 106, 92), NSColor(230, 150, 70), NSColor(214, 190, 60), NSColor(160, 190, 60), NSColor(80, 140, 225), NSColor(176, 116, 200), NSColor(150, 150, 150)]
}

func gradient(_ stops: [(CGFloat, NSColor)]) -> NSGradient {
    NSGradient(colors: stops.map { $0.1 }, atLocations: stops.map { $0.0 }, colorSpace: .sRGB)!
}

// MARK: Zeichenhelfer

enum Draw {
    /// Verlauf Titelleiste/Toolbar (Spalte der Referenz, Zeile 0 = Lichtkante, 54 = Linie)
    static func chrome(_ r: NSRect, active: Bool) {
        let rows: [(CGFloat, CGFloat)] = active
            ? [(0, 241), (1, 233), (12, 222), (23, 211), (33, 199), (43, 189), (53, 179)]
            : [(0, 247), (1, 240), (12, 233), (23, 226), (33, 219), (43, 213), (53, 207)]
        let h = r.height - 1
        let extra = r.height - M.chromeH            // Tab-Zeile: dehnt nur den oberen Teil (Zeilen 0–24)
        func loc(_ row: CGFloat) -> CGFloat { (row <= 24 ? row * (24 + extra) / 24 : row + extra) / (h - 1) }
        gradient(rows.map { (loc($0.0), NSColor(gray: $0.1)) }).draw(in: NSRect(x: r.minX, y: r.minY, width: r.width, height: h), angle: 90)
        (active ? C.chromeLine : C.chromeLineInactive).setFill()
        NSRect(x: r.minX, y: r.minY + h, width: r.width, height: 1).fill()
    }

    static func sidebarBG(_ r: NSRect) {
        let stops: [(CGFloat, NSColor)] = [(0, NSColor(232, 236, 242)), (118, NSColor(228, 232, 238)), (218, NSColor(222, 227, 233)), (318, NSColor(214, 220, 227)), (378, NSColor(209, 216, 224))]
        for (i, s) in stops.enumerated() {
            let y0 = r.minY + s.0
            let (y1, c1) = i + 1 < stops.count ? (r.minY + stops[i + 1].0, stops[i + 1].1) : (r.maxY, s.1)
            let rect = NSRect(x: r.minX, y: y0, width: r.width, height: max(0, min(y1, r.maxY) - y0))
            if rect.height > 0 { NSGradient(starting: s.1, ending: c1)?.draw(in: rect, angle: 90) }
        }
        if r.maxY > r.minY + 378 { NSColor(209, 216, 224).setFill(); NSRect(x: r.minX, y: r.minY + 378, width: r.width, height: r.maxY - r.minY - 378).fill() }
    }

    /// Blaue Auswahlzeile (Seitenleiste)
    static func selection(_ r: NSRect, active: Bool = true) {
        let top = active ? C.selTop : NSColor(180, 190, 205), bot = active ? C.selBot : NSColor(138, 150, 170)
        NSGradient(colors: [top, NSColor(93, 166, 224), NSColor(66, 141, 206), bot], atLocations: [0, 0.35, 0.7, 1], colorSpace: .sRGB)?.draw(in: r, angle: 90)
        (active ? C.selLineTop : NSColor(150, 160, 175)).setFill(); NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
        (active ? C.selLine : NSColor(120, 130, 150)).setFill(); NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
    }

    static func statusBar(_ r: NSRect, active: Bool) {
        NSColor(gray: active ? 130 : 160).setFill(); NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
        let g = active ? gradient([(0, NSColor(gray: 225)), (0.08, NSColor(gray: 213)), (0.5, NSColor(gray: 200)), (1, NSColor(gray: 177))])
                       : gradient([(0, NSColor(gray: 238)), (1, NSColor(gray: 214))])
        g.draw(in: NSRect(x: r.minX, y: r.minY + 1, width: r.width, height: r.height - 1), angle: 90)
    }

    /// Toolbar-Schaltfläche (Kapsel/Rundung 4)
    static func button(_ r: NSRect, pressed: Bool = false, selected: Bool = false, enabled: Bool = true, active: Bool = true) {
        let p = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        // weißer Schlagschatten unten
        NSColor(white: 1, alpha: 0.7).setStroke()
        let sh = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5).offsetBy(dx: 0, dy: 1), xRadius: 4, yRadius: 4); sh.lineWidth = 1; sh.stroke()
        NSGraphicsContext.saveGraphicsState(); p.addClip()
        if selected || pressed {
            gradient([(0, NSColor(gray: 104)), (0.12, NSColor(gray: 121)), (1, NSColor(gray: 146))]).draw(in: r, angle: 90)
        } else {
            gradient([(0, NSColor(gray: 252)), (0.5, NSColor(gray: 236)), (0.5, NSColor(gray: 226)), (1, NSColor(gray: 214))]).draw(in: r, angle: 90)
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor(gray: active ? 118 : 160).setStroke(); p.lineWidth = 1; p.stroke()
    }

    static func divider(x: CGFloat, in r: NSRect, gray: CGFloat = 150) {
        NSColor(gray: gray).setFill(); NSRect(x: x, y: r.minY + 1, width: 1, height: r.height - 2).fill()
    }

    /// Text mit optionalem Schlagschatten
    static func text(_ s: String, in r: NSRect, font: NSFont, color: NSColor, align: NSTextAlignment = .left, shadow: NSShadow? = nil, truncate: NSLineBreakMode = .byTruncatingTail) {
        let ps = NSMutableParagraphStyle(); ps.alignment = align; ps.lineBreakMode = truncate
        var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: ps]
        if let shadow { a[.shadow] = shadow }
        (s as NSString).draw(in: r, withAttributes: a)
    }
    static func whiteShadow(_ a: CGFloat = 0.8) -> NSShadow { let s = NSShadow(); s.shadowColor = NSColor(white: 1, alpha: a); s.shadowOffset = NSSize(width: 0, height: -1); s.shadowBlurRadius = 0; return s }
    static func darkShadow(_ a: CGFloat = 0.55) -> NSShadow { let s = NSShadow(); s.shadowColor = NSColor(white: 0, alpha: a); s.shadowOffset = NSSize(width: 0, height: 1); s.shadowBlurRadius = 0; return s }
}
