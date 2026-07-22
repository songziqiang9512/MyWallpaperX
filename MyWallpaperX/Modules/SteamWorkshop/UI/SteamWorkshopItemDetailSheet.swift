import AppKit
import Combine
import ObjectiveC
import SwiftUI
import UniformTypeIdentifiers

final class AppKitSteamWorkshopItemDetailView: NSView {
    private enum Metrics {
        static let previewHeight: CGFloat = 156
        static let cornerRadius: CGFloat = 18
        static let contentSpacing: CGFloat = 16
        static let contentTopInset: CGFloat = 22
        static let footerHeight: CGFloat = InspectorFooterMetrics.height
    }

    private let service = SteamWorkshopService.shared
    private let initialItem: SteamWorkshopBrowserItem
    private var currentItem: SteamWorkshopBrowserItem
    private var cancellables = Set<AnyCancellable>()
    private var webPropertiesExpanded = false
    private var webAdvancedPropertiesExpanded = false
    private var webDiagnosticsExpanded = false

    private let rootStack = NSStackView()
    private let scrollView = InspectorFadingScrollView()
    private let documentContainer = SteamWorkshopDetailDocumentView()
    private let contentStack = NSStackView()
    private let footerView = NSView()
    private let previewView = SteamWorkshopPreviewImageContainerView()
    private var isRestoringScrollPosition = false

    init(item: SteamWorkshopBrowserItem) {
        self.initialItem = item
        self.currentItem = item
        super.init(frame: .zero)
        setup()
        observeService()
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(item: SteamWorkshopBrowserItem) {
        let isSameItem = item.id == currentItem.id
        if !isSameItem {
            webPropertiesExpanded = false
            webAdvancedPropertiesExpanded = false
            webDiagnosticsExpanded = false
        }
        currentItem = resolvedCurrentItem(fallback: item)
        rebuild(preservingScrollPosition: isSameItem)
    }

    private func observeService() {
        service.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.currentItem = self.resolvedCurrentItem(fallback: self.currentItem)
                self.rebuild()
            }
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
                self.rebuild(preservingScrollPosition: true)
            }
            .store(in: &cancellables)
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

    private var secondaryFactText: String? {
        let values = [
            currentItem.scoreText,
            currentItem.subscriptionsText.map { "订阅 \($0)" },
            currentItem.favoritesText.map { "收藏 \($0)" }
        ].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: "  ·  ")
    }

    private var statusFactText: String? {
        let values = [
            currentItem.visibilityText.map { "可见性 \($0)" },
            currentItem.moderationText.map { "状态 \($0)" }
        ].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: "  ·  ")
    }

    private var heroBadges: [String] {
        [currentItem.workshopTypeText, currentItem.ageRatingText, currentItem.genreText]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
    }

    private var statFacts: [(String, String)] {
        [
            ("分辨率", currentItem.resolutionText),
            ("文件大小", currentItem.fileSizeText),
            ("发布时间", currentItem.postedText),
            ("分类", currentItem.categoryText)
        ].compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        }
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
        contentStack.edgeInsets = NSEdgeInsets(top: Metrics.contentTopInset, left: 0, bottom: 0, right: 0)
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

        buildPreviewSection()
        buildMetaSection()
        buildContentSection()
        buildWebPropertiesSection()
        buildWebDiagnosticsSection()
        buildSceneDiagnosticsSection()
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
        }
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
            previewView.heightAnchor.constraint(equalToConstant: Metrics.previewHeight)
        ])

        let title = label(
            currentItem.title,
            font: .systemFont(ofSize: 19, weight: .semibold),
            color: .labelColor,
            lines: 2
        )
        stack.addArrangedSubview(title)

        if !currentItem.author.isEmpty {
            stack.addArrangedSubview(label(
                currentItem.author,
                font: .systemFont(ofSize: 12, weight: .medium),
                color: .secondaryLabelColor,
                lines: 1
            ))
        }

        if let secondaryFactText {
            stack.addArrangedSubview(label(
                secondaryFactText,
                font: .systemFont(ofSize: 11, weight: .medium),
                color: .secondaryLabelColor,
                lines: 2
            ))
        }

        contentStack.addArrangedSubview(stack)
    }

    private func buildMetaSection() {
        guard !heroBadges.isEmpty || statusFactText != nil else { return }
        let stack = verticalStack(spacing: 10)

        if !heroBadges.isEmpty {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            heroBadges.forEach { row.addArrangedSubview(badge($0)) }
            stack.addArrangedSubview(row)
        }

        if let statusFactText {
            stack.addArrangedSubview(label(
                statusFactText,
                font: .systemFont(ofSize: 11, weight: .medium),
                color: .secondaryLabelColor,
                lines: 2
            ))
        }

        contentStack.addArrangedSubview(stack)
    }

    private func buildContentSection() {
        let stack = verticalStack(spacing: 14)

        if !statFacts.isEmpty {
            stack.addArrangedSubview(divider())
            let grid = factsGrid(statFacts)
            stack.addArrangedSubview(grid)
        }

        stack.addArrangedSubview(divider())
        let descriptionStack = verticalStack(spacing: 6)
        descriptionStack.addArrangedSubview(sectionTitle("描述"))
        descriptionStack.addArrangedSubview(label(
            detailDescriptionLine,
            font: .systemFont(ofSize: 13),
            color: .labelColor,
            lines: 3
        ))
        stack.addArrangedSubview(descriptionStack)

        contentStack.addArrangedSubview(stack)
    }

    private func buildNoticeSection() {
        let stack = verticalStack(spacing: 8)

        if let currentDetailError, webDownloadRecord == nil {
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

        if isRefreshingDetail, webDownloadRecord == nil {
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

        if let record = sceneDownloadRecord {
            stack.addArrangedSubview(notice(icon: "square.stack.3d.up", text: service.sceneDiagnosticsSummary(for: record)))
        }

        if !currentItem.dependencyIDs.isEmpty {
            stack.addArrangedSubview(notice(
                icon: "link.badge.plus",
                text: "该项目依赖以下 Workshop 项：\(currentItem.dependencyIDs.joined(separator: "、"))"
            ))
        }

        if currentItem.hasAdultContent {
            stack.addArrangedSubview(notice(icon: "exclamationmark.triangle.fill", text: "此项目被 Steam 标记为成人内容"))
        }

        guard !stack.arrangedSubviews.isEmpty else { return }
        contentStack.addArrangedSubview(stack)
    }

    private func buildWebDiagnosticsSection() {
        guard let webDownloadRecord else { return }
        contentStack.addArrangedSubview(divider())

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

        contentStack.addArrangedSubview(stack)
    }

    private func buildWebPropertiesSection() {
        guard let record = webDownloadRecord,
              let descriptor = webProjectDescriptor else { return }

        let values = service.effectiveWebPropertyValues(for: record, descriptor: descriptor)
        let renderableDefinitions = descriptor.propertyDefinitions.filter {
            service.shouldRenderWebPropertyControl(
                $0,
                staticContentSummary: descriptor.staticContentSummary
            )
                && service.shouldDisplayWebProperty(
                    $0,
                    values: values,
                    definitions: descriptor.propertyDefinitions
                )
        }
        guard !renderableDefinitions.isEmpty else { return }

        contentStack.addArrangedSubview(divider())

        let shouldUseCollapsedPresentation = renderableDefinitions.count > 8
        if !shouldUseCollapsedPresentation {
            webPropertiesExpanded = true
        }

        let stack = verticalStack(spacing: 12)
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false

        let titleStack = verticalStack(spacing: 4)
        titleStack.addArrangedSubview(sectionTitle("WEB 属性"))
        titleStack.addArrangedSubview(label(
            record.isDependencyBackedWeb
                ? "属性定义来自依赖宿主，当前修改会写回这个补丁壳样本"
                : "根据当前壁纸的 project.json 动态生成调节项",
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor,
            lines: 0
        ))
        header.addArrangedSubview(titleStack)
        header.addArrangedSubview(spacer())

        if shouldUseCollapsedPresentation {
            let toggle = NSButton(
                title: webPropertiesExpanded ? "收起" : "展开 \(renderableDefinitions.count) 项",
                target: self,
                action: #selector(toggleWebProperties)
            )
            toggle.bezelStyle = .rounded
            toggle.controlSize = .small
            header.addArrangedSubview(toggle)
        }
        stack.addArrangedSubview(header)

        if webPropertiesExpanded {
            let resetRow = NSStackView()
            resetRow.orientation = .horizontal
            resetRow.alignment = .centerY
            resetRow.translatesAutoresizingMaskIntoConstraints = false
            resetRow.addArrangedSubview(spacer())
            let reset = NSButton(title: "重置", target: self, action: #selector(resetWebProperties))
            reset.bezelStyle = .rounded
            reset.controlSize = .small
            resetRow.addArrangedSubview(reset)
            stack.addArrangedSubview(resetRow)

            let primary = renderableDefinitions.filter { service.isPrimaryWebPropertyControl($0) }
            let advanced = renderableDefinitions.filter { !service.isPrimaryWebPropertyControl($0) }
            let visibleOptionsByKey = Dictionary(uniqueKeysWithValues: renderableDefinitions.map {
                (
                    $0.key,
                    service.visibleWebPropertyOptions(
                        for: $0,
                        values: values,
                        definitions: descriptor.propertyDefinitions
                    )
                )
            })

            primary.forEach {
                stack.addArrangedSubview(webPropertyControl(definition: $0, value: values[$0.key] ?? $0.defaultValue, visibleOptions: visibleOptionsByKey[$0.key] ?? [], record: record))
            }

            if !advanced.isEmpty {
                let advancedToggle = NSButton(
                    title: webAdvancedPropertiesExpanded ? "收起高级参数" : "展开高级参数 \(advanced.count) 项",
                    target: self,
                    action: #selector(toggleAdvancedWebProperties)
                )
                advancedToggle.bezelStyle = .inline
                advancedToggle.alignment = .left
                stack.addArrangedSubview(advancedToggle)

                if webAdvancedPropertiesExpanded {
                    advanced.forEach {
                        stack.addArrangedSubview(webPropertyControl(definition: $0, value: values[$0.key] ?? $0.defaultValue, visibleOptions: visibleOptionsByKey[$0.key] ?? [], record: record))
                    }
                }
            }
        }

        contentStack.addArrangedSubview(stack)
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

    private func buildSceneDiagnosticsSection() {
        guard let record = sceneDownloadRecord,
              let report = service.sceneDiagnosticsReport(for: record) else { return }

        let propertyContext = service.scenePropertyContext(for: record, report: report)
        let section = SteamWorkshopSceneDetailSection(
            record: record,
            report: report,
            propertyContext: propertyContext
        ) {
            guard let propertyContext else { return }
            ScenePropertyWindowController.shared.show(record: record, context: propertyContext)
        }
        let hostingView = NSHostingView(rootView: section)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(hostingView)
    }

    private func buildFooterActions() {
        let primary = primaryFooterButton()
        let author = footerButton(
            title: "作者工坊",
            symbolName: "person.crop.circle.fill",
            kind: .secondary,
            target: self,
            action: #selector(openAuthorWorkshop)
        )
        let isDownloadInspectorItem = service.selectedDownloadInspectorItem?.id == currentItem.id
        author.isEnabled = !isRefreshingDetail && (isDownloadInspectorItem || SteamWorkshopService.resolvedAuthorWorkshopURL(for: currentItem) != nil)
        let browser = footerIconButton(symbolName: "safari", help: "网页浏览", action: #selector(openWorkshopDetail))
        let refresh = footerIconButton(symbolName: "arrow.clockwise", help: "刷新详情", action: #selector(refreshDetail))
        refresh.isEnabled = !isRefreshingDetail

        [primary, author, browser, refresh].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            footerView.addSubview($0)
        }

        let iconButtonWidth = Metrics.footerHeight
        NSLayoutConstraint.activate([
            primary.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 2),
            primary.topAnchor.constraint(equalTo: footerView.topAnchor),
            primary.bottomAnchor.constraint(equalTo: footerView.bottomAnchor),
            primary.heightAnchor.constraint(equalToConstant: Metrics.footerHeight),
            author.leadingAnchor.constraint(equalTo: primary.trailingAnchor, constant: 6),
            author.topAnchor.constraint(equalTo: footerView.topAnchor),
            author.bottomAnchor.constraint(equalTo: footerView.bottomAnchor),
            author.heightAnchor.constraint(equalToConstant: Metrics.footerHeight),
            browser.leadingAnchor.constraint(equalTo: author.trailingAnchor, constant: 6),
            browser.topAnchor.constraint(equalTo: footerView.topAnchor),
            browser.bottomAnchor.constraint(equalTo: footerView.bottomAnchor),
            browser.widthAnchor.constraint(equalToConstant: iconButtonWidth),
            browser.heightAnchor.constraint(equalToConstant: Metrics.footerHeight),
            refresh.leadingAnchor.constraint(equalTo: browser.trailingAnchor, constant: 6),
            refresh.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -2),
            refresh.topAnchor.constraint(equalTo: footerView.topAnchor),
            refresh.bottomAnchor.constraint(equalTo: footerView.bottomAnchor),
            refresh.widthAnchor.constraint(equalToConstant: iconButtonWidth),
            refresh.heightAnchor.constraint(equalToConstant: Metrics.footerHeight),
            author.widthAnchor.constraint(equalTo: primary.widthAnchor)
        ])
    }

    private func primaryFooterButton() -> InspectorFooterButton {
        if service.isDownloading(itemID: currentItem.id) || service.isQueuedForDownload(itemID: currentItem.id) {
            return footerButton(
                title: service.isQueuedForDownload(itemID: currentItem.id) ? "取消队列" : "取消下载",
                symbolName: "hourglass.circle.fill",
                kind: .danger,
                target: self,
                action: #selector(cancelDownload)
            )
        }

        let record = latestDownloadRecord ?? downloadRecord
        if let record,
           case let .missing(itemID) = record.dependencyStatus {
            if service.isDownloading(itemID: itemID) || service.isQueuedForDownload(itemID: itemID) {
                return footerButton(
                    title: service.isQueuedForDownload(itemID: itemID) ? "依赖等待下载" : "依赖下载中",
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
            return footerButton(
                title: "设为壁纸",
                symbolName: record.contentType == .scene ? "play.circle.fill" : "photo.fill",
                kind: .primary,
                target: self,
                action: #selector(setAsWallpaper)
            )
        }

        let isSceneItem = currentItem.workshopTypeText?.localizedCaseInsensitiveCompare("Scene") == .orderedSame
        let button = footerButton(
            title: latestDownloadFailure != nil ? "重新下载" : (isSceneItem ? "下载 Scene" : "下载视频"),
            symbolName: latestDownloadFailure != nil ? "arrow.clockwise.circle.fill" : "arrow.down.circle.fill",
            kind: .primary,
            target: self,
            action: #selector(requestDownload)
        )
        button.isEnabled = service.canRequestDownload(id: currentItem.id)
        return button
    }

    private func webPropertyControl(
        definition: SteamWorkshopWebPropertyDefinition,
        value: SteamWorkshopWebPropertyValue,
        visibleOptions: [SteamWorkshopWebPropertyOption],
        record: SteamWorkshopDownloadRecord
    ) -> NSView {
        let card = NSStackView()
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = 8
        card.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.10).cgColor
        card.layer?.borderWidth = 0.7
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor

        var summaryLabel: NSTextField?
        if definition.kind != .group && definition.kind != .label {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            row.addArrangedSubview(label(definition.title, font: .systemFont(ofSize: 12, weight: .semibold), color: .labelColor, lines: 1))
            row.addArrangedSubview(spacer())
            let valueLabel = label(valueSummary(value, definition: definition), font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor, lines: 1)
            summaryLabel = valueLabel
            row.addArrangedSubview(valueLabel)
            card.addArrangedSubview(row)
        }

        card.addArrangedSubview(controlView(definition: definition, value: value, visibleOptions: visibleOptions, record: record, summaryLabel: summaryLabel))

        if let footnote = propertyFootnote(definition: definition, visibleOptions: visibleOptions) {
            card.addArrangedSubview(label(footnote, font: .systemFont(ofSize: 10, weight: .medium), color: .secondaryLabelColor, lines: 0))
        }

        return card
    }

    private func controlView(
        definition: SteamWorkshopWebPropertyDefinition,
        value: SteamWorkshopWebPropertyValue,
        visibleOptions: [SteamWorkshopWebPropertyOption],
        record: SteamWorkshopDownloadRecord,
        summaryLabel: NSTextField?
    ) -> NSView {
        switch definition.kind {
        case .slider:
            let target = WebPropertyActionTarget(view: self, record: record, definition: definition, summaryLabel: summaryLabel)
            let slider = WebPropertySlider(value: value.numberValue ?? definition.defaultValue.numberValue ?? definition.minimumValue ?? 0,
                                           minValue: definition.minimumValue ?? 0,
                                           maxValue: definition.maximumValue ?? max((definition.minimumValue ?? 0) + 1, value.numberValue ?? 1),
                                           target: target,
                                           action: #selector(WebPropertyActionTarget.sliderChanged(_:)))
            slider.isContinuous = true
            slider.identifier = NSUserInterfaceItemIdentifier(definition.key)
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.onTrackingEnded = { [weak target] slider in
                target?.sliderTrackingEnded(slider)
            }
            retainActionTarget(target, for: slider)
            return slider
        case .toggle:
            let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            checkbox.state = (value.boolValue ?? definition.defaultValue.boolValue ?? false) ? .on : .off
            let target = WebPropertyActionTarget(view: self, record: record, definition: definition)
            checkbox.target = target
            checkbox.action = #selector(WebPropertyActionTarget.toggleChanged(_:))
            retainActionTarget(target, for: checkbox)
            return checkbox
        case .combo:
            let popup = NSPopUpButton()
            if visibleOptions.isEmpty {
                popup.addItem(withTitle: "当前没有可选项")
                popup.isEnabled = false
            } else {
                var selectedValueID: String?
                if visibleOptions.contains(where: { $0.value == value }) == false {
                    popup.addItem(withTitle: "当前值：\(valueSummary(value, definition: definition))（不可选）")
                    popup.lastItem?.isEnabled = false
                    popup.selectItem(at: 0)
                }
                visibleOptions.forEach { option in
                    popup.addItem(withTitle: option.label)
                    popup.lastItem?.representedObject = option.id as NSString
                    if option.value == value {
                        selectedValueID = option.id
                    }
                }
                if let selectedIndex = visibleOptions.firstIndex(where: { $0.value == value }) {
                    popup.selectItem(withTitle: visibleOptions[selectedIndex].label)
                }
                if let selectedValueID,
                   let item = popup.itemArray.first(where: { ($0.representedObject as? String) == selectedValueID }) {
                    popup.select(item)
                }
            }
            let target = WebPropertyActionTarget(view: self, record: record, definition: definition, visibleOptions: visibleOptions)
            popup.target = target
            popup.action = #selector(WebPropertyActionTarget.popupChanged(_:))
            retainActionTarget(target, for: popup)
            return popup
        case .file, .directory:
            let row = NSStackView()
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 8
            let buttonRow = NSStackView()
            buttonRow.orientation = .horizontal
            buttonRow.spacing = 10
            let choose = NSButton(title: definition.kind == .directory ? "选择文件夹" : "选择文件", target: nil, action: nil)
            choose.bezelStyle = .rounded
            choose.controlSize = .small
            let target = WebPropertyActionTarget(view: self, record: record, definition: definition, summaryLabel: summaryLabel)
            choose.target = target
            choose.action = #selector(WebPropertyActionTarget.choosePath(_:))
            retainActionTarget(target, for: choose)
            buttonRow.addArrangedSubview(choose)
            if !(value.stringValue ?? "").isEmpty {
                let clear = NSButton(title: "清空", target: target, action: #selector(WebPropertyActionTarget.clearPath(_:)))
                clear.bezelStyle = .rounded
                clear.controlSize = .small
                buttonRow.addArrangedSubview(clear)
            }
            buttonRow.addArrangedSubview(spacer())
            row.addArrangedSubview(buttonRow)
            row.addArrangedSubview(textField(textValue(value, definition: definition), placeholder: definition.kind == .directory ? "选择目录路径" : "选择文件路径", target: target, action: #selector(WebPropertyActionTarget.textChanged(_:))))
            return row
        case .label, .group:
            return label(definition.title, font: definition.kind == .group ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 12), color: .labelColor, lines: 0)
        case .color:
            return colorControl(value: value, definition: definition, record: record, summaryLabel: summaryLabel)
        case .text, .unknown:
            let target = WebPropertyActionTarget(view: self, record: record, definition: definition, summaryLabel: summaryLabel)
            return textField(textValue(value, definition: definition), placeholder: definition.title, target: target, action: #selector(WebPropertyActionTarget.textChanged(_:)))
        }
    }

    private func colorControl(
        value: SteamWorkshopWebPropertyValue,
        definition: SteamWorkshopWebPropertyDefinition,
        record: SteamWorkshopDownloadRecord,
        summaryLabel: NSTextField?
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let target = WebPropertyActionTarget(view: self, record: record, definition: definition, summaryLabel: summaryLabel)
        let colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 42, height: 26))
        colorWell.color = color(from: value.stringValue ?? definition.defaultValue.stringValue ?? "0 0 0")
        colorWell.target = target
        colorWell.action = #selector(WebPropertyActionTarget.colorChanged(_:))
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        retainActionTarget(target, for: colorWell)
        row.addArrangedSubview(colorWell)

        let field = textField(
            textValue(value, definition: definition),
            placeholder: "R G B",
            target: target,
            action: #selector(WebPropertyActionTarget.textChanged(_:))
        )
        target.textField = field
        row.addArrangedSubview(field)

        NSLayoutConstraint.activate([
            colorWell.widthAnchor.constraint(equalToConstant: 42),
            colorWell.heightAnchor.constraint(equalToConstant: 26)
        ])
        return row
    }

    private func retainActionTarget(_ target: WebPropertyActionTarget, for control: NSControl) {
        objc_setAssociatedObject(control, "[\(Unmanaged.passUnretained(control).toOpaque())].target", target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    @objc private func toggleWebProperties() {
        webPropertiesExpanded.toggle()
        rebuild(preservingScrollPosition: true)
    }

    @objc private func toggleAdvancedWebProperties() {
        webAdvancedPropertiesExpanded.toggle()
        rebuild(preservingScrollPosition: true)
    }

    @objc private func toggleWebDiagnostics() {
        webDiagnosticsExpanded.toggle()
        rebuild(preservingScrollPosition: true)
    }

    @objc private func resetWebProperties() {
        guard let webDownloadRecord else { return }
        service.resetWebPropertyValues(for: webDownloadRecord)
        rebuild(preservingScrollPosition: true)
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

    @objc private func refreshDetail() {
        service.retryInspectorDetailRefresh(for: currentItem.id)
    }

    private func updateWebProperty(_ value: SteamWorkshopWebPropertyValue, definition: SteamWorkshopWebPropertyDefinition, record: SteamWorkshopDownloadRecord, preview: Bool = false) {
        if preview {
            service.previewWebPropertyValue(value, for: definition, record: record)
            return
        } else {
            service.updateWebPropertyValue(value, for: definition, record: record)
        }
        rebuild(preservingScrollPosition: true)
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
        label(text, font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabelColor, lines: 1)
    }

    private func divider() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    private func badge(_ text: String) -> NSView {
        let label = label(text, font: .systemFont(ofSize: 11, weight: .semibold), color: .labelColor, lines: 1)
        label.alignment = .center
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 15
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
        container.layer?.borderWidth = 0.6
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 15),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -15),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -7)
        ])
        return container
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

    private func textField(_ value: String, placeholder: String, target: AnyObject, action: Selector) -> NSTextField {
        let field = NSTextField(string: value)
        field.placeholderString = placeholder
        field.target = target
        field.action = action
        field.delegate = target as? NSTextFieldDelegate
        field.translatesAutoresizingMaskIntoConstraints = false
        retainActionTarget(target as! WebPropertyActionTarget, for: field)
        return field
    }

    private func textValue(_ value: SteamWorkshopWebPropertyValue, definition: SteamWorkshopWebPropertyDefinition) -> String {
        if let stringValue = value.stringValue { return stringValue }
        if let numberValue = value.numberValue { return formattedNumber(numberValue, allowsFractional: true, precision: definition.fractionalPrecision) }
        if let boolValue = value.boolValue { return boolValue ? "true" : "false" }
        return ""
    }

    private func color(from raw: String) -> NSColor {
        guard let components = SteamWorkshopService.parseWebColorComponents(from: raw) else {
            return .black
        }
        return NSColor(
            deviceRed: components.red,
            green: components.green,
            blue: components.blue,
            alpha: 1
        )
    }

    private func colorString(from color: NSColor) -> String {
        let resolved = color.usingColorSpace(.deviceRGB) ?? .black
        return String(
            format: "%.6f %.6f %.6f",
            resolved.redComponent,
            resolved.greenComponent,
            resolved.blueComponent
        )
    }

    private func valueSummary(_ value: SteamWorkshopWebPropertyValue, definition: SteamWorkshopWebPropertyDefinition) -> String {
        if let stringValue = value.stringValue { return SteamWorkshopService.normalizedWebDisplayText(stringValue) }
        if let numberValue = value.numberValue { return formattedNumber(numberValue, allowsFractional: definition.allowsFractionalValues, precision: definition.fractionalPrecision) }
        if let boolValue = value.boolValue { return boolValue ? "开" : "关" }
        return "-"
    }

    private func propertyFootnote(definition: SteamWorkshopWebPropertyDefinition, visibleOptions: [SteamWorkshopWebPropertyOption]) -> String? {
        switch definition.kind {
        case .combo where !visibleOptions.isEmpty:
            return "\(visibleOptions.count) options"
        case .color:
            return "Wallpaper Engine RGB string"
        case .file:
            return "Wallpaper Engine file path string"
        case .directory:
            if let mode = definition.directoryMode {
                return "Wallpaper Engine directory path string  ·  mode \(mode)"
            }
            return "Wallpaper Engine directory path string"
        case .slider, .label, .group, .toggle, .text, .unknown, .combo:
            return nil
        }
    }

    private func formattedNumber(_ value: Double, allowsFractional: Bool, precision: Int?) -> String {
        if !allowsFractional {
            return String(Int(value.rounded()))
        }
        let digits = max(precision ?? 2, 0)
        return String(format: "%.\(digits)f", value)
    }

    private func normalizedSliderValue(_ value: Double, definition: SteamWorkshopWebPropertyDefinition) -> Double {
        if definition.allowsFractionalValues {
            let precision = SteamWorkshopService.effectiveWebSliderPrecision(for: definition) ?? 2
            guard precision >= 0 else { return value }
            let scale = pow(10.0, Double(precision))
            return (value * scale).rounded() / scale
        }
        return value.rounded()
    }

    private func allowedContentTypes(for fileType: String?) -> [UTType] {
        guard let normalized = fileType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else { return [] }
        switch normalized {
        case "image": return [.image]
        case "video": return [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        case "audio", "music": return [.audio, .mp3, .mpeg4Audio]
        case "font": return [.font]
        default: return []
        }
    }

    private final class WebPropertySlider: NSSlider {
        var isTrackingMouse = false
        var onTrackingEnded: ((NSSlider) -> Void)?

        override func mouseDown(with event: NSEvent) {
            isTrackingMouse = true
            super.mouseDown(with: event)
            isTrackingMouse = false
            onTrackingEnded?(self)
        }
    }

    private final class WebPropertyActionTarget: NSObject, NSTextFieldDelegate {
        weak var view: AppKitSteamWorkshopItemDetailView?
        let record: SteamWorkshopDownloadRecord
        let definition: SteamWorkshopWebPropertyDefinition
        let visibleOptions: [SteamWorkshopWebPropertyOption]
        weak var summaryLabel: NSTextField?
        weak var textField: NSTextField?
        private var pendingColorString: String?
        private var colorPanelCloseObserver: NSObjectProtocol?

        init(
            view: AppKitSteamWorkshopItemDetailView,
            record: SteamWorkshopDownloadRecord,
            definition: SteamWorkshopWebPropertyDefinition,
            visibleOptions: [SteamWorkshopWebPropertyOption] = [],
            summaryLabel: NSTextField? = nil
        ) {
            self.view = view
            self.record = record
            self.definition = definition
            self.visibleOptions = visibleOptions
            self.summaryLabel = summaryLabel
        }

        deinit {
            if let colorPanelCloseObserver {
                NotificationCenter.default.removeObserver(colorPanelCloseObserver)
            }
        }

        @objc func toggleChanged(_ sender: NSButton) {
            view?.updateWebProperty(.bool(sender.state == .on), definition: definition, record: record)
        }

        @objc func popupChanged(_ sender: NSPopUpButton) {
            guard let selectedID = sender.selectedItem?.representedObject as? String,
                  let option = visibleOptions.first(where: { $0.id == selectedID }) else { return }
            view?.updateWebProperty(option.value, definition: definition, record: record)
        }

        @objc func sliderChanged(_ sender: NSSlider) {
            let normalized = view?.normalizedSliderValue(sender.doubleValue, definition: definition) ?? sender.doubleValue
            sender.doubleValue = normalized
            summaryLabel?.stringValue = view?.valueSummary(.number(normalized), definition: definition) ?? String(normalized)
            view?.updateWebProperty(.number(normalized), definition: definition, record: record, preview: true)
            if let slider = sender as? WebPropertySlider {
                if !slider.isTrackingMouse {
                    commitSliderValue(sender)
                }
            } else if !sender.isHighlighted {
                commitSliderValue(sender)
            }
        }

        @objc func textChanged(_ sender: NSTextField) {
            commitTextFieldValue(sender.stringValue)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            previewTextFieldValue(field.stringValue)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            commitTextFieldValue(field.stringValue)
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            guard let colorString = view?.colorString(from: sender.color) else { return }
            observeColorPanelCloseIfNeeded()
            pendingColorString = colorString
            summaryLabel?.stringValue = view?.valueSummary(.string(colorString), definition: definition) ?? colorString
            textField?.stringValue = colorString
            view?.updateWebProperty(.string(colorString), definition: definition, record: record, preview: true)
        }

        @objc func choosePath(_ sender: NSButton) {
            let panel = NSOpenPanel()
            let selectsDirectories = definition.kind == .directory
            panel.canChooseFiles = !selectsDirectories
            panel.canChooseDirectories = selectsDirectories
            panel.allowsMultipleSelection = false
            panel.resolvesAliases = true
            panel.canCreateDirectories = selectsDirectories
            panel.prompt = selectsDirectories ? "选择目录" : "选择文件"
            if !selectsDirectories {
                panel.allowedContentTypes = view?.allowedContentTypes(for: definition.fileType) ?? []
            }
            if panel.runModal() == .OK, let url = panel.url {
                view?.updateWebProperty(.string(url.path), definition: definition, record: record)
            }
        }

        @objc func clearPath(_ sender: NSButton) {
            view?.updateWebProperty(.string(""), definition: definition, record: record)
        }

        private func observeColorPanelCloseIfNeeded() {
            guard colorPanelCloseObserver == nil else { return }
            colorPanelCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: NSColorPanel.shared,
                queue: .main
            ) { [weak self] _ in
                self?.commitPendingColor()
            }
        }

        private func commitSliderValue(_ sender: NSSlider) {
            let normalized = view?.normalizedSliderValue(sender.doubleValue, definition: definition) ?? sender.doubleValue
            sender.doubleValue = normalized
            summaryLabel?.stringValue = view?.valueSummary(.number(normalized), definition: definition) ?? String(normalized)
            view?.updateWebProperty(.number(normalized), definition: definition, record: record)
        }

        func sliderTrackingEnded(_ sender: NSSlider) {
            commitSliderValue(sender)
        }

        private func previewTextFieldValue(_ rawValue: String) {
            pendingColorString = nil
            let value = webPropertyValue(from: rawValue)
            summaryLabel?.stringValue = view?.valueSummary(value, definition: definition) ?? rawValue
            view?.updateWebProperty(value, definition: definition, record: record, preview: true)
        }

        private func commitTextFieldValue(_ rawValue: String) {
            pendingColorString = nil
            view?.updateWebProperty(webPropertyValue(from: rawValue), definition: definition, record: record)
        }

        private func commitPendingColor() {
            guard let pendingColorString else { return }
            self.pendingColorString = nil
            view?.updateWebProperty(.string(pendingColorString), definition: definition, record: record)
        }

        private func webPropertyValue(from rawValue: String) -> SteamWorkshopWebPropertyValue {
            if definition.kind == .slider, let value = Double(rawValue) {
                return .number(value)
            }
            return .string(rawValue)
        }
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
