import AppKit

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
struct OLDownloadedEntry: Equatable { let id: Int; let localURL: URL; var thumbnailSourceKey: String? = nil }
struct DownloadedSnapshot { var entries: [OLDownloadedEntry] = [] }
final class OnlineLibraryService {
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
    func cachedImage(forKey key: String) -> NSImage? { images[key] }
}
enum OLDownloadedThumbnailStore {
    static let sharedCache = RecordingThumbnailCache()
    static var completions: [(String, NSImage?) -> Void] = []
    static var requests: [(Int, ThumbnailCacheRequestCancellation)] = []
    static func prefetch(_ entry: OLDownloadedEntry, cancellation: ThumbnailCacheRequestCancellation,
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
protocol WallpaperGridHoverItem: NSCollectionViewItem { func refreshGridHover(isScrolling: Bool) }
extension NSView {
    var isGridPointerInside: Bool { false }
    var isGridHoverSuppressed: Bool { false }
}
final class WallpaperGridHoverTracking {
    func update(in view: NSView, owner: AnyObject, isScrolling: Bool? = nil) {}
}
class AppearanceAwareContainerView: NSView { var appearanceDidChangeHandler: (() -> Void)? }
class RecordingCard: NSCollectionViewItem {
    var configurations = 0; var visible = false; var favorite = false; var playing = false
    var switching = false
    var presentedTitle = ""; var selectedState = false; var selecting = false
    override func loadView() { view = NSView() }
    func applySwitchingState(isSwitching: Bool) { switching = isSwitching }
}
final class AppKitWallpaperItem: RecordingCard {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("video")
    var onPlayRequested: ((String) -> Void)?; var onFavoriteRequested: ((String) -> Void)?
    func setThumbnailVisible(_ visible: Bool) { self.visible = visible }
    func configure(wallpaper: VideoWallpaper, isSelected: Bool, isPlaying: Bool, isFavorite: Bool,
                   multiSelectMode: Bool, wallpaperManager: WallpaperManager, thumbnailProvider: AppKitThumbnailProvider) {
        configurations += 1; presentedTitle = wallpaper.title; selectedState = isSelected; playing = isPlaying; favorite = isFavorite
    }
    func applySelectionState(isSelected: Bool, multiSelectMode: Bool) { selectedState = isSelected; selecting = multiSelectMode }
    func applyFavoriteState(isFavorite: Bool) { favorite = isFavorite }
    func applyPlayingState(isPlaying: Bool) { playing = isPlaying }
}
final class SILGridItem: RecordingCard {
    static let reuseID = NSUserInterfaceItemIdentifier("image")
    var onApplyRequested: ((String) -> Void)?; var onToggleFavorite: ((String) -> Void)?
    func setThumbnailVisible(_ visible: Bool) { self.visible = visible }
    func configure(wallpaper: SILWallpaper, isSelected: Bool, isMultiSelectMode: Bool,
                   thumbnailVisible: Bool, isFavorite: Bool, isPlaying: Bool,
                   thumbnailLoader: @escaping (ThumbnailCacheRequestCancellation, @escaping (SILThumbnailLoadResult) -> Void) -> Void) {
        configurations += 1; presentedTitle = wallpaper.title; selectedState = isSelected; visible = thumbnailVisible
        favorite = isFavorite; playing = isPlaying
    }
    func applySelectionState(isSelected: Bool, multiSelectMode: Bool) { selectedState = isSelected; selecting = multiSelectMode }
    func applyFavoriteState(isFavorite: Bool) { favorite = isFavorite }
    func applyPlayingState(isPlaying: Bool) { playing = isPlaying }
}
final class AppKitOLDownloadsItem: RecordingCard {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("online")
    var onPrimaryAction: ((Int) -> Void)?; var onToggleFavorite: ((Int) -> Void)?
    var stop = false
    func beginDisplayingThumbnail() { visible = true }
    func endDisplayingThumbnail() { visible = false }
    func configure(entry: OLDownloadedEntry, isSelected: Bool, isMultiSelectMode: Bool,
                   isPlaying: Bool, thumbnailDemandActive: Bool?) {
        configurations += 1; selectedState = isSelected; playing = isPlaying; visible = thumbnailDemandActive ?? visible
    }
    func applySelectionState(_ selected: Bool, multiSelectMode: Bool) { self.selectedState = selected; selecting = multiSelectMode }
    func applyPlayingState(isPlaying: Bool) { playing = isPlaying }
    func applyOrganizationState(isFavorite: Bool, primaryShowsStop: Bool) { favorite = isFavorite; stop = primaryShowsStop }
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
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let manager = WallpaperManager(), images = SILService(), steam = SteamWorkshopService(), online = OnlineLibraryService()
        manager.wallpapers = [.init(id: "1", title: "video", path: "/video"),
            .init(id: "é", title: "NFC", path: "/nfc"), .init(id: "e\u{301}", title: "NFD", path: "/nfd")]
        images.wallpapers = [.init(id: "1", path: "/image", title: "image")]
        steam.downloads = [.init(id: "1", title: "steam", status: .ready),
                           .init(id: "video:opaque", title: "legacy steam", status: .ready)]
        online.downloadedContent.entries = [.init(id: 1, localURL: URL(fileURLWithPath: "/online")),
                                            .init(id: -1, localURL: URL(fileURLWithPath: "/negative"))]
        var favorites = Set<WallpaperReference>(), playing = Set<WallpaperReference>(), switching = Set<WallpaperReference>()
        var primary: [WallpaperContentItem] = [], favorite: [WallpaperContentItem] = [], inspections: [WallpaperContentItem] = []
        let adapter = WallpaperLibraryCellAdapter(manager: manager, images: images, steam: steam, online: online,
            isFavorite: { favorites.contains($0) }, isPlaying: { playing.contains($0) }, isSwitching: { switching.contains($0) },
            makePrimaryAction: { content in { primary.append(content) } }, makeFavoriteAction: { content in
                guard content.capabilities.contains(.organize) || favorites.contains(content.reference) else { return nil }
                return { favorite.append(content) }
            }, onInspect: { inspections.append($0) })
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
        let workshop = make(s) as! AppKitSteamWorkshopBrowserItem, pixabay = make(o) as! AppKitOLDownloadsItem
        checks["fourProvidersUseOriginalRegisteredCellClasses"] = video.presentedTitle == "video" && image.presentedTitle == "image" && workshop.organization != nil && pixabay.stop
        checks["factoryDoesNotAcquireOffscreenDemand"] = [video, image, workshop, pixabay].allSatisfy { !$0.visible }
        for card in [video, image, workshop, pixabay] { adapter.setVisible(card, true) }
        checks["allOriginalDisplayLifecyclesReceiveVisibleDemand"] = [video, image, workshop, pixabay].allSatisfy(\.visible)
        for card in [video, image, workshop, pixabay] { adapter.setVisible(card, false) }
        checks["allOriginalDisplayLifecyclesReleaseDemand"] = [video, image, workshop, pixabay].allSatisfy { !$0.visible }
        video.onPlayRequested?("1"); image.onApplyRequested?("1"); workshop.onSet?(); pixabay.onPrimaryAction?(1)
        checks["sameNumberAcrossProvidersDoesNotRetargetPrimary"] = primary.map(\.providerReference) == [v.providerReference, i.providerReference, s.providerReference, o.providerReference]
        primary.removeAll()
        video.onFavoriteRequested?("1"); image.onToggleFavorite?("1"); workshop.organization?.onFavorite?(); pixabay.onToggleFavorite?(1)
        checks["allFavoritesUseCanonicalRelationsNotAccountSubscription"] = favorite.map(\.reference) == [v.reference, i.reference, s.reference, o.reference]
        let nfc = make(content(.videoLibrary, "é")) as! AppKitWallpaperItem
        let nfd = make(content(.videoLibrary, "e\u{301}")) as! AppKitWallpaperItem
        checks["opaqueUnicodeSourceIDsStayByteExact"] = nfc.presentedTitle == "NFC" && nfd.presentedTitle == "NFD"
        let alias = content(.videoLibrary, "1", canonical: s.reference)
        let backing = make(alias) as! AppKitWallpaperItem
        backing.onPlayRequested?("1")
        checks["sourceThumbnailIdentityAndCanonicalCommandIdentityAreSeparate"] = backing.presentedTitle == "video" && primary.last?.reference == s.reference && primary.last?.providerReference == v.providerReference
        favorites = [v.reference, i.reference, o.reference, s.reference]; playing = favorites
        let selected = WallpaperLibraryGridController.CellState(isSelected: true, isSelecting: false, isFocused: true)
        let counts = [video.configurations, image.configurations, pixabay.configurations]
        adapter.updateCell(video, content: v, state: selected); adapter.updateCell(image, content: i, state: selected); adapter.updateCell(pixabay, content: o, state: selected)
        checks["selectionFavoriteAndPlayingDoNotReconfigureMedia"] = [video.configurations, image.configurations, pixabay.configurations] == counts
        checks["threeProvidersApplyCurrentFavoriteAndPlayingState"] = [video, image, pixabay].allSatisfy { $0.selectedState && $0.favorite && $0.playing }
        let steamConfigurations = workshop.configurations
        adapter.updateCell(workshop, content: s, state: selected)
        checks["steamStateUpdatesDoNotRebindPreviewOrProgress"] = workshop.configurations == steamConfigurations
            && workshop.organization?.isFavorite == true && workshop.playing && workshop.selectedState
        switching = favorites
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
        playing.removeAll()
        favorites.remove(v.reference)
        let revoked = content(.videoLibrary, "1", capabilities: [.inspect])
        adapter.updateCell(video, content: revoked, state: state)
        let before = primary.count; oldPrimary?("1")
        checks["oldCommandCannotBypassCapabilityRevocation"] = primary.count == before && video.onPlayRequested == nil && video.onFavoriteRequested == nil
        playing = [v.reference]
        adapter.updateCell(video, content: revoked, state: state)
        checks["unavailableActiveWallpaperStillOffersItsRealStopCommand"] = video.onPlayRequested != nil && video.playing
        playing.removeAll()
        adapter.updateCell(video, content: content(.videoLibrary, "é"), state: state)
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
        checks["restoredRowDoesNotOverrideUnacceptedContentCapabilities"] = notYetPublished.onApplyRequested == nil && notYetPublished.onToggleFavorite == nil
        unavailable.view.frame = NSRect(x: 0, y: 0, width: 240, height: 240)
        unavailable.view.layoutSubtreeIfNeeded()
        checks["unavailableArtworkUsesSharedNativePassiveHitRoot"] = unavailable.view is WallpaperCardInteractionView
            && unavailable.view.hitTest(NSPoint(x: 120, y: 160)) === unavailable.view
        images.wallpapers.removeAll()
        checks["removedSourceRequestsUnavailableReplacement"] = adapter.needsCellReplacement(image, content: i)
        favorites.remove(o.reference)
        let unavailableOnline = content(.pixabay, "1", capabilities: [.inspect, .delete])
        adapter.updateCell(pixabay, content: unavailableOnline, state: state)
        checks["presentButUnavailableSourceKeepsProviderCellWithoutPlay"] = !adapter.needsCellReplacement(pixabay, content: unavailableOnline) && pixabay.onPrimaryAction == nil && pixabay.onToggleFavorite == nil
        let negative = make(content(.pixabay, "-1")) as! AppKitOLDownloadsItem
        negative.onPrimaryAction?(-1)
        checks["legacyNegativePixabayIdentityIsNotNarrowed"] = primary.last?.providerReference.sourceID == "-1"
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
        let pickerAdapter = WallpaperLibraryCellAdapter(manager: manager, images: images, steam: steam, online: online,
            isFavorite: { _ in false }, isPlaying: { _ in false },
            makePrimaryAction: { _ in nil })
        let pickerCollection = NSCollectionView(frame: collection.frame)
        pickerCollection.dataSource = collectionDataSource
        pickerCollection.collectionViewLayout = NSCollectionViewFlowLayout()
        pickerCollection.reloadData()
        let pickerCard = pickerAdapter.makeCell(collection: pickerCollection, indexPath: IndexPath(item: 0, section: 0),
            content: s, state: state) as! AppKitSteamWorkshopBrowserItem
        checks["pickerWithoutInspectorPassesRealNilRatherThanNoOpOpenClosure"] = pickerCard.onOpen == nil
        checks["pickerWithoutFavoriteOwnerDoesNotAdvertiseNoOpHeart"] = pickerCard.organization?.canFavorite == false
        // Original thumbnail transports are recording leaves here. Their own
        // cancellation/validation gates still exercise real cache producers.
        images.wallpapers = [.init(id: "1", path: "/image", title: "image")]
        let viewportImages = images.wallpapers, viewportOnline = online.downloadedContent, viewportSteamToken = steam.previewReloadToken
        func resetSourceReads() { manager.sourceReads = 0; images.sourceReads = 0; steam.sourceReads = 0; online.sourceReads = 0 }
        func readsEachSourceOnce() -> Bool { [manager.sourceReads, images.sourceReads, steam.sourceReads, online.sourceReads] == [1, 1, 1, 1] }
        resetSourceReads()
        adapter.updateViewport(visible: [v, i, o, s], prefetch: [v, i, o, s, alias])
        checks["oneViewportResolvesEachProviderReferenceOnceAcrossVisiblePrefetchAndAlias"] = readsEachSourceOnce()
        let scopedImageLease = SILThumbnailProvider.requests.last!.2
        let scopedOnlineLease = OLDownloadedThumbnailStore.requests.last!.1
        let scopedSteamLease = SteamWorkshopPreviewState.configured.last!
        images.wallpapers = [.init(id: "1", path: "/viewport-replaced", title: "same id")]
        online.downloadedContent.entries[0].thumbnailSourceKey = "viewport-replaced"
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
        checks["emptyViewportDoesNotResolveSources"] = [manager.sourceReads, images.sourceReads, steam.sourceReads, online.sourceReads] == [0, 0, 0, 0]
        images.wallpapers = viewportImages; online.downloadedContent = viewportOnline; steam.previewReloadToken = viewportSteamToken
        adapter.updateViewport(visible: [], prefetch: [v, i, o, s])
        let imageLease = SILThumbnailProvider.requests.last!.2
        let onlineLease = OLDownloadedThumbnailStore.requests.last!.1
        let steamLease = SteamWorkshopPreviewState.configured.last!
        checks["viewport-prefetch-enters-all-four-original-pipelines"] = AppKitThumbnailProvider.batches.last?.0 == ["1"]
            && SILThumbnailProvider.requests.last?.0 == "/image" && SILThumbnailProvider.requests.last?.1 == .prefetch
            && OLDownloadedThumbnailStore.requests.last?.0 == 1 && steamLease.pixelSize == 256
        let countsBeforeHandoff = (SILThumbnailProvider.requests.count, OLDownloadedThumbnailStore.requests.count,
                                   SteamWorkshopPreviewState.configured.count)
        adapter.updateViewport(visible: [v, i, o, s], prefetch: [])
        checks["near-to-visible-handoff-retains-existing-leases-without-restarting"] = !imageLease.cancelled
            && !onlineLease.cancelled && steamLease.resets == 0 && AppKitThumbnailProvider.batches.last?.1 == ["1"]
            && countsBeforeHandoff.0 == SILThumbnailProvider.requests.count
            && countsBeforeHandoff.1 == OLDownloadedThumbnailStore.requests.count
            && countsBeforeHandoff.2 == SteamWorkshopPreviewState.configured.count
        adapter.updateViewport(visible: [], prefetch: [])
        checks["empty-viewport-revokes-every-nonvideo-lease-and-video-demand"] = imageLease.cancelled && onlineLease.cancelled
            && steamLease.resets == 1 && AppKitThumbnailProvider.batches.last?.0.isEmpty == true
            && AppKitThumbnailProvider.batches.last?.1.isEmpty == true
        let countsBeforeVisibleOnly = (SILThumbnailProvider.requests.count, OLDownloadedThumbnailStore.requests.count,
                                      SteamWorkshopPreviewState.configured.count)
        adapter.updateViewport(visible: [i, o, s], prefetch: [])
        checks["visible-only-cells-do-not-acquire-second-prefetch-consumers"] = countsBeforeVisibleOnly.0 == SILThumbnailProvider.requests.count
            && countsBeforeVisibleOnly.1 == OLDownloadedThumbnailStore.requests.count
            && countsBeforeVisibleOnly.2 == SteamWorkshopPreviewState.configured.count
        adapter.updateViewport(visible: [], prefetch: [i, i, o, s])
        let oldImage = SILThumbnailProvider.requests.last!.2
        let oldOnline = OLDownloadedThumbnailStore.requests.last!.1
        let oldSteam = SteamWorkshopPreviewState.configured.last!
        let duplicateCount = SILThumbnailProvider.requests.count
        let changedImage = WallpaperContentItem(reference: i.reference, providerReference: i.providerReference,
            locator: i.locator, title: "Metadata only", kind: i.kind, publishedAvailability: .available,
            capabilities: i.capabilities, metadata: i.metadata, acquisition: i.acquisition, update: i.update, aliases: [])
        adapter.updateViewport(visible: [], prefetch: [changedImage, o, s])
        checks["duplicate-and-metadata-only-prefetch-retain-one-consumer"] = SILThumbnailProvider.requests.count == duplicateCount && !oldImage.cancelled
        images.wallpapers[0] = .init(id: "1", path: "/image-replaced", title: "same id")
        online.downloadedContent.entries[0] = .init(id: 1, localURL: URL(fileURLWithPath: "/online-replaced"), thumbnailSourceKey: "revision-2")
        steam.previewReloadToken += 1
        adapter.updateViewport(visible: [], prefetch: [i, o, s])
        checks["same-identity-resource-replacement-revokes-old-three-provider-leases"] = oldImage.cancelled && oldOnline.cancelled
            && oldSteam.resets == 1 && SILThumbnailProvider.requests.last?.0 == "/image-replaced"
        let imageBeforeEviction = SILThumbnailProvider.requests.last!.2
        let onlineBeforeEviction = OLDownloadedThumbnailStore.requests.last!.1
        let decoded = NSImage(size: NSSize(width: 10, height: 10))
        SILThumbnailProvider.sharedCache.images["/image-replaced"] = decoded
        OLDownloadedThumbnailStore.sharedCache.images["current-online"] = decoded
        SILThumbnailProvider.completions.last?(.image(decoded))
        OLDownloadedThumbnailStore.completions.last?("current-online", decoded)
        let beforeWarm = (SILThumbnailProvider.requests.count, OLDownloadedThumbnailStore.requests.count)
        adapter.updateViewport(visible: [], prefetch: [i, o, s])
        checks["ready-prefetch-consumers-stay-stable-while-original-caches-own-pixels"] = SILThumbnailProvider.requests.count == beforeWarm.0
            && OLDownloadedThumbnailStore.requests.count == beforeWarm.1
        SILThumbnailProvider.sharedCache.images.removeAll(); OLDownloadedThumbnailStore.sharedCache.images.removeAll()
        adapter.updateViewport(visible: [], prefetch: [i, o, s])
        checks["completed-prefetch-reheats-through-original-cache-after-eviction"] = imageBeforeEviction.cancelled && onlineBeforeEviction.cancelled
            && SILThumbnailProvider.requests.count == beforeWarm.0 + 1 && OLDownloadedThumbnailStore.requests.count == beforeWarm.1 + 1
        let canceledImage = SILThumbnailProvider.requests.last!.2
        let canceledOnline = OLDownloadedThumbnailStore.requests.last!.1
        let beforeCanceled = (SILThumbnailProvider.requests.count, OLDownloadedThumbnailStore.requests.count)
        canceledImage.cancel(); canceledOnline.cancel()
        adapter.updateViewport(visible: [], prefetch: [i, o, s])
        checks["source-invalidated-prefetch-can-retry-without-new-identity-or-viewport"] = SILThumbnailProvider.requests.count == beforeCanceled.0 + 1
            && OLDownloadedThumbnailStore.requests.count == beforeCanceled.1 + 1
            && SILThumbnailProvider.requests.last!.2 !== canceledImage && OLDownloadedThumbnailStore.requests.last!.1 !== canceledOnline
        let resourceImage = SILThumbnailProvider.requests.last!.2
        adapter.updateViewport(visible: [], prefetch: [content(.staticImageLibrary, "1", capabilities: [.inspect])])
        checks["unavailable-content-cannot-acquire-or-retain-prefetch"] = resourceImage.cancelled
        let unicodeCount = AppKitThumbnailProvider.batches.count
        adapter.updateViewport(visible: [], prefetch: [content(.videoLibrary, "é"), content(.videoLibrary, "e\u{301}")])
        let unicodeBatch = AppKitThumbnailProvider.batches.last!.0
        checks["prefetch-preserves-byte-exact-opaque-provider-identities"] = AppKitThumbnailProvider.batches.count == unicodeCount + 1
            && unicodeBatch.count == 2 && unicodeBatch[0].utf8.elementsEqual("é".utf8)
            && unicodeBatch[1].utf8.elementsEqual("e\u{301}".utf8)
        favorites.insert(v.reference)
        let offline = content(.videoLibrary, "1", capabilities: [.inspect])
        adapter.updateCell(video, content: offline, state: state)
        let removal = video.onFavoriteRequested
        let favoriteCount = favorite.count
        removal?("1")
        checks["injected-offline-removal-is-not-blocked-by-organize-capability"] = removal != nil
            && favorite.count == favoriteCount + 1 && favorite.last?.reference == v.reference
        adapter.updateCell(video, content: content(.videoLibrary, "é"), state: state)
        removal?("1")
        checks["held-favorite-action-does-not-retarget-reused-provider-binding"] = favorite.count == favoriteCount + 1
        favorites.remove(v.reference)
        adapter.updateCell(video, content: offline, state: state)
        checks["nil-favorite-factory-result-revokes-card-action"] = video.onFavoriteRequested == nil
        let pickerVideo = pickerAdapter.makeCell(collection: pickerCollection, indexPath: IndexPath(item: 0, section: 0),
            content: v, state: state) as! AppKitWallpaperItem
        checks["picker-video-also-retains-no-favorite-command-without-owner"] = pickerVideo.onFavoriteRequested == nil
        let data = try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
