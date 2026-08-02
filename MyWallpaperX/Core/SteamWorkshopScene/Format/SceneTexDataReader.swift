import Compression
import Foundation

extension Data {
    func uint32LE(at offset: Int) -> UInt32 {
        withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }

    func int32LE(at offset: Int) -> Int32 {
        withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(fromByteOffset: offset, as: Int32.self).littleEndian
        }
    }

    func float32LE(at offset: Int) -> Float {
        Float(bitPattern: uint32LE(at: offset))
    }

    func skipNullTerminatedString(at offset: inout Int) throws {
        guard let terminator = self[offset...].firstIndex(of: 0) else {
            throw SceneTexContainerReader.ReadError.invalidMipTable
        }
        offset = terminator + 1
    }
}

extension SceneTexContainerReader {
    private enum SpriteVersion: String {
        case texs0001 = "TEXS0001"
        case texs0002 = "TEXS0002"
        case texs0003 = "TEXS0003"

        var usesIntegerCoordinates: Bool { self == .texs0001 }
        var hasAtlasSize: Bool { self == .texs0003 }
    }

    func readSpriteFrames(
        data: Data,
        offset: inout Int,
        imageSizes: [SIMD2<Float>]
    ) throws -> [SceneTexContainer.SpriteFrame] {
        guard offset + 13 <= data.count,
              data[offset + 8] == 0,
              let rawVersion = String(data: data[offset..<(offset + 8)], encoding: .ascii),
              let version = SpriteVersion(rawValue: rawVersion) else {
            throw ReadError.invalidSpriteTable
        }
        offset += 9
        let frameCount = Int(data.int32LE(at: offset))
        offset += 4
        guard frameCount >= 0, frameCount <= Self.maximumSpriteFrameCount else {
            throw ReadError.invalidSpriteTable
        }
        if version.hasAtlasSize {
            guard offset + 8 <= data.count,
                  data.int32LE(at: offset) > 0,
                  data.int32LE(at: offset + 4) > 0 else {
                throw ReadError.invalidSpriteTable
            }
            offset += 8
        }
        let frameByteCount = 32
        guard frameCount <= (data.count - offset) / frameByteCount else {
            throw ReadError.invalidSpriteTable
        }

        var frames: [SceneTexContainer.SpriteFrame] = []
        frames.reserveCapacity(frameCount)
        for _ in 0..<frameCount {
            let imageIndex = Int(data.int32LE(at: offset))
            let duration = data.float32LE(at: offset + 4)
            offset += 8
            guard imageSizes.indices.contains(imageIndex), duration.isFinite, duration >= 0 else {
                throw ReadError.invalidSpriteTable
            }
            let coordinates = (0..<6).map { index -> Float in
                let coordinateOffset = offset + index * 4
                return version.usesIntegerCoordinates
                    ? Float(data.int32LE(at: coordinateOffset))
                    : data.float32LE(at: coordinateOffset)
            }
            offset += 24
            guard coordinates.allSatisfy(\.isFinite) else {
                throw ReadError.invalidSpriteTable
            }
            let imageSize = imageSizes[imageIndex]
            frames.append(.init(
                imageIndex: imageIndex,
                duration: duration,
                origin: SIMD2(coordinates[0] / imageSize.x, coordinates[1] / imageSize.y),
                xAxis: SIMD2(coordinates[2] / imageSize.x, coordinates[3] / imageSize.x),
                yAxis: SIMD2(coordinates[4] / imageSize.y, coordinates[5] / imageSize.y)
            ))
        }
        return frames
    }

    func readMip(
        data: Data,
        offset: inout Int,
        containerVersion: SceneTexContainer.ContainerVersion,
        metadataEntryCount: Int,
        volumeHeader: Bool
    ) throws -> SceneTexContainer.Mip {
        if containerVersion == .texb0004 {
            for _ in 0..<metadataEntryCount {
                guard offset + 8 <= data.count else {
                    throw ReadError.invalidMipTable
                }
                offset += 8
                try data.skipNullTerminatedString(at: &offset)
                guard offset + 4 <= data.count else {
                    throw ReadError.invalidMipTable
                }
                offset += 4
            }
        }

        guard offset + 8 <= data.count else {
            throw ReadError.invalidMipTable
        }
        let width = Int(data.uint32LE(at: offset))
        offset += 4
        let height = Int(data.uint32LE(at: offset))
        offset += 4
        let depth: Int
        if volumeHeader {
            guard offset + 4 <= data.count else {
                throw ReadError.invalidMipTable
            }
            depth = Int(data.uint32LE(at: offset))
            offset += 4
        } else {
            depth = 1
        }
        guard width > 0, height > 0 else {
            throw ReadError.invalidMipTable
        }
        if volumeHeader {
            guard width <= Self.maximumVolumeDimension,
                  height <= Self.maximumVolumeDimension,
                  depth > 0, depth <= Self.maximumVolumeDimension,
                  width * height <= Self.maximumVolumeVoxelCount / depth else {
                throw ReadError.invalidMipTable
            }
        }

        var compressionCode: UInt32 = 0
        var decodedByteCount = 0
        if containerVersion != .texb0001 {
            guard offset + 8 <= data.count else {
                throw ReadError.invalidMipTable
            }
            compressionCode = data.uint32LE(at: offset)
            offset += 4
            decodedByteCount = Int(data.int32LE(at: offset))
            offset += 4
        }

        guard offset + 4 <= data.count else {
            throw ReadError.invalidMipTable
        }
        let storedByteCount = Int(data.int32LE(at: offset))
        offset += 4
        guard storedByteCount >= 0,
              storedByteCount <= Self.maximumMipByteCount,
              offset + storedByteCount <= data.count else {
            throw ReadError.invalidMipTable
        }

        let storedBytes = data.subdata(in: offset..<(offset + storedByteCount))
        offset += storedByteCount

        let mipData: Data
        switch compressionCode {
        case 0:
            mipData = storedBytes
        case 1:
            guard decodedByteCount > 0, decodedByteCount <= Self.maximumMipByteCount else {
                throw ReadError.invalidMipTable
            }
            mipData = try decompressLZ4Raw(storedBytes, expectedSize: decodedByteCount)
        default:
            throw ReadError.unsupportedCompression(compressionCode)
        }

        return .init(width: width, height: height, depth: depth, data: mipData)
    }

    private func decompressLZ4Raw(_ compressed: Data, expectedSize: Int) throws -> Data {
        var decoded = Data(count: expectedSize)
        let actualSize = decoded.withUnsafeMutableBytes { destinationBuffer in
            compressed.withUnsafeBytes { sourceBuffer in
                compression_decode_buffer(
                    destinationBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    compressed.count,
                    nil,
                    COMPRESSION_LZ4_RAW
                )
            }
        }

        guard actualSize == expectedSize else {
            throw ReadError.decompressionFailed(expectedSize: expectedSize, actualSize: actualSize)
        }
        return decoded
    }
}
