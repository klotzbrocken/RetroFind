import AppKit

func snapshotPNG(_ v: NSView, to path: String) {
    let w = Int(v.bounds.width.rounded()), h = Int(v.bounds.height.rounded())
    guard let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    r.size = v.bounds.size; v.cacheDisplay(in: v.bounds, to: r)
    try? (r.converting(to: .sRGB, renderingIntent: .default) ?? r).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let demo = CommandLine.arguments.contains("-demo")      // synthetische Seitenleiste (Screenshots)
    let args = CommandLine.arguments
    func arg(_ k: String) -> String? { args.first { $0.hasPrefix("-" + k + "=") }.map { String($0.dropFirst(k.count + 2)) } }

    func applicationDidFinishLaunching(_ n: Notification) {
        if args.contains("-selftest") { SelfTest.run() }
        if let l = arg("lang") { Lang.de = l == "de" }
        NSApp.setActivationPolicy(.regular)
        if AppDelegate.demo { CustomIcons.dirOverride = Files.fm.temporaryDirectory.appendingPathComponent("mlf-no-custom-icons") }   // Screenshots: nie eigene Symbole des Nutzers zeigen
        Menus.build()
        AppIcon.apply()
        var loc = BrowserController.startLocation()
        if let p = arg("open") { loc = p == "allfiles" ? .allMyFiles : p == "computer" ? .computer : p == "airdrop" ? .airDrop : p == "network" ? .network : .folder(URL(fileURLWithPath: (p as NSString).expandingTildeInPath)) }
        var size = M.defaultSize
        if let s = arg("size") { let p = s.split(separator: "x").compactMap { Double($0) }; if p.count == 2 { size = NSSize(width: p[0], height: p[1]) } }
        if args.contains("-fresh") { UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "de.maik.RetroFind"); UserDefaults.standard.removeObject(forKey: "lastFrame") }
        let c = BrowserController(location: loc, size: size)
        if args.contains("-fresh") || arg("size") != nil { c.win.setContentSize(size); c.win.center() }
        if let v = arg("view") { c.setMode(["icon": .icon, "list": .list, "column": .column, "cover": .coverFlow][v] ?? .icon) }
        if args.contains("-status") { Prefs.showStatus = true; c.layoutAll(); c.updateStatus() }
        if args.contains("-path") { Prefs.showPath = true; c.layoutAll() }
        if args.contains("-aqua") { Prefs.aquaLights = true; c.win.placeLights(); c.layoutAll() }
        if args.contains("-colored") { Prefs.coloredIcons = true; c.sidebar.needsDisplay = true }
        if args.contains("-xmode") { Prefs.xMode = true; Prefs.xTabs = true; Prefs.xDual = args.contains("-dual"); c.applyXMode(); Menus.xMenu?.isHidden = false
            for (i, p) in (arg("tabs") ?? "").split(separator: ",").enumerated() { c.newTab(.folder(URL(fileURLWithPath: String(p)))); _ = i }
            if let r = arg("right") { c.rightPane?.go(.folder(URL(fileURLWithPath: r)), record: true) } }
        c.win.makeKeyAndOrderFront(nil)
        if args.contains("-calc") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { c.calcFolderSizes(nil) } }
        DesktopController.apply()
        if arg("open") == nil && !args.contains("-fresh") { c.restoreTabs() }
        c.loadVisited(); BrowserController.persistEnabled = true; c.noteVisited(c.location); c.persistTabs()
        if args.contains("-uitest") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { UITest.run(c, folder: URL(fileURLWithPath: self.arg("open") ?? NSHomeDirectory())) } }
        if args.contains("-mintest") {
            c.win.setFrame(NSRect(x: 100, y: 100, width: 200, height: 80), display: true)
            print("MIN-TEST: Fenster nach Verkleinern auf 200×80 =", c.win.frame.size, " minSize =", c.win.minSize, " Toolbar-Mindestbreite =", c.chrome.minToolbarWidth)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { snapshotPNG(c.root, to: "/tmp/mlf/min.png"); NSApp.terminate(nil) }
        }
        NSApp.activate(ignoringOtherApps: true)
        if let path = arg("snap") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let s = self.arg("select"), let u = c.nodes.first(where: { $0.name.hasPrefix(s) })?.url { c.setSelection([u], source: nil); c.itemView?.selectionChanged(); c.itemView?.revealSelection() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(arg("delay") ?? "") ?? 1.8) + 0.8) {
                if self.args.contains("-inactive") { NSApp.hide(nil) }
                var target: NSView = c.root
                var targetWin: NSWindow = c.win
                switch self.arg("show") {
                case "prefs": PreferencesWindow.shared.show(); PreferencesWindow.shared.select(Int(self.arg("tab") ?? "0") ?? 0); target = PreferencesWindow.shared.win.contentView!; print("PREFS", PreferencesWindow.shared.win.frame, PreferencesWindow.shared.win.contentView!.frame, PreferencesWindow.shared.tabs.frame); targetWin = PreferencesWindow.shared.win
                case "info": if let u = c.selection.first ?? c.nodes.first?.url { InfoWindow.show([u], from: c); target = InfoWindow.open.values.first!.panel.contentView!; targetWin = InfoWindow.open.values.first!.panel }
                case "rename": BatchRenameWindow.show(Array(c.nodes.prefix(9).map { $0.url }), from: c.win); if let b = BatchRenameWindow.current { b.modePop.selectItem(at: 2); b.modeChanged(); target = b.win.contentView!; targetWin = b.win }
                case "queue": let q = TransferQueue.shared; q.paused = true; for n in c.nodes.prefix(3) { q.enqueue([n.url], to: Files.fm.temporaryDirectory, move: false) }; QueueWindow.shared.show(); target = QueueWindow.shared.win.contentView!; targetWin = QueueWindow.shared.win
                case "viewopts": ViewOptionsPanel.shared.show(for: c); target = ViewOptionsPanel.shared.panel.contentView!; targetWin = ViewOptionsPanel.shared.panel
                default: break
                }
                if self.args.contains("-realshot") {
                    let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); t.arguments = ["-x", "-o", "-l", "\(targetWin.windowNumber)", path]; try? t.run(); t.waitUntilExit()
                } else { snapshotPNG(target, to: path) }
                if self.args.contains("-quit") { NSApp.terminate(nil) }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows f: Bool) -> Bool {
        if BrowserController.all.isEmpty { BrowserController.open(BrowserController.startLocation()) } else if !f { BrowserController.all.first?.win.makeKeyAndOrderFront(nil) }
        return true
    }
    func application(_ app: NSApplication, open urls: [URL]) {
        for u in urls { BrowserController.open(.folder(u)) }
    }
    @objc func newWindowFromDock(_ s: Any?) { BrowserController.open(BrowserController.startLocation()) }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu(); let i = NSMenuItem(title: L("Neues Finder-Fenster", "New Finder Window"), action: #selector(newWindowFromDock(_:)), keyEquivalent: ""); i.target = self; m.addItem(i); return m
    }
}
