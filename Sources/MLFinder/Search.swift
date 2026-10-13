import AppKit

// MARK: Suchdefinition (S-01…S-09)

struct Criterion: Codable, Equatable {
    var attr: String        // kind, name, ext, modified, created, opened, size, label, content
    var op: String          // is, contains, begins, within, before, after, gt, lt
    var value: String
    static let attrs: [(String, String)] = [("kind", L("Art", "Kind")), ("name", L("Name", "Name")), ("content", L("Inhalt", "Contents")), ("ext", L("Erweiterung", "Extension")), ("modified", L("Änderungsdatum", "Last modified date")), ("created", L("Erstellungsdatum", "Created date")), ("opened", L("Datum des letzten Öffnens", "Last opened date")), ("size", L("Dateigröße", "File size")), ("label", L("Etikett", "Label"))]
    static let kinds: [(String, String)] = [("app", L("Programm", "Application")), ("folder", L("Ordner", "Folder")), ("doc", L("Dokument", "Document")), ("image", L("Bild", "Image")), ("movie", L("Film", "Movie")), ("music", L("Musik", "Music")), ("pdf", "PDF"), ("pres", L("Präsentation", "Presentation")), ("text", L("Text", "Text")), ("alias", "Alias"), ("other", L("Andere", "Other"))]
    static func ops(for a: String) -> [(String, String)] {
        switch a {
        case "kind", "label": return [("is", L("ist", "is")), ("isnot", L("ist nicht", "is not"))]
        case "name": return [("contains", L("enthält", "contains")), ("begins", L("beginnt mit", "begins with")), ("ends", L("endet mit", "ends with")), ("is", L("ist", "is"))]
        case "content": return [("contains", L("enthält", "contains"))]
        case "ext": return [("is", L("ist", "is"))]
        case "size": return [("gt", L("größer als (MB)", "is greater than (MB)")), ("lt", L("kleiner als (MB)", "is less than (MB)"))]
        default: return [("within", L("innerhalb der letzten (Tage)", "within last (days)")), ("before", L("vor (Tagen)", "before (days ago)")), ("today", L("ist heute", "is today"))]
        }
    }
}

struct SearchSpec: Equatable, Codable {
    var text = ""
    var scope = "this"                // this | shared | folder:<Pfad>
    var contents = false              // false = Dateiname, true = Inhalt
    var criteria: [Criterion] = []
    var saved: String?                // Pfad der .savedSearch-Datei
    var name = ""
    var allFiles = false
    var title: String {
        if !name.isEmpty { return name }
        if !text.isEmpty { return L("Suche nach „\(text)“", "Searching \u{201C}\(scopeName)\u{201D}") }
        return L("Suche in „\(scopeName)“", "Searching \u{201C}\(scopeName)\u{201D}")
    }
    var scopeName: String {
        if scope == "this" { return L("Dieser Mac", "This Mac") }
        if scope == "shared" { return L("Geteilt", "Shared") }
        return Files.displayName(URL(fileURLWithPath: String(scope.dropFirst(7))))
    }
    var id: String { saved ?? "\(scope)|\(contents)|\(text)|\(criteria.map { "\($0.attr)\($0.op)\($0.value)" })" }
    var folderURL: URL? { scope.hasPrefix("folder:") ? URL(fileURLWithPath: String(scope.dropFirst(7))) : nil }

    func predicate() -> NSPredicate {
        var subs: [NSPredicate] = []
        if allFiles {
            subs.append(NSPredicate(format: "NOT (%K == 'public.folder')", "kMDItemContentTypeTree"))
            subs.append(NSPredicate(format: "NOT (%K == 'com.apple.application')", "kMDItemContentTypeTree"))
        }
        if !text.isEmpty {
            if contents { subs.append(NSPredicate(format: "%K LIKE[cd] %@", "kMDItemTextContent", "*\(text)*")) }
            else { subs.append(NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, text)) }
        }
        for c in criteria { if let p = Self.predicate(c) { subs.append(p) } }
        if subs.isEmpty { subs.append(NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)) }
        return subs.count == 1 ? subs[0] : NSCompoundPredicate(andPredicateWithSubpredicates: subs)
    }

    static func predicate(_ c: Criterion) -> NSPredicate? {
        func tree(_ t: String) -> NSPredicate { NSPredicate(format: "%K == %@", "kMDItemContentTypeTree", t) }
        func neg(_ p: NSPredicate, _ n: Bool) -> NSPredicate { n ? NSCompoundPredicate(notPredicateWithSubpredicate: p) : p }
        let not = c.op == "isnot"
        switch c.attr {
        case "kind":
            switch c.value {
            case "app": return neg(tree("com.apple.application"), not)
            case "folder": return neg(tree("public.folder"), not)
            case "image": return neg(tree("public.image"), not)
            case "movie": return neg(tree("public.movie"), not)
            case "music": return neg(tree("public.audio"), not)
            case "pdf": return neg(tree("com.adobe.pdf"), not)
            case "pres": return neg(tree("public.presentation"), not)
            case "text": return neg(tree("public.text"), not)
            case "alias": return neg(tree("com.apple.alias-file"), not)
            case "doc": return neg(NSCompoundPredicate(orPredicateWithSubpredicates: [tree("public.composite-content"), tree("public.text"), tree("com.adobe.pdf")]), not)
            default: return neg(NSCompoundPredicate(notPredicateWithSubpredicate: NSCompoundPredicate(orPredicateWithSubpredicates: ["public.image", "public.movie", "public.audio", "com.adobe.pdf", "public.text", "public.folder", "com.apple.application"].map(tree))), not)
            }
        case "name":
            let v = c.value
            switch c.op {
            case "begins": return NSPredicate(format: "%K BEGINSWITH[cd] %@", NSMetadataItemFSNameKey, v)
            case "ends": return NSPredicate(format: "%K ENDSWITH[cd] %@", NSMetadataItemFSNameKey, v)
            case "is": return NSPredicate(format: "%K ==[cd] %@", NSMetadataItemFSNameKey, v)
            default: return NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, v)
            }
        case "content": return NSPredicate(format: "%K LIKE[cd] %@", "kMDItemTextContent", "*\(c.value)*")
        case "ext": return NSPredicate(format: "%K ENDSWITH[cd] %@", NSMetadataItemFSNameKey, "." + c.value.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        case "size":
            let n = Int64((Double(c.value.replacingOccurrences(of: ",", with: ".")) ?? 0) * 1_000_000)
            return NSPredicate(format: "%K \(c.op == "lt" ? "<" : ">") %lld", NSMetadataItemFSSizeKey, n)
        case "label":
            return neg(NSPredicate(format: "%K == %d", "kMDItemFSLabel", Labels.toSystem(Int(c.value) ?? 0)), not)
        case "modified", "created", "opened":
            let key = c.attr == "modified" ? NSMetadataItemFSContentChangeDateKey : (c.attr == "created" ? NSMetadataItemFSCreationDateKey : "kMDItemLastUsedDate")
            let days = Double(c.value) ?? 1
            let cal = Calendar.current
            switch c.op {
            case "today": return NSPredicate(format: "%K >= %@", key, cal.startOfDay(for: Date()) as NSDate)
            case "before": return NSPredicate(format: "%K < %@", key, Date().addingTimeInterval(-days * 86400) as NSDate)
            default: return NSPredicate(format: "%K >= %@", key, Date().addingTimeInterval(-days * 86400) as NSDate)
            }
        default: return nil
        }
    }

    /// mdfind-Rohabfrage für die .savedSearch-Datei
    var rawQuery: String {
        var q: [String] = []
        if !text.isEmpty { q.append(contents ? "(kMDItemTextContent == \"\(text)*\"cdw)" : "(kMDItemFSName == \"*\(text)*\"cd)") }
        for c in criteria {
            switch c.attr {
            case "name": q.append("(kMDItemFSName == \"*\(c.value)*\"cd)")
            case "content": q.append("(kMDItemTextContent == \"\(c.value)*\"cdw)")
            case "kind": q.append("(kMDItemContentTypeTree == \"\(["app": "com.apple.application", "folder": "public.folder", "image": "public.image", "movie": "public.movie", "music": "public.audio", "pdf": "com.adobe.pdf", "pres": "public.presentation", "text": "public.text"][c.value] ?? "public.data")\")")
            default: break
            }
        }
        return q.isEmpty ? "(kMDItemFSName == \"*\")" : q.joined(separator: " && ")
    }
}

// MARK: Gespeicherte Suchen („Intelligente Ordner“, S-06)

enum SavedSearches {
    static var dir: URL { Files.library.appendingPathComponent("Saved Searches") }
    static func list() -> [URL] {
        ((try? Files.fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "savedSearch" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    static func load(_ u: URL) -> SearchSpec? {
        guard let d = try? Data(contentsOf: u), let p = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil) as? [String: Any] else { return nil }
        var s: SearchSpec
        if let j = p["RetroFindSpec"] as? String, let data = j.data(using: .utf8), let sp = try? JSONDecoder().decode(SearchSpec.self, from: data) { s = sp }
        else {   // fremde Datei: nur Rohabfrage vorhanden → Name suchen
            s = SearchSpec(); if let raw = p["RawQuery"] as? String, let r = raw.range(of: "\"[^\"]+\"", options: .regularExpression) { s.text = String(raw[r].dropFirst().dropLast()).replacingOccurrences(of: "*", with: "") }
        }
        s.saved = u.path; s.name = u.deletingPathExtension().lastPathComponent
        return s
    }
    @discardableResult static func save(_ spec: SearchSpec, name: String, to dirURL: URL? = nil) -> URL? {
        var s = spec; s.name = name; s.saved = nil
        let d = dirURL ?? dir
        try? Files.fm.createDirectory(at: d, withIntermediateDirectories: true)
        let url = Files.unique(d.appendingPathComponent(name + ".savedSearch"))
        s.saved = url.path
        guard let j = try? JSONEncoder().encode(s), let js = String(data: j, encoding: .utf8) else { return nil }
        var scopes: [String] = ["kMDQueryScopeComputer"]
        if let f = spec.folderURL { scopes = [f.path] }
        let plist: [String: Any] = ["RawQuery": s.rawQuery, "RawQueryDict": ["RawQuery": s.rawQuery, "SearchScopes": scopes], "SearchCriteria": ["FXScopeArrayOfPaths": scopes], "RetroFindSpec": js]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0), (try? data.write(to: url)) != nil else { return nil }
        return url
    }
    static func update(_ spec: SearchSpec) {
        guard let p = spec.saved else { return }
        let u = URL(fileURLWithPath: p)
        try? Files.fm.removeItem(at: u)
        var s = spec; s.saved = nil
        if let n = save(s, name: spec.name.isEmpty ? u.deletingPathExtension().lastPathComponent : spec.name, to: u.deletingLastPathComponent()), n != u { try? Files.fm.moveItem(at: n, to: u) }
    }
    /// Vordefinierte Suchen der Seitenleistengruppe „Suchen nach“
    static func defaults() -> [SearchSpec] {
        func s(_ n: String, _ c: [Criterion]) -> SearchSpec { var x = SearchSpec(); x.name = n; x.criteria = c; x.scope = "this"; return x }
        return [s(L("Heute", "Today"), [Criterion(attr: "modified", op: "today", value: "")]),
                s(L("Gestern", "Yesterday"), [Criterion(attr: "modified", op: "within", value: "2")]),
                s(L("Letzte Woche", "Past Week"), [Criterion(attr: "modified", op: "within", value: "7")]),
                s(L("Alle Bilder", "All Images"), [Criterion(attr: "kind", op: "is", value: "image")]),
                s(L("Alle Filme", "All Movies"), [Criterion(attr: "kind", op: "is", value: "movie")]),
                s(L("Alle Dokumente", "All Documents"), [Criterion(attr: "kind", op: "is", value: "doc")])]
    }
}

// MARK: Spotlight-Anbindung

final class SearchEngine: NSObject {
    private var q: NSMetadataQuery?
    var onUpdate: (([FileNode], Bool) -> Void)?       // Knoten, abgeschlossen
    var spec: SearchSpec

    init(spec: SearchSpec) { self.spec = spec; super.init() }

    func start() {
        stop()
        let q = NSMetadataQuery()
        q.predicate = spec.predicate()
        if let f = spec.folderURL { q.searchScopes = [f] }
        else if spec.allFiles { q.searchScopes = [Files.home] }
        else if spec.scope == "shared" { q.searchScopes = [NSMetadataQueryNetworkScope] }
        else { q.searchScopes = [NSMetadataQueryLocalComputerScope] }
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        q.notificationBatchingInterval = 0.25
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(changed(_:)), name: .NSMetadataQueryDidUpdate, object: q)
        nc.addObserver(self, selector: #selector(changed(_:)), name: .NSMetadataQueryGatheringProgress, object: q)
        nc.addObserver(self, selector: #selector(changed(_:)), name: .NSMetadataQueryDidFinishGathering, object: q)
        self.q = q
        DispatchQueue.main.async { q.start() }
    }
    func stop() { q?.stop(); NotificationCenter.default.removeObserver(self); q = nil }
    deinit { stop() }

    @objc private func changed(_ n: Notification) {
        guard let q else { return }
        q.disableUpdates()
        var out: [FileNode] = []; out.reserveCapacity(min(q.resultCount, 3000))
        let home = Files.home.path
        for i in 0..<min(q.resultCount, 4000) {
            guard let item = q.result(at: i) as? NSMetadataItem, let p = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            if SearchEngine.hiddenPath(p, home: home, allFiles: spec.allFiles, scopedFolder: spec.folderURL != nil) { continue }
            out.append(FileNode(url: URL(fileURLWithPath: p)))
        }
        let fin = !q.isGathering
        q.enableUpdates()
        onUpdate?(out, fin)
    }

    /// S-05: Systemdateien und unsichtbare Dateien werden standardmäßig nicht gelistet.
    static func hiddenPath(_ p: String, home: String, allFiles: Bool, scopedFolder: Bool) -> Bool {
        if scopedFolder { return p.contains("/.") }
        if p.contains("/.") || p.hasPrefix("/System/") || p.hasPrefix("/private/") || p.hasPrefix("/usr/") || p.hasPrefix("/bin/") || p.hasPrefix("/sbin/") || p.hasPrefix("/opt/") || p.hasPrefix("/cores/") { return true }
        if p.hasPrefix("/Library/") || p.hasPrefix(home + "/Library/") { return true }
        if allFiles && (p.contains(".app/") || p.contains(".framework/") || p.contains(".bundle/")) { return true }
        return false
    }
}
