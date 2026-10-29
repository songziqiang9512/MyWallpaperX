import AppKit

/// Test adapter over real checkbox views/actions, without duplicating filter rules.
@MainActor func nativeFilterMenuSnapshot(_ controller: NSViewController) -> NSMenu {
    controller.loadViewIfNeeded()
    let menu = NSMenu()
    menu.autoenablesItems = false
    func append(_ button: NSButton) {
        let item = ActionMenuItem(title: button.title, symbol: "") {
            withExtendedLifetime(controller) { button.performClick(nil) }
        }
        item.isEnabled = button.isEnabled
        item.state = button.state
        menu.addItem(item)
    }
    let groups = controller.view.subviews.first as! NSStackView
    for (index, child) in groups.arrangedSubviews.enumerated() {
        if index > 0 { menu.addItem(.separator()) }
        let block = child as! NSStackView
        let title = block.arrangedSubviews[0] as! NSTextField
        let header = NSMenuItem.sectionHeader(title: title.stringValue)
        header.isEnabled = false
        menu.addItem(header)
        let grid = block.arrangedSubviews[1] as! NSGridView
        for row in 0..<grid.numberOfRows {
            for column in 0..<grid.numberOfColumns {
                if let button = grid.cell(atColumnIndex: column, rowIndex: row).contentView as? NSButton {
                    append(button)
                }
            }
        }
    }
    menu.addItem(.separator())
    let footer = controller.view.subviews.last as! NSStackView
    footer.arrangedSubviews.compactMap { $0 as? NSButton }.forEach(append)
    return menu
}
