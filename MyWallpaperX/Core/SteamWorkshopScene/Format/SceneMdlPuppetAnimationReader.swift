import Foundation
import CoreFoundation

enum SceneMdlPuppetAnimationReadError: Error, CustomStringConvertible, Equatable {
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
    case invalidEventTrack(Int)

    nonisolated var description: String {
        switch self {
        case let .unsupportedMagic(magic):
            return "unsupported animation mdl magic \(magic)"
        case .skeletonBlockMissing:
            return "MDLA requires the version-matched preceding MDLS block"
        case .invalidSkeletonBounds:
            return "invalid version-matched MDLS animation boundary"
        case let .invalidBoneCount(count):
            return "invalid animation bone count \(count)"
        case .invalidAnimationBounds:
            return "invalid version-matched MDLA bounds"
        case let .invalidAnimationCount(count):
            return "invalid MDLA animation count \(count)"
        case let .invalidAnimationHeader(index):
            return "invalid MDLA animation header \(index)"
        case let .duplicateAnimationID(id):
            return "duplicate MDLA animation id \(id)"
        case let .invalidAnimationName(id):
            return "invalid MDLA animation name for id \(id)"
        case let .unsupportedAnimationMode(mode):
            return "unsupported MDLA animation mode \(mode)"
        case let .animationBoneCount(id, expected, actual):
            return "animation \(id) has \(actual) bones; expected \(expected)"
        case let .invalidTrack(id, boneIndex):
            return "invalid animation \(id) track for bone \(boneIndex)"
        case let .invalidTransform(id, boneIndex, frameIndex):
            return "invalid animation \(id) transform at bone \(boneIndex) frame \(frameIndex)"
        case let .invalidAuxiliaryTrack(id):
            return "invalid verified auxiliary track for animation \(id)"
        case let .invalidEventTrack(id):
            return "invalid bounded event record for animation \(id)"
        }
    }
}

/// Restricted version-matched MDLA reader. MDLV0016/MDLS0002/MDLA0003,
/// MDLV0017/MDLS0002/MDLA0004, MDLV0019/MDLS0002/MDLA0005,
/// MDLV0021/MDLS0003/MDLA0006 and
/// MDLV0023/MDLS0004/MDLA0006 share the same
/// bounded full-transform track records; their distinct trailer shapes remain
/// part of the version contract.
/// Tracks are ordered by MDLS bone index and contain frameCount + 1 full
/// transforms. Real assets vary translation, rotation, and scale, so all three
/// components are retained. The three authored playback modes are kept in the
/// loss-preserving IR; the evaluator applies their bounded frame schedule.
enum SceneMdlPuppetAnimationReader {
    private enum TrailerContract {
        case perBoneAuxiliary
        case legacyZeros10
        case perBoneAlphaZeros29
        case modernAuxiliary
    }

    private struct VersionContract {
        let skeletonMarker: Data
        let animationMarker: Data
        let trailer: TrailerContract
    }

    private static let versionContracts = [
        "MDLV0016": VersionContract(
            skeletonMarker: Data("MDLS0002\0".utf8),
            animationMarker: Data("MDLA0003\0".utf8),
            trailer: .perBoneAuxiliary
        ),
        "MDLV0017": VersionContract(
            skeletonMarker: Data("MDLS0002\0".utf8),
            animationMarker: Data("MDLA0004\0".utf8),
            trailer: .legacyZeros10
        ),
        "MDLV0019": VersionContract(
            skeletonMarker: Data("MDLS0002\0".utf8),
            animationMarker: Data("MDLA0005\0".utf8),
            trailer: .perBoneAlphaZeros29
        ),
        "MDLV0021": VersionContract(
            skeletonMarker: Data("MDLS0003\0".utf8),
            animationMarker: Data("MDLA0006\0".utf8),
            trailer: .modernAuxiliary
        ),
        "MDLV0023": VersionContract(
            skeletonMarker: Data("MDLS0004\0".utf8),
            animationMarker: Data("MDLA0006\0".utf8),
            trailer: .modernAuxiliary
        ),
    ]
    private static let knownAnimationMarkers = [
        Data("MDLA0003\0".utf8),
        Data("MDLA0004\0".utf8),
        Data("MDLA0005\0".utf8),
        Data("MDLA0006\0".utf8),
    ]
    private static let attachmentMarker = Data("MDAT0001\0".utf8)
    private static let markerSize = 9
    private static let maxBoneCount = 4096
    private static let maxAnimationCount = 1024
    private static let maxFrameCount = 60000
    private static let maxNameBytes = 1024
    private static let maxModeBytes = 64
    private static let maxTotalSamples = 8_000_000
    private static let transformByteCount = 36
    private static let maxAbsoluteTransformValue: Float = 1_000_000
    private static let auxiliaryTrackKey: UInt32 = 0x418A_55D5
    // Project preparation budgets, not official file-format limits.
    private static let maxEventsPerAnimation = 1024
    private static let maxTotalEvents = 4096
    private static let maxEventPayloadBytes = 4096

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
              let animationOffset = data.range(of: contract.animationMarker)?.lowerBound
        else {
            throw SceneMdlPuppetAnimationReadError.unsupportedMagic(magic)
        }
        guard let skeletonOffset = data.range(of: contract.skeletonMarker)?.lowerBound,
              skeletonOffset < animationOffset
        else {
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
                  Int(readUInt32(data, at: skeletonEnd + markerSize)) == animationOffset
            else {
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
        var totalEvents = 0
        var animations: [SceneMdlPuppetAnimation] = []
        animations.reserveCapacity(count)
        for index in 0 ..< count {
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
            guard mode == "loop" || mode == "mirror" || mode == "single" else {
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
                  framesPerSecond <= 1000,
                  frameCount > 0,
                  frameCount <= maxFrameCount,
                  transformState == 0
            else {
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
                sampleCount: sampleCount,
                permitsReferenceCandidates: trailerContract == .modernAuxiliary
            )
            let trailer = try readTrailer(
                data: data,
                cursor: &cursor,
                bound: endOffset,
                animationID: id,
                boneCount: boneCount,
                sampleCount: sampleCount,
                frameCount: frameCount,
                mode: mode,
                eventBudget: maxTotalEvents - totalEvents,
                contract: trailerContract
            )
            totalEvents += trailer.events.count
            animations.append(SceneMdlPuppetAnimation(
                id: id,
                name: name,
                mode: mode,
                framesPerSecond: framesPerSecond,
                frameCount: frameCount,
                transformsByBone: transforms.tracks,
                transformTrackStates: transforms.states,
                alphaByBone: trailer.alphaByBone,
                events: trailer.events
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
        sampleCount: Int,
        permitsReferenceCandidates: Bool
    ) throws -> (tracks: [[SceneMdlPuppetAnimation.Transform]],
                 states: [SceneMdlPuppetAnimation.TransformTrackState]) {
        let expectedBytes = sampleCount * transformByteCount
        var tracks: [[SceneMdlPuppetAnimation.Transform]] = []
        tracks.reserveCapacity(boneCount)
        var states: [SceneMdlPuppetAnimation.TransformTrackState] = []
        states.reserveCapacity(boneCount)
        for boneIndex in 0 ..< boneCount {
            guard cursor + 8 <= bound,
                  let state = SceneMdlPuppetAnimation.TransformTrackState(
                      rawValue: readUInt32(data, at: cursor)
                  ),
                  state == .sampled || permitsReferenceCandidates,
                  Int(readUInt32(data, at: cursor + 4)) == expectedBytes,
                  cursor + 8 + expectedBytes <= bound
            else {
                throw SceneMdlPuppetAnimationReadError.invalidTrack(
                    animationID: animationID,
                    boneIndex: boneIndex
                )
            }
            cursor += 8
            var transforms: [SceneMdlPuppetAnimation.Transform] = []
            transforms.reserveCapacity(sampleCount)
            for frameIndex in 0 ..< sampleCount {
                let transformOffset = cursor + frameIndex * transformByteCount
                var values: [Float] = []
                values.reserveCapacity(9)
                for component in 0 ..< 9 {
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
            guard state != .referenceCandidate
                || transforms.dropFirst().allSatisfy({ $0 == transforms[0] }) else {
                throw SceneMdlPuppetAnimationReadError.invalidTrack(
                    animationID: animationID, boneIndex: boneIndex
                )
            }
            cursor += expectedBytes
            tracks.append(transforms)
            states.append(state)
        }
        return (tracks, states)
    }

    private static func readTrailer(
        data: Data,
        cursor: inout Int,
        bound: Int,
        animationID: Int,
        boneCount: Int,
        sampleCount: Int,
        frameCount: Int,
        mode: String,
        eventBudget: Int,
        contract: TrailerContract
    ) throws -> (alphaByBone: [[Float]]?, events: [SceneMdlPuppetAnimation.Event]) {
        if contract == .legacyZeros10 {
            guard consumeZeros(data: data, cursor: &cursor, bound: bound, count: 10) else {
                throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
            }
            return (nil, [])
        }
        let alphaByBone = try readPerBoneAlphaTracks(
            data: data,
            cursor: &cursor,
            bound: bound,
            animationID: animationID,
            boneCount: boneCount,
            sampleCount: sampleCount
        )
        if contract == .perBoneAuxiliary {
            guard consumeZeros(data: data, cursor: &cursor, bound: bound, count: 4) else {
                throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
            }
            return (alphaByBone, [])
        }
        if contract == .perBoneAlphaZeros29 {
            guard consumeZeros(data: data, cursor: &cursor, bound: bound, count: 29) else {
                throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
            }
            return (alphaByBone, [])
        }
        guard cursor < bound else {
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
                  Int(readUInt32(data, at: cursor + 12)) == expectedBytes
            else {
                throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
            }
            cursor += 16
            for frameIndex in 0 ..< sampleCount {
                let value = readFloat(data, at: cursor + frameIndex * 4)
                guard value.isFinite, value >= 0, value <= 1.0001 else {
                    throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
                }
            }
            cursor += expectedBytes
        } else if hasAuxiliaryTrack != 0 {
            throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
        }
        // Keep the verified zero AABB and absent scalar-curve profile.
        guard consumeZeros(data: data, cursor: &cursor, bound: bound, count: 25) else {
            throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
        }
        let events = try readEvents(
            data: data, cursor: &cursor, bound: bound, animationID: animationID,
            frameCount: frameCount, mode: mode, eventBudget: eventBudget
        )
        return (alphaByBone, events)
    }

    private static func readEvents(
        data: Data, cursor: inout Int, bound: Int, animationID: Int,
        frameCount: Int, mode: String, eventBudget: Int
    ) throws -> [SceneMdlPuppetAnimation.Event] {
        guard cursor + 4 <= bound else {
            throw SceneMdlPuppetAnimationReadError.invalidEventTrack(animationID)
        }
        let count = Int(readUInt32(data, at: cursor))
        cursor += 4
        if count == 0 { return [] }
        guard mode == "loop", count <= maxEventsPerAnimation,
              count <= eventBudget, count <= (bound - cursor) / 5 else {
            throw SceneMdlPuppetAnimationReadError.invalidEventTrack(animationID)
        }
        var events: [SceneMdlPuppetAnimation.Event] = []
        events.reserveCapacity(count)
        for _ in 0 ..< count {
            guard cursor + 4 <= bound else {
                throw SceneMdlPuppetAnimationReadError.invalidEventTrack(animationID)
            }
            let recordedTime = readFloat(data, at: cursor)
            cursor += 4
            guard recordedTime.isFinite else {
                throw SceneMdlPuppetAnimationReadError.invalidEventTrack(animationID)
            }
            let payload: String
            do {
                payload = try readString(
                    data: data, cursor: &cursor, bound: bound,
                    maxBytes: maxEventPayloadBytes, animationID: animationID
                )
            } catch {
                throw SceneMdlPuppetAnimationReadError.invalidEventTrack(animationID)
            }
            guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)),
                  let fields = object as? [String: Any],
                  Set(fields.keys) == Set(["name", "frame"]),
                  let name = fields["name"] as? String,
                  !name.isEmpty, name.utf8.count <= maxNameBytes, !name.contains("\0"),
                  let number = fields["frame"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let frame = Int(exactly: number.doubleValue),
                  frame > 0, frame < frameCount else {
                throw SceneMdlPuppetAnimationReadError.invalidEventTrack(animationID)
            }
            events.append(.init(name: name, frame: frame, recordedTime: recordedTime))
        }
        return events
    }

    private static func readPerBoneAlphaTracks(
        data: Data,
        cursor: inout Int,
        bound: Int,
        animationID: Int,
        boneCount: Int,
        sampleCount: Int
    ) throws -> [[Float]]? {
        guard consumeZeros(data: data, cursor: &cursor, bound: bound, count: 4),
              cursor < bound
        else {
            throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
        }
        let hasAuxiliaryTracks = data[cursor]
        cursor += 1
        if hasAuxiliaryTracks == 0 { return nil }
        guard hasAuxiliaryTracks == 1 else {
            throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
        }
        let expectedBytes = sampleCount * 4
        var tracks: [[Float]] = []
        tracks.reserveCapacity(boneCount)
        for _ in 0 ..< boneCount {
            guard cursor + 8 + expectedBytes <= bound,
                  readUInt32(data, at: cursor) == 0,
                  Int(readUInt32(data, at: cursor + 4)) == expectedBytes
            else {
                throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
            }
            cursor += 8
            var values: [Float] = []
            values.reserveCapacity(sampleCount)
            for frameIndex in 0 ..< sampleCount {
                let value = readFloat(data, at: cursor + frameIndex * 4)
                guard value.isFinite, value >= 0, value <= 1.0001 else {
                    throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
                }
                values.append(value)
            }
            cursor += expectedBytes
            tracks.append(values)
        }
        return tracks
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
              let end = data[cursor ..< limit].firstIndex(of: 0),
              let value = String(data: data[cursor ..< end], encoding: .utf8)
        else {
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
        for offset in cursor ..< (cursor + count) where data[offset] != 0 {
            return false
        }
        cursor += count
        return true
    }

    private static func matches(_ marker: Data, in data: Data, at offset: Int) -> Bool {
        guard offset >= 0, offset + marker.count <= data.count else { return false }
        return data[offset ..< (offset + marker.count)].elementsEqual(marker)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { buffer in
            data.copyBytes(to: buffer, from: offset ..< (offset + 4))
        }
        return UInt32(littleEndian: value)
    }

    private static func readFloat(_ data: Data, at offset: Int) -> Float {
        Float(bitPattern: readUInt32(data, at: offset))
    }
}
