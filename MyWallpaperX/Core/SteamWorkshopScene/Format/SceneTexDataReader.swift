import Compression
import Foundation

nonisolated extension Data {
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

nonisolated extension SceneTexContainerReader {
    typealias ConditionalDeclaration = (id: UInt32, condition: SceneTexContainer.Condition)

    private struct ConditionalPatchRecord {
        let mipLevel: Int
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let payload: Range<Int>
    }

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]

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
                xAxis: SIMD2(coordinates[2], coordinates[3]) / imageSize,
                yAxis: SIMD2(coordinates[4], coordinates[5]) / imageSize
            ))
        }
        return frames
    }

    func readMipCount(data: Data, offset: inout Int) throws -> Int {
        guard data.count - offset >= 4 else { throw ReadError.invalidMipTable }
        let count = Int(data.uint32LE(at: offset))
        offset += 4
        guard count > 0, count <= Self.maximumMipCount else { throw ReadError.invalidMipTable }
        return count
    }

    func conditionalTable(
        data: Data, offset: Int, count: Int
    ) -> (mipCountOffset: Int, declarations: [ConditionalDeclaration])? {
        // Older TEXB0004 entries instead start with a mip count and carry
        // metadata inside that mip. A positive metadata count alone is ambiguous.
        guard data.count - offset >= 12,
              data.uint32LE(at: offset) == 1, data.uint32LE(at: offset + 4) > 0 else { return nil }
        var cursor = offset
        var declarations: [ConditionalDeclaration] = []
        var seenIDs: Set<UInt32> = []
        var ambiguousIDs: Set<UInt32> = []
        for _ in 0..<count {
            guard data.count - cursor >= 12 else { return nil }
            let kind = data.uint32LE(at: cursor)
            let id = data.uint32LE(at: cursor + 4)
            cursor += 12
            guard let end = data[cursor...].firstIndex(of: 0) else { return nil }
            // A declaration is a typed key and an optional literal, not a
            // general JSON document. Large unknown metadata need not be parsed.
            if kind == 1, end - cursor <= 4096,
               let object = (try? JSONSerialization.jsonObject(with: data.subdata(in: cursor..<end)))
                    as? [String: Any],
               id != 0, object.count == 1, let raw = object["condition"],
               let condition = conditionalPredicate(raw) {
                declarations.append((id, condition))
            }
            if !seenIDs.insert(id).inserted { ambiguousIDs.insert(id) }
            cursor = end + 1
        }
        // Match the mip count and full-size base PNG framing. Unrecognized
        // conditions can still leave a well-framed ordinary base.
        guard data.count - cursor >= 32,
              (1...Self.maximumMipCount).contains(Int(data.uint32LE(at: cursor))),
              data[(cursor + 24)...].starts(with: Self.pngSignature) else { return nil }
        return (cursor, declarations.filter { !ambiguousIDs.contains($0.id) })
    }

    private func conditionalPredicate(_ value: Any) -> SceneTexContainer.Condition? {
        if let key = value as? String, !key.isEmpty { return .boolean(propertyKey: key) }
        guard let comparison = value as? [String: Any], comparison.count == 2,
              let key = comparison["name"] as? String, !key.isEmpty,
              let literal = comparison["condition"] as? String else { return nil }
        return .equals(propertyKey: key, value: literal)
    }

    func readConditionalMips(
        data: Data,
        offset: inout Int,
        declarations: [ConditionalDeclaration],
        remainingDecodedBytes: inout Int
    ) throws -> (mips: [SceneTexContainer.Mip], variants: [SceneTexContainer.ConditionalVariant]) {
        let count = try readMipCount(data: data, offset: &offset)
        var mips: [SceneTexContainer.Mip] = []
        var packets: [UInt32: [ConditionalPatchRecord]] = [:]
        let knownIDs = Set(declarations.map(\.id))
        var unavailableIDs: Set<UInt32> = []
        var hasPNGChain = true
        for mipLevel in 0..<count {
            let mip = try readMip(data: data, offset: &offset, containerVersion: .texb0003,
                metadataEntryCount: 0, volumeHeader: false, permitsLargeVideoPayload: false,
                remainingDecodedBytes: &remainingDecodedBytes)
            mips.append(mip)
            hasPNGChain = hasPNGChain && mip.data.starts(with: Self.pngSignature)
            guard readConditionalPatches(data: data, offset: &offset, mip: mip, mipLevel: mipLevel,
                    knownIDs: knownIDs, packets: &packets, unavailableIDs: &unavailableIDs) else {
                // An unbounded optional tail prevents reaching later records.
                // Earlier, fully read base mips remain usable on their own.
                return (mips, [])
            }
        }
        guard hasPNGChain else { return (mips, []) }
        // Base mips take priority; validate ranges before copying optional data.
        let variants: [SceneTexContainer.ConditionalVariant] = declarations.compactMap { declaration in
            guard !unavailableIDs.contains(declaration.id), let patches = packets[declaration.id] else { return nil }
            let bytes = patches.reduce(0) { $0 + $1.payload.count }
            guard bytes <= remainingDecodedBytes else { return nil }
            remainingDecodedBytes -= bytes
            return .init(id: declaration.id, condition: declaration.condition, mipPatches: patches.map {
                .init(mipLevel: $0.mipLevel, x: $0.x, y: $0.y, width: $0.width, height: $0.height,
                    data: data.subdata(in: $0.payload))
            })
        }
        return (mips, variants)
    }

    private func readConditionalPatches(
        data: Data, offset: inout Int, mip: SceneTexContainer.Mip, mipLevel: Int,
        knownIDs: Set<UInt32>, packets: inout [UInt32: [ConditionalPatchRecord]],
        unavailableIDs: inout Set<UInt32>
    ) -> Bool {
        guard data.count - offset >= 8, data.uint32LE(at: offset) == 1 else { return false }
        let count = Int(data.uint32LE(at: offset + 4))
        offset += 8
        guard count <= Self.maximumMipMetadataEntryCount else { return false }
        for _ in 0..<count {
            guard data.count - offset >= 32 else { return false }
            let kind = data.uint32LE(at: offset)
            let id = data.uint32LE(at: offset + 4)
            let x = Int(data.uint32LE(at: offset + 8))
            let y = Int(data.uint32LE(at: offset + 12))
            let width = Int(data.uint32LE(at: offset + 16))
            let height = Int(data.uint32LE(at: offset + 20))
            let encoding = data.uint32LE(at: offset + 24)
            let bytes = Int(data.uint32LE(at: offset + 28))
            offset += 32
            guard bytes <= data.count - offset else { return false }
            let payload = offset..<(offset + bytes)
            offset = payload.upperBound
            guard knownIDs.contains(id), !unavailableIDs.contains(id) else { continue }
            guard kind == 1, encoding == 13, bytes <= Self.maximumMipByteCount,
                  width > 0, height > 0, width <= mip.width - x, height <= mip.height - y,
                  data[payload].starts(with: Self.pngSignature) else {
                unavailableIDs.insert(id)
                continue
            }
            packets[id, default: []].append(.init(mipLevel: mipLevel, x: x, y: y,
                width: width, height: height, payload: payload))
        }
        return true
    }

    func readMip(
        data: Data,
        offset: inout Int,
        containerVersion: SceneTexContainer.ContainerVersion,
        metadataEntryCount: Int,
        volumeHeader: Bool,
        permitsLargeVideoPayload: Bool,
        remainingDecodedBytes: inout Int
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
              storedByteCount <= data.count - offset else {
            throw ReadError.invalidMipTable
        }
        // Uncompressed video in a single 2D payload is media storage, not a
        // static decoded mip. Sniff only its validated prefix; retain the full
        // payload's aggregate budget check before any large copy below.
        let isLargeVideoPayload = storedByteCount > Self.maximumMipByteCount
            && permitsLargeVideoPayload && compressionCode == 0
            && SceneTexContainer.isVideoPayload(data.subdata(
                in: offset..<(offset + min(storedByteCount, 12))
            ))
        guard storedByteCount <= Self.maximumMipByteCount || isLargeVideoPayload else {
            throw ReadError.invalidMipTable
        }

        let outputByteCount: Int
        switch compressionCode {
        case 0:
            outputByteCount = storedByteCount
        case 1:
            guard decodedByteCount > 0, decodedByteCount <= Self.maximumMipByteCount else {
                throw ReadError.invalidMipTable
            }
            outputByteCount = decodedByteCount
        default:
            throw ReadError.unsupportedCompression(compressionCode)
        }
        guard outputByteCount <= remainingDecodedBytes else {
            throw ReadError.decodedDataBudgetExceeded
        }
        remainingDecodedBytes -= outputByteCount
        let storedRange = offset..<(offset + storedByteCount)
        offset = storedRange.upperBound
        let mipData = compressionCode == 0
            ? data.subdata(in: storedRange)
            : try decompressLZ4Raw(data, range: storedRange, expectedSize: decodedByteCount)

        return .init(width: width, height: height, depth: depth, data: mipData)
    }

    private func decompressLZ4Raw(_ data: Data, range: Range<Int>, expectedSize: Int) throws -> Data {
        // The decoder returns the buffer size when output is truncated. One
        // extra byte distinguishes an exact payload from an oversized block.
        let capacity = expectedSize + 1
        var decoded = Data(count: capacity)
        let actualSize = decoded.withUnsafeMutableBytes { destinationBuffer in
            data.withUnsafeBytes { sourceBuffer in
                compression_decode_buffer(
                    destinationBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    capacity,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress!.advanced(by: range.lowerBound),
                    range.count,
                    nil,
                    COMPRESSION_LZ4_RAW
                )
            }
        }

        guard actualSize == expectedSize else {
            throw ReadError.decompressionFailed(expectedSize: expectedSize, actualSize: actualSize)
        }
        decoded.count = expectedSize
        return decoded
    }
}
