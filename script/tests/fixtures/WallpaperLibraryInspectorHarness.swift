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
struct OnlineEntry { let id: Int }
struct OnlineSnapshot { var entries: [OnlineEntry] = [] }
final class WallpaperManager { var wallpapers: [VideoWallpaper] = [] }
final class SILService { var wallpapers: [SILWallpaper] = [] }
final class OnlineLibraryService { var downloadedContent = OnlineSnapshot() }
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
final class OnlineLibraryDownloadsInspectorView: RecordingInspectorView {
    init(itemID: Int, service: OnlineLibraryService, libraryActions: WallpaperInspectorActions) { super.init(libraryActions) }
    required init?(coder: NSCoder) { nil }
}
final class InspectorPresentation: ObservableObject { @Published var state = 0; var canEditCollections = true }
final class WallpaperLibraryWorkspace {
    let presentation = InspectorPresentation()
    var relationships = UserCollectionsSnapshot(revision: 0, resetEpoch: UUID(), migrationManifestID: nil,
        playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
    var catalog = WallpaperLibraryCatalog()
    var playing: WallpaperReference?
    func content(for ref: WallpaperReference) throws -> WallpaperContentItem { try WallpaperLibraryQuery.resolve([ref], catalog: catalog, relationships: relationships)[0] }
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
    @MainActor static func main() {
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
        window.delegate = windowController
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        let workspace = WallpaperLibraryWorkspace(), manager = WallpaperManager(), images = SILService(), steam = SteamWorkshopService(), online = OnlineLibraryService()
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
        steam.downloads = [.init(id: "w")]; online.downloadedContent.entries = [.init(id: 7)]
        workspace.catalog = .init(videos: [videoValue, secondVideoValue], images: [imageValue], downloads: [webValue, remoteValue])
        var primaryFactoryCalls = 0, primaryGeneration = 0
        var primary: [WallpaperReference] = [], favorites: [WallpaperReference] = [], memberships: [WallpaperReference] = []
        func favoriteState(_ content: WallpaperContentItem, workspace: WallpaperLibraryWorkspace, canEdit: Bool) -> WallpaperLibraryFavoriteActionState {
            .init(canEdit: canEdit, hasItems: true, allFavorite: workspace.isFavorite(content.reference),
                allOrganizable: content.capabilities.contains(.organize))
        }
        let coordinator = WallpaperLibraryInspectorCoordinator(workspace: workspace, manager: manager, images: images, steam: steam, online: online,
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
            availabilityChanges: Empty<Void, Never>().eraseToAnyPublisher(),
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
        try? await Task.sleep(for: .milliseconds(300))
        split.view.layoutSubtreeIfNeeded()
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
        checks["pixabay-keeps-its-original-inspector-type"] = probe.mounts.last!.1 is OnlineLibraryDownloadsInspectorView
        coordinator.inspect(content: content(missing, .video)); await pump()
        checks["missing-source-keeps-an-inspectable-unavailable-reference"] = probe.mounts.last!.1 is NSStackView && coordinator.inspectedReference == missing
        manager.wallpapers.append(.init(id: "missing")); workspace.catalog.videos.append(content(missing, .video))
        workspace.presentation.state += 1; await pump()
        checks["same-ref-source-recovery-replaces-placeholder-with-original-detail"] = probe.mounts.last!.1 is VideoLibraryInspectorView
        let restoredView = probe.mounts.last!.1 as! VideoLibraryInspectorView
        workspace.presentation.canEditCollections = false; workspace.presentation.state += 1; await pump()
        restoredView.actions.onToggleFavorite(); restoredView.actions.onChoosePlaylist(nil)
        checks["recovery-readonly-disables-all-organization-actions"] = !restoredView.actions.state.canFavorite
            && !restoredView.actions.state.canOrganize && favorites == [video] && memberships == [video]
        coordinator.closeInspector(); await pump()
        let openCount = probe.opens.count
        workspace.presentation.state += 1; await pump()
        checks["catalog-publish-never-reopens-closed-inspector"] = coordinator.inspectorToken == nil && probe.opens.count == openCount
        workspace.presentation.canEditCollections = true
        let list = WallpaperPlaylist(name: "Mixed", sidebarRank: 0)
        workspace.relationships = .init(revision: 1, resetEpoch: workspace.relationships.resetEpoch, migrationManifestID: nil,
            playlists: [list], members: [.init(playlistID: list.id, reference: video, position: 0, addedAt: Date())], favorites: [], recent: [],
            aliases: [.init(alias: video, canonical: remote, proof: .publishedDownload)], locators: [])
        coordinator.inspect(content: videoValue); await pump()
        let aliasView = probe.mounts.last!.1 as! OnlineLibraryDownloadsInspectorView
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
        let beforeReset = probe.mounts.last!.1 as! OnlineLibraryDownloadsInspectorView
        let previousEpoch = workspace.relationships
        workspace.relationships = .init(revision: 2, resetEpoch: UUID(), migrationManifestID: nil,
            playlists: previousEpoch.playlists, members: previousEpoch.members, favorites: [], recent: [], aliases: previousEpoch.aliases, locators: [])
        let favoritesBeforeReset = favorites
        beforeReset.actions.onToggleFavorite()
        checks["reset-revokes-old-actions-before-asynchronous-view-echo"] = favorites == favoritesBeforeReset
        workspace.presentation.state += 1; await pump()
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
        policyWorkspace.catalog = .init(videos: [offlineVideo], downloads: [offlineWeb])
        policyWorkspace.relationships = .init(revision: 1, resetEpoch: UUID(), migrationManifestID: nil,
            playlists: [], members: [], favorites: [.init(reference: video, favoritedAt: nil), .init(reference: web, favoritedAt: nil)],
            recent: [], aliases: [], locators: [])
        var policyFavorites: [WallpaperReference] = [], policyMemberships: [WallpaperReference] = []
        func canEditPolicy() -> Bool { policyWorkspace.presentation.canEditCollections && !policyUndo.isApplyingTransaction }
        let policyCoordinator = WallpaperLibraryInspectorCoordinator(workspace: policyWorkspace,
            manager: manager, images: images, steam: steam, online: online, makePrimaryAction: { _ in nil },
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
        policyWorkspace.presentation.state += 1; await pump()
        let beforeReadOnlyPolicy = policyFavorites
        offlineSteamView.actions.onToggleFavorite(); offlineSteamView.actions.onChoosePlaylist(nil)
        checks["readonly-offline-inspector-refuses-heart-and-list-independently"] = !offlineSteamView.actions.state.canFavorite
            && !offlineSteamView.actions.state.canOrganize && policyFavorites == beforeReadOnlyPolicy && policyMemberships.isEmpty
        policyWorkspace.presentation.canEditCollections = true
        policyWorkspace.catalog = .init(videos: [videoValue], downloads: [offlineWeb])
        policyCoordinator.inspect(content: videoValue); await pump()
        let livePolicyView = probe.mounts.last!.1 as! VideoLibraryInspectorView
        let policyToken = policyCoordinator.inspectorToken
        let beforeBusyPolicy = livePolicyView.actions
        let beforeBusyState = policyWorkspace.presentation.state
        let beforeBusyFavorites = policyFavorites
        checks["available-inspector-has-independent-heart-and-playlist-actions-before-undo"] = livePolicyView.actions.state.canFavorite
            && livePolicyView.actions.state.canOrganize
        policyUndo.isApplyingTransaction = true
        checks["undo-busy-invalidation-disables-existing-inspector-synchronously-without-state-publish"] = !livePolicyView.actions.state.canFavorite
            && !livePolicyView.actions.state.canOrganize && policyCoordinator.inspectorToken == policyToken
            && policyWorkspace.presentation.state == beforeBusyState
        beforeBusyPolicy.onToggleFavorite(); beforeBusyPolicy.onChoosePlaylist(nil)
        checks["held-inspector-actions-cannot-bypass-current-undo-busy-policy"] = policyFavorites == beforeBusyFavorites
            && policyMemberships.isEmpty
        let disabledPolicyActions = livePolicyView.actions
        policyUndo.isApplyingTransaction = false
        checks["undo-completion-invalidation-restores-same-inspector-without-another-catalog-echo"] = livePolicyView.actions.state.canFavorite
            && livePolicyView.actions.state.canOrganize && policyCoordinator.inspectorToken == policyToken
            && policyWorkspace.presentation.state == beforeBusyState
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
        window.orderOut(nil)
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
