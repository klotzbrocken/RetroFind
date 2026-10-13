import AppKit

extension Prefs {
    static var xQueue: Bool { get { bool("xQueue", true) } set { d.set(newValue, forKey: "xQueue") } }
    static var queuePolicy: ConflictPolicy { get { ConflictPolicy(rawValue: d.string(forKey: "queuePolicy") ?? "") ?? .ask } set { d.set(newValue.rawValue, forKey: "queuePolicy") } }
    static var queueVerify: Bool { get { bool("queueVerify", false) } set { d.set(newValue, forKey: "queueVerify") } }
}

/// Ein Eintrag der Warteschlange (Kopieren oder Verschieben)
final class TransferJob: NSObject {
    enum State { case waiting, running, done, failed(String), cancelled }
    let sources: [URL]; let dir: URL; let move: Bool
    var state = State.waiting
    let control = TransferControl()
    var policy: ConflictPolicy, verify: Bool
    var speed: Double = 0, lastBytes: Int64 = 0, lastT = Date(), started: Date?
    var created: [URL] = []
    var onDone: (([URL]) -> Void)?
    var title: String { (move ? L("Verschieben", "Move") : L("Kopieren", "Copy")) + ": " + FileOps.nameList(sources) + " → " + Files.displayName(dir) }
    init(_ s: [URL], _ d: URL, _ m: Bool, _ p: ConflictPolicy, _ v: Bool) { sources = s; dir = d; move = m; policy = p; verify = v }
    var fraction: Double { control.total > 0 ? min(1, Double(control.done) / Double(control.total)) : 0 }
    var eta: TimeInterval? { speed > 1 ? Double(max(0, control.total - control.done)) / speed : nil }
    var isActive: Bool { switch state { case .waiting, .running: return true; default: return false } }
}

/// Sequentielle Warteschlange für Kopier-/Verschiebevorgänge mit Pause, Abbruch, Geschwindigkeit und Restzeit.
final class TransferQueue: NSObject {
    static let shared = TransferQueue()
    private(set) var jobs: [TransferJob] = []
    var paused = false { didSet { jobs.forEach { $0.control.paused = paused }; if !paused { kick() }; changed() } }
    var isBusy: Bool { jobs.contains { $0.isActive } }

    @discardableResult func enqueue(_ sources: [URL], to dir: URL, move: Bool, done: (([URL]) -> Void)? = nil) -> TransferJob {
        let j = TransferJob(sources, dir, move, Prefs.queuePolicy, Prefs.queueVerify)
        j.onDone = done; j.control.paused = paused
        jobs.append(j); changed(); kick()
        // Fenster erscheint, wenn der Vorgang nicht sofort fertig ist
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { if self.isBusy { QueueWindow.shared.show() } }
        return j
    }
    private func kick() {
        guard !paused, !jobs.contains(where: { if case .running = $0.state { return true }; return false }),
              let j = jobs.first(where: { if case .waiting = $0.state { return true }; return false }) else { return }
        j.state = .running; j.started = Date(); j.lastT = Date(); j.lastBytes = 0; changed()
        FileOps.shared.transfer(j.sources, to: j.dir, move: j.move, policy: j.policy, verify: j.verify, control: j.control) { [weak self] created in
            guard let self else { return }
            j.created = created
            if j.control.cancelled { j.state = .cancelled }
            else if let e = j.control.error { j.state = .failed(e) }
            else { j.state = .done }
            j.onDone?(created); self.changed(); self.kick()
        }
    }
    func cancel(_ j: TransferJob) {
        switch j.state { case .waiting: j.state = .cancelled; changed(); case .running: j.control.cancelled = true; j.control.paused = false; default: break }
    }
    func clearFinished() { jobs.removeAll { !$0.isActive }; changed() }
    /// Geschwindigkeit glätten (wird vom Fenster-Timer aufgerufen)
    func tick() {
        let now = Date()
        for j in jobs { if case .running = j.state {
            let dt = now.timeIntervalSince(j.lastT); guard dt >= 0.4 else { continue }
            let inst = Double(j.control.done - j.lastBytes) / dt
            j.speed = j.speed == 0 ? max(0, inst) : 0.65 * j.speed + 0.35 * max(0, inst)
            j.lastBytes = j.control.done; j.lastT = now
        } }
    }
    func changed() { NotificationCenter.default.post(name: .queueChanged, object: nil) }
}
extension Notification.Name { static let queueChanged = Notification.Name("MLQueueChanged") }

// MARK: Fenster

final class QueueWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = QueueWindow()
    let win = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 340), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
    let table = NSTableView(); let pauseBtn = NSButton(); var timer: Timer?
    override init() {
        super.init()
        win.title = L("Warteschlange", "Transfer Queue"); win.isReleasedWhenClosed = false; win.hidesOnDeactivate = false; win.isFloatingPanel = true
        let v = win.contentView!
        let sc = NSScrollView(frame: NSRect(x: 0, y: 44, width: 560, height: 296)); sc.autoresizingMask = [.width, .height]; sc.hasVerticalScroller = true; sc.drawsBackground = true
        let c = NSTableColumn(identifier: .init("j")); c.width = 540; c.resizingMask = .autoresizingMask; table.addTableColumn(c); table.headerView = nil; table.dataSource = self; table.delegate = self; table.rowHeight = 56; table.selectionHighlightStyle = .none
        sc.documentView = table; v.addSubview(sc)
        // Leiste unten
        pauseBtn.title = L("Anhalten", "Pause"); pauseBtn.bezelStyle = .rounded; pauseBtn.target = self; pauseBtn.action = #selector(togglePause); pauseBtn.frame = NSRect(x: 8, y: 10, width: 90, height: 26); v.addSubview(pauseBtn)
        let clear = NSButton(title: L("Fertige entfernen", "Clear Finished"), target: self, action: #selector(clearDone)); clear.bezelStyle = .rounded; clear.frame = NSRect(x: 102, y: 10, width: 130, height: 26); v.addSubview(clear)
        let pop = NSPopUpButton(frame: NSRect(x: 290, y: 10, width: 170, height: 26), pullsDown: false); pop.controlSize = .small; pop.font = lucida(11)
        for p in ConflictPolicy.allCases { pop.addItem(withTitle: p.title); pop.lastItem?.representedObject = p.rawValue }
        pop.selectItem(at: ConflictPolicy.allCases.firstIndex(of: Prefs.queuePolicy) ?? 0); pop.target = self; pop.action = #selector(policyChanged(_:)); pop.autoresizingMask = [.minXMargin]
        let l = NSTextField(labelWithString: L("Bei Konflikt:", "On conflict:")); l.font = lucida(11); l.frame = NSRect(x: 214, y: 15, width: 76, height: 14); l.alignment = .right
        let ver = NSButton(checkboxWithTitle: L("Prüfen", "Verify"), target: self, action: #selector(verifyChanged(_:))); ver.state = Prefs.queueVerify ? .on : .off; ver.font = lucida(11); ver.frame = NSRect(x: 466, y: 12, width: 84, height: 22); ver.toolTip = L("Nach dem Kopieren Größe und SHA-256 vergleichen", "After copying compare size and SHA-256"); ver.autoresizingMask = [.minXMargin]
        l.autoresizingMask = [.minXMargin]; [l, pop, ver].forEach { v.addSubview($0) }
        pauseBtn.autoresizingMask = [.maxXMargin]
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .queueChanged, object: nil)
    }
    func show() {
        reload(); if !win.isVisible { win.center(); if let k = NSApp.keyWindow { win.setFrameTopLeftPoint(NSPoint(x: k.frame.maxX - win.frame.width - 20, y: k.frame.minY + win.frame.height + 40)) } }
        win.orderFront(nil)
        if timer == nil { timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in TransferQueue.shared.tick(); if self?.win.isVisible == true { self?.table.reloadData() } } }
    }
    @objc func reload() { pauseBtn.title = TransferQueue.shared.paused ? L("Fortsetzen", "Resume") : L("Anhalten", "Pause"); table.reloadData() }
    @objc func togglePause() { TransferQueue.shared.paused.toggle() }
    @objc func clearDone() { TransferQueue.shared.clearFinished() }
    @objc func policyChanged(_ s: NSPopUpButton) { if let r = s.selectedItem?.representedObject as? String, let p = ConflictPolicy(rawValue: r) { Prefs.queuePolicy = p } }
    @objc func verifyChanged(_ s: NSButton) { Prefs.queueVerify = s.state == .on }
    func numberOfRows(in t: NSTableView) -> Int { TransferQueue.shared.jobs.count }

    static func rate(_ b: Double) -> String { Files.bytes.string(fromByteCount: Int64(b)) + "/s" }
    static func time(_ s: TimeInterval) -> String { s >= 3600 ? String(format: "%d:%02d h", Int(s) / 3600, Int(s) % 3600 / 60) : (s >= 60 ? String(format: "%d:%02d min", Int(s) / 60, Int(s) % 60) : "\(Int(s)) s") }
    func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let j = TransferQueue.shared.jobs[row]
        let v = NSView(frame: NSRect(x: 0, y: 0, width: t.bounds.width, height: 56))
        let title = NSTextField(labelWithString: j.title); title.font = lucida(12, bold: true); title.lineBreakMode = .byTruncatingMiddle; title.frame = NSRect(x: 10, y: 36, width: v.bounds.width - 54, height: 16); title.autoresizingMask = [.width]
        let bar = NSProgressIndicator(frame: NSRect(x: 10, y: 22, width: v.bounds.width - 54, height: 10)); bar.style = .bar; bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 1; bar.doubleValue = j.fraction; bar.autoresizingMask = [.width]
        var st = ""
        switch j.state {
        case .waiting: st = L("Wartet …", "Waiting…")
        case .running:
            st = TransferQueue.shared.paused ? L("Angehalten", "Paused") : "\(Int(j.fraction * 100)) % – \(Files.sizeString(j.control.done)) \(L("von", "of")) \(Files.sizeString(j.control.total))"
            if !TransferQueue.shared.paused, j.speed > 1 { st += " – \(Self.rate(j.speed))"; if let e = j.eta { st += " – " + L("noch ", "") + Self.time(e) + L("", " left") } }
        case .done: bar.doubleValue = 1; st = L("Fertig", "Done") + (j.verify && !j.move ? L(" – geprüft", " – verified") : "") + (j.started.map { " – " + Self.time(Date().timeIntervalSince($0)) } ?? "")
        case .failed(let e): st = L("Fehler: ", "Error: ") + e.replacingOccurrences(of: "\n", with: " "); bar.doubleValue = j.fraction
        case .cancelled: st = L("Abgebrochen", "Cancelled")
        }
        let sub = NSTextField(labelWithString: st); sub.font = lucida(11); sub.textColor = { if case .failed = j.state { return NSColor(190, 40, 30) }; return .secondaryLabelColor }(); sub.lineBreakMode = .byTruncatingTail; sub.frame = NSRect(x: 10, y: 4, width: v.bounds.width - 54, height: 15); sub.autoresizingMask = [.width]
        v.addSubview(title); v.addSubview(bar); v.addSubview(sub)
        if j.isActive { let x = NSButton(title: "✕", target: self, action: #selector(cancelRow(_:))); x.bezelStyle = .circular; x.tag = row; x.frame = NSRect(x: v.bounds.width - 36, y: 18, width: 26, height: 26); x.autoresizingMask = [.minXMargin]; x.toolTip = L("Abbrechen", "Cancel"); v.addSubview(x) }
        return v
    }
    @objc func cancelRow(_ s: NSButton) { let jobs = TransferQueue.shared.jobs; if jobs.indices.contains(s.tag) { TransferQueue.shared.cancel(jobs[s.tag]) } }
}
