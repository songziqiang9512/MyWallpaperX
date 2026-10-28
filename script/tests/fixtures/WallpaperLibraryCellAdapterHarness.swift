import AppKit
import Combine

// Owners and media transports are recording leaves. The complete production
// App adapter, its native makeItem path and value models are compiled unchanged.
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
    static func fallbackDisplayItem(for row: SteamWorkshopDownloadRecord) -> SteamWorkshopBrowserItem {
        .init(id: row.id, title: row.title)
    }
}
enum ThumbnailCacheRequestPriority { case visible, prefetch }
final class ThumbnailCacheRequestCancellation { var cancelled = false; func cancel() { cancelled = true } }
final class AppKitThumbnailProvider {
    static var batches: [([String], [String])] = []
    static var cancelled = 0
    init(wallpaperManager: WallpaperManager) {}
    func replacePrefetch(with values: [VideoWallpaper], retainingVisible: [VideoWallpaper]) {
        Self.batches.append((values.map(\.id), retainingVisible.map(\.id)))
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
    func cachedImage(forKey key: String) -> NSImage? { images[key] }
    func hasCachedResult(forKey key: String) -> Bool { images[key] != nil || failures.contains(key) }
}
enum PixabayDownloadedThumbnailStore {
    static let sharedCache = RecordingThumbnailCache()
    static var completions: [(String, NSImage?) -> Void] = []
    static var requests: [(Int, ThumbnailCacheRequestCancellation)] = []
    static func loadThumbnail(_ entry: PixabayDownloadedEntry, priority: ThumbnailCacheRequestPriority,
        cancellation: ThumbnailCacheRequestCancellation,
                         completion: @escaping (String, NSImage?) -> Void) { requests.append((entry.id, cancellation)); completions.append(completion) }
}
func steamWorkshopPreviewSources(item: SteamWorkshopBrowserItem, record: SteamWorkshopDownloadRecord)
    -> (primary: URL?, fallback: URL?) { (URL(string: "https://fixture.invalid/" + item.id), nil) }
final class SteamWorkshopPreviewState {
    struct Loaders { static func live(priority: ThumbnailCacheRequestPriority) -> Loaders { Loaders() } }
    static var configured: [SteamWorkshopPreviewState] = []
    var resets = 0
    var pixelSize: Int?
    init(loaders: Loaders) {}
    func configure(previewURL: URL?, fallbackImageURL: URL?, fallbackVideoURL: URL?, refreshToken: Int, maxPixelSize: Int) {
        pixelSize = maxPixelSize; Self.configured.append(self)
    }
    func reset() { resets += 1 }
}
enum SILThumbnailLoadResult { case image(NSImage), unavailable }
final class SILThumbnailProvider {
    static let sharedCache = RecordingThumbnailCache()
    let cache = SILThumbnailProvider.sharedCache
    static var completions: [(SILThumbnailLoadResult) -> Void] = []
    static var requests: [(String, ThumbnailCacheRequestPriority, ThumbnailCacheRequestCancellation)] = []
    func load(path: String, priority: ThumbnailCacheRequestPriority = .visible,
              cancellation: ThumbnailCacheRequestCancellation, completion: @escaping (SILThumbnailLoadResult) -> Void) {
        Self.requests.append((path, priority, cancellation)); Self.completions.append(completion)
    }
}
final class WallpaperLibraryGridController {
    struct CellState { let isSelected: Bool; let isSelecting: Bool; let isFocused: Bool }
}
class AppearanceAwareContainerView: NSView { var appearanceDidChangeHandler: (() -> Void)? }
class RecordingCard: NSCollectionViewItem {
    var configurations = 0; var visible = false; var playing = false
    var switching = false
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
    func setThumbnailVisible(_ value: Bool) { visible = value }
    func configure(content: WallpaperContentItem, request: Any?, selected: Bool, selecting: Bool,
                   playing: Bool, switching: Bool = false, busy: Bool = false, fraction: Double? = nil, refreshToken: UUID? = nil,
                   onPrimary: (() -> Void)?, onInspect: (() -> Void)?) {
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
                   multiSelectMode: Bool, wallpaperManager: WallpaperManager, thumbnailProvider: AppKitThumbnailProvider) {
        configurations += 1; presentedTitle = wallpaper.title; selectedState = isSelected; playing = isPlaying
    }
    func applySelectionState(isSelected: Bool, multiSelectMode: Bool) { selectedState = isSelected; selecting = multiSelectMode }
    func applyPlayingState(isPlaying: Bool) { playing = isPlaying }
}
final class SILGridItem: RecordingCard {
    static let reuseID = NSUserInterfaceItemIdentifier("image")
    var onApplyRequested: ((String) -> Void)?; var onInspectRequested: ((String) -> Void)?
    func setThumbnailVisible(_ visible: Bool) { self.visible = visible }
    func configure(wallpaper: SILWallpaper, isSelected: Bool, isMultiSelectMode: Bool,
                   thumbnailVisible: Bool, isPlaying: Bool,
                   thumbnailLoader: @escaping (ThumbnailCacheRequestCancellation, @escaping (SILThumbnailLoadResult) -> Void) -> Void) {
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
                   isPlaying: Bool, thumbnailDemandActive: Bool?) {
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
        let state = WallpaperLibraryGridController.CellState(isSelected: false, isSelecting: false, isFocused: true)
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
        for card in [video, image, workshop, pixabay] { adapter.setVisible(card, true) }
        checks["allOriginalDisplayLifecyclesReceiveVisibleDemand"] = [video, image, workshop, pixabay].allSatisfy(\.visible)
        for card in [video, image, workshop, pixabay] { adapter.setVisible(card, false) }
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
        let selected = WallpaperLibraryGridController.CellState(isSelected: true, isSelecting: false, isFocused: true)
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
        adapter.updateViewport(visible: [v, i, o, s], prefetch: [v, i, o, s, alias])
        checks["oneViewportResolvesEachProviderReferenceOnceAcrossVisiblePrefetchAndAlias"] = readsEachSourceOnce()
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
        adapter.updateViewport(visible: [v, i, o, s], prefetch: [])
        checks["near-to-visible-handoff-retains-existing-leases-without-restarting"] = !imageLease.cancelled
            && !pixabayLease.cancelled && steamLease.resets == 0 && AppKitThumbnailProvider.batches.last?.1 == ["1"]
            && countsBeforeHandoff.0 == SILThumbnailProvider.requests.count
            && countsBeforeHandoff.1 == PixabayDownloadedThumbnailStore.requests.count
            && countsBeforeHandoff.2 == SteamWorkshopPreviewState.configured.count
        adapter.updateViewport(visible: [], prefetch: [])
        checks["empty-viewport-revokes-every-nonvideo-lease-and-video-demand"] = imageLease.cancelled && pixabayLease.cancelled
            && steamLease.resets == 1 && AppKitThumbnailProvider.batches.last?.0.isEmpty == true
            && AppKitThumbnailProvider.batches.last?.1.isEmpty == true
        let countsBeforeVisibleOnly = (SILThumbnailProvider.requests.count, PixabayDownloadedThumbnailStore.requests.count,
                                      SteamWorkshopPreviewState.configured.count)
        adapter.updateViewport(visible: [i, o, s], prefetch: [])
        checks["visible-only-cells-do-not-acquire-second-prefetch-consumers"] = countsBeforeVisibleOnly.0 == SILThumbnailProvider.requests.count
            && countsBeforeVisibleOnly.1 == PixabayDownloadedThumbnailStore.requests.count
            && countsBeforeVisibleOnly.2 == SteamWorkshopPreviewState.configured.count
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
        adapter.setVisible(wallCard, true)
        defer { imageWindow.close() }
        let retryCount = primary.count
        wallCard.activatePrimary()
        checks["missing-online-image-card-admits-retry-without-fabricating-play"] = !retryRows[0].capabilities.contains(.play)
            && wallCard.canPerformPrimary && primary.count == retryCount + 1 && primary.last?.reference == wallID.reference
        adapter.setVisible(wallCard, true); adapter.setVisible(hiddenCard, false)
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
        adapter.setVisible(previewCard, true)
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
        let data = try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
