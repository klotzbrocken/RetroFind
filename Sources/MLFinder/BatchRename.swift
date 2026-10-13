import AppKit

// MARK: Mehrfach-Umbenennen (X-Modus)

struct RenameSpec: Equatable {
    enum Mode: Int, CaseIterable { case replace, add, number, caseChange, regex }
    var mode: Mode = .replace
    var find = "", replaceWith = ""
    var caseSensitive = false
    var addText = "", atStart = true
    var format = "{name} {n}"
    var start = 1, step = 1, digits = 2
    var caseMode = 0                 // 0 GROSS, 1 klein, 2 Wörter, 3 Satzanfang
    var keepExt = true
    static func title(_ m: Mode) -> String {
        switch m { case .replace: return L("Text ersetzen", "Replace text"); case .add: return L("Text hinzufügen", "Add text"); case .number: return L("Nummerieren / Format", "Number / format"); case .caseChange: return L("Groß-/Kleinschreibung", "Change case"); case .regex: return L("Regulärer Ausdruck", "Regular expression") }
    }
}

enum BatchRename {
    /// Neuer Name für Eintrag `index`; nil bei ungültigem Muster.
    static func newName(_ old: String, index: Int, spec s: RenameSpec) -> String? {
        let ns = old as NSString
        let ext = ns.pathExtension
        let hasExt = s.keepExt && !ext.isEmpty && ns.deletingPathExtension.count > 0
        let base = hasExt ? ns.deletingPathExtension : old
        var out: String
        switch s.mode {
        case .replace:
            out = s.find.isEmpty ? base : base.replacingOccurrences(of: s.find, with: s.replaceWith, options: s.caseSensitive ? [] : .caseInsensitive)
        case .add:
            out = s.atStart ? s.addText + base : base + s.addText
        case .number:
            let n = s.start + index * s.step
            let num = String(format: "%0\(max(1, s.digits))d", n)
            var f = s.format.isEmpty ? "{name}" : s.format
            if !f.contains("{n}") { f += " {n}" }
            out = f.replacingOccurrences(of: "{name}", with: base).replacingOccurrences(of: "{n}", with: num)
        case .caseChange:
            switch s.caseMode {
            case 0: out = base.uppercased()
            case 1: out = base.lowercased()
            case 2: out = base.capitalized
            default: out = base.prefix(1).uppercased() + base.dropFirst().lowercased()
            }
        case .regex:
            guard !s.find.isEmpty else { out = base; break }
            guard let re = try? NSRegularExpression(pattern: s.find, options: s.caseSensitive ? [] : .caseInsensitive) else { return nil }
            out = re.stringByReplacingMatches(in: base, options: [], range: NSRange(location: 0, length: (base as NSString).length), withTemplate: s.replaceWith)
        }
        return hasExt ? out + "." + ext : out
    }

    /// Fehlertext je Eintrag (leer = ok): leere/ungültige Namen, doppelte Ziele, Kollision mit nicht beteiligten Objekten
    static func problems(urls: [URL], names: [String?]) -> [String] {
        var out = [String](repeating: "", count: urls.count)
        var seen: [String: Int] = [:]
        let selected = Set(urls.map { $0.path })
        for (i, u) in urls.enumerated() {
            guard let n = names[i] else { out[i] = L("Ungültiges Muster", "Invalid pattern"); continue }
            let key = u.deletingLastPathComponent().path + "/" + n.lowercased()
            if n.isEmpty || n.contains("/") || n.contains(":") || n.utf8.count > 255 { out[i] = L("Ungültiger Name", "Invalid name"); continue }
            if let j = seen[key] { out[i] = L("Doppelt (wie Eintrag \(j + 1))", "Duplicate (same as item \(j + 1))"); continue }
            seen[key] = i
            let target = u.deletingLastPathComponent().appendingPathComponent(n)
            if n != u.lastPathComponent, Files.exists(target), !selected.contains(target.path), target.path.lowercased() != u.path.lowercased() { out[i] = L("Name bereits vergeben", "Name already taken") }
        }
        return out
    }
}

extension FileOps {
    /// Benennt mehrere Objekte um (zweistufig über temporäre Namen → Tausch/Verschiebung ohne Kollision), ein Undo-Schritt.
    @discardableResult func batchRename(_ pairs: [(url: URL, name: String)]) -> [URL] {
        let todo = pairs.filter { $0.url.lastPathComponent != $0.name }
        guard !todo.isEmpty else { return pairs.map { $0.url } }
        var temps: [(tmp: URL, final: URL, orig: URL)] = []
        func rollback() { for t in temps.reversed() { if Files.exists(t.tmp) { try? Files.fm.moveItem(at: t.tmp, to: t.orig) } else if Files.exists(t.final) { try? Files.fm.moveItem(at: t.final, to: t.orig) } } }
        // Phase 1: alle auf temporäre Namen
        for p in todo {
            let tmp = p.url.deletingLastPathComponent().appendingPathComponent(".mlf-rename-\(UUID().uuidString.prefix(8))")
            do { try Files.fm.moveItem(at: p.url, to: tmp) } catch { rollback(); alert(L("Mehrfach-Umbenennen abgebrochen: „\(p.url.lastPathComponent)“ konnte nicht umbenannt werden.", "Batch rename stopped: \u{201C}\(p.url.lastPathComponent)\u{201D} couldn\u{2019}t be renamed."), error.localizedDescription); return pairs.map { $0.url } }
            temps.append((tmp, p.url.deletingLastPathComponent().appendingPathComponent(p.name), p.url))
        }
        // Phase 2: auf Zielnamen
        var done: [(URL, URL)] = []
        for t in temps {
            do { try Files.fm.moveItem(at: t.tmp, to: t.final); done.append((t.orig, t.final)) }
            catch { for d in done.reversed() { try? Files.fm.moveItem(at: d.1, to: d.0) }; rollback(); alert(L("Mehrfach-Umbenennen abgebrochen.", "Batch rename stopped."), error.localizedDescription); return pairs.map { $0.url } }
        }
        let moves = done
        register(L("Mehrfach-Umbenennen (\(moves.count) Objekte)", "Batch Rename (\(moves.count) items)"),
                 undo: { FileOps.twoPhase(moves.map { ($0.1, $0.0) }) }, redo: { FileOps.twoPhase(moves) })
        changed()
        return pairs.map { p in p.url.lastPathComponent == p.name ? p.url : p.url.deletingLastPathComponent().appendingPathComponent(p.name) }
    }
    static func twoPhase(_ moves: [(URL, URL)]) {
        var tmps: [(URL, URL)] = []
        for m in moves { let t = m.0.deletingLastPathComponent().appendingPathComponent(".mlf-rename-\(UUID().uuidString.prefix(8))"); if (try? Files.fm.moveItem(at: m.0, to: t)) != nil { tmps.append((t, m.1)) } }
        for t in tmps { try? Files.fm.moveItem(at: t.0, to: t.1) }
    }
}

// MARK: Dialog

final class BatchRenameWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    static var current: BatchRenameWindow?
    let win = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    let urls: [URL]; var spec = RenameSpec(); var names: [String?] = []; var probs: [String] = []
    let table = NSTableView()
    let modePop = NSPopUpButton(frame: .zero, pullsDown: false)
    var labels: [NSTextField] = [], fields: [NSTextField] = []
    let keepExt = NSButton(checkboxWithTitle: L("Erweiterung beibehalten", "Keep extension"), target: nil, action: nil)
    let caseSens = NSButton(checkboxWithTitle: L("Groß-/Kleinschreibung beachten", "Match case"), target: nil, action: nil)
    let startPop = NSPopUpButton(frame: .zero, pullsDown: false), casePop = NSPopUpButton(frame: .zero, pullsDown: false)
    let status = NSTextField(labelWithString: ""); let ok = NSButton(title: L("Umbenennen", "Rename"), target: nil, action: nil)
    weak var parent: NSWindow?; var done: (([URL]) -> Void)?

    static func show(_ urls: [URL], from w: NSWindow?, done: (([URL]) -> Void)? = nil) {
        guard urls.count >= 1 else { NSSound.beep(); return }
        let b = BatchRenameWindow(urls: urls); b.parent = w; b.done = done; current = b; b.build()
        b.win.center(); b.win.makeKeyAndOrderFront(nil)
    }
    init(urls: [URL]) { self.urls = urls; names = urls.map { $0.lastPathComponent }; probs = [String](repeating: "", count: urls.count); super.init() }

    func build() {
        win.title = L("Mehrfach-Umbenennen – \(urls.count) Objekte", "Batch Rename – \(urls.count) items")
        let v = win.contentView!
        func lab(_ s: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat) -> NSTextField { let t = NSTextField(labelWithString: s); t.font = lucida(12); t.alignment = .right; t.frame = NSRect(x: x, y: y, width: w, height: 17); v.addSubview(t); return t }
        // Oberkante = 560: wir platzieren von oben nach unten
        _ = lab(L("Vorgang:", "Action:"), 14, 524, 80)
        for m in RenameSpec.Mode.allCases { modePop.addItem(withTitle: RenameSpec.title(m)) }
        modePop.frame = NSRect(x: 100, y: 520, width: 230, height: 24); modePop.target = self; modePop.action = #selector(modeChanged); v.addSubview(modePop)
        keepExt.frame = NSRect(x: 360, y: 522, width: 280, height: 20); keepExt.state = .on; keepExt.target = self; keepExt.action = #selector(changed); keepExt.font = lucida(12); v.addSubview(keepExt)
        for i in 0..<4 {
            let l = lab("", 14, 486 - CGFloat(i) * 32, 130); labels.append(l)
            let f = NSTextField(frame: NSRect(x: 150, y: 482 - CGFloat(i) * 32, width: 300, height: 24)); f.delegate = self; f.font = lucida(12); v.addSubview(f); fields.append(f)
        }
        caseSens.frame = NSRect(x: 150, y: 358, width: 300, height: 20); caseSens.target = self; caseSens.action = #selector(changed); caseSens.font = lucida(12); v.addSubview(caseSens)
        startPop.addItems(withTitles: [L("Am Anfang", "At start"), L("Am Ende", "At end")]); startPop.frame = NSRect(x: 460, y: 482, width: 150, height: 24); startPop.target = self; startPop.action = #selector(changed); v.addSubview(startPop)
        casePop.addItems(withTitles: [L("GROSSBUCHSTABEN", "UPPERCASE"), L("kleinbuchstaben", "lowercase"), L("Wörter Groß", "Capitalize Words"), L("Satzanfang groß", "Sentence case")]); casePop.frame = NSRect(x: 150, y: 482, width: 220, height: 24); casePop.target = self; casePop.action = #selector(changed); v.addSubview(casePop)
        let sc = NSScrollView(frame: NSRect(x: 14, y: 54, width: 632, height: 290)); sc.hasVerticalScroller = true; sc.borderType = .bezelBorder
        let c1 = NSTableColumn(identifier: .init("old")); c1.title = L("Vorher", "Before"); c1.width = 270
        let c2 = NSTableColumn(identifier: .init("new")); c2.title = L("Nachher", "After"); c2.width = 270
        let c3 = NSTableColumn(identifier: .init("st")); c3.title = ""; c3.width = 70
        [c1, c2, c3].forEach { table.addTableColumn($0) }; table.dataSource = self; table.delegate = self; table.rowHeight = 19; sc.documentView = table; sc.autoresizingMask = [.width, .height]; v.addSubview(sc)
        status.frame = NSRect(x: 14, y: 22, width: 380, height: 17); status.font = lucida(11); status.textColor = .secondaryLabelColor; v.addSubview(status)
        let cancel = NSButton(title: L("Abbrechen", "Cancel"), target: self, action: #selector(cancel)); cancel.frame = NSRect(x: 420, y: 14, width: 110, height: 28); cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"; v.addSubview(cancel)
        ok.frame = NSRect(x: 536, y: 14, width: 114, height: 28); ok.bezelStyle = .rounded; ok.keyEquivalent = "\r"; ok.target = self; ok.action = #selector(apply); v.addSubview(ok)
        for s in v.subviews where s.frame.minY > 340 { s.autoresizingMask = [.minYMargin] }
        status.autoresizingMask = [.maxYMargin]; ok.autoresizingMask = [.minXMargin, .maxYMargin]; cancel.autoresizingMask = [.minXMargin, .maxYMargin]
        modeChanged()
    }

    @objc func modeChanged() {
        let m = RenameSpec.Mode(rawValue: modePop.indexOfSelectedItem) ?? .replace
        func set(_ i: Int, _ t: String?, _ ph: String = "") { labels[i].stringValue = t ?? ""; labels[i].isHidden = t == nil; fields[i].isHidden = t == nil; fields[i].placeholderString = ph }
        for i in 0..<4 { set(i, nil) }
        caseSens.isHidden = true; startPop.isHidden = true; casePop.isHidden = true
        switch m {
        case .replace: set(0, L("Suchen:", "Find:")); set(1, L("Ersetzen durch:", "Replace with:")); caseSens.isHidden = false
        case .add: set(0, L("Text:", "Text:")); startPop.isHidden = false
        case .number: set(0, L("Format:", "Format:"), "{name} {n}"); set(1, L("Start:", "Start:"), "1"); set(2, L("Schritt:", "Step:"), "1"); set(3, L("Stellen:", "Digits:"), "2")
            if fields[0].stringValue.isEmpty { fields[0].stringValue = "{name} {n}" }; if fields[1].stringValue.isEmpty { fields[1].stringValue = "1" }; if fields[2].stringValue.isEmpty { fields[2].stringValue = "1" }; if fields[3].stringValue.isEmpty { fields[3].stringValue = "2" }
        case .caseChange: casePop.isHidden = false
        case .regex: set(0, L("Muster:", "Pattern:"), "^(\\\\d+)_"); set(1, L("Ersetzen ($1 …):", "Replace ($1 …):")); caseSens.isHidden = false
        }
        changed()
    }
    func controlTextDidChange(_ n: Notification) { changed() }
    @objc func changed() {
        var s = RenameSpec(); s.mode = RenameSpec.Mode(rawValue: modePop.indexOfSelectedItem) ?? .replace
        s.keepExt = keepExt.state == .on; s.caseSensitive = caseSens.state == .on
        s.find = fields[0].stringValue; s.replaceWith = fields[1].stringValue
        s.addText = fields[0].stringValue; s.atStart = startPop.indexOfSelectedItem == 0
        s.format = fields[0].stringValue; s.start = Int(fields[1].stringValue) ?? 1; s.step = Int(fields[2].stringValue) ?? 1; s.digits = Int(fields[3].stringValue) ?? 2
        s.caseMode = casePop.indexOfSelectedItem
        if s.mode == .regex { s.find = fields[0].stringValue; s.replaceWith = fields[1].stringValue }
        spec = s
        names = urls.enumerated().map { BatchRename.newName($0.element.lastPathComponent, index: $0.offset, spec: s) }
        probs = BatchRename.problems(urls: urls, names: names)
        table.reloadData()
        let bad = probs.filter { !$0.isEmpty }.count, changedN = zip(urls, names).filter { $0.0.lastPathComponent != $0.1 }.count
        status.stringValue = bad > 0 ? L("\(bad) Konflikte – bitte beheben.", "\(bad) conflicts – please fix.") : L("\(changedN) von \(urls.count) Objekten werden umbenannt.", "\(changedN) of \(urls.count) items will be renamed.")
        status.textColor = bad > 0 ? NSColor(190, 40, 30) : .secondaryLabelColor
        ok.isEnabled = bad == 0 && changedN > 0
    }
    func numberOfRows(in t: NSTableView) -> Int { urls.count }
    func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let tf = NSTextField(labelWithString: ""); tf.font = lucida(11); tf.lineBreakMode = .byTruncatingMiddle
        guard urls.indices.contains(row), names.indices.contains(row), probs.indices.contains(row) else { return tf }
        switch col?.identifier.rawValue {
        case "old": tf.stringValue = urls[row].lastPathComponent
        case "new": tf.stringValue = names[row] ?? "—"; if !probs[row].isEmpty { tf.textColor = NSColor(190, 40, 30) } else if names[row] != urls[row].lastPathComponent { tf.font = lucida(11, bold: true) }
        default: tf.stringValue = probs[row]; tf.textColor = NSColor(190, 40, 30); tf.font = lucida(10)
        }
        return tf
    }
    @objc func cancel() { win.orderOut(nil); BatchRenameWindow.current = nil }
    @objc func apply() {
        let pairs = zip(urls, names).compactMap { u, n in n.map { (url: u, name: $0) } }
        win.orderOut(nil); BatchRenameWindow.current = nil
        let r = FileOps.shared.batchRename(pairs); done?(r)
    }
}
