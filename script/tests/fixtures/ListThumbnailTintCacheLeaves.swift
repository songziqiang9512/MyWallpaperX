import AppKit

// Recording cache/transport boundaries; product selection and publication stay real.
enum TintThumbnailPriority { case visible, prefetch }
final class ThumbnailCacheRequestCancellation {
    private(set) var isCancelled = false
    func cancel() { isCancelled = true }
}
@MainActor final class TintRecordingThumbnailCache {
    var image: NSImage?
    var keys: [String] = []
    var priorities: [TintThumbnailPriority] = []
    func load(forKey key: String, priority: TintThumbnailPriority,
              cancellation: ThumbnailCacheRequestCancellation, loader: @escaping () -> NSImage?,
              completion: @escaping (NSImage?) -> Void) {
        keys.append(key); priorities.append(priority); completion(image)
    }
}
nonisolated func silGridThumbnailImage(atPath path: String) -> NSImage? { nil }
@MainActor final class OnlineImageThumbnailCache {
    static let shared = OnlineImageThumbnailCache()
    var result: NSImage?
    var urls: [URL] = []
    var priorities: [TintThumbnailPriority] = []
    func image(for url: URL, maxPixelSize: Int, priority: TintThumbnailPriority) async -> NSImage? {
        urls.append(url); priorities.append(priority); return result
    }
}
