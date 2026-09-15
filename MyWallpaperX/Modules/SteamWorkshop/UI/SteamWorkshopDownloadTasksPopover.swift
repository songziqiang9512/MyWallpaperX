import AppKit
import Combine

final class SteamWorkshopDownloadTasksToolbarButton: NSView {
    let button = NSButton(frame: .zero)
    private let badgeLabel = NSTextField(labelWithString: "")

    init(target: AnyObject, action: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 38, height: 32))
        translatesAutoresizingMaskIntoConstraints = false

        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .texturedRounded
        button.setButtonType(.momentaryPushIn)
        button.isBordered = true
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.image = NSImage(
            systemSymbolName: "arrow.down.to.line.compact",
            accessibilityDescription: "下载任务"
        ) ?? NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "下载任务")
        button.target = target
        button.action = action

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.alignment = .center
        badgeLabel.font = .systemFont(ofSize: 9, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.backgroundColor = NSColor.systemRed.cgColor
        badgeLabel.layer?.cornerRadius = 7
        badgeLabel.layer?.masksToBounds = true
        badgeLabel.isHidden = true
        badgeLabel.setAccessibilityElement(false)

        addSubview(button)
        addSubview(badgeLabel)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 38),
            heightAnchor.constraint(equalToConstant: 32),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 30),
            badgeLabel.topAnchor.constraint(equalTo: topAnchor),
            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            badgeLabel.heightAnchor.constraint(equalToConstant: 14),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 14)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(count: Int) {
        let safeCount = max(0, count)
        badgeLabel.stringValue = safeCount > 99 ? "99+" : "\(safeCount)"
        badgeLabel.isHidden = safeCount == 0
        let accessibility = "下载任务，\(safeCount) 项"
        button.toolTip = accessibility
        button.setAccessibilityLabel(accessibility)
    }
}

@MainActor
final class SteamWorkshopDownloadTasksPopoverController: NSObject, NSPopoverDelegate {
    private let service: SteamWorkshopService
    private let popover = NSPopover()
    private lazy var contentController = SteamWorkshopDownloadTasksContentController(
        service: service,
        cancelAll: { [weak self] in self?.confirmCancelAll() },
        clearHistory: { [weak self] in self?.confirmClearHistory() },
        showDetail: { [weak self] job in self?.showDetail(for: job) },
        showHistory: { [weak self] summary in self?.showHistory(summary) },
        viewDownloaded: { [weak self] in self?.viewDownloaded() }
    )
    private let windowProvider: () -> NSWindow?

    init(service: SteamWorkshopService, windowProvider: @escaping () -> NSWindow?) {
        self.service = service
        self.windowProvider = windowProvider
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 396, height: 492)
        popover.contentViewController = contentController
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo view: NSView, positioningRect: NSRect? = nil) {
        if popover.isShown {
            close()
            return
        }
        contentController.startObserving()
        popover.show(relativeTo: positioningRect ?? view.bounds, of: view, preferredEdge: .maxY)
    }

    func close() {
        popover.performClose(nil)
        contentController.stopObserving()
    }

    func popoverDidClose(_ notification: Notification) {
        contentController.stopObserving()
    }

    private func confirmCancelAll() {
        let cancellableJobs = SteamWorkshopDownloadTaskProjection.currentJobs(
            from: service.downloadJobStore.jobs,
            accountSteamID: service.steamAuth.steamId
        ).filter(SteamWorkshopDownloadTaskProjection.isCancellable)
        guard !cancellableJobs.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "取消全部下载任务？"
        alert.informativeText = "将停止 \(cancellableJobs.count) 个可取消的进行中或排队任务；已下载文件不会被删除。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消全部")
        alert.addButton(withTitle: "保留任务")

        let apply: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            cancellableJobs.forEach {
                self.service.cancelDownloadImmediately(itemID: $0.workshopItemId, showFeedback: false)
            }
            self.service.statusMessage = "正在取消 \(cancellableJobs.count) 个下载任务…"
        }
        if let window = windowProvider() {
            alert.beginSheetModal(for: window, completionHandler: apply)
        } else {
            apply(alert.runModal())
        }
    }

    private func showDetail(for job: SteamDownloadJob) {
        showWorkshopDetail(itemID: job.workshopItemId, title: job.title)
    }

    private func showHistory(_ summary: SteamWorkshopDownloadHistorySummary) {
        if let recordID = summary.recordID,
           service.availableDownloadRecord(forHistoryRecordID: recordID) != nil {
            close()
            NotificationCenter.default.post(
                name: .appKitSelectItemRequested,
                object: nil,
                userInfo: ["selectedItem": "steamDownloads"]
            )
            DispatchQueue.main.async { [service] in
                service.focusDownloadRecordFromHistory(itemID: recordID)
            }
            return
        }

        if summary.latestOutcome == .completed {
            let alert = NSAlert()
            alert.messageText = "已下载文件不存在"
            alert.informativeText = "历史记录仍会保留，但它不是本地文件或已下载状态的权威。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "查看作品详情")
            alert.addButton(withTitle: "留在历史")
            let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                self?.showWorkshopDetail(itemID: summary.workshopItemID, title: summary.title)
            }
            if let window = windowProvider() {
                alert.beginSheetModal(for: window, completionHandler: handle)
            } else {
                handle(alert.runModal())
            }
            return
        }

        showWorkshopDetail(itemID: summary.workshopItemID, title: summary.title)
    }

    private func showWorkshopDetail(itemID: String, title: String) {
        close()
        NotificationCenter.default.post(
            name: .appKitSelectItemRequested,
            object: nil,
            userInfo: ["selectedItem": "steamWorkshop"]
        )
        DispatchQueue.main.async { [service] in
            service.presentDownloadTaskDetail(itemID: itemID, title: title)
        }
    }

    private func confirmClearHistory() {
        guard let accountSteamID = service.steamAuth.steamId else { return }
        let count = service.downloadJobStore.history(forAccount: accountSteamID).count
        guard count > 0 else { return }

        let alert = NSAlert()
        alert.messageText = "清空下载历史？"
        alert.informativeText = "将删除当前账号的 \(count) 条终结记录；不会取消任务，也不会删除已下载文件。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空历史")
        alert.addButton(withTitle: "保留历史")
        let apply: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let removed = self.service.downloadJobStore.clearHistory(forAccount: accountSteamID)
            self.service.statusMessage = removed > 0
                ? "已清空 \(removed) 条下载历史；已下载文件保持不变。"
                : "无法保存历史清理操作，请重试。"
        }
        if let window = windowProvider() {
            alert.beginSheetModal(for: window, completionHandler: apply)
        } else {
            apply(alert.runModal())
        }
    }

    private func viewDownloaded() {
        close()
        NotificationCenter.default.post(
            name: .appKitSelectItemRequested,
            object: nil,
            userInfo: ["selectedItem": "steamDownloads"]
        )
    }
}

@MainActor
private final class SteamWorkshopDownloadTasksContentController: NSViewController {
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    private let service: SteamWorkshopService
    private let cancelAll: () -> Void
    private let clearHistory: () -> Void
    private let showDetail: (SteamDownloadJob) -> Void
    private let showHistory: (SteamWorkshopDownloadHistorySummary) -> Void
    private let viewDownloaded: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private var rowByJobID: [String: SteamWorkshopDownloadTaskRowView] = [:]
    private var orderedJobIDs: [String] = []
    private var historyRows: [SteamWorkshopDownloadHistoryRowView] = []
    private var renderedHistory: [SteamWorkshopDownloadHistorySummary] = []
    private var latestJobs: [SteamDownloadJob] = []
    private var latestHistory: [SteamDownloadHistoryEntry] = []
    private var latestAccountSteamID: String?
    private var latestSessionExpired = false

    private let countLabel = NSTextField(labelWithString: "")
    private let modeControl = NSSegmentedControl(
        labels: ["进行中", "历史"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let cancelAllButton = NSButton(title: "全部取消", target: nil, action: nil)
    private let clearHistoryButton = NSButton(title: "清空历史", target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "当前没有下载任务")
    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private let rowsStack = NSStackView()

    init(
        service: SteamWorkshopService,
        cancelAll: @escaping () -> Void,
        clearHistory: @escaping () -> Void,
        showDetail: @escaping (SteamDownloadJob) -> Void,
        showHistory: @escaping (SteamWorkshopDownloadHistorySummary) -> Void,
        viewDownloaded: @escaping () -> Void
    ) {
        self.service = service
        self.cancelAll = cancelAll
        self.clearHistory = clearHistory
        self.showDetail = showDetail
        self.showHistory = showHistory
        self.viewDownloaded = viewDownloaded
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        view = root
        preferredContentSize = NSSize(width: 396, height: 492)

        modeControl.selectedSegment = 0
        modeControl.segmentStyle = .rounded
        modeControl.controlSize = .small
        modeControl.target = self
        modeControl.action = #selector(handleModeChanged)
        modeControl.setAccessibilityLabel("下载任务列表")

        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor

        cancelAllButton.bezelStyle = .inline
        cancelAllButton.controlSize = .small
        cancelAllButton.target = self
        cancelAllButton.action = #selector(handleCancelAll)
        cancelAllButton.isEnabled = false
        cancelAllButton.toolTip = "取消当前账号全部进行中和排队中的下载任务"

        clearHistoryButton.bezelStyle = .inline
        clearHistoryButton.controlSize = .small
        clearHistoryButton.target = self
        clearHistoryButton.action = #selector(handleClearHistory)
        clearHistoryButton.isHidden = true
        clearHistoryButton.isEnabled = false
        clearHistoryButton.toolTip = "只清除当前账号的终结记录，不删除已下载文件"

        let header = NSStackView(views: [modeControl, countLabel, NSView(), cancelAllButton, clearHistoryButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        rowsStack.orientation = .vertical
        rowsStack.alignment = .width
        rowsStack.spacing = 0
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(rowsStack)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.isHidden = true
        scrollView.documentView = documentView

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.maximumNumberOfLines = 2

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let downloadedButton = NSButton(title: "查看已下载", target: self, action: #selector(handleViewDownloaded))
        downloadedButton.bezelStyle = .inline
        downloadedButton.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        downloadedButton.imagePosition = .imageLeading
        downloadedButton.translatesAutoresizingMaskIntoConstraints = false

        [header, scrollView, emptyLabel, separator, downloadedButton].forEach(root.addSubview)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -8),

            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            rowsStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 12),
            rowsStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -12),
            rowsStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 28),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),

            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: downloadedButton.topAnchor, constant: -8),

            downloadedButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            downloadedButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)
        ])
    }

    func startObserving() {
        guard cancellables.isEmpty else { return }
        service.downloadJobStore.pruneExpiredHistory()
        resetAllRows()
        Publishers.CombineLatest4(
            service.downloadJobStore.$jobs,
            service.downloadJobStore.$history,
            service.steamAuth.$steamId,
            service.steamAuth.$expired
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] jobs, history, accountSteamID, sessionExpired in
                guard let self else { return }
                self.latestJobs = jobs
                self.latestHistory = history
                self.latestAccountSteamID = accountSteamID
                self.latestSessionExpired = sessionExpired
                self.renderSelectedMode()
            }
            .store(in: &cancellables)
    }

    func stopObserving() {
        cancellables.removeAll()
        resetAllRows()
    }

    @objc private func handleCancelAll() { cancelAll() }
    @objc private func handleClearHistory() { clearHistory() }
    @objc private func handleViewDownloaded() { viewDownloaded() }

    @objc private func handleModeChanged() {
        renderSelectedMode()
    }

    private func renderSelectedMode() {
        if modeControl.selectedSegment == 1 {
            resetCurrentRows()
            reconcileHistory(history: latestHistory, accountSteamID: latestAccountSteamID)
        } else {
            resetHistoryRows()
            reconcileCurrent(
                jobs: latestJobs,
                accountSteamID: latestAccountSteamID,
                sessionExpired: latestSessionExpired
            )
        }
    }

    private func reconcileCurrent(
        jobs: [SteamDownloadJob],
        accountSteamID: String?,
        sessionExpired: Bool
    ) {
        let desired = SteamWorkshopDownloadTaskProjection.currentJobs(
            from: jobs,
            accountSteamID: accountSteamID
        )
        let desiredByID = Dictionary(uniqueKeysWithValues: desired.map { ($0.id, $0) })

        for jobID in orderedJobIDs where desiredByID[jobID] == nil {
            guard let row = rowByJobID.removeValue(forKey: jobID) else { continue }
            row.unbind()
            rowsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        orderedJobIDs.removeAll { desiredByID[$0] == nil }

        for jobID in orderedJobIDs {
            guard let job = desiredByID[jobID] else { continue }
            rowByJobID[jobID]?.update(job: job, sessionExpired: sessionExpired)
        }

        // Keep existing rows fixed while the pointer is inside the open panel.
        // Newly observed jobs append; the canonical active/waiting/queued order
        // is restored each time the popover is opened.
        for job in desired where rowByJobID[job.id] == nil {
            let row = SteamWorkshopDownloadTaskRowView(
                job: job,
                sessionExpired: sessionExpired,
                service: service,
                cancel: { [weak service] itemID in service?.cancelDownload(itemID: itemID) },
                retry: { [weak service] itemID, title in
                    service?.downloadWorkshopItem(id: itemID, pageTitle: title)
                },
                showDetail: showDetail
            )
            orderedJobIDs.append(job.id)
            rowByJobID[job.id] = row
            rowsStack.addArrangedSubview(row)
        }

        countLabel.stringValue = desired.isEmpty ? "" : "\(desired.count) 项"
        emptyLabel.stringValue = accountSteamID == nil ? "登录 Steam 后可查看当前账号的下载任务" : "当前没有下载任务"
        emptyLabel.isHidden = !desired.isEmpty
        scrollView.isHidden = desired.isEmpty
        cancelAllButton.isEnabled = desired.contains(where: SteamWorkshopDownloadTaskProjection.isCancellable)
        cancelAllButton.isHidden = false
        clearHistoryButton.isHidden = true
    }

    private func reconcileHistory(
        history: [SteamDownloadHistoryEntry],
        accountSteamID: String?
    ) {
        let desired = SteamWorkshopDownloadHistoryProjection.summaries(
            from: history,
            accountSteamID: accountSteamID
        )
        if desired != renderedHistory {
            resetHistoryRows()
            for summary in desired {
                let row = SteamWorkshopDownloadHistoryRowView(summary: summary, show: showHistory)
                historyRows.append(row)
                rowsStack.addArrangedSubview(row)
            }
            renderedHistory = desired
        }

        countLabel.stringValue = desired.isEmpty ? "" : "\(desired.count) 项"
        emptyLabel.stringValue = accountSteamID == nil ? "登录 Steam 后可查看当前账号的下载历史" : "当前没有下载历史"
        emptyLabel.isHidden = !desired.isEmpty
        scrollView.isHidden = desired.isEmpty
        cancelAllButton.isHidden = true
        clearHistoryButton.isHidden = false
        clearHistoryButton.isEnabled = !desired.isEmpty
    }

    private func resetCurrentRows() {
        rowByJobID.values.forEach {
            $0.unbind()
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        rowByJobID.removeAll()
        orderedJobIDs.removeAll()
    }

    private func resetHistoryRows() {
        historyRows.forEach {
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        historyRows.removeAll()
        renderedHistory.removeAll()
    }

    private func resetAllRows() {
        resetCurrentRows()
        resetHistoryRows()
    }
}

@MainActor
private final class SteamWorkshopDownloadHistoryRowView: NSView {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private let summary: SteamWorkshopDownloadHistorySummary
    private let show: (SteamWorkshopDownloadHistorySummary) -> Void

    init(
        summary: SteamWorkshopDownloadHistorySummary,
        show: @escaping (SteamWorkshopDownloadHistorySummary) -> Void
    ) {
        self.summary = summary
        self.show = show
        super.init(frame: .zero)
        configureViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func configureViews() {
        translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        icon.image = NSImage(
            systemSymbolName: iconName,
            accessibilityDescription: outcomeText
        )
        icon.contentTintColor = outcomeColor

        let titleLabel = NSTextField(labelWithString: summary.title)
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.toolTip = summary.title

        let statusLabel = NSTextField(labelWithString: statusText)
        statusLabel.font = .systemFont(ofSize: 10.5)
        statusLabel.textColor = outcomeColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.toolTip = summary.attempts.first?.failureMessage

        let detailButton = NSButton(
            title: summary.latestOutcome == .completed ? "查看" : "详情",
            target: self,
            action: #selector(handleShow)
        )
        detailButton.bezelStyle = .inline
        detailButton.controlSize = .small

        let titleRow = NSStackView(views: [titleLabel, NSView(), detailButton])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 6

        let body = NSStackView(views: [titleRow, statusLabel])
        body.translatesAutoresizingMaskIntoConstraints = false
        body.orientation = .vertical
        body.alignment = .width
        body.spacing = 6

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(body)
        addSubview(separator)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 72),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            body.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            body.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setAccessibilityLabel("\(summary.title)，\(statusText)")
    }

    private var statusText: String {
        let attempts = summary.attempts.count == 1 ? "1 次尝试" : "\(summary.attempts.count) 次尝试"
        return "\(outcomeText) · \(attempts) · \(Self.dateFormatter.string(from: summary.latestTerminalAt))"
    }

    private var outcomeText: String {
        switch summary.latestOutcome {
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    private var iconName: String {
        switch summary.latestOutcome {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    private var outcomeColor: NSColor {
        switch summary.latestOutcome {
        case .completed: return .systemGreen
        case .failed: return .systemRed
        case .cancelled: return .secondaryLabelColor
        }
    }

    @objc private func handleShow() { show(summary) }
}

@MainActor
private final class SteamWorkshopDownloadTaskRowView: NSView {
    private let service: SteamWorkshopService
    private let cancel: (String) -> Void
    private let retry: (String, String) -> Void
    private let showDetail: (SteamDownloadJob) -> Void
    private var job: SteamDownloadJob
    private var progressObserver: UUID?
    private var currentPreviewURL: URL?
    private var previewCancellation: SteamWorkshopPreviewLoadCancellation?
    private var speedSamples: [Double] = []
    private var lastByteSample: (bytes: Int64, date: Date)?
    private var lastProgressSequence = -1
    private var progressAccessibilityBucket: Int?
    private var progressAccessibilityPhase: SteamWorkshopDownloadProgressSnapshot.Phase?
    private var isCancellationRequested = false
    private var sessionExpired: Bool

    private let thumbnailView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressBar = SteamWorkshopGlassBarView()
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private let retryButton = NSButton(title: "重试", target: nil, action: nil)
    private let detailButton = NSButton(title: "详情", target: nil, action: nil)

    init(
        job: SteamDownloadJob,
        sessionExpired: Bool,
        service: SteamWorkshopService,
        cancel: @escaping (String) -> Void,
        retry: @escaping (String, String) -> Void,
        showDetail: @escaping (SteamDownloadJob) -> Void
    ) {
        self.job = job
        self.sessionExpired = sessionExpired
        self.service = service
        self.cancel = cancel
        self.retry = retry
        self.showDetail = showDetail
        super.init(frame: .zero)
        configureViews()
        bindProgress()
        update(job: job, sessionExpired: sessionExpired)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(job: SteamDownloadJob, sessionExpired: Bool) {
        let attemptChanged = self.job.attempt != job.attempt
        self.job = job
        self.sessionExpired = sessionExpired
        if attemptChanged {
            speedSamples.removeAll()
            lastByteSample = nil
            lastProgressSequence = -1
            progressAccessibilityBucket = nil
            progressAccessibilityPhase = nil
            isCancellationRequested = false
        }
        titleLabel.stringValue = job.title
        titleLabel.toolTip = job.title
        progressBar.setAccessibilityLabel("下载进度：\(job.title)")
        let isCancellable = SteamWorkshopDownloadTaskProjection.isCancellable(job)
        cancelButton.isHidden = !isCancellable
        cancelButton.isEnabled = isCancellable && !isCancellationRequested
        retryButton.isHidden = job.state != .failed
        retryButton.isEnabled = job.state == .failed && !sessionExpired
        detailButton.isEnabled = true
        applyJobFallback()
        loadPreviewIfNeeded()
        if let snapshot = service.downloadProgressStore.snapshot(for: job.workshopItemId) {
            apply(snapshot: snapshot)
        } else {
            updateFallbackProgressAccessibility()
        }
    }

    func unbind() {
        if let progressObserver {
            service.downloadProgressStore.removeObserver(progressObserver)
            self.progressObserver = nil
        }
        previewCancellation?.cancel()
        previewCancellation = nil
        progressBar.setProgressAnimationVisible(false)
    }

    private func configureViews() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        layer?.borderWidth = 0

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 7
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.16).cgColor
        thumbnailView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        thumbnailView.contentTintColor = .tertiaryLabelColor
        thumbnailView.setAccessibilityElement(false)

        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.layer?.cornerRadius = 2.5
        progressBar.setProgressAnimationVisible(true)
        progressBar.setAccessibilityElement(true)
        progressBar.setAccessibilityRole(.progressIndicator)

        [cancelButton, retryButton, detailButton].forEach {
            $0.bezelStyle = .inline
            $0.controlSize = .small
        }
        cancelButton.target = self
        cancelButton.action = #selector(handleCancel)
        retryButton.target = self
        retryButton.action = #selector(handleRetry)
        detailButton.target = self
        detailButton.action = #selector(handleDetail)

        let buttons = NSStackView(views: [cancelButton, retryButton, detailButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 5

        let titleRow = NSStackView(views: [titleLabel, NSView(), buttons])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 6

        let body = NSStackView(views: [titleRow, statusLabel, progressBar])
        body.orientation = .vertical
        body.alignment = .width
        body.spacing = 5
        body.translatesAutoresizingMaskIntoConstraints = false

        addSubview(thumbnailView)
        addSubview(body)
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 92),
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 58),
            thumbnailView.heightAnchor.constraint(equalToConstant: 58),
            body.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 10),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            body.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 5),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func bindProgress() {
        progressObserver = service.downloadProgressStore.addObserver(
            for: job.workshopItemId,
            owner: self
        ) { [weak self] snapshot in
            guard let self else { return }
            if let snapshot {
                self.apply(snapshot: snapshot)
            } else {
                self.applyJobFallback()
            }
        }
    }

    private func applyJobFallback() {
        statusLabel.toolTip = nil
        switch job.state {
        case .queued:
            statusLabel.stringValue = "等待下载 · 队列第 \(job.queueOrdinal) 项"
            statusLabel.textColor = .secondaryLabelColor
            progressBar.applyProgress(style: .queued, fraction: nil, indeterminate: false, animated: false)
        case .running:
            statusLabel.stringValue = "正在连接"
            statusLabel.textColor = .secondaryLabelColor
            progressBar.applyProgress(style: .downloading, fraction: nil, indeterminate: true, animated: false)
        case .staged, .committing:
            statusLabel.stringValue = "正在保存"
            statusLabel.textColor = .secondaryLabelColor
            progressBar.applyProgress(style: .downloading, fraction: 1, indeterminate: false, animated: false)
        case .failed:
            statusLabel.stringValue = "下载失败 · 可重试"
            statusLabel.textColor = .systemRed
            progressBar.applyProgress(style: .failed, fraction: nil, indeterminate: false, animated: false)
            statusLabel.toolTip = job.failureMessage
        case .completed:
            statusLabel.stringValue = "已完成"
            statusLabel.textColor = .secondaryLabelColor
            progressBar.applyProgress(style: .ready, fraction: 1, indeterminate: false, animated: false)
        case .cancelled:
            statusLabel.stringValue = "已取消"
            statusLabel.textColor = .secondaryLabelColor
            progressBar.applyProgress(style: .neutral, fraction: nil, indeterminate: false, animated: false)
        }
        if sessionExpired {
            statusLabel.stringValue = "请使用工具栏重新登录"
            statusLabel.textColor = .systemOrange
            progressBar.applyProgress(style: .waiting, fraction: nil, indeterminate: false, animated: false)
            statusLabel.toolTip = "Steam 会话已过期；任务不会自动打开登录面板。"
        }
    }

    private func updateFallbackProgressAccessibility() {
        let phase: SteamWorkshopDownloadProgressSnapshot.Phase?
        let percent: Int?
        if sessionExpired {
            phase = .waiting
            percent = nil
        } else {
            switch job.state {
            case .queued:
                phase = .waiting
                percent = nil
            case .running:
                phase = .connecting
                percent = nil
            case .staged, .committing, .completed:
                phase = .saving
                percent = 100
            case .failed:
                phase = .failed
                percent = nil
            case .cancelled:
                phase = nil
                percent = nil
            }
        }
        updateProgressAccessibility(
            value: statusLabel.stringValue,
            phase: phase,
            percent: percent,
            announce: true
        )
    }

    private func apply(snapshot: SteamWorkshopDownloadProgressSnapshot) {
        guard snapshot.itemID == job.workshopItemId,
              snapshot.jobKey == SteamWorkshopDownloadTaskProjection.jobKey(for: job) else { return }
        guard !isCancellationRequested else { return }
        switch job.state {
        case .running:
            break
        case .staged, .committing:
            guard snapshot.phase == .saving else { return }
        case .failed:
            guard snapshot.phase == .failed else { return }
        case .queued, .completed, .cancelled:
            return
        }
        let fraction = snapshot.fraction
        let style: SteamWorkshopGlassBarView.AccentStyle
        switch snapshot.phase {
        case .waiting: style = .waiting
        case .failed: style = .failed
        default: style = .downloading
        }
        progressBar.applyProgress(
            style: style,
            fraction: fraction,
            indeterminate: fraction == nil && snapshot.phase != .failed && snapshot.phase != .waiting,
            animated: snapshot.sequence > 0
        )

        var text = snapshot.statusText()
        if snapshot.phase == .transferring {
            if let rate = sampleRate(snapshot: snapshot), rate > 0 {
                text += " · \(ByteCountFormatter.string(fromByteCount: Int64(rate), countStyle: .file))/s"
                if let total = snapshot.totalBytes,
                   speedSamples.count >= 3,
                   isRateStable,
                   total > snapshot.verifiedBytes {
                    let remaining = Double(total - snapshot.verifiedBytes) / rate
                    text += " · 约 \(Self.duration(remaining))"
                }
            }
        }
        statusLabel.stringValue = text
        switch snapshot.phase {
        case .waiting:
            statusLabel.textColor = .systemOrange
        case .failed:
            statusLabel.textColor = .systemRed
        default:
            statusLabel.textColor = .secondaryLabelColor
        }
        statusLabel.toolTip = snapshot.failureMessage
        if sessionExpired {
            statusLabel.stringValue = "请使用工具栏重新登录"
            statusLabel.textColor = .systemOrange
            progressBar.applyProgress(
                style: .waiting,
                fraction: fraction,
                indeterminate: false,
                animated: false
            )
            statusLabel.toolTip = "Steam 会话已过期；任务不会自动打开登录面板。"
        }
        updateProgressAccessibility(
            value: statusLabel.stringValue,
            phase: sessionExpired ? .waiting : snapshot.phase,
            percent: snapshot.percent,
            announce: snapshot.sequence > 0
        )
    }

    private func updateProgressAccessibility(
        value: String,
        phase: SteamWorkshopDownloadProgressSnapshot.Phase?,
        percent: Int?,
        announce: Bool
    ) {
        progressBar.setAccessibilityValue(value)
        let bucket = percent.map { $0 / 10 }
        let changed = phase != progressAccessibilityPhase || bucket != progressAccessibilityBucket
        progressAccessibilityPhase = phase
        progressAccessibilityBucket = bucket
        if announce, changed, progressBar.window != nil {
            NSAccessibility.post(element: progressBar, notification: .valueChanged)
        }
    }

    private func sampleRate(snapshot: SteamWorkshopDownloadProgressSnapshot) -> Double? {
        let now = Date()
        defer {
            if snapshot.sequence > lastProgressSequence {
                lastProgressSequence = snapshot.sequence
                lastByteSample = (snapshot.verifiedBytes, now)
            }
        }
        guard snapshot.sequence > lastProgressSequence,
              let previous = lastByteSample,
              snapshot.verifiedBytes > previous.bytes else {
            return speedSamples.last
        }
        let elapsed = now.timeIntervalSince(previous.date)
        guard elapsed >= 0.08 else { return speedSamples.last }
        let rate = Double(snapshot.verifiedBytes - previous.bytes) / elapsed
        guard rate.isFinite, rate > 0 else { return speedSamples.last }
        speedSamples.append(rate)
        if speedSamples.count > 4 { speedSamples.removeFirst() }
        return speedSamples.reduce(0, +) / Double(speedSamples.count)
    }

    private var isRateStable: Bool {
        guard let minRate = speedSamples.min(), let maxRate = speedSamples.max(), minRate > 0 else { return false }
        return maxRate / minRate <= 1.8
    }

    private static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "" }
        if seconds < 60 { return "\(max(1, Int(seconds.rounded()))) 秒" }
        if seconds < 3600 { return "\(max(1, Int((seconds / 60).rounded()))) 分钟" }
        return "\(max(1, Int((seconds / 3600).rounded()))) 小时"
    }

    private func loadPreviewIfNeeded() {
        let url = service.browserItemForDownload(id: job.workshopItemId)?.previewImageURL
            ?? service.downloads.first(where: { $0.id == job.workshopItemId })?.previewURL
        guard currentPreviewURL != url else { return }
        currentPreviewURL = url
        previewCancellation?.cancel()
        previewCancellation = nil
        thumbnailView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        guard let url else { return }

        if url.isFileURL {
            steamWorkshopLoadLocalPreviewImage(from: url) { [weak self] image in
                guard let self, self.currentPreviewURL == url, let image else { return }
                self.thumbnailView.image = image
            }
            return
        }

        let key = steamWorkshopPreviewCacheKey(for: url)
        if let cached = SteamWorkshopPreviewImageCache.shared.cachedOrDiskImage(forKey: key) {
            thumbnailView.image = cached
            return
        }
        let cancellation = SteamWorkshopPreviewLoadCancellation()
        previewCancellation = cancellation
        SteamWorkshopPreviewImageCache.shared.loadImageDataAsync(forKey: key, loader: {
            await SteamWorkshopPreviewRequestCoordinator.shared.loadData(
                from: url,
                priority: .visible,
                cancellation: cancellation
            )
        }, decoder: { data in NSImage(data: data) }) { [weak self] image in
            guard let self, self.currentPreviewURL == url, !cancellation.cancelled, let image else { return }
            self.thumbnailView.image = image
            self.previewCancellation = nil
        }
    }

    @objc private func handleCancel() {
        guard SteamWorkshopDownloadTaskProjection.isCancellable(job) else { return }
        let snapshot = service.downloadProgressStore.snapshot(for: job.workshopItemId)
        isCancellationRequested = true
        cancelButton.isEnabled = false
        statusLabel.stringValue = job.state == .queued ? "正在移出队列…" : "正在取消…"
        statusLabel.textColor = .secondaryLabelColor
        progressBar.applyProgress(
            style: .waiting,
            fraction: snapshot?.fraction,
            indeterminate: false,
            animated: false
        )
        updateProgressAccessibility(
            value: statusLabel.stringValue,
            phase: .waiting,
            percent: snapshot?.percent,
            announce: true
        )
        cancel(job.workshopItemId)
        if job.state == .queued,
           service.downloadJobStore.activeJob(forWorkshopItemId: job.workshopItemId)?.state == .queued {
            isCancellationRequested = false
            cancelButton.isEnabled = true
            statusLabel.stringValue = "无法保存取消操作，请重试"
            statusLabel.textColor = .systemRed
            progressBar.applyProgress(style: .queued, fraction: nil, indeterminate: false, animated: false)
            updateProgressAccessibility(
                value: statusLabel.stringValue,
                phase: .failed,
                percent: nil,
                announce: true
            )
        }
    }
    @objc private func handleRetry() {
        guard !sessionExpired, job.state == .failed else { return }
        retryButton.isEnabled = false
        statusLabel.stringValue = "正在重试…"
        statusLabel.textColor = .secondaryLabelColor
        updateProgressAccessibility(
            value: statusLabel.stringValue,
            phase: .waiting,
            percent: service.downloadProgressStore.snapshot(for: job.workshopItemId)?.percent,
            announce: true
        )
        retry(job.workshopItemId, job.title)
        if let failed = service.downloadJobStore.failedJob(
            forWorkshopItemId: job.workshopItemId,
            accountSteamId: job.accountSteamId
        ), failed.attempt == job.attempt {
            retryButton.isEnabled = true
            statusLabel.stringValue = "无法保存重试任务，请重试"
            statusLabel.textColor = .systemRed
            updateProgressAccessibility(
                value: statusLabel.stringValue,
                phase: .failed,
                percent: nil,
                announce: true
            )
        }
    }
    @objc private func handleDetail() { showDetail(job) }
}
