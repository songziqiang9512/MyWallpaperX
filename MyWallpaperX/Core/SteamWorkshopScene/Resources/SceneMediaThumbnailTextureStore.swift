import Foundation
import ImageIO
import Metal

final class SceneMediaThumbnailTextureStore: @unchecked Sendable {
    private final class DecodeRequest: @unchecked Sendable {
        let input: SceneMediaThumbnailInbox.Snapshot
        let willRotatePrevious: Bool

        private let lock = NSLock()
        private var cancelled = false

        init(
            input: SceneMediaThumbnailInbox.Snapshot,
            willRotatePrevious: Bool
        ) {
            self.input = input
            self.willRotatePrevious = willRotatePrevious
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
        let previous: SceneTextureProviderPublication?
        let preservedPrevious: SceneTextureProviderPublication?
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
            previous: nil,
            preservedPrevious: nil,
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
    private var previousTextures: [SceneTextureLoadPurpose: MTLTexture] = [:]
    private var lastSuccessfulTextures: [SceneTextureLoadPurpose: MTLTexture] = [:]
    private var lastSuccessfulEncodedCurrent: Data?
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
        let request = DecodeRequest(
            input: input,
            willRotatePrevious: input.current != nil
                && input.current != lastSuccessfulEncodedCurrent
                && !lastSuccessfulTextures.isEmpty
        )
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
                    + " hasPreviousColor=\(previousTextures[.premultipliedColor] != nil)"
                    + " hasPreviousPreserved=\(previousTextures[.preservedChannels] != nil)"
            )
        }
#endif
        let publication: (
            String,
            SceneTextureProviderIdentity,
            [SceneTextureLoadPurpose: MTLTexture],
            SceneTextureLoadPurpose,
            SceneTextureContent
        ) -> SceneTextureProviderPublication? = {
            name, providerIdentity, textures, purpose, content in
            guard let texture = textures[purpose] else { return nil }
            let identity = SceneSystemProviderTextureIdentity(
                name: name,
                purpose: purpose
            )
            let size = CGSize(width: texture.width, height: texture.height)
            return SceneTextureProviderPublication(
                requestIdentity: .system(identity),
                candidate: SceneTextureCandidate(
                    texture: texture,
                    identity: .provider(providerIdentity),
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
            SceneMediaThumbnailBindingProgram.currentIdentity,
            .mediaThumbnailCurrent,
            currentTextures,
            .premultipliedColor,
            .color(.resolved(.premultipliedAlpha))
        )
        let preservedCurrent = publication(
            SceneMediaThumbnailBindingProgram.currentIdentity,
            .mediaThumbnailCurrent,
            currentTextures,
            .preservedChannels,
            .data
        )
        let previous = publication(
            SceneMediaThumbnailBindingProgram.previousIdentity,
            .mediaThumbnailPrevious,
            previousTextures,
            .premultipliedColor,
            .color(.resolved(.premultipliedAlpha))
        )
        let preservedPrevious = publication(
            SceneMediaThumbnailBindingProgram.previousIdentity,
            .mediaThumbnailPrevious,
            previousTextures,
            .preservedChannels,
            .data
        )
        let readyPublications = [
            current, preservedCurrent, previous, preservedPrevious,
        ].compactMap { $0 }
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
            var identities: Set<SceneSystemProviderTextureIdentity> = [
                .init(
                    name: SceneMediaThumbnailBindingProgram.currentIdentity,
                    purpose: .premultipliedColor
                ),
                .init(
                    name: SceneMediaThumbnailBindingProgram.currentIdentity,
                    purpose: .preservedChannels
                ),
            ]
            if pendingRequest?.willRotatePrevious == true {
                identities.insert(.init(
                    name: SceneMediaThumbnailBindingProgram.previousIdentity,
                    purpose: .premultipliedColor
                ))
                identities.insert(.init(
                    name: SceneMediaThumbnailBindingProgram.previousIdentity,
                    purpose: .preservedChannels
                ))
            }
            pendingIdentities = identities
        }
        return Snapshot(
            generation: readyGeneration,
            pendingGeneration: pendingRequest?.input.generation,
            pendingIdentities: pendingIdentities,
            current: current,
            preservedCurrent: preservedCurrent,
            previous: previous,
            preservedPrevious: preservedPrevious,
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
        if input.current == nil {
            currentTextures.removeAll(keepingCapacity: true)
            previousTextures.removeAll(keepingCapacity: true)
            lastSuccessfulTextures.removeAll(keepingCapacity: true)
            lastSuccessfulEncodedCurrent = nil
        } else if !decodedTextures.isEmpty {
            if request.willRotatePrevious {
                previousTextures = lastSuccessfulTextures
            }
            currentTextures = decodedTextures
            lastSuccessfulTextures = decodedTextures
            lastSuccessfulEncodedCurrent = input.current
        } else {
            // A malformed replacement must restore the authored fallback,
            // not expose either stale side of a transition. Keep only the
            // private last-successful atom so a later valid cover can still
            // identify the actual previous cover.
            currentTextures.removeAll(keepingCapacity: true)
            previousTextures.removeAll(keepingCapacity: true)
        }
        readyGeneration = input.generation
        reportedPendingGeneration = nil
        pendingRequest = nil
#if DEBUG
        print(
            "MWX media thumbnail store: phase=ready"
                + " generation=\(input.generation)"
                + " hasColor=\(decodedTextures[.premultipliedColor] != nil)"
                + " hasPreserved=\(decodedTextures[.preservedChannels] != nil)"
                + " hasPreviousColor=\(previousTextures[.premultipliedColor] != nil)"
                + " hasPreviousPreserved=\(previousTextures[.preservedChannels] != nil)"
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
