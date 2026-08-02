import Foundation
import Metal

struct SceneTexContainer {
    enum ContainerVersion: String {
        case texb0001 = "TEXB0001"
        case texb0002 = "TEXB0002"
        case texb0003 = "TEXB0003"
        case texb0004 = "TEXB0004"
    }

    struct Mip {
        let width: Int
        let height: Int
        let depth: Int
        let data: Data

        init(width: Int, height: Int, depth: Int = 1, data: Data) {
            self.width = width
            self.height = height
            self.depth = depth
            self.data = data
        }
    }

    struct Image {
        let mips: [Mip]
    }

    struct SpriteFrame {
        let imageIndex: Int
        let duration: Float
        let origin: SIMD2<Float>
        let xAxis: SIMD2<Float>
        let yAxis: SIMD2<Float>
    }

    let format: UInt32
    let flags: UInt32
    let textureWidth: Int
    let textureHeight: Int
    let textureDepth: Int
    let imageWidth: Int
    let imageHeight: Int
    let containerVersion: ContainerVersion
    let freeImageFormat: Int32
    let isVideoMp4: Bool
    let images: [Image]
    let spriteFrames: [SpriteFrame]

    init(
        format: UInt32,
        flags: UInt32,
        textureWidth: Int,
        textureHeight: Int,
        textureDepth: Int = 1,
        imageWidth: Int,
        imageHeight: Int,
        containerVersion: ContainerVersion,
        freeImageFormat: Int32,
        isVideoMp4: Bool,
        images: [Image],
        spriteFrames: [SpriteFrame]
    ) {
        self.format = format
        self.flags = flags
        self.textureWidth = textureWidth
        self.textureHeight = textureHeight
        self.textureDepth = textureDepth
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.containerVersion = containerVersion
        self.freeImageFormat = freeImageFormat
        self.isVideoMp4 = isVideoMp4
        self.images = images
        self.spriteFrames = spriteFrames
    }

    var imageCount: Int { images.count }
    var mips: [Mip] { images.first?.mips ?? [] }

    var isAnimated: Bool {
        flags & 4 != 0
    }

    var isVolume: Bool {
        textureDepth > 1 || mips.contains { $0.depth > 1 }
    }

    var metalPixelFormat: MTLPixelFormat? {
        switch format {
        case 4:
            return .bc3_rgba
        case 5:
            return .bc5_rgSnorm
        case 6:
            return .bc2_rgba
        case 7:
            return .bc1_rgba
        default:
            return nil
        }
    }

    var rawMetalPixelFormat: MTLPixelFormat? {
        switch format {
        case 8:
            return .rg8Unorm
        case 9:
            return .r8Unorm
        default:
            return nil
        }
    }

    var rawBytesPerPixel: Int? {
        switch format {
        case 8:
            return 2
        case 9:
            return 1
        default:
            return nil
        }
    }
}

struct SceneTexContainerReader {
    enum ReadError: LocalizedError {
        case invalidHeader
        case invalidMipTable
        case invalidSpriteTable
        case unsupportedCompression(UInt32)
        case decompressionFailed(expectedSize: Int, actualSize: Int)

        var errorDescription: String? {
            switch self {
            case .invalidHeader:
                return "无效的 TEXV0005 纹理头。"
            case .invalidMipTable:
                return "无效的 TEX mip 数据表。"
            case .invalidSpriteTable:
                return "无效的 TEX sprite 帧数据表。"
            case let .unsupportedCompression(code):
                return "不支持的 TEX mip 压缩方式: \(code)。"
            case let .decompressionFailed(expectedSize, actualSize):
                return "LZ4 解压失败，期望 \(expectedSize) 字节，实际得到 \(actualSize) 字节。"
            }
        }
    }

    private static let maximumImageCount = 512
    private static let maximumMipCount = 32
    private static let maximumMipMetadataEntryCount = 32
    static let maximumMipByteCount = 250_000_000
    static let maximumSpriteFrameCount = 65_536
    static let maximumVolumeDimension = 256
    static let maximumVolumeVoxelCount = 16_777_216

    func read(data: Data) throws -> SceneTexContainer {
        guard data.count >= 55,
              data.starts(with: Data("TEXV0005\0TEXI0001\0".utf8)) else {
            throw ReadError.invalidHeader
        }
        let volumeHeader = data.count >= 59
            && data[58] == 0
            && String(data: data[50..<58], encoding: .ascii)?.hasPrefix("TEXB") == true
        let markerOffset = volumeHeader ? 50 : 46
        let markerEnd = markerOffset + 8
        guard markerEnd < data.count,
              data[markerEnd] == 0,
              let rawContainerVersion = String(
                  data: data[markerOffset..<markerEnd],
                  encoding: .ascii
              ),
              let declaredContainerVersion = SceneTexContainer.ContainerVersion(rawValue: rawContainerVersion) else {
            throw ReadError.invalidHeader
        }

        let format = data.uint32LE(at: 18)
        let flags = data.uint32LE(at: 22)
        let textureWidth = Int(data.uint32LE(at: 26))
        let textureHeight = Int(data.uint32LE(at: 30))
        let textureDepth = volumeHeader ? Int(data.uint32LE(at: 42)) : 1
        let imageWidth = Int(data.uint32LE(at: 34))
        let imageHeight = Int(data.uint32LE(at: 38))

        if volumeHeader {
            guard format == 0,
                  flags & 4 == 0,
                  (1 ... Self.maximumVolumeDimension).contains(textureWidth),
                  (1 ... Self.maximumVolumeDimension).contains(textureHeight),
                  (2 ... Self.maximumVolumeDimension).contains(textureDepth),
                  textureWidth * textureHeight <= Self.maximumVolumeVoxelCount / textureDepth,
                  imageWidth == textureWidth * textureDepth,
                  imageHeight == textureHeight,
                  declaredContainerVersion == .texb0004 else {
                throw ReadError.invalidHeader
            }
        }

        var offset = markerEnd + 1
        let imageCount = Int(data.uint32LE(at: offset))
        offset += 4
        guard imageCount > 0, imageCount <= Self.maximumImageCount else {
            throw ReadError.invalidMipTable
        }

        var freeImageFormat: Int32 = -1
        var isVideoMp4 = false
        var mipMetadataEntryCount = 0
        let effectiveContainerVersion: SceneTexContainer.ContainerVersion

        switch declaredContainerVersion {
        case .texb0001, .texb0002:
            effectiveContainerVersion = declaredContainerVersion
        case .texb0003:
            guard offset + 4 <= data.count else {
                throw ReadError.invalidMipTable
            }
            freeImageFormat = data.int32LE(at: offset)
            offset += 4
            effectiveContainerVersion = .texb0003
        case .texb0004:
            guard offset + 8 <= data.count else {
                throw ReadError.invalidMipTable
            }
            freeImageFormat = data.int32LE(at: offset)
            offset += 4
            mipMetadataEntryCount = Int(data.uint32LE(at: offset))
            offset += 4
            guard mipMetadataEntryCount <= Self.maximumMipMetadataEntryCount else {
                throw ReadError.invalidMipTable
            }
            isVideoMp4 = mipMetadataEntryCount == 1
            effectiveContainerVersion = mipMetadataEntryCount == 0
                ? .texb0003
                : .texb0004
        }

        var images: [SceneTexContainer.Image] = []
        images.reserveCapacity(imageCount)
        var imageSizes: [SIMD2<Float>] = []
        for _ in 0..<imageCount {
            guard offset + 4 <= data.count else {
                throw ReadError.invalidMipTable
            }
            let mipCount = Int(data.uint32LE(at: offset))
            offset += 4
            guard mipCount > 0, mipCount <= Self.maximumMipCount else {
                throw ReadError.invalidMipTable
            }

            var parsedMips: [SceneTexContainer.Mip] = []
            for mipIndex in 0..<mipCount {
                let mip = try readMip(
                    data: data,
                    offset: &offset,
                    containerVersion: effectiveContainerVersion,
                    metadataEntryCount: mipMetadataEntryCount,
                    volumeHeader: volumeHeader
                )
                if mipIndex == 0 {
                    imageSizes.append(SIMD2(Float(mip.width), Float(mip.height)))
                }
                parsedMips.append(mip)
            }
            images.append(.init(mips: parsedMips))
        }

        guard images.count == imageCount,
              images.allSatisfy({ !$0.mips.isEmpty }) else {
            throw ReadError.invalidMipTable
        }
        if volumeHeader {
            guard imageCount == 1,
                  images[0].mips.count == 1,
                  images[0].mips[0].width == textureWidth,
                  images[0].mips[0].height == textureHeight,
                  images[0].mips[0].depth == textureDepth,
                  freeImageFormat == 13,
                  mipMetadataEntryCount == 0 else {
                throw ReadError.invalidMipTable
            }
        }
        let spriteFrames = flags & 4 == 0
            ? []
            : try readSpriteFrames(data: data, offset: &offset, imageSizes: imageSizes)

        return SceneTexContainer(
            format: format,
            flags: flags,
            textureWidth: textureWidth,
            textureHeight: textureHeight,
            textureDepth: textureDepth,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            containerVersion: effectiveContainerVersion,
            freeImageFormat: freeImageFormat,
            isVideoMp4: isVideoMp4,
            images: images,
            spriteFrames: spriteFrames
        )
    }

}
