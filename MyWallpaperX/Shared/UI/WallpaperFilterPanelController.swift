import AppKit

/// Native geometry shared by source filters. Query values and selection rules
/// stay with the source; each checkbox reads that owner's current value.
@MainActor class WallpaperFilterPanelController: NSViewController {
    struct Option {
        let title: String
        let isSelected: () -> Bool
        let toggle: () -> Void
    }
    struct Section {
        let title: String
        let columns: Int
        let options: [Option]
    }
    static let panelWidth: CGFloat = 400
    static let minimumResolutions: [(title: String, width: Int, height: Int)] = [
        ("不限", 0, 0), ("1080p 及以上", 1920, 1080), ("2K 及以上", 2560, 1440), ("4K 及以上", 3840, 2160)
    ]
    private let sections: [Section]
    private let summary: () -> String
    private let canClear: () -> Bool
    private let clear: () -> Void
    private var checkboxes: [(NSButton, Option)] = []
    private lazy var clearButton = NSButton(title: "清空筛选", target: nil, action: nil)
    private lazy var summaryLabel = NSTextField(labelWithString: "")
    private(set) var preferredPanelHeight: CGFloat = 240

    init(sections: [Section], summary: @escaping () -> String, canClear: @escaping () -> Bool,
         clear: @escaping () -> Void) {
        self.sections = sections; self.summary = summary; self.canClear = canClear; self.clear = clear
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: .init(x: 0, y: 0, width: Self.panelWidth, height: 1))
        let groups = NSStackView()
        groups.orientation = .vertical; groups.alignment = .leading; groups.spacing = 10
        groups.translatesAutoresizingMaskIntoConstraints = false
        for section in sections {
            let title = NSTextField(labelWithString: section.title)
            title.font = .systemFont(ofSize: 11, weight: .semibold); title.textColor = .secondaryLabelColor
            let buttons = section.options.map { option -> NSView in
                let button = NSButton(checkboxWithTitle: option.title, target: self, action: #selector(toggle(_:)))
                button.font = .systemFont(ofSize: 12.5); button.controlSize = .small; button.contentTintColor = .labelColor
                button.setAccessibilityLabel("\(section.title)：\(option.title)")
                checkboxes.append((button, option))
                return button
            }
            let rows = stride(from: 0, to: buttons.count, by: section.columns).map {
                Array(buttons[$0..<min($0 + section.columns, buttons.count)])
            }
            let grid = NSGridView(views: rows)
            grid.translatesAutoresizingMaskIntoConstraints = false
            grid.rowSpacing = 6; grid.columnSpacing = 12
            let width = ((Self.panelWidth - 28 - CGFloat(section.columns - 1) * 12) / CGFloat(section.columns)).rounded(.down)
            for index in 0..<grid.numberOfColumns { grid.column(at: index).width = width }
            let block = NSStackView(views: [title, grid])
            block.orientation = .vertical; block.alignment = .leading; block.spacing = 6
            groups.addArrangedSubview(block)
        }
        clearButton.bezelStyle = .rounded; clearButton.controlSize = .small
        clearButton.target = self; clearButton.action = #selector(clearFilters)
        clearButton.setAccessibilityLabel("清空全部筛选")
        summaryLabel.font = .systemFont(ofSize: 11); summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        let footer = NSStackView(views: [clearButton, summaryLabel])
        footer.orientation = .horizontal; footer.alignment = .centerY; footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false
        let divider = NSBox(); divider.boxType = .separator; divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(groups); view.addSubview(divider); view.addSubview(footer)
        NSLayoutConstraint.activate([
            groups.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            groups.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            groups.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            divider.topAnchor.constraint(equalTo: groups.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: groups.leadingAnchor), divider.trailingAnchor.constraint(equalTo: groups.trailingAnchor),
            footer.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 10),
            footer.leadingAnchor.constraint(equalTo: groups.leadingAnchor), footer.trailingAnchor.constraint(equalTo: groups.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            summaryLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Self.panelWidth - 130)
        ])
        synchronize()
        view.layoutSubtreeIfNeeded()
        preferredPanelHeight = min(view.fittingSize.height, 560)
        preferredContentSize = .init(width: Self.panelWidth, height: preferredPanelHeight)
    }

    func synchronize() {
        guard isViewLoaded else { return }
        for (button, option) in checkboxes { button.state = option.isSelected() ? .on : .off }
        clearButton.isEnabled = canClear()
        summaryLabel.stringValue = "当前筛选：" + summary()
    }

    func menuRepresentation(title: String) -> NSMenuItem {
        let root = NSMenuItem(title: title, action: nil, keyEquivalent: ""), menu = NSMenu()
        menu.autoenablesItems = false
        for (index, section) in sections.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            menu.addItem(.sectionHeader(title: section.title))
            for option in section.options {
                let item = ActionMenuItem(title: option.title, symbol: "") { option.toggle() }
                item.state = option.isSelected() ? .on : .off
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let clearItem = ActionMenuItem(title: "清空筛选", symbol: "") { [clear] in clear() }
        clearItem.isEnabled = canClear(); menu.addItem(clearItem)
        root.submenu = menu
        return root
    }
    @objc private func toggle(_ sender: NSButton) {
        checkboxes.first { $0.0 === sender }?.1.toggle()
        synchronize()
    }
    @objc private func clearFilters() { clear(); synchronize() }
}
