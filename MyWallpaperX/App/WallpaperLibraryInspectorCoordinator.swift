import AppKit
import Combine
import QuickLook
import QuickLookUI

/// One mixed-page Inspector/Quick Look composition. Providers retain metadata,
/// assets and specialized controls; all organization actions carry a fixed ref.
@MainActor final class WallpaperLibraryInspectorCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private struct Inspection {
        let token: InspectorCardToken
        var content: WallpaperContentItem
        let view: NSView
        var isMounted = false
    }
    private let workspace: WallpaperLibraryWorkspace
    private let manager: WallpaperManager
    private let images: SILService
    private let steam: SteamWorkshopService
    private let online: OnlineLibraryService
    private let makePrimaryAction: (WallpaperContentItem) -> (() -> Void)?
    private let makeFavoriteAction: (WallpaperContentItem) -> (() -> Void)?
    private let canOrganize: () -> Bool
    private let onChoosePlaylist: (WallpaperReference, NSView?) -> Void
    var onMoveSelection: ((UInt16) -> Void)?
    private var inspection: Inspection?
    private var subscriptions = Set<AnyCancellable>()
    private var observedResetEpoch: UUID
    private weak var ownedPreviewPanel: QLPreviewPanel?
    private(set) var previewReference: WallpaperReference?
    var isSwitching: ((WallpaperReference) -> Bool)?
    var onOnlineImageAuthor: ((String) -> Void)?
    private(set) var previewURL: URL?

    var inspectedReference: WallpaperReference? { inspection?.content.reference }
    var inspectorToken: InspectorCardToken? { inspection?.token }
    var isPreviewVisible: Bool { ownedPreviewPanel?.isVisible == true && ownedPreviewPanel?.dataSource === self }

    init(workspace: WallpaperLibraryWorkspace, manager: WallpaperManager, images: SILService,
         steam: SteamWorkshopService, online: OnlineLibraryService,
         makePrimaryAction: @escaping (WallpaperContentItem) -> (() -> Void)?,
         makeFavoriteAction: @escaping (WallpaperContentItem) -> (() -> Void)?,
         canOrganize: @escaping () -> Bool,
         availabilityChanges: AnyPublisher<Void, Never>,
         onChoosePlaylist: @escaping (WallpaperReference, NSView?) -> Void) {
        self.workspace = workspace; self.manager = manager; self.images = images
        self.observedResetEpoch = workspace.relationships.resetEpoch
        self.steam = steam; self.online = online
        self.makePrimaryAction = makePrimaryAction; self.makeFavoriteAction = makeFavoriteAction
        self.canOrganize = canOrganize; self.onChoosePlaylist = onChoosePlaylist
        super.init()
        NotificationCenter.default.publisher(for: .inspectorHostDidPresent).receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.mount(note) }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .inspectorHostDidClose).receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.didClose(note) }.store(in: &subscriptions)
        workspace.presentation.$state.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.refreshInspectedContent()
        }.store(in: &subscriptions)
        availabilityChanges.sink { [weak self] in self?.refreshInspectedContent() }.store(in: &subscriptions)
    }

    func inspect(content: WallpaperContentItem) {
        inspect(content: content, artwork: nil, onAuthor: nil)
    }

    func inspectOnlineArtwork(_ artwork: OnlineImageArtwork, onAuthor: ((String) -> Void)? = nil) {
        let content = OnlineImageLibrary.shared.content(for: artwork.firstAssetID.reference) ?? OnlineImageContentProjection.remote(artwork)
        inspect(content: content, artwork: artwork, onAuthor: onAuthor)
    }

    private func inspect(content: WallpaperContentItem, artwork: OnlineImageArtwork?, onAuthor: ((String) -> Void)?) {
        _ = revokeForResetIfNeeded()
        let current = resolved(content)
        if let previous = inspection, previous.content.reference == current.reference,
           previous.content.providerReference == current.providerReference,
           matchesSourceView(previous.view, content: current) {
            inspection?.content = current
            updateActions(on: previous.view, content: current, token: previous.token)
            return
        }
        let replacingVisibleContent = inspection != nil
        if let previous = inspection { releaseSourceInspection(previous.content) }
        let module = module(for: current.providerReference.provider)
        let token = InspectorCardToken(module: module, cardID: current.reference.storageKey + ":" + UUID().uuidString)
        let actions = actions(for: current, token: token)
        let hosted: NSView
        if let assetID = OnlineImageAssetID(reference: current.providerReference) {
            let record = OnlineImageLibrary.shared.record(for: current.providerReference)
            let sourceBase = URL(string: assetID.source == .wallhaven ? "https://wallhaven.cc/w/" : "https://www.pixiv.net/artworks/")!
            let value = artwork ?? OnlineImageArtwork(source: assetID.source, artworkID: assetID.artworkID,
                title: current.title, sourceURL: record?.sourceURL ?? current.metadata.sourceURL ?? sourceBase.appendingPathComponent(assetID.artworkID),
                author: current.metadata.author)
            hosted = OnlineImageInspectorView(artwork: value, library: .shared,
                makeLibraryActions: { [weak self] reference in
                    guard let self, self.inspection?.token == token,
                          let local = OnlineImageLibrary.shared.content(for: reference) else { return nil }
                    return self.actions(for: local, token: token)
                }, onAuthor: onAuthor ?? (assetID.source == .pixiv ? onOnlineImageAuthor : nil), initialPageIndex: assetID.pageIndex)
        } else { hosted = makeView(for: current, actions: actions) }
        inspection = Inspection(token: token, content: current, view: hosted)
        InspectorHostActions.postOpen(module: module, presentation: .infoPanel(cardID: token.cardID,
            title: current.title, subtitle: current.providerReference.provider.libraryDisplayName,
            preferredWidth: current.providerReference.provider == .videoLibrary ? 368 : 356,
            focusPolicy: .preserveCurrentResponder))
        if replacingVisibleContent {
            // Mount in the same native event turn. The host stays presented,
            // while the new token immediately revokes the former view's actions.
            mountCurrentContent()
        }
    }

    /// Called with the accepted fixed-ref selection. Catalog events never open
    /// a hidden Inspector or preview; they can only update an existing lease.
    func syncSelection(content: WallpaperContentItem?, artwork: OnlineImageArtwork? = nil, onAuthor: ((String) -> Void)? = nil) {
        guard let content else { closeInspector(); closePreview(); return }
        if inspection != nil { inspect(content: content, artwork: artwork, onAuthor: onAuthor) }
        if isPreviewVisible { updateVisiblePreview(content: content) }
    }

    func closeInspector() {
        guard let previous = inspection else { return }
        inspection = nil
        releaseSourceInspection(previous.content)
        InspectorHostActions.postClose(module: previous.token.module, cardID: previous.token.cardID)
    }

    private func mount(_ notification: Notification) {
        guard let request = InspectorHostRequest(userInfo: notification.userInfo), let inspection,
              request.token == inspection.token else { return }
        mountCurrentContent()
    }

    private func mountCurrentContent() {
        guard let inspection, !inspection.isMounted else { return }
        self.inspection?.isMounted = true
        InspectorHostActions.postMount(module: inspection.token.module, cardID: inspection.token.cardID, hostedView: inspection.view)
    }

    private func didClose(_ notification: Notification) {
        guard let request = InspectorHostRequest(userInfo: notification.userInfo), let previous = inspection,
              request.token == previous.token else { return }
        inspection = nil
        releaseSourceInspection(previous.content)
    }

    private func releaseSourceInspection(_ content: WallpaperContentItem) {
        if content.providerReference.provider == .steamWorkshop,
           steam.selectedDownloadInspectorItem?.id.utf8.elementsEqual(content.providerReference.sourceID.utf8) == true {
            steam.dismissDownloadInspector()
        }
    }

    private func resolved(_ content: WallpaperContentItem) -> WallpaperContentItem {
        if OnlineImageAssetID(reference: content.providerReference) != nil {
            return OnlineImageLibrary.shared.content(for: content.providerReference) ?? content
        }
        // Server-only browser results retain their original source detail DTO.
        guard content.publishedAvailability != .remote else { return content }
        return (try? workspace.content(for: content.reference)) ?? content
    }

    private func revokeForResetIfNeeded() -> Bool {
        let epoch = workspace.relationships.resetEpoch
        guard epoch != observedResetEpoch else { return false }
        observedResetEpoch = epoch
        closeInspector()
        closePreview()
        return true
    }

    private func refreshInspectedContent() {
        guard !revokeForResetIfNeeded() else { return }
        if let inspection { inspect(content: inspection.content) }
        if let previewReference, isPreviewVisible, let content = try? workspace.content(for: previewReference) {
            updateVisiblePreview(content: content)
        }
    }

    private func actions(for content: WallpaperContentItem, token: InspectorCardToken) -> WallpaperInspectorActions {
        let reference = content.reference
        let relationships = workspace.relationships
        let epoch = relationships.resetEpoch
        let aliases = (try? WallpaperLibraryQuery.canonicalReferences(Set(relationships.members.map(\.reference)).union([reference]),
            relationships: relationships)) ?? [:]
        let canonical = aliases[reference] ?? reference
        let members = relationships.members.filter { (aliases[$0.reference] ?? $0.reference) == canonical }.map(\.playlistID)
        let names = relationships.playlists.filter { members.contains($0.id) }.map(\.name)
        let primary = makePrimaryAction(content)
        let favorite = makeFavoriteAction(content)
        let state = WallpaperInspectorActions.State(isPlaying: workspace.isPlaying(reference), isSwitching: isSwitching?(reference) == true, isFavorite: workspace.isFavorite(reference),
            canPerformPrimary: primary != nil && isSwitching?(reference) != true, canFavorite: favorite != nil,
            canOrganize: canOrganize() && content.capabilities.contains(.organize), playlistNames: names)
        return WallpaperInspectorActions(state: state, onPrimary: { [weak self] in
            guard let self, self.inspection?.token == token, self.workspace.relationships.resetEpoch == epoch else { return }
            primary?()
        }, onToggleFavorite: { [weak self] in
            guard let self, self.inspection?.token == token, self.workspace.relationships.resetEpoch == epoch else { return }
            favorite?()
        }, onChoosePlaylist: { [weak self] anchor in
            guard let self, self.inspection?.token == token, self.workspace.relationships.resetEpoch == epoch, self.canOrganize(),
                  let latest = try? self.workspace.content(for: reference), latest.capabilities.contains(.organize) else { return }
            self.onChoosePlaylist(reference, anchor)
        })
    }

    private func updateActions(on view: NSView, content: WallpaperContentItem, token: InspectorCardToken) {
        let actions = actions(for: content, token: token)
        switch view {
        case let view as VideoLibraryInspectorView: view.updateLibraryActions(actions)
        case let view as SILInspectorView: view.updateLibraryActions(actions)
        case let view as OnlineLibraryDownloadsInspectorView: view.updateLibraryActions(actions)
        case let view as AppKitSteamWorkshopItemDetailView: view.updateLibraryActions(actions)
        case let view as OnlineImageInspectorView: view.updateLibraryActions(actions)
        default: break
        }
    }

    private func matchesSourceView(_ view: NSView, content: WallpaperContentItem) -> Bool {
        let source = content.providerReference
        func matches(_ value: String) -> Bool { value.utf8.elementsEqual(source.sourceID.utf8) }
        switch source.provider {
        case .videoLibrary:
            return manager.wallpapers.contains(where: { matches($0.id) }) ? view is VideoLibraryInspectorView : view is NSStackView
        case .staticImageLibrary:
            return images.wallpapers.contains(where: { matches($0.id) }) ? view is SILInspectorView : view is NSStackView
        case .steamWorkshop:
            return steam.downloads.contains(where: { matches($0.id) }) ? view is AppKitSteamWorkshopItemDetailView : view is NSStackView
        case .pixabay:
            let id = Int(source.sourceID)
            let found = id.map { id in String(id).utf8.elementsEqual(source.sourceID.utf8) && online.downloadedContent.entries.contains { $0.id == id } } ?? false
            return found ? view is OnlineLibraryDownloadsInspectorView : view is NSStackView
        case .wallhaven, .pixiv: return view is OnlineImageInspectorView
        }
    }

    private func makeView(for content: WallpaperContentItem, actions: WallpaperInspectorActions) -> NSView {
        let source = content.providerReference
        func matches(_ value: String) -> Bool { value.utf8.elementsEqual(source.sourceID.utf8) }
        switch source.provider {
        case .videoLibrary:
            if let value = manager.wallpapers.first(where: { matches($0.id) }) {
                return VideoLibraryInspectorView(wallpaper: value, wallpaperManager: manager, libraryActions: actions)
            }
        case .staticImageLibrary:
            if let value = images.wallpapers.first(where: { matches($0.id) }) {
                return SILInspectorView(wallpaper: value, service: images, libraryActions: actions)
            }
        case .steamWorkshop:
            if let record = steam.downloads.first(where: { matches($0.id) }) {
                let item = record.displayItem ?? SteamWorkshopDownloadGridSupport.fallbackDisplayItem(for: record)
                steam.presentDownloadInspector(item)
                return AppKitSteamWorkshopItemDetailView(item: item, service: steam, libraryActions: actions)
            }
        case .pixabay:
            if let id = Int(source.sourceID), String(id).utf8.elementsEqual(source.sourceID.utf8),
               online.downloadedContent.entries.contains(where: { $0.id == id }) {
                return OnlineLibraryDownloadsInspectorView(itemID: id, service: online, libraryActions: actions)
            }
        case .wallhaven, .pixiv: break // Constructed above with the page-aware image identity.
        }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.addArrangedSubview(NSTextField(wrappingLabelWithString: content.title))
        stack.addArrangedSubview(NSTextField(wrappingLabelWithString: "原始文件当前不可用，播放列表中的引用已保留。"))
        if let path = content.locator.path {
            let label = NSTextField(wrappingLabelWithString: path)
            label.isSelectable = true
            stack.addArrangedSubview(label)
        }
        return stack
    }

    private func module(for provider: WallpaperProvider) -> ModuleIdentifier {
        switch provider {
        case .videoLibrary: return .videoLibrary
        case .staticImageLibrary: return .staticImageLibrary
        case .steamWorkshop: return .steamWorkshop
        case .pixabay: return .onlineLibrary
        case .wallhaven: return .wallhaven
        case .pixiv: return .pixiv
        }
    }

    @discardableResult
    func preview(content: WallpaperContentItem) -> Bool {
        _ = revokeForResetIfNeeded()
        let current = resolved(content)
        guard let url = quickLookURL(current) else {
            closePreview()
            inspect(content: current)
            return false
        }
        previewReference = current.reference
        previewURL = url
        guard let panel = QLPreviewPanel.shared() else { return false }
        // The lease changed without a responder change. Let AppKit select the
        // controlling window and invoke its begin callback before writing data.
        panel.makeKeyAndOrderFront(nil)
        panel.updateController()
        guard panel.dataSource === self else {
            previewReference = nil; previewURL = nil
            return false
        }
        panel.reloadData()
        return true
    }

    private func quickLookURL(_ content: WallpaperContentItem) -> URL? {
        guard content.kind == .video || content.kind == .image, content.capabilities.contains(.quickLook),
              let path = content.locator.path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.isReadableFile(atPath: path) else { return nil }
        return url
    }

    private func updateVisiblePreview(content: WallpaperContentItem) {
        guard let panel = ownedPreviewPanel, panel.dataSource === self else { return }
        let current = resolved(content)
        guard let url = quickLookURL(current) else { closePreview(); return }
        guard previewReference != current.reference || previewURL != url else { return }
        previewReference = current.reference
        previewURL = url
        panel.reloadData()
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { previewURL != nil }

    func attach(to panel: QLPreviewPanel) {
        guard previewURL != nil else { return }
        ownedPreviewPanel = panel
        panel.dataSource = self
        panel.delegate = self
    }

    func detach(from panel: QLPreviewPanel) {
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
        if ownedPreviewPanel === panel { ownedPreviewPanel = nil }
    }

    func closePreview() {
        let panel = ownedPreviewPanel
        // Revoke before AppKit's synchronous end/control callbacks. They must
        // not reattach this selection while the panel is being ordered out.
        ownedPreviewPanel = nil
        previewReference = nil
        previewURL = nil
        if let panel {
            if panel.dataSource === self { panel.orderOut(nil) }
            detach(from: panel)
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { previewURL as NSURL? }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        switch event.keyCode {
        case 49, 53: closePreview(); return true
        case 123, 124, 125, 126: onMoveSelection?(event.keyCode); return true
        default: return false
        }
    }
}
