import Foundation
import Metal
import CoreGraphics
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
    private struct SourceKey: Hashable {
        let path: String
        let size: UInt64
        let modifiedAtBits: UInt64
    }

    private struct TextureKey: Hashable {
        let source: SourceKey
        let deviceRegistryID: UInt64
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
    private static let maxTextureDimension = 4096

    func load(from url: URL, device: MTLDevice) -> SceneTextureLoadOutcome {
        let key = TextureKey(source: sourceKey(for: url), deviceRegistryID: device.registryID)
        if let cached = textureOutcomes[key] { return cached }
        let ext = url.pathExtension.lowercased()
        let outcome: SceneTextureLoadOutcome
        if Self.directImageExtensions.contains(ext) {
            outcome = loadDirectImage(url: url, device: device)
        } else if ext == Self.texExtension {
            outcome = loadWallpaperEngineTex(url: url, device: device)
        } else {
            outcome = .unsupportedFormat(extension: ext)
        }
        textureOutcomes[key] = outcome
        return outcome
    }

    func makeVideoTextureSourceIfNeeded(
        from url: URL,
        layerID: Int,
        cacheDirectory: URL,
        device: MTLDevice
    ) -> SceneVideoTextureSource? {
        guard url.pathExtension.lowercased() == Self.texExtension,
              let resource = texResource(from: url),
              let container = resource.container,
              container.format == 0,
              let payload = container.mips.first?.data,
              container.isVideoMp4 || Self.isMP4Payload(payload) else {
            return nil
        }
        return SceneVideoTextureSource(
            layerID: layerID,
            mp4PayloadData: payload,
            cacheDirectory: cacheDirectory,
            device: device
        )
    }

    func texContainer(from url: URL) -> SceneTexContainer? {
        guard url.pathExtension.lowercased() == Self.texExtension else { return nil }
        return texResource(from: url)?.container
    }

    private func loadDirectImage(url: URL, device: MTLDevice) -> SceneTextureLoadOutcome {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return .decodeFailed("CGImageSource failed to decode \(url.lastPathComponent)")
        }
        return makeTexture(from: cgImage, device: device)
    }

    // Wallpaper Engine .tex containers wrap one or more compressed payloads;
    // photographic textures typically embed a JPEG mipmap chain. We extract
    // just the largest (first) JPEG or PNG payload and decode that. .tex
    // variants using DXT/BC compression have no embedded standard image and
    // are reported as such for diagnosis.
    private func loadWallpaperEngineTex(url: URL, device: MTLDevice) -> SceneTextureLoadOutcome {
        guard let resource = texResource(from: url) else {
            return .decodeFailed("read failed: \(url.lastPathComponent)")
        }
        let data = resource.data
        if let container = resource.container {
            if container.format == 0 {
                return loadFormatZeroContainer(container, fallbackData: data, device: device)
            }
            if let directUploadOutcome = makeDirectUploadTexture(from: container, device: device) {
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
        return makeTexture(from: cgImage, device: device)
    }

    private func texResource(from url: URL) -> TexResource? {
        let key = sourceKey(for: url)
        if let cached = texResources[key] { return cached }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
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
        texResources[key] = resource
        return resource
    }

    private func sourceKey(for url: URL) -> SourceKey {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        let modifiedAt = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return SourceKey(
            path: url.resolvingSymlinksInPath().standardizedFileURL.path,
            size: size,
            modifiedAtBits: modifiedAt.bitPattern
        )
    }

    private func loadFormatZeroContainer(
        _ container: SceneTexContainer,
        fallbackData: Data,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let firstMip = container.mips.first else {
            return .decodeFailed("TEX container has no mip data")
        }

        if Self.isMP4Payload(firstMip.data) {
            return .texContainsVideoPayload
        }

        if Self.isEmbeddedImagePayload(firstMip.data) {
            return SceneTextureMipUploader.uploadEmbeddedImages(
                container.mips,
                device: device
            ) ?? decodeEmbeddedImagePayload(firstMip.data, device: device)
        }

        let expectedRawByteCount = firstMip.width * firstMip.height * 4
        if firstMip.data.count == expectedRawByteCount {
            return SceneTextureMipUploader.uploadRawRGBA(container: container, device: device)
        }

        if let embedded = Self.extractEmbeddedImageData(from: fallbackData) {
            return decodeEmbeddedImagePayload(embedded, device: device)
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

    private func makeTexture(from cgImage: CGImage, device: MTLDevice) -> SceneTextureLoadOutcome {
        let srcWidth = cgImage.width
        let srcHeight = cgImage.height
        guard srcWidth > 0, srcHeight > 0 else {
            return .decodeFailed("zero-sized image")
        }

        // Proportionally cap dimensions so we never allocate a > maxDim texture.
        let maxDim = Self.maxTextureDimension
        let scale: Double
        if srcWidth > maxDim || srcHeight > maxDim {
            scale = Double(maxDim) / Double(max(srcWidth, srcHeight))
        } else {
            scale = 1.0
        }
        let width = max(1, Int(Double(srcWidth) * scale))
        let height = max(1, Int(Double(srcHeight) * scale))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return .textureAllocationFailed(width: width, height: height)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return .decodeFailed("CGContext create failed (\(width)×\(height))")
        }

        // Draw without flipping. CGBitmapContext stores rows top-down in
        // memory (row 0 is the visual top), so CGImage row 0 (image top)
        // already lands at memory row 0 = MTLTexture (0,0) = UV (0,0).
        // Previously we applied translateBy+scaleBy here, which actually
        // flipped the texture upside down. CGContext also resamples the
        // source CGImage into our target rect automatically, so the
        // downsample for huge images happens transparently.
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return .decodeFailed("CGContext data unavailable")
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: bytesPerRow
        )
        return .loaded(texture)
    }

    private func decodeEmbeddedImagePayload(
        _ data: Data,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return .decodeFailed("embedded image decode failed")
        }
        return makeTexture(from: cgImage, device: device)
    }

    private func makeCompressedTexture(
        from container: SceneTexContainer,
        pixelFormat: MTLPixelFormat,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        SceneCompressedTextureUploader.upload(
            container: container,
            pixelFormat: pixelFormat,
            device: device
        )
    }

    private func makeDirectUploadTexture(
        from container: SceneTexContainer,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome? {
        if let pixelFormat = container.metalPixelFormat {
            return makeCompressedTexture(from: container, pixelFormat: pixelFormat, device: device)
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

    private static func isMP4Payload(_ data: Data?) -> Bool {
        guard let data, data.count >= 12 else { return false }
        return data[4...7].elementsEqual(Data("ftyp".utf8))
    }

    private static func isEmbeddedImagePayload(_ data: Data) -> Bool {
        data.starts(with: Data([0x89, 0x50, 0x4E, 0x47]))
            || data.starts(with: Data([0xFF, 0xD8, 0xFF]))
    }

}
