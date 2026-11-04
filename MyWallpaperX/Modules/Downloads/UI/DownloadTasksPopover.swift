import AppKit
import Combine

@MainActor final class DownloadTasksPopoverController: NSObject, NSPopoverDelegate {
    static let panelSize = NSSize(width: 400, height: 460)
    private let popover = NSPopover()
    private lazy var scrollDismissal = ToolbarPopoverScrollDismissal(popover: popover)
    private let contentController: DownloadTasksContentController

    init(snapshot: @escaping () -> DownloadTaskSnapshot, changes: AnyPublisher<Void, Never>,
         bindings: DownloadTaskRowPresentation.Bindings, retryAllFailed: (([DownloadTaskRow]) -> Void)? = nil,
         clearHistory: (() -> Void)? = nil) {
        contentController = DownloadTasksContentController(snapshot: snapshot, changes: changes, bindings: bindings,
            retryAllFailed: retryAllFailed, clearHistory: clearHistory)
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = contentController
        contentController.loadViewIfNeeded()
        popover.contentSize = contentController.preferredContentSize
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo toolbarItem: NSToolbarItem, in window: NSWindow) {
        guard let toolbar = toolbarItem.toolbar, toolbar === window.toolbar,
              let contentView = window.contentView else { return }
        if popover.isShown { close(); return }
        contentController.startObserving()
        scrollDismissal.watch(relativeTo: contentView)
        popover.show(relativeTo: toolbarItem)
    }

    func close() {
        popover.performClose(nil)
        contentController.stopObserving()
    }

    func popoverDidClose(_ notification: Notification) { contentController.stopObserving() }
}

/// Aggregation presentation only. The App connects the original publishers and
/// source commands; opening local history performs no authentication or scan.
@MainActor final class DownloadTasksContentController: NSViewController, NSTableViewDelegate {
    private enum Section: Hashable { case content }
    private enum Item: Hashable {
        case notice, activeHeader, historyHeader
        case task(DownloadTaskIdentity)
    }
    private let snapshot: () -> DownloadTaskSnapshot
    private let changes: AnyPublisher<Void, Never>
    private let bindings: DownloadTaskRowPresentation.Bindings
    private let retryAllFailed: (([DownloadTaskRow]) -> Void)?
    private let clearHistory: (() -> Void)?
    private var subscription: AnyCancellable?
    private var statesByID: [DownloadTaskIdentity: DownloadTaskRowPresentation] = [:]
    private var dataSource: NSTableViewDiffableDataSource<Section, Item>!
    private let countLabel = NSTextField(labelWithString: "")
    private let retryButton = NSButton(title: "重试全部", target: nil, action: nil)
    private let clearButton = NSButton(title: "清空历史", target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "暂无下载任务")
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let activeLabel = NSTextField(labelWithString: "进行中")
    private let historyLabel = NSTextField(labelWithString: "历史记录")
    private let noticeLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var activeCell = DownloadTasksTableCell(content: activeLabel, identifier: NSUserInterfaceItemIdentifier("active"))
    private lazy var historyCell = DownloadTasksTableCell(content: historyLabel, identifier: NSUserInterfaceItemIdentifier("history"))
    private lazy var noticeCell = DownloadTasksTableCell(content: noticeLabel, identifier: NSUserInterfaceItemIdentifier("notice"))

    init(snapshot: @escaping () -> DownloadTaskSnapshot, changes: AnyPublisher<Void, Never>,
         bindings: DownloadTaskRowPresentation.Bindings, retryAllFailed: (([DownloadTaskRow]) -> Void)?, clearHistory: (() -> Void)?) {
        self.snapshot = snapshot
        self.changes = changes
        self.bindings = bindings
        self.retryAllFailed = retryAllFailed
        self.clearHistory = clearHistory
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = DownloadTasksPopoverController.panelSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let size = DownloadTasksPopoverController.panelSize
        let root = DownloadTasksRootView(frame: NSRect(origin: .zero, size: size))
        root.onThumbnailRequest = { [weak self] request in
            guard let self else { return }
            for item in dataSource.snapshot().itemIdentifiers {
                if case .task(let id) = item { statesByID[id]?.prepareThumbnail(request) }
            }
        }
        view = root
        preferredContentSize = size
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: size.width),
            root.heightAnchor.constraint(equalToConstant: size.height)
        ])
        countLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        countLabel.textColor = .secondaryLabelColor
        for button in [retryButton, clearButton] {
            button.bezelStyle = .inline
            button.controlSize = .small
            button.target = self
            button.isEnabled = false
        }
        retryButton.action = #selector(handleRetryAll)
        retryButton.toolTip = "经原来源重试失败任务"
        clearButton.action = #selector(handleClearHistory)
        clearButton.toolTip = "只清除历史记录，保留活动任务和已下载文件"
        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        for label in [activeLabel, historyLabel] {
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
        }
        noticeLabel.textColor = .secondaryLabelColor
        noticeLabel.font = .systemFont(ofSize: 11)
        tableView.frame = NSRect(x: 0, y: 0, width: size.width, height: 0)
        tableView.autoresizingMask = [.width]
        tableView.style = .plain
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.focusRingType = .none
        tableView.floatsGroupRows = false
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = 76
        tableView.intercellSpacing = .zero
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("task"))
        column.width = size.width
        column.minWidth = 0
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        dataSource = NSTableViewDiffableDataSource(tableView: tableView) { [weak self] table, _, _, item in
            self?.cell(for: item, in: table) ?? NSView()
        }
        tableView.delegate = self
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        for child in [countLabel, retryButton, clearButton, scrollView, emptyLabel] {
            child.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(child)
        }
        NSLayoutConstraint.activate([
            countLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            countLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            clearButton.centerYAnchor.constraint(equalTo: countLabel.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            retryButton.centerYAnchor.constraint(equalTo: countLabel.centerYAnchor),
            retryButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
    }

    func startObserving() {
        guard subscription == nil else { return }
        // The App's aggregate publishes after source willSet delivery has
        // settled on the main lane; the panel needs no second queue hop.
        subscription = changes.sink { [weak self] in self?.reconcile() }
        reconcile()
    }

    func stopObserving() {
        subscription?.cancel()
        subscription = nil
        tableView.enumerateAvailableRowViews { [self] rowView, _ in unbindView(in: rowView) }
        statesByID.values.forEach { $0.unbind() }
        statesByID.removeAll()
        dataSource.apply(NSDiffableDataSourceSnapshot<Section, Item>(), animatingDifferences: false)
    }

    private func reconcile() {
        let value = snapshot()
        let rows = value.active + value.history
        let liveIDs = Set(rows.map(\.id))
        for (id, state) in statesByID where !liveIDs.contains(id) {
            state.unbind()
            statesByID.removeValue(forKey: id)
        }
        let request = view.window.flatMap { DownloadTaskRowPresentation.thumbnailRequest(for: $0) }
        for row in rows {
            let state = statesByID[row.id] ?? DownloadTaskRowPresentation(bindings: bindings)
            statesByID[row.id] = state
            state.configure(row, request: request)
        }
        let noticeChanged = noticeLabel.stringValue != (value.notice ?? "")
        noticeLabel.stringValue = value.notice ?? ""
        activeLabel.stringValue = "进行中 · \(value.active.count)"
        historyLabel.stringValue = "历史记录 · \(value.history.count)"
        var ordered: [Item] = []
        if value.notice != nil { ordered.append(.notice) }
        if !value.active.isEmpty { ordered.append(.activeHeader) }
        ordered.append(contentsOf: value.active.map { .task($0.id) })
        if !value.history.isEmpty { ordered.append(.historyHeader) }
        ordered.append(contentsOf: value.history.map { .task($0.id) })
        let current = dataSource.snapshot()
        if current.sectionIdentifiers != [.content] || current.itemIdentifiers != ordered {
            var next = NSDiffableDataSourceSnapshot<Section, Item>()
            next.appendSections([.content])
            next.appendItems(ordered, toSection: .content)
            dataSource.apply(next, animatingDifferences: false)
        } else if noticeChanged {
            updateNoticeHeight()
        }
        countLabel.stringValue = "下载任务 · \(value.count) 项"
        retryButton.isEnabled = retryAllFailed != nil && value.history.contains { $0.phase == .failed && $0.actions.contains(.retry) }
        clearButton.isEnabled = clearHistory != nil && !value.history.isEmpty
        emptyLabel.isHidden = value.count != 0
    }

    private func cell(for item: Item, in table: NSTableView) -> NSView {
        switch item {
        case .task(let id):
            let identifier = NSUserInterfaceItemIdentifier("download-task")
            let cell = table.makeView(withIdentifier: identifier, owner: self) as? DownloadTasksTableCell
                ?? DownloadTasksTableCell(content: DownloadTaskRowView(frame: .zero), identifier: identifier)
            (cell.content as! DownloadTaskRowView).bind(statesByID[id])
            return cell
        case .notice: return noticeCell
        case .activeHeader: return activeCell
        case .historyHeader: return historyCell
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch dataSource.itemIdentifier(forRow: row) {
        case .notice?:
            let bounds = NSRect(x: 0, y: 0, width: max(1, tableView.bounds.width - 32), height: .greatestFiniteMagnitude)
            return max(14, ceil(noticeLabel.cell?.cellSize(forBounds: bounds).height ?? 14))
        case .activeHeader?, .historyHeader?: return 14
        default: return 76
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int) {
        unbindView(in: rowView)
    }

    private func unbindView(in rowView: NSTableRowView) {
        let cell = rowView.view(atColumn: 0) as? DownloadTasksTableCell
        (cell?.content as? DownloadTaskRowView)?.bind(nil)
    }

    func tableViewColumnDidResize(_ notification: Notification) { updateNoticeHeight() }

    private func updateNoticeHeight() {
        if let row = dataSource.row(forItemIdentifier: .notice) {
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
        }
    }

    @objc private func handleRetryAll() {
        let candidates = dataSource.snapshot().itemIdentifiers.compactMap { item -> DownloadTaskRow? in
            guard case .task(let id) = item else { return nil }
            return statesByID[id]?.row
        }
            .filter { $0.phase == .failed && $0.actions.contains(.retry) }
        retryAllFailed?(candidates)
    }
    @objc private func handleClearHistory() { clearHistory?() }
}

private final class DownloadTasksTableCell: NSTableCellView {
    let content: NSView

    init(content: NSView, identifier: NSUserInterfaceItemIdentifier) {
        self.content = content
        super.init(frame: .zero)
        self.identifier = identifier
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

private final class DownloadTasksRootView: NSView {
    var onThumbnailRequest: ((ThumbnailRequest) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        prepareThumbnails()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        prepareThumbnails()
    }

    private func prepareThumbnails() {
        if let window, let request = DownloadTaskRowPresentation.thumbnailRequest(for: window) {
            onThumbnailRequest?(request)
        }
    }
}
