import AppKit

enum SettingsPanelLayout {
    static let pageWidth: CGFloat = 620
    static let pageInset: CGFloat = 20
    // CotEditor leaves a 24 pt help button and one group gap below its last setting.
    static let bottomInset: CGFloat = pageInset + groupSpacing + 24
    static let groupSpacing: CGFloat = 18
    static let columnSpacing: CGFloat = 8
    static let controlSpacing: CGFloat = 6
    static let subordinateInset: CGFloat = 20
    static let checkboxTextInset: CGFloat = 22
}

final class SettingsFormView: NSGridView {
    init(rowSpacing: CGFloat = SettingsPanelLayout.groupSpacing) {
        super.init(frame: .zero)
        addColumn(with: [])
        addColumn(with: [])
        self.rowSpacing = rowSpacing
        columnSpacing = SettingsPanelLayout.columnSpacing
        rowAlignment = .firstBaseline
        yPlacement = .top
        column(at: 0).width = 0
        column(at: 0).xPlacement = .trailing
        column(at: 1).xPlacement = .fill
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @discardableResult
    func addGroup(_ title: String, controls: [NSView]) -> NSGridRow {
        let caption = NSTextField(labelWithString: String(localized: "\(title):"))
        column(at: 0).width = max(column(at: 0).width, caption.intrinsicContentSize.width)
        return addRow(with: [caption, Self.controls(controls)])
    }

    func addDivider() {
        let divider = NSBox()
        divider.boxType = .separator
        divider.setAccessibilityElement(false)

        let row = addRow(with: [divider, NSGridCell.emptyContentView])
        row.mergeCells(in: NSRange(location: 0, length: 2))
        row.rowAlignment = .none
        row.cell(at: 0).xPlacement = .fill
    }

    static func controls(_ views: [NSView], horizontal: Bool = false, indent: CGFloat = 0) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = horizontal ? .horizontal : .vertical
        stack.alignment = horizontal ? .firstBaseline : .leading
        stack.spacing = horizontal ? SettingsPanelLayout.columnSpacing : SettingsPanelLayout.controlSpacing
        stack.edgeInsets.left = indent
        return stack
    }

    static func detail(_ text: String, indent: CGFloat = 0) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        let detail = controls([label], indent: indent)
        label.widthAnchor.constraint(equalTo: detail.widthAnchor, constant: -indent).isActive = true
        return detail
    }
}
