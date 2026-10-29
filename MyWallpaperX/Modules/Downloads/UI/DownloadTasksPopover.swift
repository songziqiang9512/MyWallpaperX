import AppKit
import Combine

@MainActor final class DownloadTasksPopoverController: NSObject, NSPopoverDelegate {
    static let panelSize = NSSize(width: 400, height: 460)
    private let popover = NSPopover()
    private lazy var scrollDismissal = ToolbarPopoverScrollDismissal(popover: popover)
    private let contentController: DownloadTasksContentController

    init(snapshot: @escaping () -> DownloadTaskSnapshot, changes: AnyPublisher<Void, Never>,
         bindings: DownloadTaskRowView.Bindings, retryAllFailed: (([DownloadTaskRow]) -> Void)? = nil,
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
@MainActor final class DownloadTasksContentController: NSViewController {
    private let snapshot: () -> DownloadTaskSnapshot
    private let changes: AnyPublisher<Void, Never>
    private let bindings: DownloadTaskRowView.Bindings
    private let retryAllFailed: (([DownloadTaskRow]) -> Void)?
    private let clearHistory: (() -> Void)?
    private var subscription: AnyCancellable?
    private var rowsByID: [DownloadTaskIdentity: DownloadTaskRowView] = [:]
    private let countLabel = NSTextField(labelWithString: "")
    private let retryButton = NSButton(title: "重试全部", target: nil, action: nil)
    private let clearButton = NSButton(title: "清空历史", target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "暂无下载任务")
    private let scrollView = NSScrollView()
    private let documentView = DownloadTasksDocumentView()
    private let rowsStack = NSStackView()
    private let activeLabel = NSTextField(labelWithString: "进行中")
    private let historyLabel = NSTextField(labelWithString: "历史记录")
    private let noticeLabel = NSTextField(wrappingLabelWithString: "")

    init(snapshot: @escaping () -> DownloadTaskSnapshot, changes: AnyPublisher<Void, Never>,
         bindings: DownloadTaskRowView.Bindings, retryAllFailed: (([DownloadTaskRow]) -> Void)?, clearHistory: (() -> Void)?) {
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
        let root = NSView(frame: NSRect(origin: .zero, size: size))
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
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 0
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        noticeLabel.textColor = .secondaryLabelColor
        noticeLabel.font = .systemFont(ofSize: 11)
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(rowsStack)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
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
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            rowsStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 16),
            rowsStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -16),
            rowsStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
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
        rowsByID.values.forEach { $0.unbind() }
        rowsByID.removeAll()
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    private func reconcile() {
        let value = snapshot()
        let rows = value.active + value.history
        let liveIDs = Set(rows.map(\.id))
        for (id, row) in rowsByID where !liveIDs.contains(id) {
            row.unbind()
            rowsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
            rowsByID.removeValue(forKey: id)
        }
        for row in rows {
            if let existing = rowsByID[row.id] { existing.configure(row) }
            else {
                let view = DownloadTaskRowView(bindings: bindings)
                rowsByID[row.id] = view
                view.configure(row)
            }
        }
        activeLabel.stringValue = "进行中 · \(value.active.count)"
        historyLabel.stringValue = "历史记录 · \(value.history.count)"
        var ordered: [NSView] = []
        if let notice = value.notice { noticeLabel.stringValue = notice; ordered.append(noticeLabel) }
        if !value.active.isEmpty { ordered.append(activeLabel) }
        ordered.append(contentsOf: value.active.compactMap { rowsByID[$0.id] })
        if !value.history.isEmpty { ordered.append(historyLabel) }
        ordered.append(contentsOf: value.history.compactMap { rowsByID[$0.id] })
        let retained = Set(ordered.map(ObjectIdentifier.init))
        for child in rowsStack.arrangedSubviews where !retained.contains(ObjectIdentifier(child)) {
            rowsStack.removeArrangedSubview(child)
            child.removeFromSuperview()
        }
        var installed = rowsStack.arrangedSubviews
        let installedIDs = Set(installed.map(ObjectIdentifier.init))
        for (index, child) in ordered.enumerated() {
            if installed.indices.contains(index), installed[index] === child { continue }
            if installedIDs.contains(ObjectIdentifier(child)), let previous = installed.firstIndex(where: { $0 === child }) {
                rowsStack.removeArrangedSubview(child)
                installed.remove(at: previous)
            }
            rowsStack.insertArrangedSubview(child, at: index)
            // Reordering retains these constraints; detached views install them only after joining the stack.
            if !installedIDs.contains(ObjectIdentifier(child)), child === noticeLabel || child is DownloadTaskRowView {
                child.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
            }
            installed.insert(child, at: index)
        }
        countLabel.stringValue = "下载任务 · \(value.count) 项"
        retryButton.isEnabled = retryAllFailed != nil && value.history.contains { $0.phase == .failed && $0.actions.contains(.retry) }
        clearButton.isEnabled = clearHistory != nil && !value.history.isEmpty
        emptyLabel.isHidden = value.count != 0
    }

    @objc private func handleRetryAll() {
        let candidates = rowsStack.arrangedSubviews.compactMap { ($0 as? DownloadTaskRowView)?.displayedTask }
            .filter { $0.phase == .failed && $0.actions.contains(.retry) }
        retryAllFailed?(candidates)
    }
    @objc private func handleClearHistory() { clearHistory?() }
}

private final class DownloadTasksDocumentView: NSView {
    override var isFlipped: Bool { true }
}
