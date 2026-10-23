import AppKit

// Recording transport leaves only. The preview state and tint adapter are production.
nonisolated enum SteamWorkshopPreviewRequestPriority: Sendable { case visible, prefetch }
nonisolated final class SteamWorkshopPreviewLoadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return isCancelled }
    func cancel() { lock.lock(); isCancelled = true; lock.unlock() }
}
enum SteamWorkshopPreviewPlaceholderView {
    enum State { case hidden, loading, retrying, unavailable }
}
@MainActor enum TintSteamTransport {
    static var image: NSImage?
    static var images: [String: NSImage] = [:]
    static var loads: [URL] = []
    static var priorities: [SteamWorkshopPreviewRequestPriority] = []
    static var animationLoads = 0
    static var videoLoads = 0
}
func steamWorkshopLocalPreviewCacheKey(for url: URL) -> String { url.absoluteString }
func steamWorkshopPreviewCacheKey(for url: URL) -> String { url.absoluteString }
@MainActor func steamWorkshopLoadPreviewImage(from url: URL, maxPixelSize: Int,
    priority: SteamWorkshopPreviewRequestPriority, cancellation: SteamWorkshopPreviewLoadCancellation,
    completion: @escaping (NSImage?) -> Void) {
    TintSteamTransport.loads.append(url)
    TintSteamTransport.priorities.append(priority)
    completion(TintSteamTransport.images[url.absoluteString] ?? TintSteamTransport.image)
}
@MainActor func steamWorkshopLoadAnimatedPreview(from url: URL, cacheKey: String,
    cancellation: SteamWorkshopPreviewLoadCancellation, completion: @escaping (NSImage?) -> Void) {
    TintSteamTransport.animationLoads += 1
    completion(nil)
}
@MainActor func steamWorkshopInvalidatePreview(_ url: URL) {}
@MainActor final class SteamWorkshopPreviewRequestCoordinator {
    static let shared = SteamWorkshopPreviewRequestCoordinator()
    func nextRetryDelay(for url: URL, priority: SteamWorkshopPreviewRequestPriority) -> TimeInterval? { nil }
    func resetFailureState(for url: URL) {}
}
@MainActor final class SteamWorkshopDownloadThumbnailPipeline {
    static let shared = SteamWorkshopDownloadThumbnailPipeline()
    func generateThumbnail(for url: URL, completion: @escaping (NSImage?) -> Void) {
        TintSteamTransport.videoLoads += 1
        completion(nil)
    }
}
