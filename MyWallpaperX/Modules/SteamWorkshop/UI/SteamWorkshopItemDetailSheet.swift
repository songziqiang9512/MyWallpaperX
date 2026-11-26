import AppKit
import AVFoundation
import Combine

final class AppKitSteamWorkshopItemDetailView: NSView {
    private enum Metrics {
        static let contentSpacing: CGFloat = 16
        static let footerHeight: CGFloat = SteamWorkshopDetailFooterView.height
    }

    let service: SteamWorkshopService
    private var libraryActions: WallpaperInspectorActions?
    private let initialItem: SteamWorkshopBrowserItem
    var currentItem: SteamWorkshopBrowserItem
    var cancellables = Set<AnyCancellable>()
    var subscriptionHint: String?
    private var downloadProgressObserverID: UUID?
    private var downloadProgressSnapshot: SteamWorkshopDownloadProgressSnapshot?
    private weak var primaryProgressButton: InspectorFooterButton?
    private var didBuildInitialContent = false

    private let rootStack = NSStackView()
    private let scrollView = InspectorFadingScrollView()
    private let documentContainer = InspectorContentDocumentView()
    private let contentStack = NSStackView()
    private let footerView = SteamWorkshopDetailFooterView()
    private let previewView = SteamWorkshopPreviewImageContainerView()
    private lazy var sourceVideoFacts = verticalStack(spacing: 0)
    private var videoTrackSource: VideoTrackSource?
    private var videoTrackTask: Task<Void, Never>?
    private lazy var previewHeightConstraint = previewView.heightAnchor.constraint(equalToConstant: 156)
    private var renderedDisplayState: DisplayState?

    private struct VideoTrackSource: Equatable, Sendable {
        let itemID: String
        let url: URL
        let fileRevision: String
    }

    /// Only the active, ready Scene branch proves these in-memory inputs
    /// complete. Other branches keep the ordinary rebuild and its getters.
    private struct DisplayState: Equatable {
        let item: SteamWorkshopBrowserItem
        let record: SteamWorkshopDownloadRecord
        let isLocalDownloadInspector: Bool
        let hasCompletedInstalledLibraryLoad: Bool
        let isRefreshingDetail: Bool
        let detailError: String?
        let previewReloadToken: Int
        let isDownloading: Bool
        let isQueued: Bool
        let isLaunchPending: Bool
        let dependencyTaskActive: Bool
        let progressPhase: SteamWorkshopDownloadProgressSnapshot.Phase?
        let isOnline: Bool
        let subscriptionState: SteamWorkshopSubscriptionStore.State
        let subscriptionHint: String?
    }

    init(item: SteamWorkshopBrowserItem, service: SteamWorkshopService? = nil, libraryActions: WallpaperInspectorActions? = nil) {
        self.service = service ?? .shared
        self.libraryActions = libraryActions
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

    deinit { videoTrackTask?.cancel() }

    func configure(item: SteamWorkshopBrowserItem) {
        let isSameItem = item.id == currentItem.id
        if !isSameItem {
            subscriptionHint = nil
            bindDownloadProgress(to: item.id)
        }
        currentItem = resolvedCurrentItem(fallback: item)
        rebuild(preservingScrollPosition: isSameItem)
    }

    var isRebuildScheduled = false
    var isForcedRebuildScheduled = false


    private func bindDownloadProgress(to itemID: String) {
        if let downloadProgressObserverID {
            service.downloadProgressStore.removeObserver(downloadProgressObserverID)
        }
        downloadProgressObserverID = nil
        primaryProgressButton = nil
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
                self.primaryProgressButton?.setProgressFill(snapshot?.fraction)
                if let snapshot { self.primaryProgressButton?.setTitle(snapshot.statusText(compact: true)) }
            }
        }
    }

    func resolvedCurrentItem(fallback: SteamWorkshopBrowserItem) -> SteamWorkshopBrowserItem {
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

    var latestDownloadRecord: SteamWorkshopDownloadRecord? {
        service.latestDownloadRecord(for: currentItem.id)
    }

    private var latestDownloadFailure: String? {
        latestDownloadRecord?.failureMessage
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
        return value.isEmpty ? String(localized: "No Further Description") : value
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.wantsLayer = true
        scrollView.contentView.wantsLayer = true
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = Metrics.contentSpacing
        contentStack.edgeInsets = NSEdgeInsets(top: InspectorFadingScrollView.contentTopInset, left: 0, bottom: 16, right: 0)
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
            footerView.heightAnchor.constraint(equalToConstant: Metrics.footerHeight),
            previewHeightConstraint
        ])
    }

    private func displayState() -> DisplayState? {
        guard let record = service.latestDownloadRecord(for: currentItem.id),
              record.status == .ready, record.contentType == .scene,
              SceneDaemonClient.shared.activeRecordID == record.id,
              record.sourceVideoURL == nil, record.exportedVideoURL == nil else { return nil }
        let dependencyTaskActive: Bool
        if case let .missing(itemID) = record.dependencyStatus {
            dependencyTaskActive = service.isDownloading(itemID: itemID)
                || service.isQueuedForDownload(itemID: itemID)
        } else {
            dependencyTaskActive = false
        }
        return DisplayState(
            item: currentItem, record: record,
            isLocalDownloadInspector: service.selectedDownloadInspectorItem?.id == currentItem.id,
            hasCompletedInstalledLibraryLoad: service.hasCompletedInstalledLibraryLoad,
            isRefreshingDetail: isRefreshingDetail, detailError: currentDetailError,
            previewReloadToken: service.previewReloadToken,
            isDownloading: service.isDownloading(itemID: currentItem.id),
            isQueued: service.isQueuedForDownload(itemID: currentItem.id),
            isLaunchPending: service.isLaunchPending(record.id),
            dependencyTaskActive: dependencyTaskActive,
            progressPhase: downloadProgressSnapshot?.phase,
            isOnline: service.steamAuth.isOnline,
            subscriptionState: service.steamSubscriptions.state(for: currentItem.id),
            subscriptionHint: subscriptionHint
        )
    }

    /// Notifications remain coalesced; only a previously rendered, complete
    /// display state can suppress their redundant view reconstruction.
    func rebuildIfDisplayChanged() {
        currentItem = resolvedCurrentItem(fallback: currentItem)
        if let state = displayState(), state == renderedDisplayState { return }
        rebuild()
    }

    func rebuild(preservingScrollPosition: Bool = true) {
        let preservedOrigin = preservingScrollPosition ? scrollView.contentView.bounds.origin : nil
        currentItem = resolvedCurrentItem(fallback: currentItem)
        let displayState = displayState()
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        footerView.subviews.forEach { $0.removeFromSuperview() }

        buildPreviewSection()
        contentStack.addArrangedSubview(WallpaperLibraryControlStyle.sectionDivider())
        buildContentSection()
        buildNoticeSection()
        pinContentSectionsToFullWidth()
        buildFooterActions()
        restoreScrollPositionIfNeeded(preservedOrigin ?? .zero)
        renderedDisplayState = displayState
    }

    private func restoreScrollPositionIfNeeded(_ origin: NSPoint) {
        // Finish the new document geometry in the same event turn. Deferring
        // this correction displayed the intermediate origin for one frame.
        layoutSubtreeIfNeeded()
        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let maxY = max(0, documentHeight - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: origin.x, y: min(max(origin.y, 0), maxY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
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
        for child in view.subviews where child !== sourceVideoFacts { constrainColumnContent(in: child) }
    }

    private func buildPreviewSection() {
        let stack = verticalStack(spacing: 8)
        let record = latestDownloadRecord
        let videoURL = record?.videoURL
        previewView.configure(
            itemID: currentItem.id,
            previewImageURL: record?.previewURL ?? currentItem.previewImageURL,
            fallbackImageURL: currentItem.previewImageURL.flatMap { $0.isFileURL ? nil : $0 }
                ?? record?.browserItem?.previewImageURL,
            fallbackVideoURL: videoURL,
            refreshToken: service.previewReloadToken
        )
        refreshVideoTrackSource(record: record, videoURL: videoURL)
        previewView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(previewView)
        // The preview joins a new section on every rebuild; reuse its one
        // setup-owned fixed height instead of constructing another constraint.
        previewHeightConstraint.isActive = true
        previewView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

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

    private func refreshVideoTrackSource(record: SteamWorkshopDownloadRecord?, videoURL: URL?) {
        let source: VideoTrackSource? = if let record, record.status == .ready, record.contentType == .video,
                                          record.isStartupSnapshot != true, let videoURL,
                                          let fileRevision = previewView.previewState.videoSourceKey {
            VideoTrackSource(itemID: record.id, url: videoURL, fileRevision: fileRevision)
        } else { nil }
        guard source != videoTrackSource else { return }
        videoTrackTask?.cancel()
        videoTrackTask = nil
        videoTrackSource = source
        sourceVideoFacts.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sourceVideoFacts.isHidden = true
        guard let source else { return }

        videoTrackTask = Task.detached(priority: .userInitiated) { [weak self] in
            let details = try? await WallpaperVideoTrackDetails.load(from: AVURLAsset(url: source.url))
            await self?.publishVideoTrackDetails(details, for: source)
        }
    }

    private func publishVideoTrackDetails(_ details: WallpaperVideoTrackDetails?, for source: VideoTrackSource) {
        guard !Task.isCancelled, videoTrackSource == source else { return }
        videoTrackTask = nil
        guard let details else { return }
        let facts = [
            (String(localized: "Source Resolution"), details.resolutionText),
            (String(localized: "Codec"), details.codecText),
            (String(localized: "Nominal Frame Rate"), details.nominalFrameRateText),
        ].compactMap { label, value in value.map { (label, $0) } }
        guard !facts.isEmpty else { return }
        let rows = WallpaperLibraryControlStyle.inspectorFacts(facts)
        sourceVideoFacts.isHidden = false
        sourceVideoFacts.addArrangedSubview(rows)
        rows.widthAnchor.constraint(equalTo: sourceVideoFacts.widthAnchor).isActive = true
    }

    private func buildContentSection() {
        let stack = verticalStack(spacing: 12)
        let metadataTags = Set([currentItem.workshopTypeText, currentItem.ageRatingText, currentItem.resolutionText].compactMap { $0?.lowercased() })
        let uniqueTags = currentItem.tags.filter { !metadataTags.contains($0.lowercased()) }
        if !uniqueTags.isEmpty {
            stack.addArrangedSubview(SteamWorkshopTagStripView(tags: uniqueTags))
            stack.addArrangedSubview(WallpaperLibraryControlStyle.sectionDivider())
        }
        var facts: [(String, String)] = []
        for (name, value) in [
            (String(localized: "Type"), currentItem.workshopTypeText), (String(localized: "Resolution"), currentItem.resolutionText),
            (String(localized: "File Size"), resolvedFileSizeText), (String(localized: "Published"), currentItem.postedText),            (String(localized: "Update Time"), currentItem.updatedText), (String(localized: "Categories"), currentItem.categoryText),
            (String(localized: "Browse"), currentItem.scoreText?.replacingOccurrences(of: String(localized: "Browse "), with: "")),
            (String(localized: "Subscribe"), currentItem.subscriptionsText), (String(localized: "Favorites"), currentItem.favoritesText),
            (String(localized: "Total Subscriptions"), currentItem.lifetimeSubscriptionsText), (String(localized: "Total Favorites"), currentItem.lifetimeFavoritesText),
            (String(localized: "Visibility"), currentItem.visibilityText), (String(localized: "Age Rating"), currentItem.ageRatingText),
            (String(localized: "Moderation Status"), currentItem.moderationText)
        ] {
            if let value, !value.isEmpty { facts.append((name, value)) }
        }
        if !currentItem.dependencyIDs.isEmpty { facts.append((String(localized: "Dependent Artworks"), currentItem.dependencyIDs.joined(separator: "、"))) }
        facts.append((String(localized: "Artwork ID"), currentItem.id))
        stack.addArrangedSubview(WallpaperLibraryControlStyle.inspectorFacts(facts))
        if videoTrackSource != nil { stack.addArrangedSubview(sourceVideoFacts) }
        stack.addArrangedSubview(WallpaperLibraryControlStyle.sectionDivider())
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
            stack.addArrangedSubview(errorNotice(message: String(localized: "Last download failed: \(latestDownloadFailure)")) { [weak self] in
                guard let self else { return }
                self.service.requestDownloadForBrowserItem(self.currentItem)
            })
        }

        if isRefreshingDetail {
            stack.addArrangedSubview(notice(icon: "arrow.triangle.2.circlepath", text: String(localized: "Completing details for this item…")))
        }

        if let record = latestDownloadRecord,
           case let .missing(itemID) = record.dependencyStatus {
            stack.addArrangedSubview(notice(
                icon: "shippingbox",
                text: record.isDependencyBackedWeb
                    ? String(localized: "This is a dependent Web preset shell. Its base dependency host \(itemID) is missing, so it can’t play right now.")
                    : String(localized: "The current WEB project declares the dependency \(itemID), which isn’t satisfied locally yet.")
            ))
        }

        if currentItem.hasAdultContent {
            stack.addArrangedSubview(notice(icon: "exclamationmark.triangle.fill", text: String(localized: "Steam has marked this item as adult content")))
        }

        guard !stack.arrangedSubviews.isEmpty else { return }
        contentStack.addArrangedSubview(stack)
    }

    /// UI projects the shared account-scoped state; only known state can be toggled.
    private func authorButton() -> NSView {
        let hasName = SteamWorkshopDetailRefreshSupport.hasAuthorName(currentItem)
        let author = footerButton(title: hasName ? currentItem.author : (isRefreshingDetail ? String(localized: "Fetching author…") : String(localized: "Artist Name Unavailable")), symbolName: "person.crop.circle", kind: .secondary, target: self, action: #selector(openAuthorWorkshop))
        author.toolTip = hasName ? String(localized: "View \(currentItem.author)’s Workshop") : String(localized: "View Author’s Workshop")
        author.isEnabled = SteamWorkshopService.resolvedAuthorWorkshopURL(for: currentItem) != nil
            || (!isRefreshingDetail && service.selectedDownloadInspectorItem?.id == currentItem.id)
        WallpaperLibraryControlStyle.authorPill(author)
        return author
    }

    private func subscriptionButton() -> InspectorFooterButton {
        let state = service.steamSubscriptions.state(for: currentItem.id)
        let title: String
        let symbol: String
        var enabled = true
        if !service.steamAuth.isOnline { title = String(localized: "Subscribe"); symbol = "bookmark" }
        else {
            switch state {
            case .known(let subscribed): title = subscribed ? String(localized: "Subscribed") : String(localized: "Subscribe"); symbol = subscribed ? "bookmark.fill" : "bookmark"
            case .unknown:
                title = String(localized: "Checking…"); symbol = "clock"; enabled = false
                let id = currentItem.id
                Task { @MainActor [weak self] in
                    guard let self, self.currentItem.id == id, self.service.steamSubscriptions.state(for: id) == .unknown else { return }
                    self.service.steamSubscriptions.refresh(id)
                }
            case .loading: title = String(localized: "Checking…"); symbol = "clock"; enabled = false
            case .writing, .reconciling: title = String(localized: "Verifying…"); symbol = "clock"; enabled = false
            case .unconfirmed: title = String(localized: "Unconfirmed"); symbol = "questionmark.circle"
            }
        }
        let subscription = footerButton(title: title, symbolName: symbol, kind: .secondary, target: self, action: #selector(toggleSubscriptionClicked(_:)))
        subscription.layer?.cornerRadius = 16
        subscription.isEnabled = enabled
        subscription.toolTip = nil
        return subscription
    }

    @objc private func toggleSubscriptionClicked(_ sender: NSView) {
        guard service.steamAuth.isOnline else {
            subscriptionHint = nil
            service.presentSteamLoginForUserAction(context: String(localized: "Subscribe"))
            return
        }
        let entry = SteamWorkshopItemMenu.subscription(item: currentItem, service: service)
        if service.steamSubscriptions.state(for: currentItem.id) == .known(true) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(entry)
            let hint = NSMenuItem(title: String(localized: "Your local files won’t be deleted and playback won’t be interrupted"), action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
            ToolbarMenu.popUp(anchor: sender, menu: menu)
        } else if entry.isEnabled, let action = entry.action {
            NSApp.sendAction(action, to: entry.target, from: entry)
        }
    }


    private func buildFooterActions() {
        let primary = primaryFooterButton()
        let webpage = footerIconButton(symbolName: "safari", help: String(localized: "Open Artwork in Browser"), action: #selector(openWorkshopDetail))
        let properties = footerIconButton(symbolName: "gearshape", help: String(localized: "Adjust Properties"), action: #selector(openProperties))
        properties.isEnabled = service.hasCompletedInstalledLibraryLoad
            && latestDownloadRecord?.status == .ready && latestDownloadRecord?.contentType != .unknown
        if !service.hasCompletedInstalledLibraryLoad { properties.toolTip = String(localized: "Loading local wallpaper") }
        else if latestDownloadRecord?.status != .ready { properties.toolTip = String(localized: "Properties are available after the download finishes") }
        footerView.configure(primary: primary, webpage: webpage, properties: properties)
    }


    func updateLibraryActions(_ actions: WallpaperInspectorActions?) {
        let changed = libraryActions?.state != actions?.state
        libraryActions = actions
        if changed { rebuild(preservingScrollPosition: true) }
    }

    private var isCurrentWallpaper: Bool {
        libraryActions?.state.isPlaying ?? (latestDownloadRecord.map { service.isRecordCurrentlyPlaying($0) } ?? false)
    }

    @objc private func stopCurrentWallpaper() {
        if let libraryActions {
            guard libraryActions.state.canPerformPrimary else { return }
            libraryActions.onPrimary(); return
        }
        guard isCurrentWallpaper, let record = latestDownloadRecord else { rebuild(); return }
        // Web currently shares the Video command handler and WallpaperEngine owner.
        let consumed = PlaybackCommandMultiplexer.shared.dispatch(.stop, to: record.contentType == .scene ? .scene : (record.contentType == .web ? .web : .video))
        if !consumed { subscriptionHint = String(localized: "Stopping playback didn’t finish. Try again.") }
        rebuild()
    }

    private func primaryFooterButton() -> InspectorFooterButton {
        if isCurrentWallpaper {
            let button = footerButton(title: String(localized: "Stop Playback"), symbolName: "stop.fill", kind: .secondary, target: self, action: #selector(stopCurrentWallpaper))
            button.isEnabled = libraryActions?.state.canPerformPrimary ?? true
            return button
        }

        // 下载中：保留原「下载壁纸」按钮，进度以从左到右的颜色填充表达
        //（无独立进度条、无取消按钮、无大小信息）。
        let snapshot = downloadProgressSnapshot
        let isSaving = snapshot?.phase == .saving
        if service.isDownloading(itemID: currentItem.id) {
            let button = footerButton(
                title: snapshot?.statusText(compact: true) ?? String(localized: "Downloading…"),
                symbolName: "arrow.down.circle.fill",
                kind: .primary,
                target: nil,
                action: nil
            )
            button.isEnabled = false
            button.setProgressFill(snapshot?.fraction ?? 0)
            primaryProgressButton = button
            return button
        }
        if service.isQueuedForDownload(itemID: currentItem.id) {
            let button = footerButton(
                title: isSaving ? String(localized: "Saving…") : String(localized: "Queued…"),
                symbolName: "hourglass.circle.fill",
                kind: .primary,
                target: nil,
                action: nil
            )
            button.isEnabled = false
            button.setProgressFill(isSaving ? 1 : 0)
            primaryProgressButton = button
            return button
        }

        let record = latestDownloadRecord.flatMap { $0.status == .ready ? $0 : nil } ?? downloadRecord
        if record?.status == .ready, !service.hasCompletedInstalledLibraryLoad {
            let button = footerButton(title: String(localized: "Loading local wallpaper…"), symbolName: "hourglass.circle", kind: .secondary,
                target: nil, action: nil)
            button.isEnabled = false
            return button
        }
        if let record,
           case let .missing(itemID) = record.dependencyStatus {
            if service.isDownloading(itemID: itemID) || service.isQueuedForDownload(itemID: itemID) {
                return footerButton(
                    title: String(localized: "Cancel Dependency Download"),
                    symbolName: "hourglass.circle.fill",
                    kind: .danger,
                    target: self,
                    action: #selector(cancelRequiredDependencyDownload)
                )
            }
            return footerButton(
                title: String(localized: "Download dependency #\(itemID)"),
                symbolName: "shippingbox.fill",
                kind: .primary,
                target: self,
                action: #selector(downloadRequiredDependency)
            )
        }

        if let record {
            if service.isLaunchPending(record.id) {
                let button = footerButton(
                    title: String(localized: "Switching…"),
                    symbolName: "hourglass.circle.fill",
                    kind: .primary,
                    target: self,
                    action: #selector(setAsWallpaper)
                )
                button.isEnabled = false
                return button
            }
            let button = footerButton(
                title: String(localized: "Set as Wallpaper"),
                symbolName: record.contentType == .scene ? "play.circle.fill" : "photo.fill",
                kind: .primary,
                target: self,
                action: #selector(setAsWallpaper)
            )
            button.isEnabled = libraryActions?.state.canPerformPrimary ?? true
            return button
        }

        let button = footerButton(
            title: latestDownloadFailure != nil ? String(localized: "Retry Download") : String(localized: "Download Wallpaper"),
            symbolName: latestDownloadFailure != nil ? "arrow.clockwise.circle.fill" : "arrow.down.circle.fill",
            kind: .primary,
            target: self,
            action: #selector(requestDownload)
        )
        button.isEnabled = service.canRequestDownload(id: currentItem.id)
        return button
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
        guard service.hasCompletedInstalledLibraryLoad else { return }
        guard let record = latestDownloadRecord ?? downloadRecord,
              case let .missing(itemID) = record.dependencyStatus else {
            return
        }
        service.cancelDownload(itemID: itemID)
    }

    @objc private func setAsWallpaper() {
        if let libraryActions {
            guard libraryActions.state.canPerformPrimary else { return }
            libraryActions.onPrimary(); return
        }
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

    func verticalStack(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    func spacer() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    func label(_ text: String, font: NSFont, color: NSColor, lines: Int) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.maximumNumberOfLines = lines
        label.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }





    func notice(icon: String, text: String) -> NSView {
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
        textStack.addArrangedSubview(label(String(localized: "Couldn’t Load Full Details"), font: .systemFont(ofSize: 12, weight: .semibold), color: .labelColor, lines: 1))
        textStack.addArrangedSubview(label(message, font: .systemFont(ofSize: 11), color: .secondaryLabelColor, lines: 2))
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(spacer())
        let button = ClosureButton(title: String(localized: "Retry"), actionHandler: retry)
        button.bezelStyle = .rounded
        row.addArrangedSubview(button)
        return row
    }

    private func footerButton(title: String, symbolName: String, kind: InspectorFooterButtonKind, target: AnyObject?, action: Selector?) -> InspectorFooterButton {
        InspectorFooterButton(title: title, image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title), kind: kind, target: target, action: action)
    }

    private func footerIconButton(symbolName: String, help: String, action: Selector) -> InspectorFooterButton {
        let button = InspectorFooterButton(title: "", image: NSImage(systemSymbolName: symbolName, accessibilityDescription: help), kind: .secondary, target: self, action: action)
        button.toolTip = help
        button.setAccessibilityLabel(help)
        return button
    }


    @objc func openProperties() {
        guard service.hasCompletedInstalledLibraryLoad else { return }
        guard let record = latestDownloadRecord, record.status == .ready else { return }
        switch record.contentType {
        case .unknown: return
        case .scene:
            SteamWorkshopSceneInspectionController.requestPropertyEditor(for: record)
        case .web:
            let editor = SteamWorkshopWebPropertyEditorView(record: record)
            if editor.presentsOnlyMessage, let message = editor.emptyStateMessage {
                SteamWorkshopPropertyPanelController.shared.showMessage(title: String(localized: "Web Property Adjustments"), subtitle: record.title, message: message)
            } else {
                SteamWorkshopPropertyPanelController.shared.show(title: String(localized: "Web Property Adjustments"), subtitle: record.title, content: editor)
            }
        case .video:
            let text = label(String(localized: "Video wallpapers have no author-adjustable properties. Volume, playback speed, and playback mode use the app’s playback settings."), font: .systemFont(ofSize: 13), color: .secondaryLabelColor, lines: 0)
            SteamWorkshopPropertyPanelController.shared.show(title: String(localized: "Video Properties"), subtitle: record.title, content: text)
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
