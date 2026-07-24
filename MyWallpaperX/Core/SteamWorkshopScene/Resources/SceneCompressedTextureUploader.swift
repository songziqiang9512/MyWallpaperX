import Foundation
import Metal

struct SceneCompressedTextureUploader {
    static func upload(
        container: SceneTexContainer,
        pixelFormat: MTLPixelFormat,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let firstMip = container.mips.first else {
            return .decodeFailed("TEX container has no mip data")
        }
        // BC1/BC2/BC3 are color sources with straight alpha. The compositor
        // blends premultiplied source-over, so decode on CPU, premultiply,
        // and crop the padded block grid to the authored image size — the
        // same contract the raw format-0 path follows. Direct upload would
        // let transparent texels bloom their (usually white) RGB into the
        // frame as opaque-looking mattes.
        if let bcFormat = SceneBCTextureDecoder.Format(texFormat: container.format) {
            return uploadDecodedColor(
                container: container,
                mip: firstMip,
                format: bcFormat,
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
