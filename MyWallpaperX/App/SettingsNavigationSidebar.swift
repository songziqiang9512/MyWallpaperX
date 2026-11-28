import AppKit

final class SettingsNavigationSidebar: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onCategory: ((AppSettingsSection) -> Void)?
    private let categories = AppSettingsSection.allCases
    private let table = NSTableView()

    override func loadView() {
        let backdrop = NSVisualEffectView()
        backdrop.material = .sidebar
        backdrop.blendingMode = .withinWindow
        view = backdrop

        table.style = .sourceList
        table.headerView = nil
        table.rowHeight = 36
        table.intercellSpacing.height = 0
        table.allowsEmptySelection = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let column = NSTableColumn(identifier: .init("SettingsCategory"))
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self

        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = table
        backdrop.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: backdrop.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor)
        ])
    }

    func select(_ category: AppSettingsSection) {
        loadViewIfNeeded()
        if let row = categories.firstIndex(of: category), row != table.selectedRow {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { categories.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let index = table.selectedRow
        if categories.indices.contains(index) { onCategory?(categories[index]) }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()
        rowView.isEmphasized = false
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let category = categories[row]
        let cell = NSTableCellView()
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: category.symbolName, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 18, weight: .bold)
        icon.contentTintColor = .textColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityElement(false)
        let title = NSTextField(labelWithString: category.title)
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        title.lineBreakMode = .byTruncatingTail
        cell.toolTip = title.stringValue
        cell.imageView = icon
        cell.textField = title
        let content = NSStackView(views: [icon, title])
        content.alignment = .centerY
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(content)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            content.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 1),
            content.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            content.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
}
