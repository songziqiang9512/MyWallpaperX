import AppKit

/// One presentation lifetime per grid card/detail. Successful images are held
/// independently of cache eviction; the cache owns shared request cancellation.
@MainActor final class SteamWorkshopPreviewState {
    struct Loaders {
        var image: (URL, Int, SteamWorkshopPreviewLoadCancellation, @escaping (NSImage?) -> Void) -> Void
        var animation: (URL, SteamWorkshopPreviewLoadCancellation, @escaping (NSImage?) -> Void) -> Void
        var video: (URL, @escaping (NSImage?) -> Void) -> Void
        var retryDelay: (URL) -> TimeInterval?
        var invalidate: (URL) -> Void

        static func live(priority: SteamWorkshopPreviewRequestPriority = .visible) -> Loaders { Loaders(
            image: { url, pixels, cancellation, completion in
                steamWorkshopLoadPreviewImage(from: url, maxPixelSize: pixels, priority: priority,
                    cancellation: cancellation, completion: completion)
            },
            animation: { url, cancellation, completion in
                let key = url.isFileURL ? steamWorkshopLocalPreviewCacheKey(for: url) : steamWorkshopPreviewCacheKey(for: url)
                steamWorkshopLoadAnimatedPreview(from: url, cacheKey: key, cancellation: cancellation, completion: completion)
            },
            video: { SteamWorkshopDownloadThumbnailPipeline.shared.generateThumbnail(for: $0, completion: $1) },
            retryDelay: { SteamWorkshopPreviewRequestCoordinator.shared.nextRetryDelay(for: $0, priority: priority) },
            invalidate: { url in
                steamWorkshopInvalidatePreview(url)
                if !url.isFileURL { SteamWorkshopPreviewRequestCoordinator.shared.resetFailureState(for: url) }
            }
        ) }
    }

    private struct Source: Equatable {
        let url: URL
        let key: String
        init(_ url: URL) {
            self.url = url
            key = url.isFileURL ? steamWorkshopLocalPreviewCacheKey(for: url) : steamWorkshopPreviewCacheKey(for: url)
        }
    }
    private enum ResolvedSource: Equatable { case image(Source), video(Source) }
    private struct Request: Equatable {
        let images: [Source]
        let video: Source?
        let maxPixelSize: Int
        let refreshToken: Int
        func contains(_ source: ResolvedSource) -> Bool {
            switch source {
            case let .image(image): return images.contains(image)
            case let .video(video): return self.video == video
            }
        }
    }

    var onChange: (() -> Void)?
    private var staticImage: NSImage?
    private var animatedImage: NSImage?
    private var resolvedSource: ResolvedSource?
    private var request: Request?
    private var generation = 0
    private var animationGeneration = 0
    private var wantsAnimation = false
    private var animationAttempted = false
    private var isLoading = false
    private var isRetrying = false
    private var isImageDemandActive = true
    private var currentImageCandidate = 0
    private var suspendedImageCandidate: Int?
    private var imageCancellation: SteamWorkshopPreviewLoadCancellation?
    private var animationCancellation: SteamWorkshopPreviewLoadCancellation?
    private var retryTask: Task<Void, Never>?
    private var retryDeadline = Date.distantPast
    private let loaders: Loaders

    var image: NSImage? { animatedImage ?? staticImage }
    var requestedPixelSize: Int? { request?.maxPixelSize }
    var isAnimating: Bool { wantsAnimation && animatedImage != nil }
    var placeholder: SteamWorkshopPreviewPlaceholderView.State {
        if image != nil { return .hidden }
        if isRetrying { return .retrying }
        return isLoading ? .loading : .unavailable
    }

    init(loaders: Loaders? = nil) { self.loaders = loaders ?? .live() }
    deinit { retryTask?.cancel(); imageCancellation?.cancel(); animationCancellation?.cancel() }

    func configure(previewURL: URL?, fallbackImageURL: URL? = nil, fallbackVideoURL: URL?, refreshToken: Int = 0, maxPixelSize: Int = 800) {
        var images = previewURL.map { [Source($0)] } ?? []
        if let fallbackImageURL {
            let source = Source(fallbackImageURL)
            if !images.contains(source) { images.append(source) }
        }
        let next = Request(images: images, video: fallbackVideoURL.map(Source.init), maxPixelSize: maxPixelSize, refreshToken: refreshToken)
        guard next != request else { return }
        // Download completion may only add/remove a video fallback. A ready
        // primary image remains authoritative and needs no reload or GIF restart.
        if let previous = request, previous.refreshToken == next.refreshToken, previous.maxPixelSize == next.maxPixelSize,
           previous.images.first == next.images.first, let primary = next.images.first,
           resolvedSource == .image(primary), staticImage != nil {
            request = next
            return
        }
        start(next)
    }

    private func start(_ next: Request) {
        generation += 1
        let expected = generation
        imageCancellation?.cancel()
        imageCancellation = nil
        stopAnimation()
        retryTask?.cancel()
        if let resolvedSource, !next.contains(resolvedSource) {
            staticImage = nil
            self.resolvedSource = nil
        }
        request = next
        isLoading = true
        isRetrying = false
        retryDeadline = Date().addingTimeInterval(35)
        currentImageCandidate = 0
        if isImageDemandActive { loadImage(generation: expected) }
        else { suspendedImageCandidate = 0 }
        // A synchronous memory hit finishes before any loading presentation.
        if isLoading { onChange?() }
    }

    func reload() {
        guard let request else { return }
        for source in request.images { loaders.invalidate(source.url) }
        // Recompute local content versions after explicit refresh, too.
        let next = Request(images: request.images.map { Source($0.url) },
                           video: request.video.map { Source($0.url) }, maxPixelSize: request.maxPixelSize, refreshToken: request.refreshToken)
        start(next)
    }

    func reset() {
        generation += 1
        retryTask?.cancel()
        imageCancellation?.cancel()
        imageCancellation = nil
        request = nil
        resolvedSource = nil
        staticImage = nil
        wantsAnimation = false
        stopAnimation()
        isLoading = false
        isRetrying = false
        suspendedImageCandidate = nil
        onChange?()
    }

    /// Offscreen cards release only their pending consumer. A ready image and
    /// terminal failure remain intact; showing the card resumes unfinished work.
    func setImageDemandActive(_ active: Bool) {
        guard isImageDemandActive != active else { return }
        isImageDemandActive = active
        if !active {
            guard isLoading || isRetrying else { return }
            suspendedImageCandidate = isRetrying && !isLoading ? 0 : currentImageCandidate
            generation += 1
            imageCancellation?.cancel()
            imageCancellation = nil
            retryTask?.cancel()
            retryTask = nil
        } else if let candidate = suspendedImageCandidate, request != nil {
            suspendedImageCandidate = nil
            isLoading = true
            isRetrying = false
            loadImage(generation: generation, candidate: candidate)
            if isLoading { onChange?() }
        }
    }

    func setAnimationActive(_ active: Bool) {
        guard wantsAnimation != active else { return }
        wantsAnimation = active
        if active { loadAnimationIfNeeded() }
        else { stopAnimation(); onChange?() }
    }

    private func stopAnimation() {
        animationGeneration += 1
        animationCancellation?.cancel()
        animationCancellation = nil
        animatedImage = nil
        animationAttempted = false
    }

    private func loadImage(generation expected: Int, candidate: Int = 0) {
        guard generation == expected, isImageDemandActive, let request else { return }
        currentImageCandidate = candidate
        guard candidate < request.images.count else { loadVideoFallback(generation: expected); return }
        let source = request.images[candidate]
        let cancellation = SteamWorkshopPreviewLoadCancellation()
        imageCancellation = cancellation
        loaders.image(source.url, request.maxPixelSize, cancellation) { [weak self] image in
            guard let self, self.generation == expected, !cancellation.cancelled else { return }
            self.imageCancellation = nil
            if let image, steamWorkshopPreviewImageIsUsable(image) {
                self.finish(image, source: .image(source), generation: expected)
            } else {
                self.loadImage(generation: expected, candidate: candidate + 1)
            }
        }
    }

    private func loadVideoFallback(generation expected: Int) {
        guard let source = request?.video else { finish(nil, source: nil, generation: expected); return }
        loaders.video(source.url) { [weak self] image in
            guard let self, self.generation == expected else { return }
            self.finish(image, source: image == nil ? nil : .video(source), generation: expected)
        }
    }

    private func finish(_ image: NSImage?, source: ResolvedSource?, generation expected: Int) {
        guard generation == expected else { return }
        isLoading = false
        isRetrying = false
        if let image {
            staticImage = image
            resolvedSource = source
            onChange?()
            loadAnimationIfNeeded()
            return
        }
        onChange?()
        guard generation == expected,
              let url = request?.images.first(where: { !$0.url.isFileURL })?.url,
              let delay = loaders.retryDelay(url) else { return }
        let wait = max(0.5, delay + 0.25)
        guard Date().addingTimeInterval(wait) < retryDeadline else { return }
        isRetrying = true
        onChange?()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled, let self, self.generation == expected else { return }
            self.loadImage(generation: expected)
        }
    }

    private func loadAnimationIfNeeded() {
        guard wantsAnimation, staticImage != nil, !animationAttempted,
              case let .image(source) = resolvedSource else { return }
        animationAttempted = true
        let expected = generation
        let expectedAnimation = animationGeneration
        let cancellation = SteamWorkshopPreviewLoadCancellation()
        animationCancellation = cancellation
        loaders.animation(source.url, cancellation) { [weak self] image in
            guard let self, self.generation == expected, !cancellation.cancelled,
                  self.animationGeneration == expectedAnimation, self.wantsAnimation else { return }
            self.animationCancellation = nil
            self.animatedImage = image
            self.onChange?()
        }
    }
}
