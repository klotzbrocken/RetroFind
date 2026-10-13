import AppKit

// MARK: X-Modus: Tabs und Dual Pane (Einstellung: Einstellungen ▸ X-Modus)

extension Prefs {
    static var xMode: Bool { get { bool("xMode", false) } set { d.set(newValue, forKey: "xMode") } }
    /// Entweder Tabs oder Dual Pane (Radio-Auswahl)
    static var xKind: String { get { d.string(forKey: "xKind") ?? "tabs" } set { d.set(newValue, forKey: "xKind") } }
    static var xTabs: Bool { get { xKind == "tabs" } set { if newValue { xKind = "tabs" } } }
    static var xDual: Bool { get { xKind == "dual" } set { xKind = newValue ? "dual" : "tabs" } }
    // Allgemeine Dateiansicht-Optionen (unabhängig vom X-Modus)
    static var showLibrary: Bool { get { bool("showLibrary", bool("xShowLibrary", false)) } set { d.set(newValue, forKey: "showLibrary") } }
    static var showHidden: Bool { get { bool("showHidden", bool("xShowHidden", false)) } set { d.set(newValue, forKey: "showHidden") } }
    static var foldersFirst: Bool { get { bool("foldersFirst", bool("xFoldersFirst", false)) } set { d.set(newValue, forKey: "foldersFirst") } }
    static var aquaLights: Bool { get { bool("aquaLights", false) } set { d.set(newValue, forKey: "aquaLights") } }
}

extension BrowserController {
    var focus: BrowserController { dualOn && activeIsRight ? (rightPane ?? self) : self }
    var gastgeber: BrowserController { hostPane ?? self }

    func smallIcon(_ loc: Location) -> NSImage {
        switch loc {
        case .folder(let u): let g = Files.glyph(for: u); return IconCache.shared.folderImage(g == .home || g == .hardDisk ? .folder : g, size: 16)
        case .search: return IconCache.shared.smartFolder(16)
        default: return NSImage(size: NSSize(width: 16, height: 16), flipped: true) { r in loc.glyph.draw(in: r, selected: false); return true }
        }
    }

    // MARK: ChromeDelegate: Tabs
    var tabInfos: [TabInfo] {
        tabs.enumerated().map { i, t in
            let loc = i == tabIdx ? location : (t.history[safe: t.hIndex] ?? .folder(Files.home))
            return TabInfo(title: loc.title, icon: smallIcon(loc))
        }
    }
    var tabIndex: Int { tabIdx }
    func chromeTab(_ a: TabAction) {
        switch a {
        case .select(let i): selectTab(i)
        case .close(let i): closeTab(i)
        case .new: newTab()
        case .move(let f, let t): moveTab(f, t)
        }
    }
    func saveTab() { tabs[tabIdx] = TabState(history: history, hIndex: hIndex, selection: selection) }
    func newTab(_ loc: Location? = nil) {
        guard tabsOn else { return }
        saveTab()
        tabs.insert(TabState(history: [], hIndex: -1, selection: []), at: tabIdx + 1); tabIdx += 1
        history = []; hIndex = -1
        go(loc ?? location, record: true)
        chrome.needsDisplay = true
    }
    private func restore(_ t: TabState) {
        history = t.history; hIndex = t.hIndex
        go(history[safe: hIndex] ?? .folder(Files.home), record: false)
        if !t.selection.isEmpty { selection = t.selection; itemView?.selectionChanged(); itemView?.revealSelection() }
        chrome.needsDisplay = true
    }
    func selectTab(_ i: Int) {
        guard i != tabIdx, tabs.indices.contains(i) else { return }
        saveTab(); tabIdx = i; restore(tabs[i])
    }
    func closeTab(_ i: Int) {
        guard tabs.indices.contains(i) else { return }
        if tabs.count == 1 { win.performClose(nil); return }
        let cur = i == tabIdx
        saveTab()
        closedTabs.append(tabs[i]); if closedTabs.count > 10 { closedTabs.removeFirst() }
        tabs.remove(at: i)
        if cur { tabIdx = min(i, tabs.count - 1); restore(tabs[tabIdx]) } else { if i < tabIdx { tabIdx -= 1 }; chrome.needsDisplay = true }
    }
    func moveTab(_ f: Int, _ t: Int) {
        guard tabs.indices.contains(f), tabs.indices.contains(t), f != t else { return }
        saveTab(); let x = tabs.remove(at: f); tabs.insert(x, at: t)
        if tabIdx == f { tabIdx = t } else if f < tabIdx && t >= tabIdx { tabIdx -= 1 } else if f > tabIdx && t <= tabIdx { tabIdx += 1 }
        chrome.needsDisplay = true
    }
    @objc func newTabAction(_ s: Any?) { newTab() }
    @objc func nextTab(_ s: Any?) { if tabs.count > 1 { selectTab((tabIdx + 1) % tabs.count) } }
    @objc func prevTab(_ s: Any?) { if tabs.count > 1 { selectTab((tabIdx + tabs.count - 1) % tabs.count) } }
    /// ⌘⇧T: zuletzt geschlossenen Tab wiederherstellen
    @objc func reopenTab(_ s: Any?) {
        guard tabsOn, let t = closedTabs.popLast() else { NSSound.beep(); return }
        saveTab(); tabs.insert(t, at: tabIdx + 1); tabIdx += 1; restore(t)
    }
    /// ⌥⌘1…9: Tab direkt wählen (9 = letzter)
    @objc func jumpToTab(_ s: NSMenuItem) { let n = s.tag == 9 ? tabs.count - 1 : s.tag - 1; if tabsOn, tabs.indices.contains(n) { selectTab(n) } else { NSSound.beep() } }
    @objc func openInNewTab(_ s: Any?) { for n in selectedNodes where n.isFolderLike { newTab(.folder(n.url)) } }

    // MARK: Dual Pane
    @objc func toggleDual(_ s: Any?) {
        guard Prefs.xMode else { FileOps.shared.alert(L("Aktivieren Sie zuerst den X-Modus in den Einstellungen.", "Turn on X-Mode in Preferences first.")); return }
        Prefs.xKind = Prefs.xDual ? "tabs" : "dual"; BrowserController.applyXModeAll()
    }
    func setDual(_ on: Bool) {
        guard !paneMode else { return }
        if on, rightPane == nil {
            let rp = BrowserController(location: location, size: NSSize(width: 400, height: 400), showWindow: false)
            rp.hostWin = win; rp.hostPane = self
            rp.root.paneResponder = rp; rp.nextResponder = root
            root.addSubview(rp.root, positioned: .below, relativeTo: chrome)
            rightPane = rp; activeIsRight = false
            rp.loadVisited(); rp.noteVisited(rp.location)
            rp.layoutAll()
        } else if !on, let rp = rightPane {
            rp.root.removeFromSuperview(); rp.watcher?.cancel(); rp.searchEngine?.stop(); rp.nextResponder = nil
            rightPane = nil; activeIsRight = false
        }
        fbar.onKey = { [weak self] k in self?.dualKey(k) }
        strip.onHistory = { [weak self] _ in self?.showHistoryFromStrip(left: true) }
        rightPane?.strip.onHistory = { [weak self] _ in self?.showHistoryFromStrip(left: false) }
        strip.onFavorites = { [weak self] _ in self?.showFavoritesFromStrip(left: true) }
        rightPane?.strip.onFavorites = { [weak self] _ in self?.showFavoritesFromStrip(left: false) }
        strip.onDropFavorite = { [weak self] urls in var ok = false; for u in urls { if self?.addFavorite(u) == true { ok = true } }; return ok }
        rightPane?.strip.onDropFavorite = { [weak self] urls in var ok = false; for u in urls { if self?.gastgeber.rightPane?.addFavorite(u) == true { ok = true } }; return ok }
        refreshFavoriteState(); rightPane?.refreshFavoriteState()
        layoutAll()
        win.makeFirstResponder(itemView)
    }
    func setActivePane(right: Bool) {
        guard dualOn, activeIsRight != right else { return }
        activeIsRight = right
        strip.active = !right; rightPane?.strip.active = right
        win.makeFirstResponder(focus.itemView)
        chrome.needsDisplay = true; sidebar.needsDisplay = true
    }
    func routeMouse(_ e: NSEvent) {
        guard dualOn, let cv = win.contentView, let v = cv.hitTest(cv.convert(e.locationInWindow, from: nil)) else { return }
        var x: NSView? = v
        while let c = x { if c === rightPane?.root { setActivePane(right: true); return }; if c === contentView_ || c === pathBar { setActivePane(right: false); return }; x = c.superview }
    }
    /// F5–F8 und Tab (Dual Pane). Rückgabe: Ereignis verbraucht.
    func handleDualKey(_ e: NSEvent) -> Bool {
        guard dualOn, e.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        if win.firstResponder is NSTextView { return false }
        switch e.keyCode {
        case 48: setActivePane(right: !activeIsRight); return true
        case 99: dualKey(3); return true
        case 118: dualKey(4); return true
        case 96: dualKey(5); return true
        case 97: dualKey(6); return true
        case 98: dualKey(7); return true
        case 100: dualKey(8); return true
        default: return false
        }
    }
    func dualKey(_ k: Int) {
        let h = gastgeber; guard h.dualOn, let rp = h.rightPane else { return }
        let src = h.focus, dst = src === h ? rp : h
        switch k {
        case 5, 6:
            guard let dir = dst.currentDir, !src.selection.isEmpty else { NSSound.beep(); return }
            if Prefs.xQueue { TransferQueue.shared.enqueue(src.selection, to: dir, move: k == 6) { [weak h, weak rp] _ in h?.reload(); rp?.reload() } }
            else { FileOps.shared.transfer(src.selection, to: dir, move: k == 6) { [weak h, weak rp] _ in h?.reload(); rp?.reload() } }
        case 3: src.quickLook()
        case 4:   // F4: Auswahl im Editor öffnen (Standard: TextEdit)
            guard !src.selection.isEmpty else { NSSound.beep(); return }
            let ed = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
            NSWorkspace.shared.open(src.selection.filter { !$0.hasDirectoryPath }, withApplicationAt: ed, configuration: NSWorkspace.OpenConfiguration())
        case 7: src.newFolder(nil)
        case 8: if src.selection.isEmpty { NSSound.beep() } else { src.trashSelection() }
        default: break
        }
    }
    @objc func dualView(_ s: Any?) { dualKey(3) }
    @objc func dualEdit(_ s: Any?) { dualKey(4) }
    @objc func dualCopy(_ s: Any?) { dualKey(5) }
    @objc func dualMove(_ s: Any?) { dualKey(6) }
    @objc func dualNewFolder(_ s: Any?) { dualKey(7) }
    @objc func dualDelete(_ s: Any?) { dualKey(8) }
    @objc func switchPane(_ s: Any?) { gastgeber.setActivePane(right: !gastgeber.activeIsRight) }

    // MARK: Anwenden (Einstellungen / Menü)
    func applyXMode() {
        if !tabsOn, tabs.count > 1 { saveTab(); let keep = tabs[tabIdx]; tabs = [keep]; tabIdx = 0 }
        setDual(Prefs.xMode && Prefs.xDual)
        layoutAll(); chrome.relayout(); chrome.needsDisplay = true
    }
    static func applyXModeAll() {
        all.forEach { $0.applyXMode(); $0.reload(); $0.rightPane?.reload() }
        Menus.xMenu?.isHidden = !Prefs.xMode
    }
}

// MARK: Fußleiste mit F-Tasten (Snow-Leopard-Look)

final class FKeyBar: NSView {
    override var isFlipped: Bool { true }
    var onKey: ((Int) -> Void)?
    private var pressed: Int?
    static var defs: [(Int, String)] { [(3, L("Ansehen", "View")), (4, L("Bearbeiten", "Edit")), (5, L("Kopieren", "Copy")), (6, L("Verschieben", "Move")), (7, L("Neuer Ordner", "New Folder")), (8, L("Löschen", "Delete"))] }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private func rects() -> [NSRect] {
        let n = CGFloat(Self.defs.count), gap: CGFloat = 8, m: CGFloat = 10
        let w = (bounds.width - m * 2 - gap * (n - 1)) / n
        return (0..<Self.defs.count).map { NSRect(x: m + CGFloat($0) * (w + gap), y: 4, width: w, height: bounds.height - 8) }
    }
    override func draw(_ dirty: NSRect) {
        Draw.statusBar(bounds, active: true)
        for (i, r) in rects().enumerated() {
            Draw.button(r, pressed: pressed == i, active: true)
            let (k, t) = Self.defs[i]
            let c: NSColor = pressed == i ? .white : NSColor(gray: 30)
            let key = "F\(k)"
            Draw.text(key, in: NSRect(x: r.minX + 10, y: r.minY + 4, width: 24, height: 14), font: lucida(11, bold: true), color: pressed == i ? .white : NSColor(60, 100, 170))
            Draw.text(t, in: NSRect(x: r.minX + 34, y: r.minY + 4, width: r.width - 40, height: 14), font: lucida(12), color: c)
        }
    }
    override func mouseDown(with e: NSEvent) { let p = convert(e.locationInWindow, from: nil); pressed = rects().firstIndex { $0.contains(p) }; needsDisplay = true }
    override func mouseUp(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if let i = pressed, rects()[i].contains(p) { onKey?(Self.defs[i].0) }
        pressed = nil; needsDisplay = true
    }
}

// MARK: Tabs über Neustarts hinweg merken

extension BrowserController {
    static func encode(_ l: Location) -> String? {
        switch l { case .folder(let u): return u.path; case .allMyFiles: return "@allfiles"; case .computer: return "@computer"; case .network: return "@network"; case .airDrop: return "@airdrop"; case .search: return nil }
    }
    static func decode(_ s: String) -> Location { switch s { case "@allfiles": return .allMyFiles; case "@computer": return .computer; case "@network": return .network; case "@airdrop": return .airDrop; default: return .folder(URL(fileURLWithPath: s)) } }
    /// Nur das erste Fenster sichert seine Tabs (Orte + aktiver Tab).
    static var persistEnabled = false          // erst nach dem Wiederherstellen beim Start
    func persistTabs() {
        guard BrowserController.persistEnabled, tabsOn, !paneMode, BrowserController.all.first === self || BrowserController.all.isEmpty else { return }
        saveTabSafe()
        let paths = tabs.map { t in (t.history[safe: t.hIndex].flatMap { BrowserController.encode($0) }) ?? Files.home.path }
        UserDefaults.standard.set(paths, forKey: "savedTabs"); UserDefaults.standard.set(tabIdx, forKey: "savedTabIdx")
    }
    private func saveTabSafe() { if tabs.indices.contains(tabIdx), hIndex >= 0 { tabs[tabIdx] = TabState(history: history, hIndex: hIndex, selection: selection) } }
    func restoreTabs() {
        guard tabsOn, let saved = UserDefaults.standard.stringArray(forKey: "savedTabs"), saved.count > 1, tabs.count == 1 else { return }
        let idx = UserDefaults.standard.integer(forKey: "savedTabIdx")
        for p in saved.dropFirst() { newTab(BrowserController.decode(p)) }
        // erster Tab bekommt seinen gespeicherten Ort zurück
        tabs[0] = TabState(history: [BrowserController.decode(saved[0])], hIndex: 0, selection: [])
        selectTab(min(max(0, idx), tabs.count - 1))
    }
}

// MARK: Dual Pane: angleichen, tauschen; Auswahl nach Muster

extension BrowserController {
    /// ⌥⌘=: andere Hälfte zeigt denselben Ort wie die aktive
    @objc func mirrorPane(_ s: Any?) {
        let h = gastgeber; guard h.dualOn, let rp = h.rightPane else { NSSound.beep(); return }
        let src = h.focus, dst = src === h ? rp : h
        dst.go(src.location, record: true)
    }
    /// ⌥⌘X: Orte der beiden Hälften tauschen
    @objc func swapPanes(_ s: Any?) {
        let h = gastgeber; guard h.dualOn, let rp = h.rightPane else { NSSound.beep(); return }
        let a = h.location, b = rp.location
        h.go(b, record: true); rp.go(a, record: true)
    }
    @objc func selectPattern(_ s: Any?) { patternDialog(add: true) }
    @objc func deselectPattern(_ s: Any?) { patternDialog(add: false) }
    private func patternDialog(add: Bool) {
        let f = focus
        let a = NSAlert(); a.messageText = add ? L("Auswahl nach Muster", "Select by Pattern") : L("Auswahl nach Muster aufheben", "Deselect by Pattern")
        a.informativeText = L("Platzhalter: * (beliebig viele Zeichen), ? (ein Zeichen). Mehrere Muster mit Komma, z. B. *.png, *.jpg", "Wildcards: * (any characters), ? (one character). Separate patterns with commas, e.g. *.png, *.jpg")
        let t = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22)); t.stringValue = UserDefaults.standard.string(forKey: "lastPattern") ?? "*"; a.accessoryView = t
        a.addButton(withTitle: add ? L("Auswählen", "Select") : L("Aufheben", "Deselect")); a.addButton(withTitle: L("Abbrechen", "Cancel")); a.window.initialFirstResponder = t
        guard a.runModal() == .alertFirstButtonReturn else { return }
        UserDefaults.standard.set(t.stringValue, forKey: "lastPattern")
        f.applyPattern(t.stringValue, add: add)
    }
    func applyPattern(_ pattern: String, add: Bool) {
        let pats = pattern.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !pats.isEmpty else { return }
        let preds = pats.map { NSPredicate(format: "SELF LIKE[cd] %@", $0) }
        let hits = nodes.filter { n in preds.contains { $0.evaluate(with: n.name) } }.map { $0.url }
        var sel = selection
        if add { for u in hits where !sel.contains(u) { sel.append(u) } } else { sel.removeAll { hits.contains($0) } }
        setSelection(sel, source: nil); itemView?.selectionChanged(); itemView?.revealSelection()
        if hits.isEmpty { NSSound.beep() }
    }
}

// MARK: Aktionen: Mehrfach-Umbenennen, Warteschlange

extension BrowserController {
    @objc func batchRename(_ s: Any?) {
        let f = focus
        guard !f.selection.isEmpty else { NSSound.beep(); return }
        BatchRenameWindow.show(f.selection, from: win) { [weak f] new in f?.reload(); f?.setSelection(new, source: nil); f?.itemView?.selectionChanged() }
    }
    @objc func showQueue(_ s: Any?) { QueueWindow.shared.show() }
}

// MARK: Verlauf je Hälfte

extension BrowserController {
    static let visitedMax = 30
    var visitedKey: String { paneMode ? "hist.right" : "hist.left" }
    /// Ort an den Anfang der Liste setzen (ohne Doppelte); virtuelle Suchen werden nicht gemerkt
    func noteVisited(_ loc: Location) {
        guard BrowserController.encode(loc) != nil else { return }
        visited.removeAll { $0 == loc }; visited.insert(loc, at: 0)
        if visited.count > BrowserController.visitedMax { visited.removeLast(visited.count - BrowserController.visitedMax) }
        if BrowserController.persistEnabled || paneMode { UserDefaults.standard.set(visited.compactMap { BrowserController.encode($0) }, forKey: visitedKey) }
    }
    func loadVisited() {
        let saved = (UserDefaults.standard.stringArray(forKey: visitedKey) ?? []).map { BrowserController.decode($0) }.filter { loc in if case .folder(let u) = loc { return Files.exists(u) }; return true }
        for l in saved.reversed() where !visited.contains(l) { visited.append(l) }
        visited = Array(visited.prefix(BrowserController.visitedMax))
    }
    func historyMenu() -> NSMenu {
        let m = NSMenu(); m.autoenablesItems = false
        let head = NSMenuItem(title: L("Verlauf dieser Hälfte", "History of this pane"), action: nil, keyEquivalent: ""); head.isEnabled = false; m.addItem(head)
        for l in visited {
            guard let enc = BrowserController.encode(l) else { continue }
            let it = NSMenuItem(title: l.title, action: #selector(historyPick(_:)), keyEquivalent: ""); it.target = self; it.representedObject = enc
            it.image = smallIcon(l); it.state = l == location ? .on : .off
            if case .folder(let u) = l { it.toolTip = u.path }
            m.addItem(it)
        }
        m.addItem(.separator())
        let clr = NSMenuItem(title: L("Verlauf löschen", "Clear History"), action: #selector(clearHistory(_:)), keyEquivalent: ""); clr.target = self; m.addItem(clr)
        return m
    }
    @objc func historyPick(_ s: NSMenuItem) { if let e = s.representedObject as? String { navigate(BrowserController.decode(e)) } }
    @objc func clearHistory(_ s: Any?) { visited = [location]; UserDefaults.standard.set(visited.compactMap { BrowserController.encode($0) }, forKey: visitedKey) }
    /// ⌥↓ bzw. Knopf in der Kopfleiste: Verlauf der aktiven Hälfte aufklappen
    @objc func showHistory(_ s: Any?) {
        let f = focus
        let m = f.historyMenu()
        if f.dualOn || f.paneMode { let st = f.strip; m.popUp(positioning: nil, at: NSPoint(x: max(0, st.bounds.width - 240), y: st.bounds.height), in: st) }
        else { let v = f.contentView_; m.popUp(positioning: nil, at: NSPoint(x: 8, y: 4), in: v) }
    }
}

extension BrowserController {
    func showHistoryFromStrip(left: Bool) {
        let h = gastgeber; let pane = left ? h : (h.rightPane ?? h)
        let m = pane.historyMenu(); let st = pane.strip
        m.popUp(positioning: nil, at: NSPoint(x: max(0, st.bounds.width - 240), y: st.bounds.height), in: st)
    }
}

// MARK: Favoriten je Hälfte (Hotlist)

extension BrowserController {
    var favKey: String { paneMode ? "fav.right" : "fav.left" }
    static func favorites(_ key: String) -> [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    var favorites: [String] { get { BrowserController.favorites(favKey) } set { UserDefaults.standard.set(newValue, forKey: favKey) } }
    var currentIsFavorite: Bool { currentDir.map { favorites.contains($0.standardizedFileURL.path) } ?? false }
    func refreshFavoriteState() { strip.isFavorite = currentIsFavorite }

    @discardableResult func addFavorite(_ u: URL) -> Bool {
        let p = u.standardizedFileURL.path
        guard (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true, !favorites.contains(p) else { return false }
        favorites.append(p); refreshFavoriteState(); return true
    }
    func removeFavorite(_ p: String) { favorites.removeAll { $0 == p }; refreshFavoriteState() }
    /// ⇧⌥⌘B: aktuellen Ordner zu den Favoriten dieser Hälfte hinzufügen bzw. daraus entfernen
    @objc func toggleFavorite(_ s: Any?) {
        let f = focus
        guard let d = f.currentDir else { NSSound.beep(); return }
        if f.currentIsFavorite { f.removeFavorite(d.standardizedFileURL.path) } else { f.addFavorite(d) }
    }
    func favoritesMenu() -> NSMenu {
        let m = NSMenu(); m.autoenablesItems = false
        let head = NSMenuItem(title: L("Favoriten dieser Hälfte", "Favorites of this pane"), action: nil, keyEquivalent: ""); head.isEnabled = false; m.addItem(head)
        let favs = favorites
        if favs.isEmpty { let e = NSMenuItem(title: L("Noch keine Favoriten", "No favorites yet"), action: nil, keyEquivalent: ""); e.isEnabled = false; m.addItem(e) }
        for p in favs {
            let u = URL(fileURLWithPath: p); let exists = Files.exists(u)
            let it = NSMenuItem(title: Files.displayName(u) + (exists ? "" : L(" (nicht gefunden)", " (not found)")), action: #selector(favoritePick(_:)), keyEquivalent: ""); it.target = self; it.representedObject = p; it.isEnabled = exists
            it.image = smallIcon(.folder(u)); it.toolTip = p; if currentDir?.standardizedFileURL.path == p { it.state = .on }
            m.addItem(it)
        }
        m.addItem(.separator())
        let isFav = currentIsFavorite
        let add = NSMenuItem(title: isFav ? L("Aktuellen Ordner entfernen", "Remove Current Folder") : L("Aktuellen Ordner hinzufügen", "Add Current Folder"), action: #selector(toggleFavorite(_:)), keyEquivalent: ""); add.target = self; add.isEnabled = currentDir != nil; m.addItem(add)
        let mg = NSMenuItem(title: L("Favoriten verwalten …", "Manage Favorites…"), action: #selector(manageFavorites(_:)), keyEquivalent: ""); mg.target = self; m.addItem(mg)
        if gastgeber.dualOn { let cp = NSMenuItem(title: L("In die andere Hälfte kopieren", "Copy to Other Pane"), action: #selector(copyFavoritesToOther(_:)), keyEquivalent: ""); cp.target = self; cp.isEnabled = !favs.isEmpty; m.addItem(cp) }
        return m
    }
    @objc func favoritePick(_ s: NSMenuItem) { if let p = s.representedObject as? String { navigate(.folder(URL(fileURLWithPath: p))) } }
    @objc func copyFavoritesToOther(_ s: Any?) {
        let h = gastgeber; guard h.dualOn, let rp = h.rightPane else { return }
        let src = h.focus, dst = src === h ? rp : h
        var d = dst.favorites; for p in src.favorites where !d.contains(p) { d.append(p) }; dst.favorites = d; dst.refreshFavoriteState()
    }
    @objc func manageFavorites(_ s: Any?) { FavoritesManager.show(for: self) }
    /// ⌥⌘B bzw. Stern in der Kopfleiste: Favoriten der aktiven Hälfte aufklappen
    @objc func showFavorites(_ s: Any?) {
        let f = focus; let m = f.favoritesMenu()
        if f.dualOn || f.paneMode { let st = f.strip; m.popUp(positioning: nil, at: NSPoint(x: max(0, st.bounds.width - 260), y: st.bounds.height), in: st) }
        else { m.popUp(positioning: nil, at: NSPoint(x: 8, y: 4), in: f.contentView_) }
    }
    func showFavoritesFromStrip(left: Bool) {
        let h = gastgeber; let pane = left ? h : (h.rightPane ?? h)
        let m = pane.favoritesMenu(); let st = pane.strip
        m.popUp(positioning: nil, at: NSPoint(x: max(0, st.bounds.width - 260), y: st.bounds.height), in: st)
    }
}

/// Verwaltung der Favoriten einer Hälfte: umordnen, entfernen, aktuellen Ordner hinzufügen
final class FavoritesManager: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static var open: [String: FavoritesManager] = [:]
    let pane: BrowserController; let key: String
    let win = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 320), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
    let table = NSTableView()
    static func show(for p: BrowserController) {
        if let m = open[p.favKey] { m.win.makeKeyAndOrderFront(nil); m.table.reloadData(); return }
        let m = FavoritesManager(p); open[p.favKey] = m; m.win.center(); m.win.makeKeyAndOrderFront(nil)
    }
    init(_ p: BrowserController) {
        pane = p; key = p.favKey; super.init()
        win.title = (p.paneMode ? L("Favoriten – rechte Hälfte", "Favorites – right pane") : L("Favoriten – linke Hälfte", "Favorites – left pane")); win.isReleasedWhenClosed = false
        let v = win.contentView!
        let sc = NSScrollView(frame: NSRect(x: 12, y: 50, width: 416, height: 258)); sc.hasVerticalScroller = true; sc.borderType = .bezelBorder; sc.autoresizingMask = [.width, .height]
        let c = NSTableColumn(identifier: .init("p")); c.width = 400; c.resizingMask = .autoresizingMask; table.addTableColumn(c); table.headerView = nil; table.dataSource = self; table.delegate = self; table.rowHeight = 20
        table.registerForDraggedTypes([.string]); table.draggingDestinationFeedbackStyle = .gap
        sc.documentView = table; v.addSubview(sc)
        func btn(_ t: String, _ x: CGFloat, _ w: CGFloat, _ a: Selector) -> NSButton { let b = NSButton(title: t, target: self, action: a); b.bezelStyle = .rounded; b.frame = NSRect(x: x, y: 12, width: w, height: 26); b.autoresizingMask = [.maxXMargin, .maxYMargin]; v.addSubview(b); return b }
        _ = btn("−", 12, 34, #selector(remove)); _ = btn("↑", 50, 34, #selector(up)); _ = btn("↓", 88, 34, #selector(down))
        _ = btn(L("Aktuellen Ordner hinzufügen", "Add Current Folder"), 130, 210, #selector(addCurrent)); _ = btn(L("Fertig", "Done"), 350, 78, #selector(done))
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: UserDefaults.didChangeNotification, object: nil)
    }
    var items: [String] { get { BrowserController.favorites(key) } set { UserDefaults.standard.set(newValue, forKey: key); pane.refreshFavoriteState() } }
    @objc func reload() { table.reloadData() }
    func numberOfRows(in t: NSTableView) -> Int { items.count }
    func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let p = items[row]; let u = URL(fileURLWithPath: p)
        let tf = NSTextField(labelWithString: "\(Files.displayName(u))   —   \(p)"); tf.font = lucida(11); tf.lineBreakMode = .byTruncatingMiddle; tf.textColor = Files.exists(u) ? .labelColor : NSColor(190, 40, 30); return tf
    }
    @objc func remove() { let r = table.selectedRow; guard r >= 0 else { return }; var i = items; i.remove(at: r); items = i; table.reloadData() }
    @objc func up() { move(-1) }
    @objc func down() { move(1) }
    private func move(_ d: Int) { let r = table.selectedRow; guard r >= 0, r + d >= 0, r + d < items.count else { return }; var i = items; i.swapAt(r, r + d); items = i; table.reloadData(); table.selectRowIndexes([r + d], byExtendingSelection: false) }
    @objc func addCurrent() { if let d = pane.currentDir { pane.addFavorite(d); table.reloadData() } }
    @objc func done() { win.close(); FavoritesManager.open[key] = nil }
    // Umordnen per Ziehen
    func tableView(_ t: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? { String(row) as NSString }
    func tableView(_ t: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation { op == .above ? .move : [] }
    func tableView(_ t: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation op: NSTableView.DropOperation) -> Bool {
        guard let s = info.draggingPasteboard.string(forType: .string), let from = Int(s) else { return false }
        var i = items; let m = i.remove(at: from); i.insert(m, at: row > from ? row - 1 : row); items = i; t.reloadData(); return true
    }
}

// MARK: Globale Ansicht

extension BrowserController {
    /// Ein-/Ausschalten der gemeinsamen Ansicht für alle Ordner; alle offenen Fenster übernehmen sie sofort
    static func setGlobalView(_ on: Bool, from c: BrowserController?) {
        ViewStore.setGlobal(on, from: c?.options)
        for w in all { w.reapplyView(); w.rightPane?.reapplyView() }
    }
    func reapplyView() {
        suppressSave = true; options = ViewStore.options(for: location); suppressSave = false
        buildItemView(); arrangeAndShow(keepSelection: true); chrome.needsDisplay = true; updateStatus()
    }
}
