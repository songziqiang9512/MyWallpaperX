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
        let pendingGeneration: UInt64?
        let pendingIdentities: Set<SceneSystemProviderTextureIdentity>
        let current: SceneTextureProviderPublication?
        let preservedCurrent: SceneTextureProviderPublication?
        let systemTextures: [SceneSystemProviderTextureIdentity: MTLTexture]
        let publications: [
            SceneSystemProviderTextureIdentity: SceneTextureProviderPublication
        ]

        static let empty = Snapshot(
            generation: 0,
            pendingGeneration: nil,
            pendingIdentities: [],
            current: nil,
            preservedCurrent: nil,
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
    private var currentTextures: [SceneTextureLoadPurpose: MTLTexture] = [:]
    private var reportedPendingGeneration: UInt64?
    private var pendingRequest: DecodeRequest?

    init(
        device: MTLDevice,
        decodingQueue: DispatchQueue? = nil,
        imageDecoder: @escaping (Data) -> CGImage? =
            SceneMediaThumbnailTextureStore.decodeColorImage
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
                    + " hasColor=\(currentTextures[.premultipliedColor] != nil)"
                    + " hasPreserved=\(currentTextures[.preservedChannels] != nil)"
            )
        }
#endif
        let publication: (
            SceneTextureLoadPurpose,
            SceneTextureContent
        ) -> SceneTextureProviderPublication? = { purpose, content in
            guard let texture = self.currentTextures[purpose] else { return nil }
            let identity = SceneSystemProviderTextureIdentity(
                name: SceneMediaThumbnailBindingProgram.currentIdentity,
                purpose: purpose
            )
            let size = CGSize(width: texture.width, height: texture.height)
            return SceneTextureProviderPublication(
                requestIdentity: .system(identity),
                candidate: SceneTextureCandidate(
                    texture: texture,
                    identity: .provider(.mediaThumbnailCurrent),
                    generation: .provider(contentGeneration: self.readyGeneration),
                    purpose: purpose,
                    content: content,
                    physicalSize: size,
                    mappedSize: size,
                    uvTransform: .identity,
                    sampling: .linearClamp
                ),
                contentGeneration: self.readyGeneration
            )
        }
        let current = publication(
            .premultipliedColor,
            .color(.resolved(.premultipliedAlpha))
        )
        let preservedCurrent = publication(.preservedChannels, .data)
        let readyPublications = [current, preservedCurrent].compactMap { $0 }
        var textures: [SceneSystemProviderTextureIdentity: MTLTexture] = [:]
        var publications: [
            SceneSystemProviderTextureIdentity: SceneTextureProviderPublication
        ] = [:]
        for publication in readyPublications {
            guard case let .system(identity) = publication.requestIdentity else {
                continue
            }
            textures[identity] = publication.texture
            publications[identity] = publication
        }
        let pendingIdentities: Set<SceneSystemProviderTextureIdentity>
        if pendingRequest == nil {
            pendingIdentities = []
        } else {
            pendingIdentities = [
                .init(
                    name: SceneMediaThumbnailBindingProgram.currentIdentity,
                    purpose: .premultipliedColor
                ),
                .init(
                    name: SceneMediaThumbnailBindingProgram.currentIdentity,
                    purpose: .preservedChannels
                ),
            ]
        }
        return Snapshot(
            generation: readyGeneration,
            pendingGeneration: pendingRequest?.input.generation,
            pendingIdentities: pendingIdentities,
            current: current,
            preservedCurrent: preservedCurrent,
            systemTextures: textures,
            publications: publications
        )
    }

    private func decode(_ request: DecodeRequest) {
        guard shouldContinue(request) else { return }
        let input = request.input
        let currentImage = input.current.flatMap(imageDecoder)
        guard shouldContinue(request) else { return }
        let preservedTexture: MTLTexture?
        if let encodedSource = input.current,
           case let .success(texture) =
               SceneImageTextureUploader.uploadEncodedPreservedChannels(
                   encodedSource,
                   device: device
               ) {
            preservedTexture = texture
        } else {
            preservedTexture = nil
        }
        guard shouldContinue(request) else { return }
        var decodedTextures: [SceneTextureLoadPurpose: MTLTexture] = [:]
        if let currentImage,
           let texture = makeColorTexture(currentImage) {
            decodedTextures[.premultipliedColor] = texture
        }
        if let preservedTexture {
            decodedTextures[.preservedChannels] = preservedTexture
        }
        guard !request.isCancelled else { return }
        lock.lock()
        defer { lock.unlock() }
        guard pendingRequest === request,
              requestedGeneration == input.generation else { return }
        currentTextures = decodedTextures
        readyGeneration = input.generation
        reportedPendingGeneration = nil
        pendingRequest = nil
#if DEBUG
        print(
            "MWX media thumbnail store: phase=ready"
                + " generation=\(input.generation)"
                + " hasColor=\(decodedTextures[.premultipliedColor] != nil)"
                + " hasPreserved=\(decodedTextures[.preservedChannels] != nil)"
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

    private func makeColorTexture(_ image: CGImage) -> MTLTexture? {
        guard case let .loaded(texture) = SceneImageTextureUploader.upload(
            image: image,
            purpose: .premultipliedColor,
            maxDimension: 256,
            device: device
        ) else { return nil }
        return texture
    }

    nonisolated private static func decodeColorImage(_ data: Data) -> CGImage? {
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
