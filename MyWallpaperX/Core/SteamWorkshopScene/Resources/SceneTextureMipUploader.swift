import CoreGraphics
import Foundation
import ImageIO
import Metal

enum SceneTextureMipUploader {
    static func uploadEmbeddedImages(
        _ mips: [SceneTexContainer.Mip],
        device: MTLDevice
    ) -> SceneTextureLoadOutcome? {
        let images = mips.compactMap { mip -> CGImage? in
            guard isEmbeddedImage(mip.data),
                  let source = CGImageSourceCreateWithData(mip.data as CFData, nil) else {
                return nil
            }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard images.count == mips.count,
              let first = images.first,
              first.width <= 4096,
              first.height <= 4096,
              validDimensions(images.map { ($0.width, $0.height) }) else {
            return nil
        }
        let descriptor = descriptor(
            pixelFormat: .rgba8Unorm,
            width: first.width,
            height: first.height,
            levelCount: images.count
        )
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return .textureAllocationFailed(width: first.width, height: first.height)
        }
        for (level, image) in images.enumerated() {
            guard let rgba = rasterizedRGBA(image) else {
                return .decodeFailed("embedded image mip rasterization failed")
            }
            replace(texture: texture, level: level, width: image.width, height: image.height,
                    bytesPerRow: image.width * 4, data: rgba)
        }
        return .loaded(texture)
    }

    static func uploadEmbeddedDataImages(
        _ mips: [SceneTexContainer.Mip],
        device: MTLDevice
    ) -> SceneTextureLoadOutcome? {
        let images = mips.compactMap { mip -> CGImage? in
            guard isEmbeddedImage(mip.data),
                  let source = CGImageSourceCreateWithData(mip.data as CFData, nil) else {
                return nil
            }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard images.count == mips.count,
              let first = images.first,
              first.width <= 4096,
              first.height <= 4096,
              validDimensions(images.map { ($0.width, $0.height) }) else {
            return nil
        }
        let descriptor = descriptor(
            pixelFormat: .rgba8Unorm,
            width: first.width,
            height: first.height,
            levelCount: images.count
        )
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return .textureAllocationFailed(width: first.width, height: first.height)
        }
        for (level, image) in images.enumerated() {
            guard let rgba = rasterizedRGBA(image) else {
                return .decodeFailed("embedded data image mip rasterization failed")
            }
            let data = unpremultipliedRGBA(rgba)
            replace(
                texture: texture,
                level: level,
                width: image.width,
                height: image.height,
                bytesPerRow: image.width * 4,
                data: data
            )
        }
        return .loaded(texture)
    }

    static func uploadRaw(
        container: SceneTexContainer,
        pixelFormat: MTLPixelFormat,
        bytesPerPixel: Int,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        uploadRaw(
            container: container,
            pixelFormat: pixelFormat,
            bytesPerPixel: bytesPerPixel,
            premultiply: false,
            device: device
        )
    }

    static func uploadRawRGBA(
        container: SceneTexContainer,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let first = container.mips.first else {
            return .decodeFailed("TEX container has no mip data")
        }
        guard !isMP4(first.data) else { return .texContainsVideoPayload }
        return uploadRaw(
            container: container,
            pixelFormat: .rgba8Unorm,
            bytesPerPixel: 4,
            premultiply: true,
            device: device
        )
    }

    private static func uploadRaw(
        container: SceneTexContainer,
        pixelFormat: MTLPixelFormat,
        bytesPerPixel: Int,
        premultiply: Bool,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let first = container.mips.first,
              validDimensions(container.mips.map { ($0.width, $0.height) }) else {
            return .decodeFailed("TEX container has an invalid mip chain")
        }
        let textureDescriptor = descriptor(
            pixelFormat: pixelFormat,
            width: first.width,
            height: first.height,
            levelCount: container.mips.count
        )
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            return .textureAllocationFailed(width: first.width, height: first.height)
        }
        for (level, mip) in container.mips.enumerated() {
            let bytesPerRow = mip.width * bytesPerPixel
            let expected = bytesPerRow * mip.height
            guard mip.data.count == expected else {
                let label = premultiply ? "raw ARGB8888" : "raw"
                return .decodeFailed("\(label) mip data size mismatch: \(mip.data.count) != \(expected)")
            }
            let data = premultiply ? premultipliedRGBA(mip.data) : mip.data
            replace(texture: texture, level: level, width: mip.width, height: mip.height,
                    bytesPerRow: bytesPerRow, data: data)
        }
        return .loaded(texture)
    }

    private static func descriptor(
        pixelFormat: MTLPixelFormat,
        width: Int,
        height: Int,
        levelCount: Int
    ) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.mipmapLevelCount = levelCount
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        return descriptor
    }

    private static func replace(
        texture: MTLTexture,
        level: Int,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        data: Data
    ) {
        data.withUnsafeBytes { buffer in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: level,
                withBytes: buffer.baseAddress!,
                bytesPerRow: bytesPerRow
            )
        }
    }

    private static func validDimensions(_ dimensions: [(Int, Int)]) -> Bool {
        guard let first = dimensions.first, first.0 > 0, first.1 > 0 else { return false }
        return dimensions.enumerated().allSatisfy { level, size in
            size.0 == max(1, first.0 >> level) && size.1 == max(1, first.1 >> level)
        }
    }

    private static func isEmbeddedImage(_ data: Data) -> Bool {
        data.starts(with: Data([0x89, 0x50, 0x4E, 0x47]))
            || data.starts(with: Data([0xFF, 0xD8, 0xFF]))
    }

    private static func isMP4(_ data: Data) -> Bool {
        data.count >= 12 && data[4...7].elementsEqual(Data("ftyp".utf8))
    }

    private static func rasterizedRGBA(_ image: CGImage) -> Data? {
        let bytesPerRow = image.width * 4
        var data = Data(count: bytesPerRow * image.height)
        let rendered = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let address = buffer.baseAddress,
                  let context = CGContext(
                    data: address,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return rendered ? data : nil
    }

    private static func premultipliedRGBA(_ data: Data) -> Data {
        var output = data
        output.withUnsafeMutableBytes { raw in
            guard let bytes = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            var offset = 0
            while offset + 3 < raw.count {
                let alpha = UInt16(bytes[offset + 3])
                bytes[offset] = UInt8((UInt16(bytes[offset]) * alpha + 127) / 255)
                bytes[offset + 1] = UInt8((UInt16(bytes[offset + 1]) * alpha + 127) / 255)
                bytes[offset + 2] = UInt8((UInt16(bytes[offset + 2]) * alpha + 127) / 255)
                offset += 4
            }
        }
        return output
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
