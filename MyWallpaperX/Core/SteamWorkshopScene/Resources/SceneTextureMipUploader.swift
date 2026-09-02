import CoreGraphics
import Foundation
import ImageIO
import Metal

enum SceneTextureMipUploader {
    static func uploadVolume(
        container: SceneTexContainer,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard container.isVolume else {
            return .decodeFailed("lookup-table consumer requires a 3D TEX")
        }
        guard purpose.requiresVolumeTexture else {
            return .decodeFailed("3D TEX requires a lookup-table consumer")
        }
        return uploadEmbeddedRGBAVolume(container: container, device: device)
    }

    static func uploadEmbeddedRGBAVolume(
        container: SceneTexContainer,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard container.isVolume,
              container.format == 0,
              container.imageCount == 1,
              !container.isAnimated,
              container.spriteFrames.isEmpty,
              container.mips.count == 1,
              let mip = container.mips.first,
              mip.depth == container.textureDepth,
              isEmbeddedImage(mip.data),
              let source = CGImageSourceCreateWithData(mip.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == mip.width,
              image.height == mip.height * mip.depth,
              let rgba = SceneImageTextureUploader.rgbaData(
                  image: image,
                  width: image.width,
                  height: image.height,
                  purpose: .lookupTable
              ) else {
            return .decodeFailed("3D TEX requires one vertical RGBA slice atlas")
        }
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.width = mip.width
        descriptor.height = mip.height
        descriptor.depth = mip.depth
        descriptor.mipmapLevelCount = 1
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return .textureAllocationFailed(width: mip.width, height: mip.height)
        }
        rgba.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, mip.width, mip.height, mip.depth),
                mipmapLevel: 0,
                slice: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: mip.width * 4,
                bytesPerImage: mip.width * mip.height * 4
            )
        }
        return .loaded(texture)
    }

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
        purpose: SceneTextureLoadPurpose,
        maximumDimension: Int = 4096,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome? {
        guard purpose.preservesSourceChannels,
              maximumDimension > 0 else { return nil }
        let images = mips.compactMap { mip -> CGImage? in
            guard isEmbeddedImage(mip.data),
                  let source = CGImageSourceCreateWithData(mip.data as CFData, nil) else {
                return nil
            }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard images.count == mips.count,
              validDimensions(images.map { ($0.width, $0.height) }) else {
            return nil
        }
        let firstEligibleIndex: Int
        if let first = images.first,
           first.width <= maximumDimension,
           first.height <= maximumDimension {
            firstEligibleIndex = 0
        } else if purpose == .straightAlbedo,
                  let index = images.firstIndex(where: {
                      $0.width <= maximumDimension
                          && $0.height <= maximumDimension
                  }) {
            // A complete authored mip is already a channel-preserving,
            // filtered representation. Starting the resident chain there
            // avoids an unsafe premultiplied resize of straight-alpha albedo.
            firstEligibleIndex = index
        } else {
            return nil
        }
        let selectedImages = Array(images[firstEligibleIndex...])
        guard let first = selectedImages.first else { return nil }
        let descriptor = descriptor(
            pixelFormat: .rgba8Unorm,
            width: first.width,
            height: first.height,
            levelCount: selectedImages.count
        )
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return .textureAllocationFailed(width: first.width, height: first.height)
        }
        for (level, image) in selectedImages.enumerated() {
            guard let data = SceneImageTextureUploader.rgbaData(
                image: image,
                width: image.width,
                height: image.height,
                purpose: purpose
            ) else {
                return .decodeFailed("embedded data image mip rasterization failed")
            }
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
        let mips = croppedStaticRawMips(container: container, bytesPerPixel: 4)
        return uploadRaw(
            container: container,
            mips: mips,
            pixelFormat: .rgba8Unorm,
            bytesPerPixel: 4,
            premultiply: true,
            device: device
        )
    }

    private static func uploadRaw(
        container: SceneTexContainer,
        mips: [SceneTexContainer.Mip]? = nil,
        pixelFormat: MTLPixelFormat,
        bytesPerPixel: Int,
        premultiply: Bool,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        let uploadMips = mips ?? container.mips
        guard let first = uploadMips.first,
              validDimensions(uploadMips.map { ($0.width, $0.height) }) else {
            return .decodeFailed("TEX container has an invalid mip chain")
        }
        let textureDescriptor = descriptor(
            pixelFormat: pixelFormat,
            width: first.width,
            height: first.height,
            levelCount: uploadMips.count
        )
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            return .textureAllocationFailed(width: first.width, height: first.height)
        }
        for (level, mip) in uploadMips.enumerated() {
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

    private static func croppedStaticRawMips(
        container: SceneTexContainer,
        bytesPerPixel: Int
    ) -> [SceneTexContainer.Mip] {
        guard container.imageCount == 1,
              !container.isAnimated,
              container.imageWidth > 0,
              container.imageHeight > 0 else {
            return container.mips
        }
        let dimensions = container.mips.enumerated().map { level, mip in
            let targetWidth = max(1, container.imageWidth >> level)
            let targetHeight = max(1, container.imageHeight >> level)
            return (targetWidth, targetHeight, mip)
        }
        guard dimensions.allSatisfy({ targetWidth, targetHeight, mip in
            targetWidth <= mip.width
                && targetHeight <= mip.height
                && mip.data.count == mip.width * mip.height * bytesPerPixel
        }), dimensions.contains(where: { targetWidth, targetHeight, mip in
            targetWidth != mip.width || targetHeight != mip.height
        }) else {
            return container.mips
        }
        return dimensions.map { targetWidth, targetHeight, mip in
            let sourceBytesPerRow = mip.width * bytesPerPixel
            let targetBytesPerRow = targetWidth * bytesPerPixel
            var cropped = Data(capacity: targetBytesPerRow * targetHeight)
            for row in 0 ..< targetHeight {
                let start = row * sourceBytesPerRow
                cropped.append(mip.data[start ..< (start + targetBytesPerRow)])
            }
            return .init(width: targetWidth, height: targetHeight, data: cropped)
        }
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

}
