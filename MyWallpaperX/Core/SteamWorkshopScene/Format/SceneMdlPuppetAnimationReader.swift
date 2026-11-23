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
    case unsupportedAnimationFlags(animationID: Int, rawFlags: UInt32)
    case invalidDerivedSource(Int)
    case unsupportedDerivedControl(animationID: Int, control: UInt32, rootSelector: Int32)
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
        case let .unsupportedAnimationFlags(id, flags):
            return "unsupported MDLA animation \(id) flags \(flags)"
        case let .invalidDerivedSource(id):
            return "invalid MDLA derived source for animation \(id)"
        case let .unsupportedDerivedControl(id, control, root):
            return "unsupported MDLA animation \(id) derived control \(control) root \(root)"
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

/// Version-matched MDLA reader. MDLV0013/MDLS0001/MDLA0001,
/// MDLV0016/MDLS0002/MDLA0003,
/// MDLV0017/MDLS0002/MDLA0004, MDLV0019/MDLS0002/MDLA0005,
/// MDLV0021/MDLS0003/MDLA0006 and
/// MDLV0023/MDLS0004/MDLA0006 share the same
/// bounded full-transform track records; their distinct trailer shapes remain
/// part of the version contract.
/// Tracks are ordered by MDLS bone index and contain frameCount + 1 full
/// transforms. Real assets vary translation, rotation, and scale, so all three
/// components are retained. The three authored playback modes are kept in the
/// loss-preserving IR; the evaluator applies their bounded frame schedule.
nonisolated enum SceneMdlPuppetAnimationReader {
    private enum TrailerContract: Equatable {
        case perBoneAuxiliary
        case legacyZeros(Int)
        case perBoneAlphaZeros29
        case modernAuxiliary
        case modernBoundsAuxiliary
    }

    private struct VersionContract {
        let skeletonMarker: Data
        let animationMarker: Data
        let trailer: TrailerContract
    }

    private struct MorphShape {
        let positions: [SIMD3<Float>]
        let coverages: [Float]?
    }

    private struct ImageMorphs {
        let addresses: [Int]
        let groups: [UInt32: [MorphShape]]
    }

    private static let versionContracts = [
        "MDLV0013": VersionContract(
            skeletonMarker: Data("MDLS0001\0".utf8),
            animationMarker: Data("MDLA0001\0".utf8),
            trailer: .legacyZeros(4)
        ),
        "MDLV0016": VersionContract(
            skeletonMarker: Data("MDLS0002\0".utf8),
            animationMarker: Data("MDLA0003\0".utf8),
            trailer: .perBoneAuxiliary
        ),
        "MDLV0017": VersionContract(
            skeletonMarker: Data("MDLS0002\0".utf8),
            animationMarker: Data("MDLA0004\0".utf8),
            trailer: .legacyZeros(10)
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
            trailer: .modernBoundsAuxiliary
        ),
    ]
    private static let knownAnimationMarkers = [
        Data("MDLA0001\0".utf8),
        Data("MDLA0003\0".utf8),
        Data("MDLA0004\0".utf8),
        Data("MDLA0005\0".utf8),
        Data("MDLA0006\0".utf8),
    ]
    private static let attachmentMarker = Data("MDAT0001\0".utf8)
    private static let morphFamily = Data("MDMP".utf8)
    private static let morphMarker = Data("MDMP0001\0".utf8)
    private static let markerSize = 9
    private static let maxBoneCount = 4096
    private static let maxAnimationCount = 1024
    private static let maxFrameCount = 60000
    private static let maxNameBytes = 1024
    private static let maxModeBytes = 64
    private static let maxTotalSamples = 8_000_000
    private static let transformByteCount = 36
    private static let maxAbsoluteTransformValue: Float = 1_000_000
    // Project preparation budgets, not official file-format limits.
    private static let maxEventsPerAnimation = 1024
    private static let maxTotalEvents = 4096
    private static let maxEventPayloadBytes = 4096

    static func read(
        data rawData: Data, imageMorphLayout: SceneMdlPuppetAnimationSet.ImageMorphLayout? = nil
    ) throws -> SceneMdlPuppetAnimationSet? {
        let data = rawData.startIndex == 0 ? rawData : Data(rawData)
        let presentMarkers = knownAnimationMarkers.compactMap { marker in
            data.range(of: marker).map { (marker: marker, offset: $0.lowerBound) }
        }
        guard presentMarkers.isEmpty == false else {
            return nil
        }
        let magic = String(decoding: data.prefix(8), as: UTF8.self)
        guard let contract = versionContracts[magic],
              let animationOffset = presentMarkers.first(where: {
                  $0.marker == contract.animationMarker
              })?.offset
        else {
            throw SceneMdlPuppetAnimationReadError.unsupportedMagic(magic)
        }
        let animationHeader = animationOffset + markerSize
        let endOffset = animationHeader + 8 <= data.count
            ? Int(readUInt32(data, at: animationHeader)) : 0
        // Optional MDMP starts only at the declared MDLA boundary. Its opaque
        // payload is outside the version-matched animation-marker search.
        let hasMorphTail = imageMorphLayout != nil && contract.trailer == .modernBoundsAuxiliary
            && endOffset >= animationHeader + 8 && matches(morphFamily, in: data, at: endOffset)
        guard presentMarkers.count == 1 || (hasMorphTail && presentMarkers.allSatisfy {
            $0.marker == contract.animationMarker || $0.offset >= endOffset
        }) else {
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
        let imageMorphs: ImageMorphs?
        if hasMorphTail, let imageMorphLayout {
            imageMorphs = readImageMorphs(data, at: endOffset, layout: imageMorphLayout,
                                         meshBound: skeletonOffset)
        } else {
            imageMorphs = nil
        }
        let records = try readAnimations(
            data: data,
            headerOffset: animationHeader,
            endOffset: endOffset,
            boneCount: boneCount,
            trailerContract: contract.trailer,
            hasMorphTail: hasMorphTail,
            morphGroups: imageMorphs?.groups
        )
        // Exported source-take IDs and addressable clip IDs belong to distinct domains.
        let derived = records.filter { $0.derivedSource != nil }
        let animations = derived.isEmpty ? records : derived
        var ids: Set<Int> = []
        for animation in animations where !ids.insert(animation.id).inserted {
            throw SceneMdlPuppetAnimationReadError.duplicateAnimationID(animation.id)
        }
        return SceneMdlPuppetAnimationSet(
            boneCount: boneCount, animations: animations, records: records,
            morphVertexAddresses: imageMorphs.flatMap { morphs in
                animations.contains { !$0.morphTargets.isEmpty } ? morphs.addresses : nil
            }
        )
    }

    private static func readImageMorphs(
        _ data: Data, at offset: Int, layout: SceneMdlPuppetAnimationSet.ImageMorphLayout,
        meshBound: Int
    ) -> ImageMorphs? {
        var cursor = offset + markerSize + 4
        // In the qualified MDLV0023 84-byte stream, the fourth position
        // component is independent of the trailing texture coordinates.
        guard cursor <= data.count, matches(morphMarker, in: data, at: offset),
              layout.stride == 84, layout.count > 0, layout.vertexOffset >= 0,
              layout.vertexOffset <= meshBound,
              layout.count <= (meshBound - layout.vertexOffset) / layout.stride else { return nil }
        let end = Int(readUInt32(data, at: offset + markerSize))
        guard end > cursor, end <= data.count else { return nil }
        let rowLimit = Float((end - cursor) / 8)
        var addresses: [Int] = []
        addresses.reserveCapacity(layout.count)
        var maxAddress = 0
        for vertex in 0 ..< layout.count {
            let value = readFloat(data, at: layout.vertexOffset + vertex * layout.stride + 12)
            guard value >= 0, value <= rowLimit, value == value.rounded(.towardZero) else {
                return nil
            }
            let address = Int(value)
            addresses.append(address)
            maxAddress = max(maxAddress, address)
        }
        guard maxAddress > 0 else { return nil }

        var groups: [UInt32: [MorphShape]] = [:]
        var seenLinks: Set<UInt32> = []
        while cursor < end {
            guard cursor + 10 <= end else { return nil }
            let count = Int(readUInt16(data, at: cursor))
            let link = readUInt32(data, at: cursor + 2)
            let gain = Float(bitPattern: link)
            let flags = readUInt16(data, at: cursor + 8)
            let unique = seenLinks.insert(link).inserted
            cursor += 10
            var shapes: [MorphShape]? = count > 0 && flags == 0 && unique && gain.isFinite ? [] : nil
            for _ in 0 ..< count {
                guard readMorphShape(data, cursor: &cursor, end: end, gain: gain,
                                     minRows: maxAddress, shapes: &shapes) else {
                    return nil
                }
            }
            groups[link] = shapes
        }
        return ImageMorphs(addresses: addresses, groups: groups)
    }

    private static func readMorphShape(
        _ data: Data, cursor: inout Int, end: Int, gain: Float, minRows: Int,
        shapes: inout [MorphShape]?
    ) -> Bool {
        let nameStart = cursor + 8
        guard nameStart < end, let nameEnd = data[nameStart ..< end].firstIndex(of: 0),
              nameEnd + 5 <= end else { return false }
        let pointBytes = Int(readUInt32(data, at: nameEnd + 1))
        let pointOffset = nameEnd + 5
        let coverageHeader = pointOffset + pointBytes
        guard coverageHeader + 4 <= end else { return false }
        let coverageBytes = Int(readUInt32(data, at: coverageHeader))
        let coverageOffset = coverageHeader + 4
        guard coverageOffset + coverageBytes <= end else { return false }
        cursor = coverageOffset + coverageBytes

        guard shapes != nil else { return true }
        let rowCount = pointBytes / 6
        guard pointBytes % 6 == 0, rowCount >= minRows, coverageBytes == rowCount * 2 else {
            shapes = nil
            return true
        }
        let fullCoverage = UInt16(Int16.max)
        let fullScale = Float(fullCoverage)
        var positions: [SIMD3<Float>] = []
        var coverages: [Float]?
        positions.reserveCapacity(rowCount)
        for vertex in 0 ..< rowCount {
            let point = pointOffset + vertex * 6
            let x = Int16(bitPattern: readUInt16(data, at: point))
            let y = Int16(bitPattern: readUInt16(data, at: point + 2))
            let z = Int16(bitPattern: readUInt16(data, at: point + 4))
            let normalized = SIMD3<Float>(Float(x), Float(y), Float(z)) / fullScale
            positions.append(SIMD3(max(-1, normalized.x), max(-1, normalized.y),
                                   max(-1, normalized.z)) * gain)
            let coverage = readUInt16(data, at: coverageOffset + vertex * 2)
            guard coverage <= fullCoverage else {
                shapes = nil
                return true
            }
            if coverage != fullCoverage, coverages == nil {
                coverages = Array(repeating: 1, count: vertex)
                coverages?.reserveCapacity(rowCount)
            }
            coverages?.append(Float(coverage) / fullScale)
        }
        shapes?.append(MorphShape(positions: positions, coverages: coverages))
        return true
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
        headerOffset: Int,
        endOffset: Int,
        boneCount: Int,
        trailerContract: TrailerContract,
        hasMorphTail: Bool,
        morphGroups: [UInt32: [MorphShape]]?
    ) throws -> [SceneMdlPuppetAnimation] {
        var cursor = headerOffset + 4
        guard endOffset > cursor, endOffset <= data.count else {
            throw SceneMdlPuppetAnimationReadError.invalidAnimationBounds
        }
        let count = Int(readUInt32(data, at: cursor))
        cursor += 4
        guard count > 0, count <= maxAnimationCount else {
            throw SceneMdlPuppetAnimationReadError.invalidAnimationCount(count)
        }

        var totalSamples = 0
        var totalEvents = 0
        var requiresPhysicalEnd = false
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
            let rawMode = try readString(
                data: data,
                cursor: &cursor,
                bound: endOffset,
                maxBytes: maxModeBytes,
                animationID: id
            )
            guard cursor + 16 <= endOffset else {
                throw SceneMdlPuppetAnimationReadError.invalidAnimationHeader(index)
            }
            let framesPerSecond = readFloat(data, at: cursor)
            let frameCount = Int(readUInt32(data, at: cursor + 4))
            let rawFlags = readUInt32(data, at: cursor + 8)
            let animationBoneCount = Int(readUInt32(data, at: cursor + 12))
            cursor += 16
            guard framesPerSecond.isFinite,
                  framesPerSecond > 0,
                  framesPerSecond <= 1000,
                  frameCount > 0,
                  frameCount <= maxFrameCount
            else {
                throw SceneMdlPuppetAnimationReadError.invalidAnimationHeader(index)
            }
            let isDerived = trailerContract == .modernBoundsAuxiliary && rawFlags == 0x401
            guard rawFlags == 0 || isDerived else {
                throw SceneMdlPuppetAnimationReadError.unsupportedAnimationFlags(
                    animationID: id, rawFlags: rawFlags
                )
            }
            // Qualified imported clips initialize empty mode as loop; preserve the wire value.
            let mode = isDerived && rawMode.isEmpty ? "loop" : rawMode
            guard mode == "loop" || mode == "mirror" || mode == "single" else {
                throw SceneMdlPuppetAnimationReadError.unsupportedAnimationMode(rawMode)
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
                    || trailerContract == .modernBoundsAuxiliary
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
                isDerived: isDerived,
                eventBudget: maxTotalEvents - totalEvents,
                contract: trailerContract,
                morphGroups: morphGroups
            )
            if let source = trailer.derivedSource {
                guard source.sourceRecordOrdinal < animations.count,
                      animations[source.sourceRecordOrdinal].derivedSource == nil,
                      source.firstFrame < source.endFrame,
                      source.endFrame <= animations[source.sourceRecordOrdinal].frameCount,
                      source.endFrame - source.firstFrame == frameCount else {
                    throw SceneMdlPuppetAnimationReadError.invalidDerivedSource(id)
                }
            }
            requiresPhysicalEnd = requiresPhysicalEnd || isDerived
                || (trailer.bounds.map { $0.minimum != .zero || $0.maximum != .zero } ?? false)
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
                events: trailer.events,
                bounds: trailer.bounds,
                hasAuxiliaryScalarTrack: trailer.hasAuxiliaryScalarTrack,
                hasPostBoundsScalarTrack: trailer.hasPostBoundsScalarTrack,
                recordOrdinal: index, rawMode: rawMode, rawFlags: rawFlags,
                derivedSource: trailer.derivedSource, morphTargets: trailer.morphTargets
            ))
        }
        guard cursor == endOffset else {
            throw SceneMdlPuppetAnimationReadError.invalidAnimationBounds
        }
        if requiresPhysicalEnd, !hasMorphTail {
            guard endOffset == data.count
                || (data.count - endOffset == 1 && data[endOffset] == 0) else {
                throw SceneMdlPuppetAnimationReadError.invalidAnimationBounds
            }
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
        isDerived: Bool,
        eventBudget: Int,
        contract: TrailerContract,
        morphGroups: [UInt32: [MorphShape]]?
    ) throws -> (
        alphaByBone: [[Float]]?, events: [SceneMdlPuppetAnimation.Event],
        bounds: SceneMdlPuppetAnimation.Bounds?, hasAuxiliaryScalarTrack: Bool,
        hasPostBoundsScalarTrack: Bool,
        derivedSource: SceneMdlPuppetAnimation.DerivedSource?,
        morphTargets: [SceneMdlPuppetAnimation.MorphTarget]
    ) {
        if case let .legacyZeros(count) = contract {
            guard consumeZeros(data: data, cursor: &cursor, bound: bound, count: count) else {
                throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
            }
            return (nil, [], nil, false, false, nil, [])
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
            return (alphaByBone, [], nil, false, false, nil, [])
        }
        if contract == .perBoneAlphaZeros29 {
            guard consumeZeros(data: data, cursor: &cursor, bound: bound, count: 29) else {
                throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
            }
            return (alphaByBone, [], nil, false, false, nil, [])
        }
        guard cursor < bound else {
            throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
        }
        let hasAuxiliaryTrack = data[cursor]
        cursor += 1
        let morphTargets: [SceneMdlPuppetAnimation.MorphTarget]
        if hasAuxiliaryTrack == 1 {
            morphTargets = try readPreBoundsCurves(data, cursor: &cursor, bound: bound,
                animationID: animationID, sampleCount: sampleCount, groups: morphGroups)
        } else {
            guard hasAuxiliaryTrack == 0 else {
                throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
            }
            morphTargets = []
        }
        let bounds: SceneMdlPuppetAnimation.Bounds?
        let hasPostBoundsScalarTrack: Bool
        if contract == .modernBoundsAuxiliary {
            guard cursor + 25 <= bound else {
                throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
            }
            let values = (0 ..< 6).map { readFloat(data, at: cursor + $0 * 4) }
            guard values.allSatisfy({ $0.isFinite && abs($0) <= maxAbsoluteTransformValue }),
                  (0 ..< 3).allSatisfy({ values[$0] <= values[$0 + 3] }),
                  data[cursor + 24] <= 1 else {
                throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
            }
            bounds = .init(minimum: SIMD3(values[0], values[1], values[2]),
                maximum: SIMD3(values[3], values[4], values[5]))
            hasPostBoundsScalarTrack = data[cursor + 24] == 1
            cursor += 25
            if hasPostBoundsScalarTrack {
                let expectedBytes = sampleCount * 4
                for _ in 0 ..< boneCount {
                    guard cursor + 8 <= bound,
                          readUInt32(data, at: cursor) == 0,
                          Int(readUInt32(data, at: cursor + 4)) == expectedBytes,
                          cursor + 8 + expectedBytes <= bound else {
                        throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
                    }
                    // No pose consumer reads this channel. Validate framing,
                    // without scanning or assigning semantics to its payload.
                    cursor += 8 + expectedBytes
                }
            }
        } else {
            // MDLV0021 retains its verified zero fields and absent scalar curve.
            guard consumeZeros(data: data, cursor: &cursor, bound: bound, count: 25) else {
                throw SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
            }
            bounds = nil
            hasPostBoundsScalarTrack = false
        }
        let derivedSource: SceneMdlPuppetAnimation.DerivedSource?
        if isDerived {
            guard cursor + 18 <= bound else {
                throw SceneMdlPuppetAnimationReadError.invalidDerivedSource(animationID)
            }
            let source = SceneMdlPuppetAnimation.DerivedSource(
                sourceRecordOrdinal: Int(data[cursor]) | Int(data[cursor + 1]) << 8,
                firstFrame: Int(readUInt32(data, at: cursor + 2)),
                endFrame: Int(readUInt32(data, at: cursor + 6)),
                control: readUInt32(data, at: cursor + 10),
                rootSelector: Int32(bitPattern: readUInt32(data, at: cursor + 14))
            )
            cursor += 18
            guard source.control == 0, source.rootSelector == -1 else {
                throw SceneMdlPuppetAnimationReadError.unsupportedDerivedControl(
                    animationID: animationID, control: source.control,
                    rootSelector: source.rootSelector
                )
            }
            derivedSource = source
        } else {
            derivedSource = nil
        }
        let events = try readEvents(
            data: data, cursor: &cursor, bound: bound, animationID: animationID,
            frameCount: frameCount, mode: mode, eventBudget: eventBudget
        )
        return (alphaByBone, events, bounds, hasAuxiliaryTrack == 1,
                hasPostBoundsScalarTrack, derivedSource, morphTargets)
    }

    private static func readPreBoundsCurves(
        _ data: Data, cursor: inout Int, bound: Int, animationID: Int, sampleCount: Int,
        groups: [UInt32: [MorphShape]]?
    ) throws -> [SceneMdlPuppetAnimation.MorphTarget] {
        let failure = SceneMdlPuppetAnimationReadError.invalidAuxiliaryTrack(animationID)
        guard cursor + 4 <= bound else { throw failure }
        let eventCount = Int(readUInt32(data, at: cursor))
        cursor += 4
        guard eventCount > 0 else { throw failure }
        let sampleBytes = sampleCount * 4
        // Only one linkage group per clip has qualified deformation semantics.
        var targets: [SceneMdlPuppetAnimation.MorphTarget]? = eventCount == 1
            ? groups.map { _ in [] } : nil
        for _ in 0 ..< eventCount {
            guard cursor + 8 <= bound else { throw failure }
            let curveCount = Int(readUInt16(data, at: cursor + 4))
            guard curveCount > 0 else { throw failure }
            let shapes: [MorphShape]?
            if targets != nil, let groups {
                let link = readUInt32(data, at: cursor)
                shapes = groups[link]
                if shapes?.count != curveCount || readUInt16(data, at: cursor + 6) != 0 {
                    targets = nil
                }
            } else {
                shapes = nil
            }
            cursor += 8
            for curve in 0 ..< curveCount {
                // The first curve ID is implicit, and each later ID names its group ordinal.
                let lengthOffset = curve == 0 ? cursor : cursor + 2
                let samplesOffset = lengthOffset + 4
                let curveEnd = samplesOffset + sampleBytes
                guard curveEnd <= bound,
                      Int(readUInt32(data, at: lengthOffset)) == sampleBytes else { throw failure }
                if let shapes, targets != nil {
                    if curve > 0, Int(readUInt16(data, at: cursor)) != curve {
                        targets = nil
                    } else {
                        var weights: [Float] = []
                        weights.reserveCapacity(sampleCount)
                        for offset in stride(from: samplesOffset, to: curveEnd, by: 4) {
                            let weight = readFloat(data, at: offset)
                            guard weight.isFinite else { break }
                            weights.append(weight)
                        }
                        if weights.count == sampleCount {
                            targets?.append(.init(weights: weights, positions: shapes[curve].positions,
                                                  coverages: shapes[curve].coverages))
                        } else {
                            targets = nil
                        }
                    }
                }
                cursor = curveEnd
            }
        }
        return targets ?? []
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

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func readFloat(_ data: Data, at offset: Int) -> Float {
        Float(bitPattern: readUInt32(data, at: offset))
    }
}
