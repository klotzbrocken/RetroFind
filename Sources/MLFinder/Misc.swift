import AppKit

// MARK: AirDrop (X-07) – Übergabe an den System-Dienst; Entdeckung und Übertragung übernimmt macOS.

final class AirDropView: NSView, ItemView {
    weak var host: BrowserHost?
    override var isFlipped: Bool { true }
    private var phase: CGFloat = 0
    private var timer: Timer?
    private var dropping = false
    private let discover = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sendBtn = NSButton(title: "", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        discover.addItems(withTitles: [L("Niemand", "No One"), L("Nur Kontakte", "Contacts Only"), L("Alle", "Everyone")]); discover.selectItem(at: UserDefaults.standard.integer(forKey: "airdropVis")); discover.controlSize = .small; discover.font = lucida(11)
        let h = ActionHandler { [weak self] in UserDefaults.standard.set(self?.discover.indexOfSelectedItem ?? 0, forKey: "airdropVis") }; objc_setAssociatedObject(discover, &handlerKey, h, .OBJC_ASSOCIATION_RETAIN); discover.target = h; discover.action = #selector(ActionHandler.run)
        addSubview(discover)
        sendBtn.title = L("Dateien senden …", "Send Files…"); sendBtn.bezelStyle = .rounded; sendBtn.target = self; sendBtn.action = #selector(choose); sendBtn.font = lucida(11); addSubview(sendBtn)
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 20, repeats: true) { [weak self] _ in self?.phase += 0.012; if (self?.phase ?? 0) > 1 { self?.phase = 0 }; self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { timer?.invalidate() }
    override func layout() { super.layout(); discover.frame = NSRect(x: bounds.maxX - 180, y: bounds.maxY - 28, width: 170, height: 20); sendBtn.frame = NSRect(x: 12, y: bounds.maxY - 30, width: 130, height: 24) }
    func reload() {}; func selectionChanged() {}; func revealSelection() {}; func startRename() {}
    func applyOptions() {}
    override func viewDidMoveToWindow() { if window == nil { timer?.invalidate(); timer = nil } }

    override func draw(_ r: NSRect) {
        gradient([(0, NSColor(236, 241, 247)), (1, NSColor(208, 218, 232))]).draw(in: bounds, angle: 90)
        let c = NSPoint(x: bounds.midX, y: bounds.maxY - 90)
        for k in 0..<4 {
            let f = (CGFloat(k) / 4 + phase).truncatingRemainder(dividingBy: 1)
            let rad = 40 + f * 260
            NSColor(90, 130, 190, 0.28 * (1 - f)).setStroke(); let p = NSBezierPath(ovalIn: NSRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2)); p.lineWidth = 1.5; p.stroke()
        }
        // Eigenes Symbol
        let g = NSBezierPath(ovalIn: NSRect(x: c.x - 30, y: c.y - 30, width: 60, height: 60)); gradient([(0, NSColor(gray: 250)), (1, NSColor(gray: 205))]).draw(in: g, angle: 90); NSColor(gray: 130).setStroke(); g.lineWidth = 1; g.stroke()
        Glyph.airDrop.draw(in: NSRect(x: c.x - 18, y: c.y - 18, width: 36, height: 36))
        Draw.text(NSFullUserName(), in: NSRect(x: c.x - 100, y: c.y + 36, width: 200, height: 16), font: lucida(12), color: .black, align: .center)
        Draw.text(L("Ziehen Sie Dateien hierher, um sie per AirDrop zu senden.", "Drop files here to send them using AirDrop."), in: NSRect(x: 20, y: bounds.midY + 40, width: bounds.width - 40, height: 16), font: lucida(12), color: NSColor(gray: 80), align: .center)
        Draw.text(L("AirDrop findet Mac-Computer und Geräte in der Nähe über das System.", "AirDrop finds nearby Macs and devices through the system."), in: NSRect(x: 20, y: bounds.midY + 60, width: bounds.width - 40, height: 14), font: lucida(11), color: NSColor(gray: 120), align: .center)
        Draw.text(L("Erkennbar für:", "Allow me to be discovered by:"), in: NSRect(x: bounds.maxX - 360, y: bounds.maxY - 25, width: 180, height: 14), font: lucida(11), color: NSColor(gray: 70), align: .right)
        if dropping { C.listSel.setStroke(); let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 6, yRadius: 6); p.lineWidth = 3; p.stroke() }
    }
    func send(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let s = NSSharingService(named: .sendViaAirDrop), s.canPerform(withItems: urls) { s.perform(withItems: urls) }
        else { FileOps.shared.alert(L("AirDrop ist auf diesem Mac nicht verfügbar.", "AirDrop isn\u{2019}t available on this Mac."), L("Bluetooth und WLAN müssen eingeschaltet sein.", "Bluetooth and Wi-Fi must be turned on.")) }
    }
    @objc func choose() { let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = true; if p.runModal() == .OK { send(p.urls) } }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { dropping = true; needsDisplay = true; return .copy }
    override func draggingExited(_ s: NSDraggingInfo?) { dropping = false; needsDisplay = true }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool { dropping = false; send((s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []); return true }
}

// MARK: Hilfe (E-08)

final class HelpWindow {
    static var win: NSWindow?
    static func show(shortcuts: Bool = false) {
        let w = win ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = shortcuts ? L("Tastaturkurzbefehle", "Keyboard Shortcuts") : L("Finder-Hilfe", "Finder Help"); w.isReleasedWhenClosed = false
        let sc = NSScrollView(frame: w.contentView!.bounds); sc.autoresizingMask = [.width, .height]; sc.hasVerticalScroller = true
        let tv = NSTextView(frame: sc.bounds); tv.isEditable = false; tv.font = lucida(12); tv.autoresizingMask = [.width]; tv.textContainerInset = NSSize(width: 14, height: 12)
        let a = NSMutableAttributedString()
        func h(_ s: String) { a.append(NSAttributedString(string: s + "\n", attributes: [.font: lucida(14, bold: true)])) }
        func p(_ s: String) { a.append(NSAttributedString(string: s + "\n\n", attributes: [.font: lucida(12)])) }
        if shortcuts {
            h(L("Tastaturkurzbefehle", "Keyboard Shortcuts"))
            p("⌘N  \(L("Neues Finder-Fenster", "New Finder Window"))\n⇧⌘N  \(L("Neuer Ordner", "New Folder"))\n⌘O  \(L("Öffnen", "Open"))\n⌘W  \(L("Fenster schließen", "Close Window"))\n⌘I  \(L("Informationen", "Get Info"))\n⌘D  \(L("Duplizieren", "Duplicate"))\n⌘L  \(L("Alias erstellen", "Make Alias"))\n⌘Y / \(L("Leertaste", "Space"))  \(L("Übersicht", "Quick Look"))\n⌘⌫  \(L("In den Papierkorb legen", "Move to Trash"))\n⇧⌘⌫  \(L("Papierkorb entleeren", "Empty Trash"))\n⌘F  \(L("Suchen", "Find"))\n⌘J  \(L("Darstellungsoptionen", "View Options"))\n⌘1–4  \(L("Symbole, Liste, Spalten, Cover Flow", "Icons, List, Columns, Cover Flow"))\n⌘[ ⌘]  \(L("Zurück, Vorwärts", "Back, Forward"))\n⌘↑  \(L("Übergeordneter Ordner", "Enclosing Folder"))\n⌘↓  \(L("Öffnen", "Open"))\n⇧⌘G  \(L("Gehe zum Ordner", "Go to Folder"))\n⌘K  \(L("Mit Server verbinden", "Connect to Server"))\n⌘C ⌘V ⌥⌘V  \(L("Kopieren, Einsetzen, Hierher bewegen", "Copy, Paste, Move Item Here"))\n⌥  \(L("Gehe zu: Library; Ziehen: Kopieren; ⌘ beim Ziehen: Bewegen; ⌥⌘: Alias", "Go: Library; drag: copy; ⌘ while dragging: move; ⌥⌘: alias"))\nReturn  \(L("Umbenennen", "Rename"))")
        } else {
            h(L("Willkommen beim RetroFind", "Welcome to RetroFind"))
            p(L("RetroFind bildet den Finder von OS X 10.8 Mountain Lion nach: vier Ansichten (Symbole, Liste, Spalten, Cover Flow), Seitenleiste, Suche mit intelligenten Ordnern, Informationsfenster, Etiketten, Papierkorb, Brennordner, Teilen und mehr.", "RetroFind recreates the OS X 10.8 Mountain Lion Finder: four views (Icons, List, Columns, Cover Flow), sidebar, search with smart folders, Info windows, labels, Trash, burn folders, sharing and more."))
            h(L("Dateien bewegen und kopieren", "Moving and copying files")); p(L("Ziehen Sie Objekte zwischen Fenstern oder in die Seitenleiste. Auf demselben Volume wird bewegt, sonst kopiert. ⌥ kopiert, ⌘ bewegt, ⌥⌘ erstellt Aliasse. Bei Namenskonflikten erscheint ein Dialog (Ersetzen, Beide behalten, Zusammenführen).", "Drag items between windows or into the sidebar. On the same volume items move, otherwise they copy. ⌥ copies, ⌘ moves, ⌥⌘ makes aliases. Name conflicts show a dialog (Replace, Keep Both, Merge)."))
            h(L("Suchen und intelligente Ordner", "Search and Smart Folders")); p(L("Tippen Sie in das Suchfeld. Mit „+“ fügen Sie Kriterien hinzu, mit „Sichern“ legen Sie eine gespeicherte Suche an.", "Type in the search field. Use \u{201C}+\u{201D} to add criteria and \u{201C}Save\u{201D} to create a saved search."))
            h(L("Systemgrenzen", "System limits")); p(L("Auf einem heutigen macOS gelten Abweichungen: Sicheres Entleeren des Papierkorbs, FTP-Schreiben, Facebook-Teilen und historische Verschlüsselungsabläufe sind nicht oder nur über Systemdienste verfügbar. Siehe README.", "On a modern macOS some functions differ: Secure Empty Trash, FTP writing, Facebook sharing and historical encryption flows are unavailable or only via system services. See README."))
        }
        tv.textStorage?.setAttributedString(a); sc.documentView = tv
        w.contentView?.subviews.forEach { $0.removeFromSuperview() }; w.contentView?.addSubview(sc)
        win = w; w.center(); w.makeKeyAndOrderFront(nil)
    }
}
