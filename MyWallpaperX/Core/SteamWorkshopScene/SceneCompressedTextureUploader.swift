import Foundation
import Metal

struct SceneCompressedTextureUploader {
    private struct UploadPayload {
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let data: Data
    }

    static func upload(
        container: SceneTexContainer,
        pixelFormat: MTLPixelFormat,
        device: MTLDevice
    ) -> SceneTextureLoadOutcome {
        guard let firstMip = container.mips.first else {
            return .decodeFailed("TEX container has no mip data")
        }
        if container.format == 6, device.supportsBCTextureCompression == false {
            return .decodeFailed("BC2/DXT3 upload requires Metal BC texture compression support")
        }
        guard let bytesPerBlock = bytesPerBlock(for: pixelFormat) else {
            return .decodeFailed("unsupported Metal BC pixel format: \(pixelFormat.rawValue)")
        }

        let sourceBlocksWide = max(1, (firstMip.width + 3) / 4)
        let sourceBlocksHigh = max(1, (firstMip.height + 3) / 4)
        let sourceBytesPerRow = sourceBlocksWide * bytesPerBlock
        let storedByteCount = sourceBytesPerRow * sourceBlocksHigh
        guard firstMip.data.count == storedByteCount else {
            return .decodeFailed("BC mip data size mismatch: \(firstMip.data.count) != \(storedByteCount)")
        }

        let payload: UploadPayload
        if container.format == 6 {
            guard let cropped = croppedBC2Payload(
                container: container,
                mip: firstMip,
                bytesPerBlock: bytesPerBlock,
                sourceBlocksWide: sourceBlocksWide,
                sourceBlocksHigh: sourceBlocksHigh
            ) else {
                return .decodeFailed("BC2 image dimensions exceed the stored mip layout")
            }
            payload = cropped
        } else {
            payload = UploadPayload(
                width: firstMip.width,
                height: firstMip.height,
                bytesPerRow: sourceBytesPerRow,
                data: firstMip.data
            )
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: payload.width,
            height: payload.height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return .textureAllocationFailed(width: payload.width, height: payload.height)
        }

        payload.data.withUnsafeBytes { rawBuffer in
            texture.replace(
                region: MTLRegionMake2D(0, 0, payload.width, payload.height),
                mipmapLevel: 0,
                withBytes: rawBuffer.baseAddress!,
                bytesPerRow: payload.bytesPerRow
            )
        }
        return .loaded(texture)
    }

    private static func croppedBC2Payload(
        container: SceneTexContainer,
        mip: SceneTexContainer.Mip,
        bytesPerBlock: Int,
        sourceBlocksWide: Int,
        sourceBlocksHigh: Int
    ) -> UploadPayload? {
        let width = container.imageWidth
        let height = container.imageHeight
        guard width > 0, height > 0, width <= mip.width, height <= mip.height else {
            return nil
        }

        let targetBlocksWide = max(1, (width + 3) / 4)
        let targetBlocksHigh = max(1, (height + 3) / 4)
        guard targetBlocksWide <= sourceBlocksWide,
              targetBlocksHigh <= sourceBlocksHigh else {
            return nil
        }

        let sourceBytesPerRow = sourceBlocksWide * bytesPerBlock
        let targetBytesPerRow = targetBlocksWide * bytesPerBlock
        if targetBlocksWide == sourceBlocksWide, targetBlocksHigh == sourceBlocksHigh {
            return UploadPayload(
                width: width,
                height: height,
                bytesPerRow: targetBytesPerRow,
                data: mip.data
            )
        }

        var cropped = Data()
        cropped.reserveCapacity(targetBytesPerRow * targetBlocksHigh)
        for row in 0..<targetBlocksHigh {
            let start = row * sourceBytesPerRow
            cropped.append(contentsOf: mip.data[start..<(start + targetBytesPerRow)])
        }
        return UploadPayload(
            width: width,
            height: height,
            bytesPerRow: targetBytesPerRow,
            data: cropped
        )
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
