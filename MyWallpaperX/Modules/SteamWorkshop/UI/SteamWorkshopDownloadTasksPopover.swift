import AppKit
import Combine

@MainActor
final class SteamWorkshopDownloadTasksPopoverController: NSObject, NSPopoverDelegate {
    static let panelSize = NSSize(width: 400, height: 460)

    private let popover = NSPopover()
    private let contentController: SteamWorkshopDownloadTasksContentController

    init(service: SteamWorkshopService) {
        self.contentController = SteamWorkshopDownloadTasksContentController(service: service)
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = contentController
        // 视图先加载（preferredContentSize 就绪）再定尺寸，避免 popover 被
        // 压缩成最小尺寸。
        contentController.loadViewIfNeeded()
        popover.contentSize = contentController.preferredContentSize
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
}

/// 单一队列面板：进行中任务与历史记录合并展示。
/// 「全部清除」= 停止全部下载并清空本面板列表，不删除已下载文件。
@MainActor
final class SteamWorkshopDownloadTasksContentController: NSViewController {
    private let service: SteamWorkshopService
    private var cancellables = Set<AnyCancellable>()
    private var latestJobs: [SteamDownloadJob] = []
    private var latestHistory: [SteamDownloadHistoryEntry] = []
    private var latestAccountSteamID: String?
    private var rowsByJobKey: [String: SteamWorkshopDownloadRowView] = [:]

    private let countLabel = NSTextField(labelWithString: "")
    private let clearAllButton = NSButton(title: "全部清除", target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private let rowsStack = NSStackView()

    init(service: SteamWorkshopService) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = SteamWorkshopDownloadTasksPopoverController.panelSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let size = SteamWorkshopDownloadTasksPopoverController.panelSize
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        view = root
        preferredContentSize = size
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: size.width),
            root.heightAnchor.constraint(equalToConstant: size.height)
        ])
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        clearAllButton.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor

        clearAllButton.bezelStyle = .inline
        clearAllButton.controlSize = .small
        clearAllButton.target = self
        clearAllButton.action = #selector(handleClearAll)
        clearAllButton.isEnabled = false
        clearAllButton.toolTip = "停止全部下载并清空本面板列表，不删除已下载文件"

        emptyLabel.stringValue = "暂无下载任务"
        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 0
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(rowsStack)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView

        root.addSubview(countLabel)
        root.addSubview(clearAllButton)
        root.addSubview(scrollView)
        root.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            countLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            countLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),

            clearAllButton.centerYAnchor.constraint(equalTo: countLabel.centerYAnchor),
            clearAllButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            rowsStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
    }

    func startObserving() {
        guard cancellables.isEmpty else { return }
        service.downloadJobStore.pruneExpiredHistory()
        Publishers.CombineLatest4(
            service.downloadJobStore.$jobs,
            service.downloadJobStore.$history,
            service.steamAuth.$steamId,
            service.steamAuth.$expired
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] jobs, history, accountSteamID, _ in
                guard let self else { return }
                self.latestJobs = jobs
                self.latestHistory = history
                self.latestAccountSteamID = accountSteamID
                self.reconcile()
            }
            .store(in: &cancellables)
    }

    func stopObserving() {
        cancellables.removeAll()
        rowsByJobKey.values.forEach { $0.unbind() }
        rowsByJobKey.removeAll()
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    /// 队列 = 当前任务（活动→失败→排队）+ 历史记录，按此顺序合并展示。
    private func reconcile() {
        let jobs = SteamWorkshopDownloadTaskProjection.currentJobs(
            from: latestJobs,
            accountSteamID: latestAccountSteamID
        )
        // 失败任务同时存在于当前队列与历史；队列行优先，避免同条目双行。
        let currentJobIDs = Set(jobs.map(\.id))
        let summaries = SteamWorkshopDownloadHistoryProjection.summaries(
            from: latestHistory,
            accountSteamID: latestAccountSteamID
        ).filter { !currentJobIDs.contains($0.jobID) }

        for (key, row) in rowsByJobKey where !jobs.contains(where: { rowKey($0) == key })
            && !summaries.contains(where: { rowKey($0) == key }) {
            row.unbind()
            rowsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
            rowsByJobKey.removeValue(forKey: key)
        }
        for job in jobs {
            row(rowKey(job)) { $0.configure(job: job) }
        }
        for summary in summaries {
            row(rowKey(summary)) { $0.configure(summary: summary) }
        }

        let orderedKeys = jobs.map(rowKey) + summaries.map(rowKey)
        for (index, key) in orderedKeys.enumerated() {
            if let row = rowsByJobKey[key], rowsStack.arrangedSubviews.count > index,
               rowsStack.arrangedSubviews[index] !== row {
                rowsStack.removeArrangedSubview(row)
                rowsStack.insertArrangedSubview(row, at: index)
            }
        }

        countLabel.stringValue = orderedKeys.isEmpty ? "" : "\(orderedKeys.count) 项"
        clearAllButton.isEnabled = !orderedKeys.isEmpty
        emptyLabel.isHidden = !orderedKeys.isEmpty
        emptyLabel.stringValue = latestAccountSteamID == nil ? "登录 Steam 后可查看当前账号的下载任务" : "暂无下载任务"
    }

    private func rowKey(_ job: SteamDownloadJob) -> String { job.id }
    private func rowKey(_ summary: SteamWorkshopDownloadHistorySummary) -> String { "history-\(summary.id)" }

    /// 取已存在或新建一行；新建时挂到队列尾部并钉满面板宽度。
    private func row(_ key: String, configure: (SteamWorkshopDownloadRowView) -> Void) -> SteamWorkshopDownloadRowView {
        if let existing = rowsByJobKey[key] {
            configure(existing)
            return existing
        }
        let row = SteamWorkshopDownloadRowView(service: service) { [weak self] in
            self?.reconcile()
        }
        rowsByJobKey[key] = row
        rowsStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        configure(row)
        return row
    }

    @objc private func handleClearAll() {
        guard let account = latestAccountSteamID, account == service.steamAuth.steamId else { return }
        for job in SteamWorkshopDownloadTaskProjection.currentJobs(
            from: service.downloadJobStore.jobs, accountSteamID: account
        ) {
            if job.state == .failed { service.discardFailedDownload(jobID: job.id) }
            else if SteamWorkshopDownloadTaskProjection.isCancellable(job) {
                service.cancelDownloadImmediately(itemID: job.workshopItemId, showFeedback: false)
            }
        }
        service.downloadJobStore.clearHistory(forAccount: account)
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 统一队列行：左封面，中间标题 + 进度条 + 速度/已下载/总大小，右侧 X。
@MainActor
final class SteamWorkshopDownloadRowView: NSView {
    private let service: SteamWorkshopService
    private let onCleared: () -> Void

    private let thumbnailView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressBar = SteamWorkshopGlassBarView()
    private let clearButton = NSButton(title: "", target: nil, action: nil)

    private var job: SteamDownloadJob?
    private var clearHandler: (() -> Void)?
    private var progressObserver: UUID?
    private var currentPreviewURL: URL?
    private var previewCancellation: SteamWorkshopPreviewLoadCancellation?
    private var lastByteSample: (bytes: Int64, date: Date)?
    private var lastProgressSequence = -1

    init(service: SteamWorkshopService, onCleared: @escaping () -> Void) {
        self.service = service
        self.onCleared = onCleared
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 6
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.16).cgColor
        thumbnailView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        thumbnailView.contentTintColor = .tertiaryLabelColor
        thumbnailView.setAccessibilityElement(false)

        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.layer?.cornerRadius = 2
        progressBar.setAccessibilityElement(true)
        progressBar.setAccessibilityRole(.progressIndicator)
        progressBar.setProgressAnimationVisible(true)

        clearButton.isBordered = false
        clearButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "清除")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.setAccessibilityLabel("清除")

        addSubview(thumbnailView)
        addSubview(titleLabel)
        addSubview(statusLabel)
        addSubview(progressBar)
        addSubview(clearButton)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 64),
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 44),
            thumbnailView.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: clearButton.leadingAnchor, constant: -8),

            progressBar.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressBar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            progressBar.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            progressBar.heightAnchor.constraint(equalToConstant: 4),

            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 5),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: clearButton.leadingAnchor, constant: -8),

            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 22),
            clearButton.heightAnchor.constraint(equalToConstant: 22)
        ])
        clearButton.target = self
        clearButton.action = #selector(handleClear)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(job: SteamDownloadJob) {
        unbind()
        self.job = job
        titleLabel.stringValue = job.title
        progressBar.setAccessibilityLabel("下载进度：\(job.title)")
        clearButton.setAccessibilityLabel("清除：\(job.title)")
        applyJobFallback()
        bindProgress(job: job)
        loadPreviewIfNeeded(itemID: job.workshopItemId)
        let jobID = job.id
        let itemID = job.workshopItemId
        if SteamWorkshopDownloadTaskProjection.isCancellable(job) {
            clearHandler = { [weak self] in
                guard let self, self.service.steamAuth.steamId == job.accountSteamId,
                      let current = self.service.downloadJobStore.jobs.first(where: { $0.id == jobID }),
                      current.attempt == job.attempt,
                      SteamWorkshopDownloadTaskProjection.isCancellable(current) else { return }
                self.service.cancelDownloadImmediately(itemID: itemID, showFeedback: false)
                self.onCleared()
            }
        } else if job.state == .failed {
            clearHandler = { [weak self] in
                self?.service.discardFailedDownload(jobID: jobID)
                self?.onCleared()
            }
        }
        clearButton.isEnabled = clearHandler != nil
    }

    func configure(summary: SteamWorkshopDownloadHistorySummary) {
        unbind()
        job = nil
        titleLabel.stringValue = summary.title
        let outcome: (String, NSColor, SteamWorkshopGlassBarView.AccentStyle, Double?) = {
            switch summary.latestOutcome {
            case .completed: return ("已完成", .secondaryLabelColor, .ready, 1)
            case .failed: return ("失败", .systemRed, .failed, nil)
            case .cancelled: return ("已取消", .secondaryLabelColor, .neutral, nil)
            }
        }()
        statusLabel.stringValue = "\(outcome.0) · \(Self.dateFormatter.string(from: summary.latestTerminalAt))"
        statusLabel.textColor = outcome.1
        progressBar.applyProgress(style: outcome.2, fraction: outcome.3, indeterminate: false, animated: false)
        progressBar.setAccessibilityLabel("下载进度：\(summary.title)")
        clearButton.isEnabled = true
        clearButton.setAccessibilityLabel("清除：\(summary.title)")
        loadPreviewIfNeeded(itemID: summary.workshopItemID)
        let account = service.steamAuth.steamId
        clearHandler = { [weak self] in
            guard let self, self.service.steamAuth.steamId == account else { return }
            self.service.downloadJobStore.removeHistory(forJobID: summary.jobID, accountSteamId: account)
            self.onCleared()
        }
    }

    func unbind() {
        if let progressObserver {
            service.downloadProgressStore.removeObserver(progressObserver)
            self.progressObserver = nil
        }
        previewCancellation?.cancel()
        previewCancellation = nil
        currentPreviewURL = nil
        lastByteSample = nil
        lastProgressSequence = -1
        clearHandler = nil
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - 进行中任务的进度绑定

    private func bindProgress(job: SteamDownloadJob) {
        progressObserver = service.downloadProgressStore.addObserver(
            for: job.workshopItemId,
            owner: self
        ) { [weak self] snapshot in
            guard let self else { return }
            if let snapshot {
                self.apply(job: job, snapshot: snapshot)
            } else {
                self.applyJobFallback()
            }
        }
        if let snapshot = service.downloadProgressStore.snapshot(for: job.workshopItemId) {
            apply(job: job, snapshot: snapshot)
        }
    }

    private func applyJobFallback() {
        guard let job else { return }
        statusLabel.toolTip = nil
        switch job.state {
        case .queued:
            status("等待下载 · 队列第 \(job.queueOrdinal) 项", color: .secondaryLabelColor, style: .queued, fraction: nil, indeterminate: false)
        case .running:
            status("正在连接", color: .secondaryLabelColor, style: .downloading, fraction: nil, indeterminate: true)
        case .staged, .committing:
            status("正在保存", color: .secondaryLabelColor, style: .downloading, fraction: 1, indeterminate: false)
        case .failed:
            status(job.failureMessage ?? "下载失败", color: .systemRed, style: .failed, fraction: nil, indeterminate: false)
            statusLabel.toolTip = job.failureMessage
        case .completed:
            status("已完成", color: .secondaryLabelColor, style: .ready, fraction: 1, indeterminate: false)
        case .cancelled:
            status("已取消", color: .secondaryLabelColor, style: .neutral, fraction: nil, indeterminate: false)
        }
    }

    private func apply(job: SteamDownloadJob, snapshot: SteamWorkshopDownloadProgressSnapshot) {
        guard snapshot.itemID == job.workshopItemId,
              snapshot.jobKey == SteamWorkshopDownloadTaskProjection.jobKey(for: job) else { return }
        let style: SteamWorkshopGlassBarView.AccentStyle = {
            switch snapshot.phase {
            case .waiting: return .waiting
            case .failed: return .failed
            default: return .downloading
            }
        }()
        progressBar.applyProgress(
            style: style,
            fraction: snapshot.fraction,
            indeterminate: snapshot.fraction == nil && snapshot.phase != .failed && snapshot.phase != .waiting,
            animated: snapshot.sequence > 0
        )
        var parts: [String] = [snapshot.statusText(compact: true)]
        if snapshot.phase == .transferring {
            parts.append(sizeText(snapshot: snapshot))
            if let rate = sampleRate(snapshot: snapshot), rate > 0 {
                parts.insert(ByteCountFormatter.string(fromByteCount: Int64(rate), countStyle: .file) + "/s", at: 1)
            }
        }
        statusLabel.stringValue = parts.joined(separator: " · ")
        statusLabel.textColor = {
            switch snapshot.phase {
            case .waiting: return .systemOrange
            case .failed: return .systemRed
            default: return .secondaryLabelColor
            }
        }()
        statusLabel.toolTip = snapshot.failureMessage
        progressBar.setAccessibilityValue(statusLabel.stringValue)
    }

    private func status(
        _ text: String, color: NSColor,
        style: SteamWorkshopGlassBarView.AccentStyle,
        fraction: Double?, indeterminate: Bool
    ) {
        statusLabel.stringValue = text
        statusLabel.textColor = color
        progressBar.applyProgress(style: style, fraction: fraction, indeterminate: indeterminate, animated: false)
        progressBar.setAccessibilityValue(text)
    }

    /// 「已下载 / 总大小」；总大小未知时只显示已下载。
    private func sizeText(snapshot: SteamWorkshopDownloadProgressSnapshot) -> String {
        let downloaded = ByteCountFormatter.string(fromByteCount: snapshot.verifiedBytes, countStyle: .file)
        guard let total = snapshot.totalBytes else { return downloaded }
        return "\(downloaded) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
    }

    /// 两次快照的字节差 ÷ 时间差（无上一样本时不显示速度）。
    private func sampleRate(snapshot: SteamWorkshopDownloadProgressSnapshot) -> Double? {
        defer {
            if snapshot.sequence > lastProgressSequence {
                lastProgressSequence = snapshot.sequence
                lastByteSample = (snapshot.verifiedBytes, Date())
            }
        }
        guard snapshot.sequence > lastProgressSequence, let last = lastByteSample else { return nil }
        let elapsed = Date().timeIntervalSince(last.date)
        guard elapsed >= 0.08, snapshot.verifiedBytes > last.bytes else { return nil }
        let rate = Double(snapshot.verifiedBytes - last.bytes) / elapsed
        return rate.isFinite && rate > 0 ? rate : nil
    }

    // MARK: - 封面与清除

    private func loadPreviewIfNeeded(itemID: String) {
        let url = service.browserItemForDownload(id: itemID)?.previewImageURL
            ?? service.downloads.first(where: { $0.id == itemID })?.previewURL
        guard currentPreviewURL != url || (thumbnailView.image == nil && url != nil) else { return }
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

    @objc private func handleClear() {
        clearHandler?()
    }
}
