import AppKit
import Combine

final class AppKitSteamWorkshopItemDetailView: NSView {
    private enum Metrics {
        static let contentSpacing: CGFloat = 16
        static let contentTopInset: CGFloat = 8
        static let footerHeight: CGFloat = SteamWorkshopDetailFooterView.height
    }

    private let service = SteamWorkshopService.shared
    private let initialItem: SteamWorkshopBrowserItem
    private var currentItem: SteamWorkshopBrowserItem
    private var cancellables = Set<AnyCancellable>()
    private var subscriptionHint: String?
    private var diagnosticsPanelToken: UUID?
    private var diagnosticsPanelStack: NSStackView?
    private var webDiagnosticsExpanded = false
    private var downloadProgressObserverID: UUID?
    private var downloadProgressSnapshot: SteamWorkshopDownloadProgressSnapshot?
    private var downloadProgressLabel: NSTextField?
    private var downloadProgressIndicator: NSProgressIndicator?
    private var downloadProgressAccessibilityBucket: Int?
    private var didBuildInitialContent = false
    private lazy var sceneInspectionController = SteamWorkshopSceneInspectionController { [weak self] in
        self?.rebuild(preservingScrollPosition: true)
        self?.refreshDiagnosticsPanel()
    }

    private let rootStack = NSStackView()
    private let scrollView = InspectorFadingScrollView(fadeRatio: 0)
    private let documentContainer = SteamWorkshopDetailDocumentView()
    private let contentStack = NSStackView()
    private let footerView = SteamWorkshopDetailFooterView()
    private let previewView = SteamWorkshopPreviewImageContainerView()
    private var isRestoringScrollPosition = false

    init(item: SteamWorkshopBrowserItem) {
        self.initialItem = item
        self.currentItem = item
        super.init(frame: .zero)
        setup()
        observeService()
        bindDownloadProgress(to: item.id)
        rebuild()
        didBuildInitialContent = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(item: SteamWorkshopBrowserItem) {
        let isSameItem = item.id == currentItem.id
        if !isSameItem {
            if diagnosticsPanelToken == SteamWorkshopPropertyPanelController.shared.presentationID {
                SteamWorkshopPropertyPanelController.shared.close()
            }
            diagnosticsPanelStack = nil
            diagnosticsPanelToken = nil
            subscriptionHint = nil
            webDiagnosticsExpanded = false
            sceneInspectionController.reset()
            bindDownloadProgress(to: item.id)
        }
        currentItem = resolvedCurrentItem(fallback: item)
        rebuild(preservingScrollPosition: isSameItem)
    }

    private func observeService() {
        WallpaperManager.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .sceneWallpaperLaunchStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        service.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.currentItem = self.resolvedCurrentItem(fallback: self.currentItem)
                self.rebuild()
            }
            .store(in: &cancellables)

        service.steamAuth.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.service.steamSubscriptions.synchronizeAccount()
                if self.service.steamAuth.isOnline { self.subscriptionHint = nil }
                self.rebuild()
            }
            .store(in: &cancellables)
        service.steamSubscriptions.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: WebRuntimeDiagnosticsStore.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      self.webDiagnosticsExpanded,
                      let webDownloadRecord = self.webDownloadRecord else {
                    return
                }
                if let changedRecordID = notification.object as? String,
                   changedRecordID != webDownloadRecord.id {
                    return
                }
                self.refreshDiagnosticsPanel()
            }
            .store(in: &cancellables)

    }

    private func bindDownloadProgress(to itemID: String) {
        if let downloadProgressObserverID {
            service.downloadProgressStore.removeObserver(downloadProgressObserverID)
        }
        downloadProgressObserverID = nil
        downloadProgressLabel = nil
        downloadProgressIndicator = nil
        downloadProgressAccessibilityBucket = nil
        downloadProgressSnapshot = service.downloadProgressStore.snapshot(for: itemID)
        downloadProgressObserverID = service.downloadProgressStore.addObserver(for: itemID, owner: self) { [weak self] snapshot in
            guard let self, self.currentItem.id == itemID else { return }
            let previous = self.downloadProgressSnapshot
            self.downloadProgressSnapshot = snapshot
            let changesStructure = (previous == nil) != (snapshot == nil)
            let changesPhase = previous?.phase != snapshot?.phase
            if self.didBuildInitialContent, changesStructure || changesPhase {
                self.rebuild(preservingScrollPosition: true)
            } else {
                self.updateDownloadProgressControls(announcingFrom: previous)
            }
        }
    }

    private func resolvedCurrentItem(fallback: SteamWorkshopBrowserItem) -> SteamWorkshopBrowserItem {
        if let selected = service.selectedDownloadDetailItem, selected.id == fallback.id {
            return selected
        }
        if let selected = service.selectedBrowserItem, selected.id == fallback.id {
            return selected
        }
        if let selected = service.selectedDownloadDetailItem, selected.id == initialItem.id {
            return selected
        }
        if let selected = service.selectedBrowserItem, selected.id == initialItem.id {
            return selected
        }
        return fallback
    }

    private var downloadRecord: SteamWorkshopDownloadRecord? {
        service.playableDownloadRecord(for: currentItem.id)
    }

    private var latestDownloadRecord: SteamWorkshopDownloadRecord? {
        service.latestDownloadRecord(for: currentItem.id)
    }

    private var latestDownloadFailure: String? {
        latestDownloadRecord?.failureMessage
    }

    private var webDownloadRecord: SteamWorkshopDownloadRecord? {
        guard let latestDownloadRecord, latestDownloadRecord.contentType == .web else { return nil }
        return latestDownloadRecord
    }

    private var sceneDownloadRecord: SteamWorkshopDownloadRecord? {
        guard let latestDownloadRecord, latestDownloadRecord.contentType == .scene else { return nil }
        return latestDownloadRecord
    }

    private var webProjectDescriptor: ResolvedWebProjectDescriptor? {
        guard let webDownloadRecord else { return nil }
        return service.resolvedWebProjectDescriptor(for: webDownloadRecord)
    }

    private var isRefreshingDetail: Bool {
        if service.selectedDownloadInspectorItem?.id == currentItem.id {
            return service.isRefreshingSelectedDownloadDetailItem
        }
        return service.isRefreshingSelectedBrowserItem && service.selectedBrowserItem?.id == currentItem.id
    }

    private var currentDetailError: String? {
        if service.selectedDownloadInspectorItem?.id == currentItem.id {
            return service.selectedDownloadDetailError
        }
        guard service.selectedBrowserItem?.id == currentItem.id else { return nil }
        return service.selectedBrowserItemError
    }

    private var detailDescriptionLine: String {
        let summary = currentItem.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = currentItem.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (!description.isEmpty && description != summary) ? description : summary
        return value.isEmpty ? "暂无更多描述" : value
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = Metrics.contentSpacing
        contentStack.edgeInsets = NSEdgeInsets(top: Metrics.contentTopInset, left: 0, bottom: 16, right: 0)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        documentContainer.translatesAutoresizingMaskIntoConstraints = false
        documentContainer.addSubview(contentStack)
        scrollView.documentView = documentContainer

        footerView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rootStack)
        rootStack.addArrangedSubview(scrollView)
        rootStack.addArrangedSubview(footerView)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            documentContainer.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentContainer.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            contentStack.leadingAnchor.constraint(equalTo: documentContainer.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: documentContainer.topAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: documentContainer.bottomAnchor),
            footerView.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            footerView.heightAnchor.constraint(equalToConstant: Metrics.footerHeight)
        ])
    }

    private func rebuild(preservingScrollPosition: Bool = true) {
        let preservedOrigin = preservingScrollPosition ? scrollView.contentView.bounds.origin : nil
        currentItem = resolvedCurrentItem(fallback: currentItem)
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        footerView.subviews.forEach { $0.removeFromSuperview() }
        downloadProgressLabel = nil
        downloadProgressIndicator = nil

        buildPreviewSection()
        contentStack.addArrangedSubview(divider())
        buildContentSection()
        buildNoticeSection()
        pinContentSectionsToFullWidth()
        buildFooterActions()
        restoreScrollPositionIfNeeded(preservedOrigin ?? .zero)
    }

    private func restoreScrollPositionIfNeeded(_ origin: NSPoint) {
        guard !isRestoringScrollPosition else { return }
        isRestoringScrollPosition = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let documentHeight = self.scrollView.documentView?.bounds.height ?? 0
            let clipHeight = self.scrollView.contentView.bounds.height
            let maxY = max(0, documentHeight - clipHeight)
            let clampedOrigin = NSPoint(x: origin.x, y: min(max(origin.y, 0), maxY))
            self.scrollView.contentView.scroll(to: clampedOrigin)
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            self.isRestoringScrollPosition = false
        }
    }

    private func pinContentSectionsToFullWidth() {
        contentStack.arrangedSubviews.forEach { section in
            section.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
            constrainColumnContent(in: section)
        }
    }

    /// Give wrapping text and section rows a real available width. Intrinsic
    /// widths from long titles, author names or server messages must not widen
    /// the scroll document or push neighboring controls outside the card.
    private func constrainColumnContent(in view: NSView) {
        if let stack = view as? NSStackView, stack.orientation == .vertical {
            for child in stack.arrangedSubviews where child is NSTextField || child is NSStackView || child is NSBox {
                child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
        view.subviews.forEach { constrainColumnContent(in: $0) }
    }

    private func buildPreviewSection() {
        let stack = verticalStack(spacing: 8)

        previewView.configure(
            itemID: currentItem.id,
            previewImageURL: currentItem.previewImageURL,
            fallbackVideoURL: latestDownloadRecord?.videoURL,
            refreshToken: service.previewReloadToken
        )
        previewView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            previewView.heightAnchor.constraint(equalToConstant: 156)
        ])

        let title = label(
            currentItem.title,
            font: .systemFont(ofSize: 19, weight: .semibold),
            color: .labelColor,
            lines: 2
        )
        title.alignment = .center
        stack.setCustomSpacing(14, after: previewView)
        stack.addArrangedSubview(title)
        stack.setCustomSpacing(14, after: title)
        let authorRow = NSStackView(views: [authorButton(), subscriptionButton()])
        authorRow.orientation = .horizontal
        authorRow.distribution = .fillEqually
        authorRow.spacing = 8
        authorRow.translatesAutoresizingMaskIntoConstraints = false
        authorRow.heightAnchor.constraint(equalToConstant: 36).isActive = true
        stack.addArrangedSubview(authorRow)
        if let subscriptionHint {
            let hint = label(subscriptionHint, font: .systemFont(ofSize: 12), color: .secondaryLabelColor, lines: 0)
            hint.alignment = .center
            stack.addArrangedSubview(hint)
        }

        contentStack.addArrangedSubview(stack)
    }

    private func makeDownloadProgressView() -> NSView? {
        let queued = service.isQueuedForDownload(itemID: currentItem.id)
        guard queued || service.isDownloading(itemID: currentItem.id) || downloadProgressSnapshot?.phase == .saving else { return nil }

        let stack = verticalStack(spacing: 4)
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10
        let status = label("", font: .systemFont(ofSize: 12, weight: .medium), color: .secondaryLabelColor, lines: 1)
        header.addArrangedSubview(status)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        header.addArrangedSubview(spacer())
        let cancel = footerIconButton(symbolName: "xmark", help: "取消下载", action: #selector(cancelDownload))
        cancel.isEnabled = downloadProgressSnapshot?.phase != .saving
        cancel.widthAnchor.constraint(equalToConstant: 28).isActive = true
        cancel.heightAnchor.constraint(equalToConstant: 28).isActive = true
        header.addArrangedSubview(cancel)
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let indicator = NSProgressIndicator()
        indicator.style = .bar
        indicator.controlSize = .small
        indicator.minValue = 0
        indicator.maxValue = 1
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.setAccessibilityElement(true)
        indicator.setAccessibilityRole(.progressIndicator)
        indicator.setAccessibilityLabel("下载进度")
        stack.addArrangedSubview(indicator)
        indicator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        downloadProgressLabel = status
        downloadProgressIndicator = indicator
        updateDownloadProgressControls(announcingFrom: nil)
        return stack
    }

    private func updateDownloadProgressControls(
        announcingFrom previous: SteamWorkshopDownloadProgressSnapshot?
    ) {
        guard let label = downloadProgressLabel,
              let indicator = downloadProgressIndicator else { return }
        if let snapshot = downloadProgressSnapshot {
            label.stringValue = snapshot.statusText()
            let indeterminate = snapshot.fraction == nil
                && snapshot.phase != .waiting
                && snapshot.phase != .failed
                && snapshot.phase != .saving
            indicator.isIndeterminate = indeterminate
            if indeterminate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                indicator.startAnimation(nil)
            } else {
                indicator.stopAnimation(nil)
                indicator.doubleValue = snapshot.fraction ?? 0.04
            }
            label.textColor = SteamWorkshopDownloadProgressPalette.color(
                for: progressPaletteTone(for: snapshot.phase),
                darkMode: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            )
            indicator.setAccessibilityValue(snapshot.statusText())
            let bucket = snapshot.percent.map { $0 / 10 }
            if previous != nil,
               bucket != downloadProgressAccessibilityBucket,
               window != nil {
                NSAccessibility.post(element: indicator, notification: .valueChanged)
            }
            downloadProgressAccessibilityBucket = bucket
        } else {
            label.stringValue = "等待下载"
            indicator.isIndeterminate = false
            indicator.stopAnimation(nil)
            indicator.doubleValue = 0.04
            label.textColor = SteamWorkshopDownloadProgressPalette.color(
                for: .queued,
                darkMode: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            )
            indicator.setAccessibilityValue("等待下载")
            downloadProgressAccessibilityBucket = nil
        }
    }

    private func progressPaletteTone(
        for phase: SteamWorkshopDownloadProgressSnapshot.Phase
    ) -> SteamWorkshopDownloadProgressPalette.Tone {
        switch phase {
        case .connecting, .preparing, .transferring, .validating, .saving:
            return .transfer
        case .waiting:
            return .waiting
        case .failed:
            return .failure
        }
    }

    private func buildContentSection() {
        let stack = verticalStack(spacing: 12)
        let metadataTags = Set([currentItem.workshopTypeText, currentItem.ageRatingText, currentItem.resolutionText].compactMap { $0?.lowercased() })
        let uniqueTags = currentItem.tags.filter { !metadataTags.contains($0.lowercased()) }
        if !uniqueTags.isEmpty {
            stack.addArrangedSubview(SteamWorkshopTagStripView(tags: uniqueTags))
            stack.addArrangedSubview(divider())
        }
        stack.addArrangedSubview(sectionTitle("作品数据"))
        var facts: [(String, String)] = []
        for (name, value) in [
            ("类型", currentItem.workshopTypeText), ("分辨率", currentItem.resolutionText),
            ("文件大小", currentItem.fileSizeText), ("发布时间", currentItem.postedText),
            ("更新时间", currentItem.updatedText), ("分类", currentItem.categoryText),
            ("浏览", currentItem.scoreText?.replacingOccurrences(of: "浏览 ", with: "")),
            ("订阅", currentItem.subscriptionsText), ("收藏", currentItem.favoritesText),
            ("累计订阅", currentItem.lifetimeSubscriptionsText), ("累计收藏", currentItem.lifetimeFavoritesText),
            ("可见性", currentItem.visibilityText), ("年龄分级", currentItem.ageRatingText),
            ("审核状态", currentItem.moderationText)
        ] {
            if let value, !value.isEmpty { facts.append((name, value)) }
        }
        if !currentItem.dependencyIDs.isEmpty { facts.append(("依赖作品", currentItem.dependencyIDs.joined(separator: "、"))) }
        facts.append(("作品 ID", currentItem.id))
        stack.addArrangedSubview(factsGrid(facts))
        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(sectionTitle("作品描述"))
        stack.addArrangedSubview(label(detailDescriptionLine, font: .systemFont(ofSize: 13), color: .labelColor, lines: 0))
        contentStack.addArrangedSubview(stack)
    }

    private func buildNoticeSection() {
        let stack = verticalStack(spacing: 8)

        if let currentDetailError {
            stack.addArrangedSubview(errorNotice(message: currentDetailError) { [weak self] in
                guard let self else { return }
                self.service.retryInspectorDetailRefresh(for: self.currentItem.id)
            })
        }

        if let latestDownloadFailure,
           !service.isDownloading(itemID: currentItem.id),
           downloadRecord == nil {
            stack.addArrangedSubview(errorNotice(message: "上次下载失败：\(latestDownloadFailure)") { [weak self] in
                guard let self else { return }
                self.service.requestDownloadForBrowserItem(self.currentItem)
            })
        }

        if isRefreshingDetail {
            stack.addArrangedSubview(notice(icon: "arrow.triangle.2.circlepath", text: "正在补全该项目的详情信息…"))
        }

        if let record = latestDownloadRecord,
           case let .missing(itemID) = record.dependencyStatus {
            stack.addArrangedSubview(notice(
                icon: "shippingbox",
                text: record.isDependencyBackedWeb
                    ? "这是依赖型 WEB 预设壳，当前缺少基础依赖宿主 \(itemID)，因此暂时无法播放。"
                    : "当前 WEB 项目声明依赖包 \(itemID)，本地尚未满足该依赖。"
            ))
        }

        if currentItem.hasAdultContent {
            stack.addArrangedSubview(notice(icon: "exclamationmark.triangle.fill", text: "此项目被 Steam 标记为成人内容"))
        }

        guard !stack.arrangedSubviews.isEmpty else { return }
        contentStack.addArrangedSubview(stack)
    }

    /// UI projects the shared account-scoped state; only known state can be toggled.
    private func authorButton() -> NSView {
        let hasName = SteamWorkshopDetailRefreshSupport.hasAuthorName(currentItem)
        let author = footerButton(title: hasName ? currentItem.author : (isRefreshingDetail ? "正在获取作者…" : "作者名称暂不可用"), symbolName: "person.crop.circle", kind: .secondary, target: self, action: #selector(openAuthorWorkshop))
        author.toolTip = hasName ? "查看 \(currentItem.author) 的工坊" : "查看作者工坊"
        author.isEnabled = !isRefreshingDetail && (service.selectedDownloadInspectorItem?.id == currentItem.id || SteamWorkshopService.resolvedAuthorWorkshopURL(for: currentItem) != nil)
        author.heightAnchor.constraint(equalToConstant: 36).isActive = true
        author.layer?.cornerRadius = 18
        return author
    }

    private func subscriptionButton() -> InspectorFooterButton {
        let state = service.steamSubscriptions.state(for: currentItem.id)
        let title: String
        let symbol: String
        var enabled = true
        if !service.steamAuth.isOnline { title = "订阅"; symbol = "plus" }
        else {
            switch state {
            case .known(let subscribed): title = subscribed ? "已订阅" : "订阅"; symbol = subscribed ? "checkmark" : "plus"
            case .unknown:
                title = "查询中…"; symbol = "clock"; enabled = false
                let id = currentItem.id
                Task { @MainActor [weak self] in
                    guard let self, self.currentItem.id == id, self.service.steamSubscriptions.state(for: id) == .unknown else { return }
                    self.service.steamSubscriptions.refresh(id)
                }
            case .loading: title = "查询中…"; symbol = "clock"; enabled = false
            case .writing, .reconciling: title = "核对中…"; symbol = "clock"; enabled = false
            case .unconfirmed: title = "待确认"; symbol = "questionmark.circle"
            }
        }
        let subscription = footerButton(title: title, symbolName: symbol, kind: .secondary, target: self, action: #selector(toggleSubscriptionClicked(_:)))
        subscription.layer?.cornerRadius = 16
        subscription.isEnabled = enabled
        subscription.toolTip = service.steamAuth.isOnline ? "管理作品订阅；不会删除本地壁纸" : "请使用工具栏登录 Steam 后订阅"
        return subscription
    }

    @objc private func toggleSubscriptionClicked(_ sender: NSView) {
        guard service.steamAuth.isOnline else {
            subscriptionHint = "请使用工具栏登录 Steam，登录后即可订阅。"
            rebuild(preservingScrollPosition: true)
            return
        }
        let entry = SteamWorkshopItemMenu.subscription(item: currentItem, service: service)
        if service.steamSubscriptions.state(for: currentItem.id) == .known(true) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(entry)
            let hint = NSMenuItem(title: "不会删除本地文件或中断播放", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
        } else if entry.isEnabled, let action = entry.action {
            NSApp.sendAction(action, to: entry.target, from: entry)
        }
    }

    private func buildWebDiagnosticsSection(in destination: NSStackView) {
        guard let webDownloadRecord else { return }

        let stack = verticalStack(spacing: 10)
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false

        let titleStack = verticalStack(spacing: 4)
        titleStack.addArrangedSubview(sectionTitle("WEB 诊断"))
        titleStack.addArrangedSubview(label(
            webDiagnosticsExpanded ? "已展开详细诊断与兼容提示" : "默认不立即执行重扫描，按需展开以避免打开详情时卡顿",
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor,
            lines: 0
        ))
        header.addArrangedSubview(titleStack)
        header.addArrangedSubview(spacer())

        let toggle = NSButton(title: webDiagnosticsExpanded ? "收起" : "展开", target: self, action: #selector(toggleWebDiagnostics))
        toggle.bezelStyle = .rounded
        toggle.controlSize = .small
        header.addArrangedSubview(toggle)
        stack.addArrangedSubview(header)

        if webDiagnosticsExpanded,
           let report = service.webValidationReport(for: webDownloadRecord) {
            buildWebDiagnosticsReport(report, record: webDownloadRecord, descriptor: webProjectDescriptor, in: stack)
        }

        destination.addArrangedSubview(stack)
    }

    private func buildWebDiagnosticsReport(
        _ report: SteamWorkshopWebValidationReport,
        record: SteamWorkshopDownloadRecord?,
        descriptor: ResolvedWebProjectDescriptor?,
        in stack: NSStackView
    ) {
        let resolvedEntryPath = descriptor?.resolvedEntryRelativePath ?? report.entryRelativePath
        let entrySummary = resolvedEntryPath.isEmpty ? "未解析到入口" : resolvedEntryPath
        let runtimeEvents = WebRuntimeDiagnosticsStore.shared.recentEvents(recordID: record?.id, limit: 12)

        stack.addArrangedSubview(sectionTitle("WEB 诊断"))
        stack.addArrangedSubview(notice(
            icon: "square.stack.3d.up",
            text: "属性来源：\(descriptor?.propertySource.displayName ?? report.propertySource.displayName)"
                + ((descriptor?.presetOverrideMap.count ?? report.presetOverrideCount) > 0
                   ? "  ·  壳 preset 覆盖 \(descriptor?.presetOverrideMap.count ?? report.presetOverrideCount) 条"
                   : "")
        ))
        stack.addArrangedSubview(notice(
            icon: "doc.text.magnifyingglass",
            text: "样本结构：\(descriptor?.sampleStructure.displayName ?? report.sampleStructure.displayName)  ·  入口：\(entrySummary)  ·  扫描文件：\(report.scannedFileCount)"
        ))

        if report.issues.isEmpty {
            stack.addArrangedSubview(validationPill(severity: .info, levelTitle: SteamWorkshopWebValidationLevel.info.displayName, message: "未发现明显的本地资源缺失或外部依赖风险"))
        } else {
            report.issues.forEach {
                stack.addArrangedSubview(validationPill(severity: $0.severity, levelTitle: $0.level.displayName, message: $0.message))
            }
        }

        if let record, case let .missing(itemID) = record.dependencyStatus {
            stack.addArrangedSubview(validationPill(
                severity: .warning,
                levelTitle: SteamWorkshopWebValidationLevel.preconditionUnmet.displayName,
                message: record.isDependencyBackedWeb
                    ? "当前样本属于依赖型 WEB 预设壳，需先下载依赖宿主 \(itemID) 才能运行"
                    : "当前项目声明依赖包 \(itemID)，但本地未找到该依赖的可启动 WEB 入口"
            ))
        }

        if !runtimeEvents.isEmpty {
            stack.addArrangedSubview(sectionTitle("最近运行事件"))
            runtimeEvents.forEach {
                stack.addArrangedSubview(validationPill(severity: $0.validationSeverity, levelTitle: $0.type, message: $0.displayMessage))
            }
        }
    }
    private func buildSceneDiagnosticsSection(in destination: NSStackView) {
        guard let record = sceneDownloadRecord else { return }
        destination.addArrangedSubview(
            sceneInspectionController.makeSection(for: record)
        )
    }

    private func buildFooterActions() {
        let primary = makeDownloadProgressView() ?? primaryFooterButton()
        let webpage = footerIconButton(symbolName: "safari", help: "在浏览器打开作品", action: #selector(openWorkshopDetail))
        let properties = footerIconButton(symbolName: "gearshape", help: "属性调节", action: #selector(openProperties))
        properties.isEnabled = latestDownloadRecord?.status == .ready && latestDownloadRecord?.contentType != .unknown
        if latestDownloadRecord?.status != .ready { properties.toolTip = "下载完成后可查看属性" }
        let diagnosticsMenu = NSMenu()
        diagnosticsMenu.addItem(SteamWorkshopMenuItem(title: "播放诊断", symbol: "stethoscope") { [weak self] in self?.openDiagnostics() })
        properties.menu = diagnosticsMenu
        footerView.configure(primary: primary, webpage: webpage, properties: properties)
    }

    private func openDiagnostics() {
        guard let record = latestDownloadRecord, record.contentType == .scene || record.contentType == .web else { return }
        let stack = verticalStack(spacing: 12)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = stack
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        diagnosticsPanelStack = stack
        diagnosticsPanelToken = SteamWorkshopPropertyPanelController.shared.show(title: "播放诊断", subtitle: record.title, content: scroll)
        refreshDiagnosticsPanel()
    }

    private func refreshDiagnosticsPanel() {
        guard let token = diagnosticsPanelToken,
              SteamWorkshopPropertyPanelController.shared.presentationID == token,
              let stack = diagnosticsPanelStack, let record = latestDownloadRecord else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if record.contentType == .scene {
            buildSceneDiagnosticsSection(in: stack)
        } else if record.contentType == .web {
            buildWebDiagnosticsSection(in: stack)
        }
        for child in stack.arrangedSubviews { child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }

    @objc private func openProperties() {
        guard let record = latestDownloadRecord, record.status == .ready else { return }
        switch record.contentType {
        case .unknown: return
        case .scene:
            sceneInspectionController.requestPropertyEditor(for: record)
        case .web:
            SteamWorkshopPropertyPanelController.shared.show(title: "Web 属性调节", subtitle: record.title,
                content: SteamWorkshopWebPropertyEditorView(record: record))
        case .video:
            let text = label("视频壁纸没有作者可调属性。音量、播放速度及播放方式使用应用的播放设置。", font: .systemFont(ofSize: 13), color: .secondaryLabelColor, lines: 0)
            SteamWorkshopPropertyPanelController.shared.show(title: "Video 属性", subtitle: record.title, content: text)
        }
    }

    private var isCurrentWallpaper: Bool {
        guard let record = latestDownloadRecord else { return false }
        switch record.contentType {
        case .unknown: return false
        case .scene: return SceneDaemonClient.shared.activeRecordID == record.id
        case .web: return service.isActiveWebRecord(record)
        case .video:
            guard WallpaperEngine.shared.currentPlaybackContentKind == .video,
                  let path = WallpaperEngine.shared.currentContentPath else { return false }
            return [record.videoURL, record.exportedVideoURL, record.sourceVideoURL].compactMap { $0 }
                .contains { $0.resolvingSymlinksInPath().standardizedFileURL.path == path }
        }
    }

    @objc private func stopCurrentWallpaper() {
        guard isCurrentWallpaper, let record = latestDownloadRecord else { rebuild(); return }
        // Web currently shares the Video command handler and WallpaperEngine owner.
        let consumed = PlaybackCommandMultiplexer.shared.dispatch(.stop, to: record.contentType == .scene ? .scene : .video)
        if !consumed { subscriptionHint = "停止播放未完成，请重试。" }
        rebuild()
    }

    private func primaryFooterButton() -> InspectorFooterButton {
        if isCurrentWallpaper {
            return footerButton(title: "停止播放", symbolName: "stop.fill", kind: .secondary, target: self, action: #selector(stopCurrentWallpaper))
        }

        if downloadProgressSnapshot?.phase == .saving {
            let button = footerButton(
                title: "正在保存…",
                symbolName: "checkmark.circle.fill",
                kind: .primary,
                target: self,
                action: #selector(cancelDownload)
            )
            button.isEnabled = false
            return button
        }
        if service.isDownloading(itemID: currentItem.id) || service.isQueuedForDownload(itemID: currentItem.id) {
            return footerButton(
                title: service.isQueuedForDownload(itemID: currentItem.id) ? "取消队列" : "取消下载",
                symbolName: "hourglass.circle.fill",
                kind: .danger,
                target: self,
                action: #selector(cancelDownload)
            )
        }

        let record = latestDownloadRecord.flatMap { $0.status == .ready ? $0 : nil } ?? downloadRecord
        if let record,
           case let .missing(itemID) = record.dependencyStatus {
            if service.isDownloading(itemID: itemID) || service.isQueuedForDownload(itemID: itemID) {
                return footerButton(
                    title: "取消依赖下载",
                    symbolName: "hourglass.circle.fill",
                    kind: .danger,
                    target: self,
                    action: #selector(cancelRequiredDependencyDownload)
                )
            }
            return footerButton(
                title: "下载依赖 #\(itemID)",
                symbolName: "shippingbox.fill",
                kind: .primary,
                target: self,
                action: #selector(downloadRequiredDependency)
            )
        }

        if let record {
            if service.isLaunchPending(record.id) {
                let button = footerButton(
                    title: "正在切换…",
                    symbolName: "hourglass.circle.fill",
                    kind: .primary,
                    target: self,
                    action: #selector(setAsWallpaper)
                )
                button.isEnabled = false
                return button
            }
            return footerButton(
                title: "设为壁纸",
                symbolName: record.contentType == .scene ? "play.circle.fill" : "photo.fill",
                kind: .primary,
                target: self,
                action: #selector(setAsWallpaper)
            )
        }

        let button = footerButton(
            title: latestDownloadFailure != nil ? "重试下载" : "下载壁纸",
            symbolName: latestDownloadFailure != nil ? "arrow.clockwise.circle.fill" : "arrow.down.circle.fill",
            kind: .primary,
            target: self,
            action: #selector(requestDownload)
        )
        button.isEnabled = service.canRequestDownload(id: currentItem.id)
        return button
    }

    @objc private func toggleWebDiagnostics() {
        webDiagnosticsExpanded.toggle()
        refreshDiagnosticsPanel()
    }

    @objc private func requestDownload() {
        service.requestDownloadForBrowserItem(currentItem)
    }

    @objc private func cancelDownload() {
        service.cancelDownload(itemID: currentItem.id)
    }

    @objc private func downloadRequiredDependency() {
        guard let record = latestDownloadRecord ?? downloadRecord else { return }
        service.requestMissingDependencyDownload(for: record)
    }

    @objc private func cancelRequiredDependencyDownload() {
        guard let record = latestDownloadRecord ?? downloadRecord,
              case let .missing(itemID) = record.dependencyStatus else {
            return
        }
        service.cancelDownload(itemID: itemID)
    }

    @objc private func setAsWallpaper() {
        guard let record = latestDownloadRecord ?? downloadRecord else { return }
        service.setAsWallpaper(record)
    }

    @objc private func openAuthorWorkshop() {
        if service.selectedDownloadInspectorItem?.id == currentItem.id {
            service.openAuthorWorkshopFromLocalDownloadMetadata(for: currentItem)
            return
        }
        service.openAuthorWorksPage(for: currentItem)
    }

    @objc private func openWorkshopDetail() {
        service.openWorkshopDetailPage(for: currentItem)
    }

    private func verticalStack(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    private func label(_ text: String, font: NSFont, color: NSColor, lines: Int) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.maximumNumberOfLines = lines
        label.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let title = label(text, font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabelColor, lines: 1)
        title.alignment = .center
        return title
    }

    private func divider() -> NSView {
        let view = NSBox()
        view.boxType = .custom
        view.borderType = .noBorder
        view.fillColor = NSColor.labelColor.withAlphaComponent(0.10)
        view.contentViewMargins = .zero
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    private func factsGrid(_ facts: [(String, String)]) -> NSView {
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false

        var index = 0
        while index < facts.count {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 12
            row.distribution = .fillEqually
            row.translatesAutoresizingMaskIntoConstraints = false
            row.addArrangedSubview(factView(label: facts[index].0, value: facts[index].1))
            if index + 1 < facts.count {
                row.addArrangedSubview(factView(label: facts[index + 1].0, value: facts[index + 1].1))
            } else {
                row.addArrangedSubview(NSView())
            }
            grid.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
            index += 2
        }
        return grid
    }

    private func factView(label title: String, value: String) -> NSView {
        let stack = verticalStack(spacing: 4)
        stack.addArrangedSubview(label(title, font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor, lines: 1))
        stack.addArrangedSubview(label(value, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor, lines: 0))
        return stack
    }

    private func notice(icon: String, text: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        let imageView = NSImageView(image: NSImage(systemSymbolName: icon, accessibilityDescription: nil) ?? NSImage())
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        imageView.contentTintColor = .secondaryLabelColor
        row.addArrangedSubview(imageView)
        row.addArrangedSubview(label(text, font: .systemFont(ofSize: 12, weight: .semibold), color: .secondaryLabelColor, lines: 0))
        return row
    }

    private func errorNotice(message: String, retry: @escaping () -> Void) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        let textStack = verticalStack(spacing: 4)
        textStack.addArrangedSubview(label("详情补全失败", font: .systemFont(ofSize: 12, weight: .semibold), color: .labelColor, lines: 1))
        textStack.addArrangedSubview(label(message, font: .systemFont(ofSize: 11), color: .secondaryLabelColor, lines: 2))
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(spacer())
        let button = ClosureButton(title: "重试", actionHandler: retry)
        button.bezelStyle = .rounded
        row.addArrangedSubview(button)
        return row
    }

    private func validationPill(severity: SteamWorkshopWebValidationSeverity, levelTitle: String?, message: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.wantsLayer = true
        let tint = validationTint(severity)
        row.layer?.cornerRadius = 10
        row.layer?.backgroundColor = tint.withAlphaComponent(0.10).cgColor
        row.layer?.borderColor = tint.withAlphaComponent(0.20).cgColor
        row.layer?.borderWidth = 0.7

        let iconName: String
        switch severity {
        case .error: iconName = "xmark.octagon.fill"
        case .warning: iconName = "exclamationmark.triangle.fill"
        case .info: iconName = "info.circle.fill"
        }
        let icon = NSImageView(image: NSImage(systemSymbolName: iconName, accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        icon.contentTintColor = tint
        row.addArrangedSubview(icon)
        let textStack = verticalStack(spacing: 4)
        if let levelTitle, !levelTitle.isEmpty {
            textStack.addArrangedSubview(label(levelTitle, font: .systemFont(ofSize: 10, weight: .semibold), color: tint, lines: 1))
        }
        textStack.addArrangedSubview(label(message, font: .systemFont(ofSize: 12), color: .labelColor, lines: 0))
        row.addArrangedSubview(textStack)
        return row
    }

    private func validationTint(_ severity: SteamWorkshopWebValidationSeverity) -> NSColor {
        switch severity {
        case .error: return .systemRed
        case .warning: return .systemOrange
        case .info: return .secondaryLabelColor
        }
    }

    private func footerButton(title: String, symbolName: String, kind: InspectorFooterButtonKind, target: AnyObject, action: Selector) -> InspectorFooterButton {
        InspectorFooterButton(title: title, image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title), kind: kind, target: target, action: action)
    }

    private func footerIconButton(symbolName: String, help: String, action: Selector) -> InspectorFooterButton {
        let button = InspectorFooterButton(title: "", image: NSImage(systemSymbolName: symbolName, accessibilityDescription: help), kind: .secondary, target: self, action: action)
        button.toolTip = help
        button.setAccessibilityLabel(help)
        return button
    }


}

private final class ClosureButton: NSButton {
    private let actionHandler: () -> Void

    init(title: String, actionHandler: @escaping () -> Void) {
        self.actionHandler = actionHandler
        super.init(frame: .zero)
        self.title = title
        target = self
        action = #selector(runAction)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @objc private func runAction() {
        actionHandler()
    }
}

private final class SteamWorkshopDetailDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private extension WebRuntimeDiagnosticEvent {
    var validationSeverity: SteamWorkshopWebValidationSeverity {
        switch severity {
        case .error:
            return .error
        case .warning:
            return .warning
        case .info:
            return .info
        }
    }

    var displayMessage: String {
        let urlText = url.map { "  ·  \($0)" } ?? ""
        return "\(message)\(urlText)"
    }
}
