import AppKit
import UniformTypeIdentifiers

// MARK: Orte

enum Location: Equatable {
    static func == (a: Location, b: Location) -> Bool {
        switch (a, b) {
        case (.folder(let x), .folder(let y)): return x.standardizedFileURL.path == y.standardizedFileURL.path
        case (.allMyFiles, .allMyFiles), (.airDrop, .airDrop), (.network, .network), (.computer, .computer): return true
        case (.search(let x), .search(let y)): return x == y
        default: return false
        }
    }
    case folder(URL)
    case allMyFiles
    case airDrop
    case network
    case computer
    case search(SearchSpec)

    var url: URL? { if case .folder(let u) = self { return u }; return nil }
    var isVirtual: Bool { if case .folder = self { return false }; return true }
    var title: String {
        switch self {
        case .folder(let u): return Files.displayName(u)
        case .allMyFiles: return L("Alle meine Dateien", "All My Files")
        case .airDrop: return "AirDrop"
        case .network: return L("Netzwerk", "Network")
        case .computer: return Host.current().localizedName ?? L("Computer", "Computer")
        case .search(let s): return s.title
        }
    }
    var glyph: Glyph {
        switch self {
        case .folder(let u): return Files.glyph(for: u)
        case .allMyFiles: return .allFiles
        case .airDrop: return .airDrop
        case .network: return .network
        case .computer: return .computer
        case .search: return .smartFolder
        }
    }
}

// MARK: Dateiknoten

final class FileNode: NSObject {
    let url: URL
    var name: String
    var isDir = false, isPackage = false, isAlias = false, isLocked = false, isVolume = false, isHidden = false
    var size: Int64 = -1                 // -1 = Ordner/unbekannt
    var kind = ""
    var created: Date?, modified: Date?, opened: Date?, added: Date?
    var label = 0                        // 0 = keines, 1…7 = Rot, Orange, Gelb, Grün, Blau, Violett, Grau
    var children: [FileNode]?            // Listenansicht (aufgeklappt)
    var childCount = -1
    weak var parent: FileNode?
    var aliasBroken = false
    var calculating = false              // Ordnergröße wird berechnet
    var itemCount = -1                   // Objekte im Ordner (nach Größenberechnung)
    var section: String?                 // „Alle meine Dateien“ / Gruppierung

    var isFolderLike: Bool { isDir && !isPackage }
    /// Größenanzeige; Paketgrößen werden im Hintergrund nachgeladen
    var displaySize: String {
        if calculating { return "…" }
        if size < 0 { if isPackage { SizeService.shared.request(self) }; return "--" }
        return Files.sizeString(size)
    }
    /// Ordner, in die man navigieren kann (Pakete und Aliasse auf Ordner zählen nicht als Ordner)
    var typeID: String { (try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier) ?? "" }

    static let keys: [URLResourceKey] = [.localizedNameKey, .isDirectoryKey, .isPackageKey, .isAliasFileKey, .isHiddenKey, .fileSizeKey, .totalFileSizeKey, .contentModificationDateKey, .creationDateKey, .contentAccessDateKey, .addedToDirectoryDateKey, .localizedTypeDescriptionKey, .labelNumberKey, .isUserImmutableKey, .isVolumeKey]

    init(url u: URL) {
        // Ordner-URLs aus Verzeichnislisten tragen einen Schrägstrich → vereinheitlichen, damit Auswahlvergleiche (==) stimmen
        url = u.isFileURL ? URL(fileURLWithPath: u.path, isDirectory: false) : u
        name = url.lastPathComponent
        super.init()
        refresh()
    }

    func refresh() {
        guard let v = try? url.resourceValues(forKeys: Set(FileNode.keys)) else { name = url.lastPathComponent; return }
        name = v.localizedName ?? url.lastPathComponent
        isDir = v.isDirectory ?? false; isPackage = v.isPackage ?? false; isAlias = v.isAliasFile ?? false
        isHidden = v.isHidden ?? false; isLocked = v.isUserImmutable ?? false; isVolume = v.isVolume ?? false
        if isDir { size = -1; if !isPackage, let r = SizeService.shared.cachedFolder(url, mtime: v.contentModificationDate) { size = r.bytes; itemCount = r.items } } else { size = Int64(v.totalFileSize ?? v.fileSize ?? 0) }
        if isPackage { size = SizeService.shared.cached(url) ?? -1 }       // Paketgröße nie synchron (Programme-Ordner: tausende Dateien je App)
        kind = v.localizedTypeDescription ?? ""
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { isAlias = false }
        if isAlias && !isDir { aliasBroken = Alias.resolve(url) == nil }
        created = v.creationDate; modified = v.contentModificationDate; opened = v.contentAccessDate; added = v.addedToDirectoryDate
        label = Labels.fromSystem(v.labelNumber ?? 0)
    }

    static func packageSize(_ u: URL) -> Int64 {
        var t: Int64 = 0
        if let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: [.totalFileSizeKey, .fileSizeKey], options: []) {
            for case let f as URL in e { let v = try? f.resourceValues(forKeys: [.totalFileSizeKey, .fileSizeKey]); t += Int64(v?.totalFileSize ?? v?.fileSize ?? 0) }
        }
        return t
    }

    var comment: String {
        get { Files.getComment(url) }
        set { Files.setComment(url, newValue) }
    }
    var displayKind: String {
        if isAlias { return L("Alias", "Alias") }
        if isVolume { return L("Volume", "Volume") }
        return kind
    }
    override func isEqual(_ o: Any?) -> Bool { (o as? FileNode)?.url == url }
    override var hash: Int { url.hashValue }
}

// MARK: Etiketten (historische Farbetiketten, I-11)

enum Labels {
    /// Finder-Systemnummer je Etikett-Index 1…7 (Rot, Orange, Gelb, Grün, Blau, Violett, Grau)
    static let sys = [6, 7, 5, 2, 4, 3, 1]
    static func fromSystem(_ n: Int) -> Int { n == 0 ? 0 : (sys.firstIndex(of: n).map { $0 + 1 } ?? 0) }
    static func toSystem(_ i: Int) -> Int { i == 0 ? 0 : sys[i - 1] }
    static func name(_ i: Int) -> String {
        guard i >= 1 && i <= 7 else { return L("Keines", "None") }
        if let n = UserDefaults.standard.stringArray(forKey: "labelNames"), n.count == 7, !n[i - 1].isEmpty { return n[i - 1] }
        return Lang.de ? C.labelNames_de[i - 1] : C.labelNames_en[i - 1]
    }
    static func setNames(_ n: [String]) { UserDefaults.standard.set(n, forKey: "labelNames") }
    @discardableResult static func set(_ i: Int, for url: URL) -> Bool {
        do { try (url as NSURL).setResourceValue(NSNumber(value: toSystem(i)), forKey: .labelNumberKey); return true } catch { return false }
    }
}

// MARK: Hilfen für Dateien

enum Files {
    static let fm = FileManager.default
    static let home = fm.homeDirectoryForCurrentUser
    static func std(_ d: FileManager.SearchPathDirectory) -> URL { fm.urls(for: d, in: .userDomainMask).first ?? home }
    static var desktop: URL { std(.desktopDirectory) }
    static var documents: URL { std(.documentDirectory) }
    static var downloads: URL { std(.downloadsDirectory) }
    static var movies: URL { std(.moviesDirectory) }
    static var music: URL { std(.musicDirectory) }
    static var pictures: URL { std(.picturesDirectory) }
    static var library: URL { std(.libraryDirectory) }
    static var applications: URL { URL(fileURLWithPath: "/Applications") }
    static var utilities: URL { URL(fileURLWithPath: "/Applications/Utilities") }
    static var trash: URL { home.appendingPathComponent(".Trash") }
    static var root: URL { URL(fileURLWithPath: "/") }
    static let burnExt = "fpbf"

    static func displayName(_ u: URL) -> String {
        if u.path == "/" { return (try? u.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "Macintosh HD" }
        if u.standardizedFileURL.path == home.path { return NSUserName() }
        return fm.displayName(atPath: u.path)
    }

    static func glyph(for u: URL) -> Glyph {
        let p = u.standardizedFileURL.path
        if p == home.path { return .home }
        if p == desktop.path { return .desktop }
        if p == documents.path { return .documents }
        if p == downloads.path { return .downloads }
        if p == movies.path { return .movies }
        if p == music.path { return .music }
        if p == pictures.path { return .pictures }
        if p == "/Applications" { return .applications }
        if p == "/Applications/Utilities" { return .utilities }
        if p == library.path || p == "/Library" || p == "/System/Library" { return .library }
        if p == home.appendingPathComponent("Public").path { return .publicFolder }
        if p == home.appendingPathComponent("Sites").path { return .sites }
        if p == trash.path { return .trash }
        if p == "/" { return .hardDisk }
        if p.hasPrefix("/Volumes/") && p.split(separator: "/").count == 2 { return .hardDisk }
        if u.pathExtension == "savedSearch" { return .smartFolder }
        return .folder
    }

    /// Verzeichnisinhalt mit URLs aus dem übergebenen Ordner aufgebaut (nicht aus dem aufgelösten Pfad: /tmp ≠ /private/tmp) – damit Auswahlvergleiche stimmen.
    static func list(_ dir: URL) throws -> [URL] {
        var out = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: FileNode.keys, options: Prefs.showHidden ? [] : [.skipsHiddenFiles]).map { dir.appendingPathComponent($0.lastPathComponent) }
        // ~/Library trotz Sichtbarkeits-Flag anzeigen (Einstellung)
        if Prefs.showLibrary && dir.standardizedFileURL.path == home.standardizedFileURL.path, !out.contains(where: { $0.lastPathComponent == "Library" }), fm.fileExists(atPath: home.appendingPathComponent("Library").path) { out.append(home.appendingPathComponent("Library")) }
        return out
    }
    static func sortURLs(_ a: [URL]) -> [URL] { a.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } }

    /// Eindeutiger Name im Zielordner: „name Kopie“, „name Kopie 2“ … (F-04/F-10)
    static func unique(_ base: URL, suffix: String? = nil) -> URL {
        let dir = base.deletingLastPathComponent(); let ext = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent
        var cand = base
        var n = 0
        func make(_ n: Int) -> URL {
            var s = stem
            if let suffix { s += " " + suffix; if n > 1 { s += " \(n)" } } else if n > 0 { s += " \(n + 1)" }
            return dir.appendingPathComponent(ext.isEmpty ? s : s + "." + ext)
        }
        if suffix != nil { n = 1; cand = make(1) }
        while fm.fileExists(atPath: cand.path) || (try? cand.checkResourceIsReachable()) == true { n += 1; cand = make(n) }
        return cand
    }
    static func exists(_ u: URL) -> Bool { fm.fileExists(atPath: u.path) || (try? u.checkResourceIsReachable()) == true || ((try? u.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false) }

    // Spotlight-Kommentar (xattr com.apple.metadata:kMDItemFinderComment)
    static let commentKey = "com.apple.metadata:kMDItemFinderComment"
    static func getComment(_ u: URL) -> String {
        let n = getxattr(u.path, commentKey, nil, 0, 0, 0); guard n > 0 else { return "" }
        var buf = [UInt8](repeating: 0, count: n)
        guard getxattr(u.path, commentKey, &buf, n, 0, 0) == n else { return "" }
        return ((try? PropertyListSerialization.propertyList(from: Data(buf), options: [], format: nil)) as? String) ?? ""
    }
    static func setComment(_ u: URL, _ s: String) {
        if s.isEmpty { removexattr(u.path, commentKey, 0); return }
        if let d = try? PropertyListSerialization.data(fromPropertyList: s, format: .binary, options: 0) {
            _ = d.withUnsafeBytes { setxattr(u.path, commentKey, $0.baseAddress, d.count, 0, 0) }
        }
    }

    // Volumes
    static func volumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsEjectableKey, .volumeIsLocalKey, .volumeIsInternalKey, .volumeIsRootFileSystemKey]
        let all = fm.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return all.filter { $0.path != "/System/Volumes/Data" }
    }
    static func isEjectable(_ u: URL) -> Bool {
        guard let v = try? u.resourceValues(forKeys: [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsLocalKey, .volumeIsRootFileSystemKey]) else { return false }
        if v.volumeIsRootFileSystem == true { return false }
        return v.volumeIsEjectable == true || v.volumeIsRemovable == true || v.volumeIsLocal == false
    }
    static func isNetwork(_ u: URL) -> Bool { ((try? u.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) ?? true) == false }

    static func volumeInfo(_ u: URL) -> (capacity: Int64, available: Int64, format: String) {
        let v = try? u.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        var fs = statfs(); var fmt = ""
        if statfs(u.path, &fs) == 0 { fmt = withUnsafePointer(to: &fs.f_fstypename) { $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) } } }
        return (Int64(v?.volumeTotalCapacity ?? 0), v?.volumeAvailableCapacityForImportantUsage ?? Int64(v?.volumeAvailableCapacity ?? 0), fmt)
    }

    // Formatierung (A-11)
    static let bytes: ByteCountFormatter = { let f = ByteCountFormatter(); f.countStyle = .file; f.allowedUnits = [.useAll]; return f }()
    static func sizeString(_ n: Int64) -> String { n < 0 ? "--" : (n == 0 ? L("0 Byte", "Zero bytes") : bytes.string(fromByteCount: n)) }
    static let dateF: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; f.doesRelativeDateFormatting = true; return f }()
    static let dayF: DateFormatter = { let f = DateFormatter(); f.dateStyle = .long; f.timeStyle = .short; f.doesRelativeDateFormatting = true; return f }()
    static func dateString(_ d: Date?, long: Bool = false) -> String { d.map { (long ? dayF : dateF).string(from: $0) } ?? "--" }
    static let intF: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .decimal; return f }()
    static func num(_ n: Int) -> String { intF.string(from: NSNumber(value: n)) ?? "\(n)" }
}

// MARK: Aliasse (F-10/F-11) – echte Finder-Aliasse (Bookmark-Dateien)

enum Alias {
    static func make(for target: URL, at dest: URL) -> Bool {
        do {
            let d = try target.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
            try URL.writeBookmarkData(d, to: dest); return true
        } catch { return false }
    }
    static func resolve(_ u: URL) -> URL? {
        guard let d = try? URL.bookmarkData(withContentsOf: u) else { return nil }
        var stale = false
        guard let r = try? URL(resolvingBookmarkData: d, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale), Files.exists(r) else { return nil }
        return r
    }
}

// MARK: Sortieren / Anordnen

enum SortKey: String, CaseIterable {
    case none, name, kind, opened, added, modified, created, size, label
    var title: String {
        switch self {
        case .none: return L("Keine", "None")
        case .name: return L("Name", "Name")
        case .kind: return L("Art", "Kind")
        case .opened: return L("Datum des letzten Öffnens", "Date Last Opened")
        case .added: return L("Hinzufügedatum", "Date Added")
        case .modified: return L("Änderungsdatum", "Date Modified")
        case .created: return L("Erstellungsdatum", "Date Created")
        case .size: return L("Größe", "Size")
        case .label: return L("Etikett", "Label")
        }
    }
    func less(_ a: FileNode, _ b: FileNode) -> Bool {
        func cmp<T: Comparable>(_ x: T?, _ y: T?) -> Bool? { guard let x, let y else { return x != nil && y == nil ? true : nil }; return x == y ? nil : x < y }
        switch self {
        case .none, .name: break
        case .kind: if let r = cmp(a.displayKind, b.displayKind) { return r }
        case .opened: if let r = cmp(b.opened, a.opened) { return r }
        case .added: if let r = cmp(b.added, a.added) { return r }
        case .modified: if let r = cmp(b.modified, a.modified) { return r }
        case .created: if let r = cmp(b.created, a.created) { return r }
        case .size: if let r = cmp(b.size, a.size) { return r }
        case .label: if let r = cmp(a.label, b.label) { return r }
        }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}

// MARK: Ansichtsoptionen (A-01…A-10)

enum ViewMode: Int, Codable { case icon = 0, list, column, coverFlow }

struct ViewOptions: Codable, Equatable {
    var mode: ViewMode = .icon
    var iconSize: CGFloat = 64
    var gridSpacing: CGFloat = 40
    var textSize: CGFloat = 13
    var labelRight = false
    var showInfo = false
    var showPreview = true
    var arrange: String = "none"            // SortKey.rawValue oder "grid"
    var snapToGrid = false
    var sortKey: String = "name"            // Liste/Spalten
    var ascending = true
    var listIconSize: CGFloat = 16
    var listTextSize: CGFloat = 12
    var columns: [String] = ["name", "modified", "size", "kind"]
    var widths: [String: CGFloat] = [:]
    var calcSizes = false
    var useRelativeDates = true
    var bgColor: [CGFloat]? = nil           // RGB 0…1; nil = weiß
    var coverSplit: CGFloat = 0.5
    var colPreview = true
    var colWidth: CGFloat = 186
    var userPositions: [String: [CGFloat]] = [:]    // freie Symbolpositionen (A-01)
    var forcedMode: Int? = nil                      // „Immer in dieser Ansicht öffnen“
    var browseIn = false                            // „In dieser Ansicht durchsuchen“
    var bgImage: String? = nil                      // Hintergrundbild (A-02)
    var touched = false                             // vom Nutzer ausdrücklich geändert (sonst: erben)
}

enum ViewStore {
    static let key = "viewOptions"
    static func all() -> [String: Data] { (UserDefaults.standard.dictionary(forKey: key) as? [String: Data]) ?? [:] }
    private static func decode(_ d: Data?) -> ViewOptions? { d.flatMap { try? JSONDecoder().decode(ViewOptions.self, from: $0) } }
    /// Ansicht für einen Ort: global (Einstellung) → eigene, vom Nutzer geänderte Einstellung → Vererbung vom nächsten Elternordner → Standard.
    /// Nur ausdrücklich geänderte Einträge (`touched`) zählen; bloßes Besuchen speichert nichts und friert die Vererbung nicht ein.
    static func options(for loc: Location) -> ViewOptions {
        let d = all()
        if Prefs.globalView, var g = decode(d["__global"]) { g.userPositions = decode(d[k(loc)])?.userPositions ?? [:]; return g }
        if let o = decode(d[k(loc)]), o.touched { return o }
        if case .folder(let u) = loc {                       // Vererbung: nächster Elternordner mit eigener Einstellung
            var cur = u.standardizedFileURL
            while cur.path != "/" {
                cur = cur.deletingLastPathComponent()
                if let o = decode(d[cur.path]), o.touched { var i = o; i.userPositions = [:]; return i }
            }
        }
        if var o = decode(d["__default"]) { o.userPositions = [:]; return o }
        var o = ViewOptions()
        if case .allMyFiles = loc { o.mode = .icon }
        return o
    }
    static func save(_ o: ViewOptions, for loc: Location, asDefault: Bool = false) {
        var d = all(); var x = o; x.touched = true
        guard let data = try? JSONEncoder().encode(x) else { return }
        if asDefault { d["__default"] = data }
        else { d[k(loc)] = data; if Prefs.globalView { d["__global"] = data } }
        UserDefaults.standard.set(d, forKey: key)
    }
    /// Globale Ansicht einschalten: die Einstellungen des gegebenen Ortes werden zur gemeinsamen Ansicht
    static func setGlobal(_ on: Bool, from o: ViewOptions?) {
        Prefs.globalView = on
        guard on, var x = o else { return }
        x.touched = true; x.userPositions = [:]
        var d = all(); if let data = try? JSONEncoder().encode(x) { d["__global"] = data; UserDefaults.standard.set(d, forKey: key) }
    }
    static func remove(_ loc: Location) { var d = all(); d[k(loc)] = nil; UserDefaults.standard.set(d, forKey: key) }
    static func hasSaved(_ loc: Location) -> Bool { decode(all()[k(loc)])?.touched == true }
    static func k(_ loc: Location) -> String {
        switch loc {
        case .folder(let u): return u.standardizedFileURL.path
        case .allMyFiles: return "virtual:allfiles"
        case .airDrop: return "virtual:airdrop"
        case .network: return "virtual:network"
        case .computer: return "virtual:computer"
        case .search(let s): return "search:" + s.id
        }
    }
}

// MARK: Einstellungen (E-01…E-04)

enum Prefs {
    static let d = UserDefaults.standard
    static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) == nil ? def : d.bool(forKey: k) }
    static var showHDOnDesktop: Bool { get { bool("deskHD", true) } set { d.set(newValue, forKey: "deskHD") } }
    static var showExtensions: Bool { get { bool("showExt", true) } set { d.set(newValue, forKey: "showExt") } }
    static var warnExt: Bool { get { bool("warnExt", true) } set { d.set(newValue, forKey: "warnExt") } }
    static var warnTrash: Bool { get { bool("warnTrash", true) } set { d.set(newValue, forKey: "warnTrash") } }
    static var secureEmpty: Bool { get { bool("secureEmpty", false) } set { d.set(newValue, forKey: "secureEmpty") } }
    static var foldersInNewWindow: Bool { get { bool("newWin", false) } set { d.set(newValue, forKey: "newWin") } }
    static var springLoading: Bool { get { bool("spring", true) } set { d.set(newValue, forKey: "spring") } }
    static var springDelay: Double { get { d.object(forKey: "springDelay") == nil ? 0.8 : d.double(forKey: "springDelay") } set { d.set(newValue, forKey: "springDelay") } }
    static var searchScope: String { get { d.string(forKey: "scope") ?? "this" } set { d.set(newValue, forKey: "scope") } }   // this | folder | previous
    static var newWindowTarget: String { get { d.string(forKey: "newTarget") ?? "home" } set { d.set(newValue, forKey: "newTarget") } }   // allfiles | home | computer | path:…
    static var sidebarHidden: Set<String> { get { Set(d.stringArray(forKey: "sideHidden") ?? []) } set { d.set(Array(newValue), forKey: "sideHidden") } }
    static var sidebarCollapsed: Set<String> { get { Set(d.stringArray(forKey: "sideCollapsed") ?? []) } set { d.set(Array(newValue), forKey: "sideCollapsed") } }
    static var sectionOrder: [String] { get { d.stringArray(forKey: "sectionOrder") ?? ["fav", "shared", "devices", "search"] } set { d.set(newValue, forKey: "sectionOrder") } }
    static var favorites: [String] { get { d.stringArray(forKey: "favorites") ?? [] } set { d.set(newValue, forKey: "favorites") } }
    static var recents: [String] { get { d.stringArray(forKey: "recents") ?? [] } set { d.set(newValue, forKey: "recents") } }
    static var servers: [String] { get { d.stringArray(forKey: "servers") ?? [] } set { d.set(newValue, forKey: "servers") } }
    static var globalView: Bool { get { bool("globalView", false) } set { d.set(newValue, forKey: "globalView") } }
    static var showToolbar: Bool { get { bool("showToolbar", true) } set { d.set(newValue, forKey: "showToolbar") } }
    static var showSidebar: Bool { get { bool("showSidebar", true) } set { d.set(newValue, forKey: "showSidebar") } }
    static var showStatus: Bool { get { bool("showStatus", false) } set { d.set(newValue, forKey: "showStatus") } }
    static var showPath: Bool { get { bool("showPath", false) } set { d.set(newValue, forKey: "showPath") } }
    static var toolbarItems: [String] { get { d.stringArray(forKey: "toolbarItems") ?? Toolbar.defaultItems } set { d.set(newValue, forKey: "toolbarItems") } }
    static var toolbarMode: Int { get { d.integer(forKey: "toolbarMode") } set { d.set(newValue, forKey: "toolbarMode") } }   // 0 Symbole, 1 Symbole+Text, 2 Text
    static func noteRecent(_ u: URL) {
        var r = recents.filter { $0 != u.path }; r.insert(u.path, at: 0); recents = Array(r.prefix(10))
    }
}


extension Notification.Name { static let sizeReady = Notification.Name("MLSizeReady") }

/// Berechnet Paketgrößen auf einer Hintergrund-Queue (A-12) und meldet gesammelt Fertigstellungen.
final class SizeService {
    static let shared = SizeService()
    private var cache: [URL: Int64] = [:]
    private var pending = Set<URL>()
    private var waiting: [URL: [WeakNode]] = [:]
    private let q = DispatchQueue(label: "sizes", qos: .utility, attributes: .concurrent)
    private let lock = NSLock()
    private var notifyScheduled = false
    private final class WeakNode { weak var n: FileNode?; init(_ n: FileNode) { self.n = n } }
    // MARK: Ordnergrößen auf Knopfdruck (rekursiv, abbrechbar)
    struct FolderResult { var bytes: Int64; var items: Int; var mtime: Date? }
    private var folderCache: [URL: FolderResult] = [:]
    final class Batch { var cancelled = false; var remaining = 0 }
    private let folderQueue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 3; q.qualityOfService = .userInitiated; return q }()
    /// Gespeichertes Ergebnis, solange sich das Änderungsdatum des Ordners nicht geändert hat
    func cachedFolder(_ u: URL, mtime: Date?) -> FolderResult? { lock.lock(); defer { lock.unlock() }; guard let r = folderCache[u], r.mtime == mtime else { return nil }; return r }
    /// Berechnet die Größen (Bytes, Objekte) der Ordner im Hintergrund; `onUpdate` je fertigem Ordner, `onFinish` am Ende (Hauptthread).
    @discardableResult func calculate(_ nodes: [FileNode], onUpdate: (() -> Void)? = nil, onFinish: (() -> Void)? = nil) -> Batch {
        let batch = Batch(); batch.remaining = nodes.count
        nodes.forEach { $0.calculating = true }
        if nodes.isEmpty { DispatchQueue.main.async { onFinish?() }; return batch }
        for n in nodes {
            let u = n.url
            folderQueue.addOperation { [weak self] in
                var bytes: Int64 = 0, items = 0
                let mt = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                if let e = Files.fm.enumerator(at: u, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: []) {
                    for case let f as URL in e {
                        if batch.cancelled { break }
                        items += 1
                        let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                        if v?.isRegularFile == true { bytes += Int64(v?.fileSize ?? 0) }
                    }
                }
                let ok = !batch.cancelled
                DispatchQueue.main.async {
                    n.calculating = false
                    if ok { n.size = bytes; n.itemCount = items; self?.lock.lock(); self?.folderCache[u] = FolderResult(bytes: bytes, items: items, mtime: mt ?? nil); self?.lock.unlock() }
                    batch.remaining -= 1
                    onUpdate?(); NotificationCenter.default.post(name: .sizeReady, object: nil)
                    if batch.remaining == 0 { onFinish?() }
                }
            }
        }
        return batch
    }
    func cached(_ u: URL) -> Int64? { lock.lock(); defer { lock.unlock() }; return cache[u] }
    func request(_ n: FileNode) {
        lock.lock()
        if let s = cache[n.url] { lock.unlock(); n.size = s; return }
        waiting[n.url, default: []].append(WeakNode(n))
        let fresh = pending.insert(n.url).inserted
        lock.unlock()
        guard fresh else { return }
        let u = n.url
        q.async { [weak self] in
            let s = FileNode.packageSize(u)
            guard let self else { return }
            self.lock.lock(); self.cache[u] = s; self.pending.remove(u); let ws = self.waiting.removeValue(forKey: u) ?? []; self.lock.unlock()
            DispatchQueue.main.async {
                ws.forEach { $0.n?.size = s }
                if !self.notifyScheduled { self.notifyScheduled = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.notifyScheduled = false; NotificationCenter.default.post(name: .sizeReady, object: nil) } }
            }
        }
    }
}
