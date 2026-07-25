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
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let firstMip = container.mips.first else {
            return .decodeFailed("TEX container has no mip data")
        }
        // BC1/BC2/BC3 are color sources with straight alpha. The compositor
        // blends premultiplied source-over, so normalize color payloads before
        // consumers see them. Small single images decode on CPU; larger or
        // multi-image containers use the GPU path below. Both crop padded
        // storage to an authored image/frame region. Direct sampling would let
        // transparent texels bloom their RGB into opaque-looking mattes.
        if let bcFormat = SceneBCTextureDecoder.Format(texFormat: container.format) {
            if container.imageCount == 1,
               firstMip.width * firstMip.height <= maxDecodedPixelCount {
                return uploadDecodedColor(
                    container: container,
                    mip: firstMip,
                    format: bcFormat,
                    device: device
                )
            }
            return uploadNormalizedColor(
                container: container,
                mip: firstMip,
                pixelFormat: pixelFormat,
                device: device
            )
        }
        return uploadDirect(
            container: container,
            mip: firstMip,
            pixelFormat: pixelFormat,
            device: device
        )
    }

    private static func uploadDecodedColor(
        container: SceneTexContainer,
        mip: SceneTexContainer.Mip,
        format: SceneBCTextureDecoder.Format,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let decoded = SceneBCTextureDecoder.decode(
            blockData: mip.data,
            storedWidth: mip.width,
            storedHeight: mip.height,
            imageWidth: container.imageWidth,
            imageHeight: container.imageHeight,
            format: format
        ) else {
            return .decodeFailed("BC mip data does not match its stored block layout")
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: decoded.width,
            height: decoded.height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return .textureAllocationFailed(width: decoded.width, height: decoded.height)
        }

        let premultiplied = premultiplyStraightAlphaRGBA(decoded.rgba)
        premultiplied.withUnsafeBytes { rawBuffer in
            texture.replace(
                region: MTLRegionMake2D(0, 0, decoded.width, decoded.height),
                mipmapLevel: 0,
                withBytes: rawBuffer.baseAddress!,
                bytesPerRow: decoded.width * 4
            )
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
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        let direct = uploadDirect(
            container: container,
            mip: mip,
            pixelFormat: pixelFormat,
            device: device
        )
        guard case let .loaded(source) = direct else { return direct }
        guard let region = normalizationRegion(container: container, mip: mip) else {
            return .decodeFailed("multi-image BC sprite has no supported static first-frame region")
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: region.width,
            height: region.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let destination = device.makeTexture(descriptor: descriptor),
              let commandQueue = device.makeCommandQueue(),
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
        conversion.offset = MPSOffset(x: region.sourceX, y: region.sourceY, z: 0)
        conversion.clipRect = MTLRegionMake2D(0, 0, region.width, region.height)
        conversion.encode(
            commandBuffer: commandBuffer,
            sourceTexture: source,
            destinationTexture: destination
        )
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
        let sourceX = Int((frame.origin.x * Float(mip.width)).rounded())
        let sourceY = Int((frame.origin.y * Float(mip.height)).rounded())
        let width = Int((frame.xAxis.x * Float(mip.width)).rounded())
        let height = Int((frame.yAxis.y * Float(mip.height)).rounded())
        guard sourceX >= 0, sourceY >= 0, width > 0, height > 0,
              sourceX + width <= mip.width,
              sourceY + height <= mip.height else {
            return nil
        }
        return NormalizationRegion(
            sourceX: sourceX,
            sourceY: sourceY,
            width: width,
            height: height
        )
    }

    // Non-color payloads (BC5 normal maps) keep their native block upload.
    private static func uploadDirect(
        container: SceneTexContainer,
        mip: SceneTexContainer.Mip,
        pixelFormat: MTLPixelFormat,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let bytesPerBlock = bytesPerBlock(for: pixelFormat) else {
            return .decodeFailed("unsupported Metal BC pixel format: \(pixelFormat.rawValue)")
        }
        if device.supportsBCTextureCompression == false {
            return .decodeFailed("BC upload requires Metal BC texture compression support")
        }

        let sourceBlocksWide = max(1, (mip.width + 3) / 4)
        let sourceBlocksHigh = max(1, (mip.height + 3) / 4)
        let sourceBytesPerRow = sourceBlocksWide * bytesPerBlock
        let storedByteCount = sourceBytesPerRow * sourceBlocksHigh
        guard mip.data.count == storedByteCount else {
            return .decodeFailed("BC mip data size mismatch: \(mip.data.count) != \(storedByteCount)")
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: mip.width,
            height: mip.height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return .textureAllocationFailed(width: mip.width, height: mip.height)
        }

        mip.data.withUnsafeBytes { rawBuffer in
            texture.replace(
                region: MTLRegionMake2D(0, 0, mip.width, mip.height),
                mipmapLevel: 0,
                withBytes: rawBuffer.baseAddress!,
                bytesPerRow: sourceBytesPerRow
            )
        }
        return .loaded(texture)
    }

    private static func premultiplyStraightAlphaRGBA(_ data: Data) -> Data {
        var output = data
        let pixelCount = output.count / 4
        output.withUnsafeMutableBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for index in 0..<pixelCount {
                let pixel = bytes.advanced(by: index * 4)
                let alpha = UInt16(pixel[3])
                pixel[0] = UInt8((UInt16(pixel[0]) * alpha + 127) / 255)
                pixel[1] = UInt8((UInt16(pixel[1]) * alpha + 127) / 255)
                pixel[2] = UInt8((UInt16(pixel[2]) * alpha + 127) / 255)
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
