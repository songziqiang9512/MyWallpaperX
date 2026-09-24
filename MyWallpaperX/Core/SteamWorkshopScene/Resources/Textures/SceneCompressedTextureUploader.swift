import Foundation
import Metal
import MetalPerformanceShaders

struct SceneCompressedTextureUploader {
    // CPU decode budget: a decoded RGBA copy of one 4096x4096 mip is 64 MiB.
    // Larger payloads and multi-image sprites first keep their compact native
    // upload, then use the GPU to premultiply into the authored image or a
    // supported static first-frame region. This avoids a full CPU RGBA copy;
    // the observed 7680x7560 five-image firework sheet normalizes to its
    // 1920x1080 first frame instead of retaining a 221 MiB decoded atlas.
    private static let maxDecodedPixelCount = 4096 * 4096

    static func upload(
        container: SceneTexContainer,
        pixelFormat: MTLPixelFormat,
        purpose: SceneTextureLoadPurpose,
        uploadCommandQueue: SceneTextureUploadCommandQueue = .init(),
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let firstMip = container.mips.first,
              firstMip.width > 0, firstMip.height > 0 else {
            return .decodeFailed("TEX container has no mip data")
        }
        // BC1/BC2/BC3 storage does not identify the consumer's channel
        // semantics. Small single images decode on CPU for either purpose;
        // only color consumers premultiply straight alpha before compositing.
        if let bcFormat = SceneBCTextureDecoder.Format(texFormat: container.format) {
            if container.imageCount == 1,
               firstMip.width <= maxDecodedPixelCount / firstMip.height {
                return uploadDecoded(
                    container: container,
                    format: bcFormat,
                    purpose: purpose,
                    device: device
                )
            }
            guard !purpose.preservesSourceChannels else {
                return uploadDirect(
                    mips: container.imageCount == 1 ? container.mips : [firstMip],
                    pixelFormat: pixelFormat,
                    device: device
                )
            }
            return uploadNormalizedColor(
                container: container,
                mip: firstMip,
                pixelFormat: pixelFormat,
                uploadCommandQueue: uploadCommandQueue,
                device: device
            )
        }
        return uploadDirect(
            mips: container.imageCount == 1 ? container.mips : [firstMip],
            pixelFormat: pixelFormat,
            device: device
        )
    }

    static func uploadNativeImage(
        _ image: SceneTexContainer.Image,
        pixelFormat: MTLPixelFormat,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let firstMip = image.mips.first else {
            return .decodeFailed("TEX image has no mip data")
        }
        return uploadDirect(
            mips: [firstMip],
            pixelFormat: pixelFormat,
            device: device
        )
    }

    private static func uploadDecoded(
        container: SceneTexContainer,
        format: SceneBCTextureDecoder.Format,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard SceneTexContainer.valid2DMipDimensions(
            container.mips.map { ($0.width, $0.height) }
        ) else {
            return .decodeFailed("TEX container has an invalid mip chain")
        }
        let levelCount = purpose.preservesSourceChannels
            ? container.mips.count
            : SceneTexContainer.maximum2DMipCount(
                width: container.imageWidth, height: container.imageHeight
            )
        let decoded = container.mips.enumerated().compactMap { level, mip in
            let imageWidth = purpose.preservesSourceChannels
                ? mip.width
                : max(1, container.imageWidth >> level)
            let imageHeight = purpose.preservesSourceChannels
                ? mip.height
                : max(1, container.imageHeight >> level)
            return SceneBCTextureDecoder.decode(
                blockData: mip.data,
                storedWidth: mip.width,
                storedHeight: mip.height,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                format: format
            )
        }
        // Validate every stored payload before dropping redundant cropped levels.
        let selectedImages = decoded.prefix(levelCount)
        guard decoded.count == container.mips.count,
              let first = selectedImages.first,
              SceneTexContainer.valid2DMipDimensions(selectedImages.map { ($0.width, $0.height) }) else {
            return .decodeFailed("BC mip data does not match its stored block layout")
        }
        guard SceneImageTextureUploader.supports2DExtent(width: first.width, height: first.height) else {
            return .decodeFailed("decoded BC mip extent exceeds Metal 2D limits")
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: first.width,
            height: first.height,
            mipmapped: false
        )
        descriptor.mipmapLevelCount = selectedImages.count
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return .textureAllocationFailed(width: first.width, height: first.height)
        }

        for (level, image) in selectedImages.enumerated() {
            let rgba = purpose.preservesSourceChannels
                ? image.rgba
                : premultiplyStraightAlphaRGBA(image.rgba)
            rgba.withUnsafeBytes { rawBuffer in
                texture.replace(
                    region: MTLRegionMake2D(0, 0, image.width, image.height),
                    mipmapLevel: level,
                    withBytes: rawBuffer.baseAddress!,
                    bytesPerRow: image.width * 4
                )
            }
        }
        return .loaded(texture)
    }

    private struct NormalizationRegion {
        let sourceX: Int
        let sourceY: Int
        let width: Int
        let height: Int
    }

    private static func uploadNormalizedColor(
        container: SceneTexContainer,
        mip: SceneTexContainer.Mip,
        pixelFormat: MTLPixelFormat,
        uploadCommandQueue: SceneTextureUploadCommandQueue,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let region = normalizationRegion(container: container, mip: mip) else {
            return .decodeFailed("multi-image BC sprite has no supported static first-frame region")
        }
        let direct = uploadDirect(
            mips: container.imageCount == 1 ? container.mips : [mip],
            pixelFormat: pixelFormat,
            device: device
        )
        guard case let .loaded(source) = direct else { return direct }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: region.width,
            height: region.height,
            mipmapped: false
        )
        descriptor.mipmapLevelCount = min(
            source.mipmapLevelCount,
            SceneTexContainer.maximum2DMipCount(width: region.width, height: region.height)
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let destination = device.makeTexture(descriptor: descriptor),
              let commandQueue = uploadCommandQueue.commandQueue(for: device),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return .textureAllocationFailed(width: region.width, height: region.height)
        }

        let conversion = MPSImageConversion(
            device: device,
            srcAlpha: .nonPremultiplied,
            destAlpha: .premultiplied,
            backgroundColor: nil,
            conversionInfo: nil
        )
        // Each authored mip is an independent image, not a downsample of the
        // converted base. Views expose that exact level to MPS without copies.
        for level in 0..<destination.mipmapLevelCount {
            guard let sourceLevel = source.makeTextureView(
                pixelFormat: source.pixelFormat, textureType: .type2D,
                levels: level..<(level + 1), slices: 0..<1
            ), let destinationLevel = destination.makeTextureView(
                pixelFormat: destination.pixelFormat, textureType: .type2D,
                levels: level..<(level + 1), slices: 0..<1
            ) else {
                return .decodeFailed("GPU BC mip view creation failed at level \(level)")
            }
            conversion.offset = MPSOffset(
                x: region.sourceX >> level, y: region.sourceY >> level, z: 0
            )
            conversion.clipRect = MTLRegionMake2D(
                0, 0, destinationLevel.width, destinationLevel.height
            )
            conversion.encode(
                commandBuffer: commandBuffer,
                sourceTexture: sourceLevel,
                destinationTexture: destinationLevel
            )
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            return .decodeFailed("GPU BC premultiply failed: \(commandBuffer.error?.localizedDescription ?? "unknown error")")
        }
        return .loaded(destination)
    }

    private static func normalizationRegion(
        container: SceneTexContainer,
        mip: SceneTexContainer.Mip
    ) -> NormalizationRegion? {
        guard mip.width > 0, mip.height > 0 else { return nil }
        let crossesImages = container.spriteFrames.contains { $0.imageIndex != 0 }
        guard crossesImages else {
            let width = (1 ... mip.width).contains(container.imageWidth)
                ? container.imageWidth
                : mip.width
            let height = (1 ... mip.height).contains(container.imageHeight)
                ? container.imageHeight
                : mip.height
            return NormalizationRegion(sourceX: 0, sourceY: 0, width: width, height: height)
        }

        guard let frame = container.spriteFrames.first,
              frame.imageIndex == 0,
              abs(frame.xAxis.y) < 0.000_001,
              abs(frame.yAxis.x) < 0.000_001,
              frame.xAxis.x > 0,
              frame.yAxis.y > 0 else {
            return nil
        }
        guard let sourceX = Int(exactly: (frame.origin.x * Float(mip.width)).rounded()),
              let sourceY = Int(exactly: (frame.origin.y * Float(mip.height)).rounded()),
              let width = Int(exactly: (frame.xAxis.x * Float(mip.width)).rounded()),
              let height = Int(exactly: (frame.yAxis.y * Float(mip.height)).rounded()),
              sourceX >= 0, sourceY >= 0, width > 0, height > 0,
              width <= mip.width, height <= mip.height,
              sourceX <= mip.width - width,
              sourceY <= mip.height - height else {
            return nil
        }
        return NormalizationRegion(
            sourceX: sourceX,
            sourceY: sourceY,
            width: width,
            height: height
        )
    }

    // Large preserved-channel payloads and formats without a CPU decoder keep
    // their native block upload.
    private static func uploadDirect(
        mips: [SceneTexContainer.Mip],
        pixelFormat: MTLPixelFormat,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let firstMip = mips.first,
              SceneTexContainer.valid2DMipDimensions(mips.map { ($0.width, $0.height) }) else {
            return .decodeFailed("TEX container has an invalid mip chain")
        }
        guard let bytesPerBlock = bytesPerBlock(for: pixelFormat) else {
            return .decodeFailed("unsupported Metal BC pixel format: \(pixelFormat.rawValue)")
        }
        guard SceneImageTextureUploader.supports2DExtent(width: firstMip.width, height: firstMip.height) else {
            return .decodeFailed("BC mip extent exceeds Metal 2D limits")
        }
        if device.supportsBCTextureCompression == false {
            return .decodeFailed("BC upload requires Metal BC texture compression support")
        }

        for mip in mips {
            let blocksWide = (mip.width - 1) / 4 + 1
            let blocksHigh = (mip.height - 1) / 4 + 1
            guard let expectedByteCount = SceneTexContainer.byteCount2D(
                width: blocksWide, height: blocksHigh, bytesPerElement: bytesPerBlock
            ), mip.data.count == expectedByteCount else {
                return .decodeFailed("BC mip data does not match its stored block layout")
            }
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: firstMip.width,
            height: firstMip.height,
            mipmapped: false
        )
        descriptor.mipmapLevelCount = mips.count
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return .textureAllocationFailed(width: firstMip.width, height: firstMip.height)
        }

        for (level, mip) in mips.enumerated() {
            let bytesPerRow = ((mip.width - 1) / 4 + 1) * bytesPerBlock
            mip.data.withUnsafeBytes { rawBuffer in
                texture.replace(
                    region: MTLRegionMake2D(0, 0, mip.width, mip.height),
                    mipmapLevel: level,
                    withBytes: rawBuffer.baseAddress!,
                    bytesPerRow: bytesPerRow
                )
            }
        }
        return .loaded(texture)
    }

    private static func premultiplyStraightAlphaRGBA(_ data: Data) -> Data {
        var output = data
        output.withUnsafeMutableBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            var offset = 0
            while offset + 3 < rawBuffer.count {
                let alpha = UInt16(bytes[offset + 3])
                bytes[offset] = UInt8((UInt16(bytes[offset]) * alpha + 127) / 255)
                bytes[offset + 1] = UInt8((UInt16(bytes[offset + 1]) * alpha + 127) / 255)
                bytes[offset + 2] = UInt8((UInt16(bytes[offset + 2]) * alpha + 127) / 255)
                offset += 4
            }
        }
        return output
    }

    private static func bytesPerBlock(for pixelFormat: MTLPixelFormat) -> Int? {
        switch pixelFormat {
        case .bc1_rgba:
            return 8
        case .bc2_rgba, .bc3_rgba, .bc5_rgSnorm:
            return 16
        default:
            return nil
        }
    }
}
