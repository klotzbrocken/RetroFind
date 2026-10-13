import AppKit

extension Prefs {
    static var terminalApp: String { get { d.string(forKey: "terminalApp") ?? "com.apple.Terminal" } set { d.set(newValue, forKey: "terminalApp") } }
}

/// „Terminal hier“: öffnet ein Terminal-Programm im gewählten Ordner (ohne Automatisierungsrechte: Ordner wird dem Programm übergeben).
enum TerminalApp {
    static let known: [(id: String, name: String)] = [("com.apple.Terminal", "Terminal"), ("com.googlecode.iterm2", "iTerm"), ("com.mitchellh.ghostty", "Ghostty"), ("dev.warp.Warp-Stable", "Warp"), ("com.github.wez.wezterm", "WezTerm"), ("co.zeit.hyper", "Hyper"), ("net.kovidgoyal.kitty", "kitty"), ("org.alacritty", "Alacritty")]
    static func url(for id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }
    /// Installierte bekannte Programme (Terminal ist immer dabei) plus ein vom Nutzer gewähltes
    static func installed() -> [(id: String, name: String)] {
        var r = known.filter { url(for: $0.id) != nil }
        let cur = Prefs.terminalApp
        if !r.contains(where: { $0.id == cur }), let u = url(for: cur) { r.append((cur, Files.displayName(u).replacingOccurrences(of: ".app", with: ""))) }
        return r
    }
    @discardableResult static func open(_ dir: URL) -> Bool {
        guard let app = url(for: Prefs.terminalApp) ?? url(for: "com.apple.Terminal") else { FileOps.shared.alert(L("Kein Terminal-Programm gefunden.", "No terminal app found.")); return false }
        let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = true
        NSWorkspace.shared.open([dir], withApplicationAt: app, configuration: cfg) { _, err in
            if let err { DispatchQueue.main.async { FileOps.shared.alert(L("Das Terminal konnte nicht geöffnet werden.", "The terminal couldn\u{2019}t be opened."), err.localizedDescription) } }
        }
        return true
    }
}

extension BrowserController {
    /// Ziel: genau ein gewählter Ordner (oder Paket-Elternordner bei Dateien), sonst der aktuelle Ordner, sonst der Benutzerordner
    var terminalTarget: URL {
        let f = focus
        if f.selection.count == 1, let n = f.selectedNodes.first {
            if n.isFolderLike || n.isVolume { return n.url }
            return n.url.deletingLastPathComponent()
        }
        return f.currentDir ?? Files.home
    }
    @objc func terminalHere(_ s: Any?) { TerminalApp.open(terminalTarget) }
    /// ⌥⌘C: POSIX-Pfade der Auswahl (bzw. des aktuellen Ordners) in die Zwischenablage
    @objc func copyPath(_ s: Any?) {
        let f = focus
        let paths = f.selection.isEmpty ? (f.currentDir.map { [$0.path] } ?? []) : f.selection.map { $0.path }
        guard !paths.isEmpty else { NSSound.beep(); return }
        let pb = NSPasteboard.general; pb.clearContents(); pb.setString(paths.joined(separator: "\n"), forType: .string)
    }
}
