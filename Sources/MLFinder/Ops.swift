import AppKit
import Darwin

extension Notification.Name { static let fsChanged = Notification.Name("MLFSChanged") }

// MARK: Fortschrittsfenster (F-15)

final class ProgressPanel: NSObject {
    let win: NSPanel
    let bar = NSProgressIndicator()
    let title = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    var cancelled = false
    private var shown = false

    init(title t: String) {
        win = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 104), styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        win.title = ""
        let v = win.contentView!
        title.stringValue = t; title.font = lucida(12, bold: true); title.frame = NSRect(x: 16, y: 70, width: 388, height: 17)
        bar.style = .bar; bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 1; bar.frame = NSRect(x: 16, y: 46, width: 300, height: 14)
        detail.font = lucida(10); detail.textColor = .secondaryLabelColor; detail.frame = NSRect(x: 16, y: 20, width: 388, height: 14)
        let b = NSButton(title: "✕", target: self, action: #selector(cancel)); b.bezelStyle = .circular; b.frame = NSRect(x: 372, y: 38, width: 28, height: 28)
        b.toolTip = L("Abbrechen", "Stop")
        [title, bar, detail, b].forEach { v.addSubview($0) }
        win.center()
    }
    @objc func cancel() { cancelled = true }
    /// Erscheint erst nach 0,5 s (kurze Vorgänge bleiben unauffällig).
    func scheduleShow() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in if let s = self, !s.closed, !s.quiet { s.shown = true; s.win.makeKeyAndOrderFront(nil) } } }
    var closed = false
    var quiet = false
    func update(_ f: Double, _ text: String) { DispatchQueue.main.async { self.bar.doubleValue = f; self.detail.stringValue = text } }
    func close() { closed = true; DispatchQueue.main.async { self.win.orderOut(nil) } }
}

// MARK: Kopieren/Bewegen mit copyfile(3)

private final class CopyCtx {
    var done: Int64 = 0, total: Int64 = 1, fileBase: Int64 = 0
    var cancelled: () -> Bool = { false }
    var paused: () -> Bool = { false }
    var report: (Int64, Int64) -> Void = { _, _ in }
}

private let copyCB: copyfile_callback_t = { what, stage, state, src, dst, ctx in
    guard let ctx else { return Int32(COPYFILE_CONTINUE) }
    let c = Unmanaged<CopyCtx>.fromOpaque(ctx).takeUnretainedValue()
    while c.paused() && !c.cancelled() { usleep(100_000) }      // Pause der Warteschlange
    if c.cancelled() { return Int32(COPYFILE_QUIT) }
    if what == Int32(COPYFILE_COPY_DATA) && stage == Int32(COPYFILE_PROGRESS) {
        var n: off_t = 0; copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &n)
        c.report(c.done + Int64(n), c.total)
    } else if what == Int32(COPYFILE_COPY_DATA) && stage == Int32(COPYFILE_FINISH) {
        var n: off_t = 0; copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &n)
        c.done += Int64(n)
    }
    return Int32(COPYFILE_CONTINUE)
}

enum Choice { case replace, keepBoth, skip, stop, merge }
/// Regel für Namenskonflikte bei Vorgängen der Warteschlange
enum ConflictPolicy: String, CaseIterable {
    case ask, replace, keepBoth, skip, newerOnly
    var title: String { switch self { case .ask: return L("Nachfragen", "Ask"); case .replace: return L("Immer ersetzen", "Always replace"); case .keepBoth: return L("Beide behalten", "Keep both"); case .skip: return L("Vorhandene überspringen", "Skip existing"); case .newerOnly: return L("Nur neuere ersetzen", "Replace only if newer") } }
}
/// Gemeinsamer Zustand eines Vorgangs für die Warteschlange (Fortschritt, Abbruch, Pause, Fehler)
final class TransferControl {
    var cancelled = false, paused = false
    var done: Int64 = 0, total: Int64 = 0
    var error: String?
    var verifyError: String?
}

/// Alle Dateivorgänge. Registrieren Undo/Redo (F-16) und melden Änderungen per Notification.
final class FileOps: NSObject {
    static let shared = FileOps()
    let undoManager: UndoManager = { let u = UndoManager(); u.levelsOfUndo = 50; return u }()

    // MARK: Undo-Hilfe
    func register(_ name: String, undo: @escaping () -> Void, redo: @escaping () -> Void) {
        undoManager.registerUndo(withTarget: self) { s in undo(); s.register(name, undo: redo, redo: undo); s.changed() }
        if !undoManager.isUndoing && !undoManager.isRedoing { undoManager.setActionName(name) }
        else { undoManager.setActionName(name) }
    }
    func changed() { NotificationCenter.default.post(name: .fsChanged, object: nil) }

    static var testMode = false
    static var testChoice: Choice?
    static var testLog: [String] = []
    func alert(_ title: String, _ info: String = "", window: NSWindow? = nil) {
        if FileOps.testMode { FileOps.testLog.append(title + " " + info); return }
        let a = NSAlert(); a.messageText = title; a.informativeText = info; a.alertStyle = .warning; a.addButton(withTitle: "OK"); a.runModal()
    }
    static func nameList(_ u: [URL]) -> String { u.count == 1 ? "„\(u[0].lastPathComponent)“" : L("\(u.count) Objekte", "\(u.count) items") }

    // MARK: Größe berechnen (A-12, abbrechbar)
    static func totalSize(_ urls: [URL]) -> Int64 {
        var t: Int64 = 0
        for u in urls {
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .totalFileSizeKey, .fileSizeKey])
            if v?.isDirectory == true, let e = Files.fm.enumerator(at: u, includingPropertiesForKeys: [.totalFileSizeKey, .fileSizeKey], options: []) {
                for case let f as URL in e { let w = try? f.resourceValues(forKeys: [.totalFileSizeKey, .fileSizeKey]); t += Int64(w?.totalFileSize ?? w?.fileSize ?? 0) }
            } else { t += Int64(v?.totalFileSize ?? v?.fileSize ?? 0) }
        }
        return max(t, 1)
    }

    // MARK: Konflikt-Dialog (F-13/F-14)
    private var applyAll: Choice?
    private var policy: ConflictPolicy = .ask
    private func ask(_ src: URL, _ dst: URL, move: Bool, canMerge: Bool, many: Bool) -> Choice {
        if let a = applyAll { return a }
        switch policy {
        case .ask: break
        case .replace: return canMerge ? .merge : .replace
        case .keepBoth: return .keepBoth
        case .skip: return canMerge ? .merge : .skip
        case .newerOnly:
            if canMerge { return .merge }
            let sd = (try? src.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let dd = (try? dst.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture
            return sd > dd ? .replace : .skip
        }
        if let t = FileOps.testChoice { return (t == .replace && canMerge) ? .merge : t }
        var result: Choice = .stop
        DispatchQueue.main.sync {
            let a = NSAlert()
            let nm = dst.lastPathComponent
            a.messageText = canMerge ? L("Ein Objekt mit dem Namen „\(nm)“ ist an diesem Ort bereits vorhanden. Möchten Sie die Ordner zusammenführen?", "An item named \u{201C}\(nm)\u{201D} already exists in this location. Do you want to merge the folders?")
                                     : L("Ein Objekt mit dem Namen „\(nm)“ ist an diesem Ort bereits vorhanden. Möchten Sie es durch das Objekt ersetzen, das Sie \(move ? "bewegen" : "kopieren")?", "An item named \u{201C}\(nm)\u{201D} already exists in this location. Do you want to replace it with the one you\u{2019}re \(move ? "moving" : "copying")?")
            a.informativeText = canMerge ? L("Dabei werden gleichnamige Dateien durch die neueren/anderen ersetzt, sofern Sie dies bestätigen.", "Items with the same names in the merged folders will ask for confirmation.")
                                         : L("Dieses Objekt wurde am \(Files.dateString((try? dst.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate)) geändert.", "The existing item was modified \(Files.dateString((try? dst.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate)).")
            a.addButton(withTitle: canMerge ? L("Zusammenführen", "Merge") : L("Ersetzen", "Replace"))
            a.addButton(withTitle: L("Beide behalten", "Keep Both"))
            a.addButton(withTitle: many ? L("Überspringen", "Skip") : L("Stopp", "Stop"))
            if many { a.addButton(withTitle: L("Stopp", "Stop")) }
            if many { a.showsSuppressionButton = true; a.suppressionButton?.title = L("Auf alle anwenden", "Apply to All") }
            let r = a.runModal()
            switch r {
            case .alertFirstButtonReturn: result = canMerge ? .merge : .replace
            case .alertSecondButtonReturn: result = .keepBoth
            case .alertThirdButtonReturn: result = many ? .skip : .stop
            default: result = .stop
            }
            if many && a.suppressionButton?.state == .on && result != .stop { applyAll = result }
        }
        return result
    }

    // MARK: Kopieren / Bewegen
    /// Rückgabe: erzeugte Ziel-URLs (je Quelle) über `done`.
    func transfer(_ sources: [URL], to dir: URL, move: Bool, forceCopyNames: Bool = false, policy pol: ConflictPolicy = .ask, verify: Bool = false, control: TransferControl? = nil, done: (([URL]) -> Void)? = nil) {
        if control == nil, TransferQueue.shared.isBusy { TransferQueue.shared.enqueue(sources, to: dir, move: move, done: done); return }   // nie zwei Vorgänge gleichzeitig (gemeinsamer Konfliktzustand)
        // Plausibilität (§7.1): nicht in sich selbst, schreibbar
        let dirStd = dir.standardizedFileURL
        for s in sources {
            let sp = s.standardizedFileURL.path
            if dirStd.path == sp || dirStd.path.hasPrefix(sp + "/") {
                alert(L("Der Vorgang kann nicht abgeschlossen werden, weil „\(s.lastPathComponent)“ nicht in sich selbst kopiert/bewegt werden kann.", "The operation can\u{2019}t be completed because you can\u{2019}t put \u{201C}\(s.lastPathComponent)\u{201D} into itself.")); return
            }
        }
        if !Files.fm.isWritableFile(atPath: dir.path) {
            alert(L("Der Vorgang kann nicht abgeschlossen werden, weil Sie nicht die nötigen Zugriffsrechte für „\(dir.lastPathComponent)“ haben.", "The operation can\u{2019}t be completed because you don\u{2019}t have permission to modify \u{201C}\(dir.lastPathComponent)\u{201D}.")); return
        }
        let panel = ProgressPanel(title: move ? L("Bewegen von \(FileOps.nameList(sources)) …", "Moving \(FileOps.nameList(sources))…") : L("Kopieren von \(FileOps.nameList(sources)) …", "Copying \(FileOps.nameList(sources))…"))
        panel.quiet = control != nil; panel.scheduleShow(); applyAll = nil; policy = pol
        DispatchQueue.global(qos: .userInitiated).async {
            let ctx = CopyCtx(); ctx.total = FileOps.totalSize(sources)
            ctx.cancelled = { panel.cancelled || (control?.cancelled ?? false) }
            ctx.paused = { control?.paused ?? false }
            control?.total = ctx.total
            ctx.report = { d, t in control?.done = d; control?.total = t; panel.update(Double(d) / Double(t), "\(Files.sizeString(d)) \(L("von", "of")) \(Files.sizeString(t))") }
            var created: [(src: URL, dst: URL, replacedBackup: URL?)] = []
            var failed: String?
            for s in sources {
                if panel.cancelled || (control?.cancelled ?? false) { break }
                var dst = dir.appendingPathComponent(s.lastPathComponent)
                var backup: URL?
                let sameFolder = s.deletingLastPathComponent().standardizedFileURL.path == dirStd.path
                if sameFolder && !move { dst = Files.unique(dst, suffix: L("Kopie", "copy")) }
                else if sameFolder && move { continue }
                else if Files.exists(dst) {
                    var isDirS: ObjCBool = false, isDirD: ObjCBool = false
                    Files.fm.fileExists(atPath: s.path, isDirectory: &isDirS); Files.fm.fileExists(atPath: dst.path, isDirectory: &isDirD)
                    let canMerge = isDirS.boolValue && isDirD.boolValue && !(try! s.resourceValues(forKeys: [.isPackageKey]).isPackage ?? false)
                    switch self.ask(s, dst, move: move, canMerge: canMerge, many: sources.count > 1) {
                    case .stop: panel.cancelled = true; continue
                    case .skip: continue
                    case .keepBoth: dst = Files.unique(dst, suffix: L("Kopie", "copy"))
                    case .merge:
                        if let err = self.merge(s, into: dst, move: move, ctx: ctx, many: sources.count > 1) { failed = err }
                        else { created.append((s, dst, nil)) }
                        continue
                    case .replace:
                        // atomar ersetzen: erst neben dem Ziel kopieren, dann tauschen
                        let tmp = dir.appendingPathComponent(".\(UUID().uuidString.prefix(8))-\(s.lastPathComponent)")
                        if let err = self.copyOne(s, tmp, ctx) { failed = err; try? Files.fm.removeItem(at: tmp); continue }
                        backup = Files.unique(Files.trash.appendingPathComponent(dst.lastPathComponent))
                        do { try Files.fm.createDirectory(at: Files.trash, withIntermediateDirectories: true); try Files.fm.moveItem(at: dst, to: backup!); try Files.fm.moveItem(at: tmp, to: dst) }
                        catch { failed = error.localizedDescription; try? Files.fm.removeItem(at: tmp); if let b = backup, !Files.exists(dst) { try? Files.fm.moveItem(at: b, to: dst) }; continue }
                        if move { try? Files.fm.removeItem(at: s) }
                        created.append((s, dst, backup)); continue
                    }
                }
                if move {
                    let sameVol = (try? s.resourceValues(forKeys: [.volumeURLKey]).volume) == (try? dir.resourceValues(forKeys: [.volumeURLKey]).volume)
                    if sameVol { do { try Files.fm.moveItem(at: s, to: dst); created.append((s, dst, nil)) } catch { failed = error.localizedDescription }; continue }
                    // anderes Volume: erst kopieren, Quelle erst nach Erfolg entfernen (§7.1)
                    if let err = self.copyOne(s, dst, ctx) { failed = err; if !Files.exists(dst) || panel.cancelled { try? Files.fm.removeItem(at: dst) }; continue }
                    do { try Files.fm.removeItem(at: s) } catch { failed = error.localizedDescription }
                    created.append((s, dst, nil))
                } else {
                    if let err = self.copyOne(s, dst, ctx) { failed = err; if panel.cancelled { try? Files.fm.removeItem(at: dst) }; continue }
                    created.append((s, dst, nil))
                }
            }
            if verify && !move { for c in created { if let e = Verify.compare(c.src, c.dst) { control?.verifyError = e; failed = (failed.map { $0 + "\n" } ?? "") + e } } }
            control?.error = failed
            panel.close()
            DispatchQueue.main.async {
                if let f = failed, !panel.cancelled, control == nil { self.alert(L("Der Vorgang konnte nicht abgeschlossen werden.", "The operation could not be completed."), f) }
                let c = created
                if !c.isEmpty {
                    if move { self.register(L("Bewegen von \(FileOps.nameList(c.map { $0.src }))", "Move of \(FileOps.nameList(c.map { $0.src }))"),
                                            undo: { for x in c { try? Files.fm.moveItem(at: x.dst, to: x.src) } }, redo: { for x in c { try? Files.fm.moveItem(at: x.src, to: x.dst) } }) }
                    else { self.register(L("Kopieren von \(FileOps.nameList(c.map { $0.src }))", "Copy of \(FileOps.nameList(c.map { $0.src }))"),
                                         undo: { for x in c { _ = try? Files.fm.trashItem(at: x.dst, resultingItemURL: nil) } }, redo: { for x in c { _ = try? Files.fm.copyItem(at: x.src, to: x.dst) } }) }
                }
                self.changed(); self.policy = .ask; done?(c.map { $0.dst })
            }
        }
    }

    private func copyOne(_ s: URL, _ d: URL, _ ctx: CopyCtx) -> String? {
        let st = copyfile_state_alloc(); defer { copyfile_state_free(st) }
        let p = Unmanaged.passUnretained(ctx).toOpaque()
        copyfile_state_set(st, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(copyCB, to: UnsafeRawPointer.self))
        copyfile_state_set(st, UInt32(COPYFILE_STATE_STATUS_CTX), p)
        let r = copyfile(s.path, d.path, st, copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW_SRC))
        if r != 0 { return ctx.cancelled() ? nil : (errno == ENOSPC ? L("Nicht genügend freier Speicherplatz auf dem Zielvolume.", "There is not enough free space on the destination volume.") : String(cString: strerror(errno))) }
        return nil
    }

    /// Ordner zusammenführen: gleichnamige Unterordner rekursiv, Dateikonflikte einzeln (F-14)
    private func merge(_ s: URL, into d: URL, move: Bool, ctx: CopyCtx, many: Bool) -> String? {
        var err: String?
        let kids = (try? Files.fm.contentsOfDirectory(at: s, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [])) ?? []
        for k in kids {
            let t = d.appendingPathComponent(k.lastPathComponent)
            if Files.exists(t) {
                let v = try? k.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]); let tv = try? t.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                let bothDirs = v?.isDirectory == true && tv?.isDirectory == true && v?.isPackage != true
                switch ask(k, t, move: move, canMerge: bothDirs, many: true) {
                case .stop: return nil
                case .skip: continue
                case .keepBoth: if let e = copyOne(k, Files.unique(t, suffix: L("Kopie", "copy")), ctx) { err = e } else if move { try? Files.fm.removeItem(at: k) }
                case .merge: if let e = merge(k, into: t, move: move, ctx: ctx, many: true) { err = e }
                case .replace:
                    do { _ = try Files.fm.trashItem(at: t, resultingItemURL: nil) } catch { err = error.localizedDescription; continue }
                    if let e = copyOne(k, t, ctx) { err = e } else if move { try? Files.fm.removeItem(at: k) }
                }
            } else if let e = copyOne(k, t, ctx) { err = e } else if move { try? Files.fm.removeItem(at: k) }
        }
        if move && err == nil { try? Files.fm.removeItem(at: s) }
        return err
    }

    // MARK: Duplizieren, Alias, Neuer Ordner, Umbenennen
    @discardableResult func duplicate(_ urls: [URL]) -> [URL] {
        var out: [(URL, URL)] = []
        for u in urls {
            let d = Files.unique(u, suffix: L("Kopie", "copy"))
            do { try Files.fm.copyItem(at: u, to: d); out.append((u, d)) } catch { alert(L("Das Objekt „\(u.lastPathComponent)“ konnte nicht dupliziert werden.", "\u{201C}\(u.lastPathComponent)\u{201D} could not be duplicated."), error.localizedDescription) }
        }
        if !out.isEmpty { register(L("Duplizieren von \(FileOps.nameList(out.map { $0.0 }))", "Duplicate of \(FileOps.nameList(out.map { $0.0 }))"), undo: { for x in out { _ = try? Files.fm.trashItem(at: x.1, resultingItemURL: nil) } }, redo: { for x in out { try? Files.fm.copyItem(at: x.0, to: x.1) } }) }
        changed(); return out.map { $0.1 }
    }
    @discardableResult func makeAlias(_ urls: [URL], in dir: URL? = nil) -> [URL] {
        var out: [URL] = []
        for u in urls {
            let d = Files.unique((dir ?? u.deletingLastPathComponent()).appendingPathComponent(u.lastPathComponent + " " + L("Alias", "alias")))
            if Alias.make(for: u, at: d) { out.append(d) } else { alert(L("Alias konnte nicht erstellt werden.", "The alias could not be created.")) }
        }
        if !out.isEmpty { register(L("Alias erstellen", "Make Alias"), undo: { for x in out { _ = try? Files.fm.trashItem(at: x, resultingItemURL: nil) } }, redo: {}) }
        changed(); return out
    }
    @discardableResult func newFolder(in dir: URL, name: String? = nil, with items: [URL] = []) -> URL? {
        let base = dir.appendingPathComponent(name ?? L("Ordner ohne Titel", "untitled folder"))
        let u = Files.unique(base, suffix: nil)
        do {
            try Files.fm.createDirectory(at: u, withIntermediateDirectories: false)
            for i in items { try Files.fm.moveItem(at: i, to: u.appendingPathComponent(i.lastPathComponent)) }
        } catch { alert(L("Der Ordner konnte nicht angelegt werden.", "The folder could not be created."), error.localizedDescription); return nil }
        register(items.isEmpty ? L("Neuer Ordner", "New Folder") : L("Neuer Ordner mit Auswahl", "New Folder with Selection"),
                 undo: { for i in items { try? Files.fm.moveItem(at: u.appendingPathComponent(i.lastPathComponent), to: i) }; _ = try? Files.fm.trashItem(at: u, resultingItemURL: nil) }, redo: {})
        changed(); return u
    }
    /// F-05: Namensprüfung inkl. reiner Groß-/Kleinschreibungsänderung
    func rename(_ u: URL, to raw: String) -> URL? {
        let n = raw.trimmingCharacters(in: .whitespaces)
        if n.isEmpty || n == u.lastPathComponent { return nil }
        if n.contains("/") || n.contains(":") { alert(L("Der Name „\(n)“ kann nicht verwendet werden.", "The name \u{201C}\(n)\u{201D} can\u{2019}t be used."), L("Namen dürfen keine Doppelpunkte oder Schrägstriche enthalten.", "Names can\u{2019}t contain colons or slashes.")); return nil }
        if n.utf8.count > 255 { alert(L("Der Name ist zu lang.", "The name is too long.")); return nil }
        let d = u.deletingLastPathComponent().appendingPathComponent(n)
        let caseOnly = d.path.lowercased() == u.path.lowercased()
        if Files.exists(d) && !caseOnly { alert(L("Der Name „\(n)“ ist bereits vergeben. Bitte wählen Sie einen anderen Namen.", "The name \u{201C}\(n)\u{201D} is already taken. Please choose a different name.")); return nil }
        if !u.pathExtension.isEmpty && (d.pathExtension != u.pathExtension) && Prefs.warnExt {
            let a = NSAlert()
            a.messageText = d.pathExtension.isEmpty ? L("Möchten Sie die Erweiterung „.\(u.pathExtension)“ wirklich entfernen?", "Are you sure you want to remove the extension \u{201C}.\(u.pathExtension)\u{201D}?") : L("Möchten Sie die Erweiterung wirklich von „.\(u.pathExtension)“ in „.\(d.pathExtension)“ ändern?", "Are you sure you want to change the extension from \u{201C}.\(u.pathExtension)\u{201D} to \u{201C}.\(d.pathExtension)\u{201D}?")
            a.informativeText = L("Das Dokument lässt sich eventuell nicht mehr öffnen.", "If you make this change, your document may open in a different application.")
            a.addButton(withTitle: L("Ändern in .\(d.pathExtension)", "Use .\(d.pathExtension)")); a.addButton(withTitle: L("Beibehalten .\(u.pathExtension)", "Keep .\(u.pathExtension)"))
            if a.runModal() != .alertFirstButtonReturn { return nil }
        }
        do {
            if caseOnly { let t = u.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString)"); try Files.fm.moveItem(at: u, to: t); try Files.fm.moveItem(at: t, to: d) }
            else { try Files.fm.moveItem(at: u, to: d) }
        } catch { alert(L("Das Objekt konnte nicht umbenannt werden.", "The item could not be renamed."), error.localizedDescription); return nil }
        register(L("Umbenennen von „\(u.lastPathComponent)“", "Rename of \u{201C}\(u.lastPathComponent)\u{201D}"), undo: { try? Files.fm.moveItem(at: d, to: u) }, redo: { try? Files.fm.moveItem(at: u, to: d) })
        changed(); return d
    }

    // MARK: Papierkorb (I-01…I-04)
    static let putBackKey = "putBack"
    @discardableResult func trash(_ urls: [URL]) -> Bool {
        var moved: [(URL, URL)] = []
        for u in urls {
            if (try? u.resourceValues(forKeys: [.isUserImmutableKey]).isUserImmutable) == true {
                let a = NSAlert(); a.messageText = L("Das Objekt „\(u.lastPathComponent)“ ist gesperrt.", "The item \u{201C}\(u.lastPathComponent)\u{201D} is locked."); a.informativeText = L("Möchten Sie es trotzdem in den Papierkorb legen?", "Are you sure you want to move it to the Trash?")
                a.addButton(withTitle: L("Fortfahren", "Continue")); a.addButton(withTitle: L("Abbrechen", "Cancel")); if a.runModal() != .alertFirstButtonReturn { continue }
            }
            var res: NSURL?
            do { try Files.fm.trashItem(at: u, resultingItemURL: &res); if let r = res as URL? { moved.append((u, r)); var d = UserDefaults.standard.dictionary(forKey: Self.putBackKey) as? [String: String] ?? [:]; d[r.path] = u.path; UserDefaults.standard.set(d, forKey: Self.putBackKey) } }
            catch {
                let e = error as NSError
                if e.code == NSFileWriteNoPermissionError || e.code == NSFileWriteVolumeReadOnlyError { alert(L("Das Objekt „\(u.lastPathComponent)“ kann nicht in den Papierkorb gelegt werden, weil Sie keine Zugriffsrechte haben.", "\u{201C}\(u.lastPathComponent)\u{201D} can\u{2019}t be moved to the Trash because you don\u{2019}t have permission."), error.localizedDescription) }
                else {
                    let a = NSAlert(); a.messageText = L("„\(u.lastPathComponent)“ kann nicht in den Papierkorb gelegt werden. Möchten Sie es sofort löschen?", "\u{201C}\(u.lastPathComponent)\u{201D} can\u{2019}t be moved to the Trash. Do you want to delete it immediately?"); a.informativeText = L("Dieser Vorgang kann nicht rückgängig gemacht werden.", "This item will be deleted immediately. You can\u{2019}t undo this action.")
                    a.addButton(withTitle: L("Abbrechen", "Cancel")); a.addButton(withTitle: L("Löschen", "Delete")); if a.runModal() == .alertSecondButtonReturn { do { try Files.fm.removeItem(at: u) } catch { alert(error.localizedDescription) } }
                }
            }
        }
        if !moved.isEmpty { register(L("Bewegen von \(FileOps.nameList(moved.map { $0.0 })) in den Papierkorb", "Move of \(FileOps.nameList(moved.map { $0.0 })) to Trash"), undo: { for x in moved { try? Files.fm.moveItem(at: x.1, to: x.0) } }, redo: { for x in moved { try? Files.fm.moveItem(at: x.0, to: x.1) } }) }
        changed(); return !moved.isEmpty
    }
    func putBack(_ urls: [URL]) {
        var d = UserDefaults.standard.dictionary(forKey: Self.putBackKey) as? [String: String] ?? [:]
        for u in urls {
            guard let orig = d[u.path] else { alert(L("„\(u.lastPathComponent)“ kann nicht zurückgelegt werden, weil der ursprüngliche Ort unbekannt ist.", "\u{201C}\(u.lastPathComponent)\u{201D} can\u{2019}t be put back because its original location is unknown.")); continue }
            var dest = URL(fileURLWithPath: orig)
            if !Files.exists(dest.deletingLastPathComponent()) { alert(L("„\(u.lastPathComponent)“ kann nicht zurückgelegt werden, weil der Ordner „\(dest.deletingLastPathComponent().lastPathComponent)“ nicht mehr existiert.", "\u{201C}\(u.lastPathComponent)\u{201D} can\u{2019}t be put back because its original folder no longer exists.")); continue }
            if Files.exists(dest) { dest = Files.unique(dest, suffix: L("Kopie", "copy")) }
            do { try Files.fm.moveItem(at: u, to: dest); d[u.path] = nil } catch { alert(error.localizedDescription) }
        }
        UserDefaults.standard.set(d, forKey: Self.putBackKey); changed()
    }
    static var trashFolders: [URL] {
        var r = [Files.trash]
        for v in Files.volumes() where v.path != "/" { r.append(v.appendingPathComponent(".Trashes/\(getuid())")) }
        return r.filter { Files.exists($0) }
    }
    static var trashIsEmpty: Bool { trashFolders.allSatisfy { ((try? Files.fm.contentsOfDirectory(atPath: $0.path)) ?? []).filter { $0 != ".DS_Store" }.isEmpty } }
    func emptyTrash(secure: Bool = false, skipWarning: Bool = false) {
        let items = FileOps.trashFolders.flatMap { f in ((try? Files.fm.contentsOfDirectory(at: f, includingPropertiesForKeys: nil, options: [])) ?? []).filter { $0.lastPathComponent != ".DS_Store" } }
        if items.isEmpty { return }
        if Prefs.warnTrash && !skipWarning {
            let a = NSAlert(); a.messageText = L("Möchten Sie die Objekte im Papierkorb wirklich endgültig löschen?", "Are you sure you want to permanently erase the items in the Trash?")
            a.informativeText = L("Dieser Vorgang kann nicht rückgängig gemacht werden.", "You can\u{2019}t undo this action.")
            a.addButton(withTitle: L("Papierkorb entleeren", "Empty Trash")); a.addButton(withTitle: L("Abbrechen", "Cancel")); if a.runModal() != .alertFirstButtonReturn { return }
        }
        let panel = ProgressPanel(title: L("Papierkorb wird entleert …", "Emptying the Trash…")); panel.scheduleShow()
        DispatchQueue.global().async {
            var errors: [String] = []
            for (i, u) in items.enumerated() {
                if panel.cancelled { break }
                panel.update(Double(i) / Double(items.count), u.lastPathComponent)
                do { try Files.fm.removeItem(at: u) } catch {
                    // gesperrt: Sperre aufheben und erneut versuchen? Nein – wie im Original melden.
                    errors.append("„\(u.lastPathComponent)“: \(error.localizedDescription)")
                }
            }
            panel.close()
            DispatchQueue.main.async {
                if !errors.isEmpty { self.alert(L("Einige Objekte konnten nicht gelöscht werden (Teilfehler).", "Some items couldn\u{2019}t be removed (partial failure)."), errors.prefix(5).joined(separator: "\n")) }
                UserDefaults.standard.set([String: String](), forKey: Self.putBackKey)
                self.undoManager.removeAllActions(); self.changed()
            }
        }
    }
    /// I-04: Historischer Befehl. Auf APFS/SSD ist garantiertes Überschreiben nicht möglich → ehrlicher Hinweis, normales Löschen (§12).
    func secureEmptyTrash() {
        let a = NSAlert(); a.messageText = L("Papierkorb sicher entleeren wird auf diesem Datenträger nicht unterstützt.", "Secure Empty Trash is not supported on this volume.")
        a.informativeText = L("Auf APFS und Flash-Speicher kann ein Überschreiben nicht garantieren, dass Daten physisch vernichtet werden. Die Objekte können stattdessen normal gelöscht werden; für Vertraulichkeit hilft die Verschlüsselung des Datenträgers (FileVault).", "On APFS and flash storage, overwriting can\u{2019}t guarantee that data is physically destroyed. The items can be erased normally instead; use volume encryption (FileVault) for confidentiality.")
        a.addButton(withTitle: L("Normal entleeren", "Empty Normally")); a.addButton(withTitle: L("Abbrechen", "Cancel"))
        if a.runModal() == .alertFirstButtonReturn { emptyTrash(skipWarning: true) }
    }

    // MARK: Komprimieren (F-17)
    func compress(_ urls: [URL], completion: @escaping ([URL]) -> Void) {
        guard let first = urls.first else { return }
        let dir = first.deletingLastPathComponent()
        let outBase = urls.count == 1 ? dir.appendingPathComponent(first.lastPathComponent + ".zip") : dir.appendingPathComponent(L("Archiv", "Archive") + ".zip")
        let out = Files.unique(outBase)
        let panel = ProgressPanel(title: L("Komprimieren von \(FileOps.nameList(urls)) …", "Compressing \(FileOps.nameList(urls))…")); panel.bar.isIndeterminate = true; panel.bar.startAnimation(nil); panel.scheduleShow()
        DispatchQueue.global().async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); var tmp: URL?
            if urls.count == 1 { p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, out.path] }
            else {
                let t = Files.fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(L("Archiv", "Archive")); tmp = t.deletingLastPathComponent()
                try? Files.fm.createDirectory(at: t, withIntermediateDirectories: true)
                for u in urls { try? Files.fm.copyItem(at: u, to: t.appendingPathComponent(u.lastPathComponent)) }
                p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", t.path, out.path]
            }
            var ok = false
            do { try p.run(); p.waitUntilExit(); ok = p.terminationStatus == 0 } catch {}
            if let tmp { try? Files.fm.removeItem(at: tmp) }
            panel.close()
            DispatchQueue.main.async {
                if ok { self.register(L("Komprimieren", "Compress"), undo: { _ = try? Files.fm.trashItem(at: out, resultingItemURL: nil) }, redo: {}) }
                else { self.alert(L("Die Auswahl konnte nicht komprimiert werden.", "The selection could not be compressed.")) }
                self.changed(); completion(ok ? [out] : [])
            }
        }
    }
    func uncompress(_ u: URL) {
        let ar = URL(fileURLWithPath: "/System/Library/CoreServices/Applications/Archive Utility.app")
        let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = false
        NSWorkspace.shared.open([u], withApplicationAt: ar, configuration: cfg) { _, _ in DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.changed() } }
    }

    // MARK: Auswerfen / Brennen
    func eject(_ u: URL) {
        DispatchQueue.global().async {
            var err: Error?
            do { try NSWorkspace.shared.unmountAndEjectDevice(at: u) } catch { err = error }
            DispatchQueue.main.async {
                if let err { self.alert(L("Das Volume „\(u.lastPathComponent)“ konnte nicht ausgeworfen werden, weil es noch verwendet wird.", "The disk \u{201C}\(u.lastPathComponent)\u{201D} wasn\u{2019}t ejected because one or more programs may be using it."), err.localizedDescription) }
                self.changed()
            }
        }
    }
    func newBurnFolder(in dir: URL) -> URL? {
        let u = Files.unique(dir.appendingPathComponent(L("Brennordner", "Burn Folder")).appendingPathExtension(Files.burnExt))
        do { try Files.fm.createDirectory(at: u, withIntermediateDirectories: false) } catch { alert(error.localizedDescription); return nil }
        changed(); return u
    }
    func burn(_ folder: URL, window: NSWindow?) {
        let kids = (try? Files.fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        // Gesamtumfang und fehlende Originale (X-10)
        var total: Int64 = 0, missing: [String] = []
        for k in kids {
            if (try? k.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == true { if let t = Alias.resolve(k) { total += FileOps.totalSize([t]) } else { missing.append(k.lastPathComponent) } }
            else { total += FileOps.totalSize([k]) }
        }
        if !missing.isEmpty { alert(L("Einige Originale fehlen und können nicht gebrannt werden.", "Some originals are missing and can\u{2019}t be burned."), missing.joined(separator: ", ")); return }
        let drives = Process(); drives.executableURL = URL(fileURLWithPath: "/usr/bin/drutil"); drives.arguments = ["list"]
        let pipe = Pipe(); drives.standardOutput = pipe; try? drives.run(); drives.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if !out.contains("Vendor") && !out.contains("1 ") { alert(L("Es wurde kein Brenner gefunden.", "No burner was found."), L("Schließen Sie ein optisches Laufwerk an und legen Sie einen Rohling ein. Gesamtumfang des Brennordners: \(Files.sizeString(total)).", "Connect an optical drive and insert a blank disc. Burn folder size: \(Files.sizeString(total)).")); return }
        let a = NSAlert(); a.messageText = L("Möchten Sie „\(folder.deletingPathExtension().lastPathComponent)“ (\(Files.sizeString(total))) auf Disc brennen?", "Burn \u{201C}\(folder.deletingPathExtension().lastPathComponent)\u{201D} (\(Files.sizeString(total))) to disc?")
        a.addButton(withTitle: L("Brennen", "Burn")); a.addButton(withTitle: L("Abbrechen", "Cancel")); if a.runModal() != .alertFirstButtonReturn { return }
        let stage = Files.fm.temporaryDirectory.appendingPathComponent("burn-\(UUID().uuidString)"); try? Files.fm.createDirectory(at: stage, withIntermediateDirectories: true)
        for k in kids { let t = (try? k.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == true ? (Alias.resolve(k) ?? k) : k; try? Files.fm.copyItem(at: t, to: stage.appendingPathComponent(t.lastPathComponent)) }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/drutil"); p.arguments = ["burn", "-eject", stage.path]
        DispatchQueue.global().async { try? p.run(); p.waitUntilExit(); let st = p.terminationStatus; try? Files.fm.removeItem(at: stage); DispatchQueue.main.async { if st != 0 { self.alert(L("Das Brennen ist fehlgeschlagen.", "Burning failed."), "drutil: \(st)") } } }
    }
}


// MARK: Prüfung nach dem Kopieren (Größe + SHA-256)

import CryptoKit
enum Verify {
    /// nil = identisch; sonst Fehlertext
    static func compare(_ s: URL, _ d: URL) -> String? {
        let fm = Files.fm
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: s.path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue, (try? s.resourceValues(forKeys: [.isPackageKey]).isPackage) != true || true {
            guard let e = fm.enumerator(at: s, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []) else { return nil }
            for case let f as URL in e {
                let rel = String(f.path.dropFirst(s.path.count))
                let g = URL(fileURLWithPath: d.path + rel)
                if !Files.exists(g) { return L("Fehlt im Ziel: \(rel)", "Missing in destination: \(rel)") }
                if (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true, let err = fileCompare(f, g) { return err }
            }
            return nil
        }
        return fileCompare(s, d)
    }
    private static func fileCompare(_ a: URL, _ b: URL) -> String? {
        let sa = (try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1, sb = (try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -2
        if sa != sb { return L("Größe weicht ab: \(b.lastPathComponent)", "Size differs: \(b.lastPathComponent)") }
        guard let ha = hash(a), let hb = hash(b), ha == hb else { return L("Prüfsumme weicht ab: \(b.lastPathComponent)", "Checksum differs: \(b.lastPathComponent)") }
        return nil
    }
    private static func hash(_ u: URL) -> SHA256.Digest? {
        guard let h = try? FileHandle(forReadingFrom: u) else { return nil }
        defer { try? h.close() }
        var sha = SHA256()
        while true { guard let d = try? h.read(upToCount: 1 << 20), !d.isEmpty else { break }; sha.update(data: d) }
        return sha.finalize()
    }
}
