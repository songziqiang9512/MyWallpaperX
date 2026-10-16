import AppKit
import Combine
import Foundation

// External leaves only. The exercised detail, observation, footer, preview,
// placeholder, scrolling, tag and ordinary property-store code are production.
struct ResolvedWebProjectDescriptor {}
final class SteamWorkshopSceneInspectionController {
    let onStateChange: () -> Void
    init(onStateChange: @escaping () -> Void) { self.onStateChange = onStateChange }
    func reset() {}
}
extension AppKitSteamWorkshopItemDetailView {
    func refreshDiagnosticsPanel() {}
    @objc func openProperties() {}
}
enum WebRuntimeDiagnosticsStore { static let didChangeNotification = Notification.Name("fixture-web-diagnostics") }
extension Notification.Name { static let sceneWallpaperLaunchStateDidChange = Self("fixture-scene-launch") }
final class SceneDaemonClient { static let shared = SceneDaemonClient(); var activeRecordID: String? }
final class WallpaperManager { static let shared = WallpaperManager(); let objectWillChange = ObservableObjectPublisher() }
final class FixtureAuth { let objectWillChange = ObservableObjectPublisher(); var isOnline = false }
final class SteamWorkshopSubscriptionStore {
    enum State: Equatable { case known(Bool), unknown, loading, writing, reconciling, unconfirmed(String) }
    let objectWillChange = ObservableObjectPublisher()
    func synchronizeAccount() {}
    var value = State.known(false)
    var onRead: (() -> Void)?
    var refreshCalls = 0
    func state(for id: String) -> State { onRead?(); return value }
    func refresh(_ id: String) { refreshCalls += 1 }
}
enum SteamWorkshopItemMenu {
    static func subscription(item: SteamWorkshopBrowserItem, service: SteamWorkshopService) -> NSMenuItem { NSMenuItem() }
}
enum PlaybackScope { case scene, web, video }
enum PlaybackCommand {
    case stop
    case setProperty([String: SceneUserPropertyValue], revision: UInt64, recordID: String)
}
final class PlaybackCommandMultiplexer {
    static let shared = PlaybackCommandMultiplexer()
    var propertyDispatches = 0
    func dispatch(_ command: PlaybackCommand, to scope: PlaybackScope) -> Bool {
        if case .setProperty = command { propertyDispatches += 1 }
        return true
    }
}
final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    let objectWillChange = ObservableObjectPublisher()
    let defaults = UserDefaults(suiteName: "com.songziqiang.MyWallpaperX.Debug.DetailInvalidation." + UUID().uuidString)!
    var scenePropertyCommandRevision: UInt64 = 0
    var scenePropertyEditRevisions: [String: UInt64] = [:]
    var selectedDownloadDetailItem: SteamWorkshopBrowserItem?
    var selectedBrowserItem: SteamWorkshopBrowserItem?
    var selectedDownloadInspectorItem: SteamWorkshopBrowserItem?
    var isRefreshingSelectedDownloadDetailItem = false
    var isRefreshingSelectedBrowserItem = false
    var selectedDownloadDetailError: String?
    var selectedBrowserItemError: String?
    let steamAuth = FixtureAuth()
    let steamSubscriptions = SteamWorkshopSubscriptionStore()
    let downloadProgressStore = SteamWorkshopDownloadProgressStore()
    var previewReloadToken = 0
    var record: SteamWorkshopDownloadRecord?
    var downloadingIDs: Set<String> = []
    var queuedIDs: Set<String> = []
    var accessorReads: [String: Int] = [:]
    var downloading = false
    var pendingLaunch = false
    var playing = false
    func playableDownloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { accessorReads["playable", default: 0] += 1; return record?.id == id ? record : nil }
    func latestDownloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { record?.id == id ? record : nil }
    func downloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { accessorReads["ready", default: 0] += 1; return latestDownloadRecord(for: id).flatMap { $0.status == .ready ? $0 : nil } }
    func resolvedWebProjectDescriptor(for record: SteamWorkshopDownloadRecord) -> ResolvedWebProjectDescriptor? { accessorReads["descriptor", default: 0] += 1; return nil }
    func isDownloading(itemID: String) -> Bool { downloading || downloadingIDs.contains(itemID) }
    func isQueuedForDownload(itemID: String) -> Bool { queuedIDs.contains(itemID) }
    func isRecordCurrentlyPlaying(_ record: SteamWorkshopDownloadRecord) -> Bool { accessorReads["playing", default: 0] += 1; return record.contentType == .scene ? SceneDaemonClient.shared.activeRecordID == record.id : playing }
    func isLaunchPending(_ id: String) -> Bool { pendingLaunch }
    func canRequestDownload(id: String) -> Bool { true }
    func scheduleActiveScenePropertyRender(for record: SteamWorkshopDownloadRecord) { preconditionFailure("dispatch must be consumed") }
    nonisolated static func creatorID(from url: URL?) -> String? { nil }
    static func resolvedAuthorWorkshopURL(for item: SteamWorkshopBrowserItem) -> URL? { item.authorWorkshopURL }
    func retryInspectorDetailRefresh(for id: String) {}
    func requestDownloadForBrowserItem(_ item: SteamWorkshopBrowserItem) {}
    func cancelDownload(itemID: String) {}
    func requestMissingDependencyDownload(for record: SteamWorkshopDownloadRecord) {}
    func setAsWallpaper(_ record: SteamWorkshopDownloadRecord) {}
    func openAuthorWorkshopFromLocalDownloadMetadata(for item: SteamWorkshopBrowserItem) {}
    func openAuthorWorksPage(for item: SteamWorkshopBrowserItem) {}
    func openWorkshopDetailPage(for item: SteamWorkshopBrowserItem) {}
    func presentSteamLoginForUserAction(context: String) {}
}
extension SteamWorkshopDownloadRecord { var isDependencyBackedWeb: Bool { false } }
func steamWorkshopLocalPreviewCacheKey(for url: URL) -> String { url.path }
func steamWorkshopPreviewCacheKey(for url: URL) -> String { url.absoluteString }
enum FixturePreview {
    static var localLoads: [URL] = []
    static var animationLoads = 0
    static var animationURLs: [URL] = []
    static var remoteKeys: [String] = []
    static var failLocal = false
    static var failRemote = false
    static var animateRemote = false
    static let image = NSImage(size: NSSize(width: 48, height: 48))
    static let remoteImage = NSImage(size: NSSize(width: 48, height: 48))
    static let remoteAnimation = NSImage(size: NSSize(width: 48, height: 48))
}
func steamWorkshopLoadAnimatedPreview(from url: URL, cacheKey: String, cancellation: SteamWorkshopPreviewLoadCancellation? = nil, completion: @escaping (NSImage?) -> Void) {
    FixturePreview.animationLoads += 1
    FixturePreview.animationURLs.append(url)
    completion(!url.isFileURL && FixturePreview.animateRemote ? FixturePreview.remoteAnimation : nil)
}
func steamWorkshopLoadLocalPreviewImage(from url: URL, cancellation: SteamWorkshopPreviewLoadCancellation? = nil, completion: @escaping (NSImage?) -> Void) {
    FixturePreview.localLoads.append(url)
    completion(FixturePreview.failLocal ? nil : FixturePreview.image)
}
func steamWorkshopPreviewImageLooksSuspicious(_ image: NSImage) -> Bool { false }
func steamWorkshopPreviewImageIsUsable(_ image: NSImage) -> Bool { true }
func steamWorkshopPreviewImage(from data: Data) -> NSImage? { nil }
final class SteamWorkshopDownloadThumbnailPipeline {
    static let shared = SteamWorkshopDownloadThumbnailPipeline()
    func generateThumbnail(for url: URL, completion: @escaping (NSImage?) -> Void) { preconditionFailure("nil preview required") }
}
final class SteamWorkshopPreviewImageCache {
    static let shared = SteamWorkshopPreviewImageCache()
    func cachedImage(forKey key: String) -> NSImage? { nil }
    func remove(forKey key: String) {}
    func loadImageDataAsync(forKey key: String, loader: @escaping () async -> Data?, decoder: @escaping (Data) -> NSImage?, cancellation: SteamWorkshopPreviewLoadCancellation? = nil, completion: @escaping (NSImage?) -> Void) {
        FixturePreview.remoteKeys.append(key)
        completion(FixturePreview.failRemote ? nil : FixturePreview.remoteImage)
    }
}
enum SteamWorkshopPreviewRequestPriority { case userInitiated, visible }
final class SteamWorkshopPreviewRequestCoordinator {
    typealias Priority = SteamWorkshopPreviewRequestPriority
    static let shared = SteamWorkshopPreviewRequestCoordinator()
    func loadData(from url: URL, priority: Priority) async -> Data? { nil }
    func markCachedImageSuspicious(forKey key: String) {}
    func resetFailureState(for url: URL) {}
    func nextRetryDelay(for url: URL, priority: Priority) -> TimeInterval? { nil }
}

nonisolated final class SteamWorkshopPreviewLoadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}
