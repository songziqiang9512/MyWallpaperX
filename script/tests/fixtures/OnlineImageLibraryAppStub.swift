import Combine
import Foundation

/// Request facts only; the controlled cache leaf never performs network I/O.
nonisolated struct OnlineImageFixtureThumbnailRequest: Sendable {
    let url: URL
    let source: OnlineImageSource
    let scopeID: String
}

/// Controlled acquisition leaf for real App routing fixtures. It never opens
/// a session, reads user files or applies a desktop image.
@MainActor final class OnlineImageLibrary: ObservableObject {
    static let shared = OnlineImageLibrary()
    @Published var snapshot = OnlineImageLocalSnapshot()
    @Published var progress: [OnlineImageAssetID: Double] = [:]
    var root = URL(fileURLWithPath: "/fixture-owned-online-images", isDirectory: true)
    var downloadRoots: [URL] { [root] }
    var requestLibraryPlayback: ((WallpaperReference) -> Void)?
    var captureApplyIntent: (() -> (() -> Bool))?
    var isFileInUse: ((String) -> Bool)?
    var refreshes = 0
    var retries: [WallpaperReference] = []
    var deletions: [WallpaperReference] = []
    var cancellations: [OnlineImageAssetID] = []
    var deletion: ((WallpaperReference) async throws -> Void)?
    var scopes: [OnlineImageSource: String] = [.wallhaven: "fixture-wallhaven", .pixiv: "fixture-pixiv"]
    var thumbnailRequests: [OnlineImageFixtureThumbnailRequest] = []
    var downloads: [OnlineImageAssetID] = []
    var downloadApplyFlags: [Bool] = []
    var detailRequests: [OnlineImageArtwork] = []
    var assetRequests: [OnlineImageArtwork] = []
    var detailResolver: ((OnlineImageArtwork) async throws -> OnlineImageArtwork)?
    var assetResolver: ((OnlineImageArtwork) async throws -> [OnlineImageAsset])?
    var originalFetcher: ((OnlineImageAsset, URL) async throws -> Void)?
    var refresh: (() async -> Void)?
    var previewPreparation: (() async -> Void)?

    func detail(_ artwork: OnlineImageArtwork) async throws -> OnlineImageArtwork {
        detailRequests.append(artwork)
        return try await detailResolver?(artwork) ?? artwork
    }
    func assets(for artwork: OnlineImageArtwork) async throws -> [OnlineImageAsset] {
        assetRequests.append(artwork)
        return try await assetResolver?(artwork) ?? []
    }
    func preparePixiv() async { await previewPreparation?() }
    func prepareWallhaven() async {}
    func cachedOriginalPreviewURL(for id: OnlineImageAssetID) async -> URL? { nil }
    func originalPreviewURL(_ asset: OnlineImageAsset) async throws -> URL {
        let ext = asset.originalURL.pathExtension
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-original-\(UUID().uuidString)")
            .appendingPathExtension(ext.isEmpty ? "img" : ext)
        guard let originalFetcher else { throw OnlineImageError.unsupported }
        do { try await originalFetcher(asset, url); try Task.checkCancellation(); return url }
        catch { try? FileManager.default.removeItem(at: url); throw error }
    }

    func requestScope(_ source: OnlineImageSource) -> String { scopes[source] ?? source.rawValue }
    func thumbnailRequest(url: URL, source: OnlineImageSource) -> OnlineImageFixtureThumbnailRequest {
        let request = OnlineImageFixtureThumbnailRequest(url: url, source: source, scopeID: requestScope(source))
        thumbnailRequests.append(request)
        return request
    }
    func downloadArtwork(_ artwork: OnlineImageArtwork, pageIndex: Int = 0, apply: Bool = false) {
        downloads.append(.init(source: artwork.source, artworkID: artwork.artworkID, pageIndex: pageIndex))
        downloadApplyFlags.append(apply)
    }
    func download(_ asset: OnlineImageAsset, apply: Bool = false) { downloads.append(asset.id); downloadApplyFlags.append(apply) }
    @discardableResult func refreshLocal() -> Task<Void, Never> {
        refreshes += 1
        let refresh = refresh
        return Task { await refresh?() }
    }
    func record(for reference: WallpaperReference) -> OnlineImageLocalRecord? {
        snapshot.records.first { $0.assetID.reference == reference }
    }
    func localURL(for record: OnlineImageLocalRecord) -> URL? { root.appendingPathComponent(record.relativePath) }
    func content(for reference: WallpaperReference) -> WallpaperContentItem? {
        guard let record = record(for: reference), let url = localURL(for: record) else { return nil }
        return OnlineImageContentProjection.local(record, url: url, available: !snapshot.unavailable.contains(record.id))
    }
    func retry(_ reference: WallpaperReference) { retries.append(reference) }
    func cancel(_ id: OnlineImageAssetID) { cancellations.append(id) }
    func delete(_ reference: WallpaperReference, expectedRevision: UUID? = nil,
                permitsDeletion: @escaping () -> Bool = { true }) async throws {
        guard permitsDeletion(), expectedRevision == nil || expectedRevision == record(for: reference)?.revision else {
            throw OnlineImageError.message("下载记录已变化")
        }
        deletions.append(reference)
        try await deletion?(reference)
    }
}
