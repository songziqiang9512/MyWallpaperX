import AppKit
import Combine
import QuickLookUI

// ACTUAL_FAVORITE_ACTION_STATE
// ACTUAL_RELATIONSHIP_UNDO_MANAGER

// The actual coordinator, Query, references, Split and native InspectorHost run here.
// Provider detail views record the injected state/actions; their actual layout,
// preview loading and specialized buttons are covered by the nearest view gates.
struct VideoWallpaper { let id: String }
struct SILWallpaper { let id: String }
struct SteamWorkshopBrowserItem { let id: String }
struct SteamWorkshopDownloadRecord { let id: String; var displayItem: SteamWorkshopBrowserItem? }
struct PixabayEntry { let id: Int }
struct PixabaySnapshot { var entries: [PixabayEntry] = [] }
final class WallpaperManager { var wallpapers: [VideoWallpaper] = [] }
final class SILService { var wallpapers: [SILWallpaper] = [] }
final class PixabayService { var downloadedContent = PixabaySnapshot(); var items: [PixabayVideoItem] = [] }
final class SteamWorkshopService {
    var downloads: [SteamWorkshopDownloadRecord] = []
    var selectedDownloadInspectorItem: SteamWorkshopBrowserItem?
    var inspected: [String] = []
    var dismissals = 0
    func presentDownloadInspector(_ item: SteamWorkshopBrowserItem) { selectedDownloadInspectorItem = item; inspected.append(item.id) }
    func dismissDownloadInspector() { selectedDownloadInspectorItem = nil; dismissals += 1 }
}
enum SteamWorkshopDownloadGridSupport {
    static func fallbackDisplayItem(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopBrowserItem { .init(id: record.id) }
}
class RecordingInspectorView: NSView {
    var actions: WallpaperInspectorActions
    private(set) var nativeMounts = 0
    init(_ actions: WallpaperInspectorActions) { self.actions = actions; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    func updateLibraryActions(_ actions: WallpaperInspectorActions) { self.actions = actions }
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview != nil { nativeMounts += 1 }
    }
}
final class VideoLibraryInspectorView: RecordingInspectorView {
    init(wallpaper: VideoWallpaper, wallpaperManager: WallpaperManager, libraryActions: WallpaperInspectorActions) { super.init(libraryActions) }
    required init?(coder: NSCoder) { nil }
}
final class SILInspectorView: RecordingInspectorView {
    init(wallpaper: SILWallpaper, service: SILService, libraryActions: WallpaperInspectorActions) { super.init(libraryActions) }
    required init?(coder: NSCoder) { nil }
}
final class AppKitSteamWorkshopItemDetailView: RecordingInspectorView {
    init(item: SteamWorkshopBrowserItem, service: SteamWorkshopService, libraryActions: WallpaperInspectorActions) { super.init(libraryActions) }
    required init?(coder: NSCoder) { nil }
}
final class PixabayDownloadsInspectorView: RecordingInspectorView {
    private(set) var remoteItem: PixabayVideoItem?
    init(itemID: Int, service: PixabayService, libraryActions: WallpaperInspectorActions, remoteItem: PixabayVideoItem? = nil) {
        self.remoteItem = remoteItem; super.init(libraryActions)
    }
    func updateLibraryActions(_ value: WallpaperInspectorActions, remoteItem: PixabayVideoItem? = nil) {
        actions = value; if let remoteItem { self.remoteItem = remoteItem }
    }
    required init?(coder: NSCoder) { nil }
}
// Source layout/acquisition is a leaf here. The actual Coordinator supplies the
// page identity, DTO and token-bound actions; no detail/preview request is made.
final class OnlineImageInspectorView: NSView {
    let artwork: OnlineImageArtwork
    let initialPageIndex: Int
    let thumbnailPixelSize: Int
    let onAuthor: ((OnlineImageAuthor) -> Void)?
    var actions: WallpaperInspectorActions?
    init(artwork: OnlineImageArtwork, library: OnlineImageLibrary,
         makeLibraryActions: @escaping (WallpaperReference) -> WallpaperInspectorActions?,
         onAuthor: ((OnlineImageAuthor) -> Void)? = nil, initialPageIndex: Int = 0, thumbnailPixelSize: Int = 800) {
        self.artwork = artwork; self.initialPageIndex = initialPageIndex; self.onAuthor = onAuthor; self.thumbnailPixelSize = thumbnailPixelSize
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
    func updateLibraryActions(_ value: WallpaperInspectorActions) { actions = value }
}
private final class ImageSelectionGridLeaf {
    var onSelection: ((Set<WallpaperReference>, WallpaperReference?) -> UUID?)?
    var onEscape: (() -> Void)?
}
private final class ImageSelectionBrowserLeaf {
    private struct Selection {
        var references = Set<WallpaperReference>()
        var focusedReference: WallpaperReference?
        var sessionID = UUID()
    }
    private var selection = Selection()
    var acceptsInput = true
    let grid = ImageSelectionGridLeaf()
    var thumbnailPixelSize = 512
    var contents: [WallpaperReference: WallpaperContentItem] = [:]
    var onSelectionChange: ((WallpaperContentItem?) -> Void)?
    var onEscape: (() -> Void)?
    var selectedContent: WallpaperContentItem? {
        selection.references.count == 1 ? selection.references.first.flatMap { contents[$0] } : nil
    }
    func bindGrid() {
        // ACTUAL_IMAGE_BROWSER_SELECTION
        // ACTUAL_IMAGE_BROWSER_ESCAPE
    }
    func select(_ reference: WallpaperReference?) {
        let references = reference.map { Set([$0]) } ?? []
        _ = grid.onSelection?(references, reference)
    }
}
private final class ImageSelectionSessionLeaf {
    struct State { var items: [OnlineImageArtwork] = [] }
    var state = State()
    var authors: [OnlineImageAuthor] = []
    func openAuthor(_ author: OnlineImageAuthor) { authors.append(author) }
}
private final class ImageSelectionAssemblyProbe {
    let inspector: WallpaperLibraryInspectorCoordinator
    let pixiv = ImageSelectionSessionLeaf()
    init(_ inspector: WallpaperLibraryInspectorCoordinator) { self.inspector = inspector }
    func bind(_ browser: ImageSelectionBrowserLeaf, session: ImageSelectionSessionLeaf, source: OnlineImageSource) {
        let page: WallpaperLibraryPage = source == .pixiv ? .pixiv : .wallhaven
        // ACTUAL_IMAGE_SELECTION_ASSEMBLY
        // ACTUAL_IMAGE_ESCAPE_ASSEMBLY
    }
    // The real App bridge methods are exercised with the real Session by
    // OnlineImageBrowseHarness; this leaf records the Inspector callback only.
    func openAuthor(_ author: OnlineImageAuthor, from page: WallpaperLibraryPage) {
        inspector.closeInspector(); inspector.closePreview(); pixiv.openAuthor(author)
    }
}

/// Only the original-byte transfer leaf is controlled. It intentionally writes
/// after cancellation; real Coordinator generations and QL leases reject it.
@MainActor final class OriginalPreviewLeaf {
    struct Request { let asset: OnlineImageAsset; let destination: URL; let scopeID: String }
    private(set) var requests: [Request] = []
    private var pending: [Int: CheckedContinuation<Void, Error>] = [:]
    func fetch(_ asset: OnlineImageAsset, to destination: URL) async throws {
        let index = requests.count
        requests.append(.init(asset: asset, destination: destination,
            scopeID: OnlineImageLibrary.shared.requestScope(asset.id.source)))
        try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func complete(_ index: Int, bytes: Data) throws {
        guard let continuation = pending.removeValue(forKey: index) else { preconditionFailure("Original response needs a pending request") }
        try bytes.write(to: requests[index].destination)
        continuation.resume()
    }
    func fail(_ index: Int, _ error: Error) {
        guard let continuation = pending.removeValue(forKey: index) else { preconditionFailure("Original failure needs a pending request") }
        continuation.resume(throwing: error)
    }
}
final class WallpaperLibraryWorkspace {
    let presentation = InspectorPresentation()
    let playbackChanges = PassthroughSubject<Void, Never>()
    var relationships = UserCollectionsSnapshot(revision: 0, resetEpoch: UUID(), migrationManifestID: nil,
        playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
    let catalog = InspectorCatalog()
    var playing: WallpaperReference?
    private(set) var contentReads = 0
    func content(for ref: WallpaperReference) throws -> WallpaperContentItem {
        contentReads += 1
        return try WallpaperLibraryQuery.resolve([ref], catalog: catalog.catalog, relationships: relationships)[0]
    }
    func isPlaying(_ ref: WallpaperReference) -> Bool { playing == ref }
    func isFavorite(_ ref: WallpaperReference) -> Bool { relationships.favorites.contains { $0.reference == ref } }
}
final class InspectorProbe: NSObject {
    var mounts: [(InspectorCardToken, NSView)] = []
    var opens: [InspectorHostRequest] = []
    var closes: [Notification] = []
    var observers: [NSObjectProtocol] = []
    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: .inspectorHostOpenRequested, object: nil, queue: .main) { [weak self] note in
            guard let request = InspectorHostRequest(userInfo: note.userInfo) else { return }
            self?.opens.append(request)
        })
        observers.append(NotificationCenter.default.addObserver(forName: .inspectorHostCloseRequested, object: nil, queue: .main) { [weak self] note in
            self?.closes.append(note)
        })
        observers.append(NotificationCenter.default.addObserver(forName: .inspectorHostMountContentRequested, object: nil, queue: .main) { [weak self] note in
            guard let mount = InspectorHostMountRequest(userInfo: note.userInfo) else { return }
            self?.mounts.append((mount.token, mount.hostedView))
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
final class PreviewWindowController: NSWindowController, NSWindowDelegate {
    weak var coordinator: WallpaperLibraryInspectorCoordinator?
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { panel.map { coordinator?.acceptsPreviewPanelControl($0) == true } ?? false }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { if let panel { coordinator?.attach(to: panel) } }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { if let panel { coordinator?.detach(from: panel) } }
}
final class ForeignPreviewOwner: NSObject, QLPreviewPanelDataSource {
    var url: URL!
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { url as NSURL }
}

@main struct WallpaperLibraryInspectorHarness {
    @MainActor static func pump() async { try? await Task.sleep(for: .milliseconds(35)) }
    @MainActor static func waitUntil(_ label: String, receipt: (() -> String)? = nil, _ condition: () -> Bool) async throws {
        for _ in 0..<80 { if condition() { return }; await pump() }
        throw NSError(domain: "InspectorFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out: " + label + (receipt.map { "\n" + $0() } ?? "")])
    }
    @MainActor static func nativeLayoutTurn(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    @MainActor static func main() {
        initializeNativeAppHarness()
        let app = NSApplication.shared
        Task { @MainActor in
            do { try await run() } catch { fputs("\(error)\n", stderr); exit(1) }
            app.stop(nil)
            if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { app.postEvent(wake, atStart: false) }
        }
        app.run()
    }
    @MainActor static func run() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 160, y: 160, width: 1000, height: 680), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let sidebar = NSViewController(), contentController = NSViewController()
        sidebar.view = NSView(); contentController.view = NSView()
        let sidebarTint = AppKitListTintSurface()
        sidebar.view.addSubview(sidebarTint)
        let split = AppKitMainSplitViewController(sidebar: sidebar, content: contentController, sidebarTintHost: sidebarTint)
        window.contentViewController = split
        split.loadViewIfNeeded()
        // Assigning a controller adopts its initial 500 pt view size. Restore
        // the intended real viewport after that native installation completes.
        window.setContentSize(NSSize(width: 1000, height: 680))
        let host = split.children.flatMap(\.children).compactMap { $0 as? InspectorHostViewController }.first!
        let animationHost = host.view.superview!, overlay = animationHost.superview!
        let trailing = overlay.constraints.first {
            ($0.firstItem as? NSView) === animationHost && $0.firstAttribute == .trailing
        }!
        func recordHost(_ stage: String, extra: [String: Any] = [:]) {
            let local = NSPoint(x: 10, y: 10)
            let parentPoint = overlay.convert(local, to: overlay.superview)
            let presentationFrame = animationHost.layer?.presentation()?.frame
            var values: [String: Any] = ["stage": stage, "hostFrame": NSStringFromRect(animationHost.frame),
                "overlayFrame": NSStringFromRect(overlay.frame), "overlayBounds": NSStringFromRect(overlay.bounds),
                "trailing": trailing.constant, "hidden": overlay.isHidden, "hiddenAncestor": overlay.isHiddenOrHasHiddenAncestor,
                "rawHitIsOverlay": overlay.hitTest(local) === overlay,
                "convertedHitIsOverlay": overlay.hitTest(parentPoint) === overlay,
                "parentPoint": NSStringFromPoint(parentPoint),
                "windowVisible": overlay.window?.isVisible == true,
                "presentationFrame": presentationFrame.map { NSStringFromRect($0) } ?? "nil"]
            values.merge(extra, uniquingKeysWith: { _, new in new })
            if let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) {
                FileHandle.standardError.write(data); FileHandle.standardError.write(Data([10]))
            }
        }
        let windowController = PreviewWindowController(window: window)
        defer { withExtendedLifetime(windowController) {} }
        window.delegate = windowController
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        let workspace = WallpaperLibraryWorkspace(), manager = WallpaperManager(), images = SILService(), steam = SteamWorkshopService(), pixabay = PixabayService()
        let video = WallpaperReference(provider: .videoLibrary, sourceID: "v")
        let secondVideo = WallpaperReference(provider: .videoLibrary, sourceID: "v2")
        let image = WallpaperReference(provider: .staticImageLibrary, sourceID: "i")
        let web = WallpaperReference(provider: .steamWorkshop, sourceID: "w")
        let remote = WallpaperReference(provider: .pixabay, sourceID: "7")
        let missing = WallpaperReference(provider: .videoLibrary, sourceID: "missing")
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let file = directory.appendingPathComponent("preview.png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
        func content(_ ref: WallpaperReference, _ kind: WallpaperMediaKind) -> WallpaperContentItem {
            .init(reference: ref, providerReference: ref, locator: .init(path: file.path, titleHint: ref.sourceID, mediaKind: kind), title: ref.sourceID,
                kind: kind, publishedAvailability: .available, capabilities: [.play, .inspect, .organize, .quickLook], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        }
        let videoValue = content(video, .video), secondVideoValue = content(secondVideo, .video), imageValue = content(image, .image), webValue = content(web, .web), remoteValue = content(remote, .video)
        manager.wallpapers = [.init(id: "v"), .init(id: "v2")]; images.wallpapers = [.init(id: "i")]
        steam.downloads = [.init(id: "w")]; pixabay.downloadedContent.entries = [.init(id: 7)]
        workspace.catalog.catalog = .init(videos: [videoValue, secondVideoValue], images: [imageValue], downloads: [webValue, remoteValue])
        var primaryFactoryCalls = 0, primaryGeneration = 0
        var primary: [WallpaperReference] = [], favorites: [WallpaperReference] = [], memberships: [WallpaperReference] = []
        func favoriteState(_ content: WallpaperContentItem, workspace: WallpaperLibraryWorkspace, canEdit: Bool) -> WallpaperLibraryFavoriteActionState {
            .init(canEdit: canEdit, hasItems: true, allFavorite: workspace.isFavorite(content.reference),
                allOrganizable: content.capabilities.contains(.organize))
        }
        let availability = PassthroughSubject<Void, Never>()
        let coordinator = WallpaperLibraryInspectorCoordinator(workspace: workspace, manager: manager, images: images, steam: steam, pixabay: pixabay,
            makePrimaryAction: { content in
                primaryFactoryCalls += 1
                let generation = primaryGeneration
                return { if primaryGeneration == generation { primary.append(content.reference) } }
            }, makeFavoriteAction: { content in
                let action = favoriteState(content, workspace: workspace, canEdit: workspace.presentation.canEditCollections)
                guard action.canExecute else { return nil }
                return {
                    guard let current = try? workspace.content(for: content.reference) else { return }
                    let latest = favoriteState(current, workspace: workspace, canEdit: workspace.presentation.canEditCollections)
                    guard latest.canExecute, latest.isRemoving == action.isRemoving else { return }
                    favorites.append(content.reference)
                }
            }, canOrganize: { workspace.presentation.canEditCollections },
            availabilityChanges: availability.eraseToAnyPublisher(),
            onChoosePlaylist: { ref, _ in memberships.append(ref) })
        windowController.coordinator = coordinator
        let probe = InspectorProbe()
        var checks: [String: Bool] = [:]
        await pump()
        checks["fixed-sidebar-starts-expanded-and-keeps-native-width-limits"] = split.splitViewItems.count == 2
            && !split.splitViewItems[0].canCollapse && !split.splitViewItems[0].isCollapsed
            && split.splitViewItems[0].minimumThickness == 200 && split.splitViewItems[0].maximumThickness == 320
        split.splitView.setPosition(260, ofDividerAt: 0)
        split.view.layoutSubtreeIfNeeded()
        let draggedWidth = sidebar.view.frame.width
        split.toggleSidebar(nil); await pump()
        checks["native-sidebar-toggle-cannot-collapse-or-disable-width-drag"] = !split.splitViewItems[0].isCollapsed
            && abs(draggedWidth - 260) <= 1 && abs(sidebar.view.frame.width - draggedWidth) <= 1
        coordinator.inspect(content: videoValue); await pump()
        let videoToken = coordinator.inspectorToken!
        let videoView = probe.mounts.last!.1 as! VideoLibraryInspectorView
        checks["initial-inspection-prepares-one-action-set-for-the-source-view"] = primaryFactoryCalls == 1
        videoView.actions.onToggleFavorite(); videoView.actions.onChoosePlaylist(nil); videoView.actions.onPrimary()
        checks["video-actions-carry-fixed-ref-and-do-not-copy-source-selection"] = primary == [video] && favorites == [video] && memberships == [video]
        coordinator.inspect(content: videoValue); await pump()
        checks["repeat-inspection-keeps-token-view-and-scroll-owner"] = coordinator.inspectorToken == videoToken && probe.mounts.count == 1
        let priorFactoryCalls = primaryFactoryCalls
        primaryGeneration += 1
        videoView.actions.onPrimary()
        checks["rendered-primary-never-reclassifies-action-on-click"] = primaryFactoryCalls == priorFactoryCalls && primary == [video]
        // Stable-geometry probes start after the real entrance has completed.
        // The later replacement assertions remain synchronous and still reject
        // a replacement that starts another entrance or remounts its content.
        let entranceDeadline = Date().addingTimeInterval(2)
        var entranceSettled = false
        repeat {
            nativeLayoutTurn(split.view)
            let visibleFrame = animationHost.layer?.presentation()?.frame ?? animationHost.frame
            entranceSettled = abs(trailing.constant) <= 0.5
                && abs(animationHost.frame.maxX - overlay.bounds.maxX) <= 0.5
                && abs(visibleFrame.maxX - overlay.bounds.maxX) <= 0.5
            if !entranceSettled { await pump() }
        } while !entranceSettled && Date() < entranceDeadline
        checks["native-inspector-entrance-settles-before-stable-geometry-probes"] = entranceSettled
        let closeCountBeforeReplacement = probe.closes.count
        let hostParent = host.parent, originalTrailing = trailing.constant
        recordHost("before-selected-ref-replacement")
        let dimmingPoint = NSPoint(x: 10, y: 10)
        checks["real-inspector-viewport-leaves-a-native-dimming-hit-outside-the-panel"] = overlay.bounds.width > animationHost.frame.width
            && overlay.bounds.contains(dimmingPoint) && !animationHost.frame.contains(dimmingPoint)
            && overlay.hitTest(overlay.convert(dimmingPoint, to: overlay.superview)) === overlay
        let mountsBeforeReplacement = probe.mounts.count
        coordinator.syncSelection(content: secondVideoValue)
        let secondView = probe.mounts.last!.1 as! VideoLibraryInspectorView
        checks["selected-ref-replacement-mounts-in-the-same-real-host-turn"] = coordinator.inspectedReference == secondVideo
            && coordinator.inspectorToken != videoToken && host.parent === hostParent && !overlay.isHidden
            && secondView.isDescendant(of: host.view) && videoView.superview == nil
            && probe.mounts.count == mountsBeforeReplacement + 1 && probe.closes.count == closeCountBeforeReplacement
            && trailing.constant == originalTrailing
        await pump(); split.view.layoutSubtreeIfNeeded()
        recordHost("after-selected-ref-replacement", extra: ["nativeMounts": secondView.nativeMounts,
            "originalTrailing": originalTrailing, "edgeDelta": animationHost.frame.maxX - overlay.bounds.maxX])
        checks["replacement-does-not-reenter-slide-or-remount-after-late-present-echo"] = secondView.nativeMounts == 1
            && abs(animationHost.frame.maxX - overlay.bounds.maxX) <= 0.5
            && overlay.hitTest(NSPoint(x: 10, y: 10)) === overlay
        coordinator.syncSelection(content: videoValue); await pump()
        coordinator.inspect(content: webValue); await pump()
        let webToken = coordinator.inspectorToken!
        let webView = probe.mounts.last!.1 as! AppKitSteamWorkshopItemDetailView
        checks["steam-reuses-source-detail-and-refresh-owner"] = steam.inspected == ["w"] && coordinator.inspectedReference == web
        split.view.layoutSubtreeIfNeeded()
        checks["cross-provider-content-keeps-host-and-updates-native-panel-width"] = host.parent === hostParent
            && webView.isDescendant(of: host.view) && !overlay.isHidden && probe.closes.count == closeCountBeforeReplacement
            && abs(animationHost.frame.width - (356 + 24)) <= 0.5
            && abs(animationHost.frame.maxX - overlay.bounds.maxX) <= 0.5
        videoView.actions.onPrimary(); videoView.actions.onToggleFavorite(); videoView.actions.onChoosePlaylist(nil)
        checks["old-provider-buttons-cannot-act-on-new-inspection"] = primary == [video] && favorites == [video] && memberships == [video]
        let obsolete = probe.opens.first!
        NotificationCenter.default.post(name: .inspectorHostDidPresent, object: nil, userInfo: obsolete.userInfo)
        NotificationCenter.default.post(name: .inspectorHostDidClose, object: nil, userInfo: obsolete.userInfo)
        await pump()
        checks["late-host-mount-close-cannot-touch-new-token"] = coordinator.inspectorToken == webToken && probe.mounts.last!.0 == webToken
        coordinator.inspect(content: imageValue); await pump()
        checks["switching-provider-releases-only-matching-steam-detail"] = steam.dismissals == 1 && probe.mounts.last!.1 is SILInspectorView
        webView.actions.onPrimary()
        checks["removed-steam-footer-cannot-start-late-playback"] = primary == [video]
        coordinator.inspect(content: remoteValue); await pump()
        checks["pixabay-keeps-its-original-inspector-type"] = probe.mounts.last!.1 is PixabayDownloadsInspectorView
        coordinator.inspect(content: content(missing, .video)); await pump()
        checks["missing-source-keeps-an-inspectable-unavailable-reference"] = probe.mounts.last!.1 is NSStackView && coordinator.inspectedReference == missing
        manager.wallpapers.append(.init(id: "missing")); workspace.catalog.catalog.videos.append(content(missing, .video))
        workspace.publishPresentation(); await pump()
        checks["same-ref-source-recovery-replaces-placeholder-with-original-detail"] = probe.mounts.last!.1 is VideoLibraryInspectorView
        let restoredView = probe.mounts.last!.1 as! VideoLibraryInspectorView
        workspace.presentation.canEditCollections = false; workspace.publishPresentation(); await pump()
        restoredView.actions.onToggleFavorite(); restoredView.actions.onChoosePlaylist(nil)
        checks["recovery-readonly-disables-all-organization-actions"] = !restoredView.actions.state.canFavorite
            && !restoredView.actions.state.canOrganize && favorites == [video] && memberships == [video]
        coordinator.closeInspector(); await pump()
        let openCount = probe.opens.count
        workspace.publishPresentation(); await pump()
        checks["catalog-publish-never-reopens-closed-inspector"] = coordinator.inspectorToken == nil && probe.opens.count == openCount
        workspace.presentation.canEditCollections = true
        let list = WallpaperPlaylist(name: "Mixed", sidebarRank: 0)
        workspace.relationships = .init(revision: 1, resetEpoch: workspace.relationships.resetEpoch, migrationManifestID: nil,
            playlists: [list], members: [.init(playlistID: list.id, reference: video, position: 0, addedAt: Date())], favorites: [], recent: [],
            aliases: [.init(alias: video, canonical: remote, proof: .publishedDownload)], locators: [])
        coordinator.inspect(content: videoValue); await pump()
        let aliasView = probe.mounts.last!.1 as! PixabayDownloadsInspectorView
        checks["trusted-alias-routes-detail-to-current-provider-and-shows-canonical-membership"] = coordinator.inspectedReference == remote && aliasView.actions.state.playlistNames == ["Mixed"]
        aliasView.actions.onChoosePlaylist(nil)
        checks["alias-organization-action-uses-canonical-ref"] = memberships == [video, remote]
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        let keyDeadline = Date().addingTimeInterval(2)
        while (!app.isActive || !window.isKeyWindow), Date() < keyDeadline { await pump() }
        checks["native-preview-window-has-real-appkit-control"] = app.isActive && window.isKeyWindow
        var arrows: [UInt16] = []
        coordinator.onMoveSelection = { arrows.append($0) }
        checks["native-quicklook-opens-local-video-url"] = coordinator.preview(content: remoteValue) && coordinator.previewReference == remote && coordinator.previewURL == file
        await pump()
        let panel = QLPreviewPanel.shared()!
        checks["native-quicklook-datasource-and-delegate-have-one-current-owner"] = panel.dataSource === coordinator && panel.delegate === coordinator && coordinator.numberOfPreviewItems(in: panel) == 1
        checks["native-quicklook-has-the-real-window-as-its-controller"] = panel.currentController as AnyObject === windowController
        coordinator.syncSelection(content: imageValue); await pump()
        checks["cross-provider-preview-retains-same-native-owner-and-new-fixed-ref"] = panel.dataSource === coordinator && coordinator.previewReference == image
        let arrow = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124)!
        checks["quicklook-arrow-delegates-to-current-grid-not-source-global-selection"] = coordinator.previewPanel(panel, handle: arrow) && arrows == [124]
        let library = OnlineImageLibrary.shared
        library.root = directory
        let imageIDs = [OnlineImageAssetID(source: .pixiv, artworkID: "42"), .init(source: .pixiv, artworkID: "42", pageIndex: 2),
                        .init(source: .pixiv, artworkID: "43")]
        let imageRecords = try imageIDs.enumerated().map { index, id in
            let relativePath = "online-\(index).png"
            try Data(contentsOf: file).write(to: directory.appendingPathComponent(relativePath))
            return OnlineImageLocalRecord(assetID: id, title: id.artworkID, sourceURL: URL(string: "https://example.invalid/" + id.artworkID)!,
                author: "artist", authorID: "77", tags: [], relativePath: relativePath, pixelWidth: 8, pixelHeight: 8,
                fileSizeBytes: 1, firstDownloadedAt: Date(), revision: UUID())
        }
        library.snapshot = .init(records: imageRecords)
        let imageContents = imageRecords.map { OnlineImageContentProjection.local($0, url: library.localURL(for: $0)!, available: true) }
        workspace.catalog.catalog.downloads += imageContents
        var localAuthors: [OnlineImageAuthor] = []
        coordinator.onOnlineImageAuthor = { localAuthors.append($0) }
        coordinator.inspect(content: imageContents[1]); await pump()
        let pageView = probe.mounts.last!.1 as! OnlineImageInspectorView
        checks["downloaded-pixiv-page-keeps-page-reference-and-inspector-index"] = coordinator.inspectedReference == imageIDs[1].reference
            && pageView.initialPageIndex == 2 && pageView.artwork.artworkID == "42"
        let localAuthor = OnlineImageAuthor(source: .pixiv, id: "77", name: "artist")
        pageView.onAuthor?(localAuthor)
        checks["local-pixiv-inspector-uses-injected-author-navigation-without-browse-dto"] = pageView.onAuthor != nil && localAuthors == [localAuthor]
        let shells = ["42", "43", "44"].map { id in
            OnlineImageArtwork(source: .pixiv, artworkID: id, title: "remote-" + id,
                sourceURL: URL(string: "https://example.invalid/" + id)!, author: "remote artist", authorID: "88", kind: .image)
        }
        let browser = ImageSelectionBrowserLeaf(), assembly = ImageSelectionAssemblyProbe(coordinator)
        assembly.pixiv.state.items = shells
        browser.contents = Dictionary(imageContents.map { ($0.reference, $0) }, uniquingKeysWith: { _, newer in newer })
        let remoteImage = OnlineImageContentProjection.remote(shells[2])
        browser.contents[remoteImage.reference] = remoteImage
        browser.bindGrid(); assembly.bind(browser, session: assembly.pixiv, source: .pixiv)
        coordinator.inspectOnlineArtwork(shells[0]); await pump()
        _ = coordinator.preview(content: imageContents[0]); await pump()
        coordinator.onMoveSelection = { _ in browser.select(imageIDs[2].reference) }
        _ = coordinator.previewPanel(panel, handle: arrow); await pump()
        let selectedImageView = probe.mounts.last!.1 as! OnlineImageInspectorView
        checks["real-image-selection-callback-updates-existing-quicklook-fixed-reference"] = coordinator.previewReference == imageIDs[2].reference
            && coordinator.previewURL == library.localURL(for: imageRecords[2]) && panel.dataSource === coordinator
        checks["image-selection-sync-preserves-real-artwork-and-author-callback"] = selectedImageView.artwork == shells[1]
            && selectedImageView.initialPageIndex == 0 && selectedImageView.onAuthor != nil && selectedImageView.thumbnailPixelSize == browser.thumbnailPixelSize
        let acceptedImageReference = browser.selectedContent?.reference
        let acceptedImageToken = coordinator.inspectorToken
        browser.acceptsInput = false
        browser.select(remoteImage.reference); await pump()
        checks["image-selection-callback-keeps-current-preview-and-inspector-while-modal-input-is-blocked"] = browser.selectedContent?.reference == acceptedImageReference
            && coordinator.inspectorToken == acceptedImageToken && coordinator.previewReference == imageIDs[2].reference
        browser.acceptsInput = true
        let remoteAuthor = OnlineImageAuthor(source: .pixiv, id: "88", name: "remote artist")
        selectedImageView.onAuthor?(remoteAuthor)
        checks["image-selection-author-action-keeps-the-existing-source-session"] = assembly.pixiv.authors == [remoteAuthor]
        _ = coordinator.preview(content: imageContents[2]); await pump()
        browser.select(remoteImage.reference); await pump()
        checks["image-selection-without-local-preview-closes-existing-quicklook"] = coordinator.previewURL == nil && panel.dataSource !== coordinator
        _ = coordinator.preview(content: imageContents[2]); await pump()
        browser.select(nil); await pump()
        checks["empty-image-selection-callback-closes-inspector-and-quicklook"] = coordinator.previewURL == nil && coordinator.inspectorToken == nil
            && panel.dataSource !== coordinator
        let stableSelection = Set([imageIDs[0].reference])
        let initialSelectionToken = browser.grid.onSelection?(stableSelection, imageIDs[0].reference)
        let repeatedSelectionToken = browser.grid.onSelection?(stableSelection, imageIDs[0].reference)
        let changedFocusToken = browser.grid.onSelection?(stableSelection, nil)
        let changedReferencesToken = browser.grid.onSelection?(Set([imageIDs[2].reference]), nil)
        checks["image-selection-session-token-is-stable-for-identical-references-and-focus"] = initialSelectionToken != nil
            && repeatedSelectionToken == initialSelectionToken
        checks["image-selection-session-token-revokes-old-focus-only-actions"] = changedFocusToken != nil
            && changedFocusToken != repeatedSelectionToken
        checks["image-selection-session-token-revokes-old-reference-only-actions"] = changedReferencesToken != nil
            && changedReferencesToken != changedFocusToken
        library.snapshot = .init()

        let originals = OriginalPreviewLeaf()
        defer { originals.requests.forEach { try? FileManager.default.removeItem(at: $0.destination) } }
        let originalBytes = try Data(contentsOf: file) + Data("original metadata bytes must survive QL".utf8)
        func originalURL(_ content: WallpaperContentItem) -> URL {
            let suffix = content.title.contains("Updated") ? "-revision-2" : ""
            return URL(string: "https://i.pximg.net/original-\(content.providerReference.sourceID)\(suffix).png")!
        }
        let defaultAssetResolver: (OnlineImageArtwork) async throws -> [OnlineImageAsset] = { artwork in
            let id = OnlineImageAssetID(source: artwork.source, artworkID: artwork.artworkID)
            let suffix = artwork.title.contains("Updated") ? "-revision-2" : ""
            return [.init(id: id, title: artwork.title, sourceURL: artwork.sourceURL,
                originalURL: URL(string: "https://i.pximg.net/original-\(id.reference.sourceID)\(suffix).png")!)]
        }
        library.assetResolver = defaultAssetResolver
        library.originalFetcher = { asset, url in try await originals.fetch(asset, to: url) }
        let remoteA = OnlineImageContentProjection.remote(.init(source: .pixiv, artworkID: "900", title: "Remote A",
            sourceURL: URL(string: "https://www.pixiv.net/artworks/900")!,
            previewURL: URL(string: "https://i.pximg.net/fixture-A.jpg"), kind: .image))
        let remoteB = OnlineImageContentProjection.remote(.init(source: .pixiv, artworkID: "901", title: "Remote B",
            sourceURL: URL(string: "https://www.pixiv.net/artworks/901")!,
            previewURL: URL(string: "https://i.pximg.net/fixture-B.jpg"), kind: .image))
        func remotePreviewReceipt(_ expected: URL? = nil) -> String {
            let frontmost = NSWorkspace.shared.frontmostApplication, url = coordinator.previewURL
            return "appActive=\(app.isActive), frontmost=\(frontmost?.bundleIdentifier ?? "nil"), pid=\(frontmost?.processIdentifier ?? -1), "
                + "host=\(window.windowNumber), visible=\(window.isVisible), key=\(window.isKeyWindow), owner=\(window.windowController === windowController), appKey=\(app.keyWindow?.windowNumber ?? -1), appMain=\(app.mainWindow?.windowNumber ?? -1), "
                + "panel=\(panel.windowNumber), visible=\(panel.isVisible), key=\(panel.isKeyWindow), source=\(String(describing: panel.dataSource)), delegate=\(String(describing: panel.delegate)), ownedVisible=\(coordinator.isPreviewVisible), "
                + "reference=\(coordinator.previewReference?.storageKey ?? "nil"), url=\(url?.path ?? "nil"), expected=\(expected?.path ?? "nil"), bytesMatch=\(url.flatMap { try? Data(contentsOf: $0) } == originalBytes)"
        }
        let beforeQuick = (primary.count, library.downloads.count, library.retries.count, library.snapshot.records.count)
        let beforeQuickSnapshot = library.snapshot, beforeQuickProgress = library.progress, beforeQuickThumbnails = library.thumbnailRequests.count
        coordinator.closePreview()
        window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        try await waitUntil("remote preview active/key fixture admission", receipt: { remotePreviewReceipt() }) { app.isActive && window.isKeyWindow }
        let initialPreviewCount = originals.requests.count
        library.previewPreparation = { library.scopes[.pixiv] = "fixture-restored-cookie-scope"; library.previewPreparation = nil }
        checks["remote-quicklook-is-admitted-without-library-download-or-publication"] = coordinator.preview(content: remoteA)
            && coordinator.previewReference == remoteA.reference && coordinator.previewURL == nil
        try await waitUntil("remote preview A request") { originals.requests.count == initialPreviewCount + 1 }
        let requestA = initialPreviewCount
        checks["remote-quicklook-resolves-the-exact-original-asset-instead-of-the-thumbnail"] = originals.requests[requestA].asset.originalURL == originalURL(remoteA)
            && originals.requests[requestA].asset.originalURL != remoteA.metadata.previewURL
            && originals.requests[requestA].asset.id.reference == remoteA.providerReference && originals.requests[requestA].scopeID == "fixture-restored-cookie-scope"
        coordinator.syncSelection(content: remoteB); await pump()
        checks["selection-during-original-fetch-keeps-one-pending-owner-and-loading-reference"] = originals.requests.count == initialPreviewCount + 1
            && coordinator.previewReference == remoteA.reference && coordinator.loadingPreviewReference == remoteA.reference
        _ = coordinator.preview(content: remoteB); await pump()
        checks["second-space-cancels-pending-original-without-starting-the-new-selection"] = originals.requests.count == initialPreviewCount + 1
            && coordinator.previewReference == nil && coordinator.loadingPreviewReference == nil
        try originals.complete(requestA, bytes: originalBytes); await pump()
        checks["cancelled-original-cannot-open-after-selection-moves-to-B"] = coordinator.previewReference == nil
            && coordinator.previewURL == nil && !coordinator.isPreviewVisible
        _ = coordinator.preview(content: remoteB)
        try await waitUntil("remote preview B request") { originals.requests.count == initialPreviewCount + 2 }
        let requestB = initialPreviewCount + 1
        try originals.complete(requestB, bytes: originalBytes)
        let expectedTemporaryB = originals.requests[requestB].destination
        try await waitUntil("remote preview B original bytes publication", receipt: { remotePreviewReceipt(expectedTemporaryB) }) {
            coordinator.previewReference == remoteB.reference && coordinator.previewURL == expectedTemporaryB && (try? Data(contentsOf: expectedTemporaryB)) == originalBytes
        }
        try await waitUntil("remote preview B native panel", receipt: { remotePreviewReceipt(expectedTemporaryB) }) { coordinator.isPreviewVisible && panel.dataSource === coordinator && panel.delegate === coordinator }
        let temporaryB = coordinator.previewURL!
        checks["remote-preview-publishes-original-bytes-through-the-existing-quicklook-owner"] = coordinator.previewReference == remoteB.reference
            && temporaryB.pathExtension == originals.requests[requestB].asset.originalURL.pathExtension
            && (try? Data(contentsOf: temporaryB)) == originalBytes
            && panel.dataSource === coordinator && panel.delegate === coordinator && coordinator.numberOfPreviewItems(in: panel) == 1
        let acceptedCount = originals.requests.count
        _ = coordinator.preview(content: remoteB); await pump()
        checks["repeated-explicit-preview-reuses-the-current-lease"] = originals.requests.count == acceptedCount
            && coordinator.previewURL == temporaryB && coordinator.isPreviewVisible
        workspace.publishPresentation(); availability.send(); await pump()
        checks["unrelated-catalog-and-relationship-echo-retains-remote-original-preview"] = originals.requests.count == acceptedCount
            && coordinator.previewURL == temporaryB && coordinator.isPreviewVisible && panel.dataSource === coordinator
        coordinator.closePreview()
        checks["closing-remote-preview-keeps-cache-bytes-and-revokes-only-the-panel-lease"] = FileManager.default.fileExists(atPath: temporaryB.path)
            && FileManager.default.isReadableFile(atPath: file.path) && coordinator.previewURL == nil

        _ = coordinator.preview(content: remoteA)
        try await waitUntil("remote close request") { originals.requests.count == acceptedCount + 1 }
        let cancelledForClear = coordinator.closePreviewForCacheClear()
        try originals.complete(acceptedCount, bytes: originalBytes); await cancelledForClear?.value; await pump()
        checks["closing-a-pending-remote-preview-prevents-late-reopening"] = cancelledForClear != nil && coordinator.previewReference == nil
            && coordinator.previewURL == nil && !coordinator.isPreviewVisible

        _ = coordinator.preview(content: remoteA)
        try await waitUntil("remote scope request") { originals.requests.count == acceptedCount + 2 }
        let scopeRequest = acceptedCount + 1
        let oldScope = library.requestScope(.pixiv)
        library.scopes[.pixiv] = "fixture-pixiv-next"
        coordinator.revokeRemotePreview(source: .pixiv)
        try originals.complete(scopeRequest, bytes: originalBytes); await pump()
        checks["scope-revocation-rejects-late-remote-preview-without-a-native-panel"] = originals.requests[scopeRequest].scopeID == oldScope
            && coordinator.previewReference == nil && coordinator.previewURL == nil && !coordinator.isPreviewVisible

        _ = coordinator.preview(content: remoteB)
        try await waitUntil("new remote scope request") { originals.requests.count == acceptedCount + 3 }
        let newScopeRequest = acceptedCount + 2
        try originals.complete(newScopeRequest, bytes: originalBytes)
        try await waitUntil("new scope preview") { coordinator.isPreviewVisible && coordinator.previewURL != nil }
        let newScopeTemporary = coordinator.previewURL!
        checks["new-source-scope-can-explicitly-open-its-own-preview"] = originals.requests[newScopeRequest].scopeID == library.requestScope(.pixiv)
            && coordinator.previewReference == remoteB.reference
        coordinator.syncSelection(content: nil)
        checks["clearing-selection-releases-remote-preview-and-retains-cache-image"] = coordinator.previewReference == nil
            && coordinator.previewURL == nil && FileManager.default.fileExists(atPath: newScopeTemporary.path)

        _ = coordinator.preview(content: remoteA)
        try await waitUntil("remote selection-clear request") { originals.requests.count == acceptedCount + 4 }
        coordinator.syncSelection(content: nil)
        try originals.complete(acceptedCount + 3, bytes: originalBytes); await pump()
        checks["clearing-selection-while-remote-preview-is-pending-cannot-reopen"] = coordinator.previewReference == nil
            && coordinator.previewURL == nil && !coordinator.isPreviewVisible

        // Keep cancelled A held while explicit B becomes visible, then close
        // the real native panel and reject A's late completion.
        let nativeCloseStart = originals.requests.count
        _ = coordinator.preview(content: remoteA)
        try await waitUntil("native-close old A request") { originals.requests.count == nativeCloseStart + 1 }
        coordinator.syncSelection(content: remoteB)
        _ = coordinator.preview(content: remoteB); _ = coordinator.preview(content: remoteB)
        try await waitUntil("native-close B request") { originals.requests.count == nativeCloseStart + 2 }
        try originals.complete(nativeCloseStart + 1, bytes: originalBytes)
        do {
            try await waitUntil("native-close B panel") { coordinator.isPreviewVisible && coordinator.previewURL != nil }
        } catch {
            let diagnostics: [String: Any] = ["stage": "native-close-B-timeout",
                "previewReference": coordinator.previewReference?.storageKey ?? "nil", "previewURL": coordinator.previewURL?.path ?? "nil",
                "previewVisible": coordinator.isPreviewVisible, "panelVisible": panel.isVisible,
                "panelOwnDataSource": panel.dataSource === coordinator, "panelOwnDelegate": panel.delegate === coordinator,
                "panelOwnController": panel.currentController as AnyObject === windowController,
                "mainWindowKey": window.isKeyWindow, "keyWindowType": String(describing: app.keyWindow.map { type(of: $0) }),
                "localReferences": library.snapshot.records.map { $0.assetID.reference.storageKey },
                "requests": originals.requests.map { ["url": $0.asset.originalURL.absoluteString, "scope": $0.scopeID] },
                "scope": library.requestScope(.pixiv), "errors": workspace.presentation.errors]
            FileHandle.standardError.write(try JSONSerialization.data(withJSONObject: diagnostics, options: [.sortedKeys]))
            FileHandle.standardError.write(Data([10]))
            throw error
        }
        let nativeCloseTemporary = coordinator.previewURL!
        panel.performClose(nil)
        for _ in 0..<30 {
            if coordinator.previewURL == nil { break }
            await pump()
        }
        checks["native-quicklook-close-revokes-remote-lease-and-retains-original-cache"] = coordinator.previewReference == nil
            && coordinator.previewURL == nil && FileManager.default.fileExists(atPath: nativeCloseTemporary.path)
        try originals.complete(nativeCloseStart, bytes: originalBytes); await pump()
        checks["native-quicklook-close-cannot-be-undone-by-an-older-pending-preview"] = coordinator.previewReference == nil
            && coordinator.previewURL == nil && !coordinator.isPreviewVisible
        // A failed native-close assertion must not leave its evidence file or
        // panel behind and prevent the remaining local-preview checks.
        coordinator.closePreview()

        let escapedRequest = originals.requests.count
        _ = coordinator.preview(content: remoteA)
        try await waitUntil("real-source-Escape pending request") { originals.requests.count == escapedRequest + 1 }
        browser.acceptsInput = false
        browser.grid.onEscape?()
        checks["blocked-source-grid-Escape-does-not-cancel-background-page-state"] = coordinator.previewReference == remoteA.reference
        browser.acceptsInput = true
        browser.grid.onEscape?()
        try originals.complete(escapedRequest, bytes: originalBytes); await pump()
        checks["actual-source-grid-and-App-Escape-consumers-cancel-pending-quicklook"] = coordinator.previewReference == nil
            && coordinator.previewURL == nil && !coordinator.isPreviewVisible

        let changedRemoteA = OnlineImageContentProjection.remote(.init(source: .pixiv, artworkID: "900", title: "Updated remote A",
            sourceURL: URL(string: "https://www.pixiv.net/artworks/900")!,
            previewURL: URL(string: "https://i.pximg.net/fixture-A-revision-2.jpg"), kind: .image))
        let changedResourceStart = originals.requests.count
        _ = coordinator.preview(content: remoteA)
        try await waitUntil("old resource pending") { originals.requests.count == changedResourceStart + 1 }
        _ = coordinator.preview(content: changedRemoteA); _ = coordinator.preview(content: changedRemoteA)
        try await waitUntil("same-reference new resource request") { originals.requests.count == changedResourceStart + 2 }
        try originals.complete(changedResourceStart, bytes: originalBytes); await pump()
        checks["explicit-same-reference-preview-replaces-a-changed-resource-URL"] = coordinator.previewReference == changedRemoteA.reference
            && coordinator.previewURL == nil && originals.requests[changedResourceStart + 1].asset.originalURL == originalURL(changedRemoteA)
        try originals.complete(changedResourceStart + 1, bytes: originalBytes)
        try await waitUntil("changed resource native preview") { coordinator.isPreviewVisible && coordinator.previewURL != nil }
        let changedResourceTemporary = coordinator.previewURL!
        coordinator.syncSelection(content: remoteA)
        try await waitUntil("selection consumer changed resource") { originals.requests.count == changedResourceStart + 3 }
        checks["same-reference-selection-keeps-the-visible-file-until-replacement-is-ready"] = FileManager.default.fileExists(atPath: changedResourceTemporary.path)
            && originals.requests[changedResourceStart + 2].asset.originalURL == originalURL(remoteA)
        try originals.complete(changedResourceStart + 2, bytes: originalBytes)
        try await waitUntil("selection resource native preview") {
            coordinator.isPreviewVisible && coordinator.previewURL != nil && coordinator.previewURL != changedResourceTemporary
        }
        checks["same-reference-selection-keeps-cached-bytes-after-native-replacement"] = FileManager.default.fileExists(atPath: changedResourceTemporary.path)
        coordinator.closePreview()
        let abaStart = originals.requests.count
        for (index, value) in [remoteA, remoteB, remoteA].enumerated() {
            coordinator.closePreview()
            _ = coordinator.preview(content: value)
            try await waitUntil("A-B-A original admitted") { originals.requests.count == abaStart + index + 1 }
        }
        try originals.complete(abaStart, bytes: originalBytes); try originals.complete(abaStart + 1, bytes: originalBytes); await pump()
        checks["old-A-original-cannot-satisfy-a-new-A-generation-after-A-B-A"] = coordinator.previewReference == remoteA.reference
            && coordinator.previewURL == nil && !FileManager.default.fileExists(atPath: originals.requests[abaStart].destination.path)
        try originals.complete(abaStart + 2, bytes: originalBytes)
        try await waitUntil("new A original is the QL lease") { coordinator.previewURL == originals.requests[abaStart + 2].destination }
        coordinator.closePreview()
        var heldAssets: CheckedContinuation<[OnlineImageAsset], Error>?
        library.assetResolver = { _ in try await withCheckedThrowingContinuation { heldAssets = $0 } }
        let beforeResolveScope = originals.requests.count, errorsBeforeResolveScope = workspace.presentation.errors.count
        _ = coordinator.preview(content: remoteA)
        try await waitUntil("original resolver held before scope change") { heldAssets != nil }
        library.scopes[.pixiv] = "scope-changed-during-resolution"
        heldAssets!.resume(returning: try await defaultAssetResolver(.init(source: .pixiv, artworkID: "900", title: "Remote A", sourceURL: remoteA.metadata.sourceURL!)))
        try await waitUntil("old resolver scope retires QL") { coordinator.previewReference == nil }
        checks["old-original-resolution-cannot-borrow-a-new-account-scope-or-start-transfer"] = originals.requests.count == beforeResolveScope
            && workspace.presentation.errors.count == errorsBeforeResolveScope && !coordinator.isPreviewVisible
        library.assetResolver = defaultAssetResolver
        let fetchScopeStart = originals.requests.count
        _ = coordinator.preview(content: remoteA)
        try await waitUntil("original transfer held before scope change") { originals.requests.count == fetchScopeStart + 1 }
        library.scopes[.pixiv] = "scope-changed-during-original-transfer"
        try originals.complete(fetchScopeStart, bytes: originalBytes)
        try await waitUntil("old transfer scope retires QL") { coordinator.previewReference == nil }
        checks["old-original-transfer-cannot-open-in-a-new-account-scope"] = !coordinator.isPreviewVisible
            && coordinator.previewReference == nil && coordinator.loadingPreviewReference == nil
        let pageID = OnlineImageAssetID(source: .pixiv, artworkID: "902", pageIndex: 2)
        let pageTwo = WallpaperContentItem(reference: pageID.reference, providerReference: pageID.reference,
            locator: .init(mediaKind: .image), title: "Page two", kind: .image, publishedAvailability: .remote,
            capabilities: [.inspect, .quickLook, .download], metadata: .init(sourceURL: URL(string: "https://www.pixiv.net/artworks/902")), acquisition: .idle, update: .idle, aliases: [])
        library.assetResolver = { art in [0, 2].map { .init(id: .init(source: .pixiv, artworkID: art.artworkID, pageIndex: $0),
            title: art.title, sourceURL: art.sourceURL, originalURL: URL(string: "https://i.pximg.net/original-page-\($0).png")!) } }
        let exactPageStart = originals.requests.count
        _ = coordinator.preview(content: pageTwo)
        try await waitUntil("exact original page request") { originals.requests.count == exactPageStart + 1 }
        checks["remote-QL-selects-the-requested-page-even-when-page-zero-comes-first"] = originals.requests[exactPageStart].asset.id == pageID
        try originals.complete(exactPageStart, bytes: originalBytes)
        try await waitUntil("exact original page is visible") { coordinator.previewURL == originals.requests[exactPageStart].destination }
        coordinator.closePreview()
        library.assetResolver = { _ in [] }
        let beforeMissingPage = originals.requests.count, errorsBeforeMissingPage = workspace.presentation.errors.count
        _ = coordinator.preview(content: pageTwo)
        try await waitUntil("missing original page reports failure") { workspace.presentation.errors.count == errorsBeforeMissingPage + 1 }
        checks["missing-original-page-does-not-fall-back-to-another-page-or-thumbnail"] = originals.requests.count == beforeMissingPage
            && coordinator.previewReference == nil && coordinator.previewURL == nil
        library.assetResolver = defaultAssetResolver
        let failStart = originals.requests.count, errorsBeforeOriginalFailure = workspace.presentation.errors.count
        _ = coordinator.preview(content: remoteB)
        try await waitUntil("original transfer failure request") { originals.requests.count == failStart + 1 }
        originals.fail(failStart, OnlineImageError.message("owned original transfer failure"))
        try await waitUntil("original transfer error belongs to this request") { workspace.presentation.errors.count == errorsBeforeOriginalFailure + 1 }
        checks["original-transfer-failure-ends-the-request-and-reports-its-real-error"] = coordinator.previewReference == nil
            && coordinator.previewURL == nil && workspace.presentation.errors.last == "owned original transfer failure"
        checks["remote-preview-never-downloads-applies-or-publishes-a-local-record"] = primary.count == beforeQuick.0
            && library.downloads.count == beforeQuick.1 && library.retries.count == beforeQuick.2
            && library.snapshot.records.count == beforeQuick.3 && library.downloadApplyFlags.isEmpty
            && library.snapshot == beforeQuickSnapshot && library.progress == beforeQuickProgress
            && library.thumbnailRequests.count == beforeQuickThumbnails

        func publishLocalPreview(_ remote: WallpaperContentItem) throws -> URL {
            let id = OnlineImageAssetID(reference: remote.providerReference)!
            let path = "published-preview-\(id.artworkID).png"
            let url = directory.appendingPathComponent(path)
            try Data(contentsOf: file).write(to: url)
            let record = OnlineImageLocalRecord(assetID: id, title: remote.title, sourceURL: remote.metadata.sourceURL!,
                author: nil, authorID: nil, tags: [], relativePath: path, pixelWidth: 8, pixelHeight: 8,
                fileSizeBytes: 1, firstDownloadedAt: Date(), revision: UUID())
            library.snapshot = .init(records: library.snapshot.records + [record], revision: library.snapshot.revision + 1)
            workspace.catalog.catalog.downloads.append(OnlineImageContentProjection.local(record, url: url, available: true))
            availability.send()
            return url
        }
        let visiblePublicationRequest = originals.requests.count
        _ = coordinator.preview(content: remoteB)
        try await waitUntil("visible publication preview request") { originals.requests.count == visiblePublicationRequest + 1 }
        try originals.complete(visiblePublicationRequest, bytes: originalBytes)
        try await waitUntil("visible remote before publication") { coordinator.isPreviewVisible && coordinator.previewURL != nil }
        let replacedTemporary = coordinator.previewURL!
        let visibleLocal = try publishLocalPreview(remoteB)
        try await waitUntil("visible same-reference local publication") { coordinator.previewURL == visibleLocal && coordinator.isPreviewVisible && panel.dataSource === coordinator }
        checks["visible-remote-preview-switches-to-new-same-reference-local-publication"] = coordinator.previewReference == remoteB.reference
            && panel.dataSource === coordinator && FileManager.default.fileExists(atPath: replacedTemporary.path)
        coordinator.closePreview()

        let pendingPublicationRequest = originals.requests.count
        _ = coordinator.preview(content: remoteA)
        try await waitUntil("pending publication preview request") { originals.requests.count == pendingPublicationRequest + 1 }
        let pendingLocal = try publishLocalPreview(remoteA)
        try await waitUntil("pending same-reference local publication") { coordinator.previewURL == pendingLocal && coordinator.isPreviewVisible && panel.dataSource === coordinator }
        checks["pending-remote-preview-switches-to-local-publication-without-waiting-for-original-fetch"] = coordinator.previewReference == remoteA.reference
            && coordinator.isPreviewVisible && panel.dataSource === coordinator
        try originals.complete(pendingPublicationRequest, bytes: originalBytes); await pump()
        checks["late-remote-original-cannot-replace-the-published-same-reference-local-file"] = coordinator.previewReference == remoteA.reference
            && coordinator.previewURL == pendingLocal && originals.requests.count == pendingPublicationRequest + 1
        coordinator.closePreview()
        library.snapshot = .init()
        workspace.catalog.catalog.downloads.removeAll { [remoteA.reference, remoteB.reference].contains($0.reference) }

        let beforeLocalPreview = originals.requests.count
        checks["local-quicklook-still-opens-the-local-file-without-remote-acquisition"] = coordinator.preview(content: imageValue)
            && coordinator.previewURL == file && coordinator.previewReference == image
        try await waitUntil("local native owner after remote preview") { coordinator.isPreviewVisible && panel.dataSource === coordinator && panel.delegate === coordinator }
        checks["local-quicklook-keeps-the-existing-native-owner-after-remote-preview"] = originals.requests.count == beforeLocalPreview
            && panel.dataSource === coordinator && panel.delegate === coordinator
        let replacementFile = directory.appendingPathComponent("preview-replacement.png")
        try Data(contentsOf: file).write(to: replacementFile)
        var replacementLocator = imageValue.locator; replacementLocator.path = replacementFile.path
        var replacementMetadata = imageValue.metadata; replacementMetadata.resourceRevision = "replacement-revision"
        let replacementImage = WallpaperContentItem(reference: imageValue.reference, providerReference: imageValue.providerReference,
            locator: replacementLocator, title: imageValue.title, kind: imageValue.kind, publishedAvailability: imageValue.publishedAvailability,
            capabilities: imageValue.capabilities, metadata: replacementMetadata, acquisition: imageValue.acquisition,
            update: imageValue.update, aliases: imageValue.aliases)
        workspace.catalog.catalog.images = [replacementImage]
        coordinator.syncSelection(content: replacementImage); await pump()
        try await waitUntil("same-reference local resource replacement") { coordinator.previewURL == replacementFile && panel.dataSource === coordinator && coordinator.isPreviewVisible }
        checks["same-reference-local-resource-replacement-updates-quicklook-URL"] = coordinator.previewReference == image
            && coordinator.previewURL == replacementFile && panel.dataSource === coordinator && originals.requests.count == beforeLocalPreview
        coordinator.closePreview()
        workspace.catalog.catalog.images = [imageValue]

        checks["web-scene-do-not-masquerade-as-quicklook-video"] = !coordinator.preview(content: webValue) && coordinator.previewURL == nil && coordinator.inspectedReference == web
        _ = coordinator.preview(content: imageValue); await pump()
        coordinator.syncSelection(content: nil)
        let closeDeadline = Date().addingTimeInterval(1)
        while panel.isVisible, Date() < closeDeadline { await pump() }
        checks["cleared-selection-closes-preview-and-releases-own-delegates"] = coordinator.previewURL == nil && panel.dataSource !== coordinator && panel.delegate !== coordinator && !panel.isVisible
        _ = coordinator.preview(content: imageValue); await pump()
        let foreign = ForeignPreviewOwner(); foreign.url = file
        panel.dataSource = foreign
        panel.delegate = nil
        let visible = panel.isVisible
        coordinator.closePreview()
        checks["old-preview-close-never-detaches-or-closes-a-new-owner"] = panel.dataSource === foreign && panel.isVisible == visible
        panel.orderOut(nil); panel.dataSource = nil
        coordinator.inspect(content: remoteValue); await pump()
        let beforeReset = probe.mounts.last!.1 as! PixabayDownloadsInspectorView
        let previousEpoch = workspace.relationships
        workspace.relationships = .init(revision: 2, resetEpoch: UUID(), migrationManifestID: nil,
            playlists: previousEpoch.playlists, members: previousEpoch.members, favorites: [], recent: [], aliases: previousEpoch.aliases, locators: [])
        let favoritesBeforeReset = favorites
        beforeReset.actions.onToggleFavorite()
        checks["reset-revokes-old-actions-before-asynchronous-view-echo"] = favorites == favoritesBeforeReset
        workspace.publishPresentation(); await pump()
        checks["reset-closes-existing-inspection-without-reopening-old-content"] = coordinator.inspectorToken == nil
        coordinator.closeInspector()

        // The real manager's Void publisher drives the real Coordinator here.
        // Its SQLite Undo admission/settlement is covered by CommandTransactions;
        // these controlled input transitions isolate the synchronous UI echo.
        let policyWorkspace = WallpaperLibraryWorkspace()
        let policyUndo = RelationshipUndoManager()
        let offlineVideo = WallpaperContentItem(reference: video, providerReference: video,
            locator: videoValue.locator, title: "Offline video", kind: .video, publishedAvailability: .unavailable,
            capabilities: [.inspect], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        let offlineWeb = WallpaperContentItem(reference: web, providerReference: web,
            locator: webValue.locator, title: "Offline workshop", kind: .web, publishedAvailability: .unavailable,
            capabilities: [.inspect], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        policyWorkspace.catalog.catalog = .init(videos: [offlineVideo], downloads: [offlineWeb])
        policyWorkspace.relationships = .init(revision: 1, resetEpoch: UUID(), migrationManifestID: nil,
            playlists: [], members: [], favorites: [.init(reference: video, favoritedAt: nil), .init(reference: web, favoritedAt: nil)],
            recent: [], aliases: [], locators: [])
        var policyFavorites: [WallpaperReference] = [], policyMemberships: [WallpaperReference] = []
        func canEditPolicy() -> Bool { policyWorkspace.presentation.canEditCollections && !policyUndo.isApplyingTransaction }
        let policyCoordinator = WallpaperLibraryInspectorCoordinator(workspace: policyWorkspace,
            manager: manager, images: images, steam: steam, pixabay: pixabay, makePrimaryAction: { _ in nil },
            makeFavoriteAction: { value in
                let action = favoriteState(value, workspace: policyWorkspace, canEdit: canEditPolicy())
                guard action.canExecute else { return nil }
                return {
                    guard let latest = try? policyWorkspace.content(for: value.reference) else { return }
                    let current = favoriteState(latest, workspace: policyWorkspace, canEdit: canEditPolicy())
                    guard current.canExecute, current.isRemoving == action.isRemoving else { return }
                    policyFavorites.append(value.reference)
                }
            }, canOrganize: canEditPolicy, availabilityChanges: policyUndo.applyingChanges.eraseToAnyPublisher(),
            onChoosePlaylist: { ref, _ in policyMemberships.append(ref) })
        policyCoordinator.inspect(content: offlineVideo); await pump()
        let offlineVideoView = probe.mounts.last!.1 as! VideoLibraryInspectorView
        checks["offline-favorite-inspector-keeps-removal-without-granting-playlist-write"] = offlineVideoView.actions.state.isFavorite
            && offlineVideoView.actions.state.canFavorite && !offlineVideoView.actions.state.canOrganize
        let heldOfflineVideo = offlineVideoView.actions
        heldOfflineVideo.onToggleFavorite(); heldOfflineVideo.onChoosePlaylist(nil)
        checks["offline-inspector-removal-executes-fixed-ref-and-list-action-stays-disabled"] = policyFavorites == [video]
            && policyMemberships.isEmpty
        policyCoordinator.inspect(content: offlineWeb); await pump()
        let offlineSteamView = probe.mounts.last!.1 as! AppKitSteamWorkshopItemDetailView
        heldOfflineVideo.onToggleFavorite()
        offlineSteamView.actions.onToggleFavorite(); offlineSteamView.actions.onChoosePlaylist(nil)
        checks["offline-workshop-inspector-separates-heart-from-list-and-revokes-old-token"] = offlineSteamView.actions.state.canFavorite
            && !offlineSteamView.actions.state.canOrganize && policyFavorites == [video, web] && policyMemberships.isEmpty
        policyWorkspace.presentation.canEditCollections = false
        policyWorkspace.publishPresentation(); await pump()
        let beforeReadOnlyPolicy = policyFavorites
        offlineSteamView.actions.onToggleFavorite(); offlineSteamView.actions.onChoosePlaylist(nil)
        checks["readonly-offline-inspector-refuses-heart-and-list-independently"] = !offlineSteamView.actions.state.canFavorite
            && !offlineSteamView.actions.state.canOrganize && policyFavorites == beforeReadOnlyPolicy && policyMemberships.isEmpty
        policyWorkspace.presentation.canEditCollections = true
        policyWorkspace.catalog.catalog = .init(videos: [videoValue], downloads: [offlineWeb])
        policyCoordinator.inspect(content: videoValue); await pump()
        let livePolicyView = probe.mounts.last!.1 as! VideoLibraryInspectorView
        let policyToken = policyCoordinator.inspectorToken
        let beforeBusyPolicy = livePolicyView.actions
        let beforeBusyState = policyWorkspace.presentation.publications
        let beforeBusyFavorites = policyFavorites
        checks["available-inspector-has-independent-heart-and-playlist-actions-before-undo"] = livePolicyView.actions.state.canFavorite
            && livePolicyView.actions.state.canOrganize
        policyUndo.isApplyingTransaction = true
        checks["undo-busy-invalidation-disables-existing-inspector-synchronously-without-state-publish"] = !livePolicyView.actions.state.canFavorite
            && !livePolicyView.actions.state.canOrganize && policyCoordinator.inspectorToken == policyToken
            && policyWorkspace.presentation.publications == beforeBusyState
        beforeBusyPolicy.onToggleFavorite(); beforeBusyPolicy.onChoosePlaylist(nil)
        checks["held-inspector-actions-cannot-bypass-current-undo-busy-policy"] = policyFavorites == beforeBusyFavorites
            && policyMemberships.isEmpty
        let disabledPolicyActions = livePolicyView.actions
        policyUndo.isApplyingTransaction = false
        checks["undo-completion-invalidation-restores-same-inspector-without-another-catalog-echo"] = livePolicyView.actions.state.canFavorite
            && livePolicyView.actions.state.canOrganize && policyCoordinator.inspectorToken == policyToken
            && policyWorkspace.presentation.publications == beforeBusyState
        disabledPolicyActions.onToggleFavorite()
        checks["disabled-rendered-heart-does-not-borrow-action-after-undo-completes"] = policyFavorites == beforeBusyFavorites
        let beforePolicyReset = livePolicyView.actions
        let policyRelations = policyWorkspace.relationships
        policyWorkspace.relationships = .init(revision: 2, resetEpoch: UUID(), migrationManifestID: nil,
            playlists: [], members: [], favorites: policyRelations.favorites, recent: [], aliases: [], locators: [])
        beforePolicyReset.onToggleFavorite(); beforePolicyReset.onChoosePlaylist(nil)
        checks["policy-actions-still-reject-reset-before-any-availability-or-state-echo"] = policyFavorites == beforeBusyFavorites
            && policyMemberships.isEmpty
        let policyOpenCount = probe.opens.count
        policyUndo.isApplyingTransaction = true
        policyUndo.isApplyingTransaction = false
        checks["availability-after-reset-closes-without-reopening-old-inspection"] = policyCoordinator.inspectorToken == nil
            && probe.opens.count == policyOpenCount
        policyCoordinator.closeInspector()

        // Real overlay lifecycle: a new selection during the old close must
        // cancel its completion, and old token messages cannot affect it.
        coordinator.inspect(content: imageValue); await pump()
        let closingToken = coordinator.inspectorToken!
        let closingView = probe.mounts.last!.1
        InspectorHostActions.postClose(module: closingToken.module, cardID: closingToken.cardID)
        checks["real-close-revokes-overlay-hit-interception-before-completion"] = overlay.hitTest(NSPoint(x: 10, y: 10)) == nil
        coordinator.syncSelection(content: remoteValue)
        let reopenedToken = coordinator.inspectorToken!, reopenedView = probe.mounts.last!.1
        checks["selection-during-close-reopens-existing-host-with-new-lease"] = reopenedToken != closingToken
            && !overlay.isHidden && reopenedView.isDescendant(of: host.view)
            && overlay.hitTest(NSPoint(x: 10, y: 10)) === overlay
        await pump()
        let inFlightTrailing = trailing.constant
        coordinator.syncSelection(content: imageValue)
        let finalToken = coordinator.inspectorToken!, finalView = probe.mounts.last!.1
        checks["selection-during-entrance-preserves-current-slide-offset"] = trailing.constant == inFlightTrailing
            && !overlay.isHidden && finalView.isDescendant(of: host.view)
        InspectorHostActions.postMount(module: closingToken.module, cardID: closingToken.cardID, hostedView: closingView)
        InspectorHostActions.postClose(module: closingToken.module, cardID: closingToken.cardID)
        try? await Task.sleep(for: .milliseconds(350))
        split.view.layoutSubtreeIfNeeded()
        recordHost("after-obsolete-animation-and-real-token-messages", extra: [
            "tokenMatches": coordinator.inspectorToken == finalToken, "finalInHost": finalView.isDescendant(of: host.view),
            "oldDetached": closingView.superview == nil, "reopenedDetached": reopenedView.superview == nil,
            "edgeDelta": animationHost.frame.maxX - overlay.bounds.maxX])
        checks["late-real-mount-close-and-obsolete-animation-cannot-replace-or-hide-new-panel"] = coordinator.inspectorToken == finalToken
            && finalView.isDescendant(of: host.view) && closingView.superview == nil && reopenedView.superview == nil
            && !overlay.isHidden && overlay.hitTest(NSPoint(x: 10, y: 10)) === overlay
            && abs(animationHost.frame.maxX - overlay.bounds.maxX) <= 0.5
        coordinator.closeInspector()
        let remoteFile = PixabayVideoFile(url: "https://cdn.pixabay.com/owned-video.mp4", width: 1920, height: 1080, size: 4096, thumbnail: "https://cdn.pixabay.com/owned-preview.jpg")
        func pixabayRemote(_ id: Int, title: String = "Owned Pixabay", duration: Int = 12) -> PixabayVideoItem {
            .init(id: id, pageURL: "https://pixabay.com/videos/id-\(id)/", tags: title, duration: duration, user: "Owned author",
                videos: .init(large: remoteFile, medium: remoteFile, small: nil, tiny: nil))
        }
        let pixabayA = pixabayRemote(88), pixabayB = pixabayRemote(89)
        let closedPixabayOpens = probe.opens.count
        coordinator.syncPixabaySelection(pixabayA); await pump()
        checks["pixabay-selection-does-not-open-a-closed-inspector"] = coordinator.inspectedReference == nil && probe.opens.count == closedPixabayOpens
        coordinator.inspectPixabayItem(pixabayA); await pump()
        let pixabayAView = probe.mounts.last!.1 as! PixabayDownloadsInspectorView
        checks["explicit-pixabay-details-use-the-accepted-model-without-current-search-items"] = pixabay.items.isEmpty
            && coordinator.inspectedReference == .init(provider: .pixabay, sourceID: "88") && pixabayAView.remoteItem == pixabayA
        let closesBeforePixabaySelection = probe.closes.count
        coordinator.syncPixabaySelection(pixabayB); await pump()
        let pixabayBView = probe.mounts.last!.1 as! PixabayDownloadsInspectorView
        let pixabayToken = coordinator.inspectorToken, pixabayMounts = probe.mounts.count
        checks["pixabay-selection-replaces-only-visible-content-without-closing-the-host"] = pixabayBView !== pixabayAView
            && pixabayBView.remoteItem == pixabayB && coordinator.inspectedReference == .init(provider: .pixabay, sourceID: "89")
            && probe.closes.count == closesBeforePixabaySelection
        let changedPixabay = pixabayRemote(89, title: "Updated accepted model", duration: 21)
        coordinator.syncPixabaySelection(changedPixabay); await pump()
        checks["same-pixabay-reference-updates-model-through-the-original-view-and-token"] = coordinator.inspectorToken == pixabayToken
            && probe.mounts.count == pixabayMounts && pixabayBView.remoteItem == changedPixabay && pixabay.items.isEmpty
        workspace.publishPresentation(); availability.send(); await pump()
        checks["unknown-reference-echo-keeps-accepted-pixabay-remote-details-and-actions"] = coordinator.inspectorToken == pixabayToken
            && probe.mounts.count == pixabayMounts && pixabayBView.remoteItem == changedPixabay && !pixabayBView.actions.state.canFavorite
        pixabay.downloadedContent.entries.append(.init(id: 89))
        workspace.catalog.catalog.downloads.append(content(.init(provider: .pixabay, sourceID: "89"), .video))
        availability.send(); await pump()
        checks["actual-pixabay-local-publication-upgrades-actions-without-replacing-the-view"] = coordinator.inspectorToken == pixabayToken
            && probe.mounts.count == pixabayMounts && pixabayBView.actions.state.canFavorite && pixabayBView.remoteItem == changedPixabay
        coordinator.syncPixabaySelection(nil); await pump()
        checks["cleared-pixabay-selection-releases-current-inspector-without-reopening"] = coordinator.inspectedReference == nil
            && coordinator.previewReference == nil
        window.orderOut(nil)
        checks.merge(try await inspectorPresentationRefreshChecks(), uniquingKeysWith: { _, new in new })
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
