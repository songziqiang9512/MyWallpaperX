import CoreGraphics
import Foundation
import ImageIO
import Metal

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
    enum MipmapGeneration {
        case fullChain
        case baseLevelOnly
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
    }

    static let encodedPreservedChannelsMaximumDimension = 256
    private static let encodedPreservedChannelsMaximumSourceDimension = 4_096

    /// Decodes a bounded encoded source directly into a channel-preserving
    /// texture. This path never consumes an existing color texture because a
    /// premultiplied texture cannot recover source RGB at zero/fractional alpha.
    static func uploadEncodedPreservedChannels(
        _ encodedSource: Data,
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
        guard let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
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
        guard let texture = makeTexture(
            rgba: outputRGBA,
            width: outputWidth,
            height: outputHeight,
            mipmapGeneration: .fullChain,
            device: device
        ) else {
            return .failure(.textureAllocationFailed(
                width: outputWidth,
                height: outputHeight
            ))
        }
        return .success(texture)
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
        var destination = Data(count: destinationWidth * destinationHeight * 4)
        destination.withUnsafeMutableBytes { destinationRaw in
            source.withUnsafeBytes { sourceRaw in
                guard let output = destinationRaw.bindMemory(to: UInt8.self).baseAddress,
                      let input = sourceRaw.bindMemory(to: UInt8.self).baseAddress else {
                    return
                }
                let xRatio = Double(sourceWidth) / Double(destinationWidth)
                let yRatio = Double(sourceHeight) / Double(destinationHeight)
                for destinationY in 0 ..< destinationHeight {
                    let sourceY = max(
                        0,
                        min(
                            Double(sourceHeight - 1),
                            (Double(destinationY) + 0.5) * yRatio - 0.5
                        )
                    )
                    let y0 = Int(sourceY.rounded(.down))
                    let y1 = min(y0 + 1, sourceHeight - 1)
                    let yWeight = sourceY - Double(y0)
                    for destinationX in 0 ..< destinationWidth {
                        let sourceX = max(
                            0,
                            min(
                                Double(sourceWidth - 1),
                                (Double(destinationX) + 0.5) * xRatio - 0.5
                            )
                        )
                        let x0 = Int(sourceX.rounded(.down))
                        let x1 = min(x0 + 1, sourceWidth - 1)
                        let xWeight = sourceX - Double(x0)
                        let destinationOffset = (
                            destinationY * destinationWidth + destinationX
                        ) * 4
                        for component in 0 ..< 4 {
                            let topLeft = Double(input[(y0 * sourceWidth + x0) * 4 + component])
                            let topRight = Double(input[(y0 * sourceWidth + x1) * 4 + component])
                            let bottomLeft = Double(input[(y1 * sourceWidth + x0) * 4 + component])
                            let bottomRight = Double(input[(y1 * sourceWidth + x1) * 4 + component])
                            let top = topLeft + (topRight - topLeft) * xWeight
                            let bottom = bottomLeft + (bottomRight - bottomLeft) * xWeight
                            output[destinationOffset + component] = UInt8(
                                max(0, min(255, (top + (bottom - top) * yWeight).rounded()))
                            )
                        }
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

        guard let texture = makeTexture(
            rgba: rgba,
            width: width,
            height: height,
            mipmapGeneration: mipmapGeneration,
            device: device
        ) else {
            return .textureAllocationFailed(width: width, height: height)
        }
        return .loaded(texture)
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
        device: MTLDevice
    ) -> MTLTexture? {
        let (pixelCount, pixelCountOverflow) = width.multipliedReportingOverflow(
            by: height
        )
        let (byteCount, byteCountOverflow) = pixelCount.multipliedReportingOverflow(
            by: 4
        )
        guard width > 0,
              height > 0,
              !pixelCountOverflow,
              !byteCountOverflow,
              rgba.count == byteCount else {
            return nil
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
            return nil
        }
        rgba.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: width * 4
            )
        }
        guard mipmapGeneration == .fullChain else { return texture }
        // Direct images have no compiled TEX mip-chain authority, so build a
        // complete chain for the shared min/mag/mip sampler. A decoded TEX
        // fallback passes `.baseLevelOnly` when the compiled container has one
        // level and must remain one level after bounded normalization.
        guard let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeBlitCommandEncoder()
        else {
            return texture
        }
        encoder.generateMipmaps(for: texture)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return texture
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
            // Straight/data consumers cannot safely reconstruct source
            // channels from a premultiplied representation: RGB at alpha zero
            // is already irrecoverable and fractional alpha loses precision.
            // Raster fallback also creates that representation. Refuse either
            // case instead of silently rewriting data.
            guard width == image.width,
                  height == image.height,
                  let source = sourceRGBA(image),
                  !source.premultiplied else {
                return nil
            }
            return source.data
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
        _ image: CGImage
    ) -> (data: Data, premultiplied: Bool)? {
        guard image.bitsPerComponent == 8,
              image.bitsPerPixel == 32,
              image.bytesPerRow >= image.width * 4,
              image.colorSpace?.model == .rgb,
              image.pixelFormatInfo == .packed,
              image.decode == nil,
              !image.bitmapInfo.contains(.floatComponents),
              let providerData = image.dataProvider?.data else {
            return nil
        }
        let alphaInfo = image.alphaInfo
        let supportedAlpha: Set<CGImageAlphaInfo> = [
            .last, .premultipliedLast, .first, .premultipliedFirst,
            .noneSkipLast, .noneSkipFirst,
        ]
        guard supportedAlpha.contains(alphaInfo) else { return nil }

        let source = providerData as Data
        guard source.count >= image.bytesPerRow * image.height else { return nil }
        let order = image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
        let littleEndian: Bool
        switch order {
        case CGBitmapInfo.byteOrderDefault.rawValue,
             CGBitmapInfo.byteOrder32Big.rawValue:
            littleEndian = false
        case CGBitmapInfo.byteOrder32Little.rawValue:
            littleEndian = true
        default:
            return nil
        }
        guard image.bitmapInfo.rawValue == alphaInfo.rawValue | order else {
            return nil
        }
        var output = Data(count: image.width * image.height * 4)
        output.withUnsafeMutableBytes { outputRaw in
            source.withUnsafeBytes { sourceRaw in
                guard let destination = outputRaw.bindMemory(to: UInt8.self).baseAddress,
                      let bytes = sourceRaw.bindMemory(to: UInt8.self).baseAddress else {
                    return
                }
                for row in 0 ..< image.height {
                    for column in 0 ..< image.width {
                        let sourceOffset = row * image.bytesPerRow + column * 4
                        let destinationOffset = (row * image.width + column) * 4
                        let pixel = rgba(
                            bytes: bytes + sourceOffset,
                            alphaInfo: alphaInfo,
                            littleEndian: littleEndian
                        )
                        destination[destinationOffset] = pixel.0
                        destination[destinationOffset + 1] = pixel.1
                        destination[destinationOffset + 2] = pixel.2
                        destination[destinationOffset + 3] = pixel.3
                    }
                }
            }
        }
        return (
            output,
            alphaInfo == .premultipliedLast || alphaInfo == .premultipliedFirst
        )
    }

    private static func rgba(
        bytes: UnsafePointer<UInt8>,
        alphaInfo: CGImageAlphaInfo,
        littleEndian: Bool
    ) -> (UInt8, UInt8, UInt8, UInt8) {
        switch (alphaInfo, littleEndian) {
        case (.last, false), (.premultipliedLast, false):
            return (bytes[0], bytes[1], bytes[2], bytes[3])
        case (.last, true), (.premultipliedLast, true):
            return (bytes[3], bytes[2], bytes[1], bytes[0])
        case (.first, false), (.premultipliedFirst, false):
            return (bytes[1], bytes[2], bytes[3], bytes[0])
        case (.first, true), (.premultipliedFirst, true):
            return (bytes[2], bytes[1], bytes[0], bytes[3])
        case (.noneSkipLast, false):
            return (bytes[0], bytes[1], bytes[2], 255)
        case (.noneSkipLast, true):
            return (bytes[3], bytes[2], bytes[1], 255)
        case (.noneSkipFirst, false):
            return (bytes[1], bytes[2], bytes[3], 255)
        case (.noneSkipFirst, true):
            return (bytes[2], bytes[1], bytes[0], 255)
        default:
            return (0, 0, 0, 0)
        }
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
