import CoreGraphics
import Foundation
import Metal

enum SceneTextureLoadPurpose: Hashable {
    case premultipliedColor
    case preservedChannels
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
        if purpose == .preservedChannels,
           width == image.width,
           height == image.height,
           let source = sourceRGBA(image) {
            return source.premultiplied
                ? unpremultipliedRGBA(source.data)
                : source.data
        }
        guard let rasterized = rasterizedRGBA(
            image,
            width: width,
            height: height
        ) else {
            return nil
        }
        return purpose == .premultipliedColor
            ? rasterized
            : unpremultipliedRGBA(rasterized)
    }

    private static func sourceRGBA(
        _ image: CGImage
    ) -> (data: Data, premultiplied: Bool)? {
        guard image.bitsPerComponent == 8,
              image.bitsPerPixel == 32,
              image.bytesPerRow >= image.width * 4,
              image.colorSpace?.model == .rgb,
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
        let littleEndian = order == CGBitmapInfo.byteOrder32Little.rawValue
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

    private static func unpremultipliedRGBA(_ data: Data) -> Data {
        var output = data
        output.withUnsafeMutableBytes { raw in
            guard let bytes = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            var offset = 0
            while offset + 3 < raw.count {
                let alpha = UInt16(bytes[offset + 3])
                if alpha > 0 {
                    bytes[offset] = UInt8(min(255, (UInt16(bytes[offset]) * 255) / alpha))
                    bytes[offset + 1] = UInt8(
                        min(255, (UInt16(bytes[offset + 1]) * 255) / alpha)
                    )
                    bytes[offset + 2] = UInt8(
                        min(255, (UInt16(bytes[offset + 2]) * 255) / alpha)
                    )
                }
                offset += 4
            }
        }
        return output
    }
}
