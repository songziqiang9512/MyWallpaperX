//
//  ToolbarMenuPopover.swift
//  MyWallpaperX
//

import AppKit

/// 工具栏菜单按钮的统一 popover 呈现器：面板宽度自适应行内容，锚定触发
/// 按钮（.maxY 边，三角箭头指向按钮）。勾选行点击后面板保持打开并按
/// provider 重绘；动作行点击后关闭。每个工具栏控制器持有一个实例。
@MainActor
final class ToolbarMenuPopoverPresenter: NSObject, NSPopoverDelegate {
    struct Row {
        enum Kind {
            /// 点击后关闭面板
            case action
            /// 点击后保持打开，按 provider 重绘
            case check
            /// 灰显状态行，不可点
            case info
            case sectionHeader
            case separator
        }

        var title: String
        var kind: Kind
        var isChecked: Bool = false
        var isEnabled: Bool = true
        var handler: (() -> Void)?

        static func separator() -> Row {
            Row(title: "", kind: .separator)
        }

        static func header(_ title: String) -> Row {
            Row(title: title, kind: .sectionHeader)
        }
    }

    private let popover = NSPopover()
    private weak var anchoredView: NSView?
    private var contentProvider: (() -> [Row])?
    private let rowsViewController = ToolbarMenuRowsViewController()
    /// 锚定视图不在窗口（工具栏溢出为菜单项）时的兜底锚点。
    private let fallbackAnchorProvider: (() -> NSView?)?

    init(fallbackAnchorProvider: (() -> NSView?)? = nil) {
        self.fallbackAnchorProvider = fallbackAnchorProvider
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = rowsViewController
    }

    var isShown: Bool { popover.isShown }

    /// 已锚定同一按钮则关闭（toggle 语义）；否则打开/换锚重开。
    func toggle(anchor: NSView, rows provider: @escaping () -> [Row]) {
        if popover.isShown {
            let sameAnchor = anchoredView === anchor
            close()
            guard !sameAnchor else { return }
        }
        var positioningRect = anchor.bounds
        let resolvedAnchor: NSView
        if anchor.window != nil {
            resolvedAnchor = anchor
        } else if let fallback = fallbackAnchorProvider?(), fallback.window != nil {
            // 溢出兜底：锚窗口右上角（与下载任务/筛选面板的兜底约定一致）。
            resolvedAnchor = fallback
            positioningRect = NSRect(
                x: max(0, fallback.bounds.maxX - 32),
                y: fallback.bounds.maxY,
                width: 1,
                height: 1
            )
        } else {
            return
        }
        anchoredView = anchor
        contentProvider = provider
        reload(provider())
        popover.show(relativeTo: positioningRect, of: resolvedAnchor, preferredEdge: .maxY)
    }

    func close() {
        popover.performClose(nil)
    }

    private func reload(_ rows: [Row]) {
        rowsViewController.reload(rows: rows) { [weak self] row in
            self?.handleSelection(of: row)
        }
        let contentSize = NSSize(width: rowsViewController.preferredWidth, height: rowsViewController.preferredHeight)
        popover.contentSize = contentSize
        rowsViewController.preferredContentSize = contentSize
    }

    func popoverDidClose(_ notification: Notification) {
        // 换锚重开时，上一次 .transient 关闭的晚到回调会在这里触发；
        // 此时 popover 已承载新一次呈现（isShown == true），不得清掉它。
        guard !popover.isShown else { return }
        anchoredView = nil
        contentProvider = nil
    }

    private func handleSelection(of row: Row) {
        switch row.kind {
        case .action:
            row.handler?()
            close()
        case .check:
            row.handler?()
            guard let contentProvider else { return }
            reload(contentProvider())
        default:
            break
        }
    }
}

/// 菜单行内容：竖排行，宽度按最宽行自适应。
@MainActor
private final class ToolbarMenuRowsViewController: NSViewController {
    private static let horizontalInsets: CGFloat = 12 // 仅 stack 边距 6×2；行内 8×2 已含在 fittingSize
    private static let minPanelWidth: CGFloat = 104
    private static let maxPanelWidth: CGFloat = 280
    private static let rowHeight: CGFloat = 26
    private static let headerHeight: CGFloat = 24
    private static let separatorHeight: CGFloat = 5

    private let stack = NSStackView()
    private var selectionHandler: ((ToolbarMenuPopoverPresenter.Row) -> Void)?
    /// 行载荷按视图身份索引（NSButton.objectValue 是按钮状态值，不能携带
    /// 自定义数据）。
    private var rowsByButton: [ObjectIdentifier: ToolbarMenuPopoverPresenter.Row] = [:]
    private var contentRowsHeight: CGFloat = 44
    private(set) var preferredWidth: CGFloat = 120
    private(set) var preferredHeight: CGFloat = 44

    override func loadView() {
        let root = NSView()
        view = root
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6)
        ])
    }

    func reload(rows: [ToolbarMenuPopoverPresenter.Row], selectionHandler: @escaping (ToolbarMenuPopoverPresenter.Row) -> Void) {
        loadViewIfNeeded()
        self.selectionHandler = selectionHandler
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rowsByButton = [:]
        var widestRow: CGFloat = 0
        for row in rows {
            switch row.kind {
            case .separator:
                let box = NSBox()
                box.boxType = .separator
                stack.addArrangedSubview(box)
            case .sectionHeader:
                stack.addArrangedSubview(makeHeaderRow(row.title, widthOut: &widestRow))
            case .info, .action, .check:
                let textWidth = (row.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
                widestRow = max(widestRow, ceil(textWidth) + 36)
                let rowView = makeTitleRow(row.title, isEnabled: row.isEnabled, isChecked: row.isChecked, row: row.kind == .info ? nil : row)
                stack.addArrangedSubview(rowView)
            }
        }
        for rowView in stack.arrangedSubviews {
            rowView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        preferredWidth = min(max(widestRow + Self.horizontalInsets, Self.minPanelWidth), Self.maxPanelWidth)
        let rowHeights = rows.map { row -> CGFloat in
            switch row.kind {
            case .separator: return Self.separatorHeight
            case .sectionHeader: return Self.headerHeight
            default: return Self.rowHeight
            }
        }
        contentRowsHeight = 12 + rowHeights.reduce(0, +)
        preferredHeight = contentRowsHeight
    }

    private func makeHeaderRow(_ title: String, widthOut: inout CGFloat) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: Self.headerHeight),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        widthOut = max(widthOut, label.fittingSize.width + 16)
        return container
    }

    private func makeTitleRow(
        _ title: String,
        isEnabled: Bool,
        isChecked: Bool,
        row: ToolbarMenuPopoverPresenter.Row?
    ) -> NSView {
        let button = NSButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 13)
        button.alignment = .left
        button.lineBreakMode = .byTruncatingTail
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.isEnabled = isEnabled
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        if isChecked {
            button.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        } else {
            let blank = NSImage(size: NSSize(width: 12, height: 12))
            blank.isTemplate = false
            button.image = blank
        }
        // 主色标题：borderless 按钮的默认渲染偏暗，显式用 attributedTitle
        // 避免看起来像不可点击；info 行（无动作）保持灰显语义。
        let dimmed = row == nil
        let textColor: NSColor = dimmed || !isEnabled ? .secondaryLabelColor : .labelColor
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: textColor, .font: NSFont.systemFont(ofSize: 13)]
        )
        if let row {
            button.target = self
            button.action = #selector(handleRowTap(_:))
            button.setAccessibilityLabel(title)
            button.setAccessibilityValue(isChecked ? "已勾选" : "未勾选")
            rowsByButton[ObjectIdentifier(button)] = row
        } else {
            button.setAccessibilityLabel(title)
        }
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    @objc private func handleRowTap(_ sender: NSButton) {
        guard let row = rowsByButton[ObjectIdentifier(sender)] else { return }
        selectionHandler?(row)
    }
}
