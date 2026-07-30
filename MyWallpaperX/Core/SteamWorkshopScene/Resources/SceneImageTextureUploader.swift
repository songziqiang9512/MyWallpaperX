import CoreGraphics
import Foundation
import Metal

enum SceneTextureLoadPurpose: Hashable {
    case premultipliedColor
    case straightAlbedo
    case preservedChannels
    case mask
    case noise
    case flow
    case phase
    case normal
    case depth

    var preservesSourceChannels: Bool {
        switch self {
        case .premultipliedColor:
            false
        case .straightAlbedo, .preservedChannels, .mask, .noise, .flow, .phase,
             .normal, .depth:
            true
        }
    }
}

enum SceneImageTextureUploader {
    static func upload(
        image: CGImage,
        purpose: SceneTextureLoadPurpose,
        maxDimension: Int,
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
        rgba.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: width * 4
            )
        }
        return .loaded(texture)
    }

    static func rgbaData(
        image: CGImage,
        width: Int,
        height: Int,
        purpose: SceneTextureLoadPurpose
    ) -> Data? {
        if purpose.preservesSourceChannels {
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
