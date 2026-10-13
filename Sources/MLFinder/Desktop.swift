import AppKit

/// Optionaler Schreibtisch (N-14): zeigt ~/Desktop und die in den Einstellungen gewählten Volumes als freie Symbolfläche
/// über dem Hintergrundbild. Standardmäßig aus (in RetroMac übernimmt die vorhandene Desktop-Komponente diese Aufgabe).
final class DesktopController: NSObject {
    static var shared: DesktopController?
    static var isOn: Bool { Prefs.bool("desktopOn", false) }
    let win: NSWindow
    let bc: BrowserController

    static func apply() {
        if isOn { if shared == nil { shared = DesktopController() } } else { shared?.close(); shared = nil }
    }
    override init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        bc = BrowserController(location: .folder(Files.desktop), size: NSSize(width: 800, height: 600), showWindow: false)
        bc.desktopMode = true
        win = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        win.isOpaque = false; win.backgroundColor = .clear; win.hasShadow = false; win.isReleasedWhenClosed = false
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        var o = bc.options; o.mode = .icon; o.arrange = "none"; o.iconSize = 64; o.textSize = 12; bc.options = o
        bc.buildItemView(); bc.load()
        guard let sc = bc.scroll, let iv = bc.itemView as? IconView else { return }
        iv.desktop = true; sc.removeFromSuperview(); sc.drawsBackground = false; sc.hasVerticalScroller = false
        sc.frame = NSRect(origin: .zero, size: screen.frame.size); sc.autoresizingMask = [.width, .height]
        let host = NSView(frame: sc.frame); host.addSubview(sc); win.contentView = host
        iv.relayout()
        win.orderFront(nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reflow), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    @objc func reflow() { if let s = NSScreen.main { win.setFrame(s.frame, display: true); (bc.itemView as? IconView)?.relayout() } }
    func close() { win.orderOut(nil); bc.watcher?.cancel() }
}
