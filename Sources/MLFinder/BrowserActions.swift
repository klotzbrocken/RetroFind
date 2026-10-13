import AppKit
import QuickLookUI

// MARK: Menüaktionen eines Finder-Fensters

extension BrowserController {
    var nodesSel: [FileNode] { selectedNodes }
    var targets: [URL] { selection }
    private var singleName: String { selection.count == 1 ? "„\(selection[0].lastPathComponent)“" : L("\(selection.count) Objekte", "\(selection.count) Items") }

    // MARK: Ablage
    @objc func newFinderWindow(_ s: Any?) { BrowserController.open(BrowserController.startLocation(), from: self) }
    @objc func newFolder(_ s: Any?) {
        guard let d = currentDir else { NSSound.beep(); return }
        if let u = FileOps.shared.newFolder(in: d) { load(); selection = [u]; itemView?.selectionChanged(); itemView?.revealSelection(); itemView?.startRename() }
    }
    @objc func newFolderWithSelection(_ s: Any?) {
        guard let d = currentDir, !selection.isEmpty else { return }
        if let u = FileOps.shared.newFolder(in: d, name: L("Neuer Ordner mit Auswahl (\(selection.count))", "New Folder With Items"), with: selection) { load(); selection = [u]; itemView?.selectionChanged(); itemView?.startRename() }
    }
    @objc func newSmartFolder(_ s: Any?) {
        var spec = SearchSpec(); spec.scope = currentDir.map { "folder:" + $0.path } ?? "this"; spec.criteria = [Criterion(attr: "kind", op: "is", value: "doc")]; spec.name = ""
        searchBar.showCriteria = true
        go(.search(spec), record: true)
    }
    @objc func newBurnFolder(_ s: Any?) {
        guard let d = currentDir, let u = FileOps.shared.newBurnFolder(in: d) else { return }
        load(); selection = [u]; itemView?.selectionChanged(); itemView?.startRename()
    }
    /// Ordnergrößen auf Knopfdruck: Auswahl (oder – ohne Auswahl – alle Ordner der Ansicht), rekursiv, im Hintergrund
    @objc func calcFolderSizes(_ s: Any?) {
        var targets = selectedNodes.filter { $0.isDir }
        if targets.isEmpty { targets = nodes.filter { $0.isDir && !$0.isPackage } }
        targets = targets.filter { !$0.calculating }
        guard !targets.isEmpty else { NSSound.beep(); return }
        sizeBatch?.cancelled = true
        sizeBusy = true; updateStatus()
        sizeBatch = SizeService.shared.calculate(targets, onUpdate: { [weak self] in self?.itemView?.needsDisplay = true; self?.updateStatus() }, onFinish: { [weak self] in self?.sizeBusy = false; self?.updateStatus(); self?.itemView?.needsDisplay = true })
        itemView?.needsDisplay = true
    }
    @objc func openItem(_ s: Any?) { openSelection() }
    @objc func openItemInNewWindow(_ s: Any?) { for n in nodesSel where n.isFolderLike { BrowserController.open(.folder(n.url), from: self) } }
    @objc func openWithApp(_ s: NSMenuItem) {
        guard let app = s.representedObject as? URL else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(selection, withApplicationAt: app, configuration: cfg, completionHandler: nil)
    }
    @objc func openWithOther(_ s: Any?) {
        let p = NSOpenPanel(); p.directoryURL = Files.applications; p.allowedContentTypes = [.application]; p.message = L("Wählen Sie ein Programm.", "Choose an application.")
        if p.runModal() == .OK, let u = p.url { NSWorkspace.shared.open(selection, withApplicationAt: u, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil) }
    }
    @objc func closeWin(_ s: Any?) { let h = gastgeber; if h.tabsOn && h.tabs.count > 1 { h.closeTab(h.tabIdx) } else { h.win.performClose(nil) } }
    @objc func getInfo(_ s: Any?) { InfoWindow.show(selection.isEmpty ? (currentDir.map { [$0] } ?? []) : selection, from: self) }
    @objc func getSummaryInfo(_ s: Any?) { InfoWindow.showInspector(from: self) }
    @objc func compressItems(_ s: Any?) {
        guard !selection.isEmpty else { return }
        if selection.count == 1, selection[0].pathExtension == "zip" { FileOps.shared.uncompress(selection[0]); return }
        FileOps.shared.compress(selection) { [weak self] r in self?.load(); self?.selection = r; self?.itemView?.selectionChanged() }
    }
    @objc func duplicateItems(_ s: Any?) { let r = FileOps.shared.duplicate(selection); load(); selection = r; itemView?.selectionChanged(); itemView?.revealSelection() }
    @objc func makeAlias(_ s: Any?) { let r = FileOps.shared.makeAlias(selection); load(); selection = r; itemView?.selectionChanged() }
    @objc func showOriginal(_ s: Any?) {
        guard let n = nodesSel.first, n.isAlias, let t = Alias.resolve(n.url) else { NSSound.beep(); return }
        navigate(.folder(t.deletingLastPathComponent())); selection = [t]; itemView?.selectionChanged(); itemView?.revealSelection()
    }
    @objc func addToSidebar(_ s: Any?) { for n in nodesSel where n.isFolderLike || n.isVolume { sidebar.addFavorite(n.url) } }
    @objc func quickLookItems(_ s: Any?) { quickLook() }
    @objc func moveToTrash(_ s: Any?) { trashSelection() }
    @objc func putBackItems(_ s: Any?) { FileOps.shared.putBack(selection) }
    @objc func emptyTrash(_ s: Any?) { FileOps.shared.emptyTrash(skipWarning: NSEvent.modifierFlags.contains(.option)) }
    @objc func secureEmptyTrash(_ s: Any?) { FileOps.shared.secureEmptyTrash() }
    @objc func ejectItem(_ s: Any?) { if let u = selection.first { FileOps.shared.eject(u) } else if let d = currentDir, Files.isEjectable(d) { FileOps.shared.eject(d) } }
    @objc func burnItem(_ s: Any?) { if let d = currentDir ?? selection.first { FileOps.shared.burn(selection.first(where: { $0.pathExtension == Files.burnExt }) ?? d, window: win) } }
    @objc func findItem(_ s: Any?) { win.makeFirstResponder(chrome.search.field) }
    @objc func printItems(_ s: Any?) {   // F-19: über die zugeordnete Anwendung
        for u in selection { let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/bin/lpr"); t.arguments = [u.path]; try? t.run() }
    }
    @objc func changeLabel(_ s: NSMenuItem) { setLabel(s.tag) }
    func setLabel(_ i: Int) {
        for u in selection { Labels.set(i, for: u) }
        FileOps.shared.changed()
    }
    @objc func renameItem(_ s: Any?) { itemView?.startRename() }

    // MARK: Bearbeiten
    @objc func undo(_ s: Any?) { FileOps.shared.undoManager.undo(); reload() }
    @objc func redo(_ s: Any?) { FileOps.shared.undoManager.redo(); reload() }
    @objc func copy(_ s: Any?) {
        let pb = NSPasteboard.general; pb.clearContents()
        guard !selection.isEmpty else { return }
        pb.writeObjects(selection as [NSURL]); clipboardMove = false
        pb.setString(selection.map { $0.lastPathComponent }.joined(separator: "\n"), forType: .string)
    }
    @objc func paste(_ s: Any?) { pasteItems(move: false) }
    @objc func pasteMove(_ s: Any?) { pasteItems(move: true) }
    func pasteItems(move: Bool) {
        guard let d = currentDir, let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { NSSound.beep(); return }
        let finish: ([URL]) -> Void = { [weak self] r in self?.load(); self?.selection = r; self?.itemView?.selectionChanged(); self?.itemView?.revealSelection() }
        if Prefs.xMode && Prefs.xQueue { TransferQueue.shared.enqueue(urls, to: d, move: move, done: finish) } else { FileOps.shared.transfer(urls, to: d, move: move, done: finish) }
    }
    @objc func showClipboard(_ s: Any?) { ClipboardWindow.show() }

    // MARK: Darstellung
    @objc func viewAsIcons(_ s: Any?) { setMode(.icon) }
    @objc func viewAsList(_ s: Any?) { setMode(.list) }
    @objc func viewAsColumns(_ s: Any?) { setMode(.column) }
    @objc func viewAsCoverFlow(_ s: Any?) { setMode(.coverFlow) }
    @objc func toggleToolbar(_ s: Any?) { Prefs.showToolbar.toggle(); BrowserController.all.forEach { $0.layoutAll(); $0.chrome.relayout() } }
    @objc func toggleSidebar(_ s: Any?) { Prefs.showSidebar.toggle(); BrowserController.all.forEach { $0.layoutAll() } }
    @objc func toggleStatusBar(_ s: Any?) { Prefs.showStatus.toggle(); BrowserController.all.forEach { $0.layoutAll(); $0.updateStatus() } }
    @objc func togglePathBar(_ s: Any?) { Prefs.showPath.toggle(); BrowserController.all.forEach { $0.layoutAll(); $0.updatePathBar() } }
    @objc func customizeToolbar(_ s: Any?) { CustomizeSheet.show(from: self) }
    @objc func showViewOptions(_ s: Any?) { ViewOptionsPanel.shared.show(for: self) }
    @objc func cleanUp(_ s: Any?) { (itemView as? IconView)?.cleanUp() }
    @objc func cleanUpBy(_ s: NSMenuItem) { var o = options; o.arrange = "none"; o.userPositions = [:]; options = o; if let k = SortKey(rawValue: (s.representedObject as? String) ?? "name") { options.arrange = "none"; rawNodes = sorted(rawNodes, key: k, asc: true); nodes = rawNodes; groups = [Group(title: nil, nodes: nodes, total: nodes.count)]; itemView?.reload() } }
    @objc func arrangeBy(_ s: NSMenuItem) {
        guard let k = s.representedObject as? String else { return }
        var o = options; o.arrange = k; o.userPositions = [:]; o.snapToGrid = k == "grid" ? !o.snapToGrid : o.snapToGrid
        if k == "grid" { o.arrange = options.arrange; o.snapToGrid = !options.snapToGrid }
        options = o; viewStateChanged()
    }
    @objc func sortBy(_ s: NSMenuItem) {
        guard let k = s.representedObject as? String else { return }
        if options.sortKey == k { options.ascending.toggle() } else { options.sortKey = k; options.ascending = true }
        viewStateChanged()
    }

    // MARK: Gehe zu
    @objc func goBackAction(_ s: Any?) { goBack() }
    @objc func goForwardAction(_ s: Any?) { goForward() }
    @objc func goEnclosing(_ s: Any?) { goUp() }
    @objc func goInto(_ s: Any?) { openSelection() }
    @objc func goAllMyFiles(_ s: Any?) { navigate(.allMyFiles) }
    @objc func goDocuments(_ s: Any?) { navigate(.folder(Files.documents)) }
    @objc func goDesktop(_ s: Any?) { navigate(.folder(Files.desktop)) }
    @objc func goDownloads(_ s: Any?) { navigate(.folder(Files.downloads)) }
    @objc func goHome(_ s: Any?) { navigate(.folder(Files.home)) }
    @objc func goLibrary(_ s: Any?) { navigate(.folder(Files.library)) }
    @objc func goComputer(_ s: Any?) { navigate(.computer) }
    @objc func goAirDrop(_ s: Any?) { navigate(.airDrop) }
    @objc func goNetwork(_ s: Any?) { navigate(.network) }
    @objc func goApplications(_ s: Any?) { navigate(.folder(Files.applications)) }
    @objc func goUtilities(_ s: Any?) { navigate(.folder(Files.utilities)) }
    @objc func goRecent(_ s: NSMenuItem) { if let p = s.representedObject as? String { navigate(.folder(URL(fileURLWithPath: p))) } }
    @objc func goToFolder(_ s: Any?) { Dialogs.goToFolder(window: win) { [weak self] u in self?.navigate(.folder(u)) } }
    @objc func connectToServer(_ s: Any?) { Dialogs.connect(window: win, from: self) }
    @objc func openTrash(_ s: Any?) { navigate(.folder(Files.trash)) }

    // MARK: Fenster
    @objc func minimizeWin(_ s: Any?) { win.miniaturize(nil) }
    @objc func zoomWin(_ s: Any?) { chromeZoom() }
    @objc func cycleWindows(_ s: Any?) { let a = BrowserController.all.filter { !$0.win.isMiniaturized }; if let i = a.firstIndex(where: { $0 === self }), a.count > 1 { a[(i + 1) % a.count].win.makeKeyAndOrderFront(nil) } }

    // MARK: Menüs (Kontext, Aktion, Anordnen, Teilen)
    func contextMenu(for n: FileNode?) -> NSMenu { contextMenu(for: n, action: false) }
    func contextMenu(for n: FileNode?, action: Bool) -> NSMenu {
        let m = NSMenu(); m.autoenablesItems = false
        func add(_ t: String, _ sel: Selector, key: String = "", enabled: Bool = true, tag: Int = 0, obj: Any? = nil, to menu: NSMenu? = nil) {
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: key); i.target = self; i.isEnabled = enabled; i.tag = tag; i.representedObject = obj; (menu ?? m).addItem(i)
        }
        let sel = selectedNodes
        let isTrash = currentDir?.standardizedFileURL.path == Files.trash.path
        if sel.isEmpty {
            if currentDir != nil { add(L("Neuer Ordner", "New Folder"), #selector(newFolder(_:))); m.addItem(.separator()) }
            add(L("Informationen", "Get Info"), #selector(getInfo(_:)))
            add(L("Terminal hier öffnen", "Open Terminal Here"), #selector(terminalHere(_:)))
            m.addItem(.separator())
            add(L("Einsetzen", "Paste Item"), #selector(paste(_:)), enabled: currentDir != nil && NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]))
            if isTrash { m.addItem(.separator()); add(L("Papierkorb entleeren", "Empty Trash"), #selector(emptyTrash(_:)), enabled: !FileOps.trashIsEmpty) }
            m.addItem(.separator())
            add(L("Darstellungsoptionen einblenden", "Show View Options"), #selector(showViewOptions(_:)))
            if options.mode == .icon { let a = NSMenuItem(title: L("Anordnen nach", "Arrange By"), action: nil, keyEquivalent: ""); a.submenu = arrangeMenu(); m.addItem(a) }
            return m
        }
        let name = singleName
        let folderOnly = sel.count == 1 && sel[0].isFolderLike
        add(L("Öffnen", "Open"), #selector(openItem(_:)))
        if tabsOn, sel.allSatisfy({ $0.isFolderLike }) { add(L("In neuem Tab öffnen", "Open in New Tab"), #selector(openInNewTab(_:))) }
        if sel.count == 1, !sel[0].isFolderLike || sel[0].isPackage { m.addItem(withOpenWith()) }
        if sel.allSatisfy({ $0.isFolderLike }) { add(L("In neuem Fenster öffnen", "Open in New Window"), #selector(openItemInNewWindow(_:))) }
        if sel.count == 1, sel[0].isAlias { add(L("Original zeigen", "Show Original"), #selector(showOriginal(_:))) }
        if sel.count == 1, sel[0].isPackage { add(L("Paketinhalt zeigen", "Show Package Contents"), #selector(showPackageContents(_:))) }
        m.addItem(.separator())
        if isTrash { add(L("Zurücklegen", "Put Back"), #selector(putBackItems(_:))); m.addItem(.separator()) }
        else { add(L("\(name) in den Papierkorb legen", "Move \(name) to Trash"), #selector(moveToTrash(_:))); m.addItem(.separator()) }
        add(L("Informationen", "Get Info"), #selector(getInfo(_:)))
        if sel.count <= 1 { add(L("Terminal hier öffnen", "Open Terminal Here"), #selector(terminalHere(_:))) }
        if sel.contains(where: { $0.isDir }) { add(L("Größe berechnen", "Calculate Size"), #selector(calcFolderSizes(_:))) }
        if sel.count == 1 { add(L("Umbenennen", "Rename"), #selector(renameItem(_:))) }
        if Prefs.xMode && sel.count > 1 { add(L("\(sel.count) Objekte umbenennen …", "Rename \(sel.count) Items…"), #selector(batchRename(_:))) }
        if sel.count == 1, sel[0].url.pathExtension == "zip" { add(L("Entpacken", "Open Archive"), #selector(compressItems(_:))) }
        else { add(L("\(name) komprimieren", "Compress \(name)"), #selector(compressItems(_:))) }
        add(L("\(name) duplizieren", "Duplicate"), #selector(duplicateItems(_:)))
        add(L("Alias erstellen", "Make Alias"), #selector(makeAlias(_:)))
        add(L("\(name) übersicht", "Quick Look \(name)"), #selector(quickLookItems(_:)))
        if folderOnly && !isTrash { add(L("Zur Seitenleiste hinzufügen", "Add to Sidebar"), #selector(addToSidebar(_:))) }
        m.addItem(.separator())
        add(L("\(name) kopieren", "Copy \(name)"), #selector(copy(_:)))
        if sel.count == 1, sel[0].url.pathExtension == Files.burnExt { add(L("Brennen …", "Burn…"), #selector(burnItem(_:))) }
        if sel.count == 1, Files.isEjectable(sel[0].url) { add(L("Auswerfen", "Eject"), #selector(ejectItem(_:))) }
        if sel.count == 1, sel[0].url.scheme != "file" { add(L("Bildschirm teilen …", "Share Screen…"), #selector(shareScreen(_:))) }
        if sel.count == 1, sel[0].isVolume, !Files.isNetwork(sel[0].url) { add(L("„\(sel[0].name)“ verschlüsseln …", "Encrypt \u{201C}\(sel[0].name)\u{201D}…"), #selector(encryptVolume(_:))) }
        m.addItem(.separator())
        let lab = NSMenuItem(); lab.view = LabelRowView(target: self); m.addItem(lab)
        if action || true { m.addItem(.separator()); let sh = NSMenuItem(title: L("Teilen", "Share"), action: nil, keyEquivalent: ""); sh.submenu = shareMenu(); m.addItem(sh) }
        return m
    }
    func withOpenWith() -> NSMenuItem {
        let it = NSMenuItem(title: L("Öffnen mit", "Open With"), action: nil, keyEquivalent: ""); let sub = NSMenu(); it.submenu = sub
        guard let u = selection.first else { return it }
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: u)
        let def = NSWorkspace.shared.urlForApplication(toOpen: u)
        for a in apps.prefix(15) {
            let t = Files.displayName(a).replacingOccurrences(of: ".app", with: "") + (a == def ? L(" (Standard)", " (default)") : "")
            let i = NSMenuItem(title: t, action: #selector(openWithApp(_:)), keyEquivalent: ""); i.target = self; i.representedObject = a
            let ic = NSWorkspace.shared.icon(forFile: a.path); ic.size = NSSize(width: 16, height: 16); i.image = ic; sub.addItem(i)
            if a == def { sub.addItem(.separator()) }
        }
        sub.addItem(.separator())
        let o = NSMenuItem(title: L("Andere …", "Other…"), action: #selector(openWithOther(_:)), keyEquivalent: ""); o.target = self; sub.addItem(o)
        return it
    }
    /// X-06: Einstieg zur Bildschirmfreigabe (System-App)
    @objc func shareScreen(_ s: Any?) {
        guard let u = selection.first, let host = u.host else { return }
        if let v = URL(string: "vnc://\(host)") { NSWorkspace.shared.open(v) }
    }
    /// X-12: Einstieg zum Verschlüsseln (APFS/CoreStorage über diskutil). Kennwort läuft über stdin, nie über Argumente/Logs.
    @objc func encryptVolume(_ s: Any?) {
        guard let u = selection.first else { return }
        let a = NSAlert(); a.messageText = L("Möchten Sie „\(u.lastPathComponent)“ verschlüsseln?", "Do you want to encrypt \u{201C}\(u.lastPathComponent)\u{201D}?")
        a.informativeText = L("Legen Sie ein Kennwort fest. Merken Sie es sich gut – ohne Kennwort sind die Daten verloren.", "Choose a password. Remember it – without it the data can\u{2019}t be recovered.")
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 58))
        let p1 = NSSecureTextField(frame: NSRect(x: 0, y: 32, width: 260, height: 22)); p1.placeholderString = L("Kennwort", "Password")
        let p2 = NSSecureTextField(frame: NSRect(x: 0, y: 4, width: 260, height: 22)); p2.placeholderString = L("Bestätigen", "Verify")
        v.addSubview(p1); v.addSubview(p2); a.accessoryView = v
        a.addButton(withTitle: L("Verschlüsseln", "Encrypt")); a.addButton(withTitle: L("Abbrechen", "Cancel"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        guard !p1.stringValue.isEmpty, p1.stringValue == p2.stringValue else { FileOps.shared.alert(L("Die Kennwörter stimmen nicht überein.", "The passwords don\u{2019}t match.")); return }
        let pw = p1.stringValue
        DispatchQueue.global().async {
            let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil"); t.arguments = ["apfs", "encryptVolume", u.path, "-user", "disk", "-stdinpassphrase"]
            let inPipe = Pipe(), outPipe = Pipe(); t.standardInput = inPipe; t.standardOutput = outPipe; t.standardError = outPipe
            do { try t.run(); inPipe.fileHandleForWriting.write((pw + "\n").data(using: .utf8)!); try? inPipe.fileHandleForWriting.close(); t.waitUntilExit() } catch {}
            let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async { FileOps.shared.alert(t.terminationStatus == 0 ? L("Die Verschlüsselung wurde gestartet.", "Encryption has started.") : L("Das Volume konnte nicht verschlüsselt werden.", "The volume couldn\u{2019}t be encrypted."), out.prefix(300).description) }
        }
    }
    @objc func showPackageContents(_ s: Any?) { if let u = selection.first { navigate(.folder(u)) } }

    func arrangeMenu() -> NSMenu {
        let m = NSMenu(); m.autoenablesItems = false
        if options.mode == .icon {
            let g = NSMenuItem(title: L("Am Raster ausrichten", "Snap to Grid"), action: #selector(arrangeBy(_:)), keyEquivalent: ""); g.target = self; g.representedObject = "grid"; g.state = options.snapToGrid ? .on : .off; m.addItem(g); m.addItem(.separator())
            for k in SortKey.allCases where k != .none || true {
                let i = NSMenuItem(title: k.title, action: #selector(arrangeBy(_:)), keyEquivalent: ""); i.target = self; i.representedObject = k.rawValue; i.state = options.arrange == k.rawValue ? .on : .off; m.addItem(i)
            }
        } else {
            for k in SortKey.allCases where k != .none {
                let i = NSMenuItem(title: k.title, action: #selector(sortBy(_:)), keyEquivalent: ""); i.target = self; i.representedObject = k.rawValue; i.state = options.sortKey == k.rawValue ? .on : .off; m.addItem(i)
            }
        }
        return m
    }
    func shareMenu() -> NSMenu {
        let m = NSMenu(); m.autoenablesItems = false
        let items: [Any] = selection.isEmpty ? [] : selection as [Any]
        let services = items.isEmpty ? [] : NSSharingService.sharingServices(forItems: items)
        if services.isEmpty { let i = NSMenuItem(title: L("Keine Dienste verfügbar", "No services available"), action: nil, keyEquivalent: ""); i.isEnabled = false; m.addItem(i) }
        for s in services {
            let i = NSMenuItem(title: s.menuItemTitle, action: #selector(runShare(_:)), keyEquivalent: ""); i.target = self; i.representedObject = s; i.image = s.image; i.image?.size = NSSize(width: 16, height: 16); m.addItem(i)
        }
        return m
    }
    @objc func runShare(_ s: NSMenuItem) { (s.representedObject as? NSSharingService)?.perform(withItems: selection) }

    // MARK: Quick Look (S-10…S-12)
    func quickLook() {
        let p = QLPreviewPanel.shared()!
        if p.isVisible { p.orderOut(nil) } else { updateQuickLook(); p.makeKeyAndOrderFront(nil) }
    }
    func updateQuickLook() {
        quickLookURLs = selection
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible, (QLPreviewPanel.shared().currentController as AnyObject?) === self { QLPreviewPanel.shared().reloadData() }
    }
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self; panel.delegate = self; updateQuickLook() }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil; panel.delegate = nil }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { quickLookURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { quickLookURLs[index] as NSURL }
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown, [123, 124, 125, 126].contains(event.keyCode), selection.count <= 1 {
            // Pfeile bewegen die Auswahl im Fenster, Vorschau folgt
            win.makeFirstResponder(itemView); itemView?.keyDown(with: event); return true
        }
        return false
    }

    // MARK: Teilen aus der Auswahl heraus + Suche
    static func startLocation() -> Location {
        switch Prefs.newWindowTarget {
        case "allfiles": return .allMyFiles
        case "computer": return .computer
        case "home": return .folder(Files.home)
        case let s where s.hasPrefix("path:"): return .folder(URL(fileURLWithPath: String(s.dropFirst(5))))
        default: return .folder(Files.home)
        }
    }

    var inSearch: Bool { if case .search = location { return true }; return false }
    func showSearchBar(_ spec: SearchSpec) {
        searchBar.isHidden = false
        searchBar.folderName = preSearchFolder.map { Files.displayName($0) } ?? spec.folderURL.map { Files.displayName($0) }
        searchBar.folderPath = preSearchFolder?.path ?? spec.folderURL?.path
        searchBar.spec = spec; layoutAll()
    }
    func endSearchSilently() { searchEngine?.stop(); searchEngine = nil; if !searchBar.isHidden { searchBar.isHidden = true; searchBar.showCriteria = false; layoutAll() } }

    func searchTyped(_ t: String) {
        var spec: SearchSpec
        if case .search(let s) = location { spec = s }
        else {
            if t.isEmpty { return }
            spec = SearchSpec()
            switch Prefs.searchScope {
            case "folder": if let d = currentDir { spec.scope = "folder:" + d.path }
            case "previous": spec.scope = UserDefaults.standard.string(forKey: "lastScope") ?? "this"
            default: break
            }
            preSearchLocation = location; preSearchFolder = currentDir
            if spec.scope == "this", let d = currentDir, Prefs.searchScope == "this" { _ = d }
        }
        spec.text = t
        if t.isEmpty && spec.criteria.isEmpty && spec.saved == nil { endSearch(); return }
        applySearch(spec)
    }
    func applySearch(_ spec: SearchSpec) {
        if inSearch {
            history[hIndex] = .search(spec); location = .search(spec)
            searchSpec = spec; startSearch(spec, live: true); chrome.needsDisplay = true
            showSearchBarKeepRows(spec)
        } else { go(.search(spec), record: true) }
        UserDefaults.standard.set(spec.scope, forKey: "lastScope")
    }
    func showSearchBarKeepRows(_ spec: SearchSpec) { searchBar.isHidden = false; if searchBar.spec != spec { searchBar.spec = spec }; layoutAll() }
    func endSearch() {
        guard inSearch else { return }
        chrome.search.text = ""
        let target = preSearchLocation ?? .folder(Files.home)
        preSearchLocation = nil
        go(target, record: true)
    }
    func searchSpecChanged() {
        var s = searchBar.spec; s.text = chrome.search.text
        if s.saved != nil { s.saved = searchSpec.saved }
        applySearch(s)
    }
    func saveSearch() {
        var s = searchBar.spec; s.text = chrome.search.text
        let a = NSAlert(); a.messageText = L("Intelligenten Ordner sichern", "Save Smart Folder"); a.informativeText = L("Geben Sie einen Namen für die gespeicherte Suche ein.", "Enter a name for the saved search.")
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 52))
        let f = NSTextField(frame: NSRect(x: 0, y: 28, width: 300, height: 22)); f.stringValue = s.saved != nil ? s.name : (s.text.isEmpty ? L("Neue Suche", "New Search") : s.text)
        let c = NSButton(checkboxWithTitle: L("Zur Seitenleiste hinzufügen", "Add To Sidebar"), target: nil, action: nil); c.frame = NSRect(x: 0, y: 0, width: 300, height: 20); c.state = .on
        v.addSubview(f); v.addSubview(c); a.accessoryView = v
        a.addButton(withTitle: L("Sichern", "Save")); a.addButton(withTitle: L("Abbrechen", "Cancel"))
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let name = f.stringValue.isEmpty ? L("Neue Suche", "New Search") : f.stringValue
        if s.saved != nil { s.name = name; SavedSearches.update(s); searchSpec = s; reload(); return }
        if let u = SavedSearches.save(s, name: name) {
            if c.state == .on { var l = UserDefaults.standard.stringArray(forKey: "sideSaved") ?? []; l.append(u.path); UserDefaults.standard.set(l, forKey: "sideSaved") }
            sidebar.reload()
            if let loaded = SavedSearches.load(u) { chrome.search.text = loaded.text; go(.search(loaded), record: true) }
        }
    }

    // MARK: Validierung
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let a = item.action
        let hasSel = !selection.isEmpty
        switch a {
        case #selector(newFolder(_:)), #selector(newBurnFolder(_:)): return currentDir != nil
        case #selector(newFolderWithSelection(_:)): return hasSel && currentDir != nil
        case #selector(openItem(_:)), #selector(getInfo(_:)), #selector(quickLookItems(_:)), #selector(duplicateItems(_:)), #selector(makeAlias(_:)), #selector(renameItem(_:)), #selector(printItems(_:)):
            if a == #selector(getInfo(_:)) { return hasSel || currentDir != nil }
            if a == #selector(getInfo(_:)) { item.title = L("Informationen", "Get Info") }
            return hasSel
        case #selector(compressItems(_:)):
            if hasSel { item.title = selection.count == 1 && selection[0].pathExtension == "zip" ? L("Archiv öffnen", "Open Archive") : L("\(singleName) komprimieren", "Compress \(singleName)") } else { item.title = L("Komprimieren", "Compress") }; return hasSel
        case #selector(moveToTrash(_:)):
            if hasSel { item.title = L("\(singleName) in den Papierkorb legen", "Move \(singleName) to Trash") }; return hasSel && currentDir?.standardizedFileURL.path != Files.trash.path
        case #selector(putBackItems(_:)): return hasSel && currentDir?.standardizedFileURL.path == Files.trash.path
        case #selector(emptyTrash(_:)), #selector(secureEmptyTrash(_:)): return !FileOps.trashIsEmpty
        case #selector(showOriginal(_:)): return selectedNodes.count == 1 && selectedNodes[0].isAlias
        case #selector(ejectItem(_:)): return (selection.count == 1 && Files.isEjectable(selection[0])) || (currentDir.map { Files.isEjectable($0) } ?? false)
        case #selector(burnItem(_:)): return currentDir?.pathExtension == Files.burnExt || selection.contains { $0.pathExtension == Files.burnExt }
        case #selector(addToSidebar(_:)): return selectedNodes.contains { $0.isFolderLike || $0.isVolume }
        case #selector(copy(_:)): return hasSel
        case #selector(paste(_:)), #selector(pasteMove(_:)): return currentDir != nil && NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        case #selector(undo(_:)): let u = FileOps.shared.undoManager; item.title = u.canUndo ? (Lang.de ? "Widerrufen " : "Undo ") + u.undoActionName.replacingOccurrences(of: "Undo ", with: "") : L("Widerrufen", "Undo"); return u.canUndo
        case #selector(redo(_:)): let u = FileOps.shared.undoManager; item.title = u.canRedo ? (Lang.de ? "Wiederholen " : "Redo ") + u.redoActionName : L("Wiederholen", "Redo"); return u.canRedo
        case #selector(viewAsIcons(_:)): item.state = options.mode == .icon ? .on : .off; return true
        case #selector(viewAsList(_:)): item.state = options.mode == .list ? .on : .off; return true
        case #selector(viewAsColumns(_:)): item.state = options.mode == .column ? .on : .off; return true
        case #selector(viewAsCoverFlow(_:)): item.state = options.mode == .coverFlow ? .on : .off; return true
        case #selector(toggleToolbar(_:)): item.title = Prefs.showToolbar ? L("Symbolleiste ausblenden", "Hide Toolbar") : L("Symbolleiste einblenden", "Show Toolbar"); return true
        case #selector(toggleSidebar(_:)): item.title = Prefs.showSidebar ? L("Seitenleiste ausblenden", "Hide Sidebar") : L("Seitenleiste einblenden", "Show Sidebar"); return true
        case #selector(toggleStatusBar(_:)): item.title = Prefs.showStatus ? L("Statusleiste ausblenden", "Hide Status Bar") : L("Statusleiste einblenden", "Show Status Bar"); return true
        case #selector(togglePathBar(_:)): item.title = Prefs.showPath ? L("Pfadleiste ausblenden", "Hide Path Bar") : L("Pfadleiste einblenden", "Show Path Bar"); return true
        case #selector(cleanUp(_:)): return options.mode == .icon
        case #selector(goBackAction(_:)): return canGoBack
        case #selector(goForwardAction(_:)): return canGoForward
        case #selector(goEnclosing(_:)): return currentDir != nil
        case #selector(arrangeBy(_:)), #selector(sortBy(_:)): return true
        case #selector(newSmartFolder(_:)), #selector(showViewOptions(_:)): return true
        case #selector(terminalHere(_:)), #selector(copyPath(_:)): return true
        case #selector(toggleFavorite(_:)): item.title = focus.currentIsFavorite ? L("Aktuellen Ordner aus Favoriten entfernen", "Remove Current Folder from Favorites") : L("Aktuellen Ordner zu Favoriten", "Add Current Folder to Favorites"); return focus.currentDir != nil
        case #selector(showFavorites(_:)), #selector(manageFavorites(_:)): return true
        case #selector(showHistory(_:)): return !focus.visited.isEmpty
        case #selector(calcFolderSizes(_:)): return nodes.contains { $0.isDir }
        case #selector(batchRename(_:)): return !focus.selection.isEmpty
        case #selector(showQueue(_:)): return true
        case #selector(reopenTab(_:)): return gastgeber.tabsOn && !gastgeber.closedTabs.isEmpty
        case #selector(jumpToTab(_:)): return gastgeber.tabsOn && gastgeber.tabs.count > 1
        case #selector(mirrorPane(_:)), #selector(swapPanes(_:)): return gastgeber.dualOn
        case #selector(showPackageContents(_:)): return selectedNodes.count == 1 && selectedNodes[0].isPackage
        case #selector(closeWin(_:)), #selector(minimizeWin(_:)), #selector(zoomWin(_:)): return true
        default: return true
        }
    }
}
