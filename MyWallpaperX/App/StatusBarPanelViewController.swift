import AppKit

final class StatusBarPanelViewController: NSViewController {
    enum Action {
        case settings, previous, next, playback, mute, properties, openMain, mode, quit
        case volume(Double)
    }

    let panel = StatusBarPanelView(frame: NSRect(x: 0, y: 0, width: 344, height: 536))
    var onAction: ((Action) -> Void)?
    var onDismiss: (() -> Void)?
    private let workshopPreview = SteamWorkshopPreviewState()
    private lazy var videoPreview = AppKitThumbnailProvider(wallpaperManager: .shared)
    private let previewQueue = DispatchQueue(label: "com.songziqiang.MyWallpaperX.status-panel.preview", qos: .utility)
    private var videoCancellation: ThumbnailCacheRequestCancellation?
    private var localImageCancellation: SteamWorkshopPreviewLoadCancellation?
    private var displayedCoverSource: CoverSource?
    private var refreshToken: Int?
    private var imageGeneration: UInt64 = 0

    private enum CoverSource: Equatable {
        case video(VideoWallpaper)
        case images([URL], revision: String?)

        init(_ content: StatusBarPanelPresentation.Content) {
            var urls: [URL]
            var revision: String? = nil
            switch content {
            case .none, .remembered(_, nil):
                urls = []
            case let .video(item):
                self = .video(item)
                return
            case let .remembered(_, item?):
                let thumbnail = item.metadata.thumbnailPath.map { URL(fileURLWithPath: $0) }
                let imageFile = item.kind == .image ? item.locator.path.map { URL(fileURLWithPath: $0) } : nil
                urls = [thumbnail, item.metadata.previewURL, imageFile].compactMap { $0 }
                revision = item.metadata.resourceRevision
            case let .workshop(item):
                urls = item.previewURL.map { [$0] } ?? []
                if let fallback = item.browserItem?.previewImageURL, !urls.contains(fallback) { urls.append(fallback) }
                // Ready timestamps identify the installed publication; transfer
                // progress timestamps do not describe an image replacement.
                if item.status == .ready { revision = String(item.updatedAt.timeIntervalSince1970) }
            case let .still(url):
                urls = [url]
            }
            self = .images(urls.filter(\.isFileURL) + urls.filter { !$0.isFileURL }, revision: revision)
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.video(lhs), .video(rhs)):
                return lhs.path == rhs.path && lhs.thumbnailPath == rhs.thumbnailPath
            case let (.images(lhs, lhsRevision), .images(rhs, rhsRevision)):
                return lhs == rhs && lhsRevision == rhsRevision
            default:
                return false
            }
        }
    }

    override func loadView() {
        view = panel
        for (button, action) in [
            (panel.settings, #selector(settings)), (panel.previous, #selector(previous)),
            (panel.playback, #selector(playback)), (panel.next, #selector(next)),
            (panel.mute, #selector(mute)), (panel.cover.properties, #selector(properties)),
            (panel.openMain, #selector(openMain)), (panel.quit, #selector(quit)),
            (panel.mode, #selector(mode)), (panel.compactProperties, #selector(properties))
        ] { button.target = self; button.action = action }
        panel.volume.target = self
        panel.volume.action = #selector(volume)
        workshopPreview.onChange = { [weak self] in
            guard let self else { return }
            self.panel.cover.setImage(self.workshopPreview.image)
        }
    }

    func apply(_ presentation: StatusBarPanelPresentation, refreshToken: Int) {
        loadViewIfNeeded()
        panel.apply(presentation)
        let source = CoverSource(presentation.content)
        let needsPreview = displayedCoverSource != source || self.refreshToken != refreshToken
        // Retain the latest video snapshot for thumbnail-ready demand, while
        // title/favorite/usage changes keep the current image and request.
        displayedCoverSource = source
        guard needsPreview else { return }
        videoCancellation?.cancel()
        localImageCancellation?.cancel()
        workshopPreview.reset()
        imageGeneration &+= 1
        let expected = imageGeneration
        self.refreshToken = refreshToken
        panel.cover.setImage(nil)
        switch source {
        case let .video(item):
            loadVideoCover(item, generation: expected)
        case let .images(urls, _):
            loadImageCover(urls, generation: expected)
        }
    }

    func releasePreview() {
        imageGeneration &+= 1
        videoCancellation?.cancel()
        videoCancellation = nil
        localImageCancellation?.cancel()
        localImageCancellation = nil
        workshopPreview.reset()
        displayedCoverSource = nil
        refreshToken = nil
        panel.cover.setImage(nil)
    }

    func thumbnailBecameReady(at normalizedPath: String) {
        guard case let .video(item) = displayedCoverSource,
              WallpaperManager.shared.normalizedPath(item.path) == normalizedPath else { return }
        // Only the derived asset changed; the wallpaper model may be identical.
        // Invalidate this consumer, not the shared cache or another card.
        videoCancellation?.cancel()
        imageGeneration &+= 1
        let expected = imageGeneration
        loadVideoCover(item, generation: expected)
    }

    private func loadVideoCover(_ item: VideoWallpaper, generation: UInt64, mayGenerate: Bool = true) {
        // The existing cache may create/migrate its directory on first access.
        // Warm that owner off-main before constructing the lightweight provider.
        let preparation = ThumbnailCacheRequestCancellation()
        videoCancellation = preparation
        previewQueue.async { [weak self] in
            guard !preparation.cancelled else { return }
            _ = VideoLibraryThumbnailStore.sharedCache
            DispatchQueue.main.async {
                guard let self, self.imageGeneration == generation, !preparation.cancelled else { return }
                self.loadPreparedVideoCover(item, generation: generation, mayGenerate: mayGenerate)
            }
        }
    }

    private func loadPreparedVideoCover(_ item: VideoWallpaper, generation: UInt64, mayGenerate: Bool) {
        videoCancellation = videoPreview.loadThumbnail(for: item) { [weak self] image in
            guard let self, self.imageGeneration == generation else { return }
            if let image { self.panel.cover.setImage(image) }
            guard image == nil, mayGenerate else { return }
            let manager = WallpaperManager.shared
            let path = manager.normalizedPath(item.path)
            guard manager.shouldRetryThumbnailGeneration(for: path) || manager.isThumbnailGenerationInFlight(for: path) else { return }
            // Cached reads do not create a missing derived image. A status-only
            // replay needs the same bounded single-flight generator as a card.
            manager.generateThumbnail(for: URL(fileURLWithPath: item.path)) { [weak self] output in
                guard let self, self.imageGeneration == generation, output != nil else { return }
                self.loadVideoCover(item, generation: generation, mayGenerate: false)
            }
        }
    }

    private func loadImageCover(_ urls: [URL], generation: UInt64) {
        guard let url = urls.first else { return }
        let cancellation = SteamWorkshopPreviewLoadCancellation()
        localImageCancellation = cancellation
        previewQueue.async { [weak self] in
            guard !cancellation.cancelled else { return }
            _ = SteamWorkshopPreviewImageCache.shared
            guard url.isFileURL else {
                DispatchQueue.main.async {
                    guard let self, self.imageGeneration == generation, !cancellation.cancelled else { return }
                    self.localImageCancellation = nil
                    // Keep the existing remote request/backoff consumer, after
                    // initializing its shared cache outside the opening path.
                    self.workshopPreview.configure(previewURL: url, fallbackImageURL: urls.dropFirst().first,
                        fallbackVideoURL: nil, refreshToken: self.refreshToken ?? 0, maxPixelSize: 800)
                }
                return
            }
            guard !cancellation.cancelled else { return }
            steamWorkshopLoadPreviewImage(from: url, maxPixelSize: 800, cancellation: cancellation) { image in
                DispatchQueue.main.async {
                    guard let self, self.imageGeneration == generation, !cancellation.cancelled else { return }
                    self.localImageCancellation = nil
                    if let image, steamWorkshopPreviewImageIsUsable(image) { self.panel.cover.setImage(image) }
                    else { self.loadImageCover(Array(urls.dropFirst()), generation: generation) }
                }
            }
        }
    }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }
    @objc private func settings() { onAction?(.settings) }
    @objc private func previous() { onAction?(.previous) }
    @objc private func playback() { onAction?(.playback) }
    @objc private func next() { onAction?(.next) }
    @objc private func mute() { onAction?(.mute) }
    @objc private func properties() { onAction?(.properties) }
    @objc private func openMain() { onAction?(.openMain) }
    @objc private func mode() { onAction?(.mode) }
    @objc private func quit() { onAction?(.quit) }
    @objc private func volume() { onAction?(.volume(panel.volume.doubleValue.rounded())) }
}
