import AppKit

/// Barrierefreiheit (§15.4): selbst gezeichnete Ansichten stellen Objekte mit Namen, Rolle und Auswahlzustand bereit.
enum AX {
    static func element(parent: NSView, label: String, role: NSAccessibility.Role, frame: NSRect, selected: Bool, help: String? = nil) -> NSAccessibilityElement {
        let e = NSAccessibilityElement()
        e.setAccessibilityParent(parent); e.setAccessibilityRole(role); e.setAccessibilityLabel(label)
        e.setAccessibilityFrameInParentSpace(frame); e.setAccessibilitySelected(selected)
        if let help { e.setAccessibilityHelp(help) }
        return e
    }
}

extension IconView {
    override func accessibilityChildren() -> [Any]? {
        axCells().map { c in AX.element(parent: self, label: c.node.name + (c.node.isDir ? ", " + L("Ordner", "folder") : ", " + c.node.displayKind), role: .row, frame: c.frame, selected: host?.isSelected(c.node.url) ?? false) }
    }
}
extension SidebarView {
    override func accessibilityChildren() -> [Any]? {
        axRows().map { r in AX.element(parent: self, label: r.title, role: r.isHeader ? .staticText : .row, frame: r.rect, selected: r.selected) }
    }
}
extension RowsView {
    override func accessibilityChildren() -> [Any]? {
        guard let l = list else { return nil }
        return l.rows.enumerated().map { i, r in AX.element(parent: self, label: "\(r.node.name), \(r.node.displayKind), \(Files.sizeString(r.node.size))", role: .row, frame: NSRect(x: 0, y: CGFloat(i) * l.rowHeight, width: bounds.width, height: l.rowHeight), selected: l.host?.isSelected(r.node.url) ?? false) }
    }
}
