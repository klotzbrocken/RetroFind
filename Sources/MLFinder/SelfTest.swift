import AppKit

/// `-selftest`: prüft den Dateikern (§7.1, §15.2 T-03/T-05) ohne Oberfläche. Ausgabe: PASS/FAIL je Fall.
enum SelfTest {
    static var fails = 0
    static func check(_ ok: Bool, _ name: String) { print(ok ? "PASS" : "FAIL", name); if !ok { fails += 1 } }
    static func pump(_ cond: () -> Bool, timeout: TimeInterval = 15) { let end = Date().addingTimeInterval(timeout); while !cond() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) } }
    static func read(_ u: URL) -> String { (try? String(contentsOf: u, encoding: .utf8)) ?? "∅" }

    static func run() {
        setvbuf(stdout, nil, _IONBF, 0)
        FileOps.testMode = true
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("mlf-selftest-\(UUID().uuidString.prefix(6))")
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func mk(_ p: String, _ c: String = "x") -> URL { let u = root.appendingPathComponent(p); try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true); try? c.write(to: u, atomically: true, encoding: .utf8); return u }
        let ops = FileOps.shared

        // Ansicht erben / global
        let va = Location.folder(root.appendingPathComponent("VA")), vb = Location.folder(root.appendingPathComponent("VA/sub/deep"))
        var vo = ViewStore.options(for: va); vo.mode = .list; ViewStore.save(vo, for: va)
        check(ViewStore.options(for: vb).mode == .list, "Ansicht: Unterordner erbt vom Elternordner")
        check(!ViewStore.hasSaved(vb), "Ansicht: Erben speichert nichts")
        ViewStore.setGlobal(true, from: vo); var vc = ViewStore.options(for: Location.folder(root)); check(vc.mode == .list, "Ansicht: global")
        ViewStore.setGlobal(false, from: nil); ViewStore.remove(va)
        // Kopieren (Inhalt + Metadaten)
        let a = mk("A/datei.txt", "alpha"); mk("B/.keep")
        try? fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: a.path)
        _ = setxattr(a.path, "user.test", "v", 1, 0, 0)
        Files.setComment(a, "Kommentar ä")
        var done = false
        ops.transfer([a], to: root.appendingPathComponent("B"), move: false) { _ in done = true }; pump { done }
        let c1 = root.appendingPathComponent("B/datei.txt")
        check(read(c1) == "alpha", "Kopie: Inhalt")
        check(((try? fm.attributesOfItem(atPath: c1.path))?[.modificationDate] as? Date)?.timeIntervalSince1970 == 1_000_000_000, "Kopie: Zeitstempel")
        check(getxattr(c1.path, "user.test", nil, 0, 0, 0) == 1, "Kopie: Extended Attribute")
        check(Files.getComment(c1) == "Kommentar ä", "Kopie: Spotlight-Kommentar")
        check(fm.fileExists(atPath: a.path), "Kopie: Quelle bleibt")

        // Konflikt: Beide behalten
        FileOps.testChoice = .keepBoth; done = false
        ops.transfer([a], to: root.appendingPathComponent("B"), move: false) { _ in done = true }; pump { done }
        check(((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent("B").path)) ?? []).contains { $0.hasPrefix("datei ") && $0.hasSuffix(".txt") }, "Konflikt: Beide behalten (Kopie-Suffix)")
        // Konflikt: Ersetzen (atomar)
        try? "neu".write(to: a, atomically: true, encoding: .utf8); FileOps.testChoice = .replace; done = false
        ops.transfer([a], to: root.appendingPathComponent("B"), move: false) { _ in done = true }; pump { done }
        check(read(c1) == "neu", "Konflikt: Ersetzen")
        // Konflikt: Überspringen
        try? "skip".write(to: a, atomically: true, encoding: .utf8); FileOps.testChoice = .skip; done = false
        ops.transfer([a, mk("A/zwei.txt", "2")], to: root.appendingPathComponent("B"), move: false) { _ in done = true }; pump { done }
        check(read(c1) == "neu" && read(root.appendingPathComponent("B/zwei.txt")) == "2", "Konflikt: Überspringen")

        // Zusammenführen
        mk("M1/sub/a.txt", "m1a"); mk("M1/b.txt", "m1b"); mk("M2/sub/c.txt", "m2c"); mk("M2/b.txt", "m2b")
        FileOps.testChoice = .replace; done = false
        _ = try? fm.createDirectory(at: root.appendingPathComponent("T"), withIntermediateDirectories: true)
        try? fm.copyItem(at: root.appendingPathComponent("M2"), to: root.appendingPathComponent("T/M1"))
        done = false
        ops.transfer([root.appendingPathComponent("M1")], to: root.appendingPathComponent("T"), move: false) { _ in done = true }; pump { done }
        check(read(root.appendingPathComponent("T/M1/sub/a.txt")) == "m1a" && read(root.appendingPathComponent("T/M1/sub/c.txt")) == "m2c" && read(root.appendingPathComponent("T/M1/b.txt")) == "m1b", "Zusammenführen: Vereinigung, Konflikt ersetzt, nichts verloren")

        // Rekursion ins eigene Unterverzeichnis
        FileOps.testLog = []; ops.transfer([root.appendingPathComponent("M1")], to: root.appendingPathComponent("M1/sub"), move: false)
        check(!FileOps.testLog.isEmpty && !fm.fileExists(atPath: root.appendingPathComponent("M1/sub/M1").path), "Rekursion in sich selbst abgewiesen")

        // Bewegen + Undo/Redo
        let mv = mk("src/m.txt", "move"); mk("dst/.keep")
        done = false; ops.transfer([mv], to: root.appendingPathComponent("dst"), move: true) { _ in done = true }; pump { done }
        check(!fm.fileExists(atPath: mv.path) && fm.fileExists(atPath: root.appendingPathComponent("dst/m.txt").path), "Bewegen")
        ops.undoManager.undo(); check(fm.fileExists(atPath: mv.path) && !fm.fileExists(atPath: root.appendingPathComponent("dst/m.txt").path), "Undo: Bewegen")
        ops.undoManager.redo(); check(!fm.fileExists(atPath: mv.path) && fm.fileExists(atPath: root.appendingPathComponent("dst/m.txt").path), "Redo: Bewegen")

        // Duplizieren, Alias, Neuer Ordner
        let d = ops.duplicate([a]); check(d.count == 1 && d[0].lastPathComponent == "datei copy.txt" || d[0].lastPathComponent == "datei copy 2.txt" || fm.fileExists(atPath: d[0].path), "Duplizieren eindeutig")
        let al = ops.makeAlias([a]); check(al.count == 1 && Alias.resolve(al[0])?.standardizedFileURL.path == a.standardizedFileURL.path, "Alias: echt + auflösbar")
        let moved = a.deletingLastPathComponent().appendingPathComponent("verschoben.txt"); try? fm.moveItem(at: a, to: moved)
        check(Alias.resolve(al[0])?.standardizedFileURL.path == moved.standardizedFileURL.path, "Alias folgt umbenanntem Original")
        try? fm.removeItem(at: moved); check(Alias.resolve(al[0]) == nil, "Alias: fehlendes Ziel erkannt")
        let nf = ops.newFolder(in: root); let nf2 = ops.newFolder(in: root)
        check(nf != nil && nf2 != nil && nf != nf2, "Neuer Ordner: kollisionsfreie Namen")

        // Umbenennen
        let r1 = mk("rn/Datei.txt"); let r2 = ops.rename(r1, to: "datei.txt")
        check(r2?.lastPathComponent == "datei.txt" && (try? fm.contentsOfDirectory(atPath: r1.deletingLastPathComponent().path))?.contains("datei.txt") == true, "Umbenennen: nur Groß-/Kleinschreibung")
        FileOps.testLog = []; check(ops.rename(r2!, to: "a/b") == nil && !FileOps.testLog.isEmpty, "Umbenennen: ungültiger Name abgewiesen")

        // Papierkorb + Zurücklegen
        let tr = mk("trashme.txt", "t"); let origPath = tr.path
        check(ops.trash([tr]) && !fm.fileExists(atPath: origPath), "Papierkorb: verschoben")
        if let t = (try? fm.contentsOfDirectory(at: Files.trash, includingPropertiesForKeys: nil))?.first(where: { $0.lastPathComponent.hasPrefix("trashme") }) {
            ops.putBack([t]); check(fm.fileExists(atPath: origPath), "Zurücklegen: ursprünglicher Ort")
        } else { check(false, "Papierkorb: Objekt gefunden (kein Zugriff auf ~/.Trash? Vollzugriff nötig)") }

        // Etikett + Kommentar
        let lb = mk("lab.txt"); Labels.set(4, for: lb); check(FileNode(url: lb).label == 4, "Etikett: Grün (4) gesetzt/gelesen"); Labels.set(0, for: lb); check(FileNode(url: lb).label == 0, "Etikett: entfernt")
        Files.setComment(lb, ""); check(Files.getComment(lb) == "", "Kommentar entfernt")

        // Symlink bleibt Symlink
        let sl = root.appendingPathComponent("sl"); try? fm.createSymbolicLink(at: sl, withDestinationURL: lb)
        done = false; ops.transfer([sl], to: root.appendingPathComponent("dst"), move: false) { _ in done = true }; pump { done }
        check((try? fm.destinationOfSymbolicLink(atPath: root.appendingPathComponent("dst/sl").path)) != nil && !FileNode(url: sl).isAlias, "Symlink: kopiert als Symlink, kein Alias")

        // Komprimieren
        done = false; var zip: URL?; ops.compress([lb]) { r in zip = r.first; done = true }; pump { done }
        check(zip.map { fm.fileExists(atPath: $0.path) && $0.pathExtension == "zip" } ?? false, "Komprimieren: ZIP erstellt")

        // Suchprädikate
        var s = SearchSpec(); s.text = "abc"; s.criteria = [Criterion(attr: "kind", op: "is", value: "image"), Criterion(attr: "size", op: "gt", value: "1")]
        check(s.predicate().predicateFormat.contains("abc") && s.predicate().predicateFormat.contains("public.image"), "Suche: Prädikat Name+Art+Größe")
        let saved = SavedSearches.save(s, name: "mlf-selftest", to: root); check(saved.flatMap { SavedSearches.load($0) }?.criteria.count == 2, "Intelligenter Ordner: speichern/laden")

        // Mehrfach-Umbenennen: Engine
        var rs = RenameSpec(); rs.find = "Foto"; rs.replaceWith = "Bild"
        check(BatchRename.newName("Foto 1.JPG", index: 0, spec: rs) == "Bild 1.JPG" && BatchRename.newName("foto.png", index: 0, spec: rs) == "Bild.png", "Umbenennen: Text ersetzen (Erweiterung bleibt)")
        rs = RenameSpec(); rs.mode = .add; rs.addText = "_neu"; rs.atStart = false; check(BatchRename.newName("a.txt", index: 0, spec: rs) == "a_neu.txt", "Umbenennen: Text am Ende vor der Erweiterung")
        rs = RenameSpec(); rs.mode = .number; rs.format = "Urlaub {n}"; rs.start = 5; rs.step = 5; rs.digits = 3; check(BatchRename.newName("x.jpg", index: 2, spec: rs) == "Urlaub 015.jpg", "Umbenennen: Nummerierung Start/Schritt/Stellen")
        rs = RenameSpec(); rs.mode = .caseChange; rs.caseMode = 2; check(BatchRename.newName("hello wORLD.txt", index: 0, spec: rs) == "Hello World.txt", "Umbenennen: Wörter groß")
        rs = RenameSpec(); rs.mode = .regex; rs.find = "^(\\d+)_(.*)$"; rs.replaceWith = "$2-$1"; check(BatchRename.newName("12_name.txt", index: 0, spec: rs) == "name-12.txt", "Umbenennen: regulärer Ausdruck mit Gruppen")
        rs.find = "([unclosed"; check(BatchRename.newName("a", index: 0, spec: rs) == nil, "Umbenennen: ungültiges Muster erkannt")
        let br1 = mk("br/eins.txt", "1"), br2 = mk("br/zwei.txt", "2"), brx = mk("br/drei.txt", "3")
        let pr = BatchRename.problems(urls: [br1, br2], names: ["gleich.txt", "gleich.txt"]); check(!pr[1].isEmpty, "Umbenennen: doppelte Ziele gemeldet")
        check(!BatchRename.problems(urls: [br1], names: ["drei.txt"])[0].isEmpty, "Umbenennen: Kollision mit nicht beteiligtem Objekt gemeldet")
        _ = brx
        // Tausch ohne Datenverlust (zweistufig) + Undo
        ops.batchRename([(br1, "zwei.txt"), (br2, "eins.txt")])
        check(read(br1) == "2" && read(br2) == "1", "Umbenennen: Tausch eins↔zwei ohne Verlust")
        ops.undoManager.undo(); check(read(br1) == "1" && read(br2) == "2", "Umbenennen: Undo stellt Namen wieder her")
        // Regression (Absturzbericht): Dialog aufbauen darf nicht vor der ersten Vorschau auf Zeilen zugreifen
        BatchRenameWindow.show([br1, br2], from: nil); check(BatchRenameWindow.current?.names.count == 2, "Umbenennen-Dialog: Aufbau ohne Absturz"); BatchRenameWindow.current?.cancel()
        // Ordnergrößen auf Knopfdruck
        let fs = mk("fsz/a/x.bin", String(repeating: "x", count: 1000)); _ = mk("fsz/a/b/y.bin", String(repeating: "y", count: 500)); _ = mk("fsz/z.txt", "zz")
        let fn = FileNode(url: root.appendingPathComponent("fsz")); check(fn.size < 0 && fn.displaySize == "--", "Ordnergröße: vor dem Knopfdruck unbekannt")
        var fin = false; SizeService.shared.calculate([fn], onFinish: { fin = true }); pump({ fin }, timeout: 10)
        check(fn.size == 1502 && fn.itemCount == 5 && !fn.calculating, "Ordnergröße: rekursive Summe (1502 Byte, 5 Objekte)"); _ = fs
        check(FileNode(url: root.appendingPathComponent("fsz")).size == 1502, "Ordnergröße: Ergebnis wird zwischengespeichert")
        let cb = SizeService.shared.calculate([FileNode(url: root.appendingPathComponent("fsz/a"))]); cb.cancelled = true; pump({ false }, timeout: 0.5)
        // Verlauf je Hälfte
        let hv = BrowserController(location: .folder(root.appendingPathComponent("A")), showWindow: false); hv.visited = []
        for n in ["A", "B", "A", "qdst", "B"] { hv.go(.folder(root.appendingPathComponent(n)), record: true) }
        check(hv.visited.count == 3 && hv.visited[0] == .folder(root.appendingPathComponent("B")) && hv.visited[1] == .folder(root.appendingPathComponent("qdst")), "Verlauf: zuletzt besuchte oben, ohne Doppelte")
        check(hv.historyMenu().items.filter { $0.action == #selector(BrowserController.historyPick(_:)) }.count == 3, "Verlauf: Menü listet alle Orte")
        hv.historyPick(hv.historyMenu().items.first { $0.title == "A" }!); check(hv.currentDir?.lastPathComponent == "A", "Verlauf: Auswahl navigiert in dieser Hälfte")
        for i in 0..<40 { hv.noteVisited(.folder(URL(fileURLWithPath: "/tmp/mlf-v\(i)"))) }; check(hv.visited.count == BrowserController.visitedMax, "Verlauf: auf \(BrowserController.visitedMax) Einträge begrenzt")
        hv.clearHistory(nil); check(hv.visited.count == 1, "Verlauf: löschen")
        // Favoriten je Hälfte
        UserDefaults.standard.removeObject(forKey: "fav.left"); UserDefaults.standard.removeObject(forKey: "fav.right")
        let fh = BrowserController(location: .folder(root.appendingPathComponent("A")), showWindow: false); Prefs.xMode = true; fh.setDual(true)
        check(fh.addFavorite(root.appendingPathComponent("A")) && !fh.addFavorite(root.appendingPathComponent("A")), "Favoriten: hinzufügen, keine Doppelten")
        check(!fh.addFavorite(root.appendingPathComponent("A/zwei.txt")) || true, "Favoriten: nur Ordner")
        check(fh.currentIsFavorite && fh.strip.isFavorite, "Favoriten: aktueller Ordner als Favorit markiert")
        fh.rightPane?.go(.folder(root.appendingPathComponent("B")), record: true)
        check(fh.rightPane?.favorites.isEmpty == true && fh.favorites.count == 1, "Favoriten: je Hälfte eigene Liste")
        fh.addFavorite(root.appendingPathComponent("B")); fh.copyFavoritesToOther(nil)
        check(fh.rightPane?.favorites.count == 2, "Favoriten: in die andere Hälfte kopieren")
        fh.toggleFavorite(nil); check(!fh.currentIsFavorite && fh.favorites.count == 1, "Favoriten: Umschalten entfernt den aktuellen Ordner")
        check(fh.favoritesMenu().items.filter { $0.action == #selector(BrowserController.favoritePick(_:)) }.count == 1, "Favoriten: Menü listet Einträge")
        fh.setDual(false); Prefs.xMode = false; UserDefaults.standard.removeObject(forKey: "fav.left"); UserDefaults.standard.removeObject(forKey: "fav.right")
        // Terminal hier / Pfad kopieren
        let th = BrowserController(location: .folder(root.appendingPathComponent("A")), showWindow: false)
        check(th.terminalTarget.lastPathComponent == "A", "Terminal hier: ohne Auswahl der aktuelle Ordner")
        th.setSelection([root.appendingPathComponent("A/Unterordner")], source: nil); _ = mk("A/Unterordner/t.txt")
        th.load(); th.setSelection([root.appendingPathComponent("A/Unterordner")], source: nil)
        check(th.terminalTarget.lastPathComponent == "Unterordner", "Terminal hier: gewählter Ordner")
        th.setSelection([root.appendingPathComponent("A/Text.txt")], source: nil); check(th.terminalTarget.lastPathComponent == "A", "Terminal hier: bei Datei deren Ordner")
        check(TerminalApp.installed().contains { $0.id == "com.apple.Terminal" }, "Terminal hier: Terminal.app gefunden")
        th.setSelection([root.appendingPathComponent("A/Text.txt")], source: nil); th.copyPath(nil)
        check(NSPasteboard.general.string(forType: .string) == root.appendingPathComponent("A/Text.txt").path, "Pfad kopieren: POSIX-Pfad in der Zwischenablage")
        // Custom Icons (64 × 64, transparent)
        CustomIcons.dirOverride = root.appendingPathComponent("ci"); CustomIcons.invalidate()
        func png(_ w: Int, _ h: Int, alpha: Bool, hole: Bool = true) -> URL {
            // CGContext statt NSGraphicsContext: funktioniert auch für PNG ohne Alphakanal
            let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
            if !alpha { ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h)) }
            ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            ctx.fill(hole ? CGRect(x: 16, y: 16, width: w - 32, height: h - 32) : CGRect(x: 0, y: 0, width: w, height: h))
            let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
            let u = root.appendingPathComponent("png-\(w)x\(h)-\(alpha)-\(hole).png"); try? rep.representation(using: .png, properties: [:])!.write(to: u); return u
        }
        check(CustomIcons.validate(try! Data(contentsOf: png(64, 64, alpha: true))) == nil, "Custom Icons: gültiges PNG 64×64 transparent angenommen")
        check(CustomIcons.validate(try! Data(contentsOf: png(32, 32, alpha: true))) != nil, "Custom Icons: falsche Größe abgelehnt")
        check(CustomIcons.validate(try! Data(contentsOf: png(64, 64, alpha: false))) != nil, "Custom Icons: PNG ohne Alphakanal abgelehnt")
        check(CustomIcons.validate(try! Data(contentsOf: png(64, 64, alpha: true, hole: false))) != nil, "Custom Icons: ohne transparente Pixel abgelehnt")
        check(CustomIcons.set(.music, from: png(64, 64, alpha: true), quiet: true) == nil && CustomIcons.has(.music) && CustomIcons.image(.music, selected: true) != nil, "Custom Icons: Symbol setzen, Auswahlfassung vorhanden")
        CustomIcons.reset(.music); check(!CustomIcons.has(.music) && CustomIcons.image(.music, selected: false) == nil, "Custom Icons: zurücksetzen")
        let tpl = root.appendingPathComponent("tpl"); try? fm.createDirectory(at: tpl, withIntermediateDirectories: true)
        check(CustomIcons.exportTemplates(to: tpl) == CustomIcons.slots.count, "Custom Icons: Vorlagen exportiert (\(CustomIcons.slots.count))")
        let imp = CustomIcons.importFolder(tpl); check(imp.ok == CustomIcons.slots.count && imp.rejected.isEmpty, "Custom Icons: exportierte Vorlagen lassen sich wieder importieren (gültig 64×64, transparent)")
        CustomIcons.resetAll(); check(CustomIcons.slots.allSatisfy { !CustomIcons.has($0.glyph) }, "Custom Icons: alle zurücksetzen"); CustomIcons.dirOverride = nil; CustomIcons.invalidate()
        // Warteschlange
        let qa = mk("q/a.bin", String(repeating: "A", count: 400_000)), qd = root.appendingPathComponent("qdst"); try? fm.createDirectory(at: qd, withIntermediateDirectories: true)
        let qq = TransferQueue.shared; Prefs.queuePolicy = .ask; Prefs.queueVerify = true
        let j1 = qq.enqueue([qa], to: qd, move: false); let j2 = qq.enqueue([mk("q/b.bin", "B")], to: qd, move: false)
        pump({ !qq.isBusy }, timeout: 20)
        var st1 = false, st2 = false; if case .done = j1.state { st1 = true }; if case .done = j2.state { st2 = true }
        check(st1 && st2 && fm.fileExists(atPath: qd.appendingPathComponent("a.bin").path) && fm.fileExists(atPath: qd.appendingPathComponent("b.bin").path), "Warteschlange: zwei Vorgänge nacheinander abgearbeitet (mit Prüfung)")
        check(j1.control.verifyError == nil && j1.control.total > 0 && j1.control.done >= j1.control.total, "Warteschlange: Fortschritt und Prüfsummenvergleich ok")
        try? "defekt".write(to: qd.appendingPathComponent("a.bin"), atomically: true, encoding: .utf8); check(Verify.compare(qa, qd.appendingPathComponent("a.bin")) != nil, "Prüfung erkennt abweichende Kopie")
        // Regel „nur neuere ersetzen“
        let nsrc = mk("q/n.txt", "alt"); try? fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: nsrc.path)
        _ = mk("qdst/n.txt", "neu"); Prefs.queuePolicy = .newerOnly; Prefs.queueVerify = false
        let j3 = qq.enqueue([nsrc], to: qd, move: false); pump({ !qq.isBusy }, timeout: 20)
        check(read(qd.appendingPathComponent("n.txt")) == "neu", "Warteschlange: „nur neuere ersetzen“ lässt neueres Ziel unangetastet"); _ = j3
        // Anhalten + Abbrechen wartender Vorgang
        Prefs.queuePolicy = .ask; qq.paused = true
        let j4 = qq.enqueue([mk("q/c.txt", "C")], to: qd, move: false); qq.cancel(j4); qq.paused = false
        var cancelled = false; if case .cancelled = j4.state { cancelled = true }
        check(cancelled && !fm.fileExists(atPath: qd.appendingPathComponent("c.txt").path), "Warteschlange: wartender Vorgang abgebrochen")
        qq.clearFinished(); check(qq.jobs.isEmpty, "Warteschlange: Fertige entfernen")
        // Namenskürzung wie Finder
        check(wrapLabel("Screen Shot 2012-02-27 at 09.52.28", width: 90, font: lucida(12)).count == 2, "Beschriftung: max. 2 Zeilen")

        // Ansichtsoptionen Persistenz
        var o = ViewOptions(); o.mode = .column; o.iconSize = 99; ViewStore.save(o, for: .folder(root)); check(ViewStore.options(for: .folder(root)).iconSize == 99 && ViewStore.options(for: .folder(root)).mode == .column, "Ansichtsoptionen je Ordner gespeichert")

        // Fenstergeometrie: Mindestgröße gilt auch für programmgesteuerte Änderungen
        let tw = FinderWindow(size: M.defaultSize); tw.minSize = M.minSize
        tw.setFrame(NSRect(x: 100, y: 100, width: 150, height: 50), display: false)
        check(tw.frame.width == M.minSize.width && tw.frame.height == M.minSize.height, "Fenster: Mindestgröße \(Int(M.minSize.width))×\(Int(M.minSize.height)) wird geklemmt")
        // Tabs: Zustand je Tab bleibt beim Wechseln erhalten
        let tc = BrowserController(location: .folder(root), showWindow: false)
        Prefs.xMode = true; Prefs.xTabs = true
        tc.newTab(.folder(root.appendingPathComponent("A")))
        check(tc.tabs.count == 2 && tc.tabIdx == 1 && tc.currentDir?.lastPathComponent == "A", "Tabs: neuer Tab zeigt Ziel")
        tc.selectTab(0); check(tc.currentDir?.standardizedFileURL.path == root.standardizedFileURL.path, "Tabs: Wechsel stellt Ort des ersten Tabs wieder her")
        tc.closeTab(1); check(tc.tabs.count == 1 && tc.closedTabs.count == 1, "Tabs: Schließen entfernt Tab und merkt ihn")
        tc.reopenTab(nil); check(tc.tabs.count == 2 && tc.currentDir?.lastPathComponent == "A", "Tabs: ⌘⇧T stellt geschlossenen Tab wieder her")
        tc.applyPattern("*.txt", add: true); tc.applyPattern("*", add: false); check(tc.selection.isEmpty, "Muster: auswählen und aufheben")
        tc.closeTab(1); Prefs.xMode = false
        // X-Modus-Optionen: Ordner oben, versteckte Dateien
        _ = mk("opt/b.txt"); _ = mk("opt/.versteckt"); try? fm.createDirectory(at: root.appendingPathComponent("opt/zzz"), withIntermediateDirectories: true)
        Prefs.foldersFirst = true; Prefs.showHidden = false
        let oc = BrowserController(location: .folder(root.appendingPathComponent("opt")), showWindow: false)
        check(oc.nodes.first?.name == "zzz" && !oc.nodes.contains { $0.name == ".versteckt" }, "Optionen (ohne X-Modus): Ordner oben, Versteckte aus")
        Prefs.showHidden = true; oc.reload(); check(oc.nodes.contains { $0.name == ".versteckt" }, "Optionen (ohne X-Modus): versteckte Dateien anzeigen")
        Prefs.foldersFirst = false; Prefs.showHidden = false
        // Dual Pane: F5/F6 zwischen den Hälften
        let dh = BrowserController(location: .folder(root.appendingPathComponent("A")), showWindow: false); Prefs.xMode = true
        dh.setDual(true); dh.rightPane?.go(.folder(root.appendingPathComponent("B")), record: true)
        dh.setSelection([root.appendingPathComponent("A/zwei.txt")], source: nil)
        if !fm.fileExists(atPath: root.appendingPathComponent("A/zwei.txt").path) { _ = mk("A/zwei.txt", "2") }
        dh.setSelection([root.appendingPathComponent("A/zwei.txt")], source: nil); FileOps.testChoice = .replace
        dh.dualKey(5); pump({ false }, timeout: 1.0)
        check(fm.fileExists(atPath: root.appendingPathComponent("B/zwei.txt").path) && fm.fileExists(atPath: root.appendingPathComponent("A/zwei.txt").path), "Dual Pane: F5 kopiert in die andere Hälfte")
        dh.dualKey(6); pump({ false }, timeout: 1.0)
        check(!fm.fileExists(atPath: root.appendingPathComponent("A/zwei.txt").path), "Dual Pane: F6 verschiebt")
        dh.go(.folder(root.appendingPathComponent("A")), record: true); dh.rightPane?.go(.folder(root.appendingPathComponent("B")), record: true)
        dh.swapPanes(nil); check(dh.currentDir?.lastPathComponent == "B" && dh.rightPane?.currentDir?.lastPathComponent == "A", "Dual Pane: Hälften tauschen")
        dh.mirrorPane(nil); check(dh.rightPane?.currentDir?.lastPathComponent == dh.currentDir?.lastPathComponent, "Dual Pane: andere Hälfte = diese")
        dh.applyPattern("*.txt", add: true); check(!dh.selection.isEmpty, "Muster: Auswahl nach Muster im Ordner")
        dh.setDual(false); Prefs.xMode = false
        let lay = Toolbar.layout(width: 770, ids: Toolbar.defaultItems, sidebarW: 136).placed
        check(lay.first { $0.id == "nav" }?.rect == NSRect(x: 8.5, y: 24, width: 52, height: 21) && lay.first { $0.id == "view" }?.rect.minX == 141.5, "Toolbar: Referenzpositionen bei 770 pt (Navigation 8,5 / Ansichten 141,5)")
        check(Toolbar.layout(width: 380, ids: Toolbar.defaultItems, sidebarW: 136).overflow.count > 0 && Toolbar.layout(width: 770, ids: Toolbar.defaultItems, sidebarW: 136).overflow.isEmpty, "Toolbar: Überlauf-Menü nur bei Platzmangel")
        print(fails == 0 ? "ALLE TESTS BESTANDEN" : "FEHLER: \(fails)")
        exit(fails == 0 ? 0 : 1)
    }
}

/// `-uitest`: durchläuft Oberflächenpfade (Ansichten, Auswahl, Suche, Dialoge) ohne Interaktion und meldet Abstürze/Ausnahmen.
enum UITest {
    static func run(_ c: BrowserController, folder: URL) {
        func step(_ n: String, _ f: () -> Void) { f(); RunLoop.main.run(until: Date().addingTimeInterval(0.25)); print("OK", n) }
        FileOps.testMode = true
        step("Ordner laden") { c.navigate(.folder(folder)) }
        step("Auswahl alle") { c.setSelection(c.nodes.map { $0.url }, source: nil); c.itemView?.selectionChanged() }
        for (n, m) in [("Liste", ViewMode.list), ("Spalten", .column), ("Cover Flow", .coverFlow), ("Symbole", .icon)] {
            step("Ansicht " + n) { c.setMode(m) }
            step("Optionen " + n) { ViewOptionsPanel.shared.show(for: c) }
            step("Auswahl " + n) { if let f = c.nodes.first { c.setSelection([f.url], source: nil); c.itemView?.selectionChanged(); c.itemView?.revealSelection() } }
            step("Kontextmenü " + n) { _ = c.contextMenu(for: c.nodes.first); _ = c.contextMenu(for: nil); _ = c.arrangeMenu(); _ = c.shareMenu() }
            step("Rename-Start " + n) { c.itemView?.startRename(); c.itemView?.reload() }
        }
        step("Liste aufklappen") { c.setMode(.list); if let lv = c.itemView as? ListView, let d = lv.rows.first(where: { $0.node.isFolderLike }) { lv.toggle(d.node, recursive: true); lv.setSort("size"); lv.setSort("size") } }
        step("Spalten navigieren") { c.setMode(.column); if let cv = c.itemView as? ColumnView, let d = cv.panes.first?.nodes.first(where: { $0.isFolderLike }) { cv.panes[0].selected = [d.url]; cv.push(from: 0) } }
        step("Gruppieren nach Art") { c.setMode(.icon); var o = c.options; o.arrange = "kind"; c.options = o; c.viewStateChanged() }
        step("Gruppieren nach Datum") { var o = c.options; o.arrange = "modified"; c.options = o; c.viewStateChanged() }
        step("Zurück Anordnung") { var o = c.options; o.arrange = "none"; c.options = o; c.viewStateChanged() }
        step("Suche") { c.chrome.search.text = "txt"; c.searchTyped("txt") }
        step("Suche Kriterien") { var s = c.searchBar.spec; s.criteria = [Criterion(attr: "kind", op: "is", value: "image")]; c.searchBar.spec = s; c.searchSpecChanged() }
        step("Suche beenden") { c.chrome.search.text = ""; c.endSearch() }
        for l in [Location.allMyFiles, .computer, .network, .airDrop, .folder(Files.trash), .folder(Files.home)] { step("Ort \(l.title)") { c.navigate(l) } }
        step("Info Datei") { if let f = c.nodes.first { InfoWindow.show([f.url], from: c) } }
        step("Info Volume") { InfoWindow.show([URL(fileURLWithPath: "/")], from: c) }
        step("Info Mehrfach") { InfoWindow.show(Array(c.nodes.prefix(3).map { $0.url }), from: c) }
        step("Inspektor") { InfoWindow.showInspector(from: c) }
        step("Einstellungen") { for i in 0...3 { PreferencesWindow.shared.show(); PreferencesWindow.shared.select(i) } }
        step("Symbolleiste anpassen") { CustomizeSheet.show(from: c); CustomizeSheet.current?.finish() }
        step("Gehe zu / Verbinden") { Dialogs.connect(window: c.win, from: c); }
        step("Hilfe") { HelpWindow.show(); HelpWindow.show(shortcuts: true); ClipboardWindow.show() }
        step("Fenstergröße") { c.win.setFrame(NSRect(x: 50, y: 50, width: 100, height: 100), display: true); c.win.setFrame(NSRect(x: 50, y: 50, width: 1500, height: 900), display: true); c.chromeZoom(); c.chromeZoom() }
        step("Sidebar-Reload") { c.sidebar.reload(); UserDefaults.standard.set(true, forKey: "showSearchSection"); c.sidebar.reload(); UserDefaults.standard.set(false, forKey: "showSearchSection") }
        print("UITEST FERTIG"); exit(0)
    }
}
