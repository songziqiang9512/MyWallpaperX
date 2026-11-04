import AppKit
import Combine

// Owners and media transports are recording leaves. The complete production
// App adapter and native makeItem path run with an asset-helper entry observer.
// Source getters here do not stat; this observer counts helper entry only.
@MainActor enum AdapterPrefetchAssetsProbe {
    static var references: [WallpaperReference] = []
}
final class WallpaperManager {
    var sourceReads = 0
    private var records: [VideoWallpaper] = []
    var wallpapers: [VideoWallpaper] { get { sourceReads += 1; return records } set { records = newValue } }
}
struct SILWallpaper: Equatable { let id: String; let path: String; let title: String }
final class SILService {
    var sourceReads = 0
    private var records: [SILWallpaper] = []
    var wallpapers: [SILWallpaper] { get { sourceReads += 1; return records } set { records = newValue } }
}
struct SteamWorkshopBrowserItem: Equatable { let id: String; let title: String }
struct SteamWorkshopDownloadRecord: Equatable {
    enum Status { case ready, downloading, failed, queued }
    let id: String; let title: String; let status: Status
    var displayItem: SteamWorkshopBrowserItem? = nil
    var videoURL: URL? = nil
    var previewURL: URL? = nil
}
final class SteamWorkshopDownloadProgressStore {}
final class SteamWorkshopService {
    var sourceReads = 0
    private var records: [SteamWorkshopDownloadRecord] = []
    var downloads: [SteamWorkshopDownloadRecord] { get { sourceReads += 1; return records } set { records = newValue } }
    let downloadProgressStore = SteamWorkshopDownloadProgressStore()
    var previewReloadToken = 0
    var downloadRequests: [String] = []; var cancellations: [String] = []
    func downloadWorkshopItem(id: String, pageTitle: String?, item: SteamWorkshopBrowserItem?) { downloadRequests.append(id) }
    func cancelDownload(itemID: String) { cancellations.append(itemID) }
}
struct PixabayDownloadedEntry: Equatable { let id: Int; let localURL: URL; var thumbnailSourceKey: String? = nil }
struct DownloadedSnapshot { var entries: [PixabayDownloadedEntry] = [] }
final class PixabayService {
    var sourceReads = 0
    private var content = DownloadedSnapshot()
    var downloadedContent: DownloadedSnapshot { get { sourceReads += 1; return content } set { content = newValue } }
}
enum SteamWorkshopDownloadGridSupport {
    static var fallbackTitles: [String] = []
    static func fallbackDisplayItem(for row: SteamWorkshopDownloadRecord) -> SteamWorkshopBrowserItem {
        fallbackTitles.append(row.title)
        return .init(id: row.id, title: row.title)
    }
}
enum ThumbnailCacheRequestPriority { case visible, prefetch }
final class ThumbnailCacheRequestCancellation { var cancelled = false; func cancel() { cancelled = true } }
final class AppKitThumbnailProvider {
    static var batches: [([String], [String])] = []
    static var batchPaths: [([String], [String])] = []
    static var cancelled = 0
    static var thumbnailRequests: [ThumbnailRequest?] = []
    init(wallpaperManager: WallpaperManager) {}
    func replacePrefetch(with values: [VideoWallpaper], retainingVisible: [VideoWallpaper], request: ThumbnailRequest? = nil) {
        Self.thumbnailRequests.append(request)
        Self.batches.append((values.map(\.id), retainingVisible.map(\.id)))
        Self.batchPaths.append((values.map(\.path), retainingVisible.map(\.path)))
    }
    static var visibleDemand: [[String]] = []
    static var repairs = 0
    func updateVisiblePreviewDemand(with values: [VideoWallpaper]) { Self.visibleDemand.append(values.map(\.id)) }
    func repairVisiblePreviews() { Self.repairs += 1 }
    func cancelAllPrefetch() { Self.cancelled += 1 }
}
final class RecordingThumbnailCache {
    var images: [String: NSImage] = [:]
    var failures: Set<String> = []
    func cachedImage(forKey key: String, request: ThumbnailRequest? = nil) -> NSImage? { images[key] }
    func hasCachedResult(forKey key: String, request: ThumbnailRequest? = nil) -> Bool { images[key] != nil || failures.contains(key) }
}
enum PixabayDownloadedThumbnailStore {
    static let sharedCache = RecordingThumbnailCache()
    static var completions: [(String, NSImage?) -> Void] = []
    static var requests: [(Int, ThumbnailCacheRequestCancellation)] = []
    static var requestedURLs: [URL] = []
    static func loadThumbnail(_ entry: PixabayDownloadedEntry, request: ThumbnailRequest? = nil, priority: ThumbnailCacheRequestPriority,
        cancellation: ThumbnailCacheRequestCancellation,
                         completion: @escaping (String, NSImage?) -> Void) { requests.append((entry.id, cancellation)); requestedURLs.append(entry.localURL); completions.append(completion) }
}
func steamWorkshopPreviewSources(item: SteamWorkshopBrowserItem, record: SteamWorkshopDownloadRecord)
    -> (primary: URL?, fallback: URL?) { (record.previewURL ?? URL(string: "https://fixture.invalid/" + item.id), nil) }
final class SteamWorkshopPreviewState {
    struct Loaders { static func live(priority: ThumbnailCacheRequestPriority) -> Loaders { Loaders() } }
    static var configured: [SteamWorkshopPreviewState] = []
    static var configurationCount = 0
    static var resetCount = 0
    static var completesSynchronously = false
    static let cache = RecordingThumbnailCache()
    var onChange: (() -> Void)?
    var image: NSImage?
    var resets = 0
    var pixelSize: Int?
    var previewURL: URL?
    var refreshToken: Int?
    init(loaders: Loaders) {}
    func configure(previewURL: URL?, fallbackImageURL: URL?, fallbackVideoURL: URL?, refreshToken: Int, maxPixelSize: Int) {
        pixelSize = maxPixelSize; self.previewURL = previewURL; self.refreshToken = refreshToken
        Self.configurationCount += 1; Self.configured.append(self)
        if Self.completesSynchronously { deliver(NSImage(size: NSSize(width: 48, height: 48))) }
    }
    func deliver(_ image: NSImage?) {
        self.image = image
        if let image, let previewURL { Self.cache.images[previewURL.absoluteString] = image }
        onChange?()
    }
    func reset() { resets += 1; Self.resetCount += 1; image = nil; onChange?() }
}
enum SILThumbnailLoadResult { case image(NSImage), unavailable }
final class SILThumbnailProvider {
    static let sharedCache = RecordingThumbnailCache()
    let cache = SILThumbnailProvider.sharedCache
    static var completions: [(SILThumbnailLoadResult) -> Void] = []
    static var requests: [(String, ThumbnailCacheRequestPriority, ThumbnailCacheRequestCancellation)] = []
    static var thumbnailRequests: [ThumbnailRequest?] = []
    func load(path: String, request: ThumbnailRequest? = nil, priority: ThumbnailCacheRequestPriority = .visible,
              cancellation: ThumbnailCacheRequestCancellation, completion: @escaping (SILThumbnailLoadResult) -> Void) {
        Self.thumbnailRequests.append(request)
        Self.requests.append((path, priority, cancellation)); Self.completions.append(completion)
    }
}
final class WallpaperLibraryGridController {
    struct CellState { let isSelected: Bool; let isSelecting: Bool; let isFocused: Bool; let thumbnailRequest: ThumbnailRequest }
}
class AppearanceAwareContainerView: NSView { var appearanceDidChangeHandler: (() -> Void)? }
class RecordingCard: NSCollectionViewItem {
    var configurations = 0; var visible = false; var playing = false
    var switching = false
    var configuredRequests: [ThumbnailRequest?] = []
    var presentedTitle = ""; var selectedState = false; var selecting = false
    override func loadView() { view = NSView() }
    func applySwitchingState(isSwitching: Bool) { switching = isSwitching }
}
private enum RecordingProgressStyle { case downloading, neutral }
private final class RecordingImageGlass {
    var fraction: Double?
    func applyProgress(style: RecordingProgressStyle, fraction: Double?, indeterminate: Bool, animated: Bool) { self.fraction = fraction }
}
private final class RecordingImageBar {
    enum PrimaryState { case apply, switching, playing, download }
    let playButton = NSButton(), detailButton = NSButton()
    let glass = RecordingImageGlass()
    var primaryState: PrimaryState = .apply
    var primaryActionTitle: String?
    var onPlay: (() -> Void)?
    var onInspect: (() -> Void)?
    func apply(title: String, metadata: String) {}
}
final class OnlineImageGridItem: RecordingCard {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("online-image")
    private let bar: RecordingImageBar? = RecordingImageBar()
    private var content: WallpaperContentItem?
    private var busy = false
    private var onPrimary: (() -> Void)?
    private var onInspect: (() -> Void)?
    var reference: WallpaperReference? { content?.providerReference }
    private(set) var transferUpdates = 0
    private(set) var fraction: Double?
    var canPerformPrimary: Bool { bar?.playButton.isEnabled == true }
    var heldPrimary: (() -> Void)? { bar?.onPlay }
    var heldInspect: (() -> Void)? { bar?.onInspect }
    func activatePrimary() { if canPerformPrimary { bar?.onPlay?() } }
    func setThumbnailVisible(_ value: Bool, thumbnailRequest: ThumbnailRequest? = nil) { visible = value }
    func configure(content: WallpaperContentItem, request: Any?, selected: Bool, selecting: Bool,
                   playing: Bool, switching: Bool = false, busy: Bool = false, fraction: Double? = nil, refreshToken: UUID? = nil, thumbnailRequest: ThumbnailRequest? = nil,
                   onPrimary: (() -> Void)?, onInspect: (() -> Void)?) {
        configuredRequests.append(thumbnailRequest)
        configurations += 1; presentedTitle = content.title; selectedState = selected
        self.content = content; self.playing = playing; self.selecting = selecting; self.switching = switching
        self.onPrimary = onPrimary; self.onInspect = onInspect
        bar?.onPlay = onPrimary; updateControls(); applyTransfer(busy: busy, fraction: fraction)
    }
    private func updateVisibility() { transferUpdates += 1 }
    // ACTUAL_IMAGE_CONTROLS
    // ACTUAL_IMAGE_TRANSFER
}
private final class ImageCancelMenuWorkspace {
    struct Relationships { var resetEpoch = UUID() }
    struct Presentation {
        struct Selection { var sessionID = UUID() }
        var page = WallpaperLibraryPage.downloads
        var selectionState = Selection()
    }
    var relationships = Relationships()
    var presentation = Presentation()
}
private final class ImageCancelMenuProbe {
    let workspace = ImageCancelMenuWorkspace()
    func makeMenu(_ item: WallpaperContentItem) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        let epoch = workspace.relationships.resetEpoch, page = workspace.presentation.page
        let session = workspace.presentation.selectionState.sessionID
        // ACTUAL_MENU_ADD
        // ACTUAL_IMAGE_CANCEL
        return menu
    }
}
final class AppKitWallpaperItem: RecordingCard {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("video")
    var onPlayRequested: ((String) -> Void)?; var onInspectRequested: ((String) -> Void)?
    func setThumbnailVisible(_ visible: Bool) { self.visible = visible }
    func configure(wallpaper: VideoWallpaper, isSelected: Bool, isPlaying: Bool,
                   multiSelectMode: Bool, thumbnailRequest: ThumbnailRequest? = nil, wallpaperManager: WallpaperManager, thumbnailProvider: AppKitThumbnailProvider) {
        configuredRequests.append(thumbnailRequest)
        configurations += 1; presentedTitle = wallpaper.title; selectedState = isSelected; playing = isPlaying
    }
    func applySelectionState(isSelected: Bool, multiSelectMode: Bool) { selectedState = isSelected; selecting = multiSelectMode }
    func applyPlayingState(isPlaying: Bool) { playing = isPlaying }
}
final class SILGridItem: RecordingCard {
    var recordedLoader: ((ThumbnailCacheRequestCancellation, @escaping (SILThumbnailLoadResult) -> Void) -> Void)?
    static let reuseID = NSUserInterfaceItemIdentifier("image")
    var onApplyRequested: ((String) -> Void)?; var onInspectRequested: ((String) -> Void)?
    func setThumbnailVisible(_ visible: Bool) { self.visible = visible }
    func configure(wallpaper: SILWallpaper, isSelected: Bool, isMultiSelectMode: Bool,
                   thumbnailVisible: Bool, isPlaying: Bool, cachedThumbnail: NSImage? = nil,
                   thumbnailLoader: @escaping (ThumbnailCacheRequestCancellation, @escaping (SILThumbnailLoadResult) -> Void) -> Void) {
        recordedLoader = thumbnailLoader
        configurations += 1; presentedTitle = wallpaper.title; selectedState = isSelected; visible = thumbnailVisible
        playing = isPlaying
    }
    func applySelectionState(isSelected: Bool, multiSelectMode: Bool) { selectedState = isSelected; selecting = multiSelectMode }
    func applyPlayingState(isPlaying: Bool) { playing = isPlaying }
}
final class AppKitPixabayDownloadsItem: RecordingCard {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("online")
    var onPrimaryAction: ((Int) -> Void)?; var onInspectRequested: ((Int) -> Void)?
    func beginDisplayingThumbnail() { visible = true }
    func endDisplayingThumbnail() { visible = false }
    func configure(entry: PixabayDownloadedEntry, isSelected: Bool, isMultiSelectMode: Bool,
                   isPlaying: Bool, request: ThumbnailRequest? = nil, thumbnailDemandActive: Bool?) {
        configurations += 1; selectedState = isSelected; playing = isPlaying; visible = thumbnailDemandActive ?? visible
    }
    func applySelectionState(_ selected: Bool, multiSelectMode: Bool) { self.selectedState = selected; selecting = multiSelectMode }
    func applyPlayingState(isPlaying: Bool) { playing = isPlaying }
}
final class AppKitSteamWorkshopBrowserItem: RecordingCard {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("steam")
    enum DisplayContext { case downloads }
    struct OrganizationPresentation {
        let isFavorite: Bool; let canFavorite: Bool
        var isSwitching = false
        var canPlay = true; var canDownload = true; var canCancel = true
        var onFavorite: (() -> Void)?; var onPrimary: (() -> Void)?
    }
    var organization: OrganizationPresentation?
    var onDownload: (() -> Void)?; var onCancel: (() -> Void)?; var onSet: (() -> Void)?; var onOpen: (() -> Void)?
    func applyOrganizationState(_ presentation: OrganizationPresentation, isPlaying: Bool, isMultiSelectMode: Bool, isKeyboardFocused: Bool) {
        organization = presentation; playing = isPlaying; selecting = isMultiSelectMode; selectedState = isKeyboardFocused
    }
    func setPreviewVisible(_ visible: Bool) { self.visible = visible }
    func configureMetadataOnly(displayContext: DisplayContext, isPlaying: Bool, item: SteamWorkshopBrowserItem,
        downloadRecord: SteamWorkshopDownloadRecord?, downloadProgressStore: SteamWorkshopDownloadProgressStore,
        isDownloading: Bool, isDownloaded: Bool, isMultiSelectMode: Bool, isKeyboardFocused: Bool,
        organization: OrganizationPresentation?, onOpen: (() -> Void)?, onDownload: @escaping () -> Void,
        onSetAsWallpaper: @escaping () -> Void, onCancelDownload: @escaping () -> Void) {
        configurations += 1; self.organization = organization; self.onOpen = onOpen; self.onDownload = onDownload
        self.onSet = onSetAsWallpaper; self.onCancel = onCancelDownload; playing = isPlaying
    }
}

final class AdapterCollectionDataSource: NSObject, NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        NSCollectionViewItem()
    }
}

@main enum Checks {
    static func content(_ provider: WallpaperProvider, _ id: String, canonical: WallpaperReference? = nil,
                        capabilities: WallpaperContentCapabilities = [.inspect, .play, .organize]) -> WallpaperContentItem {
        let ref = WallpaperReference(provider: provider, sourceID: id)
        return WallpaperContentItem(reference: canonical ?? ref, providerReference: ref,
            locator: .init(path: "/not-read/\(id)", titleHint: id, mediaKind: .video), title: id, kind: .video,
            publishedAvailability: capabilities.contains(.play) ? .available : .unavailable,
            capabilities: capabilities, metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let manager = WallpaperManager(), images = SILService(), steam = SteamWorkshopService(), pixabayService = PixabayService()
        manager.wallpapers = [.init(id: "1", title: "video", path: "/video"),
            .init(id: "é", title: "NFC", path: "/nfc"), .init(id: "e\u{301}", title: "NFD", path: "/nfd")]
        images.wallpapers = [.init(id: "1", path: "/image", title: "image")]
        steam.downloads = [.init(id: "1", title: "steam", status: .ready),
                           .init(id: "video:opaque", title: "legacy steam", status: .ready)]
        pixabayService.downloadedContent.entries = [.init(id: 1, localURL: URL(fileURLWithPath: "/online")),
                                            .init(id: -1, localURL: URL(fileURLWithPath: "/negative"))]
        var playing = Set<WallpaperReference>(), switching = Set<WallpaperReference>()
        var primary: [WallpaperContentItem] = [], inspections: [WallpaperContentItem] = []
        let adapter = WallpaperLibraryCellAdapter(manager: manager, images: images, steam: steam, pixabay: pixabayService,
            isPlaying: { playing.contains($0) }, isSwitching: { switching.contains($0) },
            makePrimaryAction: { content in { primary.append(content) } }, onInspect: { inspections.append($0) })
        let collection = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let collectionDataSource = AdapterCollectionDataSource()
        collection.dataSource = collectionDataSource
        collection.collectionViewLayout = NSCollectionViewFlowLayout()
        collection.reloadData()
        let state = WallpaperLibraryGridController.CellState(isSelected: false, isSelecting: false, isFocused: true, thumbnailRequest: .init(width: 320, height: 320, mode: .fill))
        func make(_ item: WallpaperContentItem) -> NSCollectionViewItem {
            adapter.makeCell(collection: collection, indexPath: IndexPath(item: 0, section: 0), content: item, state: state)
        }
        var checks: [String: Bool] = [:]
        let v = content(.videoLibrary, "1"), i = content(.staticImageLibrary, "1")
        let s = content(.steamWorkshop, "1"), o = content(.pixabay, "1")
        let video = make(v) as! AppKitWallpaperItem, image = make(i) as! SILGridItem
        let workshop = make(s) as! AppKitSteamWorkshopBrowserItem, pixabay = make(o) as! AppKitPixabayDownloadsItem
        checks["fourProvidersUseOriginalRegisteredCellClasses"] = video.presentedTitle == "video" && image.presentedTitle == "image" && workshop.organization != nil && pixabay.onPrimaryAction != nil
        checks["factoryDoesNotAcquireOffscreenDemand"] = [video, image, workshop, pixabay].allSatisfy { !$0.visible }
        for card in [video, image, workshop, pixabay] { adapter.setVisible(card, state) }
        checks["allOriginalDisplayLifecyclesReceiveVisibleDemand"] = [video, image, workshop, pixabay].allSatisfy(\.visible)
        for card in [video, image, workshop, pixabay] { adapter.setVisible(card, nil) }
        checks["allOriginalDisplayLifecyclesReleaseDemand"] = [video, image, workshop, pixabay].allSatisfy { !$0.visible }
        video.onPlayRequested?("1"); image.onApplyRequested?("1"); workshop.onSet?(); pixabay.onPrimaryAction?(1)
        checks["sameNumberAcrossProvidersDoesNotRetargetPrimary"] = primary.map(\.providerReference) == [v.providerReference, i.providerReference, s.providerReference, o.providerReference]
        primary.removeAll()
        video.onInspectRequested?("1"); image.onInspectRequested?("1"); workshop.onOpen?(); pixabay.onInspectRequested?(1)
        checks["allDetailControlsCarryCanonicalAndProviderIdentity"] = inspections.map(\.providerReference) == [v.providerReference, i.providerReference, s.providerReference, o.providerReference]
        let nfc = make(content(.videoLibrary, "é")) as! AppKitWallpaperItem
        let nfd = make(content(.videoLibrary, "e\u{301}")) as! AppKitWallpaperItem
        checks["opaqueUnicodeSourceIDsStayByteExact"] = nfc.presentedTitle == "NFC" && nfd.presentedTitle == "NFD"
        let alias = content(.videoLibrary, "1", canonical: s.reference)
        let backing = make(alias) as! AppKitWallpaperItem
        backing.onPlayRequested?("1")
        checks["sourceThumbnailIdentityAndCanonicalCommandIdentityAreSeparate"] = backing.presentedTitle == "video" && primary.last?.reference == s.reference && primary.last?.providerReference == v.providerReference
        playing = [v.reference, i.reference, o.reference, s.reference]
        let selected = WallpaperLibraryGridController.CellState(isSelected: true, isSelecting: false, isFocused: true, thumbnailRequest: .init(width: 320, height: 320, mode: .fill))
        let counts = [video.configurations, image.configurations, pixabay.configurations]
        adapter.updateCell(video, content: v, state: selected); adapter.updateCell(image, content: i, state: selected); adapter.updateCell(pixabay, content: o, state: selected)
        checks["selectionAndPlayingDoNotReconfigureMedia"] = [video.configurations, image.configurations, pixabay.configurations] == counts
        checks["threeProvidersApplySelectionAndPlaying"] = [video, image, pixabay].allSatisfy { $0.selectedState && $0.playing }
        let steamConfigurations = workshop.configurations
        adapter.updateCell(workshop, content: s, state: selected)
        checks["steamStateUpdatesDoNotRebindPreviewOrProgress"] = workshop.configurations == steamConfigurations
            && workshop.playing && workshop.selectedState
        switching = playing
        let primaryBeforeSwitching = primary.count
        for (card, content) in [(video, v), (image, i), (pixabay, o), (workshop, s)] {
            adapter.updateCell(card, content: content, state: selected)
        }
        video.onPlayRequested?("1"); image.onApplyRequested?("1"); pixabay.onPrimaryAction?(1); workshop.organization?.onPrimary?()
        checks["allProvidersReceivePendingBeforeRebindingAndCannotReissuePrimary"] = video.switching && image.switching && pixabay.switching
            && workshop.organization?.isSwitching == true && workshop.organization?.canPlay == false
            && video.onPlayRequested == nil && image.onApplyRequested == nil && pixabay.onPrimaryAction == nil
            && primary.count == primaryBeforeSwitching
        checks["pendingOnlyDoesNotReconfigureAnyProviderMedia"] = [video.configurations, image.configurations, pixabay.configurations] == counts
            && workshop.configurations == steamConfigurations
        let firstPendingImage = make(i) as! SILGridItem
        checks["firstConfiguredPendingCellReceivesSameProjection"] = firstPendingImage.switching && firstPendingImage.onApplyRequested == nil
        switching.removeAll()
        for (card, content) in [(video, v), (image, i), (pixabay, o), (workshop, s)] {
            adapter.updateCell(card, content: content, state: selected)
        }
        checks["settledPendingClearsAllProvidersAndRestoresOriginalPrimary"] = !video.switching && !image.switching && !pixabay.switching
            && workshop.organization?.isSwitching == false && workshop.organization?.canPlay == true
            && video.onPlayRequested != nil && image.onApplyRequested != nil && pixabay.onPrimaryAction != nil
        let oldPrimary = video.onPlayRequested
        let oldInspect = video.onInspectRequested, beforeInspectionReuse = inspections.count
        playing.removeAll()
        let revoked = content(.videoLibrary, "1", capabilities: [.inspect])
        adapter.updateCell(video, content: revoked, state: state)
        let before = primary.count; oldPrimary?("1")
        checks["oldCommandCannotBypassCapabilityRevocation"] = primary.count == before && video.onPlayRequested == nil && video.onInspectRequested != nil
        playing = [v.reference]
        adapter.updateCell(video, content: revoked, state: state)
        checks["unavailableActiveWallpaperStillOffersItsRealStopCommand"] = video.onPlayRequested != nil && video.playing
        playing.removeAll()
        adapter.updateCell(video, content: content(.videoLibrary, "é"), state: state)
        oldInspect?("1")
        checks["held-detail-command-cannot-borrow-a-reused-provider-binding"] = inspections.count == beforeInspectionReuse
        oldPrimary?("1")
        checks["oldReusedCallbackCannotRetargetAnotherSourceID"] = primary.count == before
        video.onPlayRequested?("é")
        checks["newReusedCallbackTargetsCurrentSourceID"] = primary.last?.providerReference.sourceID == "é"
        let missing = content(.staticImageLibrary, "missing", capabilities: [.inspect])
        let unavailable = make(missing)
        checks["missingSourceRowUsesRealUnavailableCell"] = unavailable is WallpaperLibraryUnavailableItem && !adapter.needsCellReplacement(unavailable, content: missing)
        checks["unavailableCardKeepsVoiceOverTitleWithoutHoverPathMetadata"] = unavailable.view.accessibilityLabel() == "missing，原文件不可用"
            && unavailable.view.toolTip == nil
        images.wallpapers.append(.init(id: "missing", path: "/restored", title: "restored"))
        checks["restoredSourceRequestsNativeCellReplacement"] = adapter.needsCellReplacement(unavailable, content: missing)
        let notYetPublished = make(missing) as! SILGridItem
        checks["restoredRowDoesNotOverrideUnacceptedContentCapabilities"] = notYetPublished.onApplyRequested == nil && notYetPublished.onInspectRequested != nil
        unavailable.view.frame = NSRect(x: 0, y: 0, width: 240, height: 240)
        unavailable.view.layoutSubtreeIfNeeded()
        checks["unavailableArtworkUsesSharedNativePassiveHitRoot"] = unavailable.view is WallpaperCardInteractionView
            && unavailable.view.hitTest(NSPoint(x: 120, y: 160)) === unavailable.view
        let heldImageApply = image.onApplyRequested, heldImageInspect = image.onInspectRequested
        let beforeImageReuse = (primary.count, inspections.count)
        let otherImage = content(.staticImageLibrary, "missing")
        adapter.updateCell(image, content: otherImage, state: state)
        heldImageApply?("1"); heldImageInspect?("1")
        checks["held-image-commands-stop-at-original-adapter-after-real-source-reuse"] = heldImageApply != nil && heldImageInspect != nil && primary.count == beforeImageReuse.0
            && inspections.count == beforeImageReuse.1
        image.onApplyRequested?("missing"); image.onInspectRequested?("missing")
        checks["reused-image-commands-deliver-the-new-fixed-source-once"] = primary.count == beforeImageReuse.0 + 1
            && inspections.count == beforeImageReuse.1 + 1 && primary.last?.providerReference == otherImage.providerReference
            && inspections.last?.providerReference == otherImage.providerReference
        images.wallpapers.removeAll()
        checks["removedSourceRequestsUnavailableReplacement"] = adapter.needsCellReplacement(image, content: i)
        let unavailableOnline = content(.pixabay, "1", capabilities: [.inspect, .delete])
        adapter.updateCell(pixabay, content: unavailableOnline, state: state)
        checks["presentButUnavailableSourceKeepsProviderCellWithoutPlay"] = !adapter.needsCellReplacement(pixabay, content: unavailableOnline) && pixabay.onPrimaryAction == nil && pixabay.onInspectRequested != nil
        let negative = make(content(.pixabay, "-1")) as! AppKitPixabayDownloadsItem
        negative.onPrimaryAction?(-1)
        checks["legacyNegativePixabayIdentityIsNotNarrowed"] = primary.last?.providerReference.sourceID == "-1"
        adapter.updateCell(pixabay, content: o, state: state)
        let heldPixabayApply = pixabay.onPrimaryAction, heldPixabayInspect = pixabay.onInspectRequested
        let beforePixabayReuse = (primary.count, inspections.count)
        let otherPixabay = content(.pixabay, "-1")
        adapter.updateCell(pixabay, content: otherPixabay, state: state)
        heldPixabayApply?(1); heldPixabayInspect?(1)
        checks["held-Pixabay-commands-stop-at-original-adapter-after-real-source-reuse"] = heldPixabayApply != nil && heldPixabayInspect != nil && primary.count == beforePixabayReuse.0
            && inspections.count == beforePixabayReuse.1
        pixabay.onPrimaryAction?(-1); pixabay.onInspectRequested?(-1)
        checks["reused-Pixabay-commands-deliver-the-new-fixed-source-once"] = primary.count == beforePixabayReuse.0 + 1
            && inspections.count == beforePixabayReuse.1 + 1 && primary.last?.providerReference == otherPixabay.providerReference
            && inspections.last?.providerReference == otherPixabay.providerReference
        let legacySteam = make(content(.steamWorkshop, "video:opaque"))
        checks["legacySteamOpaqueVideoIdentityRemainsVisible"] = legacySteam is AppKitSteamWorkshopBrowserItem
        let transfer = content(.steamWorkshop, "1", capabilities: [.inspect, .cancelDownload, .retryUpdate])
        adapter.updateCell(workshop, content: transfer, state: state)
        workshop.onDownload?(); workshop.onCancel?(); workshop.onSet?()
        checks["transferCommandsUseOriginalSourceOwnerAndNeverPretendPlayback"] = steam.downloadRequests == ["1"] && steam.cancellations == ["1"] && primary.last?.providerReference.sourceID == "-1"
        let oldCancel = workshop.onCancel
        adapter.updateCell(workshop, content: s, state: state); oldCancel?()
        checks["oldTransferCallbackCannotBypassCurrentCapabilities"] = steam.cancellations == ["1"]
        playing = [s.reference]
        adapter.updateCell(workshop, content: s, state: state); workshop.organization?.onPrimary?(); workshop.onOpen?()
        checks["organizationStopAndInspectorRetainExactContent"] = primary.last?.reference == s.reference && inspections.last?.providerReference == s.providerReference
        let heldInspector = workshop.onOpen
        let beforeInspectorReuse = inspections.count
        let replacementSteam = content(.steamWorkshop, "video:opaque")
        adapter.updateCell(workshop, content: replacementSteam, state: state)
        heldInspector?()
        checks["heldInspectorCallbackCannotOpenAnotherProviderRowAfterReuse"] = inspections.count == beforeInspectorReuse
        workshop.onOpen?()
        checks["reconfiguredInspectorCallbackUsesItsExactCurrentProviderReference"] = inspections.count == beforeInspectorReuse + 1
            && inspections.last?.providerReference == replacementSteam.providerReference
        adapter.updateCell(workshop, content: s, state: state)
        let pickerAdapter = WallpaperLibraryCellAdapter(manager: manager, images: images, steam: steam, pixabay: pixabayService,
            isPlaying: { _ in false },
            makePrimaryAction: { _ in nil })
        let pickerCollection = NSCollectionView(frame: collection.frame)
        pickerCollection.dataSource = collectionDataSource
        pickerCollection.collectionViewLayout = NSCollectionViewFlowLayout()
        pickerCollection.reloadData()
        let pickerCard = pickerAdapter.makeCell(collection: pickerCollection, indexPath: IndexPath(item: 0, section: 0),
            content: s, state: state) as! AppKitSteamWorkshopBrowserItem
        checks["pickerWithoutInspectorPassesRealNilRatherThanNoOpOpenClosure"] = pickerCard.onOpen == nil
        // Original thumbnail transports are recording leaves here. Their own
        // cancellation/validation gates still exercise real cache producers.
        images.wallpapers = [.init(id: "1", path: "/image", title: "image")]
        let viewportImages = images.wallpapers, viewportOnline = pixabayService.downloadedContent, viewportSteamToken = steam.previewReloadToken
        func resetSourceReads() { manager.sourceReads = 0; images.sourceReads = 0; steam.sourceReads = 0; pixabayService.sourceReads = 0 }
        func readsEachSourceOnce() -> Bool { [manager.sourceReads, images.sourceReads, steam.sourceReads, pixabayService.sourceReads] == [1, 1, 1, 1] }
        resetSourceReads()
        AdapterPrefetchAssetsProbe.references = []
        adapter.updateViewport(visible: [v, i, o, s], prefetch: [v, i, o, s, alias])
        checks["oneViewportResolvesEachProviderReferenceOnceAcrossVisiblePrefetchAndAlias"] = readsEachSourceOnce()
        let nonvideoReferences = Set([i, o, s].map(\.providerReference))
        checks["nearbyPreparesEachNonvideoReferenceOnceAcrossVisiblePrefetchAndAlias"] =
            Set(AdapterPrefetchAssetsProbe.references) == nonvideoReferences && AdapterPrefetchAssetsProbe.references.count == 3
        let scopedImageLease = SILThumbnailProvider.requests.last!.2
        let scopedOnlineLease = PixabayDownloadedThumbnailStore.requests.last!.1
        let scopedSteamLease = SteamWorkshopPreviewState.configured.last!
        images.wallpapers = [.init(id: "1", path: "/viewport-replaced", title: "same id")]
        pixabayService.downloadedContent.entries[0].thumbnailSourceKey = "viewport-replaced"
        steam.previewReloadToken += 1
        resetSourceReads()
        adapter.updateViewport(visible: [v, i, o, s], prefetch: [v, i, o, s])
        checks["nextViewportRereadsLiveSourcesAndReplacesTheOriginalLeases"] = readsEachSourceOnce()
            && scopedImageLease.cancelled && scopedOnlineLease.cancelled && scopedSteamLease.resets == 1
            && SILThumbnailProvider.requests.last?.0 == "/viewport-replaced"
        let revokedImageLease = SILThumbnailProvider.requests.last!.2, beforeSourceRemoval = SILThumbnailProvider.requests.count
        images.wallpapers = []
        resetSourceReads()
        adapter.updateViewport(visible: [v, i, o, s], prefetch: [v, i, o, s])
        checks["nextViewportMissingSourceRevokesLeaseWithoutReusingPriorResolution"] = readsEachSourceOnce()
            && revokedImageLease.cancelled && SILThumbnailProvider.requests.count == beforeSourceRemoval
        resetSourceReads()
        adapter.updateViewport(visible: [], prefetch: [])
        checks["emptyViewportDoesNotResolveSources"] = [manager.sourceReads, images.sourceReads, steam.sourceReads, pixabayService.sourceReads] == [0, 0, 0, 0]
        images.wallpapers = viewportImages; pixabayService.downloadedContent = viewportOnline; steam.previewReloadToken = viewportSteamToken
        adapter.updateViewport(visible: [], prefetch: [v, i, o, s])
        let imageLease = SILThumbnailProvider.requests.last!.2
        let pixabayLease = PixabayDownloadedThumbnailStore.requests.last!.1
        let steamLease = SteamWorkshopPreviewState.configured.last!
        checks["viewport-prefetch-enters-all-four-original-pipelines"] = AppKitThumbnailProvider.batches.last?.0 == ["1"]
            && SILThumbnailProvider.requests.last?.0 == "/image" && SILThumbnailProvider.requests.last?.1 == .prefetch
            && PixabayDownloadedThumbnailStore.requests.last?.0 == 1 && steamLease.pixelSize == 256
        let countsBeforeHandoff = (SILThumbnailProvider.requests.count, PixabayDownloadedThumbnailStore.requests.count,
                                   SteamWorkshopPreviewState.configured.count)
        AdapterPrefetchAssetsProbe.references = []
        adapter.updateViewport(visible: [v, i, o, s], prefetch: [])
        checks["near-to-visible-handoff-retains-existing-leases-without-restarting"] = !imageLease.cancelled
            && !pixabayLease.cancelled && steamLease.resets == 0 && AppKitThumbnailProvider.batches.last?.1 == ["1"]
            && countsBeforeHandoff.0 == SILThumbnailProvider.requests.count
            && countsBeforeHandoff.1 == PixabayDownloadedThumbnailStore.requests.count
            && countsBeforeHandoff.2 == SteamWorkshopPreviewState.configured.count
        checks["nearToVisibleStillChecksAssetsForEveryRetainedLease"] =
            Set(AdapterPrefetchAssetsProbe.references) == nonvideoReferences && AdapterPrefetchAssetsProbe.references.count == 3
        adapter.updateViewport(visible: [], prefetch: [])
        checks["empty-viewport-revokes-every-nonvideo-lease-and-video-demand"] = imageLease.cancelled && pixabayLease.cancelled
            && steamLease.resets == 1 && AppKitThumbnailProvider.batches.last?.0.isEmpty == true
            && AppKitThumbnailProvider.batches.last?.1.isEmpty == true
        let countsBeforeVisibleOnly = (SILThumbnailProvider.requests.count, PixabayDownloadedThumbnailStore.requests.count,
                                      SteamWorkshopPreviewState.configured.count)
        AdapterPrefetchAssetsProbe.references = []
        adapter.updateViewport(visible: [i, o, s], prefetch: [])
        checks["visible-only-cells-do-not-acquire-second-prefetch-consumers"] = countsBeforeVisibleOnly.0 == SILThumbnailProvider.requests.count
            && countsBeforeVisibleOnly.1 == PixabayDownloadedThumbnailStore.requests.count
            && countsBeforeVisibleOnly.2 == SteamWorkshopPreviewState.configured.count
        checks["visibleOnlyWithoutPrefetchLeaseSkipsAssetPreparation"] = AdapterPrefetchAssetsProbe.references.isEmpty
        adapter.updateViewport(visible: [], prefetch: [i, o, s])
        let changedImageLease = SILThumbnailProvider.requests.last!.2
        let changedOnlineLease = PixabayDownloadedThumbnailStore.requests.last!.1
        let changedSteamLease = SteamWorkshopPreviewState.configured.last!
        let countsBeforeVisibleChange = (SILThumbnailProvider.requests.count, PixabayDownloadedThumbnailStore.requests.count,
                                        SteamWorkshopPreviewState.configured.count)
        images.wallpapers = [.init(id: "1", path: "/visible-replaced", title: "same id")]
        pixabayService.downloadedContent.entries[0].thumbnailSourceKey = "visible-replaced"
        steam.previewReloadToken += 1
        AdapterPrefetchAssetsProbe.references = []
        adapter.updateViewport(visible: [i, o, s], prefetch: [])
        checks["visibleOnlyResourceChangesRetireExistingPrefetchLeasesWithoutRestart"] =
            Set(AdapterPrefetchAssetsProbe.references) == nonvideoReferences && AdapterPrefetchAssetsProbe.references.count == 3
            && changedImageLease.cancelled && changedOnlineLease.cancelled && changedSteamLease.resets == 1
            && countsBeforeVisibleChange.0 == SILThumbnailProvider.requests.count
            && countsBeforeVisibleChange.1 == PixabayDownloadedThumbnailStore.requests.count
            && countsBeforeVisibleChange.2 == SteamWorkshopPreviewState.configured.count
        images.wallpapers = viewportImages; pixabayService.downloadedContent = viewportOnline; steam.previewReloadToken = viewportSteamToken
        adapter.updateViewport(visible: [], prefetch: [i, i, o, s])
        let oldImage = SILThumbnailProvider.requests.last!.2
        let oldOnline = PixabayDownloadedThumbnailStore.requests.last!.1
        let oldSteam = SteamWorkshopPreviewState.configured.last!
        let duplicateCount = SILThumbnailProvider.requests.count
        let changedImage = WallpaperContentItem(reference: i.reference, providerReference: i.providerReference,
            locator: i.locator, title: "Metadata only", kind: i.kind, publishedAvailability: .available,
            capabilities: i.capabilities, metadata: i.metadata, acquisition: i.acquisition, update: i.update, aliases: [])
        adapter.updateViewport(visible: [], prefetch: [changedImage, o, s])
        checks["duplicate-and-metadata-only-prefetch-retain-one-consumer"] = SILThumbnailProvider.requests.count == duplicateCount && !oldImage.cancelled
        images.wallpapers[0] = .init(id: "1", path: "/image-replaced", title: "same id")
        pixabayService.downloadedContent.entries[0] = .init(id: 1, localURL: URL(fileURLWithPath: "/online-replaced"), thumbnailSourceKey: "revision-2")
        steam.previewReloadToken += 1
        adapter.updateViewport(visible: [], prefetch: [i, o, s])
        checks["same-identity-resource-replacement-revokes-old-three-provider-leases"] = oldImage.cancelled && oldOnline.cancelled
            && oldSteam.resets == 1 && SILThumbnailProvider.requests.last?.0 == "/image-replaced"
        let imageBeforeEviction = SILThumbnailProvider.requests.last!.2
        let pixabayBeforeEviction = PixabayDownloadedThumbnailStore.requests.last!.1
        let decoded = NSImage(size: NSSize(width: 10, height: 10))
        SILThumbnailProvider.sharedCache.images["/image-replaced"] = decoded
        PixabayDownloadedThumbnailStore.sharedCache.images["current-online"] = decoded
        SILThumbnailProvider.completions.last?(.image(decoded))
        PixabayDownloadedThumbnailStore.completions.last?("current-online", decoded)
        let beforeWarm = (SILThumbnailProvider.requests.count, PixabayDownloadedThumbnailStore.requests.count)
        adapter.updateViewport(visible: [], prefetch: [i, o, s])
        checks["ready-prefetch-consumers-stay-stable-while-original-caches-own-pixels"] = SILThumbnailProvider.requests.count == beforeWarm.0
            && PixabayDownloadedThumbnailStore.requests.count == beforeWarm.1
        SILThumbnailProvider.sharedCache.images.removeAll(); PixabayDownloadedThumbnailStore.sharedCache.images.removeAll()
        adapter.updateViewport(visible: [], prefetch: [i, o, s])
        checks["completed-prefetch-reheats-through-original-cache-after-eviction"] = imageBeforeEviction.cancelled && pixabayBeforeEviction.cancelled
            && SILThumbnailProvider.requests.count == beforeWarm.0 + 1 && PixabayDownloadedThumbnailStore.requests.count == beforeWarm.1 + 1
        let canceledImage = SILThumbnailProvider.requests.last!.2
        let canceledOnline = PixabayDownloadedThumbnailStore.requests.last!.1
        let beforeCanceled = (SILThumbnailProvider.requests.count, PixabayDownloadedThumbnailStore.requests.count)
        canceledImage.cancel(); canceledOnline.cancel()
        adapter.updateViewport(visible: [], prefetch: [i, o, s])
        checks["cancelled-prefetch-consumers-reacquire-without-new-source-identity"] = SILThumbnailProvider.requests.count == beforeCanceled.0 + 1
            && PixabayDownloadedThumbnailStore.requests.count == beforeCanceled.1 + 1
            && SILThumbnailProvider.requests.last!.2 !== canceledImage && PixabayDownloadedThumbnailStore.requests.last!.1 !== canceledOnline
        let uncachedOnline = PixabayDownloadedThumbnailStore.requests.last!.1
        let beforeUncached = PixabayDownloadedThumbnailStore.requests.count
        PixabayDownloadedThumbnailStore.completions.last?("source-invalidated-online", nil)
        adapter.updateViewport(visible: [], prefetch: [i, o, s])
        checks["online-uncached-nil-completion-reheats-without-source-identity-or-consumer-cancellation-signal"] =
            uncachedOnline.cancelled && PixabayDownloadedThumbnailStore.requests.count == beforeUncached + 1
        PixabayDownloadedThumbnailStore.sharedCache.failures.insert("broken-online")
        PixabayDownloadedThumbnailStore.completions.last?("broken-online", nil)
        let beforeFailureEcho = PixabayDownloadedThumbnailStore.requests.count
        adapter.updateViewport(visible: [], prefetch: [i, o, s])
        adapter.updateViewport(visible: [], prefetch: [i, o, s])
        checks["online-real-negative-cache-conclusion-keeps-bad-source-warm-across-viewport-echoes"] =
            PixabayDownloadedThumbnailStore.requests.count == beforeFailureEcho
        let resourceImage = SILThumbnailProvider.requests.last!.2
        adapter.updateViewport(visible: [], prefetch: [content(.staticImageLibrary, "1", capabilities: [.inspect])])
        checks["unavailable-content-cannot-acquire-or-retain-prefetch"] = resourceImage.cancelled
        let unicodeCount = AppKitThumbnailProvider.batches.count
        adapter.updateViewport(visible: [], prefetch: [content(.videoLibrary, "é"), content(.videoLibrary, "e\u{301}")])
        let unicodeBatch = AppKitThumbnailProvider.batches.last!.0
        checks["prefetch-preserves-byte-exact-opaque-provider-identities"] = AppKitThumbnailProvider.batches.count == unicodeCount + 1
            && unicodeBatch.count == 2 && unicodeBatch[0].utf8.elementsEqual("é".utf8)
            && unicodeBatch[1].utf8.elementsEqual("e\u{301}".utf8)
        let pickerVideo = pickerAdapter.makeCell(collection: pickerCollection, indexPath: IndexPath(item: 0, section: 0),
            content: v, state: state) as! AppKitWallpaperItem
        checks["picker-video-retains-no-detail-command-without-owner"] = pickerVideo.onInspectRequested == nil
        let library = OnlineImageLibrary.shared
        let wallID = OnlineImageAssetID(source: .wallhaven, artworkID: "opaque-wall")
        let pageID = OnlineImageAssetID(source: .pixiv, artworkID: "42", pageIndex: 2)
        let hiddenID = OnlineImageAssetID(source: .pixiv, artworkID: "42", pageIndex: 3)
        let records = [wallID, pageID, hiddenID].map { id in
            OnlineImageLocalRecord(assetID: id, title: id.artworkID, sourceURL: URL(string: "https://example.invalid/" + id.artworkID)!,
                author: nil, authorID: nil, tags: [], relativePath: UUID().uuidString + ".png", pixelWidth: 1, pixelHeight: 1,
                fileSizeBytes: 1, firstDownloadedAt: Date(), revision: UUID())
        }
        library.snapshot = .init(records: records, unavailable: Set(records.map(\.id)))
        let retryRows = records.map { OnlineImageContentProjection.local($0, url: library.localURL(for: $0)!, available: false) }
        let wallCard = make(retryRows[0]) as! OnlineImageGridItem
        let hiddenCard = make(retryRows[2]) as! OnlineImageGridItem
        // Recording views retain the real control/input projection. Visibility is
        // controlled adapter input; this window supplies a native association.
        let imageWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 320),
            styleMask: [.titled], backing: .buffered, defer: false)
        imageWindow.isReleasedWhenClosed = false
        imageWindow.contentView = wallCard.view
        adapter.setVisible(wallCard, state)
        defer { imageWindow.close() }
        let retryCount = primary.count
        wallCard.activatePrimary()
        checks["missing-online-image-card-admits-retry-without-fabricating-play"] = !retryRows[0].capabilities.contains(.play)
            && wallCard.canPerformPrimary && primary.count == retryCount + 1 && primary.last?.reference == wallID.reference
        adapter.setVisible(wallCard, state); adapter.setVisible(hiddenCard, nil)
        let configured = wallCard.configurations, hiddenUpdates = hiddenCard.transferUpdates
        resetSourceReads()
        library.progress = [wallID: 0.4, hiddenID: 0.8]
        try await Task.sleep(for: .milliseconds(20))
        checks["online-image-progress-updates-only-visible-bound-card-without-reprojection"] = wallCard.fraction == 0.4
            && !wallCard.canPerformPrimary && wallCard.configurations == configured && hiddenCard.transferUpdates == hiddenUpdates
            && [manager.sourceReads, images.sourceReads, steam.sourceReads, pixabayService.sourceReads] == [0, 0, 0, 0]
        let busyCount = primary.count; wallCard.activatePrimary()
        checks["busy-online-image-card-does-not-admit-a-second-retry"] = primary.count == busyCount
        let heldWallRetry = wallCard.heldPrimary
        adapter.updateCell(wallCard, content: retryRows[1], state: state)
        heldWallRetry?()
        checks["held-online-image-retry-cannot-target-reused-source-or-page"] = primary.count == busyCount
        library.progress = [wallID: 0.6, pageID: 0.9]
        try await Task.sleep(for: .milliseconds(20))
        checks["reused-online-image-card-consumes-only-current-page-progress"] = wallCard.fraction == 0.9 && !wallCard.canPerformPrimary
        library.progress = [wallID: 0.7]
        try await Task.sleep(for: .milliseconds(20))
        wallCard.activatePrimary()
        checks["online-image-progress-completion-reenables-exact-current-page-retry"] = wallCard.fraction == nil
            && wallCard.canPerformPrimary && primary.last?.reference == pageID.reference
        let menuProbe = ImageCancelMenuProbe()
        library.progress = [pageID: 0.3, hiddenID: 0.5]; library.cancellations = []
        let cancelMenu = menuProbe.makeMenu(retryRows[1]), cancelItem = cancelMenu.items.first!
        adapter.updateCell(wallCard, content: retryRows[2], state: state)
        _ = NSApp.sendAction(cancelItem.action!, to: cancelItem.target, from: cancelItem)
        checks["held-cancel-menu-keeps-exact-asset-page-after-card-reuse"] = library.cancellations == [pageID]
        menuProbe.workspace.presentation.selectionState.sessionID = UUID()
        _ = NSApp.sendAction(cancelItem.action!, to: cancelItem.target, from: cancelItem)
        checks["old-cancel-menu-cannot-borrow-later-selection-session"] = library.cancellations == [pageID]
        library.progress = [:]
        checks["idle-online-image-has-no-cancel-menu-action"] = menuProbe.makeMenu(retryRows[1]).items.isEmpty
        library.snapshot = .init(records: records)
        let previewRows = records.map { OnlineImageContentProjection.local($0, url: library.localURL(for: $0)!, available: true) }
        let previewCard = make(previewRows[0]) as! OnlineImageGridItem
        imageWindow.contentView = previewCard.view
        adapter.setVisible(previewCard, state)
        let wallPreview = previewCard.heldInspect
        wallPreview?()
        checks["image-card-detail-carries-its-fixed-current-asset-reference"] = wallPreview != nil && inspections.last?.reference == wallID.reference
        let previewCount = inspections.count
        adapter.updateCell(previewCard, content: previewRows[1], state: state)
        wallPreview?()
        checks["held-image-detail-cannot-borrow-a-reused-source-binding"] = inspections.count == previewCount
        let pagePreview = previewCard.heldInspect
        pagePreview?()
        checks["reused-image-detail-targets-the-real-page-asset"] = inspections.last?.providerReference == pageID.reference
        let beforePageReuse = inspections.count
        adapter.updateCell(previewCard, content: previewRows[2], state: state)
        pagePreview?()
        checks["held-image-detail-cannot-retarget-a-different-page-of-the-same-work"] = inspections.count == beforePageReuse
        let currentPreview = previewCard.heldInspect
        let originalPreview = previewRows[2]
        let renamedPreview = WallpaperContentItem(reference: originalPreview.reference, providerReference: originalPreview.providerReference,
            locator: originalPreview.locator, title: "Updated current page", kind: originalPreview.kind,
            publishedAvailability: originalPreview.publishedAvailability, capabilities: originalPreview.capabilities,
            metadata: originalPreview.metadata, acquisition: originalPreview.acquisition, update: originalPreview.update, aliases: originalPreview.aliases)
        adapter.updateCell(previewCard, content: renamedPreview, state: state)
        currentPreview?()
        checks["current-image-detail-uses-current-metadata-with-the-same-fixed-reference"] = inspections.last?.providerReference == hiddenID.reference
            && inspections.last?.title == renamedPreview.title
        let noPreview = WallpaperContentItem(reference: renamedPreview.reference, providerReference: renamedPreview.providerReference,
            locator: renamedPreview.locator, title: renamedPreview.title, kind: renamedPreview.kind,
            publishedAvailability: renamedPreview.publishedAvailability, capabilities: renamedPreview.capabilities.subtracting(.quickLook),
            metadata: renamedPreview.metadata, acquisition: renamedPreview.acquisition, update: renamedPreview.update, aliases: renamedPreview.aliases)
        adapter.updateCell(previewCard, content: noPreview, state: state)
        checks["image-card-quicklook-capability-does-not-revoke-its-explicit-detail-command"] = previewCard.heldInspect != nil
        library.snapshot = .init()

        // Small request matrix measures the real adapter, not a lookup replica.
        adapter.updateViewport(visible: [], prefetch: [])
        manager.wallpapers = [.init(id: "batch-v0", title: "v0", path: "/batch/v0"),
            .init(id: "batch-v1", title: "v1", path: "/batch/v1"),
            .init(id: "batch-v0", title: "later", path: "/batch/v0-later")]
        images.wallpapers = [.init(id: "batch-i0", path: "/batch/i0", title: "i0"),
            .init(id: "batch-i1", path: "/batch/i1", title: "i1"),
            .init(id: "batch-i0", path: "/batch/i0-later", title: "later")]
        steam.downloads = [.init(id: "batch-s0", title: "batch-first-s0", status: .ready),
            .init(id: "batch-s1", title: "batch-first-s1", status: .ready),
            .init(id: "batch-s0", title: "batch-later-s0", status: .ready)]
        pixabayService.downloadedContent.entries = [.init(id: 7, localURL: URL(fileURLWithPath: "/batch/p7")),
            .init(id: -7, localURL: URL(fileURLWithPath: "/batch/p-minus7")),
            .init(id: 0, localURL: URL(fileURLWithPath: "/batch/p-zero-unrequested")),
            .init(id: 7, localURL: URL(fileURLWithPath: "/batch/p7-later"))]
        let requested = [content(.videoLibrary, "batch-v0"), content(.videoLibrary, "batch-v1"), content(.videoLibrary, "batch-missing"),
            content(.staticImageLibrary, "batch-i0"), content(.staticImageLibrary, "batch-i1"), content(.staticImageLibrary, "batch-missing"),
            content(.steamWorkshop, "batch-s0"), content(.steamWorkshop, "batch-s1"), content(.steamWorkshop, "batch-missing"),
            content(.pixabay, "7"), content(.pixabay, "-7"), content(.pixabay, "07"), content(.pixabay, "+7"),
            content(.pixabay, "-0"), content(.pixabay, "9223372036854775808")]
        let imageStart = SILThumbnailProvider.requests.count, urlStart = PixabayDownloadedThumbnailStore.requestedURLs.count
        let titleStart = SteamWorkshopDownloadGridSupport.fallbackTitles.count
        resetSourceReads()
        adapter.updateViewport(visible: [requested[0]], prefetch: requested + [requested[0], requested[2]])
        checks["batch-reads-each-requested-source-at-most-once"] =
            [manager.sourceReads, images.sourceReads, steam.sourceReads, pixabayService.sourceReads].allSatisfy { (0...1).contains($0) }
        checks["batch-video-first-record-and-request-order-multiplicity"] = AppKitThumbnailProvider.batchPaths.last?.0 == ["/batch/v0", "/batch/v1", "/batch/v0"]
            && AppKitThumbnailProvider.batchPaths.last?.1 == ["/batch/v0"]
        checks["batch-image-first-record-order-and-missing"] = SILThumbnailProvider.requests.dropFirst(imageStart).map { $0.0 } == ["/batch/i0", "/batch/i1"]
        let resolvedTitles = Array(SteamWorkshopDownloadGridSupport.fallbackTitles.dropFirst(titleStart))
        checks["batch-steam-first-record-and-missing"] = resolvedTitles.contains("batch-first-s0")
            && resolvedTitles.contains("batch-first-s1") && !resolvedTitles.contains("batch-later-s0")
        checks["batch-pixabay-canonical-int-first-record-and-invalid-aliases"] = PixabayDownloadedThumbnailStore.requestedURLs.dropFirst(urlStart).map(\.path)
            == ["/batch/p7", "/batch/p-minus7"]
        manager.wallpapers.reverse()
        resetSourceReads()
        adapter.updateViewport(visible: [], prefetch: [requested[0], requested[2]])
        checks["batch-next-turn-observes-reordered-first-and-skips-unrequested-sources"] =
            AppKitThumbnailProvider.batchPaths.last?.0 == ["/batch/v0-later"] && (0...1).contains(manager.sourceReads)
            && images.sourceReads == 0 && steam.sourceReads == 0 && pixabayService.sourceReads == 0
        manager.wallpapers = []
        adapter.updateViewport(visible: [], prefetch: [requested[0]])
        checks["batch-next-turn-deletion-does-not-borrow-previous-record"] = AppKitThumbnailProvider.batchPaths.last?.0.isEmpty == true
        manager.wallpapers = [.init(id: "batch-v0", title: "new", path: "/batch/new-v0")]
        adapter.updateViewport(visible: [], prefetch: [requested[0]])
        checks["batch-next-turn-insert-after-miss-reads-current-path"] = AppKitThumbnailProvider.batchPaths.last?.0 == ["/batch/new-v0"]
        images.wallpapers = [.init(id: "é", path: "/batch/nfc", title: "NFC"),
            .init(id: "e\u{301}", path: "/batch/nfd", title: "NFD"),
            .init(id: "é", path: "/batch/nfc-later", title: "later")]
        steam.downloads = [.init(id: "é", title: "steam-NFC", status: .ready),
            .init(id: "e\u{301}", title: "steam-NFD", status: .ready),
            .init(id: "é", title: "steam-NFC-later", status: .ready)]
        let opaqueImageStart = SILThumbnailProvider.requests.count
        let opaqueTitleStart = SteamWorkshopDownloadGridSupport.fallbackTitles.count
        resetSourceReads()
        adapter.updateViewport(visible: [], prefetch: [content(.staticImageLibrary, "é"), content(.staticImageLibrary, "e\u{301}"),
            content(.steamWorkshop, "é"), content(.steamWorkshop, "e\u{301}")])
        checks["batch-image-opaque-UTF8-and-duplicate-first"] = SILThumbnailProvider.requests.dropFirst(opaqueImageStart).map { $0.0 }
            == ["/batch/nfc", "/batch/nfd"]
        let opaqueTitles = Array(SteamWorkshopDownloadGridSupport.fallbackTitles.dropFirst(opaqueTitleStart))
        checks["batch-steam-opaque-UTF8-and-duplicate-first"] = opaqueTitles.contains("steam-NFC") && opaqueTitles.contains("steam-NFD")
            && !opaqueTitles.contains("steam-NFC-later")
        checks["batch-opaque-sources-obey-one-read-budget"] = manager.sourceReads == 0 && pixabayService.sourceReads == 0
            && (0...1).contains(images.sourceReads) && (0...1).contains(steam.sourceReads)
        images.wallpapers.reverse()
        adapter.updateViewport(visible: [], prefetch: [content(.staticImageLibrary, "é")])
        checks["batch-image-reorder-replaces-previous-first-path"] = SILThumbnailProvider.requests.last?.0 == "/batch/nfc-later"
        images.wallpapers = []
        let lastImageLease = SILThumbnailProvider.requests.last!.2, deletedImageCount = SILThumbnailProvider.requests.count
        adapter.updateViewport(visible: [], prefetch: [content(.staticImageLibrary, "é")])
        checks["batch-image-deletion-cancels-without-reloading-old-source"] = lastImageLease.cancelled
            && SILThumbnailProvider.requests.count == deletedImageCount
        images.wallpapers = [.init(id: "é", path: "/batch/nfc-restored", title: "restored")]
        adapter.updateViewport(visible: [], prefetch: [content(.staticImageLibrary, "é")])
        checks["batch-image-insert-after-miss-uses-current-path"] = SILThumbnailProvider.requests.last?.0 == "/batch/nfc-restored"
        library.snapshot = .init(records: records)
        resetSourceReads()
        let onlineStart = SILThumbnailProvider.requests.count
        adapter.updateViewport(visible: [], prefetch: [content(.wallhaven, wallID.reference.sourceID)])
        checks["batch-online-only-skips-local-source-arrays"] =
            [manager.sourceReads, images.sourceReads, steam.sourceReads, pixabayService.sourceReads] == [0, 0, 0, 0]
            && SILThumbnailProvider.requests.count == onlineStart + 1
            && SILThumbnailProvider.requests.last?.0 == library.localURL(for: records[0])?.path
        library.snapshot = .init()
        resetSourceReads()
        adapter.updateViewport(visible: [], prefetch: [])
        checks["batch-empty-demand-does-not-read-source-arrays"] =
            [manager.sourceReads, images.sourceReads, steam.sourceReads, pixabayService.sourceReads] == [0, 0, 0, 0]

        manager.wallpapers = [.init(id: "size-video", title: "size", path: "/size-video")]
        images.wallpapers = [.init(id: "size-image", path: "/size-image", title: "size")]
        let sizeVideo = content(.videoLibrary, "size-video"), sizeImage = content(.staticImageLibrary, "size-image")
        let sizedVideo = make(sizeVideo) as! AppKitWallpaperItem, sizedImage = make(sizeImage) as! SILGridItem
        let targetImageLease = ThumbnailCacheRequestCancellation()
        sizedImage.recordedLoader?(targetImageLease) { _ in }
        checks["grid-target-reaches-original-video-card-and-sil-loader"] =
            sizedVideo.configuredRequests.last == ThumbnailRequest(width: 320, height: 320, mode: .fill) && SILThumbnailProvider.thumbnailRequests.last == ThumbnailRequest(width: 320, height: 320, mode: .fill)
        let beforeSame = (sizedVideo.configurations, sizedImage.configurations)
        adapter.updateCell(sizedVideo, content: sizeVideo, state: state)
        adapter.updateCell(sizedImage, content: sizeImage, state: state)
        checks["same-target-update-keeps-original-local-configurations"] =
            sizedVideo.configurations == beforeSame.0 && sizedImage.configurations == beforeSame.1
        let larger = WallpaperLibraryGridController.CellState(isSelected: false, isSelecting: false,
            isFocused: true, thumbnailRequest: .init(width: 640, height: 640, mode: .fill))
        adapter.updateCell(sizedVideo, content: sizeVideo, state: larger)
        adapter.updateCell(sizedImage, content: sizeImage, state: larger)
        sizedImage.recordedLoader?(ThumbnailCacheRequestCancellation()) { _ in }
        checks["new-target-reconfigures-both-original-local-cards-once"] =
            sizedVideo.configurations == beforeSame.0 + 1 && sizedImage.configurations == beforeSame.1 + 1
                && sizedVideo.configuredRequests.last == ThumbnailRequest(width: 640, height: 640, mode: .fill) && SILThumbnailProvider.thumbnailRequests.last == ThumbnailRequest(width: 640, height: 640, mode: .fill)
        adapter.updateViewport(visible: [], prefetch: [sizeVideo, sizeImage], request: .init(width: 640, height: 640, mode: .fill))
        let sizeCount = SILThumbnailProvider.requests.count, sizeLease = SILThumbnailProvider.requests.last!.2
        checks["visible-and-nearby-use-the-same-target-value"] =
            AppKitThumbnailProvider.thumbnailRequests.last == ThumbnailRequest(width: 640, height: 640, mode: .fill) && SILThumbnailProvider.thumbnailRequests.last == ThumbnailRequest(width: 640, height: 640, mode: .fill)
        adapter.updateViewport(visible: [], prefetch: [sizeVideo, sizeImage], request: .init(width: 640, height: 640, mode: .fill))
        checks["same-target-keeps-the-current-prefetch-lease"] =
            !sizeLease.cancelled && SILThumbnailProvider.requests.count == sizeCount
        adapter.updateViewport(visible: [], prefetch: [sizeVideo, sizeImage], request: .init(width: 320, height: 320, mode: .fill))
        checks["new-target-retires-obsolete-nearby-interest"] = sizeLease.cancelled
            && SILThumbnailProvider.requests.count == sizeCount + 1 && SILThumbnailProvider.thumbnailRequests.last == ThumbnailRequest(width: 320, height: 320, mode: .fill)

        for (surface, subject) in [("mixed", adapter), ("picker", pickerAdapter)] {
            subject.updateViewport(visible: [], prefetch: [])
            let source = URL(string: "https://fixture.invalid/steam-sized-\(surface)")!
            var record = SteamWorkshopDownloadRecord(id: "steam-sized", title: "Steam sized", status: .ready, previewURL: source)
            steam.downloads = [record]
            let steamContent = content(.steamWorkshop, record.id)
            var previous: SteamWorkshopPreviewState?
            var previousTier: Int?
            for (width, tier) in [(256, 256), (257, 512), (512, 512), (513, 800), (900, 800)] {
                let before = SteamWorkshopPreviewState.configured.count
                subject.updateViewport(visible: [], prefetch: [steamContent], request: .init(width: width, height: width, mode: .fill))
                let current = SteamWorkshopPreviewState.configured.last!
                checks["\(surface)-steam-\(width)-backing-pixels-prefetches-\(tier)-tier"] = current.pixelSize == tier
                    && current.previewURL == source
                if let previous, previousTier == tier {
                    checks["\(surface)-steam-same-\(tier)-tier-geometry-keeps-one-prefetch"] = current === previous
                        && previous.resets == 0 && SteamWorkshopPreviewState.configured.count == before
                } else {
                    checks["\(surface)-steam-enter-\(tier)-tier-retires-only-old-interest"] = SteamWorkshopPreviewState.configured.count == before + 1
                        && (previous.map { $0.resets == 1 } ?? true)
                }
                previous = current; previousTier = tier
            }
            let ready = previous!, configured = SteamWorkshopPreviewState.configured.count
            subject.updateViewport(visible: [steamContent], prefetch: [], request: .init(width: 799, height: 799, mode: .fill))
            checks["\(surface)-steam-same-tier-nearby-to-visible-keeps-original-interest"] = ready.resets == 0
                && SteamWorkshopPreviewState.configured.count == configured
            let smaller = ThumbnailRequest(width: 320, height: 320, mode: .fill)
            subject.updateViewport(visible: [steamContent], prefetch: [], request: smaller)
            checks["\(surface)-steam-visible-tier-change-retires-obsolete-prefetch-without-duplicate"] = ready.resets == 1
                && SteamWorkshopPreviewState.configured.count == configured
            subject.updateViewport(visible: [], prefetch: [steamContent], request: smaller)
            let renewed = SteamWorkshopPreviewState.configured.last!
            let replacement = source.appendingPathComponent("replacement")
            record.previewURL = replacement; steam.downloads = [record]
            subject.updateViewport(visible: [], prefetch: [steamContent], request: smaller)
            let changed = SteamWorkshopPreviewState.configured.last!
            checks["\(surface)-steam-same-tier-source-replacement-revokes-old-interest"] = renewed.resets == 1
                && changed !== renewed && changed.pixelSize == 512 && changed.previewURL == replacement
            steam.previewReloadToken += 1
            subject.updateViewport(visible: [], prefetch: [steamContent], request: smaller)
            let reloaded = SteamWorkshopPreviewState.configured.last!
            checks["\(surface)-steam-preview-reload-revokes-same-source-and-tier"] = changed.resets == 1
                && reloaded !== changed && reloaded.pixelSize == 512 && reloaded.refreshToken == steam.previewReloadToken
            subject.updateViewport(visible: [], prefetch: [])
            checks["\(surface)-steam-targeted-prefetch-leaves-no-interest-after-close"] = reloaded.resets == 1
        }

        for synchronous in [true, false] {
            let mode = synchronous ? "synchronous" : "asynchronous"
            adapter.updateViewport(visible: [], prefetch: [])
            SteamWorkshopPreviewState.configured.removeAll()
            SteamWorkshopPreviewState.completesSynchronously = synchronous
            let source = URL(string: "https://fixture.invalid/steam-lifetime-\(mode)")!
            steam.downloads = [.init(id: mode, title: mode, status: .ready, previewURL: source)]
            let row = content(.steamWorkshop, mode)
            let target = ThumbnailRequest(width: 512, height: 512, mode: .fill)
            adapter.updateViewport(visible: [], prefetch: [row], request: target)
            weak var observed = SteamWorkshopPreviewState.configured.last
            SteamWorkshopPreviewState.configured.removeAll()
            if !synchronous {
                checks["steam-pending-preview-remains-owned-without-observation-registry"] = observed != nil
                observed?.deliver(NSImage(size: NSSize(width: 48, height: 48)))
            }
            checks["steam-\(mode)-success-releases-nondisplay-state"] = observed == nil
                && SteamWorkshopPreviewState.cache.images[source.absoluteString] != nil
            let configured = SteamWorkshopPreviewState.configurationCount
            adapter.updateViewport(visible: [], prefetch: [row], request: target)
            checks["steam-\(mode)-completed-interest-does-not-recreate-state"] = SteamWorkshopPreviewState.configurationCount == configured
            SteamWorkshopPreviewState.cache.images.removeAll()
            adapter.updateViewport(visible: [], prefetch: [row], request: target)
            adapter.updateViewport(visible: [row], prefetch: [], request: target)
            checks["steam-\(mode)-eviction-keeps-best-effort-interest-without-decode-loop"] = SteamWorkshopPreviewState.configurationCount == configured
                && SteamWorkshopPreviewState.cache.images.isEmpty
            adapter.updateViewport(visible: [], prefetch: [])
        }
        SteamWorkshopPreviewState.completesSynchronously = false
        steam.downloads = [.init(id: "pending-lifetime", title: "Pending", status: .ready)]
        let pendingRow = content(.steamWorkshop, "pending-lifetime")
        adapter.updateViewport(visible: [], prefetch: [pendingRow])
        weak var failed = SteamWorkshopPreviewState.configured.last
        SteamWorkshopPreviewState.configured.removeAll()
        failed?.deliver(nil)
        let beforeSteamFailureEcho = SteamWorkshopPreviewState.configurationCount
        adapter.updateViewport(visible: [], prefetch: [pendingRow])
        checks["steam-nil-presentation-keeps-state-for-original-retry-and-fallback"] = failed != nil
            && SteamWorkshopPreviewState.configurationCount == beforeSteamFailureEcho
        let beforePendingCancel = SteamWorkshopPreviewState.resetCount
        adapter.updateViewport(visible: [], prefetch: [])
        checks["steam-pending-cancel-resets-and-releases-state"] = failed == nil
            && SteamWorkshopPreviewState.resetCount == beforePendingCancel + 1

        let lateSource = URL(string: "https://fixture.invalid/steam-late-lifetime")!
        var lateRecord = SteamWorkshopDownloadRecord(id: "late-lifetime", title: "Late", status: .ready, previewURL: lateSource)
        steam.downloads = [lateRecord]
        let lateRow = content(.steamWorkshop, lateRecord.id)
        adapter.updateViewport(visible: [], prefetch: [lateRow])
        let retired = SteamWorkshopPreviewState.configured.last!
        lateRecord.previewURL = lateSource.appendingPathComponent("replacement"); steam.downloads = [lateRecord]
        adapter.updateViewport(visible: [], prefetch: [lateRow])
        weak var replacement = SteamWorkshopPreviewState.configured.last
        SteamWorkshopPreviewState.configured.removeAll()
        // Inject beyond the leaf's reset to test the Adapter's weak old-demand
        // receipt; the real State's generation rejection has its own gate.
        retired.deliver(NSImage(size: NSSize(width: 48, height: 48)))
        checks["steam-late-success-on-reset-state-cannot-retire-current-source-interest"] = retired.resets == 1
            && replacement != nil && replacement?.resets == 0
        let beforeReplacementCancel = SteamWorkshopPreviewState.resetCount
        adapter.updateViewport(visible: [], prefetch: [])
        checks["steam-late-reset-callback-leaves-current-cancel-effective"] = replacement == nil
            && SteamWorkshopPreviewState.resetCount == beforeReplacementCancel + 1
        SteamWorkshopPreviewState.cache.images.removeAll()

        let data = try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
