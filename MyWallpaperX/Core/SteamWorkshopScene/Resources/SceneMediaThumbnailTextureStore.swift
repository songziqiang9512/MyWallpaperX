import Foundation
import ImageIO
import Metal

final class SceneMediaThumbnailTextureStore: @unchecked Sendable {
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
    private let queue = DispatchQueue(
        label: "com.mywallpaperx.scene.media-thumbnail",
        qos: .userInitiated
    )
    private let lock = NSLock()
    private var requestedGeneration: UInt64 = 0
    private var readyGeneration: UInt64 = 0
    private var currentTexture: MTLTexture?
    private var previousTexture: MTLTexture?

    init(device: MTLDevice) {
        self.device = device
    }

    func update(from input: SceneMediaThumbnailInbox.Snapshot) {
        lock.lock()
        guard input.generation != requestedGeneration else {
            lock.unlock()
            return
        }
        requestedGeneration = input.generation
        lock.unlock()

        queue.async { [weak self] in
            self?.decode(input)
        }
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        guard readyGeneration == requestedGeneration else { return .empty }
        var textures: [String: MTLTexture] = [:]
        var publications: [String: SceneTextureProviderPublication] = [:]
        let current = currentTexture.map {
            SceneTextureProviderPublication(texture: $0, contentGeneration: readyGeneration)
        }
        if let current {
            textures[SceneMediaThumbnailBindingProgram.currentIdentity] = current.texture
            publications[SceneMediaThumbnailBindingProgram.currentIdentity] = current
        }
        if let previousTexture {
            let previous = SceneTextureProviderPublication(
                texture: previousTexture,
                contentGeneration: readyGeneration
            )
            textures[SceneMediaThumbnailBindingProgram.previousIdentity] = previous.texture
            publications[SceneMediaThumbnailBindingProgram.previousIdentity] = previous
        }
        return Snapshot(
            generation: readyGeneration,
            current: current,
            systemTextures: textures,
            publications: publications
        )
    }

    private func decode(_ input: SceneMediaThumbnailInbox.Snapshot) {
        let current = input.current.flatMap(Self.decodeImage).flatMap(makeTexture)
        let previous = input.previous.flatMap(Self.decodeImage).flatMap(makeTexture)
        lock.lock()
        defer { lock.unlock() }
        guard requestedGeneration == input.generation else { return }
        currentTexture = current
        previousTexture = previous
        readyGeneration = input.generation
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
