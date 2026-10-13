import AppKit

/// Programmsymbol-Einstellung: eigenes PNG (genau 256×256 px) ersetzt das Symbol im Dock und im Programmwechsler.
enum AppIcon {
    static var dir: URL { Files.fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RetroFind") }
    static var file: URL { dir.appendingPathComponent("AppIcon.png") }
    static var hasCustom: Bool { Files.fm.fileExists(atPath: file.path) }

    static func apply() {
        if hasCustom, let img = NSImage(contentsOf: file) { NSApp.applicationIconImage = img } else { NSApp.applicationIconImage = nil }
    }
    /// Prüft Format und Größe; Rückgabe: Fehlertext oder nil.
    static func validate(_ data: Data) -> String? {
        guard let rep = NSBitmapImageRep(data: data), data.starts(with: [0x89, 0x50, 0x4E, 0x47]) else { return L("Die Datei ist kein PNG.", "The file is not a PNG.") }
        guard rep.pixelsWide == 256, rep.pixelsHigh == 256 else { return L("Das Bild ist \(rep.pixelsWide) × \(rep.pixelsHigh) Pixel groß – erforderlich sind genau 256 × 256.", "The image is \(rep.pixelsWide) × \(rep.pixelsHigh) pixels – exactly 256 × 256 is required.") }
        return nil
    }
    @discardableResult static func set(from url: URL) -> Bool {
        guard let d = try? Data(contentsOf: url) else { FileOps.shared.alert(L("Die Datei konnte nicht gelesen werden.", "The file couldn\u{2019}t be read.")); return false }
        if let err = validate(d) { FileOps.shared.alert(L("Das Programmsymbol kann nicht verwendet werden.", "The app icon can\u{2019}t be used."), err); return false }
        try? Files.fm.createDirectory(at: dir, withIntermediateDirectories: true)
        do { try d.write(to: file, options: .atomic) } catch { FileOps.shared.alert(error.localizedDescription); return false }
        apply(); return true
    }
    static func choose() -> Bool {
        let p = NSOpenPanel(); p.allowedContentTypes = [.png]; p.message = L("Wählen Sie ein PNG mit genau 256 × 256 Pixeln.", "Choose a PNG that is exactly 256 × 256 pixels.")
        guard p.runModal() == .OK, let u = p.url else { return false }
        return set(from: u)
    }
    static func reset() { try? Files.fm.removeItem(at: file); apply() }
}
