import Foundation
import ImageIO
import Metal

final class SceneMediaThumbnailTextureStore: @unchecked Sendable {
    private final class DecodeRequest: @unchecked Sendable {
        let input: SceneMediaThumbnailInbox.Snapshot

        private let lock = NSLock()
        private var cancelled = false

        init(input: SceneMediaThumbnailInbox.Snapshot) {
            self.input = input
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    struct Snapshot {
        let generation: UInt64
        let current: SceneTextureProviderPublication?
        let systemTextures: [String: MTLTexture]
        let publications: [String: SceneTextureProviderPublication]

        static let empty = Snapshot(
            generation: 0,
            current: nil,
            systemTextures: [:],
            publications: [:]
        )
    }

    private let device: MTLDevice
    private let queue: DispatchQueue
    private let imageDecoder: (Data) -> CGImage?
    private let lock = NSLock()
    private var requestedGeneration: UInt64 = 0
    private var readyGeneration: UInt64 = 0
    private var currentTexture: MTLTexture?
    private var reportedPendingGeneration: UInt64?
    private var pendingRequest: DecodeRequest?

    init(
        device: MTLDevice,
        decodingQueue: DispatchQueue? = nil,
        imageDecoder: @escaping (Data) -> CGImage? =
            SceneMediaThumbnailTextureStore.decodeImage
    ) {
        self.device = device
        self.imageDecoder = imageDecoder
        self.queue = decodingQueue ?? DispatchQueue(
            label: "com.mywallpaperx.scene.media-thumbnail",
            qos: .userInitiated
        )
    }

    func update(from input: SceneMediaThumbnailInbox.Snapshot) {
        lock.lock()
        guard input.generation != requestedGeneration else {
            lock.unlock()
            return
        }
        requestedGeneration = input.generation
        pendingRequest?.cancel()
        let request = DecodeRequest(input: input)
        pendingRequest = request
        lock.unlock()

        queue.async { [weak self] in
            self?.decode(request)
        }
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
#if DEBUG
        if readyGeneration != requestedGeneration,
           readyGeneration > 0,
           reportedPendingGeneration != requestedGeneration {
            reportedPendingGeneration = requestedGeneration
            print(
                "MWX media thumbnail store: phase=pending-last-ready"
                    + " requestedGeneration=\(requestedGeneration)"
                    + " readyGeneration=\(readyGeneration)"
                    + " hasCurrent=\(currentTexture != nil)"
            )
        }
#endif
        var textures: [String: MTLTexture] = [:]
        var publications: [String: SceneTextureProviderPublication] = [:]
        let current = currentTexture.map {
            let size = CGSize(width: $0.width, height: $0.height)
            return SceneTextureProviderPublication(
                requestIdentity: .system(
                    SceneMediaThumbnailBindingProgram.currentIdentity
                ),
                candidate: SceneTextureCandidate(
                    texture: $0,
                    identity: .provider(.mediaThumbnailCurrent),
                    generation: .provider(contentGeneration: readyGeneration),
                    purpose: .premultipliedColor,
                    content: .color(.resolved(.premultipliedAlpha)),
                    physicalSize: size,
                    mappedSize: size,
                    uvTransform: .identity,
                    sampling: .linearClamp
                ),
                contentGeneration: readyGeneration
            )
        }
        if let current {
            textures[SceneMediaThumbnailBindingProgram.currentIdentity] = current.texture
            publications[SceneMediaThumbnailBindingProgram.currentIdentity] = current
        }
        return Snapshot(
            generation: readyGeneration,
            current: current,
            systemTextures: textures,
            publications: publications
        )
    }

    private func decode(_ request: DecodeRequest) {
        guard shouldContinue(request) else { return }
        let input = request.input
        let currentImage = input.current.flatMap(imageDecoder)
        guard shouldContinue(request) else { return }
        let current = currentImage.flatMap(makeTexture)
        guard !request.isCancelled else { return }
        lock.lock()
        defer { lock.unlock() }
        guard pendingRequest === request,
              requestedGeneration == input.generation else { return }
        currentTexture = current
        readyGeneration = input.generation
        reportedPendingGeneration = nil
        pendingRequest = nil
#if DEBUG
        print(
            "MWX media thumbnail store: phase=ready"
                + " generation=\(input.generation)"
                + " hasCurrent=\(current != nil)"
        )
#endif
    }

    private func shouldContinue(_ request: DecodeRequest) -> Bool {
        guard !request.isCancelled else { return false }
        lock.lock()
        defer { lock.unlock() }
        return pendingRequest === request
            && requestedGeneration == request.input.generation
    }

    private func makeTexture(_ image: CGImage) -> MTLTexture? {
        guard case let .loaded(texture) = SceneImageTextureUploader.upload(
            image: image,
            purpose: .premultipliedColor,
            maxDimension: 256,
            device: device
        ) else { return nil }
        return texture
    }

    nonisolated private static func decodeImage(_ data: Data) -> CGImage? {
        guard data.count <= SceneMediaThumbnailInbox.maximumEncodedByteCount,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
