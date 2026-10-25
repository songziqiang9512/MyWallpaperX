import AppKit

/// A native menu item retains the fixed command captured when its menu opened.
@MainActor
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void
    private var permission: (() -> Bool)?
    init(title: String, symbol: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func requirePermission(_ predicate: @escaping () -> Bool) {
        let previous = permission
        permission = { previous?() != false && predicate() }
    }
    @objc private func invoke() {
        guard permission?() != false else { return }; handler()
    }
}

// Composed menus can contain source-owned commands and nested playlist items.
// Gate only new menu invocations; admitted async work keeps its original owner.
@MainActor extension NSMenu {
    func requireAppActionPermission(_ predicate: @escaping () -> Bool) {
        for item in items {
            (item as? ActionMenuItem)?.requirePermission(predicate)
            item.submenu?.requireAppActionPermission(predicate)
        }
    }
}
