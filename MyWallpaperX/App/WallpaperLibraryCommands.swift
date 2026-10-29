import AppKit
import Combine

/// Fixed-reference product commands shared by toolbar, card, menu and Inspector.
/// The existing services still own imports, files, downloads and runtime output.
@MainActor final class WallpaperLibraryCommands {
    let workspace: WallpaperLibraryWorkspace
    let manager: WallpaperManager
    let images: SILService
    let steam: SteamWorkshopService
    let pixabay: PixabayService
    let hostWindow: () -> NSWindow?
    var onInspect: ((WallpaperContentItem) -> Void)?
    var onPreview: ((WallpaperContentItem) -> Void)?
    var onAddWallpapers: ((UUID) -> Void)?
    var onCloseInspector: (() -> Void)?
    var onFocusSearch: (() -> Void)?
    private(set) var relationshipUndo: WallpaperLibraryRelationshipUndo?
    private(set) var playlists: PlaylistOrganizationActions?
    private lazy var imports = WallpaperLibraryImportCoordinator(workspace: workspace, manager: manager, images: images, hostWindow: hostWindow)

    init(workspace: WallpaperLibraryWorkspace, manager: WallpaperManager, images: SILService,
         steam: SteamWorkshopService, pixabay: PixabayService, hostWindow: @escaping () -> NSWindow?) {
        self.workspace = workspace; self.manager = manager; self.images = images
        self.steam = steam; self.pixabay = pixabay; self.hostWindow = hostWindow
        if let collections = workspace.collections {
            relationshipUndo = WallpaperLibraryRelationshipUndo(collections: collections,
                report: { [weak workspace] in workspace?.presentation.report($0) }, didRestore: { [weak workspace] in
                    guard let workspace else { return }
                    workspace.didRestoreOrganization()
                })
            let actions = PlaylistOrganizationActions(collections: collections, hostWindow: hostWindow)
            actions.onOpen = { [weak workspace] id in _ = workspace?.presentation.switchPage(.playlist(id)) }
            actions.onDidEdit = { [weak workspace] id, deleted in workspace?.didEditMembers(of: .playlist(id), deleted: deleted) }
            playlists = actions
        }
    }

    var selection: [WallpaperContentItem] {
        let state = workspace.presentation.selectionState
        return workspace.presentation.queryResult.items.filter { state.references.contains($0.reference) }
    }
    var canOrganize: Bool { workspace.presentation.canEditCollections && relationshipUndo?.undoManager.isApplyingTransaction != true }
    var availabilityChanges: AnyPublisher<Void, Never> {
        relationshipUndo?.undoManager.applyingChanges.eraseToAnyPublisher()
            ?? Empty<Void, Never>(completeImmediately: false).eraseToAnyPublisher()
    }
    var canImport: Bool { canOrganize && WallpaperLibraryImportCoordinator.permitsImport(to: workspace.presentation.page) }
    var canToggleSelection: Bool { !workspace.presentation.page.isRemoteBrowse && workspace.presentation.page != .playlists }
    var canFavorite: Bool { favoriteActionState.canExecute }
    var favoriteActionState: WallpaperLibraryFavoriteActionState { favoriteActionState(for: selection) }

    func favoriteActionState(for items: [WallpaperContentItem]) -> WallpaperLibraryFavoriteActionState {
        guard !items.isEmpty, let state = favoriteState(for: items) else { return .unavailable }
        return .init(canEdit: canOrganize, hasItems: !items.isEmpty,
            allFavorite: items.allSatisfy { state.isFavorite($0.reference) },
            allOrganizable: items.allSatisfy { $0.capabilities.contains(.organize) })
    }

    private func favoriteState(for items: [WallpaperContentItem]) -> WallpaperLibraryCardStateProjection? {
        try? WallpaperLibraryCardStateProjection(items: items, relationships: workspace.relationships,
            committedReference: nil, sequenceTicket: nil, runtimeTicket: nil)
    }

    func makeFavoriteAction(_ references: [WallpaperReference]? = nil,
                            resolved: (items: [WallpaperContentItem], state: WallpaperLibraryFavoriteActionState)? = nil) -> (() -> Void)? {
        guard let items = resolved?.items ?? resolveSelection(references) else { return nil }
        let action = resolved?.state ?? favoriteActionState(for: items)
        guard action.canExecute else { return nil }
        let fixed = items.map(\.reference), page = workspace.presentation.page
        let epoch = workspace.relationships.resetEpoch, sessionID = workspace.presentation.selectionState.sessionID
        return { [weak self] in
            guard let self, self.workspace.presentation.page == page,
                  self.workspace.relationships.resetEpoch == epoch,
                  self.workspace.presentation.selectionState.sessionID == sessionID else { return }
            self.toggleFavorite(fixed, expectingRemoval: action.isRemoving)
        }
    }

    /// Capture the meaning when a control/menu is rendered. A delayed Stop
    /// never turns into Play or borrows a later ticket for the same reference.
    func makePrimaryAction(for content: WallpaperContentItem,
                           from capturedSource: WallpaperPlaybackSequence.Snapshot? = nil,
                           renderedPlaying: Bool? = nil, renderedTicket: PlaybackSwitchTicket? = nil) -> (() -> Void)? {
        if renderedPlaying ?? workspace.isPlaying(content.reference),
           let ticket = renderedPlaying == nil ? manager.playbackSwitch.committed?.ticket : renderedTicket {
            return { [weak self] in self?.stop(content.reference, expectedTicket: ticket) }
        }
        if let apply = makeApplyAction(for: content, from: capturedSource) { return apply }
        if canOrganize, WallpaperLibraryImportCoordinator.canRelocate(content, relationships: workspace.relationships) {
            let reference = content.reference, epoch = workspace.relationships.resetEpoch
            let page = workspace.presentation.page
            return { [weak self] in
                guard let self, self.workspace.relationships.resetEpoch == epoch,
                      self.workspace.presentation.page == page, self.canOrganize else { return }
                self.imports.chooseReplacement(for: reference)
            }
        }
        return WallpaperLibraryDownloadRecovery.makePrimaryAction(for: content, workspace: workspace, steam: steam, pixabay: pixabay)
    }

    func makeApplyAction(for content: WallpaperContentItem,
                         from capturedSource: WallpaperPlaybackSequence.Snapshot? = nil) -> (() -> Void)? {
        guard content.capabilities.contains(.play),
              let source = capturedSource ?? (try? workspace.capturePlaybackSnapshot(for: content.reference)) else { return nil }
        return { [weak self] in self?.workspace.play(content.reference, from: source) }
    }

    func stop(_ reference: WallpaperReference, expectedTicket: PlaybackSwitchTicket) {
        guard workspace.isPlaying(reference), manager.playbackSwitch.committed?.ticket == expectedTicket,
              manager.libraryPlaybackSequence.committed?.ticket == expectedTicket else { return }
        manager.stopCurrentPlayback()
    }

    func playDisplayed(random: Bool = false) {
        let playable = workspace.presentation.queryResult.items.filter { $0.capabilities.contains(.play) }
        let chosen: WallpaperContentItem?
        if random {
            let committed = manager.libraryPlaybackSequence.committed?.reference
            let requested = manager.libraryPlaybackSequence.pending?.proposal.entry.reference
            let identities = try? WallpaperLibraryQuery.canonicalReferences(Set([committed, requested].compactMap { $0 }),
                relationships: workspace.relationships)
            let current = committed.map { identities?[$0] ?? $0 }
            let pending = requested.map { identities?[$0] ?? $0 }
            let alternatives = playable.filter { $0.reference != current }
            let fresh = alternatives.filter { $0.reference != pending }
            chosen = (fresh.isEmpty ? alternatives : fresh).randomElement() ?? playable.first
        } else {
            chosen = playable.first
        }
        guard let chosen else { return }
        if random { manager.setRandomPlaybackEnabled(true) }
        workspace.play(chosen.reference)
    }

    func toggleSelectionMode() {
        guard canToggleSelection else { return }
        let selecting = !workspace.presentation.selectionState.isSelecting
        _ = workspace.presentation.setSelection([], isSelecting: selecting)
        onCloseInspector?()
    }

    func selectAll() {
        guard canToggleSelection else { return }
        let refs = Set(workspace.presentation.queryResult.items.map(\.reference))
        _ = workspace.presentation.setSelection(refs, focused: workspace.presentation.queryResult.items.first?.reference, isSelecting: true)
    }

    func toggleFavorite(_ references: [WallpaperReference]? = nil, expectingRemoval: Bool? = nil) {
        guard canOrganize, let collections = workspace.collections else { return }
        guard let items = resolveSelection(references) else { return }
        let action = favoriteActionState(for: items)
        guard action.canExecute, expectingRemoval == nil || expectingRemoval == action.isRemoving else { return }
        let enabled = !action.isRemoving
        perform(items.map { .setFavorite($0.organizationItem, enabled, Date()) }, name: enabled ? "特别喜爱" : "取消特别喜爱",
                page: .favorites, collections: collections, selectedReferences: Set(items.map(\.reference)))
    }

    private func resolveSelection(_ references: [WallpaperReference]?) -> [WallpaperContentItem]? {
        let references = references ?? selection.map(\.reference)
        do { return try WallpaperLibraryQuery.resolve(references, catalog: workspace.catalog.catalog, relationships: workspace.relationships) }
        catch { workspace.presentation.report(error); return nil }
    }

    func choosePlaylist(_ references: [WallpaperReference]? = nil, anchor: NSView? = nil) {
        guard let menu = makePlaylistMenu(references) else { return }
        if let anchor { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.maxY), in: anchor) }
        else if let view = hostWindow()?.contentView { menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.midX, y: view.bounds.midY), in: view) }
    }

    func makePlaylistMenu(_ references: [WallpaperReference]? = nil, permitsAction: (() -> Bool)? = nil) -> NSMenu? {
        guard canOrganize, let items = resolveSelection(references), !items.isEmpty,
              items.allSatisfy({ $0.capabilities.contains(.organize) }), permitsAction?() != false else { return nil }
        let menu = NSMenu()
        let epoch = workspace.relationships.resetEpoch
        let page = workspace.presentation.page, session = workspace.presentation.selectionState.sessionID
        menu.autoenablesItems = false
        for list in workspace.relationships.playlists.sorted(by: { $0.sidebarRank < $1.sidebarRank }) {
            menu.addItem(ActionMenuItem(title: list.name, symbol: WallpaperLibrarySymbols.playlist) { [weak self] in
                guard permitsAction?() != false, let self, self.canOrganize, self.workspace.relationships.resetEpoch == epoch,
                      self.workspace.presentation.page == page, self.workspace.presentation.selectionState.sessionID == session,
                      let current = self.resolveSelection(items.map(\.reference)) else { return }
                guard current.count == items.count, current.allSatisfy({ $0.capabilities.contains(.organize) }) else { return }
                let receipt = self.workspace.presentation.beginOrganizationOperation(Set(current.map(\.reference)))
                self.playlists?.add(current.map(\.organizationItem), to: list.id) { [weak self] in
                    self?.workspace.presentation.completeOrganizationOperation(receipt, succeeded: true)
                }
            })
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(ActionMenuItem(title: "新建列表…", symbol: "plus") { [weak self] in
            guard permitsAction?() != false, let self, self.canOrganize, self.workspace.relationships.resetEpoch == epoch,
                  self.workspace.presentation.page == page, self.workspace.presentation.selectionState.sessionID == session,
                  let current = self.resolveSelection(items.map(\.reference)) else { return }
            guard current.count == items.count, current.allSatisfy({ $0.capabilities.contains(.organize) }) else { return }
            let receipt = self.workspace.presentation.beginOrganizationOperation(Set(current.map(\.reference)))
            self.playlists?.create(members: current.map(\.organizationItem)) { [weak self] in
                self?.workspace.presentation.completeOrganizationOperation(receipt, succeeded: true)
            }
        })
        return menu
    }

    func makeRecentMenu(for target: WallpaperLibraryPage? = nil) -> NSMenu? {
        guard (target ?? workspace.presentation.page) == .recent else { return nil }
        let epoch = workspace.relationships.resetEpoch, page = workspace.presentation.page
        let menu = NSMenu()
        let item = ActionMenuItem(title: "清空最近使用…", symbol: "clock.badge.xmark") { [weak self] in
            guard let self, self.workspace.relationships.resetEpoch == epoch,
                  self.workspace.presentation.page == page else { return }
            self.clearRecent()
        }
        item.isEnabled = canOrganize && !workspace.relationships.recent.isEmpty
        menu.autoenablesItems = false
        menu.addItem(item)
        return menu
    }

    private func clearRecent() {
        guard canOrganize, let collections = workspace.collections, !workspace.relationships.recent.isEmpty else { return }
        let epoch = workspace.relationships.resetEpoch
        let page = workspace.presentation.page, session = workspace.presentation.selectionState.sessionID
        let selected = page == .recent ? workspace.presentation.selectionState.references : []
        let alert = makeAppAlert(title: "清空最近使用？", message: "仅清除播放记录。原始壁纸、播放列表和特别喜爱均会保留。",
            style: .warning, buttons: ["清空最近使用", "取消"])
        presentAppAlert(alert, in: hostWindow()) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn, self.canOrganize,
                  self.workspace.relationships.resetEpoch == epoch, self.workspace.presentation.page == page,
                  self.workspace.presentation.selectionState.sessionID == session else { return }
            self.perform([.clearRecent], name: nil, page: .recent, collections: collections,
                selectedReferences: selected)
        }
    }

    func importFiles(_ urls: [URL]? = nil) {
        guard canImport else { return }
        let page = workspace.presentation.page
        if let urls { imports.importFiles(urls, to: page) }
        else { imports.chooseFiles(to: page) }
    }

    func inspectSelection() { if selection.count == 1, let item = selection.first { onInspect?(item) } }
    func previewSelection() { if selection.count == 1, let item = selection.first { onPreview?(item) } }
    func reveal(_ items: [WallpaperContentItem]? = nil) {
        let urls = (items ?? selection).filter { $0.capabilities.contains(.reveal) }.compactMap { $0.locator.path.map { URL(fileURLWithPath: $0) } }
        if !urls.isEmpty { FinderRevealCoordinator.shared.reveal(urls) }
    }

    /// The browser exposes a real way back for retained local downloads. This
    /// action neither downloads again nor starts playback.
    func makeRestoreLibraryAction(for content: WallpaperContentItem) -> (() -> Void)? {
        guard canOrganize, content.publishedAvailability == .available,
              let revisions = try? WallpaperLibraryQuery.libraryExclusionRevisions(for: [content.reference], relationships: workspace.relationships),
              let revision = revisions[content.reference],
              let restore = makeExplicitLibraryRestorationReceipt(for: content.reference) else { return nil }
        let page = workspace.presentation.page, epoch = workspace.relationships.resetEpoch
        let session = workspace.presentation.selectionState.sessionID
        return { [weak self] in
            guard let self, self.canOrganize, self.workspace.relationships.resetEpoch == epoch,
                  self.workspace.presentation.page == page, self.workspace.presentation.selectionState.sessionID == session,
                  let current = try? self.workspace.content(for: content.reference), current.reference == content.reference,
                  current.publishedAvailability == .available,
                  let latest = try? WallpaperLibraryQuery.libraryExclusionRevisions(for: [content.reference], relationships: self.workspace.relationships),
                  latest[content.reference] == revision else { return }
            restore()
        }
    }

    /// Injected into the source's explicit download admission. Its callback is
    /// carried by that original request/queue payload, never made by a scan.
    func makeExplicitLibraryRestorationReceipt(for reference: WallpaperReference) -> (() -> Void)? {
        guard canOrganize else { return nil }
        return Self.makeExplicitLibraryRestorationReceipt(for: reference, in: workspace)
    }

    /// Runtime download retries may outlive or precede any main window. The
    /// existing workspace/Store own admission; a window is only an optional echo.
    static func makeExplicitLibraryRestorationReceipt(for reference: WallpaperReference,
                                                       in workspace: WallpaperLibraryWorkspace) -> (() -> Void)? {
        guard workspace.presentation.canEditCollections, let collections = workspace.collections,
              let revisions = try? WallpaperLibraryQuery.libraryExclusionRevisions(for: [reference], relationships: collections.snapshot) else { return nil }
        let epoch = collections.snapshot.resetEpoch, expected = revisions[reference]
        return { [weak workspace, collections] in
            guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else { return }
            Task { @MainActor [weak workspace, collections] in
                guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else { return }
                do {
                    try await collections.perform(.clearLibraryExclusion(reference, expectedRevision: expected), expectedEpoch: epoch)
                    guard collections.snapshot.resetEpoch == epoch else { return }
                    let page: WallpaperLibraryPage
                    switch reference.provider {
                    case .videoLibrary: page = .videos
                    case .staticImageLibrary: page = .images
                    case .steamWorkshop, .pixabay, .wallhaven, .pixiv: page = .downloads
                    }
                    workspace?.didEditMembers(of: page)
                } catch {
                    guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else { return }
                    workspace?.presentation.report(error)
                }
            }
        }
    }

    var removalTitle: String { removalTitle(for: workspace.presentation.page) }
    private func removalTitle(for page: WallpaperLibraryPage) -> String {
        switch page {
        case .playlist: return "从列表移除"
        case .favorites: return "取消特别喜爱"
        case .recent: return "从最近移除"
        case .downloads: return "从我的下载移除"
        default: return "移出资料库"
        }
    }

    func remove(_ items: [WallpaperContentItem]? = nil, from fixedPage: WallpaperLibraryPage? = nil) {
        guard canOrganize else { return }
        let fixed = items ?? selection
        guard !fixed.isEmpty else { return }
        let page = fixedPage ?? workspace.presentation.page, epoch = workspace.relationships.resetEpoch
        guard page == workspace.presentation.page, !page.isRemoteBrowse, page != .playlists else { return }
        let session = workspace.presentation.selectionState.sessionID
        let receipt = workspace.presentation.beginRemoval(Set(fixed.map(\.reference)), from: page)
        let title = removalTitle(for: page)
        let scope: String
        switch page {
        case .favorites: scope = "移除喜爱标记及最近使用记录，源文件和其他列表保留。"
        case .recent: scope = "仅移除播放记录，源文件和其他列表保留。"
        case .playlist: scope = "移除当前列表项目及最近使用记录，源文件和其他列表保留。"
        case .downloads: scope = "移除下载项目及最近使用记录，源文件和其他列表保留。"
        default: scope = "移除资料库项目及最近使用记录，源文件和其他列表保留。"
        }
        let saver = ScreenSaverIntegration.shared.configuration?.content
        let retainedSaver = fixed.contains { $0.reference.storageKey == saver?.sourceIdentity }
        let message = scope + "勾选会删除源文件，无法撤销。"
            + (retainedSaver ? "\n已保存的屏保副本会保留，可在「锁屏与屏保」中清除。" : "")
        let alert = makeAppAlert(title: "\(title) \(fixed.count) 项？", message: message, style: .warning, buttons: ["移除", "取消"])
        alert.showsSuppressionButton = true
        let deleteFiles = alert.suppressionButton!
        deleteFiles.title = "删除磁盘的源文件"
        deleteFiles.state = .off
        deleteFiles.sizeToFit()
        deleteFiles.alignment = .left
        presentAppAlert(alert, in: hostWindow()) { [weak self] response in
            guard let self else { return }
            guard response == .alertFirstButtonReturn,
                  self.canOrganize, self.workspace.relationships.resetEpoch == epoch,
                  self.workspace.presentation.page == page,
                  self.workspace.presentation.selectionState.sessionID == session else {
                self.workspace.presentation.completeRemoval(receipt, succeeded: [])
                return
            }
            self.removeConfirmed(fixed, page: page, receipt: receipt, epoch: epoch, deleteSourceFiles: deleteFiles.state == .on)
        }
    }

    private func removeConfirmed(_ items: [WallpaperContentItem], page: WallpaperLibraryPage,
                                 receipt: WallpaperLibrarySelectionReceipt?, epoch: UUID, deleteSourceFiles: Bool) {
        guard let collections = workspace.collections else { return }
        Task { @MainActor [weak self] in
            guard let self, collections.snapshot.resetEpoch == epoch, !collections.isResetting else { return }
            let physical = deleteSourceFiles ? await self.deleteSourceFiles(items, epoch: epoch) : nil
            // Started file I/O cannot be rolled back by a later reset. Refresh
            // current source truth even when its old selection receipt is revoked.
            if deleteSourceFiles { self.workspace.catalog.refreshAvailability() }
            guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else { return }
            let succeeded = physical.map { Set($0.items.filter(\.succeeded).map(\.reference)) } ?? Set(items.map(\.reference))
            let accepted = items.filter { succeeded.contains($0.reference) }
            var commands: [UserCollectionsCommand] = []
            var undoName: String?
            switch page {
            case .playlist(let id):
                commands = [.removeMembers(id, accepted.map(\.reference), Date())]; undoName = "从列表移除"
            case .favorites:
                commands = accepted.map { .setFavorite($0.organizationItem, false, Date()) }; undoName = "取消特别喜爱"
            case .recent: break
            case .videos, .images, .downloads: break
            default: self.workspace.presentation.completeRemoval(receipt, succeeded: []); return
            }
            if deleteSourceFiles || page == .videos || page == .images || page == .downloads {
                commands.append(.setLibraryExcluded(accepted.map(\.reference), true))
            }
            commands.append(.removeRecent(accepted.map(\.reference)))
            do {
                if !accepted.isEmpty {
                    try await collections.perform(commands, undoName: deleteSourceFiles ? nil : undoName, expectedEpoch: epoch)
                }
                guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else { return }
                self.workspace.presentation.completeRemoval(receipt, succeeded: succeeded)
                self.workspace.didEditMembers(of: page)
            } catch {
                guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else { return }
                self.workspace.presentation.completeRemoval(receipt, succeeded: [])
                let prefix = physical?.items.contains(where: { $0.sourceFileDeleted }) == true ? "源文件已删除，但 App 移除记录未能保存。其他关系将显示文件缺失。\n" : ""
                self.workspace.presentation.report(CocoaError(.fileWriteUnknown,
                    userInfo: [NSLocalizedDescriptionKey: prefix + error.localizedDescription]))
            }
            if let physical {
                let failures = physical.items.filter { !$0.succeeded }.map {
                    $0.sourceURL.lastPathComponent + "：" + ($0.failureMessage ?? "源文件未删除")
                }
                if !failures.isEmpty {
                    presentAppAlert(makeAppAlert(title: "部分源文件未完成删除", message: failures.joined(separator: "\n")), in: self.hostWindow())
                }
            }
        }
    }

    private func deleteSourceFiles(_ fixed: [WallpaperContentItem], epoch: UUID) async -> WallpaperSourceDeletionResult {
        var results: [WallpaperSourceDeletionResult.Item] = []
        var targets: [WallpaperContentItem] = []
        for item in fixed {
            let url = URL(fileURLWithPath: item.locator.path ?? "")
            if item.reference.provider == .videoLibrary || item.reference.provider == .staticImageLibrary {
                let path = url.resolvingSymlinksInPath().standardizedFileURL.path
                let ownedRoots = [steam.steamDownloadLibraryRootURL] + type(of: pixabay).downloadRoots + OnlineImageLibrary.shared.downloadRoots
                if ownedRoots.contains(where: {
                    let root = $0.resolvingSymlinksInPath().standardizedFileURL.path
                    return path == root || path.hasPrefix(root + "/")
                }) {
                    results.append(.init(reference: item.reference, sourceURL: url, succeeded: false, sourceFileDeleted: false,
                        failureMessage: "该文件由下载来源管理，请从我的下载删除；不会根据路径推断别名"))
                    continue
                }
            }
            guard let current = try? workspace.content(for: item.reference), current.reference == item.reference,
                  current.providerReference == item.providerReference,
                  current.locator.path.map({ Data($0.utf8) }) == item.locator.path.map({ Data($0.utf8) }),
                  current.publishedAvailability == .available, item.locator.path?.isEmpty == false else {
                results.append(.init(reference: item.reference, sourceURL: url, succeeded: false, sourceFileDeleted: false,
                    failureMessage: "源文件不可用或条目已变化，未删除"))
                continue
            }
            targets.append(current)
        }
        func provider(_ item: WallpaperContentItem) -> WallpaperProvider {
            // A proven remote identity must retain that source's owned-tree
            // transaction, even when its available pixel backing is a Video row.
            [.steamWorkshop, .pixabay, .wallhaven, .pixiv].contains(item.reference.provider) ? item.reference.provider : item.providerReference.provider
        }
        for source in WallpaperProvider.allCases {
            guard workspace.relationships.resetEpoch == epoch, workspace.collections?.isResetting == false else { break }
            let group = targets.filter { provider($0) == source }
            guard !group.isEmpty else { continue }
            switch source {
            case .videoLibrary, .staticImageLibrary:
                let sourceResult: WallpaperSourceDeletionResult
                if source == .videoLibrary {
                    let refs = Set(group.map(\.providerReference))
                    let rows = manager.wallpapers.filter { refs.contains(.init(provider: .videoLibrary, sourceID: $0.id)) }
                    sourceResult = await withCheckedContinuation { continuation in
                        manager.deleteSourceFiles(rows) { continuation.resume(returning: $0) }
                    }
                } else {
                    sourceResult = await withCheckedContinuation { continuation in
                        images.deleteSourceFiles(ids: group.map(\.providerReference.sourceID), isInUse: { [weak manager = self.manager] url in
                            manager?.isLocalSourceFileInUse(url.path) ?? true
                        }) { continuation.resume(returning: $0) }
                    }
                }
                let bySource = Dictionary(sourceResult.items.map { ($0.reference, $0) }, uniquingKeysWith: { first, _ in first })
                for item in group {
                    let result = bySource[item.providerReference]
                    results.append(.init(reference: item.reference, sourceURL: URL(fileURLWithPath: item.locator.path!),
                        succeeded: result?.succeeded == true, sourceFileDeleted: result?.sourceFileDeleted == true,
                        failureMessage: result?.failureMessage ?? (result == nil ? "来源条目已不存在" : nil)))
                }
            case .steamWorkshop:
                let removed: WallpaperSourceDeletionResult = await withCheckedContinuation { continuation in
                    steam.deleteSourceFiles(itemIDs: group.map(\.reference.sourceID)) { continuation.resume(returning: $0) }
                }
                let byReference = Dictionary(removed.items.map { ($0.reference, $0) }, uniquingKeysWith: { first, _ in first })
                for item in group {
                    let result = byReference[item.reference]
                    results.append(.init(reference: item.reference, sourceURL: URL(fileURLWithPath: item.locator.path!),
                        succeeded: result?.succeeded == true, sourceFileDeleted: result?.sourceFileDeleted == true,
                        failureMessage: result?.failureMessage ?? (result == nil ? "Steam 源文件删除未完成" : nil)))
                }
            case .pixabay:
                let removed = pixabay.deleteLocalFiles(at: group.map { URL(fileURLWithPath: $0.locator.path!) }, isInUse: { [weak manager = self.manager] url in
                    manager?.isLocalSourceFileInUse(url.path) ?? true
                })
                let byPath = Dictionary(removed.map { (Data($0.localURL.standardizedFileURL.path.utf8), $0) }, uniquingKeysWith: { first, _ in first })
                for item in group {
                    let url = URL(fileURLWithPath: item.locator.path!).standardizedFileURL
                    let result = byPath[Data(url.path.utf8)]
                    results.append(.init(reference: item.reference, sourceURL: url, succeeded: result?.succeeded == true,
                        sourceFileDeleted: result?.sourceFileDeleted == true, failureMessage: result?.failureMessage ?? (result == nil ? "下载文件已变化" : nil)))
                }
            case .wallhaven, .pixiv:
                for item in group {
                    guard workspace.relationships.resetEpoch == epoch, workspace.collections?.isResetting == false else { break }
                    let url = URL(fileURLWithPath: item.locator.path!)
                    do {
                        guard let revision = item.metadata.resourceRevision.flatMap(UUID.init(uuidString:)) else {
                            throw OnlineImageError.message("下载记录已变化，请重新打开列表后再删除。")
                        }
                        try await OnlineImageLibrary.shared.delete(item.reference, expectedRevision: revision,
                            permitsDeletion: { [weak workspace = self.workspace] in
                                workspace?.relationships.resetEpoch == epoch && workspace?.collections?.isResetting == false
                            })
                        results.append(.init(reference: item.reference, sourceURL: url, succeeded: true, sourceFileDeleted: true, failureMessage: nil))
                    } catch {
                        results.append(.init(reference: item.reference, sourceURL: url, succeeded: false,
                            sourceFileDeleted: !FileManager.default.fileExists(atPath: url.path), failureMessage: error.localizedDescription))
                    }
                }
            }
        }
        return .init(items: results)
    }

    private func perform(_ commands: [UserCollectionsCommand], name: String?, page: WallpaperLibraryPage,
                         collections: UserCollectionsController, selectedReferences: Set<WallpaperReference>) {
        let epoch = collections.snapshot.resetEpoch
        let receipt = workspace.presentation.beginOrganizationOperation(selectedReferences)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await collections.perform(commands, undoName: name, expectedEpoch: epoch)
                guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else { return }
                self.workspace.presentation.completeOrganizationOperation(receipt, succeeded: true)
                self.workspace.didEditMembers(of: page)
            } catch {
                guard collections.snapshot.resetEpoch == epoch, !collections.isResetting else { return }
                self.workspace.presentation.completeOrganizationOperation(receipt, succeeded: false)
                self.workspace.presentation.report(error)
            }
        }
    }

    func contextMenu(for items: [WallpaperContentItem], includeRecoverySourcePage: Bool = true, includeFavorite: Bool = true) -> NSMenu? {
        guard !items.isEmpty else { return nil }
        let menu = NSMenu(); menu.autoenablesItems = false
        let epoch = workspace.relationships.resetEpoch
        let page = workspace.presentation.page
        let session = workspace.presentation.selectionState.sessionID
        let accountEpoch = steam.steamServiceClient.accountEpoch
        let source = items.first.flatMap { try? workspace.capturePlaybackSnapshot(for: $0.reference) }
        func add(_ title: String, _ symbol: String, enabled: Bool = true, action: @escaping () -> Void) {
            let item = ActionMenuItem(title: title, symbol: symbol) { [weak self] in
                guard let self, self.workspace.relationships.resetEpoch == epoch,
                      self.workspace.presentation.page == page,
                      self.workspace.presentation.selectionState.sessionID == session else { return }
                action()
            }
            item.isEnabled = enabled; menu.addItem(item)
        }
        if items.count == 1, let item = items.first {
            if workspace.isPlaying(item.reference), let ticket = manager.playbackSwitch.committed?.ticket {
                add("停止播放", "stop.fill") { [weak self] in self?.stop(item.reference, expectedTicket: ticket) }
            } else {
                add("设为壁纸", "play.fill", enabled: item.capabilities.contains(.play)) { [weak self] in
                    self?.workspace.play(item.reference, from: source)
                }
            }
            if item.kind == .video {
                add("用作屏保", "display") { [weak self] in
                    guard let self else { return }
                    guard item.publishedAvailability.isAvailable, item.capabilities.contains(.play) else {
                        presentAppAlert(makeAppAlert(title: "视频暂不可用", message: "请重新定位本地文件或完成下载后，再将此视频保存为系统屏保。"), in: self.hostWindow())
                        return
                    }
                    ScreenSaverWindowController.shared.show(reference: item.reference, relativeTo: self.hostWindow())
                }
            }
            add("查看信息", "info.circle") { [weak self] in self?.onInspect?(item) }
            add("预览", "eye", enabled: item.capabilities.contains(.quickLook) || item.kind == .web || item.kind == .scene) { [weak self] in self?.onPreview?(item) }
            if WallpaperLibraryImportCoordinator.canRelocate(item, relationships: workspace.relationships) {
                add("重新定位文件…", "folder.badge.questionmark", enabled: canOrganize) { [weak self] in
                    self?.imports.chooseReplacement(for: item.reference)
                }
            }
            if let recovery = WallpaperLibraryDownloadRecovery.makeMenu(for: item, workspace: workspace,
                steam: steam, pixabay: pixabay, includeSourcePage: includeRecoverySourcePage) {
                for entry in recovery.items { recovery.removeItem(entry); menu.addItem(entry) }
            }
            if let assetID = OnlineImageAssetID(reference: item.providerReference),
               OnlineImageLibrary.shared.progress[assetID] != nil {
                add("取消下载", "xmark") { OnlineImageLibrary.shared.cancel(assetID) }
            }
        }
        if includeFavorite {
            let state = favoriteActionState(for: items)
            let action = makeFavoriteAction(resolved: (items, state))
            add(state.title, state.isRemoving ? "heart.fill" : "heart", enabled: state.canExecute) { action?() }
        }
        let playlistItem = NSMenuItem(title: "添加到列表", action: nil, keyEquivalent: "")
        playlistItem.image = NSImage(systemSymbolName: "text.badge.plus", accessibilityDescription: nil)
        playlistItem.submenu = makePlaylistMenu(items.map(\.reference))
        playlistItem.isEnabled = playlistItem.submenu != nil
        menu.addItem(playlistItem)
        let files = items.compactMap { item -> URL? in
            guard item.kind == .image || item.kind == .video, let path = item.locator.path else { return nil }
            return URL(fileURLWithPath: path)
        }
        if files.count == items.count, let openWith = WallpaperOpenWithMenu.make(for: files, permitsAction: { [weak self] in
            guard let self else { return false }
            return self.workspace.relationships.resetEpoch == epoch && self.workspace.presentation.page == page
                && self.workspace.presentation.selectionState.sessionID == session
        }, reportError: { [weak self] in self?.workspace.presentation.report($0) }) {
            menu.addItem(openWith)
        }
        add("在 Finder 中显示", "folder", enabled: items.contains { $0.capabilities.contains(.reveal) }) { [weak self] in self?.reveal(items) }
        if items.count == 1, let item = items.first, item.providerReference.provider == .steamWorkshop,
           let record = steam.latestDownloadRecord(for: item.providerReference.sourceID) {
            menu.addItem(.separator())
            let source = SteamWorkshopItemMenu.make(item: record.displayItemForToolbar, service: steam,
                includePrimary: false, includeReveal: false)
            for entry in source.items { source.removeItem(entry); menu.addItem(entry) }
            if item.capabilities.contains(.retryUpdate) || item.capabilities.contains(.retryDownload) {
                add(item.capabilities.contains(.retryUpdate) ? "重试更新" : "重试下载", "arrow.clockwise") { [weak self] in
                    guard let self, self.steam.steamServiceClient.accountEpoch == accountEpoch else { return }
                    self.steam.downloadWorkshopItem(id: record.id, pageTitle: record.title)
                }
            }
        }
        let retryable = items.compactMap { item -> SteamWorkshopDownloadRecord? in
            guard item.providerReference.provider == .steamWorkshop, let record = steam.latestDownloadRecord(for: item.providerReference.sourceID),
                  SteamWorkshopDownloadGridSupport.isRetryEligible(record) else { return nil }
            return record
        }
        if items.count > 1, !retryable.isEmpty {
            add("重试 \(retryable.count) 项", "arrow.clockwise") { [weak self] in
                guard let self, self.steam.steamServiceClient.accountEpoch == accountEpoch else { return }
                for record in retryable {
                    guard let current = self.steam.latestDownloadRecord(for: record.id), SteamWorkshopDownloadGridSupport.isRetryEligible(current) else { continue }
                    self.steam.downloadWorkshopItem(id: current.id, pageTitle: current.title)
                }
            }
        }
        if !workspace.presentation.page.isRemoteBrowse {
            menu.addItem(.separator())
            add(removalTitle(for: page), "trash", enabled: canOrganize) { [weak self] in self?.remove(items, from: page) }
        }
        return menu
    }
}

/// Ephemeral state for one accepted display batch. Alias normalization is done
/// once; asking a visible card about favorite/playing never rebuilds a catalog.
/// One eligibility rule for the displayed heart and its command. Removing an
/// existing favorite needs no local media; adding requires every item to be
/// organizable. A mixed selection must never advertise an action that is a no-op.
nonisolated struct WallpaperLibraryFavoriteActionState: Equatable, Sendable {
    let isRemoving: Bool
    let canExecute: Bool
    var title: String { isRemoving ? "取消特别喜爱" : "特别喜爱" }

    init(canEdit: Bool, hasItems: Bool, allFavorite: Bool, allOrganizable: Bool) {
        isRemoving = hasItems && allFavorite
        canExecute = hasItems && canEdit && (allFavorite || allOrganizable)
    }

    static let unavailable = Self(canEdit: false, hasItems: false, allFavorite: false, allOrganizable: false)
}

nonisolated struct WallpaperLibraryCardStateProjection {
    private let canonicalReferences: [WallpaperReference: WallpaperReference]
    private let favorites: Set<WallpaperReference>
    private let playingReference: WallpaperReference?
    private let switchingReference: WallpaperReference?
    let committedTicket: PlaybackSwitchTicket?

    init(items: [WallpaperContentItem], relationships: UserCollectionsSnapshot,
         committedReference: WallpaperReference?, sequenceTicket: PlaybackSwitchTicket?, runtimeTicket: PlaybackSwitchTicket?,
         additionalReferences: [WallpaperReference] = [],
         pendingReference: WallpaperReference? = nil, pendingSequenceTicket: PlaybackSwitchTicket? = nil,
         pendingRuntimeTicket: PlaybackSwitchTicket? = nil) throws {
        var references = Set(items.map(\.reference) + relationships.favorites.map(\.reference) + additionalReferences)
        if let committedReference { references.insert(committedReference) }
        if let pendingReference { references.insert(pendingReference) }
        let canonical = try WallpaperLibraryQuery.canonicalReferences(references, relationships: relationships)
        canonicalReferences = canonical
        favorites = Set(relationships.favorites.map { canonical[$0.reference] ?? $0.reference })
        if let pendingReference, let pendingSequenceTicket, pendingSequenceTicket == pendingRuntimeTicket {
            switchingReference = canonical[pendingReference] ?? pendingReference
        } else { switchingReference = nil }
        if let committedReference, let sequenceTicket, sequenceTicket == runtimeTicket {
            playingReference = canonical[committedReference] ?? committedReference
            committedTicket = sequenceTicket
        } else {
            playingReference = nil
            committedTicket = nil
        }
    }

    func canonical(_ reference: WallpaperReference) -> WallpaperReference { canonicalReferences[reference] ?? reference }
    func isFavorite(_ reference: WallpaperReference) -> Bool { favorites.contains(canonical(reference)) }
    func favoriteActionState(for content: WallpaperContentItem, canEdit: Bool) -> WallpaperLibraryFavoriteActionState {
        .init(canEdit: canEdit, hasItems: true, allFavorite: isFavorite(content.reference),
            allOrganizable: content.capabilities.contains(.organize))
    }
    func isPlaying(_ reference: WallpaperReference) -> Bool { playingReference == canonical(reference) }
    func isSwitching(_ reference: WallpaperReference) -> Bool { switchingReference == canonical(reference) }
}
