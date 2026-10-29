import AppKit

/// Demand-lifetime artwork composition. The source pipelines retain ownership
/// of decoded pixels, file identity, scheduling and in-flight request sharing.
@MainActor final class WallpaperLibraryArtworkProvider {
    typealias Cancellation = () -> Void
    typealias Loader = (WallpaperContentItem, @escaping (NSImage?) -> Void) -> Cancellation
    struct Identity: Equatable {
        let reference: WallpaperReference
        let assets: [Data]
        init(_ content: WallpaperContentItem) {
            reference = content.providerReference
            assets = [content.locator.path ?? "", content.metadata.thumbnailPath ?? "",
                content.metadata.previewURL?.absoluteString ?? "", content.metadata.previewVideoURL?.absoluteString ?? "",
                content.metadata.resourceRevision ?? "", content.publishedAvailability.rawValue,
                String(describing: content.metadata.fileSizeBytes), String(describing: content.metadata.modifiedAt)]
                .map { Data($0.utf8) }
        }
        var tintAssets: [String] { assets.map { $0.base64EncodedString() } }
    }
    private final class Cover {
        let identity: Identity?
        let customAssetID: UUID?
        var sourceImage: NSImage?
        var cancellation: Cancellation?
        init(_ identity: Identity?, customAssetID: UUID?) { self.identity = identity; self.customAssetID = customAssetID }
        func cancel() { let pending = cancellation; cancellation = nil; pending?() }
    }
    private enum TintTarget { case none, content(Identity), directory(UUID) }
    private let loader: Loader
    private var entries: [UUID: WallpaperPlaylistDirectoryEntry] = [:]
    private var resolve: ([WallpaperReference]) -> [WallpaperContentItem] = { _ in [] }
    private var demands: [UUID: Set<UUID>] = [:]
    private var covers: [UUID: Cover] = [:]
    private var rendered: [UUID: WallpaperPlaylistArtwork] = [:]
    private var customCovers: [UUID: UUID] = [:]
    private var resetEpoch: UUID?
    var loadCustomCover: ((UUID, @escaping (NSImage?) -> Void) -> Cancellation)?
    private var reconciliation = UUID()
    private var tintTarget = TintTarget.none
    private var lastDirectoryTintImage: NSImage?
    let currentListTintSource = ListThumbnailTintSource()
    var onCoversChanged: (([UUID: WallpaperPlaylistArtwork]) -> Void)?

    init(loader: @escaping Loader) { self.loader = loader }
    isolated deinit { for cover in covers.values { cover.cancel() } }

    convenience init(manager: WallpaperManager, images: SILService, steam: SteamWorkshopService, pixabay: PixabayService) {
        self.init(loader: Self.liveLoader(manager: manager, images: images, steam: steam, pixabay: pixabay))
    }

    static func liveLoader(manager: WallpaperManager, images: SILService, steam: SteamWorkshopService, pixabay: PixabayService) -> Loader {
        let videos = AppKitThumbnailProvider(wallpaperManager: manager)
        let stills = SILThumbnailProvider()
        return { content, completion in
            let reference = content.providerReference
            func matches(_ id: String) -> Bool { id.utf8.elementsEqual(reference.sourceID.utf8) }
            guard content.publishedAvailability == .available else { completion(nil); return {} }
            switch reference.provider {
            case .videoLibrary:
                guard let row = manager.wallpapers.first(where: { matches($0.id) }) else { completion(nil); return {} }
                let cancellation = videos.loadThumbnail(for: row, priority: .prefetch, completion: completion)
                return { cancellation.cancel() }
            case .staticImageLibrary:
                guard let row = images.wallpapers.first(where: { matches($0.id) }) else { completion(nil); return {} }
                let cancellation = ThumbnailCacheRequestCancellation()
                stills.load(path: row.path, priority: .prefetch, cancellation: cancellation) { result in
                    if case .image(let image) = result { completion(image) } else { completion(nil) }
                }
                return { cancellation.cancel() }
            case .steamWorkshop:
                guard let row = steam.downloads.first(where: { matches($0.id) }) else { completion(nil); return {} }
                let item = row.displayItem ?? SteamWorkshopDownloadGridSupport.fallbackDisplayItem(for: row)
                let urls = steamWorkshopPreviewSources(item: item, record: row)
                let state = SteamWorkshopPreviewState(loaders: .live(priority: .prefetch))
                state.onChange = { [weak state] in
                    if let image = state?.image { completion(image) }
                }
                state.configure(previewURL: urls.primary, fallbackImageURL: urls.fallback,
                                fallbackVideoURL: row.videoURL, maxPixelSize: 256)
                return { state.onChange = nil; state.reset() }
            case .pixabay:
                guard let id = Int(reference.sourceID), String(id).utf8.elementsEqual(reference.sourceID.utf8),
                      let row = pixabay.downloadedContent.entries.first(where: { $0.id == id }) else { completion(nil); return {} }
                let cancellation = ThumbnailCacheRequestCancellation()
                PixabayDownloadedThumbnailStore.loadThumbnail(row, priority: .prefetch, cancellation: cancellation) { _, image in completion(image) }
                return { cancellation.cancel() }
            case .wallhaven, .pixiv:
                let library = OnlineImageLibrary.shared
                guard let record = library.record(for: reference), record.revision.uuidString == content.metadata.resourceRevision,
                      let url = library.localURL(for: record) else { completion(nil); return {} }
                let cancellation = ThumbnailCacheRequestCancellation()
                stills.load(path: url.path, priority: .prefetch, cancellation: cancellation) { result in
                    if case .image(let image) = result { completion(image) } else { completion(nil) }
                }
                return { cancellation.cancel() }
            }
        }
    }

    /// The resolver returns one value per input reference, in that order, using
    /// one current catalog/relationship projection for the entire visible batch.
    func update(entries: [WallpaperPlaylistDirectoryEntry], resetEpoch: UUID? = nil,
                customCovers: [UUID: UUID] = [:], resolve: @escaping ([WallpaperReference]) -> [WallpaperContentItem]) {
        let expected = UUID()
        reconciliation = expected
        self.entries = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.resolve = resolve
        self.customCovers = customCovers
        if self.resetEpoch != resetEpoch {
            self.resetEpoch = resetEpoch
            let retired = Array(covers.values)
            covers.removeAll(); rendered.removeAll()
            lastDirectoryTintImage = nil
            retired.forEach { $0.cancel() }
            guard reconciliation == expected else { return }
            currentListTintSource.invalidate()
            guard reconciliation == expected else { return }
            onCoversChanged?(rendered)
            guard reconciliation == expected else { return }
        }
        reconcile()
    }

    func setDemand(sourceToken: UUID, playlistIDs: Set<UUID>) {
        guard (demands[sourceToken] ?? []) != playlistIDs else { return }
        if playlistIDs.isEmpty { demands.removeValue(forKey: sourceToken) }
        else { demands[sourceToken] = playlistIDs }
        reconcile()
    }

    /// A direct consumer receives an independent lease in the original cache.
    func load(content: WallpaperContentItem, completion: @escaping (NSImage?) -> Void) -> Cancellation {
        loader(content, completion)
    }

    func updateCurrentList(first: WallpaperContentItem?) {
        let identity = first.map(Identity.init)
        let unchanged: Bool
        if case .content(let previous) = tintTarget { unchanged = previous == identity }
        else { unchanged = identity == nil && isNoTint }
        guard !unchanged else { return }
        tintTarget = identity.map(TintTarget.content) ?? .none
        lastDirectoryTintImage = nil
        reconcile()
        currentListTintSource.update(id: identity?.reference.storageKey, assets: identity?.tintAssets ?? []) { [weak self] completion in
            guard let self, let first else { completion(nil); return {} }
            return self.load(content: first, completion: completion)
        }
    }

    func updateCurrentDirectory(firstPlaylistID: UUID?) {
        if case .directory(let previous) = tintTarget, previous == firstPlaylistID { return }
        if firstPlaylistID == nil && isNoTint { return }
        tintTarget = firstPlaylistID.map(TintTarget.directory) ?? .none
        lastDirectoryTintImage = firstPlaylistID.flatMap { rendered[$0]?.image }
        currentListTintSource.update(id: firstPlaylistID.map { "playlist-cover:" + $0.uuidString }) { [weak self] completion in
            guard let self, let firstPlaylistID else { completion(nil); return {} }
            completion(self.rendered[firstPlaylistID]?.image)
            return {}
        }
        reconcile()
    }

    private var isNoTint: Bool { if case .none = tintTarget { return true }; return false }

    private func reconcile() {
        let expected = UUID()
        reconciliation = expected
        var desired = demands.values.reduce(into: Set<UUID>()) { $0.formUnion($1) }
        if case .directory(let id) = tintTarget { desired.insert(id) }
        desired.formIntersection(entries.keys)
        var seen = Set<WallpaperReference>()
        let references = desired.sorted(by: { $0.uuidString < $1.uuidString }).filter { customCovers[$0] == nil }.compactMap { entries[$0]?.coverReference }
            .filter { seen.insert($0).inserted }
        let resolved = references.isEmpty ? [] : resolve(references)
        // A failed batch has no optional visual result. Never pair a partial
        // result with another source's input reference.
        let contents = resolved.count == references.count ? Dictionary(uniqueKeysWithValues: zip(references, resolved)) : [:]
        var changed = false
        for id in Array(covers.keys) where !desired.contains(id) {
            guard reconciliation == expected else { return }
            let previous = covers.removeValue(forKey: id)
            changed = rendered.removeValue(forKey: id) != nil || changed
            previous?.cancel()
        }
        for id in desired {
            guard reconciliation == expected else { return }
            let assetID = customCovers[id]
            let content = assetID == nil ? entries[id]?.coverReference.flatMap { contents[$0] } : nil
            let identity = content.map(Identity.init)
            if let old = covers[id], old.identity == identity, old.customAssetID == assetID { continue }
            let previous = covers.removeValue(forKey: id)
            changed = rendered.removeValue(forKey: id) != nil || changed
            previous?.cancel()
            guard reconciliation == expected else { return }
            let cover = Cover(identity, customAssetID: assetID)
            covers[id] = cover
            rendered[id] = WallpaperPlaylistArtwork(image: nil, isCustom: assetID != nil)
            changed = true
            let complete: (NSImage?) -> Void = { [weak self, weak cover] image in
                guard let self, let cover, self.covers[id] === cover, cover.sourceImage !== image else { return }
                cover.sourceImage = image
                self.rendered[id] = WallpaperPlaylistArtwork(image: image.flatMap(Self.square), isCustom: assetID != nil)
                self.publish()
            }
            let cancel: Cancellation
            if let assetID { cancel = loadCustomCover?(assetID, complete) ?? {} }
            else if let content, content.publishedAvailability == .available { cancel = loader(content, complete) }
            else { continue }
            if covers[id] === cover { cover.cancellation = cancel } else { cancel() }

        }
        if reconciliation == expected, changed { publish() }
    }

    private func publish() {
        if case .directory(let id) = tintTarget {
            let next = rendered[id]?.image
            if next !== lastDirectoryTintImage {
                lastDirectoryTintImage = next
                currentListTintSource.invalidate()
            }
        }
        onCoversChanged?(rendered)
    }

    /// Normalize the one selected image without baking in an appearance color.
    private static func square(_ image: NSImage) -> NSImage? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let size = NSSize(width: 256, height: 256)
        let result = NSImage(size: size)
        result.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill(using: .copy)
        let scale = max(size.width / image.size.width, size.height / image.size.height)
        let crop = NSSize(width: size.width / scale, height: size.height / scale)
        let source = NSRect(x: (image.size.width - crop.width) / 2, y: (image.size.height - crop.height) / 2,
                            width: crop.width, height: crop.height)
        image.draw(in: NSRect(origin: .zero, size: size), from: source, operation: .sourceOver,
                   fraction: 1, respectFlipped: true, hints: nil)
        result.unlockFocus()
        return result
    }
}
