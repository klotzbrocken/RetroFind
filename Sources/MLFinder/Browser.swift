import AppKit
import QuickLookUI
import UniformTypeIdentifiers

/// Ein Finder-Fenster: Zustand, Navigation, Laden, Auswahl (N-01…N-16, A-07).
final class BrowserController: NSWindowController, ChromeDelegate, BrowserHost, SidebarHost, NSWindowDelegate, NSMenuItemValidation, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static var all: [BrowserController] = []
    let ownWin: FinderWindow
    weak var hostWin: FinderWindow?                      // eingebettete Hälfte (Dual Pane): Fenster des Gastgebers
    var win: FinderWindow { hostWin ?? ownWin }
    weak var hostPane: BrowserController?
    var rightPane: BrowserController?
    var activeIsRight = false
    struct TabState { var history: [Location]; var hIndex: Int; var selection: [URL] }
    var tabs: [TabState] = [TabState(history: [], hIndex: -1, selection: [])]
    var tabIdx = 0
    var closedTabs: [TabState] = []
    var visited: [Location] = []                 // Verlauf der Hälfte (zuletzt besuchte Orte, ohne Doppelte)
    var sizeBatch: SizeService.Batch?
    var sizeBusy = false
    let fbar = FKeyBar()
    let strip = PaneStrip()
    let divider = PaneDivider()
    let root = RootView()
    let chrome = ChromeBar()
    let sidebar = SidebarView(frame: .zero)
    let status = StatusBarView()
    let pathBar = PathBarView()
    let searchBar = SearchBarView()
    let sidebarLine = LineView()
    var itemView: (NSView & ItemView)?
    var scroll: NSScrollView?
    let errorLabel = NSTextField(labelWithString: "")
    var contentView_: NSView = NSView()

    var location: Location = .folder(Files.home)
    var history: [Location] = []; var hIndex = -1
    var rawNodes: [FileNode] = []
    var nodes: [FileNode] = []
    var groups: [Group] = []
    var expandedGroups: Set<String> = []
    var selection: [URL] = [] { didSet { selectionDidChange() } }
    var suppressSave = false
    var options = ViewOptions() { didSet { if !suppressSave && options != oldValue { ViewStore.save(options, for: location) } } }
    var searchEngine: SearchEngine?
    var searchSpec = SearchSpec()
    var gathering = false
    var watcher: DispatchSourceFileSystemObject?
    var reloadWork: DispatchWorkItem?
    var sidebarW: CGFloat = UserDefaults.standard.object(forKey: "sidebarW") as? CGFloat ?? M.sidebarW
    var loadError: String?
    var infoWindows: [InfoWindow] = []
    var clipboardMove = false
    var quickLookURLs: [URL] = []
    var desktopMode = false
    var preSearchLocation: Location?
    var preSearchFolder: URL?

    var isActive: Bool { win.isKeyWindow || win.isMainWindow || (QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible) }
    var currentDir: URL? { if case .folder(let u) = location { return u }; return nil }
    var canGoBack: Bool { let f = focus; return f === self ? hIndex > 0 : f.canGoBack }
    var canGoForward: Bool { let f = focus; return f === self ? hIndex < history.count - 1 : f.canGoForward }
    var viewModeIndex: Int { let f = focus; return f === self ? options.mode.rawValue : f.viewModeIndex }
    var titleText: String { let f = focus; return f === self ? location.title : f.titleText }
    var titleIcon: NSImage? {
        if focus !== self { return focus.titleIcon }
        switch location {
        case .folder(let u): let g = Files.glyph(for: u); return IconCache.shared.folderImage(g == .home || g == .hardDisk ? .folder : g, size: 16)
        case .search: return IconCache.shared.smartFolder(16)
        default: return NSImage(size: NSSize(width: 16, height: 16), flipped: true) { r in self.location.glyph.draw(in: r, selected: false); return true }
        }
    }
    var titleURL: URL? { focus === self ? currentDir : focus.currentDir }

    // MARK: Aufbau
    init(location loc: Location, size: NSSize = M.defaultSize, cascadeFrom: BrowserController? = nil, showWindow: Bool = true) {
        ownWin = FinderWindow(size: size)
        super.init(window: ownWin)
        ownWin.delegate = self; ownWin.windowController = self
        ownWin.contentView = root
        win.minSize = M.minSize
        win.contentMinSize = win.minSize
        chrome.delegate = self; sidebar.host = self
        root.addSubview(sidebar); root.addSubview(contentView_); root.addSubview(pathBar); root.addSubview(status); root.addSubview(searchBar); root.addSubview(sidebarLine); root.addSubview(fbar); root.addSubview(strip); root.addSubview(divider); root.addSubview(chrome); strip.isHidden = true; divider.isHidden = true
        contentView_.wantsLayer = false
        errorLabel.font = lucida(12); errorLabel.textColor = NSColor(gray: 110); errorLabel.alignment = .center; errorLabel.isHidden = true; errorLabel.maximumNumberOfLines = 3
        contentView_.addSubview(errorLabel)
        searchBar.isHidden = true
        sidebarLine.onDrag = { [weak self] x in guard let s = self else { return }; s.sidebarW = max(105, min(300, x.rounded())); UserDefaults.standard.set(s.sidebarW, forKey: "sidebarW"); s.layoutAll(); s.sidebar.needsDisplay = true; s.win.invalidateCursorRects(for: s.sidebarLine) }
        pathBar.onNavigate = { [weak self] u in self?.navigate(.folder(u)) }
        pathBar.dropOp = { [weak self] urls, dir in self?.dragOperation(urls, into: dir, flags: NSEvent.modifierFlags) ?? [] }
        pathBar.onDrop = { [weak self] urls, dir in self?.performDrop(urls, into: dir, flags: NSEvent.modifierFlags) ?? false }
        status.onSlider = { [weak self] v in guard let s = self else { return }; s.options.iconSize = v; s.itemView?.applyOptions() }
        chrome.search.onChange = { [weak self] t in self?.searchTyped(t) }
        chrome.search.onCommit = { [weak self] t in self?.searchTyped(t) }
        chrome.search.onEscape = { [weak self] in self?.endSearch() }
        searchBar.onChange = { [weak self] in self?.searchSpecChanged() }
        searchBar.onSave = { [weak self] in self?.saveSearch() }
        root.onLayout = { [weak self] in self?.layoutAll() }
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(fsEvent), name: .fsChanged, object: nil)
        nc.addObserver(self, selector: #selector(sizesUpdated), name: .sizeReady, object: nil)
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: win, queue: .main) { [weak self] _ in self?.activeChanged() }
        nc.addObserver(forName: NSWindow.didResignKeyNotification, object: win, queue: .main) { [weak self] _ in self?.activeChanged() }
        nc.addObserver(forName: NSWindow.didResignMainNotification, object: win, queue: .main) { [weak self] _ in self?.activeChanged() }
        nc.addObserver(forName: NSWindow.didBecomeMainNotification, object: win, queue: .main) { [weak self] _ in self?.activeChanged() }
        if showWindow { BrowserController.all.append(self); ownWin.onMouseDown = { [weak self] e in self?.routeMouse(e) }; ownWin.onKeyEquivalent = { [weak self] e in self?.handleDualKey(e) ?? false } }
        fbar.onKey = { [weak self] k in self?.dualKey(k) }
        go(loc, record: true)
        if let c = cascadeFrom { let f = c.win.frame; win.setFrameTopLeftPoint(NSPoint(x: f.minX + 22, y: f.maxY - 22)); ensureVisible() }
        else if !restoreFrame() { win.center() }
        win.setFrameAutosaveName("")
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { watcher?.cancel() }

    func ensureVisible() {
        var f = win.frame; f.size.width = max(f.width, win.minSize.width); f.size.height = max(f.height, win.minSize.height)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(f.insetBy(dx: 40, dy: 40)) }) { win.setFrame(f, display: false); win.center() } else { win.setFrame(f, display: false) }
    }
    func restoreFrame() -> Bool {
        guard let s = UserDefaults.standard.string(forKey: "lastFrame") else { return false }
        let r = NSRectFromString(s); if r.width < M.minSize.width { return false }
        let off = CGFloat(BrowserController.all.count - 1) * 22
        win.setFrame(NSRect(x: r.minX + off, y: r.minY - off, width: r.width, height: r.height), display: false); ensureVisible(); return true
    }

    // MARK: Layout (Maße aus Messkatalog)
    var paneMode: Bool { hostPane != nil }
    var dualOn: Bool { rightPane != nil }
    var tabsOn: Bool { Prefs.xMode && Prefs.xTabs && !paneMode }
    var tabRowH: CGFloat { tabsOn ? 10 : 0 }
    var chromeH: CGFloat { paneMode ? 0 : (Prefs.showToolbar ? M.chromeH : 23) + tabRowH }
    var bottomBars: CGFloat { (Prefs.showStatus ? M.statusH : 0) + (Prefs.showPath ? M.pathH : 0) + (dualOn ? M.fbarH : 0) }
    func layoutAll() {
        let b = root.bounds
        if paneMode { layoutPane(b); return }
        let sbW = Prefs.showSidebar ? sidebarW : 0
        win.titleZoneH = 23 + tabRowH
        chrome.extraTop = tabRowH; chrome.showTabs = tabsOn; chrome.aqua = Prefs.aquaLights
        chrome.showToolbar = Prefs.showToolbar
        chrome.sidebarW = sbW
        chrome.frame = NSRect(x: 0, y: 0, width: b.width, height: chromeH)
        let fb = dualOn ? M.fbarH : 0
        fbar.isHidden = !dualOn; fbar.frame = NSRect(x: 0, y: b.height - M.fbarH, width: b.width, height: M.fbarH)
        let showStatus = Prefs.showStatus || dualOn
        let statusH = showStatus ? M.statusH : 0, pathH = Prefs.showPath ? M.pathH : 0
        let cx = sbW + (Prefs.showSidebar ? 1 : 0)
        let regionW = b.width - cx
        let dw: CGFloat = dualOn ? 5 : 0
        let leftW = dualOn ? floor((regionW - dw) / 2) : regionW
        let bottom = b.height - fb                                     // untere Kante des Arbeitsbereichs
        let stripH: CGFloat = dualOn ? M.stripH : 0
        // Statusleiste und Pfadleiste (Breadcrumbs) unten, je Hälfte bzw. über die ganze Breite
        status.isHidden = !showStatus; status.frame = NSRect(x: dualOn ? cx : 0, y: bottom - statusH, width: dualOn ? leftW : b.width, height: M.statusH)
        pathBar.isHidden = !Prefs.showPath
        pathBar.frame = NSRect(x: dualOn ? cx : 0, y: bottom - statusH - pathH, width: dualOn ? leftW : b.width, height: M.pathH)
        let contentBottom = bottom - statusH - pathH
        let sideBottom = dualOn ? bottom : contentBottom
        sidebar.isHidden = !Prefs.showSidebar; sidebarLine.isHidden = !Prefs.showSidebar
        sidebar.frame = NSRect(x: 0, y: chromeH, width: sbW, height: max(0, sideBottom - chromeH))
        sidebarLine.frame = NSRect(x: sbW - 3, y: chromeH, width: 7, height: sidebar.frame.height)
        var top = chromeH + stripH
        strip.isHidden = !dualOn; strip.frame = NSRect(x: cx, y: chromeH, width: leftW, height: stripH)
        if !searchBar.isHidden { let sh = searchBar.preferredHeight; searchBar.frame = NSRect(x: cx, y: top, width: leftW, height: sh); top += sh }
        contentView_.frame = NSRect(x: cx, y: top, width: leftW, height: max(0, contentBottom - top))
        scroll?.frame = contentView_.bounds; if scroll == nil { itemView?.frame = contentView_.bounds }
        errorLabel.frame = NSRect(x: 20, y: contentView_.bounds.midY - 24, width: contentView_.bounds.width - 40, height: 48)
        if let v = itemView as? IconView, scroll != nil { v.relayout() }
        divider.isHidden = !dualOn; divider.frame = NSRect(x: cx + leftW, y: chromeH, width: dw, height: max(0, bottom - chromeH))
        if let rp = rightPane {
            rp.root.frame = NSRect(x: cx + leftW + dw, y: chromeH, width: regionW - leftW - dw, height: max(0, bottom - chromeH))
            rp.root.needsLayout = true
        }
        strip.active = dualOn && !activeIsRight; rightPane?.strip.active = dualOn && activeIsRight
        root.needsDisplay = true
    }
    /// Eingebettete Fensterhälfte: Streifen oben, Inhalt, Pfadleiste (optional) und Statusleiste unten – ohne Toolbar und Seitenleiste.
    func layoutPane(_ b: NSRect) {
        chrome.isHidden = true; sidebar.isHidden = true; sidebarLine.isHidden = true; fbar.isHidden = true; divider.isHidden = true
        let pathH = Prefs.showPath ? M.pathH : 0
        strip.isHidden = false; strip.frame = NSRect(x: 0, y: 0, width: b.width, height: M.stripH)
        status.isHidden = false; status.frame = NSRect(x: 0, y: b.height - M.statusH, width: b.width, height: M.statusH)
        pathBar.isHidden = !Prefs.showPath; pathBar.frame = NSRect(x: 0, y: b.height - M.statusH - pathH, width: b.width, height: M.pathH)
        if !searchBar.isHidden { searchBar.isHidden = true }
        contentView_.frame = NSRect(x: 0, y: M.stripH, width: b.width, height: max(0, b.height - M.statusH - pathH - M.stripH))
        scroll?.frame = contentView_.bounds; if scroll == nil { itemView?.frame = contentView_.bounds }
        errorLabel.frame = NSRect(x: 20, y: contentView_.bounds.midY - 24, width: contentView_.bounds.width - 40, height: 48)
        if let v = itemView as? IconView, scroll != nil { v.relayout() }
        root.needsDisplay = true
    }

    // MARK: Navigation (N-03)
    func go(_ loc: Location, record: Bool) {
        if record {
            if hIndex < history.count - 1 { history.removeSubrange((hIndex + 1)...) }
            if history.last != loc { history.append(loc) }
            hIndex = history.count - 1
        }
        if case .search(let sp) = loc {
            if sp.saved != nil { chrome.search.text = sp.text }
        } else { endSearchSilently(); if !chrome.search.text.isEmpty { chrome.search.text = "" }; preSearchLocation = nil; preSearchFolder = nil }
        location = loc
        if case .folder(let u) = loc { Prefs.noteRecent(u) }
        noteVisited(loc)
        refreshFavoriteState()
        suppressSave = true                                                         // Laden/Vererben ändert nichts am gespeicherten Zustand
        options = ViewStore.options(for: loc)                                       // global → eigene → vom Elternordner geerbt → Standard
        if let f = options.forcedMode, let m = ViewMode(rawValue: f) { options.mode = m }   // A-10: erzwungene Öffnungsansicht
        if case .airDrop = loc { options.mode = .icon }
        suppressSave = false
        sizeBatch?.cancelled = true; sizeBusy = false
        selection = []
        expandedGroups = []
        buildItemView()
        persistTabs()
        if case .search(let sp) = loc { showSearchBar(sp) }
        load()
        chrome.needsDisplay = true; sidebar.needsDisplay = true; updatePathBar(); win.title = location.title
        NotificationCenter.default.post(name: .locationChanged, object: self)
    }
    func navigate(_ loc: Location) { if loc != location { go(loc, record: true) } else { reload() } }
    func goBack() { if canGoBack { hIndex -= 1; go(history[hIndex], record: false) } }
    func goForward() { if canGoForward { hIndex += 1; go(history[hIndex], record: false) } }
    func goUp() {
        guard case .folder(let u) = location else { return }
        let p = u.deletingLastPathComponent()
        if u.path == "/" { navigate(.computer) } else if u.standardizedFileURL.path != p.standardizedFileURL.path { go(.folder(p), record: true); selection = [u] ; itemView?.selectionChanged(); itemView?.revealSelection() }
    }
    func sidebarNavigate(_ loc: Location, newWindow: Bool) {
        if focus !== self { focus.sidebarNavigate(loc, newWindow: newWindow); return }
        if newWindow && tabsOn { newTab(loc); return }
        if newWindow { BrowserController.open(loc, from: self) } else { navigate(loc) }
    }
    func sidebarInfo(_ url: URL) { InfoWindow.show([url], from: self) }
    func sidebarDrop(_ urls: [URL], to dir: URL, flags: NSEvent.ModifierFlags) { _ = performDrop(urls, into: dir, flags: flags) }

    static func open(_ loc: Location, from: BrowserController? = nil, size: NSSize? = nil) {
        let c = BrowserController(location: loc, size: size ?? from?.win.frame.size ?? M.defaultSize, cascadeFrom: from)
        c.win.makeKeyAndOrderFront(nil)
    }

    // MARK: Laden
    @objc func fsEvent() { scheduleReload() }
    func scheduleReload() {
        reloadWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.reload() }
        reloadWork = w; DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
    }
    func reload() {
        if searchEngine == nil { load(keepSelection: true) }
        sidebar.reload()
    }

    func load(keepSelection: Bool = false) {
        watcher?.cancel(); watcher = nil
        loadError = nil; gathering = false
        searchEngine?.stop(); searchEngine = nil
        switch location {
        case .folder(let u):
            if !Files.exists(u) { folderVanished(u); return }
            watch(u)
            do {
                let kids = try Files.list(u)
                rawNodes = kids.map { FileNode(url: $0) }
                if desktopMode { rawNodes += Files.volumes().filter { v in (v.path == "/" && Prefs.bool("deskHD", true)) || (v.path != "/" && Files.isNetwork(v) && Prefs.bool("deskSrv", true)) || (v.path != "/" && !Files.isNetwork(v) && Prefs.bool(Files.isEjectable(v) ? "deskOpt" : "deskExt", false)) }.map { FileNode(url: $0) } }
            } catch {
                rawNodes = []; loadError = (error as NSError).code == NSFileReadNoPermissionError || (error as NSError).code == 257 ? L("Sie haben keine Berechtigung, den Inhalt dieses Ordners zu sehen.", "You do not have permission to see the contents of this folder.") : error.localizedDescription
            }
        case .computer:
            rawNodes = Files.volumes().map { let n = FileNode(url: $0); return n }
        case .network:
            rawNodes = networkNodes()
        case .airDrop:
            rawNodes = []
        case .allMyFiles:
            var s = SearchSpec(); s.allFiles = true; startSearch(s, live: true); return
        case .search(let spec):
            searchSpec = spec; startSearch(spec, live: true); return
        }
        arrangeAndShow(keepSelection: keepSelection)
    }
    func watch(_ u: URL) {
        let fd = Darwin.open(u.path, O_EVTONLY); guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend, .attrib, .link], queue: .main)
        src.setEventHandler { [weak self] in
            guard let s = self else { return }
            let flags = src.data
            if flags.contains(.delete) || flags.contains(.rename) { s.scheduleReload() } else { s.scheduleReload() }
        }
        src.setCancelHandler { Darwin.close(fd) }
        src.resume(); watcher = src
    }
    /// N-16: Ziel gelöscht/umbenannt → nächsten vorhandenen übergeordneten Ordner anzeigen
    func folderVanished(_ u: URL) {
        var p = u.deletingLastPathComponent()
        while !Files.exists(p) && p.path != "/" { p = p.deletingLastPathComponent() }
        history = history.map { $0 == .folder(u) ? .folder(p) : $0 }
        location = .folder(p); load()
        chrome.needsDisplay = true; sidebar.needsDisplay = true
    }
    func networkNodes() -> [FileNode] {
        var out: [FileNode] = []
        for s in ServerBrowser.shared.servers {
            let n = FileNode(url: URL(string: "\(s.scheme)://\(s.host)")!); n.name = s.name; n.isDir = true; n.kind = L("Server", "Server"); n.size = -1; out.append(n)
        }
        for v in Files.volumes() where Files.isNetwork(v) { out.append(FileNode(url: v)) }
        return out
    }

    func startSearch(_ spec: SearchSpec, live: Bool) {
        gathering = true
        let eng = SearchEngine(spec: spec)
        eng.onUpdate = { [weak self] ns, fin in
            guard let s = self else { return }
            s.rawNodes = ns; s.gathering = !fin
            s.arrangeAndShow(keepSelection: true)
        }
        searchEngine = eng
        rawNodes = []; arrangeAndShow(keepSelection: true)
        eng.start()
    }

    // MARK: Anordnen/Gruppieren (A-08, A-09)
    func sorted(_ a: [FileNode], key: SortKey, asc: Bool) -> [FileNode] {
        let s = a.sorted { key.less($0, $1) }
        let r = asc ? s : s.reversed()
        if Prefs.foldersFirst { return r.filter { $0.isFolderLike || $0.isVolume } + r.filter { !($0.isFolderLike || $0.isVolume) } }   // X-Modus: Ordner immer oben
        return r
    }
    func arrangeAndShow(keepSelection: Bool = false) {
        let key = SortKey(rawValue: options.mode == .icon ? (options.arrange == "grid" ? "name" : options.arrange) : options.sortKey) ?? .name
        var list = sorted(rawNodes, key: key == .none ? .name : key, asc: options.mode == .icon ? true : options.ascending)
        if case .allMyFiles = location { list = sorted(rawNodes, key: .modified, asc: true) }
        nodes = list
        groups = computeGroups(list)
        if keepSelection { let existing = Set(allVisibleURLs()); selection = selection.filter { existing.contains($0) } } else { selection = [] }
        errorLabel.stringValue = loadError ?? ""; errorLabel.isHidden = loadError == nil
        if case .search = location, nodes.isEmpty, !gathering { errorLabel.stringValue = L("Keine Ergebnisse", "No results"); errorLabel.isHidden = false }
        itemView?.reload()
        updateStatus(); chrome.needsDisplay = true
    }
    func allVisibleURLs() -> [URL] { var r: [URL] = []; func walk(_ n: [FileNode]) { for x in n { r.append(x.url); if let c = x.children { walk(c) } } }; walk(nodes); return r }

    func computeGroups(_ list: [FileNode]) -> [Group] {
        if case .allMyFiles = location {
            var buckets: [String: [FileNode]] = [:]; var order: [String] = []
            let names = [L("Bilder", "Images"), L("PDF-Dokumente", "PDF Documents"), L("Filme", "Movies"), L("Musik", "Music"), L("Präsentationen", "Presentations"), L("Dokumente", "Documents"), L("Andere", "Other")]
            for n in list { let c = BrowserController.category(n); buckets[names[c], default: []].append(n) }
            for nm in names where buckets[nm] != nil { order.append(nm) }
            return order.map { Group(title: $0, nodes: buckets[$0]!, total: buckets[$0]!.count) }
        }
        guard options.mode == .icon, let key = SortKey(rawValue: options.arrange), key != .none, key != .name else { return [Group(title: nil, nodes: list, total: list.count)] }
        var out: [(String, [FileNode])] = []
        func add(_ t: String, _ n: FileNode) { if let i = out.firstIndex(where: { $0.0 == t }) { out[i].1.append(n) } else { out.append((t, [n])) } }
        let cal = Calendar.current, now = Date()
        func bucket(_ d: Date?) -> String {
            guard let d else { return L("Unbekannt", "Unknown") }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: now)).day ?? 0
            if days <= 0 { return L("Heute", "Today") }; if days == 1 { return L("Gestern", "Yesterday") }
            if days <= 7 { return L("Letzte 7 Tage", "Previous 7 Days") }; if days <= 30 { return L("Letzte 30 Tage", "Previous 30 Days") }
            let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: d)
        }
        for n in list {
            switch key {
            case .kind: add(n.displayKind.isEmpty ? L("Andere", "Other") : n.displayKind, n)
            case .opened: add(bucket(n.opened), n); case .added: add(bucket(n.added), n)
            case .modified: add(bucket(n.modified), n); case .created: add(bucket(n.created), n)
            case .size:
                let s = n.size
                add(s < 0 ? L("Ordner", "Folders") : s == 0 ? L("Null Byte", "Zero bytes") : s < 10_000 ? L("100 Byte bis 10 KB", "100 bytes to 10 KB") : s < 1_000_000 ? L("10 KB bis 1 MB", "10 KB to 1 MB") : s < 100_000_000 ? L("1 MB bis 100 MB", "1 MB to 100 MB") : L("Über 100 MB", "Over 100 MB"), n)
            case .label: add(n.label == 0 ? L("Kein Etikett", "No Label") : Labels.name(n.label), n)
            default: break
            }
        }
        return out.map { Group(title: $0.0, nodes: $0.1, total: $0.1.count) }
    }
    static func category(_ n: FileNode) -> Int {
        guard let ut = try? n.url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return 6 }
        if ut.conforms(to: .image) { return 0 }; if ut.conforms(to: .pdf) { return 1 }; if ut.conforms(to: .movie) { return 2 }; if ut.conforms(to: .audio) { return 3 }
        if ut.conforms(to: .presentation) { return 4 }; if ut.conforms(to: .content) || ut.conforms(to: .text) || ut.conforms(to: .spreadsheet) { return 5 }; return 6
    }

    // MARK: Ansicht aufbauen (A-07)
    func buildItemView() {
        let oldSel = selection
        itemView?.removeFromSuperview(); scroll?.removeFromSuperview(); scroll = nil; itemView = nil
        var v: (NSView & ItemView)
        switch location {
        case .airDrop: v = AirDropView()
        default:
            switch options.mode {
            case .icon: v = IconView(frame: .zero)
            case .list: v = ListView(frame: .zero)
            case .column: v = ColumnView(frame: .zero)
            case .coverFlow: v = CoverFlowView(frame: .zero)
            }
        }
        v.host = self
        if v is IconView {
            let sc = NSScrollView(frame: contentView_.bounds)
            sc.hasVerticalScroller = true; sc.hasHorizontalScroller = false; sc.autohidesScrollers = true; sc.scrollerStyle = .legacy; sc.borderType = .noBorder
            sc.drawsBackground = true; sc.backgroundColor = .white
            sc.documentView = v
            contentView_.addSubview(sc, positioned: .below, relativeTo: errorLabel); scroll = sc
        } else { v.frame = contentView_.bounds; contentView_.addSubview(v, positioned: .below, relativeTo: errorLabel) }
        itemView = v
        selection = oldSel
        layoutAll()
        v.reload()
    }
    func setMode(_ m: ViewMode) {
        guard m != options.mode, !location.isVirtual || m != .coverFlow || true else { return }
        let keep = selection
        options.mode = m
        if case .airDrop = location { return }
        buildItemView(); arrangeAndShow(keepSelection: true)
        selection = keep; itemView?.selectionChanged(); itemView?.revealSelection()   // A-07
        chrome.needsDisplay = true; updateStatus()
    }
    func viewStateChanged() { arrangeAndShow(keepSelection: true); chrome.needsDisplay = true }

    // MARK: Auswahl
    func isSelected(_ u: URL) -> Bool { selection.contains(u) }
    func setSelection(_ urls: [URL], source: NSView?) {
        selection = urls.map { $0.isFileURL ? URL(fileURLWithPath: $0.path, isDirectory: false) : $0 }      // Ordner-URLs ohne Schrägstrich vereinheitlichen
        for v in [itemView].compactMap({ $0 }) where v !== source { v.selectionChanged() }
        if source != nil, let s = source as? ItemView { _ = s }
        (itemView as? IconView)?.needsDisplay = true
        updateQuickLook()
    }
    func selectionDidChange() { updateStatus(); chrome.needsDisplay = true; NotificationCenter.default.post(name: .selectionChangedNote, object: nil); if let v = itemView, !(v is IconView) { v.selectionChanged() } }
    func node(for u: URL) -> FileNode? {
        func find(_ ns: [FileNode]) -> FileNode? { for n in ns { if n.url.path == u.path { return n }; if let c = n.children, let f = find(c) { return f } }; return nil }
        return find(nodes) ?? find(rawNodes)
    }
    var selectedNodes: [FileNode] { selection.compactMap { node(for: $0) } }
    func children(of n: FileNode) -> [FileNode] {
        if let c = n.children { return c }
        let kids = ((try? Files.list(n.url)) ?? []).map { k -> FileNode in let f = FileNode(url: k); f.parent = n; return f }
        let key = SortKey(rawValue: options.sortKey) ?? .name
        let s = sorted(kids, key: key, asc: options.ascending); n.children = s; return s
    }

    // MARK: Öffnen (F-02, F-11)
    func openSelection() { for n in selectedNodes { open(n, modifiers: NSEvent.modifierFlags) } }
    func open(_ n: FileNode, modifiers: NSEvent.ModifierFlags) {
        let newWin = Prefs.foldersInNewWindow != modifiers.contains(.command)
        func enter(_ loc: Location) {
            if tabsOn && modifiers.contains(.command) { newTab(loc); return }
            if modifiers.contains(.option) { BrowserController.open(loc, from: self); win.close() }
            else if newWin { BrowserController.open(loc, from: self) } else { navigate(loc) }
        }
        if n.url.scheme != "file" { NSWorkspace.shared.open(n.url); return }
        if n.isAlias {
            guard let t = Alias.resolve(n.url) else { brokenAlias(n); return }
            let tv = try? t.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if tv?.isDirectory == true && tv?.isPackage != true { enter(.folder(t)) } else { NSWorkspace.shared.open(t) }
            return
        }
        if n.url.pathExtension == "savedSearch" { if let s = SavedSearches.load(n.url) { enter(.search(s)) }; return }
        if n.isFolderLike || (n.isVolume && n.isDir) { enter(.folder(n.url)); return }
        NSWorkspace.shared.open(n.url)
    }
    func brokenAlias(_ n: FileNode) {
        let a = NSAlert(); a.messageText = L("Das Alias „\(n.name)“ konnte nicht geöffnet werden, weil das Original nicht gefunden wurde.", "The alias \u{201C}\(n.name)\u{201D} can\u{2019}t be opened because the original item can\u{2019}t be found.")
        a.addButton(withTitle: L("Alias reparieren …", "Fix Alias…")); a.addButton(withTitle: L("Alias löschen", "Delete Alias")); a.addButton(withTitle: "OK")
        let r = a.runModal()
        if r == .alertFirstButtonReturn {
            let p = NSOpenPanel(); p.message = L("Wählen Sie ein neues Original für das Alias.", "Choose a new original for the alias."); p.canChooseDirectories = true
            if p.runModal() == .OK, let t = p.url { try? Files.fm.removeItem(at: n.url); _ = Alias.make(for: t, at: n.url); FileOps.shared.changed() }
        } else if r == .alertSecondButtonReturn { FileOps.shared.trash([n.url]) }
    }
    func springOpen(_ n: FileNode) { if n.isFolderLike || n.isVolume { navigate(.folder(n.url)) } }

    // MARK: Drag & Drop (F-07, F-08)
    func dragOperation(_ urls: [URL], into dir: URL?, flags: NSEvent.ModifierFlags) -> NSDragOperation {
        guard let dir, !urls.isEmpty else { return [] }
        if urls.contains(where: { $0.standardizedFileURL.path == dir.standardizedFileURL.path || dir.standardizedFileURL.path.hasPrefix($0.standardizedFileURL.path + "/") }) { return [] }
        if (try? dir.resourceValues(forKeys: [.isWritableKey]).isWritable) == false { return [] }
        if flags.contains(.control) && flags.contains(.option) { return .link }
        if flags.contains(.option) { return .copy }
        if flags.contains(.command) { return .move }
        let sameVol = (try? urls[0].resourceValues(forKeys: [.volumeURLKey]).volume) == (try? dir.resourceValues(forKeys: [.volumeURLKey]).volume)
        return sameVol ? .move : .copy
    }
    func performDrop(_ urls: [URL], into dir: URL?, flags: NSEvent.ModifierFlags) -> Bool {
        guard let dir else { return false }
        let op = dragOperation(urls, into: dir, flags: flags)
        if op == .link { FileOps.shared.makeAlias(urls, in: dir); return true }
        if op == .move || op == .copy {
            if op == .move, urls.allSatisfy({ $0.deletingLastPathComponent().standardizedFileURL.path == dir.standardizedFileURL.path }) { return true }
            FileOps.shared.transfer(urls, to: dir, move: op == .move) { [weak self] created in if dir == self?.currentDir { self?.reload(); self?.setSelection(created, source: nil); self?.itemView?.selectionChanged() } }
            return true
        }
        return false
    }
    func rename(_ n: FileNode, to name: String) {
        if let d = FileOps.shared.rename(n.url, to: name) { load(keepSelection: false); selection = [d]; itemView?.selectionChanged(); itemView?.revealSelection() }
    }
    func trashSelection() {
        if currentDir?.standardizedFileURL.path == Files.trash.path { return }
        FileOps.shared.trash(selection)
    }

    // MARK: Fensterdelegate
    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
    func windowWillClose(_ n: Notification) {
        UserDefaults.standard.set(NSStringFromRect(win.frame), forKey: "lastFrame")
        watcher?.cancel(); searchEngine?.stop(); setDual(false)
        NotificationCenter.default.removeObserver(self)
        BrowserController.all.removeAll { $0 === self }
        infoWindows.forEach { $0.close() }
        NotificationCenter.default.post(name: .locationChanged, object: nil)
    }
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { FileOps.shared.undoManager }
    func windowDidResize(_ n: Notification) { root.needsLayout = true }
    func windowDidEndLiveResize(_ n: Notification) { UserDefaults.standard.set(NSStringFromRect(win.frame), forKey: "lastFrame") }
    func windowDidMove(_ n: Notification) { UserDefaults.standard.set(NSStringFromRect(win.frame), forKey: "lastFrame") }
    func activeChanged() {
        let a = win.isKeyWindow || (QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible && (QLPreviewPanel.shared().currentController as AnyObject?) === self)
        chrome.active = a; status.active = a; sidebar.active = a; pathBar.active = a; root.needsDisplay = true; itemView?.needsDisplay = true
        if win.isMainWindow || win.isKeyWindow { }
    }
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame: NSRect) -> NSRect {
        var ideal = NSSize(width: 800, height: 600)
        if let v = itemView as? IconView { let c = v.idealContentSize(); ideal = NSSize(width: c.width + (Prefs.showSidebar ? sidebarW + 1 : 0), height: c.height + chromeH + bottomBars) }
        else if let v = itemView as? ListView { ideal = NSSize(width: v.idealWidth + (Prefs.showSidebar ? sidebarW + 1 : 0) + 15, height: CGFloat(nodes.count) * v.rowHeight + 17 + chromeH + bottomBars + 4) }
        let vis = (window.screen ?? NSScreen.main)?.visibleFrame ?? defaultFrame
        var f = window.frame
        f.size.width = min(max(ideal.width, win.minSize.width), vis.width); f.size.height = min(max(ideal.height, win.minSize.height), vis.height)
        f.origin.y = f.maxY - f.height; f.origin.y = max(vis.minY, min(f.origin.y, vis.maxY - f.height)); f.origin.x = max(vis.minX, min(f.origin.x, vis.maxX - f.width))
        f.origin.y = window.frame.maxY - f.height
        if f.minY < vis.minY { f.origin.y = vis.minY }
        return f
    }
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { true }

    // MARK: ChromeDelegate
    func chromeClose() { win.performClose(nil) }
    func chromeMiniaturize() { win.miniaturize(nil) }
    func chromeZoom() {
        if let saved = win.userFrame, abs(win.frame.width - saved.width) > 2 || abs(win.frame.height - saved.height) > 2, win.userFrame != nil && isZoomedState { win.setFrame(saved, display: true, animate: true); isZoomedState = false; return }
        win.userFrame = win.frame
        let target = windowWillUseStandardFrame(win, defaultFrame: win.frame)
        isZoomedState = true
        win.setFrame(target, display: true, animate: true)
    }
    var isZoomedState = false
    func chromeToolbarEnabled(_ id: String) -> Bool {
        if focus !== self { return focus.chromeToolbarEnabled(id) }
        if id == "dual" { return true }
        switch id {
        case "info", "quicklook", "delete": return !selection.isEmpty
        case "share": return !selection.isEmpty
        case "newfolder": return currentDir != nil
        case "burn": return currentDir?.pathExtension == Files.burnExt
        case "eject": return selection.count == 1 && Files.isEjectable(selection[0])
        default: return true
        }
    }
    func chromeAction(_ id: String, sub: Int) {
        if focus !== self { focus.chromeAction(id, sub: sub); return }
        if id == "dual" { toggleDual(nil); return }
        switch id {
        case "nav": sub == 0 ? goBack() : goForward()
        case "view": setMode(ViewMode(rawValue: sub) ?? .icon)
        case "newfolder": newFolder(nil)
        case "delete": trashSelection()
        case "terminal": terminalHere(nil)
        case "info": getInfo(nil)
        case "quicklook": quickLook()
        case "connect": connectToServer(nil)
        case "burn": if let d = currentDir { FileOps.shared.burn(d, window: win) }
        case "eject": if let u = selection.first { FileOps.shared.eject(u) }
        default: break
        }
    }
    func chromeMenu(for id: String) -> NSMenu? {
        if focus !== self { return focus.chromeMenu(for: id) }
        switch id {
        case "action": return contextMenu(for: selectedNodes.first, action: true)
        case "arrange": return arrangeMenu()
        case "share": return shareMenu()
        case "path": return chromePathMenu()
        default: return nil
        }
    }
    func chromePathMenu() -> NSMenu? {
        guard let u = currentDir else { return nil }
        let m = NSMenu(); var cur: URL? = u.standardizedFileURL; var chain: [URL] = []
        while let c = cur { chain.append(c); let p = c.deletingLastPathComponent(); cur = (c.path == "/" || p.path == c.path) ? nil : p }
        for c in chain { let it = NSMenuItem(title: Files.displayName(c), action: #selector(pathMenuPick(_:)), keyEquivalent: ""); it.target = self; it.representedObject = c
            it.image = IconCache.shared.folderImage(.folder, size: 16); m.addItem(it) }
        return m
    }
    @objc func pathMenuPick(_ s: NSMenuItem) { if let u = s.representedObject as? URL { navigate(.folder(u)) } }
    func updatePathBar() { pathBar.url = currentDir; pathBar.needsDisplay = true }

    // MARK: Status (A-11)
    @objc func sizesUpdated() { updateStatus(); itemView?.needsDisplay = true }
    func updateStatus() {
        var t = ""
        let count = nodes.count
        let n = Files.num(count)
        if case .airDrop = location { status.text = ""; return }
        var avail = ""
        if let d = currentDir { let i = Files.volumeInfo(d); if i.capacity > 0 { avail = L(", \(Files.sizeString(i.available)) verfügbar", ", \(Files.sizeString(i.available)) available") } }
        if !selection.isEmpty { t = L("\(Files.num(selection.count)) von \(n) ausgewählt", "\(Files.num(selection.count)) of \(n) selected") + avail }
        else if case .allMyFiles = location { t = L("\(n) Objekte", "\(n) items") }
        else { t = (count == 1 ? L("1 Objekt", "1 item") : L("\(n) Objekte", "\(n) items")) + avail }
        if gathering && count == 0 { t = L("Suche läuft …", "Searching…") }
        // Summe der Auswahl, sobald alle Größen bekannt sind (Ordnergrößen auf Knopfdruck)
        let sel = selectedNodes
        if !selection.isEmpty, sel.count == selection.count {
            if sel.contains(where: { $0.calculating }) { t += L(" – berechne Größen …", " – calculating sizes…") }
            else if sel.allSatisfy({ $0.size >= 0 }) { let tot = sel.reduce(Int64(0)) { $0 + $1.size }; let items = sel.filter { $0.itemCount >= 0 }.reduce(0) { $0 + $1.itemCount }
                t += " – " + Files.sizeString(tot) + (items > 0 ? L(" (\(Files.num(items)) Objekte darin)", " (\(Files.num(items)) items inside)") : "") }
        } else if sizeBusy { t += L(" – berechne Größen …", " – calculating sizes…") }
        status.text = t
        status.showSlider = options.mode == .icon && !location.isVirtual || (options.mode == .icon)
        status.sliderValue = options.iconSize
        status.needsDisplay = true
    }

    // MARK: Zwischenablage-Hilfen
    var targetURLs: [URL] { selection }
}

extension Notification.Name { static let locationChanged = Notification.Name("MLLocationChanged") }

// MARK: Einfache Hilfsansicht

final class LineView: NSView {
    override var isFlipped: Bool { true }
    var onDrag: ((CGFloat) -> Void)?
    override func draw(_ d: NSRect) { C.sidebarLine.setFill(); NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height).fill() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) {}
    override func mouseDragged(with e: NSEvent) { if let sv = superview { onDrag?(sv.convert(e.locationInWindow, from: nil).x) } }
}
