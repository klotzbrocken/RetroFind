import AppKit

struct Group {
    var title: String?
    var nodes: [FileNode]
    var total: Int          // Gesamtzahl (für „Alle anzeigen (n)“)
}

protocol BrowserHost: AnyObject {
    var location: Location { get }
    var options: ViewOptions { get set }
    var nodes: [FileNode] { get }
    var groups: [Group] { get }
    var selection: [URL] { get }
    var isActive: Bool { get }
    var expandedGroups: Set<String> { get set }
    func isSelected(_ u: URL) -> Bool
    func setSelection(_ urls: [URL], source: NSView?)
    func open(_ n: FileNode, modifiers: NSEvent.ModifierFlags)
    func openSelection()
    func contextMenu(for n: FileNode?) -> NSMenu
    func dragOperation(_ urls: [URL], into dir: URL?, flags: NSEvent.ModifierFlags) -> NSDragOperation
    func performDrop(_ urls: [URL], into dir: URL?, flags: NSEvent.ModifierFlags) -> Bool
    func rename(_ n: FileNode, to name: String)
    func quickLook()
    func children(of n: FileNode) -> [FileNode]
    func navigate(_ loc: Location)
    func goUp()
    func node(for u: URL) -> FileNode?
    func springOpen(_ n: FileNode)
    func trashSelection()
    func viewStateChanged()
    var currentDir: URL? { get }
}

protocol ItemView: NSView {
    var host: BrowserHost? { get set }
    func reload()
    func selectionChanged()
    func revealSelection()
    func startRename()
    func applyOptions()
}

extension NSView {
    /// Hilfsfunktion: eingebettete Bildschirmskalierung
    var scale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
}

/// Zeilen einer Beschriftung (max. 2 Zeilen, zweite Zeile mittig gekürzt – wie im Finder)
func wrapLabel(_ s: String, width: CGFloat, font: NSFont, maxLines: Int = 2) -> [String] {
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    func w(_ t: String) -> CGFloat { (t as NSString).size(withAttributes: attrs).width }
    if w(s) <= width { return [s] }
    var lines: [String] = []; var rest = Substring(s)
    while !rest.isEmpty && lines.count < maxLines - 1 {
        if w(String(rest)) <= width { lines.append(String(rest)); rest = ""; break }
        var cut = rest.startIndex; var lastSpace: String.Index?
        var i = rest.startIndex
        while i < rest.endIndex { let nxt = rest.index(after: i); if w(String(rest[rest.startIndex..<nxt])) > width { break }; if rest[i] == " " || rest[i] == "-" || rest[i] == "_" || rest[i] == "." { lastSpace = nxt }; cut = nxt; i = nxt }
        if let ls = lastSpace, ls > rest.startIndex { cut = ls }
        if cut == rest.startIndex { cut = rest.index(after: rest.startIndex) }
        lines.append(String(rest[rest.startIndex..<cut]).trimmingCharacters(in: .whitespaces)); rest = rest[cut...]
    }
    if !rest.isEmpty { lines.append(truncMiddle(String(rest), width: width, font: font)) }
    return lines
}
func truncMiddle(_ s: String, width: CGFloat, font: NSFont) -> String {
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    if (s as NSString).size(withAttributes: attrs).width <= width { return s }
    let chars = Array(s); var keep = chars.count
    while keep > 2 {
        keep -= 1
        let a = (keep + 1) / 2, b = keep / 2
        let t = String(chars.prefix(a)) + "…" + String(chars.suffix(b))
        if (t as NSString).size(withAttributes: attrs).width <= width { return t }
    }
    return "…"
}
