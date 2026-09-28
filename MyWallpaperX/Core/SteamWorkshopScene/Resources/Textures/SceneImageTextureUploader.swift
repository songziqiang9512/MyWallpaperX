import CoreGraphics
import Foundation
import ImageIO
import Metal

/// One device-scoped upload queue shared by launch/resource owners. Metal
/// command queues are thread-safe; serial command-buffer order remains local
/// to each synchronous upload while queue construction leaves the hot loop.
nonisolated final class SceneTextureUploadCommandQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var queues: [UInt64: MTLCommandQueue] = [:]
    private var creationAttempts = 0

    var creationAttemptCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return creationAttempts
    }

    func commandQueue(for device: MTLDevice) -> MTLCommandQueue? {
        lock.lock()
        defer { lock.unlock() }
        if let queue = queues[device.registryID] { return queue }
        creationAttempts += 1
        // Allocation failure is local to this request. Later resource loads
        // must be able to recover without replacing the shared upload owner.
        guard let queue = device.makeCommandQueue() else { return nil }
        queue.label = "MyWallpaperX Scene Resource Upload"
        queues[device.registryID] = queue
        return queue
    }
}

nonisolated enum SceneTextureLoadPurpose: Hashable, Sendable {
    case premultipliedColor
    case straightAlbedo
    case preservedChannels
    case mask
    case noise
    case flow
    case phase
    case normal
    case depth
    case lookupTable

    var preservesSourceChannels: Bool {
        switch self {
        case .premultipliedColor:
            false
        case .straightAlbedo, .preservedChannels, .mask, .noise, .flow, .phase,
             .normal, .depth, .lookupTable:
            true
        }
    }

    var requiresVolumeTexture: Bool {
        self == .lookupTable
    }
}

enum SceneImageTextureUploader {
    // The supported macOS Metal GPU families allow at most 16384 per 2D axis.
    // makeTexture can assert on an invalid descriptor instead of returning nil.
    static func supports2DExtent(width: Int, height: Int) -> Bool {
        (1...16_384).contains(width) && (1...16_384).contains(height)
    }

    enum MipmapGeneration {
        case fullChain
        case baseLevelOnly
    }

    private enum UploadFailure: Error {
        case allocation
        case mipmapGeneration(String)
    }

    enum EncodedPreservedChannelsError: Error, Equatable {
        case emptySource
        case imageSourceUnavailable
        case metadataUnavailable
        case dimensionsOutOfRange(width: Int, height: Int, maximum: Int)
        case nonIdentityOrientation(Int)
        case decodeUnavailable
        case decodedDimensionsMismatch(
            expectedWidth: Int,
            expectedHeight: Int,
            actualWidth: Int,
            actualHeight: Int
        )
        case unsupportedPixelLayout
        case premultipliedPixelLayout
        case textureAllocationFailed(width: Int, height: Int)
        case mipmapGenerationFailed(String)
    }

    static let encodedPreservedChannelsMaximumDimension = 256
    private static let encodedPreservedChannelsMaximumSourceDimension = 4_096

    /// Decodes a bounded encoded source directly into a channel-preserving
    /// texture. This path never consumes an existing color texture because a
    /// premultiplied texture cannot recover source RGB at zero/fractional alpha.
    static func uploadEncodedPreservedChannels(
        _ encodedSource: Data,
        uploadCommandQueue: SceneTextureUploadCommandQueue = .init(),
        device: MTLDevice
    ) -> Result<MTLTexture, EncodedPreservedChannelsError> {
        guard !encodedSource.isEmpty else { return .failure(.emptySource) }
        guard let imageSource = CGImageSourceCreateWithData(
            encodedSource as CFData,
            nil
        ) else {
            return .failure(.imageSourceUnavailable)
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(
            imageSource,
            0,
            nil
        ) as? [CFString: Any],
        let width = exactPositiveInteger(properties[kCGImagePropertyPixelWidth]),
        let height = exactPositiveInteger(properties[kCGImagePropertyPixelHeight]) else {
            return .failure(.metadataUnavailable)
        }
        let maximumSource = encodedPreservedChannelsMaximumSourceDimension
        guard width <= maximumSource, height <= maximumSource else {
            return .failure(.dimensionsOutOfRange(
                width: width,
                height: height,
                maximum: maximumSource
            ))
        }
        let orientation: Int
        if let rawOrientation = properties[kCGImagePropertyOrientation] {
            guard let value = exactPositiveInteger(rawOrientation) else {
                return .failure(.metadataUnavailable)
            }
            orientation = value
        } else {
            orientation = 1
        }
        guard orientation == 1 else {
            return .failure(.nonIdentityOrientation(orientation))
        }
        let decodeOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(imageSource, 0, decodeOptions) else {
            return .failure(.decodeUnavailable)
        }
        guard image.width == width, image.height == height else {
            return .failure(.decodedDimensionsMismatch(
                expectedWidth: width,
                expectedHeight: height,
                actualWidth: image.width,
                actualHeight: image.height
            ))
        }
        guard let source = sourceRGBA(image) else {
            return .failure(.unsupportedPixelLayout)
        }
        guard image.alphaInfo == .last || image.alphaInfo == .first
                || image.alphaInfo == .noneSkipLast
                || image.alphaInfo == .noneSkipFirst else {
            if source.premultiplied { return .failure(.premultipliedPixelLayout) }
            return .failure(.unsupportedPixelLayout)
        }
        guard !source.premultiplied else {
            return .failure(.premultipliedPixelLayout)
        }
        let maximum = encodedPreservedChannelsMaximumDimension
        let scale = min(1, Double(maximum) / Double(max(width, height)))
        let outputWidth = max(1, Int(Double(width) * scale))
        let outputHeight = max(1, Int(Double(height) * scale))
        let outputRGBA: Data
        if outputWidth == width, outputHeight == height {
            outputRGBA = source.data
        } else {
            outputRGBA = resampledStraightRGBA(
                source.data,
                sourceWidth: width,
                sourceHeight: height,
                destinationWidth: outputWidth,
                destinationHeight: outputHeight
            )
        }
        switch makeTexture(
            rgba: outputRGBA,
            width: outputWidth,
            height: outputHeight,
            mipmapGeneration: .fullChain,
            uploadCommandQueue: uploadCommandQueue,
            device: device
        ) {
        case let .success(texture):
            return .success(texture)
        case .failure(.allocation):
            return .failure(.textureAllocationFailed(
                width: outputWidth,
                height: outputHeight
            ))
        case let .failure(.mipmapGeneration(reason)):
            return .failure(.mipmapGenerationFailed(reason))
        }
    }

    /// Resamples straight RGBA lanes independently. Core Graphics image
    /// rasterization premultiplies translucent pixels, so it cannot preserve
    /// authored RGB where alpha is zero or fractional.
    private static func resampledStraightRGBA(
        _ source: Data,
        sourceWidth: Int,
        sourceHeight: Int,
        destinationWidth: Int,
        destinationHeight: Int
    ) -> Data {
        source.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            return resampledRGBA(sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                destinationWidth: destinationWidth, destinationHeight: destinationHeight) { x, y in
                let offset = (y * sourceWidth + x) * 4
                return SIMD4(Double(bytes[offset]), Double(bytes[offset + 1]),
                             Double(bytes[offset + 2]), Double(bytes[offset + 3]))
            }
        }
    }

    /// Filter source lanes directly into the bounded output. The reader can
    /// normalize a packed image without allocating a full-size RGBA copy.
    private static func resampledRGBA(
        sourceWidth: Int, sourceHeight: Int,
        destinationWidth: Int, destinationHeight: Int,
        pixel: (Int, Int) -> SIMD4<Double>
    ) -> Data {
        var destination = Data(count: destinationWidth * destinationHeight * 4)
        destination.withUnsafeMutableBytes { raw in
            let output = raw.bindMemory(to: UInt8.self)
            let xRatio = Double(sourceWidth) / Double(destinationWidth)
            let yRatio = Double(sourceHeight) / Double(destinationHeight)
            let exact = sourceWidth == destinationWidth && sourceHeight == destinationHeight
            for y in 0..<destinationHeight {
                let sy = max(0, min(Double(sourceHeight - 1), (Double(y) + 0.5) * yRatio - 0.5))
                let y0 = Int(sy), y1 = min(y0 + 1, sourceHeight - 1)
                for x in 0..<destinationWidth {
                    let value: SIMD4<Double>
                    if exact {
                        value = pixel(x, y)
                    } else {
                        let sx = max(0, min(Double(sourceWidth - 1), (Double(x) + 0.5) * xRatio - 0.5))
                        let x0 = Int(sx), x1 = min(x0 + 1, sourceWidth - 1)
                        let topLeft = pixel(x0, y0), bottomLeft = pixel(x0, y1)
                        let top = topLeft + (pixel(x1, y0) - topLeft) * (sx - Double(x0))
                        let bottom = bottomLeft + (pixel(x1, y1) - bottomLeft) * (sx - Double(x0))
                        value = top + (bottom - top) * (sy - Double(y0))
                    }
                    for c in 0..<4 {
                        output[(y * destinationWidth + x) * 4 + c] = UInt8(clamping: Int(value[c].rounded()))
                    }
                }
            }
        }
        return destination
    }

    static func upload(
        image: CGImage,
        purpose: SceneTextureLoadPurpose,
        maxDimension: Int,
        mipmapGeneration: MipmapGeneration = .fullChain,
        uploadCommandQueue: SceneTextureUploadCommandQueue = .init(),
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard image.width > 0, image.height > 0 else {
            return .decodeFailed("zero-sized image")
        }

        let scale = min(
            1,
            Double(maxDimension) / Double(max(image.width, image.height))
        )
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let rgba = rgbaData(
            image: image,
            width: width,
            height: height,
            purpose: purpose
        ) else {
            return .decodeFailed("CGImage RGBA rasterization failed (\(width)×\(height))")
        }

        switch makeTexture(
            rgba: rgba,
            width: width,
            height: height,
            mipmapGeneration: mipmapGeneration,
            uploadCommandQueue: uploadCommandQueue,
            device: device
        ) {
        case let .success(texture):
            return .loaded(texture)
        case .failure(.allocation):
            return .textureAllocationFailed(width: width, height: height)
        case let .failure(.mipmapGeneration(reason)):
            return .decodeFailed("GPU mipmap generation failed: \(reason)")
        }
    }

    private static func exactPositiveInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let signed = number.int64Value
        guard signed > 0,
              number.compare(NSNumber(value: signed)) == .orderedSame else {
            return nil
        }
        return Int(signed)
    }

    private static func makeTexture(
        rgba: Data,
        width: Int,
        height: Int,
        mipmapGeneration: MipmapGeneration,
        uploadCommandQueue: SceneTextureUploadCommandQueue,
        device: MTLDevice
    ) -> Result<MTLTexture, UploadFailure> {
        let (pixelCount, pixelCountOverflow) = width.multipliedReportingOverflow(
            by: height
        )
        let (byteCount, byteCountOverflow) = pixelCount.multipliedReportingOverflow(
            by: 4
        )
        guard supports2DExtent(width: width, height: height),
              !pixelCountOverflow,
              !byteCountOverflow,
              rgba.count == byteCount else {
            return .failure(.allocation)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: mipmapGeneration == .fullChain
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return .failure(.allocation)
        }
        rgba.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: width * 4
            )
        }
        guard texture.mipmapLevelCount > 1 else { return .success(texture) }
        // Direct images have no compiled TEX mip-chain authority, so build a
        // complete chain for the shared min/mag/mip sampler. A decoded TEX
        // fallback passes `.baseLevelOnly` when the compiled container has one
        // level and must remain one level after bounded normalization.
        guard let queue = uploadCommandQueue.commandQueue(for: device) else {
            return .failure(.mipmapGeneration("command queue unavailable"))
        }
        guard let commandBuffer = queue.makeCommandBuffer() else {
            return .failure(.mipmapGeneration("command buffer unavailable"))
        }
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            return .failure(.mipmapGeneration("blit encoder unavailable"))
        }
        encoder.generateMipmaps(for: texture)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            return .failure(.mipmapGeneration(
                commandBuffer.error?.localizedDescription ?? "GPU completion failed"
            ))
        }
        return .success(texture)
    }

    static func rgbaData(
        image: CGImage,
        width: Int,
        height: Int,
        purpose: SceneTextureLoadPurpose
    ) -> Data? {
        if purpose.preservesSourceChannels {
            if purpose == .straightAlbedo, imageHasNoAlpha(image) {
                // For an explicitly opaque source, straight and premultiplied
                // RGB are identical because alpha is exactly one. This makes
                // bounded raster/downscale safe without weakening data roles.
                return rasterizedRGBA(
                    image,
                    width: width,
                    height: height
                )
            }
            let needsResize = width != image.width || height != image.height
            guard !needsResize || (purpose == .straightAlbedo
                && width > 0 && height > 0 && width <= image.width && height <= image.height),
                image.alphaInfo != .premultipliedFirst,
                image.alphaInfo != .premultipliedLast else { return nil }
            // Packed source channels are read directly into the output. This
            // preserves transparent RGB without an unpremultiply fallback or a
            // full-size intermediate allocation when a large image is reduced.
            return sourceRGBA(image, width: width, height: height,
                              colorConversion: purpose == .straightAlbedo)?.data
        }
        return rasterizedRGBA(
            image,
            width: width,
            height: height
        )
    }

    static func imageHasNoAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst:
            true
        case .premultipliedLast, .premultipliedFirst, .last, .first, .alphaOnly:
            false
        @unknown default:
            false
        }
    }

    private static func sourceRGBA(
        _ image: CGImage, width: Int? = nil, height: Int? = nil,
        colorConversion: Bool = false
    ) -> (data: Data, premultiplied: Bool)? {
        let rgb = image.colorSpace?.model == .rgb
        let gray = image.colorSpace?.model == .monochrome
        let bits = image.bitsPerComponent
        let channels = rgb ? 4 : 2
        let bytesPerPixel = channels * (bits / 8)
        let outputWidth = width ?? image.width, outputHeight = height ?? image.height
        let rowBytes = image.width.multipliedReportingOverflow(by: bytesPerPixel)
        let sourceBytes = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        let outputPixels = outputWidth.multipliedReportingOverflow(by: outputHeight)
        guard image.width > 0, image.height > 0, outputWidth > 0, outputHeight > 0,
              !rowBytes.overflow, !sourceBytes.overflow, !outputPixels.overflow,
              !outputPixels.partialValue.multipliedReportingOverflow(by: 4).overflow,
              (rgb && bits == 8 || colorConversion && (rgb || gray) && (bits == 8 || bits == 16)),
              image.bitsPerPixel == channels * bits,
              image.bytesPerRow >= rowBytes.partialValue,
              image.pixelFormatInfo == .packed, image.decode == nil,
              !image.bitmapInfo.contains(.floatComponents) else { return nil }
        let alpha = image.alphaInfo
        let first = alpha == .first || alpha == .premultipliedFirst || alpha == .noneSkipFirst
        let last = alpha == .last || alpha == .premultipliedLast || alpha == .noneSkipLast
        guard first || last else { return nil }
        let order = image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
        let little: Bool
        switch order {
        case CGBitmapInfo.byteOrderDefault.rawValue:
            little = false
        case CGBitmapInfo.byteOrder32Big.rawValue where bits == 8 && rgb,
             CGBitmapInfo.byteOrder16Big.rawValue where bits == 16 || gray:
            little = false
        case CGBitmapInfo.byteOrder32Little.rawValue where bits == 8 && rgb,
             CGBitmapInfo.byteOrder16Little.rawValue where bits == 16 || gray:
            little = true
        default: return nil
        }
        guard image.bitmapInfo.rawValue == alpha.rawValue | order,
              let provider = image.dataProvider?.data,
              CFDataGetLength(provider) >= sourceBytes.partialValue,
              let bytes = CFDataGetBytePtr(provider) else { return nil }
        let data = withExtendedLifetime(provider) {
            resampledRGBA(sourceWidth: image.width, sourceHeight: image.height,
                          destinationWidth: outputWidth, destinationHeight: outputHeight) { x, y in
                let pixel = bytes + y * image.bytesPerRow + x * bytesPerPixel
                func channel(_ index: Int) -> Double {
                    if bits == 8 { return Double(pixel[little ? channels - 1 - index : index]) }
                    let a = UInt16(pixel[index * 2]), b = UInt16(pixel[index * 2 + 1])
                    return Double(little ? a | (b << 8) : (a << 8) | b) / 257
                }
                let colorIndex = first ? 1 : 0
                let alphaValue = alpha == .noneSkipFirst || alpha == .noneSkipLast
                    ? 255 : channel(first ? 0 : channels - 1)
                let red = channel(colorIndex)
                return SIMD4(red, gray ? red : channel(colorIndex + 1),
                             gray ? red : channel(colorIndex + 2), alphaValue)
            }
        }
        return (data, alpha == .premultipliedLast || alpha == .premultipliedFirst)
    }

    private static func rasterizedRGBA(
        _ image: CGImage,
        width: Int,
        height: Int
    ) -> Data? {
        let bytesPerRow = width * 4
        var data = Data(count: bytesPerRow * height)
        let rendered = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let address = buffer.baseAddress,
                  let context = CGContext(
                    data: address,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return rendered ? data : nil
    }

}
