import AppKit

/// Menüleiste (E-05, Menü-Audit §11): Finder, Ablage, Bearbeiten, Darstellung, Gehe zu, Fenster, Hilfe.
enum Menus {
    static var libraryItem: NSMenuItem?
    static var goMenu: NSMenu?
    static var recentMenu: NSMenu?
    static var monitor: Any?
    static var xMenu: NSMenuItem?

    static func item(_ t: String, _ sel: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil, tag: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: sel, keyEquivalent: key); i.keyEquivalentModifierMask = key.isEmpty ? [] : mods; i.target = target; i.tag = tag; return i
    }
    static let up = String(UnicodeScalar(NSUpArrowFunctionKey)!), down = String(UnicodeScalar(NSDownArrowFunctionKey)!), bs = String(UnicodeScalar(NSBackspaceCharacter)!)

    static func build() {
        let main = NSMenu()
        func top(_ title: String, _ m: NSMenu) { let i = NSMenuItem(title: title, action: nil, keyEquivalent: ""); i.submenu = m; m.title = title; main.addItem(i) }
        let app = NSApp!

        // Finder
        let am = NSMenu()
        am.addItem(item(L("Über RetroFind", "About RetroFind"), #selector(AppActions.about(_:)), target: AppActions.shared))
        am.addItem(.separator())
        am.addItem(item(L("Einstellungen …", "Preferences…"), #selector(AppActions.prefs(_:)), ",", target: AppActions.shared))
        am.addItem(.separator())
        am.addItem(item(L("Papierkorb entleeren …", "Empty Trash…"), Selector(("emptyTrash:")), bs, [.command, .shift]))
        am.addItem(item(L("Papierkorb sicher entleeren …", "Secure Empty Trash…"), Selector(("secureEmptyTrash:"))))
        am.addItem(item(L("Time Machine öffnen", "Enter Time Machine"), #selector(AppActions.timeMachine(_:)), target: AppActions.shared))
        am.addItem(.separator())
        let sv = NSMenuItem(title: L("Dienste", "Services"), action: nil, keyEquivalent: ""); let svm = NSMenu(title: "Services"); sv.submenu = svm; app.servicesMenu = svm; am.addItem(sv)
        am.addItem(.separator())
        am.addItem(item(L("RetroFind ausblenden", "Hide RetroFind"), #selector(NSApplication.hide(_:)), "h"))
        am.addItem(item(L("Andere ausblenden", "Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        am.addItem(item(L("Alle einblenden", "Show All"), #selector(NSApplication.unhideAllApplications(_:))))
        am.addItem(.separator())
        am.addItem(item(L("RetroFind beenden", "Quit RetroFind"), #selector(NSApplication.terminate(_:)), "q"))
        top("RetroFind", am)

        // Ablage / File
        let fm = NSMenu()
        fm.addItem(item(L("Neues Finder-Fenster", "New Finder Window"), Selector(("newFinderWindow:")), "n"))
        fm.addItem(item(L("Neuer Ordner", "New Folder"), Selector(("newFolder:")), "n", [.command, .shift]))
        fm.addItem(item(L("Neuer Ordner mit Auswahl", "New Folder with Selection"), Selector(("newFolderWithSelection:")), "n", [.command, .control]))
        fm.addItem(item(L("Neuer intelligenter Ordner", "New Smart Folder"), Selector(("newSmartFolder:")), "n", [.command, .option]))
        fm.addItem(item(L("Neuer Brennordner", "New Burn Folder"), Selector(("newBurnFolder:"))))
        fm.addItem(item(L("Öffnen", "Open"), Selector(("openItem:")), "o"))
        fm.addItem(item(L("Fenster schließen", "Close Window"), Selector(("closeWin:")), "w"))
        fm.addItem(.separator())
        fm.addItem(item(L("Informationen", "Get Info"), Selector(("getInfo:")), "i"))
        fm.addItem(item(L("Informationen (Inspektor)", "Show Inspector"), Selector(("getSummaryInfo:")), "i", [.command, .option]))
        fm.addItem(item(L("Komprimieren", "Compress"), Selector(("compressItems:"))))
        fm.addItem(item(L("Duplizieren", "Duplicate"), Selector(("duplicateItems:")), "d"))
        fm.addItem(item(L("Alias erstellen", "Make Alias"), Selector(("makeAlias:")), "l"))
        fm.addItem(item(L("Übersicht", "Quick Look"), Selector(("quickLookItems:")), "y"))
        fm.addItem(item(L("Original zeigen", "Show Original"), Selector(("showOriginal:")), "r"))
        fm.addItem(item(L("Zur Seitenleiste hinzufügen", "Add to Sidebar"), Selector(("addToSidebar:")), "t", [.command, .control]))
        fm.addItem(.separator())
        fm.addItem(item(L("In den Papierkorb legen", "Move to Trash"), Selector(("moveToTrash:")), bs))
        fm.addItem(item(L("Zurücklegen", "Put Back"), Selector(("putBackItems:")), bs, [.command, .option]))
        fm.addItem(item(L("Auswerfen", "Eject"), Selector(("ejectItem:")), "e"))
        fm.addItem(item(L("Brennen …", "Burn…"), Selector(("burnItem:"))))
        fm.addItem(.separator())
        fm.addItem(item(L("Suchen", "Find"), Selector(("findItem:")), "f"))
        fm.addItem(.separator())
        let lab = NSMenuItem(title: L("Etikett", "Label"), action: nil, keyEquivalent: ""); let lm = NSMenu(title: L("Etikett", "Label"))
        for i in 0...7 { let t = i == 0 ? L("Keines", "None") : Labels.name(i); let it = NSMenuItem(title: t, action: Selector(("changeLabel:")), keyEquivalent: ""); it.tag = i; if i > 0 { it.image = dot(C.labelFill[i - 1]) }; lm.addItem(it) }
        lab.submenu = lm; fm.addItem(lab)
        fm.addItem(item(L("Drucken", "Print"), Selector(("printItems:")), "p"))
        top(L("Ablage", "File"), fm)

        // Bearbeiten / Edit
        let em = NSMenu()
        em.addItem(item(L("Widerrufen", "Undo"), Selector(("undo:")), "z"))
        em.addItem(item(L("Wiederholen", "Redo"), Selector(("redo:")), "z", [.command, .shift]))
        em.addItem(.separator())
        em.addItem(item(L("Kopieren", "Copy"), Selector(("copy:")), "c"))
        em.addItem(item(L("Objekt einsetzen", "Paste Item"), Selector(("paste:")), "v"))
        em.addItem(item(L("Objekt hierher bewegen", "Move Item Here"), Selector(("pasteMove:")), "v", [.command, .option]))
        em.addItem(item(L("Alles auswählen", "Select All"), Selector(("selectAll:")), "a"))
        em.addItem(.separator())
        em.addItem(item(L("Ablage anzeigen", "Show Clipboard"), Selector(("showClipboard:"))))
        top(L("Bearbeiten", "Edit"), em)

        // Darstellung / View
        let vm = NSMenu()
        vm.addItem(item(L("als Symbole", "as Icons"), Selector(("viewAsIcons:")), "1"))
        vm.addItem(item(L("als Liste", "as List"), Selector(("viewAsList:")), "2"))
        vm.addItem(item(L("als Spalten", "as Columns"), Selector(("viewAsColumns:")), "3"))
        vm.addItem(item(L("als Cover Flow", "as Cover Flow"), Selector(("viewAsCoverFlow:")), "4"))
        vm.addItem(.separator())
        vm.addItem(item(L("Aufräumen", "Clean Up"), Selector(("cleanUp:"))))
        let cu = NSMenuItem(title: L("Aufräumen nach", "Clean Up By"), action: nil, keyEquivalent: ""); let cum = NSMenu()
        for k in SortKey.allCases where k != .none { let i = NSMenuItem(title: k.title, action: Selector(("cleanUpBy:")), keyEquivalent: ""); i.representedObject = k.rawValue; cum.addItem(i) }
        cu.submenu = cum; vm.addItem(cu)
        let ab = NSMenuItem(title: L("Anordnen nach", "Arrange By"), action: nil, keyEquivalent: ""); let abm = NSMenu(); abm.delegate = ArrangeDelegate.shared; ab.submenu = abm; vm.addItem(ab)
        let sb = NSMenuItem(title: L("Sortieren nach", "Sort By"), action: nil, keyEquivalent: ""); let sbm = NSMenu(); sbm.delegate = ArrangeDelegate.shared; sbm.title = "sort"; sb.submenu = sbm; vm.addItem(sb)
        vm.addItem(.separator())
        vm.addItem(item(L("Symbolleiste ausblenden", "Hide Toolbar"), Selector(("toggleToolbar:")), "t", [.command, .option]))
        vm.addItem(item(L("Symbolleiste anpassen …", "Customize Toolbar…"), Selector(("customizeToolbar:"))))
        vm.addItem(item(L("Seitenleiste ausblenden", "Hide Sidebar"), Selector(("toggleSidebar:")), "s", [.command, .option]))
        vm.addItem(item(L("Statusleiste einblenden", "Show Status Bar"), Selector(("toggleStatusBar:")), "/"))
        vm.addItem(item(L("Pfadleiste einblenden", "Show Path Bar"), Selector(("togglePathBar:")), "p", [.command, .option]))
        vm.addItem(.separator())
        vm.addItem(item(L("Darstellungsoptionen einblenden", "Show View Options"), Selector(("showViewOptions:")), "j"))
        vm.addItem(item(L("Ordnergrößen berechnen", "Calculate Folder Sizes"), Selector(("calcFolderSizes:")), "s", [.command, .option, .shift]))
        vm.addItem(.separator())
        vm.addItem(item(L("Schreibtisch-Symbole einblenden", "Show Desktop Icons"), #selector(AppActions.toggleDesktop(_:)), target: AppActions.shared))
        top(L("Darstellung", "View"), vm)

        // Gehe zu / Go
        let gm = NSMenu(title: L("Gehe zu", "Go")); goMenu = gm
        gm.addItem(item(L("Zurück", "Back"), Selector(("goBackAction:")), "[", [.command]))
        gm.addItem(item(L("Vorwärts", "Forward"), Selector(("goForwardAction:")), "]", [.command]))
        gm.addItem(item(L("Übergeordneter Ordner", "Enclosing Folder"), Selector(("goEnclosing:")), up, [.command]))
        gm.addItem(item(L("Ausgewähltes Objekt öffnen", "Open Selected Item"), Selector(("goInto:")), down, [.command]))
        gm.addItem(.separator())
        gm.addItem(item(L("Alle meine Dateien", "All My Files"), Selector(("goAllMyFiles:")), "f", [.command, .shift]))
        gm.addItem(item(L("Dokumente", "Documents"), Selector(("goDocuments:")), "o", [.command, .shift]))
        gm.addItem(item(L("Schreibtisch", "Desktop"), Selector(("goDesktop:")), "d", [.command, .shift]))
        gm.addItem(item(L("Downloads", "Downloads"), Selector(("goDownloads:")), "l", [.command, .option]))
        gm.addItem(item(L("Benutzerordner", "Home"), Selector(("goHome:")), "h", [.command, .shift]))
        let lib = item(L("Library", "Library"), Selector(("goLibrary:")), "l", [.command, .shift]); lib.isHidden = true; libraryItem = lib; gm.addItem(lib)
        gm.addItem(item(L("Computer", "Computer"), Selector(("goComputer:")), "c", [.command, .shift]))
        gm.addItem(item("AirDrop", Selector(("goAirDrop:")), "r", [.command, .shift]))
        gm.addItem(item(L("Netzwerk", "Network"), Selector(("goNetwork:")), "k", [.command, .shift]))
        gm.addItem(item(L("Programme", "Applications"), Selector(("goApplications:")), "a", [.command, .shift]))
        gm.addItem(item(L("Dienstprogramme", "Utilities"), Selector(("goUtilities:")), "u", [.command, .shift]))
        gm.addItem(.separator())
        let rc = NSMenuItem(title: L("Benutzte Ordner", "Recent Folders"), action: nil, keyEquivalent: ""); let rm = NSMenu(); rm.delegate = ArrangeDelegate.shared; rm.title = "recent"; rc.submenu = rm; recentMenu = rm; gm.addItem(rc)
        gm.addItem(.separator())
        gm.addItem(item(L("Gehe zum Ordner …", "Go to Folder…"), Selector(("goToFolder:")), "g", [.command, .shift]))
        gm.addItem(item(L("Mit Server verbinden …", "Connect to Server…"), Selector(("connectToServer:")), "k"))
        gm.delegate = ArrangeDelegate.shared
        top(L("Gehe zu", "Go"), gm)

        // X-Modus (nur sichtbar, wenn in den Einstellungen aktiv)
        let xm = NSMenu(title: "X-Modus")
        xm.addItem(item(L("Neuer Tab", "New Tab"), Selector(("newTabAction:")), "t"))
        xm.addItem(item(L("Nächster Tab", "Next Tab"), Selector(("nextTab:")), "]", [.command, .shift]))
        xm.addItem(item(L("Vorheriger Tab", "Previous Tab"), Selector(("prevTab:")), "[", [.command, .shift]))
        xm.addItem(item(L("In neuem Tab öffnen", "Open in New Tab"), Selector(("openInNewTab:"))))
        xm.addItem(item(L("Geschlossenen Tab wiederherstellen", "Reopen Closed Tab"), Selector(("reopenTab:")), "t", [.command, .shift]))
        let jump = NSMenuItem(title: L("Gehe zu Tab", "Go to Tab"), action: nil, keyEquivalent: ""); let jm = NSMenu()
        for n in 1...9 { jm.addItem(item(n == 9 ? L("Letzter Tab", "Last Tab") : L("Tab \(n)", "Tab \(n)"), Selector(("jumpToTab:")), String(n), [.command, .option], tag: n)) }
        jump.submenu = jm; xm.addItem(jump)
        xm.addItem(.separator())
        xm.addItem(item(L("Dual Pane ein/aus", "Toggle Dual Pane"), Selector(("toggleDual:")), "p", [.command, .option]))
        xm.addItem(item(L("Terminal hier", "Terminal Here"), Selector(("terminalHere:")), "t", [.command, .option, .shift]))
        xm.addItem(item(L("Pfad kopieren", "Copy Path"), Selector(("copyPath:")), "c", [.command, .option]))
        xm.addItem(item(L("Mehrfach-Umbenennen …", "Batch Rename…"), Selector(("batchRename:")), "r", [.command, .option]))
        xm.addItem(item(L("Warteschlange anzeigen", "Show Transfer Queue"), Selector(("showQueue:")), "q", [.command, .option]))
        xm.addItem(.separator())
        xm.addItem(item(L("Favoriten der Hälfte …", "Pane Favorites…"), Selector(("showFavorites:")), "b", [.command, .option]))
        xm.addItem(item(L("Aktuellen Ordner als Favorit ein/aus", "Toggle Current Folder as Favorite"), Selector(("toggleFavorite:")), "b", [.command, .option, .shift]))
        xm.addItem(item(L("Verlauf der Hälfte …", "Pane History…"), Selector(("showHistory:")), String(UnicodeScalar(NSDownArrowFunctionKey)!), [.option]))
        xm.addItem(item(L("Fenster wechseln (Tab)", "Switch Pane (Tab)"), Selector(("switchPane:"))))
        xm.addItem(item(L("Andere Hälfte = diese", "Mirror to Other Pane"), Selector(("mirrorPane:")), "=", [.command, .option]))
        xm.addItem(item(L("Hälften tauschen", "Swap Panes"), Selector(("swapPanes:")), "x", [.command, .option]))
        xm.addItem(item(L("Auswahl nach Muster …", "Select by Pattern…"), Selector(("selectPattern:")), "+", [.command]))
        xm.addItem(item(L("Auswahl nach Muster aufheben …", "Deselect by Pattern…"), Selector(("deselectPattern:")), "-", [.command]))
        xm.addItem(item(L("F3 Ansehen", "F3 View"), Selector(("dualView:"))))
        xm.addItem(item(L("F4 Bearbeiten", "F4 Edit"), Selector(("dualEdit:"))))
        xm.addItem(item(L("F5 Kopieren", "F5 Copy"), Selector(("dualCopy:"))))
        xm.addItem(item(L("F6 Verschieben", "F6 Move"), Selector(("dualMove:"))))
        xm.addItem(item(L("F7 Neuer Ordner", "F7 New Folder"), Selector(("dualNewFolder:"))))
        xm.addItem(item(L("F8 Löschen", "F8 Delete"), Selector(("dualDelete:"))))
        top("X-Modus", xm); xMenu = main.items.last; xMenu?.isHidden = !Prefs.xMode

        // Fenster / Window
        let wm = NSMenu(title: L("Fenster", "Window"))
        wm.addItem(item(L("Im Dock ablegen", "Minimize"), Selector(("minimizeWin:")), "m"))
        wm.addItem(item(L("Zoom", "Zoom"), Selector(("zoomWin:"))))
        wm.addItem(item(L("Fenster wechseln", "Cycle Through Windows"), Selector(("cycleWindows:")), "`"))
        wm.addItem(.separator())
        wm.addItem(item(L("Alle nach vorne bringen", "Bring All to Front"), #selector(NSApplication.arrangeInFront(_:))))
        top(L("Fenster", "Window"), wm); app.windowsMenu = wm

        // Hilfe / Help
        let hm = NSMenu(title: L("Hilfe", "Help"))
        hm.addItem(item(L("Finder-Hilfe", "Finder Help"), #selector(AppActions.help(_:)), "?", target: AppActions.shared))
        hm.addItem(item(L("Tastaturkurzbefehle", "Keyboard Shortcuts"), #selector(AppActions.shortcuts(_:)), target: AppActions.shared))
        top(L("Hilfe", "Help"), hm); app.helpMenu = hm

        app.mainMenu = main
        // Wahltaste zeigt „Library“ im Menü „Gehe zu“ (N-09)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { e in libraryItem?.isHidden = !e.modifierFlags.contains(.option); return e }
    }
    static func dot(_ c: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in c.setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill(); c.shadow(withLevel: 0.4)?.setStroke(); NSBezierPath(ovalIn: r.insetBy(dx: 1.5, dy: 1.5)).stroke(); return true }
    }
}

/// Füllt Anordnen-/Sortieren-/Benutzte-Ordner-Untermenüs bei Bedarf
final class ArrangeDelegate: NSObject, NSMenuDelegate {
    static let shared = ArrangeDelegate()
    var current: BrowserController? { (NSApp.keyWindow?.windowController as? BrowserController) ?? BrowserController.all.first }
    func menuWillOpen(_ menu: NSMenu) { Menus.libraryItem?.isHidden = !NSEvent.modifierFlags.contains(.option) }
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.title == "recent" {
            menu.removeAllItems()
            for p in Prefs.recents { let u = URL(fileURLWithPath: p); let i = NSMenuItem(title: Files.displayName(u), action: Selector(("goRecent:")), keyEquivalent: ""); i.representedObject = p; i.image = IconCache.shared.folderImage(.folder, size: 16); menu.addItem(i) }
            menu.addItem(.separator())
            let c = NSMenuItem(title: L("Liste löschen", "Clear Menu"), action: #selector(clearRecents), keyEquivalent: ""); c.target = self; menu.addItem(c)
            return
        }
        guard let c = current else { return }
        menu.removeAllItems()
        let src = c.arrangeMenu()
        if menu.title == "sort" {
            for k in SortKey.allCases where k != .none { let i = NSMenuItem(title: k.title, action: Selector(("sortBy:")), keyEquivalent: ""); i.representedObject = k.rawValue; i.state = c.options.sortKey == k.rawValue ? .on : .off; menu.addItem(i) }
            return
        }
        if c.options.mode == .icon { for it in src.items { src.removeItem(it); it.target = nil; menu.addItem(it) } }
        else { let i = NSMenuItem(title: L("Nur in der Symbolansicht", "Icon view only"), action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i) }
    }
    @objc func clearRecents() { Prefs.recents = [] }
}

final class AppActions: NSObject {
    static let shared = AppActions()
    @objc func about(_ s: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "RetroFind", .credits: NSAttributedString(string: L("Alle Symbole sind eigene Zeichnungen (GPL-3.0); das Programmsymbol ist vom Autor bereitgestellt (nicht GPL). Eigene Seitenleistensymbole: Einstellungen ▸ Custom Icons.\n\n", "All icons are original drawings (GPL-3.0); the app icon is author-supplied (not GPL). Custom sidebar icons: Preferences ▸ Custom Icons.\n\n") + L("Nachbau des Finders von OS X 10.8 Mountain Lion. Unabhängiges Projekt, nicht mit Apple verbunden. Apple, Mac, OS X und Mountain Lion sind Marken von Apple Inc.", "A recreation of the OS X 10.8 Mountain Lion Finder. Independent project, not affiliated with Apple. Apple, Mac, OS X and Mountain Lion are trademarks of Apple Inc."), attributes: [.font: NSFont.systemFont(ofSize: 11)])] )
    }
    @objc func prefs(_ s: Any?) { PreferencesWindow.shared.show() }
    @objc func help(_ s: Any?) { HelpWindow.show() }
    @objc func timeMachine(_ s: Any?) { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Time Machine.app")) }
    @objc func toggleDesktop(_ s: Any?) { UserDefaults.standard.set(!DesktopController.isOn, forKey: "desktopOn"); DesktopController.apply() }
    @objc func validateMenuItem(_ i: NSMenuItem) -> Bool { if i.action == #selector(toggleDesktop(_:)) { i.title = DesktopController.isOn ? L("Schreibtisch-Symbole ausblenden", "Hide Desktop Icons") : L("Schreibtisch-Symbole einblenden", "Show Desktop Icons") }; return true }
    @objc func shortcuts(_ s: Any?) { HelpWindow.show(shortcuts: true) }
}
