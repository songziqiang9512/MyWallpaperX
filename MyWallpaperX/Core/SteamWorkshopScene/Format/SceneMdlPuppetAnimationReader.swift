import Foundation

enum SceneMdlPuppetAnimationReadError: Error, CustomStringConvertible, Equatable, Sendable {
    case unsupportedMagic(String)
    case skeletonBlockMissing
    case invalidSkeletonBounds
    case invalidBoneCount(Int)
    case invalidAnimationBounds
    case invalidAnimationCount(Int)
    case invalidAnimationHeader(Int)
    case duplicateAnimationID(Int)
    case invalidAnimationName(Int)
    case unsupportedAnimationMode(String)
    case animationBoneCount(animationID: Int, expected: Int, actual: Int)
    case invalidTrack(animationID: Int, boneIndex: Int)
    case invalidTransform(animationID: Int, boneIndex: Int, frameIndex: Int)
    case invalidAuxiliaryTrack(Int)

    nonisolated var description: String {
        switch self {
        case .unsupportedMagic(let magic):
            return "unsupported animation mdl magic \(magic)"
        case .skeletonBlockMissing:
            return "MDLA requires the version-matched preceding MDLS block"
        case .invalidSkeletonBounds:
            return "invalid version-matched MDLS animation boundary"
        case .invalidBoneCount(let count):
            return "invalid animation bone count \(count)"
        case .invalidAnimationBounds:
            return "invalid version-matched MDLA bounds"
        case .invalidAnimationCount(let count):
            return "invalid MDLA animation count \(count)"
        case .invalidAnimationHeader(let index):
            return "invalid MDLA animation header \(index)"
        case .duplicateAnimationID(let id):
            return "duplicate MDLA animation id \(id)"
        case .invalidAnimationName(let id):
            return "invalid MDLA animation name for id \(id)"
        case .unsupportedAnimationMode(let mode):
            return "unsupported MDLA animation mode \(mode)"
        case .animationBoneCount(let id, let expected, let actual):
            return "animation \(id) has \(actual) bones; expected \(expected)"
        case .invalidTrack(let id, let boneIndex):
            return "invalid animation \(id) track for bone \(boneIndex)"
        case .invalidTransform(let id, let boneIndex, let frameIndex):
            return "invalid animation \(id) transform at bone \(boneIndex) frame \(frameIndex)"
        case .invalidAuxiliaryTrack(let id):
            return "invalid verified auxiliary track for animation \(id)"
        }
    }
}

// Restricted version-matched MDLA reader. MDLV0017/MDLS0002/MDLA0004 and
// MDLV0023/MDLS0004/MDLA0006 share the same bounded full-transform track
// records; their distinct trailer shapes remain part of the version contract.
// Tracks are ordered by MDLS bone index and contain frameCount + 1 full
// transforms. Real assets vary translation, rotation, and scale, so all three
// components are retained without claiming unsupported mixing semantics.
enum SceneMdlPuppetAnimationReader {
    private enum TrailerContract {
        case legacyZeros10
        case modernAuxiliary
    }

    private struct VersionContract {
        let skeletonMarker: Data
        let animationMarker: Data
        let trailer: TrailerContract
    }

    private static let versionContracts = [
        "MDLV0017": VersionContract(
            skeletonMarker: Data("MDLS0002\0".utf8),
            animationMarker: Data("MDLA0004\0".utf8),
            trailer: .legacyZeros10
        ),
        "MDLV0023": VersionContract(
            skeletonMarker: Data("MDLS0004\0".utf8),
            animationMarker: Data("MDLA0006\0".utf8),
            trailer: .modernAuxiliary
        ),
    ]
    private static let knownAnimationMarkers = [
        Data("MDLA0004\0".utf8),
        Data("MDLA0006\0".utf8),
    ]
    private static let attachmentMarker = Data("MDAT0001\0".utf8)
    private static let markerSize = 9
    private static let maxBoneCount = 4_096
    private static let maxAnimationCount = 1_024
    private static let maxFrameCount = 60_000
    private static let maxNameBytes = 1_024
    private static let maxModeBytes = 64
    private static let maxTotalSamples = 8_000_000
    private static let transformByteCount = 36
    private static let maxAbsoluteTransformValue: Float = 1_000_000
    private static let auxiliaryTrackKey: UInt32 = 0x418A_55D5

    static func read(data rawData: Data) throws -> SceneMdlPuppetAnimationSet? {
        let data = rawData.startIndex == 0 ? rawData : Data(rawData)
        let presentMarkers = knownAnimationMarkers.filter { data.range(of: $0) != nil }
        guard presentMarkers.isEmpty == false else {
            return nil
        }
        let magic = String(decoding: data.prefix(8), as: UTF8.self)
        guard let contract = versionContracts[magic],
              presentMarkers.count == 1,
              presentMarkers[0] == contract.animationMarker,
              let animationOffset = data.range(of: contract.animationMarker)?.lowerBound else {
            throw SceneMdlPuppetAnimationReadError.unsupportedMagic(magic)
        }
        guard let skeletonOffset = data.range(of: contract.skeletonMarker)?.lowerBound,
              skeletonOffset < animationOffset else {
            throw SceneMdlPuppetAnimationReadError.skeletonBlockMissing
        }
        let boneCount = try readBoneCount(
            data: data,
            skeletonOffset: skeletonOffset,
            animationOffset: animationOffset
        )
        let animations = try readAnimations(
            data: data,
            blockOffset: animationOffset,
            boneCount: boneCount,
            trailerContract: contract.trailer
        )
        return SceneMdlPuppetAnimationSet(boneCount: boneCount, animations: animations)
    }

    private static func readBoneCount(
        data: Data,
        skeletonOffset: Int,
        animationOffset: Int
    ) throws -> Int {
        let cursor = skeletonOffset + markerSize
        guard cursor + 8 <= data.count else {
            throw SceneMdlPuppetAnimationReadError.invalidSkeletonBounds
        }
        let skeletonEnd = Int(readUInt32(data, at: cursor))
        guard skeletonEnd > cursor, skeletonEnd <= animationOffset else {
            throw SceneMdlPuppetAnimationReadError.invalidSkeletonBounds
        }
        if skeletonEnd != animationOffset {
            guard matches(attachmentMarker, in: data, at: skeletonEnd),
                  skeletonEnd + markerSize + 4 <= data.count,
                  Int(readUInt32(data, at: skeletonEnd + markerSize)) == animationOffset else {
                throw SceneMdlPuppetAnimationReadError.invalidSkeletonBounds
            }
        }
        let count = Int(readUInt32(data, at: cursor + 4))
        guard count > 0, count <= maxBoneCount else {
            throw SceneMdlPuppetAnimationReadError.invalidBoneCount(count)
        }
        return count
    }

    private static func readAnimations(
        data: Data,
        blockOffset: Int,
        boneCount: Int,
        trailerContract: TrailerContract
    ) throws -> [SceneMdlPuppetAnimation] {
        var cursor = blockOffset + markerSize
        guard cursor + 8 <= data.count else {
            throw SceneMdlPuppetAnimationReadError.invalidAnimationBounds
        }
        let endOffset = Int(readUInt32(data, at: cursor))
        cursor += 4
        guard endOffset > cursor, endOffset <= data.count else {
            throw SceneMdlPuppetAnimationReadError.invalidAnimationBounds
        }
        let count = Int(readUInt32(data, at: cursor))
        cursor += 4
        guard count > 0, count <= maxAnimationCount else {
            throw SceneMdlPuppetAnimationReadError.invalidAnimationCount(count)
        }

        var ids: Set<Int> = []
        var totalSamples = 0
        var animations: [SceneMdlPuppetAnimation] = []
        animations.reserveCapacity(count)
        for index in 0..<count {
            guard cursor + 8 <= endOffset else {
                throw SceneMdlPuppetAnimationReadError.invalidAnimationHeader(index)
            }
            let id = Int(readUInt32(data, at: cursor))
            let headerState = readUInt32(data, at: cursor + 4)
            cursor += 8
            guard id > 0, headerState == 0 else {
                throw SceneMdlPuppetAnimationReadError.invalidAnimationHeader(index)
            }
            guard ids.insert(id).inserted else {
                throw SceneMdlPuppetAnimationReadError.duplicateAnimationID(id)
            }
            let name = try readString(
                data: data,
                cursor: &cursor,
                bound: endOffset,
                maxBytes: maxNameBytes,
                animationID: id
            )
            guard name.isEmpty == false else {
                throw SceneMdlPuppetAnimationReadError.invalidAnimationName(id)
            }
            let mode = try readString(
                data: data,
                cursor: &cursor,
                bound: endOffset,
                maxBytes: maxModeBytes,
                animationID: id
            )
            guard mode == "loop" else {
                throw SceneMdlPuppetAnimationReadError.unsupportedAnimationMode(mode)
            }
            guard cursor + 16 <= endOffset else {
                throw SceneMdlPuppetAnimationReadError.invalidAnimationHeader(index)
            }
            let framesPerSecond = readFloat(data, at: cursor)
            let frameCount = Int(readUInt32(data, at: cursor + 4))
            let transformState = readUInt32(data, at: cursor + 8)
            let animationBoneCount = Int(readUInt32(data, at: cursor + 12))
            cursor += 16
            guard framesPerSecond.isFinite,
                  framesPerSecond > 0,
                  framesPerSecond <= 1_000,
                  frameCount > 0,
                  frameCount <= maxFrameCount,
                  transformState == 0 else {
                throw SceneMdlPuppetAnimationReadError.invalidAnimationHeader(index)
            }
            guard animationBoneCount == boneCount else {
                throw SceneMdlPuppetAnimationReadError.animationBoneCount(
                    animationID: id,
                    expected: boneCount,
                    actual: animationBoneCount
                )
            }
            let sampleCount = frameCount + 1
            totalSamples += sampleCount * boneCount
            guard totalSamples <= maxTotalSamples else {
                throw SceneMdlPuppetAnimationReadError.invalidAnimationBounds
            }
            let transforms = try readTransforms(
                data: data,
                cursor: &cursor,
                bound: endOffset,
                animationID: id,
                boneCount: boneCount,
                sampleCount: sampleCount
            )
            try readTrailer(
                data: data,
                cursor: &cursor,
                bound: endOffset,
                animationID: id,
                sampleCount: sampleCount,
                contract: trailerContract
            )
            animations.append(SceneMdlPuppetAnimation(
                id: id,
                name: name,
                mode: mode,
                framesPerSecond: framesPerSecond,
                frameCount: frameCount,
                transformsByBone: transforms
            ))
        }
        guard cursor == endOffset else {
            throw SceneMdlPuppetAnimationReadError.invalidAnimationBounds
        }
        return animations
    }

    private static func readTransforms(
        data: Data,
        cursor: inout Int,
        bound: Int,
        animationID: Int,
        boneCount: Int,
        sampleCount: Int
    ) throws -> [[SceneMdlPuppetAnimation.Transform]] {
        let expectedBytes = sampleCount * transformByteCount
        var tracks: [[SceneMdlPuppetAnimation.Transform]] = []
        tracks.reserveCapacity(boneCount)
        for boneIndex in 0..<boneCount {
            guard cursor + 8 <= bound,
                  readUInt32(data, at: cursor) == 0,
                  Int(readUInt32(data, at: cursor + 4)) == expectedBytes,
                  cursor + 8 + expectedBytes <= bound else {
                throw SceneMdlPuppetAnimationReadError.invalidTrack(
                    animationID: animationID,
                    boneIndex: boneIndex
                )
            }
            cursor += 8
            var transforms: [SceneMdlPuppetAnimation.Transform] = []
            transforms.reserveCapacity(sampleCount)
            for frameIndex in 0..<sampleCount {
                let transformOffset = cursor + frameIndex * transformByteCount
                var values: [Float] = []
                values.reserveCapacity(9)
                for component in 0..<9 {
                    let value = readFloat(data, at: transformOffset + component * 4)
                    guard value.isFinite, abs(value) <= maxAbsoluteTransformValue else {
                        throw SceneMdlPuppetAnimationReadError.invalidTransform(
                            animationID: animationID,
                            boneIndex: boneIndex,
                            frameIndex: frameIndex
                        )
                    }
                    values.append(value)
                }
                transforms.append(.init(
                    translation: SIMD3(values[0], values[1], values[2]),
                    rotation: SIMD3(values[3], values[4], values[5]),
                    scale: SIMD3(values[6], values[7], values[8])
                ))
            }
            cursor += expectedBytes
            tracks.append(transforms)
        }
        return tracks
    }

    private static func readTrailer(
        data: Data,
        cursor: inout Int,
        bound: Int,
        animationID: Int,
        sampleCount: Int,
        contract: TrailerContract
    ) throws {
        if contract == .legacyZeros10 {
            guard consumeZeros(data: data, cursor: &cursor, bound: bound, count: 10) else {
                throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
            }
            return
        }
        guard consumeZeros(data: data, cursor: &cursor, bound: bound, count: 5),
              cursor < bound else {
            throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
        }
        let hasAuxiliaryTrack = data[cursor]
        cursor += 1
        if hasAuxiliaryTrack == 1 {
            let expectedBytes = sampleCount * 4
            guard cursor + 16 + expectedBytes <= bound,
                  readUInt32(data, at: cursor) == 1,
                  readUInt32(data, at: cursor + 4) == auxiliaryTrackKey,
                  readUInt32(data, at: cursor + 8) == 1,
                  Int(readUInt32(data, at: cursor + 12)) == expectedBytes else {
                throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
            }
            cursor += 16
            for frameIndex in 0..<sampleCount {
                let value = readFloat(data, at: cursor + frameIndex * 4)
                guard value.isFinite, value >= 0, value <= 1.0001 else {
                    throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
                }
            }
            cursor += expectedBytes
        } else if hasAuxiliaryTrack != 0 {
            throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
        }
        guard consumeZeros(data: data, cursor: &cursor, bound: bound, count: 29) else {
            throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
        }
    }

    private static func readString(
        data: Data,
        cursor: inout Int,
        bound: Int,
        maxBytes: Int,
        animationID: Int
    ) throws -> String {
        let limit = min(bound, cursor + maxBytes + 1)
        guard cursor < limit,
              let end = data[cursor..<limit].firstIndex(of: 0),
              let value = String(data: data[cursor..<end], encoding: .utf8) else {
            throw SceneMdlPuppetAnimationReadError.invalidAnimationName(animationID)
        }
        cursor = end + 1
        return value
    }

    private static func consumeZeros(
        data: Data,
        cursor: inout Int,
        bound: Int,
        count: Int
    ) -> Bool {
        guard cursor + count <= bound else { return false }
        for offset in cursor..<(cursor + count) where data[offset] != 0 {
            return false
        }
        cursor += count
        return true
    }

    private static func matches(_ marker: Data, in data: Data, at offset: Int) -> Bool {
        guard offset >= 0, offset + marker.count <= data.count else { return false }
        return data[offset..<(offset + marker.count)].elementsEqual(marker)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { buffer in
            data.copyBytes(to: buffer, from: offset..<(offset + 4))
        }
        return UInt32(littleEndian: value)
    }

    private static func readFloat(_ data: Data, at offset: Int) -> Float {
        Float(bitPattern: readUInt32(data, at: offset))
    }
}
