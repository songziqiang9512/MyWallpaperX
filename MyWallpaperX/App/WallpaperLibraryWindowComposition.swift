import AppKit
import Combine

/// The App layer joins the value-based Shell with the existing source owners.
/// It never mirrors selection into four services or owns playback transactions.
@MainActor final class WallpaperLibraryWindowComposition {
    let workspace: WallpaperLibraryWorkspace
    private let manager: WallpaperManager
    private let images: SILService
    private let steam: SteamWorkshopService
    private let pixabay: PixabayService
    private let sidebar = WallpaperLibrarySidebarController()
    private let detail = AppKitDetailHostViewController()
    private let directory = AppKitPlaylistDirectoryController()
    private let header = WallpaperPlaylistHeaderView()
    private let creationNotice = WallpaperPlaylistCreationNotice()
    private var subscriptions = Set<AnyCancellable>()
    private var windowVisibility: NSKeyValueObservation?
    private var windowObservers: [NSObjectProtocol] = []
    private var lastPage: WallpaperLibraryPage?
    private var lastDirectoryRevision: (UInt64, Int64, UUID)?
    private var allEntries: [WallpaperPlaylistDirectoryEntry] = []
    private var covers: [UUID: WallpaperPlaylistArtwork] = [:]
    private let sidebarDemand = UUID(), directoryDemand = UUID(), gridDemand = UUID()
    private let headerDemand = UUID()
    private var sourceSnapshot: WallpaperPlaybackSequence.Snapshot?
    private var cardState: WallpaperLibraryCardStateProjection?
    private var downloadedContent: [WallpaperReference: WallpaperContentItem] = [:]
    private var playlistNames: [WallpaperReference: [String]] = [:]
    private var lastRenderSignature: RenderSignature?
    private var picker: WallpaperPlaylistPickerController?
    private var backgroundStyle = WallpaperSettings.defaults.libraryBackgroundStyle
    var onGridLayoutChanged: (() -> Void)?
    var onNavigationContextChanged: (() -> Void)?
    private struct DirectoryReturnContext: Equatable {
        let playlistID: UUID
        let resetEpoch: UUID
        let admission = UUID()
    }
    private var directoryReturnContext: DirectoryReturnContext? {
        didSet { if oldValue != directoryReturnContext { onNavigationContextChanged?() } }
    }

    func makeDirectoryReturnAction() -> (() -> Void)? {
        guard let context = directoryReturnContext,
              workspace.presentation.page == .playlist(context.playlistID),
              workspace.relationships.resetEpoch == context.resetEpoch,
              workspace.relationships.playlists.contains(where: { $0.id == context.playlistID }) else { return nil }
        return { [weak self] in
            guard let self, self.directoryReturnContext == context,
                  self.makeDirectoryReturnAction() != nil, self.permitsInput else { return }
            self.navigate(to: .playlists)
        }
    }

    private func invalidateDirectoryReturnContext() {
        guard let context = directoryReturnContext else { return }
        if workspace.presentation.page != .playlist(context.playlistID)
            || workspace.relationships.resetEpoch != context.resetEpoch
            || !workspace.relationships.playlists.contains(where: { $0.id == context.playlistID }) {
            directoryReturnContext = nil
        }
    }

    private var permitsInput: Bool { WallpaperLibrarySheetPresentation.permitsInput(in: split.view.window) }


    var gridClipWidth: CGFloat {
        switch workspace.presentation.page {
        case .workshop: return steamBrowserContent.clipWidth
        case .pixabay: return pixabayBrowserContent.clipWidth
        case .wallhaven, .pixiv: return onlineImages.browser(for: workspace.presentation.page)?.clipWidth ?? 0
        case .playlists: return directory.clipWidth
        default: return grid.isViewLoaded ? grid.scrollView.contentView.bounds.width : 0
        }
    }

    private struct RenderSignature: Equatable {
        let page: WallpaperLibraryPage
        var query: WallpaperLibraryQueryState
        let items: [WallpaperContentItem]
        let selection: WallpaperLibrarySelectionState
        let catalogRevision: UInt64
        let projectionRevision: UInt64
        let relationshipsRevision: Int64
        let resetEpoch: UUID
        let sequenceReference: WallpaperReference?
        let sequenceTicket: PlaybackSwitchTicket?
        let ticket: PlaybackSwitchTicket?
        let pendingReference: WallpaperReference?
        let pendingSequenceTicket: PlaybackSwitchTicket?
        let pendingRuntimeTicket: PlaybackSwitchTicket?
        let canEdit: Bool
        let recoveryNotice: String?
        let operationError: String?
        let operationErrorEvent: UInt64
        let visible: Bool

        func hasSameCardInputs(as other: Self) -> Bool {
            var query = self.query, otherQuery = other.query
            query.preferredColumns = 5; otherQuery.preferredColumns = 5
            query.scrollAnchor = nil; otherQuery.scrollAnchor = nil
            query.scrollOffset = nil; otherQuery.scrollOffset = nil
            query.scrollAtTop = nil; otherQuery.scrollAtTop = nil
            return page == other.page && catalogRevision == other.catalogRevision && projectionRevision == other.projectionRevision
                && relationshipsRevision == other.relationshipsRevision && resetEpoch == other.resetEpoch
                && sequenceReference == other.sequenceReference && sequenceTicket == other.sequenceTicket && ticket == other.ticket
                && pendingReference == other.pendingReference && pendingSequenceTicket == other.pendingSequenceTicket
                && pendingRuntimeTicket == other.pendingRuntimeTicket
                && query == otherQuery && items == other.items
        }
    }

    lazy var split: AppKitMainSplitViewController = {
        let chrome = self.chrome
        let controller = AppKitMainSplitViewController(sidebar: sidebar, content: chrome, sidebarTintHost: sidebar.backgroundTintHost,
            permitsNoticeInteraction: { [weak chrome] in chrome?.permitsNoticeInteraction(at: $0) ?? false },
            onNoticeOcclusionChange: { [weak chrome] in chrome?.setNoticeTrailingOcclusion($0) },
            onListTintChange: { SettingsWindowController.shared.updateMainWindowTint($0, animated: $1) })
        return controller
    }()
    lazy var commands = WallpaperLibraryCommands(workspace: workspace, manager: manager, images: images,
        steam: steam, pixabay: pixabay, hostWindow: { [weak self] in self?.split.view.window })
    lazy var inspector = WallpaperLibraryInspectorCoordinator(workspace: workspace, manager: manager, images: images,
        steam: steam, pixabay: pixabay,
        makePrimaryAction: { [weak self] content in
            guard let self else { return nil }
            return self.commands.makePrimaryAction(for: content)
        }, makeFavoriteAction: { [weak self] in self?.makeCardFavoriteAction($0) },
        canOrganize: { [weak self] in self?.commands.canOrganize == true },
        availabilityChanges: commands.availabilityChanges,
        onChoosePlaylist: { [weak self] ref, anchor in self?.commands.choosePlaylist([ref], anchor: anchor) })
    private lazy var adapter: WallpaperLibraryCellAdapter = WallpaperLibraryCellAdapter(manager: manager, images: images, steam: steam, pixabay: pixabay,
        isPlaying: { [weak self] in self?.cardState?.isPlaying($0) ?? false },
        isSwitching: { [weak self] in self?.cardState?.isSwitching($0) ?? false },
        makePrimaryAction: { [weak self] in self?.makeCardPrimaryAction($0) },
        onInspect: { [weak self] in self?.inspector.inspect(content: $0) })
    private lazy var grid: WallpaperLibraryGridController = WallpaperLibraryGridController { [weak self] collection, path, content, state in
        guard let self else { return NSCollectionViewItem() }
        return self.adapter.makeCell(collection: collection, indexPath: path, content: content, state: state)
    }
    private lazy var chrome = WallpaperLibraryPageChrome(content: detail)
    private lazy var steamBrowserContent: AppKitSteamWorkshopBrowserView = {
        let view = AppKitSteamWorkshopBrowserView()
        view.opensDetailsOnSingleClick = { [weak self] in self?.manager.settings.libraryCardClickAction == .openDetails }
        view.makeOrganization = { [weak self] in self?.remoteOrganization(for: $0) }
        view.makeInspectorActions = { [weak self] in self?.remoteInspectorActions(for: $0) }
        view.makeOrganizationMenu = { [weak self] in self?.remoteOrganizationMenu(for: $0) }
        return view
    }()
    private lazy var steamBrowser = WallpaperLibraryViewController(steamBrowserContent)
    private lazy var pixabayBrowserContent: PixabayBrowserView = {
        let view = PixabayBrowserView()
        view.makeOrganization = { [weak self] in self?.pixabayOrganization(for: $0) }
        view.onInspect = { [weak self] in self?.inspector.inspectPixabayItem($0) }
        view.opensDetailsOnSingleClick = { [weak self] in self?.manager.settings.libraryCardClickAction == .openDetails }
        view.onSelectionChange = { [weak self] in self?.inspector.syncPixabaySelection($0) }
        return view
    }()
    private lazy var pixabayBrowser = WallpaperLibraryViewController(pixabayBrowserContent)
    lazy var onlineImages: WallpaperLibraryOnlineImages = {
        let value = WallpaperLibraryOnlineImages(workspace: workspace, commands: commands, inspector: inspector)
        value.opensDetailsOnSingleClick = { [weak self] in self?.manager.settings.libraryCardClickAction == .openDetails }
        value.isPlaying = { [weak self] in self?.cardState?.isPlaying($0) == true }
        value.isSwitching = { [weak self] in self?.cardState?.isSwitching($0) == true }
        return value
    }()
    private lazy var artwork = WallpaperLibraryArtworkProvider(manager: manager, images: images, steam: steam, pixabay: pixabay)

    init(workspace: WallpaperLibraryWorkspace, manager: WallpaperManager, images: SILService,
         steam: SteamWorkshopService, pixabay: PixabayService) {
        self.workspace = workspace; self.manager = manager; self.images = images; self.steam = steam; self.pixabay = pixabay
    }

    var canDeleteSelectedPlaylist: Bool {
        permitsInput && workspace.presentation.page == .playlists && commands.canOrganize && directory.canDeleteSelectedPlaylist
    }

    func deleteSelectedPlaylist() {
        guard canDeleteSelectedPlaylist else { return }
        directory.deleteSelectedPlaylist()
    }

    func start() {
        split.loadViewIfNeeded()
        configureActions()
        manager.$settings.map(\.libraryBackgroundStyle).removeDuplicates()
            .sink { [weak self] style in self?.applyBackgroundStyle(style) }
            .store(in: &subscriptions)
        if let window = split.view.window {
            windowVisibility = window.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.render() }
            }
            for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.render() }
                })
            }
        }
        workspace.presentation.$state.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.render() }
            .store(in: &subscriptions)
        workspace.catalog.visibleLocalFactsRefreshed.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.adapter.repairVisiblePreviews()
        }.store(in: &subscriptions)
        workspace.playbackChanges.sink { [weak self] in self?.render() }
            .store(in: &subscriptions)
        commands.availabilityChanges.sink { [weak self] in self?.render() }.store(in: &subscriptions)
        steam.$navigationVersion.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.workspace.presentation.page == .workshop else { return }
                self.steamBrowserContent.refreshLibraryActions()
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .appKitSelectItemRequested).receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.handleNavigation($0) }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .appOpenSettingsRequested).receive(on: DispatchQueue.main)
            .sink { _ in SettingsWindowController.shared.showWindow() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .wallpaperManagerDidResetToFreshInstallState).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sidebar.resetSidebarState() }.store(in: &subscriptions)
        render()
    }

    deinit { windowObservers.forEach(NotificationCenter.default.removeObserver) }

    private var isVisible: Bool { split.view.window?.isVisible == true && split.view.window?.isMiniaturized == false }

    private func configureActions() {
        let permitsPullCountInput = { [weak self] in self?.permitsInput == true }
        grid.scrollView.permitsPullCountInput = permitsPullCountInput
        directory.permitsPullCountInput = permitsPullCountInput
        sidebar.makeRecentMenu = { [weak self] in
            guard let self, self.permitsInput else { return nil }
            return self.commands.makeRecentMenu(for: .recent)
        }
        commands.playlists?.coverPreview = { [weak self] id in
            guard let cover = self?.covers[id], !cover.isCustom else { return nil }
            return cover.image
        }
        commands.playlists?.permitsEditing = { [weak self] in self?.commands.canOrganize == true }
        commands.playlists?.availabilityChanges = commands.availabilityChanges
            .merge(with: workspace.presentation.$state.map { _ in () })
            .eraseToAnyPublisher()
        commands.playlists?.onWillPresent = { [weak self] in self?.inspector.closePreview() }
        commands.playlists?.onOpen = { [weak self] id in
            guard let self else { return }
            self.openPlaylist(id, fromDirectory: self.workspace.presentation.page == .playlists)
        }
        sidebar.onNavigate = { [weak self] page in
            guard let self, self.permitsInput else { return }; self.navigate(to: page)
        }
        sidebar.onPlaylistAction = { [weak self] in self?.performPlaylistAction($0) }
        sidebar.onAddReferences = { [weak self] refs, id in self?.addReferences(refs, to: id) ?? false }
        directory.onScrollAnchor = { [weak self] id, offset, atTop in
            self?.workspace.presentation.setDirectoryScrollAnchor(id, offset: offset, atTop: atTop)
        }
        grid.onClipWidthChange = { [weak self] _ in self?.onGridLayoutChanged?() }
        directory.onClipWidthChange = { [weak self] _ in self?.onGridLayoutChanged?() }
        steamBrowserContent.onClipWidthChange = { [weak self] _ in self?.onGridLayoutChanged?() }
        pixabayBrowserContent.onClipWidthChange = { [weak self] _ in self?.onGridLayoutChanged?() }
        sidebar.onReorder = { [weak self] ids, completion in
            self?.reorderPlaylists(ids, completion: completion) ?? completion(.failure(UserCollectionsError.staleResetEpoch))
        }
        directory.onAction = { [weak self] in self?.performPlaylistAction($0, fromDirectory: true) }
        directory.onReorder = { [weak self] ids, completion in
            self?.reorderPlaylists(ids, completion: completion) ?? completion(.failure(UserCollectionsError.staleResetEpoch))
        }
        sidebar.onCoverDemand = { [weak self] ids in guard let self else { return }; self.artwork.setDemand(sourceToken: self.sidebarDemand, playlistIDs: ids) }
        directory.onCoverDemand = { [weak self] ids in guard let self else { return }; self.artwork.setDemand(sourceToken: self.directoryDemand, playlistIDs: ids) }
        artwork.loadCustomCover = { [weak workspace] id, completion in
            guard let collections = workspace?.collections else { completion(nil); return {} }
            let epoch = collections.snapshot.resetEpoch
            let task = Task { @MainActor in
                let asset = try? await collections.playlistCoverAsset(id: id, expectedEpoch: epoch)
                guard !Task.isCancelled, collections.snapshot.resetEpoch == epoch else { return }
                completion(asset.flatMap { NSImage(data: $0.imageData) })
            }
            return { task.cancel() }
        }
        artwork.onCoversChanged = { [weak self] in self?.covers = $0; self?.renderCovers() }
        commands.onInspect = { [weak self] in self?.inspector.inspect(content: $0) }
        commands.onPreview = { [weak self] in _ = self?.inspector.preview(content: $0) }
        commands.onCloseInspector = { [weak self] in self?.inspector.closeInspector(); self?.inspector.closePreview() }
        commands.onAddWallpapers = { [weak self] in self?.showPicker(for: $0) }
        commands.playlists?.onCreatedFromMembers = { [weak self] id in self?.showCreatedPlaylistNotice(id) }
        grid.updateCell = { [weak self] in self?.adapter.updateCell($0, content: $1, state: $2) }
        grid.needsCellReplacement = { [weak self] in self?.adapter.needsCellReplacement($0, content: $1) ?? false }
        grid.setCellVisible = { [weak self] in self?.adapter.setVisible($0, $1) }
        grid.onViewport = { [weak self] visible, prefetch in
            guard let self else { return }
            self.adapter.updateViewport(visible: visible, prefetch: prefetch)
            self.workspace.catalog.setVisibleReferences(Set(visible.map(\.providerReference)), sourceToken: self.gridDemand)
        }
        grid.onSelection = { [weak self] refs, focus in
            guard let self, self.permitsInput else { return nil }
            let model = self.workspace.presentation
            guard model.setSelection(refs, focused: focus, isSelecting: model.selectionState.isSelecting) else { return nil }
            return model.selectionState.sessionID
        }
        grid.onSelectAll = { [weak self] in
            guard let self, self.permitsInput else { return }
            self.commands.selectAll()
        }
        grid.opensDetailsOnSingleClick = { [weak self] in self?.manager.settings.libraryCardClickAction == .openDetails }
        grid.onInspect = { [weak self] content in
            guard let self, self.permitsInput else { return }
            self.inspector.inspect(content: content)
        }
        grid.onPrimaryAction = { [weak self] in self?.makeCardPrimaryAction($0)?() }
        grid.onQuickLook = { [weak self] in _ = self?.inspector.preview(content: $0) }
        grid.onDelete = { [weak self] in self?.commands.remove($0) }
        grid.onEscape = { [weak self] in self?.escape() }
        grid.onScrollAnchor = { [weak self] page, reference, offset, atTop in
            self?.workspace.presentation.setScrollAnchor(reference, offset: offset, atTop: atTop, page: page)
        }
        grid.menuProvider = { [weak self] items in
            guard let self, self.permitsInput, let menu = self.commands.contextMenu(for: items) else { return nil }
            menu.requireAppActionPermission { [weak self] in self?.permitsInput == true }
            return menu
        }
        inspector.isSwitching = { [weak self] in self?.cardState?.isSwitching($0) == true }
        inspector.onMoveSelection = { [weak self] key in
            guard let self, self.permitsInput, let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: self.split.view.window?.windowNumber ?? 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: key) else { return }
            if let browser = self.onlineImages.browser(for: self.workspace.presentation.page) { browser.moveSelection(with: event) }
            else { self.grid.collection.keyDown(with: event) }
        }
        onlineImages.onNavigate = { [weak self] page in
            guard let self, self.permitsInput else { return }
            if case .playlist(let id) = page, !self.workspace.relationships.playlists.contains(where: { $0.id == id }) {
                self.navigate(to: .playlists)
            } else { self.navigate(to: page) }
        }
        inspector.onOnlineImageAuthor = { [weak self] id in
            guard let self, self.permitsInput else { return }
            self.onlineImages.openAuthor(id, from: self.workspace.presentation.page)
        }
        split.onRestoreContentFocus = { [weak self] in self?.restoreContentFocus() }
    }

    func navigate(to page: WallpaperLibraryPage) {
        directoryReturnContext = nil
        navigatePage(to: page)
    }

    private func navigatePage(to page: WallpaperLibraryPage) {
        // The source retains its author/personal context and scroll receipt.
        // Returning to discovery is the explicit toolbar Back action.
        if page == workspace.presentation.page, !page.isRemoteBrowse, page != .playlists {
            grid.scrollToTop()
            return
        }
        _ = workspace.presentation.switchPage(page)
    }

    private func openPlaylist(_ id: UUID, fromDirectory: Bool) {
        guard workspace.relationships.playlists.contains(where: { $0.id == id }) else { return }
        directoryReturnContext = fromDirectory && workspace.presentation.page == .playlists
            ? DirectoryReturnContext(playlistID: id, resetEpoch: workspace.relationships.resetEpoch) : nil
        navigatePage(to: .playlist(id))
    }

    private func performPlaylistAction(_ action: PlaylistOrganizationAction, fromDirectory: Bool = false) {
        guard permitsInput else { return }
        if case .open(let id) = action { openPlaylist(id, fromDirectory: fromDirectory); return }
        guard commands.canOrganize else { return }
        commands.playlists?.handle(action)
    }

    private func reorderPlaylists(_ ids: [UUID], completion: @escaping (Result<Int64, Error>) -> Void) {
        guard permitsInput, commands.canOrganize, let actions = commands.playlists else {
            completion(.failure(UserCollectionsError.staleResetEpoch)); return
        }
        actions.reorder(ids, completion: completion)
    }

    private func handleNavigation(_ note: Notification) {
        let page: WallpaperLibraryPage
        switch note.userInfo?["selectedItem"] as? String {
        case "steamWorkshop": page = .workshop
        case "steamDownloads", "onlineDownloads": page = .downloads
        case "onlineLibrary": page = .pixabay
        case "wallhaven": page = .wallhaven
        case "pixiv": page = .pixiv
        case "staticImageLibrary": page = .images
        default: return
        }
        navigate(to: page)
    }

    private func render() {
        let model = workspace.presentation, state = model.state
        let relationships = workspace.relationships, catalog = workspace.catalog.catalog
        var query = state.query
        query.scrollAnchor = nil
        query.scrollOffset = nil
        query.scrollAtTop = nil
        let committed = manager.libraryPlaybackSequence.committed
        let pending = manager.libraryPlaybackSequence.pending
        let signature = RenderSignature(page: state.page, query: query, items: state.queryResult.items, selection: state.selectionState,
            catalogRevision: catalog.revision, projectionRevision: workspace.projectionRevision,
            relationshipsRevision: relationships.revision, resetEpoch: relationships.resetEpoch,
            sequenceReference: committed?.reference, sequenceTicket: committed?.ticket,
            ticket: manager.playbackSwitch.committed?.ticket,
            pendingReference: pending?.proposal.entry.reference, pendingSequenceTicket: pending?.ticket,
            pendingRuntimeTicket: manager.playbackSwitch.pending?.selection.ticket, canEdit: commands.canOrganize,
            recoveryNotice: workspace.recoveryMessage, operationError: state.lastError, operationErrorEvent: state.lastErrorEvent, visible: isVisible)
        // A scroll anchor is a receipt from the already-scrolled native view.
        // Its echo persists the anchor without rebuilding every visible card.
        guard signature != lastRenderSignature else { return }
        let previousSignature = lastRenderSignature
        let didReset = lastRenderSignature.map { $0.resetEpoch != relationships.resetEpoch } ?? false
        if didReset { grid.invalidateScrollReceipt(); directory.invalidateScrollReceipt() }
        invalidateDirectoryReturnContext()
        if state.page != lastPage || didReset { creationNotice.dismiss() }
        lastRenderSignature = signature
        configureFileDrop(for: state.page)
        let entering = state.page != lastPage || didReset
        if entering {
            inspector.closeInspector(); inspector.closePreview()
            NotificationCenter.default.post(name: .inspectorHostCloseRequested, object: nil)
            lastPage = state.page
            publishRemoteMode(state.page)
        }
        updateDirectoryFacts()
        let headerIDs: Set<UUID>
        if case .playlist(let id) = state.page, isVisible { headerIDs = [id] } else { headerIDs = [] }
        artwork.setDemand(sourceToken: headerDemand, playlistIDs: headerIDs)
        renderCovers()
        updatePageChrome(state)
        if state.page == .playlists {
            detail.present(directory)
            if entering {
                directory.restoreScrollAnchor(state.directoryScrollAnchor, offset: state.directoryScrollOffset,
                    atTop: state.directoryScrollAtTop)
            }
            artwork.updateCurrentDirectory(firstPlaylistID: isVisible && backgroundStyle == .listCoverTint ? state.directoryEntries.first?.id : nil)
            bindTint(artwork.currentListTintSource)
            return
        }
        prepareCardState(state, catalog: catalog, relationships: relationships, signature: signature, previousSignature: previousSignature)
        if state.page.isRemoteBrowse {
            if let browser = onlineImages.browser(for: state.page) {
                onlineImages.window = split.view.window
                onlineImages.onClipWidthChange = { [weak self] in self?.onGridLayoutChanged?() }
                browser.preferredColumns = state.query.preferredColumns
                detail.present(browser)
                onlineImages.setVisible(isVisible, page: state.page)
                browser.refreshOrganization()
                bindTint(browser.listThumbnailTintSource)
                return
            }
            if state.page == .pixabay { pixabayBrowserContent.preferredColumns = state.query.preferredColumns }
            else { steamBrowserContent.preferredColumns = state.query.preferredColumns }
            let browser = state.page == .pixabay ? pixabayBrowser : steamBrowser
            detail.present(browser)
            if state.page == .pixabay { pixabayBrowserContent.refreshOrganization() }
            else { steamBrowserContent.refreshLibraryActions() }
            bindTint(ListThumbnailTintSource.mounted(in: browser.view))
            return
        }
        let hasHeader: Bool
        if case .playlist = state.page { hasHeader = true } else { hasHeader = false }
        grid.update(page: state.page, items: state.queryResult.items, selection: state.selectionState,
            preferredColumns: state.query.preferredColumns, permitsDragging: commands.canOrganize,
            scrollAnchor: state.query.scrollAnchor, scrollOffset: state.query.scrollOffset, scrollAtTop: state.query.scrollAtTop,
            resetScroll: didReset, header: hasHeader ? (header, header.preferredHeight(forWidth:)) : nil)
        detail.present(grid)
        let selected = state.selectionState.references.count == 1 ? state.queryResult.items.first { state.selectionState.references.contains($0.reference) } : nil
        inspector.syncSelection(content: state.selectionState.isSelecting ? nil : selected)
        artwork.updateCurrentList(first: isVisible ? state.queryResult.items.first : nil)
        bindTint(artwork.currentListTintSource)
    }

    private func bindTint(_ source: ListThumbnailTintSource?) {
        split.bindTint(source)
    }

    private func applyBackgroundStyle(_ style: LibraryBackgroundStyle) {
        backgroundStyle = style
        let usesTint = style == .listCoverTint
        sidebar.setUsesThumbnailTint(usesTint)
        split.setUsesThumbnailTint(usesTint)
        if workspace.presentation.page == .playlists {
            artwork.updateCurrentDirectory(firstPlaylistID: usesTint && isVisible ? workspace.presentation.state.directoryEntries.first?.id : nil)
        }
    }

    private func configureFileDrop(for page: WallpaperLibraryPage) {
        grid.onImportFiles = nil
        switch page {
        case .videos, .images, .playlist: break
        default: return
        }
        guard commands.canOrganize else { return }
        let epoch = workspace.relationships.resetEpoch
        grid.onImportFiles = { [weak self] urls in
            guard let self, self.permitsInput, self.workspace.presentation.page == page,
                  self.workspace.relationships.resetEpoch == epoch, self.commands.canImport else { return false }
            self.commands.importFiles(urls)
            return true
        }
    }

    private func prepareCardState(_ state: WallpaperLibraryPresentationState, catalog: WallpaperLibraryCatalog,
                                  relationships: UserCollectionsSnapshot, signature: RenderSignature, previousSignature: RenderSignature?) {
        if cardState != nil, let previousSignature, signature.hasSameCardInputs(as: previousSignature) { return }
        do {
            var seen = Set<WallpaperReference>()
            let references = (state.queryResult.items.map(\.reference) + catalog.downloads.map(\.reference)).filter { seen.insert($0).inserted }
            let resolved = try WallpaperLibraryQuery.resolve(references, catalog: catalog, relationships: relationships)
            let byReference = Dictionary(zip(references, resolved), uniquingKeysWith: { first, _ in first })
            downloadedContent = Dictionary(catalog.downloads.compactMap { item in
                byReference[item.reference].map { (item.providerReference, $0) }
            }, uniquingKeysWith: { first, _ in first })
            let committed = manager.libraryPlaybackSequence.committed
            let pending = manager.libraryPlaybackSequence.pending
            let projection = try WallpaperLibraryCardStateProjection(items: state.queryResult.items + resolved, relationships: relationships,
                committedReference: committed?.reference, sequenceTicket: committed?.ticket, runtimeTicket: manager.playbackSwitch.committed?.ticket,
                additionalReferences: relationships.members.map(\.reference),
                pendingReference: pending?.proposal.entry.reference, pendingSequenceTicket: pending?.ticket,
                pendingRuntimeTicket: manager.playbackSwitch.pending?.selection.ticket)
            cardState = projection
            let names = Dictionary(relationships.playlists.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            playlistNames = [:]
            for member in relationships.members {
                if let name = names[member.playlistID] { playlistNames[projection.canonical(member.reference), default: []].append(name) }
            }
            let sourceItems = state.queryResult.items.compactMap { byReference[$0.reference] }
            sourceSnapshot = try state.page.isRemoteBrowse ? nil : sourceItems.first.map {
                try workspace.capturePlaybackSnapshot(for: $0.reference,
                    resolvedProjection: (catalog.revision, relationships.revision, relationships.resetEpoch, sourceItems))
            }
        } catch {
            cardState = nil; sourceSnapshot = nil; downloadedContent = [:]; playlistNames = [:]
            workspace.presentation.report(error)
        }
    }

    private func makeCardPrimaryAction(_ content: WallpaperContentItem) -> (() -> Void)? {
        guard let cardState, !cardState.isSwitching(content.reference) else { return nil }
        return commands.makePrimaryAction(for: content, from: sourceSnapshot,
            renderedPlaying: cardState.isPlaying(content.reference), renderedTicket: cardState.committedTicket)
    }

    private func makeCardFavoriteAction(_ content: WallpaperContentItem) -> (() -> Void)? {
        guard let cardState else { return nil }
        let action = cardState.favoriteActionState(for: content, canEdit: commands.canOrganize)
        guard action.canExecute else { return nil }
        let page = workspace.presentation.page, epoch = workspace.relationships.resetEpoch
        let sessionID = workspace.presentation.selectionState.sessionID
        return { [weak self] in
            guard let self, self.permitsInput, self.workspace.presentation.page == page,
                  self.workspace.relationships.resetEpoch == epoch,
                  self.workspace.presentation.selectionState.sessionID == sessionID else { return }
            self.commands.toggleFavorite([content.reference], expectingRemoval: action.isRemoving)
        }
    }

    private func pixabayOrganization(for item: PixabayVideoItem) -> WallpaperInspectorActions? {
        guard workspace.presentation.page == .pixabay else { return nil }
        let provider = WallpaperReference(provider: .pixabay, sourceID: String(item.id))
        guard let content = downloadedContent[provider], content.publishedAvailability.isPublishedLocally, let cardState else { return nil }
        let page = workspace.presentation.page, epoch = workspace.relationships.resetEpoch
        let sessionID = workspace.presentation.selectionState.sessionID
        let primary = remotePrimaryAction(content, page: page, epoch: epoch, sessionID: sessionID)
        let favorite = makeCardFavoriteAction(content)
        return .init(state: .init(isPlaying: cardState.isPlaying(content.reference),
            isSwitching: cardState.isSwitching(content.reference), isFavorite: cardState.isFavorite(content.reference),
            canPerformPrimary: primary != nil, canFavorite: favorite != nil,
            canOrganize: commands.canOrganize && content.capabilities.contains(.organize),
            playlistNames: playlistNames[cardState.canonical(content.reference)] ?? []),
            onPrimary: { primary?() }, onToggleFavorite: { favorite?() }, onChoosePlaylist: { [weak self] anchor in
                guard let self, self.acceptsRemoteAction(page: page, epoch: epoch, sessionID: sessionID) else { return }
                self.commands.choosePlaylist([content.reference], anchor: anchor)
            }, makePlaylistMenu: { [weak self] permitsAction in
                guard let self, self.acceptsRemoteAction(page: page, epoch: epoch, sessionID: sessionID) else { return nil }
                return self.commands.makePlaylistMenu([content.reference], permitsAction: permitsAction)
            }, onRestoreLibrary: commands.makeRestoreLibraryAction(for: content))
    }

    private func remoteOrganization(for item: SteamWorkshopBrowserItem) -> AppKitSteamWorkshopBrowserItem.OrganizationPresentation? {
        guard workspace.presentation.page == .workshop else { return nil }
        let provider = WallpaperReference(provider: .steamWorkshop, sourceID: item.id)
        guard let content = downloadedContent[provider], content.publishedAvailability.isPublishedLocally, let cardState else { return nil }
        let page = workspace.presentation.page, epoch = workspace.relationships.resetEpoch
        let sessionID = workspace.presentation.selectionState.sessionID
        let navigationVersion = steam.navigationVersion
        let primary = remotePrimaryAction(content, page: page, epoch: epoch, sessionID: sessionID, navigationVersion: navigationVersion)
        let favorite = makeCardFavoriteAction(content)
        return .init(isFavorite: cardState.isFavorite(content.reference),
            canFavorite: favorite != nil,
            isPlaying: cardState.isPlaying(content.reference), isSwitching: cardState.isSwitching(content.reference), canPlay: primary != nil,
            canDownload: !content.capabilities.intersection([.download, .retryDownload, .retryUpdate]).isEmpty,
            canCancel: content.capabilities.contains(.cancelDownload), onFavorite: { [weak self] in
                guard let self, self.acceptsRemoteAction(page: page, epoch: epoch, sessionID: sessionID,
                    navigationVersion: navigationVersion) else { return }
                favorite?()
            }, onPrimary: primary)
    }

    private func remoteOrganizationMenu(for item: SteamWorkshopBrowserItem) -> NSMenu? {
        let provider = WallpaperReference(provider: .steamWorkshop, sourceID: item.id)
        guard let content = downloadedContent[provider], content.publishedAvailability.isPublishedLocally,
              let organization = remoteOrganization(for: item) else { return nil }
        let page = workspace.presentation.page, epoch = workspace.relationships.resetEpoch
        let sessionID = workspace.presentation.selectionState.sessionID
        let navigationVersion = steam.navigationVersion
        let menu = NSMenu()
        menu.autoenablesItems = false
        let favorite = ActionMenuItem(title: organization.isFavorite ? "取消特别喜爱" : "特别喜爱", symbol: "heart") {
            organization.onFavorite?()
        }
        favorite.isEnabled = organization.canFavorite
        menu.addItem(favorite)
        let playlist = NSMenuItem(title: "添加到列表", action: nil, keyEquivalent: "")
        playlist.image = NSImage(systemSymbolName: "text.badge.plus", accessibilityDescription: nil)
        playlist.submenu = commands.makePlaylistMenu([content.reference], permitsAction: { [weak self] in
            self?.acceptsRemoteAction(page: page, epoch: epoch, sessionID: sessionID, navigationVersion: navigationVersion) == true
        })
        playlist.isEnabled = commands.canOrganize && content.capabilities.contains(.organize) && playlist.submenu != nil
        menu.addItem(playlist)
        if let restore = commands.makeRestoreLibraryAction(for: content) {
            menu.addItem(ActionMenuItem(title: "重新加入我的下载", symbol: "arrow.down.to.line") { [weak self] in
                guard let self, self.acceptsRemoteAction(page: page, epoch: epoch, sessionID: sessionID,
                    navigationVersion: navigationVersion) else { return }
                restore()
            })
        }
        return menu
    }

    private var selectedBrowserReference: WallpaperReference? {
        switch workspace.presentation.page {
        case .workshop: return steamBrowserContent.selectedItem.map { .init(provider: .steamWorkshop, sourceID: $0.id) }
        case .pixabay: return pixabayBrowserContent.selectedItem.map { .init(provider: .pixabay, sourceID: String($0.id)) }
        case .wallhaven, .pixiv: return onlineImages.selectedContent?.reference
        default: return nil
        }
    }
    private func bindSelectedBrowserAction(_ action: @escaping () -> Void) -> (() -> Void)? {
        guard let reference = selectedBrowserReference else { return nil }
        let page = workspace.presentation.page, epoch = workspace.relationships.resetEpoch, navigation = steam.navigationVersion
        return { [weak self] in
            guard let self, self.isVisible, self.permitsInput, self.workspace.presentation.page == page,
                  self.workspace.relationships.resetEpoch == epoch, self.selectedBrowserReference == reference,
                  page != .workshop || self.steam.navigationVersion == navigation else { return }
            action()
        }
    }
    func selectedBrowserPrimaryAction() -> (title: String, action: () -> Void)? {
        let title: String, action: () -> Void
        switch workspace.presentation.page {
        case .workshop:
            guard let primary = steamBrowserContent.selectedPrimaryAction, let reference = selectedBrowserReference else { return nil }
            title = workspace.isPlaying(reference) ? "停止播放" : steam.downloadProgressStore.snapshot(for: reference.sourceID)?.phase == .failed
                ? "重试下载" : downloadedContent[reference]?.publishedAvailability.isPublishedLocally == true ? "设为壁纸" : "下载壁纸"
            action = primary
        case .pixabay:
            guard let primary = pixabayBrowserContent.selectedPrimaryAction, let reference = selectedBrowserReference else { return nil }
            title = workspace.isPlaying(reference) ? "停止播放" : downloadedContent[reference]?.publishedAvailability.isPublishedLocally == true ? "设为壁纸" : "下载视频"
            action = primary
        default:
            guard let primary = onlineImages.selectedPrimaryAction() else { return nil }
            title = primary.title; action = primary.action
        }
        return bindSelectedBrowserAction(action).map { (title, $0) }
    }
    func selectedBrowserInfoAction() -> (() -> Void)? {
        switch workspace.presentation.page {
        case .workshop: return bindSelectedBrowserAction { [weak self] in _ = self?.steamBrowserContent.inspectSelectedItem() }
        case .pixabay: return bindSelectedBrowserAction { [weak self] in _ = self?.pixabayBrowserContent.inspectSelectedItem() }
        case .wallhaven, .pixiv: return bindSelectedBrowserAction { [weak self] in self?.onlineImages.inspectSelected() }
        default: return nil
        }
    }
    func selectedBrowserPreviewAction() -> (() -> Void)? {
        guard onlineImages.selectedContent?.capabilities.contains(.quickLook) == true else { return nil }
        return bindSelectedBrowserAction { [weak self] in self?.onlineImages.previewSelected() }
    }
    func selectedBrowserOrganizationActions() -> WallpaperInspectorActions? {
        if workspace.presentation.page == .wallhaven || workspace.presentation.page == .pixiv {
            return onlineImages.selectedOrganizationActions()
        }
        let actions: WallpaperInspectorActions?
        switch workspace.presentation.page {
        case .workshop: actions = steamBrowserContent.selectedItem.flatMap { remoteInspectorActions(for: $0, requiresInspectedItem: false) }
        case .pixabay: actions = pixabayBrowserContent.selectedItem.flatMap { pixabayOrganization(for: $0) }
        default: actions = nil
        }
        guard let actions, let reference = selectedBrowserReference else { return nil }
        // Source actions already own page/epoch/ticket checks. Only the grid
        // identity is added here; an Inspector's selection is a different slot.
        return .init(state: actions.state, onPrimary: actions.onPrimary, onToggleFavorite: { [weak self] in
            guard self?.selectedBrowserReference == reference else { return }
            actions.onToggleFavorite()
        }, onChoosePlaylist: { [weak self] anchor in
            guard self?.selectedBrowserReference == reference else { return }
            actions.onChoosePlaylist(anchor)
        })
    }

    private func acceptsRemoteAction(page: WallpaperLibraryPage, epoch: UUID, sessionID: UUID, selectedID: String? = nil, navigationVersion: Int? = nil) -> Bool {
        guard permitsInput, workspace.presentation.page == page, page.isRemoteBrowse,
              workspace.relationships.resetEpoch == epoch, workspace.presentation.selectionState.sessionID == sessionID else { return false }
        if let navigationVersion, steam.navigationVersion != navigationVersion { return false }
        return selectedID.map { steam.selectedBrowserItem?.id.utf8.elementsEqual($0.utf8) == true } ?? true
    }

    private func remotePrimaryAction(_ content: WallpaperContentItem, page: WallpaperLibraryPage, epoch: UUID, sessionID: UUID,
                                     selectedID: String? = nil, navigationVersion: Int? = nil) -> (() -> Void)? {
        guard let cardState, !cardState.isSwitching(content.reference) else { return nil }
        if cardState.isPlaying(content.reference), let ticket = cardState.committedTicket {
            return { [weak self] in
                guard let self, self.acceptsRemoteAction(page: page, epoch: epoch, sessionID: sessionID, selectedID: selectedID, navigationVersion: navigationVersion) else { return }
                self.commands.stop(content.reference, expectedTicket: ticket)
            }
        }
        guard content.capabilities.contains(.play) else { return nil }
        return { [weak self] in
            guard let self, self.acceptsRemoteAction(page: page, epoch: epoch, sessionID: sessionID, selectedID: selectedID, navigationVersion: navigationVersion) else { return }
            self.workspace.requestSingle(content.reference)
        }
    }

    private func remoteInspectorActions(for item: SteamWorkshopBrowserItem, requiresInspectedItem: Bool = true) -> WallpaperInspectorActions? {
        guard workspace.presentation.page == .workshop else { return nil }
        let provider = WallpaperReference(provider: .steamWorkshop, sourceID: item.id)
        guard let content = downloadedContent[provider], content.publishedAvailability.isPublishedLocally, let cardState else { return nil }
        let page = workspace.presentation.page, epoch = workspace.relationships.resetEpoch
        let sessionID = workspace.presentation.selectionState.sessionID
        let navigationVersion = steam.navigationVersion
        let selectedID = requiresInspectedItem ? item.id : nil
        let primary = remotePrimaryAction(content, page: page, epoch: epoch, sessionID: sessionID, selectedID: selectedID, navigationVersion: navigationVersion)
        let favorite = makeCardFavoriteAction(content)
        return .init(state: .init(isPlaying: cardState.isPlaying(content.reference),
            isSwitching: cardState.isSwitching(content.reference), isFavorite: cardState.isFavorite(content.reference),
            canPerformPrimary: primary != nil, canFavorite: favorite != nil,
            canOrganize: commands.canOrganize && content.capabilities.contains(.organize),
            playlistNames: playlistNames[cardState.canonical(content.reference)] ?? []), onPrimary: { primary?() },
            onToggleFavorite: { [weak self] in
                guard let self, self.acceptsRemoteAction(page: page, epoch: epoch, sessionID: sessionID, selectedID: selectedID, navigationVersion: navigationVersion) else { return }
                favorite?()
            }, onChoosePlaylist: { [weak self] anchor in
                guard let self, self.acceptsRemoteAction(page: page, epoch: epoch, sessionID: sessionID, selectedID: selectedID, navigationVersion: navigationVersion) else { return }
                self.commands.choosePlaylist([content.reference], anchor: anchor)
            })
    }

    private func updateDirectoryFacts() {
        let revision = (workspace.catalog.catalog.revision, workspace.relationships.revision, workspace.relationships.resetEpoch)
        guard lastDirectoryRevision?.0 != revision.0 || lastDirectoryRevision?.1 != revision.1
                || lastDirectoryRevision?.2 != revision.2 else { return }
        lastDirectoryRevision = revision
        do {
            allEntries = try WallpaperLibraryQuery.directory(state: .init(), catalog: workspace.catalog.catalog, relationships: workspace.relationships)
            artwork.update(entries: allEntries, resetEpoch: workspace.relationships.resetEpoch,
                customCovers: Dictionary(uniqueKeysWithValues: workspace.relationships.playlists.compactMap { row in
                row.customCoverAssetID.map { (row.id, $0) }
            }), resolve: { [weak workspace] refs in
                guard let workspace else { return [] }
                return (try? WallpaperLibraryQuery.resolve(refs, catalog: workspace.catalog.catalog, relationships: workspace.relationships)) ?? []
            })
        } catch { workspace.presentation.report(error) }
    }

    private func renderCovers() {
        let state = workspace.presentation.state
        let count = state.page == .playlists ? workspace.relationships.playlists.count : state.queryResult.unfilteredCount
        sidebar.update(page: state.page, playlists: workspace.relationships.playlists, counts: state.page.isRemoteBrowse ? [:] : [state.page: count],
            covers: covers.compactMapValues(\.image), canEdit: commands.canOrganize, resetEpoch: workspace.relationships.resetEpoch, relationshipsRevision: workspace.relationships.revision)
        if state.page == .playlists {
            directory.update(entries: state.directoryEntries, covers: covers, preferredColumns: state.query.preferredColumns,
                permitsReordering: commands.canOrganize && workspace.presentation.permitsDirectoryReordering, canEdit: commands.canOrganize, resetEpoch: workspace.relationships.resetEpoch, relationshipsRevision: workspace.presentation.relationshipsRevision)
        }
        if case .playlist = state.page { updateHeader(state) }
    }

    private func updateHeader(_ state: WallpaperLibraryPresentationState) {
        guard case .playlist(let id) = state.page, let entry = allEntries.first(where: { $0.id == id }) else { return }
        let playable = state.queryResult.items.filter { $0.capabilities.contains(.play) }.count
        let query = state.query
        let filtered = !query.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || query.provider != nil || query.kind != nil || query.status != .all
        let summary = filtered ? "显示 \(state.queryResult.items.count) / 共 \(entry.count) 张壁纸" : "\(entry.count) 张壁纸"
        header.update(name: entry.name, summary: summary, image: covers[id]?.image, canPlay: playable > 0, canAdd: commands.canOrganize,
            descriptionText: workspace.relationships.playlists.first(where: { $0.id == id })?.descriptionText, playableCount: playable,
            play: { [weak self] in
                guard let self, self.permitsInput else { return }
                self.commands.playDisplayed()
            }, random: { [weak self] in
                guard let self, self.permitsInput else { return }
                self.commands.playDisplayed(random: true)
            },
            add: { [weak self] in self?.showPicker(for: id) })
    }

    private func updatePageChrome(_ state: WallpaperLibraryPresentationState) {
        let page = state.page, epoch = workspace.relationships.resetEpoch
        func action(_ title: String, _ perform: @escaping (WallpaperLibraryWindowComposition) -> Void) -> (String, () -> Void) {
            (title, { [weak self] in
                guard let self, self.permitsInput, self.workspace.presentation.page == page,
                      self.workspace.relationships.resetEpoch == epoch else { return }
                perform(self)
            })
        }
        let filtered = !state.query.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.query.provider != nil
            || state.query.kind != nil || state.query.status != .all || (page == .downloads && !state.query.showsAdultContent)
        var message: String?, actions: [(String, () -> Void)] = []
        var notices = [workspace.recoveryMessage, state.lastError].compactMap { $0 }.filter { !$0.isEmpty }
        var noticeActions: [(String, () -> Void)] = []
        let dependencies = (try? WallpaperLibraryQuery.requiredProviders(page: state.page, state: state.query, relationships: workspace.relationships)) ?? []
        if state.page == .playlists {
            let total = workspace.relationships.playlists.count, visible = state.directoryEntries.count
            directory.setPullCountText(visible == total ? "共 \(total) 个播放列表" : "显示 \(visible) / 共 \(total) 个播放列表")
        } else if case .playlist = page {
            grid.scrollView.pullCountText = nil
        } else if !state.page.isRemoteBrowse {
            let total = state.queryResult.unfilteredCount, visible = state.queryResult.items.count
            let fullCountKnown: Bool
            switch page {
            case .videos, .images, .downloads:
                // The total precedes provider filtering. Keep the original
                // filtered dependencies below for empty/loading feedback.
                let allProviders = (try? WallpaperLibraryQuery.requiredProviders(page: page, state: .init(), relationships: workspace.relationships)) ?? []
                fullCountKnown = allProviders.isSubset(of: workspace.catalog.catalog.loadedProviders)
            default:
                // Relation pages include unresolved canonical placeholders.
                fullCountKnown = true
            }
            if fullCountKnown {
                grid.scrollView.pullCountText = visible == total ? "共 \(total) 张壁纸" : "显示 \(visible) / 共 \(total) 张壁纸"
            } else {
                grid.scrollView.pullCountText = total > 0 ? (filtered ? "显示 \(visible) / 已加载 \(total) 张壁纸" : "已加载 \(total) 张壁纸") : nil
            }
        }
        var scanFailed = false
        // Remote browsing keeps its existing search/loading/error owner. These
        // statuses describe only the local downloaded content used by a page.
        if dependencies.contains(.pixabay), let scan = workspace.catalog.catalog.sourceScanStatuses[.pixabay] {
            switch scan.phase {
            case .loading:
                if scan.hasSuccessfulScan { notices.append("正在刷新 Pixabay 已下载的壁纸…") }
            case .ready(let warnings):
                if !warnings.isEmpty { notices.append("Pixabay 已下载内容：" + warnings.joined(separator: "；")) }
            case .failed(let reason):
                scanFailed = true
                notices.append((scan.hasSuccessfulScan ? "刷新失败，保留现有内容。" : "") + reason)
                noticeActions.append(action("重试载入") { $0.pixabay.refreshDownloadedContent() })
            }
        }
        if let provider = dependencies.first(where: { $0 == .wallhaven || $0 == .pixiv }),
           let scan = workspace.catalog.catalog.sourceScanStatuses[provider] {
            switch scan.phase {
            case .loading:
                if scan.hasSuccessfulScan { notices.append("正在刷新已下载的在线图片…") }
            case .ready(let warnings):
                if !warnings.isEmpty { notices.append("在线图片：" + warnings.joined(separator: "；")) }
            case .failed(let reason):
                scanFailed = true
                notices.append((scan.hasSuccessfulScan ? "刷新失败，保留现有内容。" : "") + reason)
                noticeActions.append(action("重试载入在线图片") { _ in OnlineImageLibrary.shared.refreshLocal() })
            }
        }
        if state.page == .playlists {
            if state.directoryEntries.isEmpty, !state.query.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message = "没有符合条件的播放列表"
                actions = [action("清除搜索") { composition in
                    var query = composition.workspace.presentation.queryState
                    query.search = ""
                    _ = composition.workspace.presentation.setQueryState(query)
                }]
            }
        } else if !state.page.isRemoteBrowse, state.queryResult.items.isEmpty {
            if scanFailed { message = "暂时没有可显示的壁纸" }
            else if !dependencies.isSubset(of: workspace.catalog.catalog.loadedProviders) { message = "正在载入壁纸…" }
            else if filtered {
                message = "没有符合条件的壁纸"
                actions = [action("清除筛选") { composition in
                    var query = composition.workspace.presentation.queryState
                    query.search = ""; query.provider = nil; query.kind = nil; query.status = .all
                    if page == .downloads { query.showsAdultContent = true }
                    _ = composition.workspace.presentation.setQueryState(query)
                }]
            } else {
                switch state.page {
                case .videos, .images:
                    message = state.page == .images ? "导入图片，建立你的壁纸资料库" : "导入视频，建立你的壁纸资料库"
                case .downloads:
                    message = "下载的壁纸将显示在这里"
                case .recent: message = "播放过的壁纸将显示在这里"
                case .favorites: message = "标记为特别喜爱的壁纸将显示在这里"
                case .playlist:
                    message = "从顶部添加壁纸，开始建立这个播放列表"
                default: break
                }
            }
        }
        chrome.update(notices: notices, empty: message, noticeActions: noticeActions, actions: actions, errorEvent: state.lastErrorEvent)
    }

    private func publishRemoteMode(_ page: WallpaperLibraryPage) {
        NotificationCenter.default.post(name: .steamWorkshopModeDidChange, object: nil,
            userInfo: ["enabled": page == .workshop])
        NotificationCenter.default.post(name: .pixabayModeDidChange, object: nil, userInfo: ["enabled": page == .pixabay])
        NotificationCenter.default.post(name: .staticImageLibraryModeDidChange, object: nil, userInfo: ["enabled": false])
    }

    private func addReferences(_ references: [WallpaperReference], to id: UUID) -> Bool {
        guard permitsInput, commands.canOrganize, !references.isEmpty, let collections = workspace.collections,
              collections.snapshot.playlists.contains(where: { $0.id == id }),
              let values = try? WallpaperLibraryQuery.resolve(references, catalog: workspace.catalog.catalog, relationships: workspace.relationships),
              values.allSatisfy({ $0.capabilities.contains(.organize) }) else { return false }
        let epoch = collections.snapshot.resetEpoch
        Task { @MainActor [weak self] in
            do {
                try await collections.perform(.addMembers(id, values.map(\.organizationItem), Date()), undoName: "添加到列表", expectedEpoch: epoch)
                guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else { return }
                self?.workspace.didEditMembers(of: .playlist(id))
            } catch { if collections.snapshot.resetEpoch == epoch { self?.workspace.presentation.report(error) } }
        }
        return true
    }

    private func showPicker(for id: UUID) {
        guard permitsInput, commands.canOrganize, picker == nil else { return }
        let picker = WallpaperPlaylistPickerController(workspace: workspace, manager: manager, images: images, steam: steam,
            pixabay: pixabay, destination: .playlist(id), hostWindow: { [weak self] in self?.split.view.window })
        self.picker = picker
        picker.onClose = { [weak self] in self?.picker = nil }
        inspector.closePreview()
        picker.show()
    }

    private func showCreatedPlaylistNotice(_ id: UUID) {
        guard let playlist = workspace.relationships.playlists.first(where: { $0.id == id }),
              let window = split.view.window else { return }
        let epoch = workspace.relationships.resetEpoch
        let page = workspace.presentation.page
        creationNotice.show(name: playlist.name, in: window) { [weak self] in
            guard let self, self.workspace.relationships.resetEpoch == epoch,
                  self.workspace.collections?.isResetting != true, self.workspace.presentation.page == page,
                  self.workspace.relationships.playlists.contains(where: { $0.id == id }) else { return }
            self.navigate(to: .playlist(id))
        }
    }

    func restoreContentFocus() {
        if let browser = onlineImages.browser(for: workspace.presentation.page) { browser.requestFocus(); return }
        guard !workspace.presentation.page.isRemoteBrowse, workspace.presentation.page != .playlists else { return }
        grid.collection.window?.makeFirstResponder(grid.collection)
    }

    func escape() {
        if inspector.previewReference != nil { inspector.closePreview() }
        else if inspector.inspectedReference != nil { inspector.closeInspector() }
        else if workspace.presentation.selectionState.isSelecting { commands.toggleSelectionMode() }
    }

    func close() {
        onlineImages.close()
        creationNotice.dismiss()
        inspector.closeInspector(); inspector.closePreview()
        artwork.setDemand(sourceToken: sidebarDemand, playlistIDs: [])
        artwork.setDemand(sourceToken: directoryDemand, playlistIDs: [])
        artwork.setDemand(sourceToken: headerDemand, playlistIDs: [])
        artwork.updateCurrentList(first: nil)
        workspace.catalog.setVisibleReferences([], sourceToken: gridDemand)
        adapter.updateViewport(visible: [], prefetch: [])
        picker?.close()
        commands.playlists?.close()
        directoryReturnContext = nil
        windowVisibility = nil
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        subscriptions.removeAll()
    }
}
