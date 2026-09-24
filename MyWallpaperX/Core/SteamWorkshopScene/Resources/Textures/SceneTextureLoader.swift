import Foundation
import Metal
import CoreGraphics
import Darwin
import ImageIO

// Outcome of attempting to load a layer texture. Captured so the preview can
// report exactly *why* a layer's texture didn't show up (file missing, .tex
// uses a compressed codec we don't decode, oversized texture allocation
// failed, etc.) — black previews are otherwise impossible to debug.
enum SceneTextureLoadOutcome {
    case loaded(MTLTexture)
    case unsupportedFormat(extension: String)
    case unsupportedTexFormat(code: UInt32)
    case texNoEmbeddedImage             // .tex container is DXT/BC, no JPEG/PNG inside
    case texContainsVideoPayload
    case decodeFailed(String)
    case textureAllocationFailed(width: Int, height: Int)
}

/// Shared admission counter for launch-lifetime decoded texture caches. It
/// accounts only re-creatable source/decoded bytes; published Metal textures
/// remain owned by their existing product stores and are never evicted here.
nonisolated final class SceneTextureDecodeCacheBudget: @unchecked Sendable {
    private let lock = NSLock()
    private var limit: Int
    private var reserved = 0
    private var rejectedAdmissions = 0

    init(maximumBytes: Int) {
        limit = max(maximumBytes, 0)
    }

    var maximumBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return limit
    }

    var residentBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return reserved
    }

    var rejectionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return rejectedAdmissions
    }

    func updateMaximumBytes(_ maximumBytes: Int) {
        lock.lock()
        limit = max(maximumBytes, 0)
        lock.unlock()
    }

    fileprivate func reserve(_ byteCount: Int) -> Bool {
        guard byteCount >= 0 else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard byteCount <= limit - min(reserved, limit) else {
            rejectedAdmissions += 1
            return false
        }
        reserved += byteCount
        return true
    }

    fileprivate func release(_ byteCount: Int) {
        lock.lock()
        reserved = max(reserved - max(byteCount, 0), 0)
        lock.unlock()
    }
}

nonisolated private final class SceneTextureDecodeCacheLease {
    private let budget: SceneTextureDecodeCacheBudget
    private var reservedBytes = 0

    init(budget: SceneTextureDecodeCacheBudget) {
        self.budget = budget
    }

    deinit {
        budget.release(reservedBytes)
    }

    func reserve(_ byteCount: Int) -> Bool {
        guard budget.reserve(byteCount) else { return false }
        reservedBytes += byteCount
        return true
    }
}

final class SceneTextureLoader {
    struct SourceKey: Hashable {
        let path: String
        let size: UInt64
        let modifiedAtBits: UInt64
        let fileSystemID: UInt64
        let fileID: UInt64
        let statusChangedAtSeconds: Int64
        let statusChangedAtNanoseconds: Int64
    }

    private struct TextureKey: Hashable {
        let source: SourceKey
        let deviceRegistryID: UInt64
        let purpose: SceneTextureLoadPurpose
    }

    private struct TexResource {
        let container: SceneTexContainer?
        let parseError: String?

        var decodedByteCost: Int? {
            guard let container else { return 0 }
            let (frameBytes, frameOverflow) = container.spriteFrames.count
                .multipliedReportingOverflow(by: MemoryLayout<SceneTexContainer.SpriteFrame>.stride)
            guard !frameOverflow else { return nil }
            var total = frameBytes
            for image in container.images {
                for mip in image.mips {
                    let (next, overflow) = total.addingReportingOverflow(mip.data.count)
                    guard !overflow else { return nil }
                    total = next
                }
            }
            return total
        }
    }

    private enum DirectImageResource {
        case decoded(CGImage)
        case failed(String)
    }

    private enum TexEmbeddedImageResource {
        case decoded([CGImage])
        case failed
    }

    private static let directImageExtensions: Set<String> = ["png", "jpg", "jpeg"]
    private static let texExtension = "tex"
    private var textures: [TextureKey: MTLTexture] = [:]
    private var texResources: [SourceKey: TexResource] = [:]
    private var directImageResources: [SourceKey: DirectImageResource] = [:]
    private var texEmbeddedImageResources: [SourceKey: TexEmbeddedImageResource] = [:]
    let uploadCommandQueue: SceneTextureUploadCommandQueue
    let decodeCacheBudget: SceneTextureDecodeCacheBudget
    private let decodeCacheLease: SceneTextureDecodeCacheLease
    private(set) var directImageDecodeAttemptCount = 0
    private(set) var texEmbeddedImageDecodeAttemptCount = 0

    // GPUs cope poorly with extremely large textures (e.g. 8192×6144 RGBA8 =
    // 192 MB), and Apple Silicon's maxTexture2DLimit is 16384 but actual
    // allocation can still fail under memory pressure. Cap source images so
    // we always have headroom for several layers worth of textures.
    static let maxTextureDimension = 4096

    init(
        uploadCommandQueue: SceneTextureUploadCommandQueue = .init(),
        decodeCacheBudget: SceneTextureDecodeCacheBudget = .init(
            maximumBytes: 1_024 * 1_024 * 1_024
        )
    ) {
        self.uploadCommandQueue = uploadCommandQueue
        self.decodeCacheBudget = decodeCacheBudget
        self.decodeCacheLease = SceneTextureDecodeCacheLease(
            budget: decodeCacheBudget
        )
    }

    func load(from url: URL, device: MTLDevice) -> SceneTextureLoadOutcome {
        load(from: url, purpose: .premultipliedColor, device: device)
    }

    /// Loads a texture according to the consumer's channel contract. The
    /// purpose participates in cache identity so one source can safely serve
    /// both composited color and data/straight-channel consumers.
    func load(
        from url: URL,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let source = sourceKey(for: url) else {
            return .decodeFailed("file metadata unavailable: \(url.lastPathComponent)")
        }
        return load(
            from: url,
            source: source,
            purpose: purpose,
            device: device
        )
    }

    func load(
        from url: URL,
        source: SourceKey,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        let key = TextureKey(
            source: source,
            deviceRegistryID: device.registryID,
            purpose: purpose
        )
        if let cached = textures[key] {
            guard sourceKey(for: url) == source else {
                return .decodeFailed("file changed while loading: \(url.lastPathComponent)")
            }
            return .loaded(cached)
        }
        let ext = url.pathExtension.lowercased()
        let outcome: SceneTextureLoadOutcome
        if Self.directImageExtensions.contains(ext) {
            outcome = loadDirectImage(
                url: url,
                source: source,
                purpose: purpose,
                device: device
            )
        } else if ext == Self.texExtension {
            outcome = loadWallpaperEngineTex(
                url: url,
                source: source,
                purpose: purpose,
                device: device
            )
        } else {
            outcome = .unsupportedFormat(extension: ext)
        }
        guard sourceKey(for: url) == source else {
            return .decodeFailed("file changed while loading: \(url.lastPathComponent)")
        }
        // Upload failures describe this attempt, not an immutable property of
        // the source. Keep decoded resources reusable while allowing a later
        // explicit load to recover from transient Metal allocation/GPU faults.
        if case let .loaded(texture) = outcome { textures[key] = texture }
        return outcome
    }

    /// Compatibility wrapper for existing data consumers.
    func loadDataTexture(from url: URL, device: MTLDevice) -> SceneTextureLoadOutcome {
        load(from: url, purpose: .preservedChannels, device: device)
    }

    func texContainer(from url: URL) -> SceneTexContainer? {
        guard let source = sourceKey(for: url) else { return nil }
        return texContainer(from: url, source: source)
    }

    func texContainer(from url: URL, source: SourceKey) -> SceneTexContainer? {
        guard url.pathExtension.lowercased() == Self.texExtension else { return nil }
        return texResource(from: url, source: source)?.container
    }

    private func loadDirectImage(
        url: URL,
        source: SourceKey,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        let resource: DirectImageResource
        if let cached = directImageResources[source] {
            resource = cached
        } else {
            directImageDecodeAttemptCount += 1
            if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
                resource = .decoded(image)
            } else {
                resource = .failed(
                    "CGImageSource failed to decode \(url.lastPathComponent)"
                )
            }
            if case let .decoded(image) = resource,
               decodeCacheLease.reserve(Self.decodedByteCost(image)) {
                directImageResources[source] = resource
            } else if case .failed = resource {
                directImageResources[source] = resource
            }
        }
        let cgImage: CGImage
        switch resource {
        case let .decoded(image):
            cgImage = image
        case let .failed(message):
            return .decodeFailed(message)
        }
        return SceneImageTextureUploader.upload(
            image: cgImage,
            purpose: purpose,
            maxDimension: Self.maxTextureDimension,
            uploadCommandQueue: uploadCommandQueue,
            device: device
        )
    }

    // TEX payloads may be raw, BC, embedded images, video, or a bounded volume;
    // dispatch only after the container metadata has been preserved.
    private func loadWallpaperEngineTex(
        url: URL,
        source: SourceKey,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let resource = texResource(from: url, source: source) else {
            return .decodeFailed("read failed: \(url.lastPathComponent)")
        }
        guard let container = resource.container else {
            return .decodeFailed("TEX parse failed: \(resource.parseError ?? "unknown error")")
        }
        if container.format == 0 {
            return loadFormatZeroContainer(
                container,
                source: source,
                purpose: purpose,
                device: device
            )
        }
        return makeDirectUploadTexture(
            from: container,
            purpose: purpose,
            device: device
        ) ?? .unsupportedTexFormat(code: container.format)
    }

    private func texResource(from url: URL, source: SourceKey) -> TexResource? {
        guard sourceKey(for: url) == source else { return nil }
        if let cached = texResources[source] { return cached }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        guard sourceKey(for: url) == source else { return nil }
        let resource: TexResource
        do {
            resource = TexResource(
                container: try SceneTexContainerReader().read(data: data),
                parseError: nil
            )
        } catch {
            resource = TexResource(
                container: nil,
                parseError: error.localizedDescription
            )
        }
        // The source file may be much smaller than its decompressed mips.
        // Only parsed payloads remain resident; the original bytes are no
        // longer needed once the container has been validated.
        if let byteCost = resource.decodedByteCost,
           decodeCacheLease.reserve(byteCost) {
            texResources[source] = resource
        }
        return resource
    }

    func sourceKey(for url: URL) -> SourceKey? {
        let canonicalPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        var status = Darwin.stat()
        guard canonicalPath.withCString({
            Darwin.lstat($0, &status)
        }) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_size >= 0 else {
            return nil
        }
        let modifiedAt = Double(status.st_mtimespec.tv_sec)
            + Double(status.st_mtimespec.tv_nsec) / 1_000_000_000
        return SourceKey(
            path: canonicalPath,
            size: UInt64(status.st_size),
            modifiedAtBits: modifiedAt.bitPattern,
            fileSystemID: UInt64(bitPattern: Int64(status.st_dev)),
            fileID: UInt64(status.st_ino),
            statusChangedAtSeconds: Int64(status.st_ctimespec.tv_sec),
            statusChangedAtNanoseconds: Int64(status.st_ctimespec.tv_nsec)
        )
    }

    private func loadFormatZeroContainer(
        _ container: SceneTexContainer,
        source: SourceKey,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let firstMip = container.mips.first else {
            return .decodeFailed("TEX container has no mip data")
        }

        if container.isVolume || purpose.requiresVolumeTexture {
            return SceneTextureMipUploader.uploadVolume(
                container: container,
                purpose: purpose,
                device: device
            )
        }

        if Self.isMP4Payload(firstMip.data) {
            return .texContainsVideoPayload
        }

        if container.containerVersion == .texb0003,
           Self.isEmbeddedImagePayload(firstMip.data)
            || [2, 13].contains(container.freeImageFormat),
           !hasValidTexb3EmbeddedMipChain(container) {
            return .decodeFailed("compiled TEX embedded mip metadata does not match its payload")
        }

        if Self.isEmbeddedImagePayload(firstMip.data) {
            guard let images = cachedTexEmbeddedImages(
                source: source,
                payloads: container.mips.map(\.data)
            ) else {
                return .decodeFailed("compiled TEX embedded mip chain could not be decoded")
            }
            let uploaded = purpose.preservesSourceChannels
                ? SceneTextureMipUploader.uploadEmbeddedDataImages(
                    images,
                    purpose: purpose,
                    maximumDimension: Self.maxTextureDimension,
                    device: device
                )
                : SceneTextureMipUploader.uploadEmbeddedImages(
                    images,
                    device: device
                )
            if let uploaded {
                return uploaded
            }
            guard container.mips.count == 1 else {
                return .decodeFailed(
                    "compiled TEX embedded mip chain could not be preserved"
                )
            }
            return decodeEmbeddedImagePayload(
                firstMip.data,
                purpose: purpose,
                mipmapGeneration: .baseLevelOnly,
                device: device
            )
        }

        guard let expectedRawByteCount = SceneTexContainer.byteCount2D(
            width: firstMip.width, height: firstMip.height, bytesPerElement: 4
        ) else {
            return .decodeFailed("raw ARGB8888 dimensions exceed addressable byte size")
        }
        if firstMip.data.count == expectedRawByteCount {
            if purpose.preservesSourceChannels {
                return SceneTextureMipUploader.uploadRaw(
                    container: container,
                    pixelFormat: .rgba8Unorm,
                    bytesPerPixel: 4,
                    device: device
                )
            }
            return SceneTextureMipUploader.uploadRawRGBA(
                container: container,
                device: device
            )
        }

        return .decodeFailed("raw ARGB8888 mip data size mismatch: \(firstMip.data.count) != \(expectedRawByteCount)")
    }

    func hasValidTexb3EmbeddedMipChain(_ container: SceneTexContainer) -> Bool {
        guard SceneTexContainer.valid2DMipDimensions(
            container.mips.map { ($0.width, $0.height) }
        ) else { return false }
        let expectedMagic: Data
        switch container.freeImageFormat {
        case 2:
            expectedMagic = Data([0xFF, 0xD8, 0xFF])
        case 13:
            expectedMagic = Data([0x89, 0x50, 0x4E, 0x47])
        default:
            return false
        }
        return container.mips.allSatisfy { mip in
            mip.data.starts(with: expectedMagic)
                && embeddedImagePixelSize(mip.data)
                    == CGSize(width: mip.width, height: mip.height)
        }
    }

    func embeddedImagePixelSize(_ data: Data) -> CGSize? {
        guard Self.isEmbeddedImagePayload(data),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    private func cachedTexEmbeddedImages(
        source: SourceKey,
        payloads: [Data]
    ) -> [CGImage]? {
        if let cached = texEmbeddedImageResources[source] {
            guard case let .decoded(images) = cached else { return nil }
            return images
        }
        texEmbeddedImageDecodeAttemptCount += payloads.count
        guard let images = SceneTextureMipUploader.decodeEmbeddedImages(payloads) else {
            texEmbeddedImageResources[source] = .failed
            return nil
        }
        let byteCost = images.reduce(into: 0) { total, image in
            let (next, overflow) = total.addingReportingOverflow(
                Self.decodedByteCost(image)
            )
            total = overflow ? Int.max : next
        }
        if decodeCacheLease.reserve(byteCost) {
            texEmbeddedImageResources[source] = .decoded(images)
        }
        return images
    }

    private static func decodedByteCost(_ image: CGImage) -> Int {
        let (cost, overflow) = image.bytesPerRow.multipliedReportingOverflow(
            by: image.height
        )
        return overflow ? Int.max : cost
    }

    private func decodeEmbeddedImagePayload(
        _ data: Data,
        purpose: SceneTextureLoadPurpose,
        mipmapGeneration: SceneImageTextureUploader.MipmapGeneration,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return .decodeFailed("embedded image decode failed")
        }
        return SceneImageTextureUploader.upload(
            image: cgImage,
            purpose: purpose,
            maxDimension: Self.maxTextureDimension,
            mipmapGeneration: mipmapGeneration,
            uploadCommandQueue: uploadCommandQueue,
            device: device
        )
    }

    private func makeDirectUploadTexture(
        from container: SceneTexContainer,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome? {
        if let pixelFormat = container.metalPixelFormat {
            return SceneCompressedTextureUploader.upload(
                container: container,
                pixelFormat: pixelFormat,
                purpose: purpose,
                uploadCommandQueue: uploadCommandQueue,
                device: device
            )
        }
        if let pixelFormat = container.rawMetalPixelFormat,
           let bytesPerPixel = container.rawBytesPerPixel {
            return SceneTextureMipUploader.uploadRaw(
                container: container,
                pixelFormat: pixelFormat,
                bytesPerPixel: bytesPerPixel,
                device: device
            )
        }
        if container.format == 0 {
            return SceneTextureMipUploader.uploadRawRGBA(container: container, device: device)
        }
        return nil
    }

    static func isMP4Payload(_ data: Data?) -> Bool {
        guard let data, data.count >= 12 else { return false }
        return data[4...7].elementsEqual(Data("ftyp".utf8))
    }

    private static func isEmbeddedImagePayload(_ data: Data) -> Bool {
        data.starts(with: Data([0x89, 0x50, 0x4E, 0x47]))
            || data.starts(with: Data([0xFF, 0xD8, 0xFF]))
    }

}
