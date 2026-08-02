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
        let data: Data
        let container: SceneTexContainer?
        let parseError: String?
    }

    private static let directImageExtensions: Set<String> = ["png", "jpg", "jpeg"]
    private static let texExtension = "tex"
    private var textureOutcomes: [TextureKey: SceneTextureLoadOutcome] = [:]
    private var texResources: [SourceKey: TexResource] = [:]

    // GPUs cope poorly with extremely large textures (e.g. 8192×6144 RGBA8 =
    // 192 MB), and Apple Silicon's maxTexture2DLimit is 16384 but actual
    // allocation can still fail under memory pressure. Cap source images so
    // we always have headroom for several layers worth of textures.
    static let maxTextureDimension = 4096

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
        if let cached = textureOutcomes[key] {
            guard sourceKey(for: url) == source else {
                return .decodeFailed("file changed while loading: \(url.lastPathComponent)")
            }
            return cached
        }
        let ext = url.pathExtension.lowercased()
        let outcome: SceneTextureLoadOutcome
        if Self.directImageExtensions.contains(ext) {
            outcome = loadDirectImage(url: url, purpose: purpose, device: device)
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
        textureOutcomes[key] = outcome
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
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return .decodeFailed("CGImageSource failed to decode \(url.lastPathComponent)")
        }
        return SceneImageTextureUploader.upload(
            image: cgImage,
            purpose: purpose,
            maxDimension: Self.maxTextureDimension,
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
        let data = resource.data
        if let container = resource.container {
            if container.format == 0 {
                return loadFormatZeroContainer(
                    container,
                    fallbackData: data,
                    purpose: purpose,
                    device: device
                )
            }
            if let directUploadOutcome = makeDirectUploadTexture(
                from: container,
                purpose: purpose,
                device: device
            ) {
                return directUploadOutcome
            }
        }
        guard let embedded = Self.extractEmbeddedImageData(from: data) else {
            if let container = resource.container {
                return .unsupportedTexFormat(code: container.format)
            }
            return .decodeFailed("TEX parse failed: \(resource.parseError ?? "unknown error")")
        }
        guard let source = CGImageSourceCreateWithData(embedded as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return .decodeFailed("embedded image decode failed")
        }
        return SceneImageTextureUploader.upload(
            image: cgImage,
            purpose: purpose,
            maxDimension: Self.maxTextureDimension,
            device: device
        )
    }

    private func texResource(from url: URL, source: SourceKey) -> TexResource? {
        guard sourceKey(for: url) == source else { return nil }
        if let cached = texResources[source] { return cached }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        guard sourceKey(for: url) == source else { return nil }
        let resource: TexResource
        do {
            resource = TexResource(
                data: data,
                container: try SceneTexContainerReader().read(data: data),
                parseError: nil
            )
        } catch {
            resource = TexResource(
                data: data,
                container: nil,
                parseError: error.localizedDescription
            )
        }
        texResources[source] = resource
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
        fallbackData: Data,
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

        if Self.isEmbeddedImagePayload(firstMip.data) {
            let uploaded = purpose.preservesSourceChannels
                ? SceneTextureMipUploader.uploadEmbeddedDataImages(
                    container.mips,
                    device: device
                )
                : SceneTextureMipUploader.uploadEmbeddedImages(
                    container.mips,
                    device: device
                )
            return uploaded ?? decodeEmbeddedImagePayload(
                firstMip.data,
                purpose: purpose,
                device: device
            )
        }

        let expectedRawByteCount = firstMip.width * firstMip.height * 4
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

        if let embedded = Self.extractEmbeddedImageData(from: fallbackData) {
            return decodeEmbeddedImagePayload(
                embedded,
                purpose: purpose,
                device: device
            )
        }

        return .decodeFailed("raw ARGB8888 mip data size mismatch: \(firstMip.data.count) != \(expectedRawByteCount)")
    }

    // Returns the byte range of the first JPEG or PNG payload inside a .tex
    // container. Two rules avoid false positives that arise when scanning a
    // multi-megabyte compressed payload byte-by-byte:
    //
    //  1. Search only the first 256 bytes for the magic. Wallpaper Engine's
    //     .tex container header (TEXV/TEXI/TEXB blocks + format/size fields)
    //     is small; the embedded image's magic always lands inside this
    //     window. Beyond that window any byte triple in compressed data is
    //     just random — and `\xFF\xD8\xFF` happens often enough inside large
    //     PNGs to make the loader misidentify them as JPEGs and try to decode
    //     PNG data from the middle.
    //  2. Hand the full tail (magic → file end) to CGImageSource and let it
    //     find the JPEG EOI / PNG IEND itself. Byte-searching for EOI/IEND
    //     is unsafe — both byte sequences regularly appear inside JPEG
    //     entropy-coded segments and PNG zlib streams.
    private static func extractEmbeddedImageData(from data: Data) -> Data? {
        let jpegSOI = Data([0xFF, 0xD8, 0xFF])
        let pngMagic = Data([0x89, 0x50, 0x4E, 0x47])
        let searchEnd = min(256, data.count)
        let searchRange = 0..<searchEnd

        // PNG and JPEG can in principle coexist in the same header window
        // (they don't in practice), so pick whichever magic appears earlier.
        let pngLoc = data.range(of: pngMagic, in: searchRange)?.lowerBound
        let jpgLoc = data.range(of: jpegSOI, in: searchRange)?.lowerBound

        let chosen: Int?
        switch (pngLoc, jpgLoc) {
        case let (p?, j?): chosen = min(p, j)
        case let (p?, nil): chosen = p
        case let (nil, j?): chosen = j
        case (nil, nil): chosen = nil
        }
        guard let start = chosen else { return nil }
        return data.subdata(in: start..<data.count)
    }

    private func decodeEmbeddedImagePayload(
        _ data: Data,
        purpose: SceneTextureLoadPurpose,
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
