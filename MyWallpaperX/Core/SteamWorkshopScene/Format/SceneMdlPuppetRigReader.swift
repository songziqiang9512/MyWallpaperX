import Foundation
import CoreFoundation

nonisolated struct SceneMdlPuppetRig: Equatable {
    struct Bone: Equatable {
        /// Authored bone identity is part of the Puppet scripting contract.
        /// Keep the UTF-8 name beside the validated hierarchy instead of
        /// discarding it while reading the MDLS record.
        let name: String
        let parentIndex: Int
        let translationPhysics: TranslationPhysics?
        let physicsDiagnostic: String?
        let bindLocalMatrixColumnMajor: [Float]

        init(
            name: String = "",
            parentIndex: Int,
            bindLocalMatrixColumnMajor: [Float],
            translationPhysics: TranslationPhysics? = nil,
            physicsDiagnostic: String? = nil
        ) {
            self.name = name
            self.translationPhysics = translationPhysics
            self.physicsDiagnostic = physicsDiagnostic
            self.parentIndex = parentIndex
            self.bindLocalMatrixColumnMajor = bindLocalMatrixColumnMajor
        }
    }

    struct TranslationPhysics: Equatable {
        let spring: Bool
        let stiffness: Float
        let friction: Float
        let inertia: Float
        let maxDistance: Float
        let gravity: SIMD3<Float>

        init(spring: Bool, stiffness: Float, friction: Float, inertia: Float,
             maxDistance: Float, gravity: SIMD3<Float> = .zero) {
            self.spring = spring
            self.stiffness = stiffness
            self.friction = friction
            self.inertia = inertia
            self.maxDistance = maxDistance
            self.gravity = gravity
        }

        static func read(metadata: Data) throws -> Self? {
            guard !metadata.isEmpty else { return nil }
            guard let object = (try? JSONSerialization.jsonObject(with: metadata)) as? [String: Any]
            else { throw SceneMdlPuppetRigReadError.invalidPhysicsMetadata }
            let spring = object["se"] as? Bool == true
            let rigid = object["re"] as? Bool == true
            guard spring || rigid, object["t"] as? Bool == true else { return nil }
            // This slice admits the documented translational spring/rigid
            // mode. Other enabled solvers cannot silently become this one.
            guard object["r"] as? Bool != true, object["ik"] as? Bool != true else {
                throw SceneMdlPuppetRigReadError.unsupportedPhysicsMode
            }
            func finite(_ key: String, fallback: Float) throws -> Float {
                guard let value = object[key] else { return fallback }
                guard let number = value as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.floatValue.isFinite, number.doubleValue >= 0 else {
                    throw SceneMdlPuppetRigReadError.invalidPhysicsMetadata
                }
                return number.floatValue
            }
            var gravity = SIMD3<Float>.zero
            if object["ge"] as? Bool == true {
                // Explicit serialized gravity is qualified; absent defaults
                // remain local to this unsupported bone, not a bad rig.
                guard let direction = object["gd"] as? String, object["m"] != nil else {
                    throw SceneMdlPuppetRigReadError.unsupportedPhysicsMode
                }
                let components = direction.split(whereSeparator: \.isWhitespace).map { Float($0) }
                guard components.count == 3, let x = components[0],
                      let y = components[1], let z = components[2] else {
                    throw SceneMdlPuppetRigReadError.invalidPhysicsMetadata
                }
                gravity = try SIMD3(x, y, z) * finite("m", fallback: 0) * 1000
                guard gravity.x.isFinite, gravity.y.isFinite, gravity.z.isFinite else {
                    throw SceneMdlPuppetRigReadError.invalidPhysicsMetadata
                }
            }
            return try Self(spring: spring,
                stiffness: finite("ts", fallback: 200),
                friction: finite("tf", fallback: 10),
                inertia: finite("ti", fallback: 30),
                maxDistance: finite("tm", fallback: 200), gravity: gravity)
        }
    }

    struct VertexWeights: Equatable {
        let boneIndices: SIMD4<UInt32>
        let boneWeights: SIMD4<Float>
    }

    struct PlanarConstraint: Equatable {
        let root: Int
        let joint: Int
        let end: Int
        let goalTrackIndex: Int
        let referenceGoal: SIMD3<Float>
        let referenceGuide: SIMD2<Float>
    }

    let bones: [Bone]
    let vertexWeights: [VertexWeights]
    /// Optional assembled character pose, independent of the mesh's skinning bind.
    let referenceLocalMatricesColumnMajor: [[Float]]?
    let referencePoseDiagnostic: String?
    let hasLegacyControlTracks: Bool
    let planarConstraint: PlanarConstraint?

    init(bones: [Bone], vertexWeights: [VertexWeights],
         referenceLocalMatricesColumnMajor: [[Float]]? = nil,
         referencePoseDiagnostic: String? = nil,
         hasLegacyControlTracks: Bool = false,
         planarConstraint: PlanarConstraint? = nil) {
        self.bones = bones
        self.vertexWeights = vertexWeights
        self.referenceLocalMatricesColumnMajor = referenceLocalMatricesColumnMajor
        self.referencePoseDiagnostic = referencePoseDiagnostic
        self.hasLegacyControlTracks = hasLegacyControlTracks
        self.planarConstraint = planarConstraint
    }
}

nonisolated enum SceneMdlPuppetRigReadError: Error, CustomStringConvertible, Equatable {
    case invalidPhysicsMetadata
    case unsupportedPhysicsMode
    case unsupportedMagic(String)
    case skeletonBlockMissing
    case invalidSkeletonBounds
    case invalidBoneCount(Int)
    case invalidBoneRecord(Int)
    case invalidBoneParent(boneIndex: Int, parentIndex: Int)
    case invalidBindMatrix(Int)
    case invalidReferenceMatrix(Int)
    case invalidReferenceBounds
    case unsupportedReferencePose
    case unsupportedVertexStride(Int)
    case vertexCountMismatch(expected: Int, actual: Int)
    case invalidVertexWeights(Int)

    nonisolated var description: String {
        switch self {
        case .invalidPhysicsMetadata: return "invalid bone physics metadata"
        case .unsupportedPhysicsMode: return "unsupported enabled bone physics mode"
        case let .unsupportedMagic(magic):
            return "unsupported rig mdl magic \(magic)"
        case .skeletonBlockMissing:
            return "rig requires the version-matched skeleton block"
        case .invalidSkeletonBounds:
            return "invalid version-matched rig bounds"
        case let .invalidBoneCount(count):
            return "invalid rig bone count \(count)"
        case let .invalidBoneRecord(index):
            return "invalid version-matched rig bone record \(index)"
        case let .invalidBoneParent(boneIndex, parentIndex):
            return "invalid rig parent \(parentIndex) for bone \(boneIndex)"
        case let .invalidBindMatrix(index):
            return "invalid bind matrix for rig bone \(index)"
        case let .invalidReferenceMatrix(index):
            return "invalid reference matrix for rig bone \(index)"
        case .invalidReferenceBounds:
            return "incomplete rig reference pose within skeleton bounds"
        case .unsupportedReferencePose:
            return "reference pose is unverified for this skeleton version"
        case let .unsupportedVertexStride(stride):
            return "unsupported skinned vertex stride \(stride)"
        case let .vertexCountMismatch(expected, actual):
            return "rig has \(actual) vertex weights; expected \(expected)"
        case let .invalidVertexWeights(index):
            return "invalid puppet vertex weights at index \(index)"
        }
    }
}

/// Version-matched MDLS bind hierarchy plus the four-index/four-weight vertex
/// fields. MDLV0013/MDLS0001, MDLV0014/MDLS0002,
/// MDLV0016, MDLV0017 and MDLV0019 with MDLS0002, and
/// MDLV0021/MDLS0003 and MDLV0023/MDLS0004 use the same validated record shape; the version
/// pair is still checked before any bone data is consumed. The index fields
/// begin at stride - 40 and weights at stride - 24 for the verified 52-, 80-,
/// and 84-byte records.
nonisolated enum SceneMdlPuppetRigReader {
    /// A validated vertex span, shared by image Puppet and direct-model readers.
    /// It carries no projected positions or second vertex storage.
    struct VertexLayout {
        let version: String
        let vertexStride: Int
        let vertexDataOffset: Int
        let vertexCount: Int
    }

    private struct VersionContract {
        let skeletonMarker: Data
        let vertexStrides: Set<Int>
    }

    private static let versionContracts = [
        "MDLV0013": VersionContract(
            skeletonMarker: Data("MDLS0001\0".utf8),
            vertexStrides: [52]
        ),
        "MDLV0014": VersionContract(
            skeletonMarker: Data("MDLS0002\0".utf8),
            vertexStrides: [52]
        ),
        "MDLV0016": VersionContract(
            skeletonMarker: Data("MDLS0002\0".utf8),
            vertexStrides: [52]
        ),
        "MDLV0017": VersionContract(
            skeletonMarker: Data("MDLS0002\0".utf8),
            vertexStrides: [80, 84]
        ),
        "MDLV0019": VersionContract(
            skeletonMarker: Data("MDLS0002\0".utf8),
            vertexStrides: [80]
        ),
        "MDLV0021": VersionContract(
            skeletonMarker: Data("MDLS0003\0".utf8),
            vertexStrides: [80]
        ),
        "MDLV0023": VersionContract(
            skeletonMarker: Data("MDLS0004\0".utf8),
            vertexStrides: [80, 84]
        ),
    ]
    private static let markerSize = 9
    private static let matrixByteCount = 64
    private static let preReferenceRecordByteCount = 1 + 4 + 4 + matrixByteCount
    private static let maxBoneCount = 4096
    private static let maxNameBytes = 1024
    private static let maxMetadataBytes = 64 * 1024
    private static let maxAbsoluteMatrixValue: Float = 1_000_000
    private static let weightTolerance: Float = 0.0001

    static func read(
        data rawData: Data,
        mesh: SceneMdlPuppetMesh
    ) throws -> SceneMdlPuppetRig {
        let data = rawData.startIndex == 0 ? rawData : Data(rawData)
        let magic = String(decoding: data.prefix(8), as: UTF8.self)
        guard let contract = versionContracts[magic], mesh.version == magic else {
            throw SceneMdlPuppetRigReadError.unsupportedMagic(magic)
        }
        guard let skeletonOffset = data.range(of: contract.skeletonMarker)?.lowerBound else {
            throw SceneMdlPuppetRigReadError.skeletonBlockMissing
        }
        return try read(data: data, vertexLayout: .init(
            version: mesh.version, vertexStride: mesh.vertexStride,
            vertexDataOffset: mesh.meshBlockOffset + 8,
            vertexCount: mesh.vertices.count
        ), skeletonOffset: skeletonOffset)
    }

    /// Direct models supply the exact skeleton boundary reached by their
    /// complete envelope parser; this entry never searches past a bad mesh.
    static func read(
        data rawData: Data,
        vertexLayout: VertexLayout,
        skeletonOffset: Int
    ) throws -> SceneMdlPuppetRig {
        let data = rawData.startIndex == 0 ? rawData : Data(rawData)
        let magic = String(decoding: data.prefix(8), as: UTF8.self)
        guard let contract = versionContracts[magic], vertexLayout.version == magic else {
            throw SceneMdlPuppetRigReadError.unsupportedMagic(magic)
        }
        guard skeletonOffset >= markerSize, skeletonOffset <= data.count,
              contract.skeletonMarker.count <= data.count - skeletonOffset,
              data[skeletonOffset..<(skeletonOffset + contract.skeletonMarker.count)]
                .elementsEqual(contract.skeletonMarker) else {
            throw SceneMdlPuppetRigReadError.skeletonBlockMissing
        }
        let skeleton = try readBones(data: data, blockOffset: skeletonOffset,
            isMDLS0002: contract.skeletonMarker == Data("MDLS0002\0".utf8))
        let weights = try readVertexWeights(
            data: data,
            layout: vertexLayout,
            skeletonOffset: skeletonOffset,
            boneCount: skeleton.bones.count
        )
        return SceneMdlPuppetRig(bones: skeleton.bones, vertexWeights: weights,
            referenceLocalMatricesColumnMajor: skeleton.reference,
            referencePoseDiagnostic: skeleton.diagnostic, hasLegacyControlTracks: skeleton.hasControls,
            planarConstraint: skeleton.constraint)
    }

    private static func readBones(
        data: Data,
        blockOffset: Int,
        isMDLS0002: Bool
    ) throws -> (bones: [SceneMdlPuppetRig.Bone], reference: [[Float]]?, diagnostic: String?, hasControls: Bool,
                 constraint: SceneMdlPuppetRig.PlanarConstraint?) {
        var cursor = blockOffset + markerSize
        guard cursor + 8 <= data.count else {
            throw SceneMdlPuppetRigReadError.invalidSkeletonBounds
        }
        let endOffset = Int(readUInt32(data, at: cursor))
        cursor += 4
        guard endOffset > cursor, endOffset <= data.count else {
            throw SceneMdlPuppetRigReadError.invalidSkeletonBounds
        }
        let boneCount = Int(readUInt32(data, at: cursor))
        cursor += 4
        guard boneCount > 0, boneCount <= maxBoneCount else {
            throw SceneMdlPuppetRigReadError.invalidBoneCount(boneCount)
        }

        var bones: [SceneMdlPuppetRig.Bone] = []
        bones.reserveCapacity(boneCount)
        let maximumBoneFlags: UInt32 = isMDLS0002 ? 3 : 1
        for boneIndex in 0 ..< boneCount {
            guard let nameEnd = nullTerminator(
                in: data,
                from: cursor,
                bound: endOffset,
                maxBytes: maxNameBytes
            ), let name = String(
                data: data[cursor ..< nameEnd], encoding: .utf8
            ) else {
                throw SceneMdlPuppetRigReadError.invalidBoneRecord(boneIndex)
            }
            cursor = nameEnd + 1
            guard cursor + 12 + matrixByteCount <= endOffset else {
                throw SceneMdlPuppetRigReadError.invalidBoneRecord(boneIndex)
            }
            let flags = readUInt32(data, at: cursor)
            let parentIndex = Int(readInt32(data, at: cursor + 4))
            let byteCount = Int(readUInt32(data, at: cursor + 8))
            cursor += 12
            guard flags <= maximumBoneFlags, byteCount == matrixByteCount else {
                throw SceneMdlPuppetRigReadError.invalidBoneRecord(boneIndex)
            }
            guard parentIndex >= -1, parentIndex < boneIndex else {
                throw SceneMdlPuppetRigReadError.invalidBoneParent(
                    boneIndex: boneIndex,
                    parentIndex: parentIndex
                )
            }
            let matrix = try readMatrix(data: data, at: cursor, boneIndex: boneIndex)
            cursor += matrixByteCount
            guard let metadataEnd = nullTerminator(
                in: data,
                from: cursor,
                bound: endOffset,
                maxBytes: maxMetadataBytes
            ) else {
                throw SceneMdlPuppetRigReadError.invalidBoneRecord(boneIndex)
            }
            let physics: SceneMdlPuppetRig.TranslationPhysics?
            var physicsDiagnostic: String?
            do {
                physics = try SceneMdlPuppetRig.TranslationPhysics.read(
                    metadata: Data(data[cursor..<metadataEnd]))
            } catch SceneMdlPuppetRigReadError.unsupportedPhysicsMode {
                // An unsupported visual solver is local to this bone; it
                // must not discard an otherwise valid animated skeleton.
                physics = nil
                physicsDiagnostic = "unsupported-enabled-physics"
            } catch SceneMdlPuppetRigReadError.invalidPhysicsMetadata {
                physics = nil
                physicsDiagnostic = "invalid-physics-metadata"
            }
            cursor = metadataEnd + 1
            bones.append(.init(
                name: name,
                parentIndex: parentIndex,
                bindLocalMatrixColumnMajor: matrix,
                translationPhysics: physics,
                physicsDiagnostic: physicsDiagnostic
            ))
        }
        guard cursor < endOffset else { return (bones, nil, nil, false, nil) }
        guard let envelope = referenceEnvelope(
            in: data, after: cursor, end: endOffset,
            boneCount: boneCount, isMDLS0002: isMDLS0002
        ) else {
            return (bones, nil, "unsupported-reference-pose-prefix", false, nil)
        }
        let recordsStart = cursor + 2
        let hasReference = data[envelope.flag] == 1
        cursor = envelope.flag + 1
        var reference: [[Float]]?
        if hasReference {
            guard isMDLS0002 else { throw SceneMdlPuppetRigReadError.unsupportedReferencePose }
            guard boneCount * matrixByteCount <= endOffset - cursor else {
                throw SceneMdlPuppetRigReadError.invalidReferenceBounds
            }
            var matrices: [[Float]] = []
            matrices.reserveCapacity(boneCount)
            for boneIndex in 0..<boneCount {
                do {
                    matrices.append(try readMatrix(data: data, at: cursor, boneIndex: boneIndex))
                } catch {
                    throw SceneMdlPuppetRigReadError.invalidReferenceMatrix(boneIndex)
                }
                cursor += matrixByteCount
            }
            reference = matrices
        }
        let hasControls = envelope.count == 2
        let constraint = hasControls
            ? readPlanarConstraint(in: data, recordsStart: recordsStart, referenceEnd: cursor,
                                   hasReference: hasReference, bound: endOffset, bones: bones)
            : nil
        return (bones, reference, nil, hasControls, constraint)
    }

    private static func referenceEnvelope(
        in data: Data, after bonesEnd: Int, end: Int, boneCount: Int, isMDLS0002: Bool
    ) -> (flag: Int, count: Int)? {
        guard end - bonesEnd >= 3 else { return nil }
        let recordCount = Int(data[bonesEnd]) | (Int(data[bonesEnd + 1]) << 8)
        var cursor = bonesEnd + 2
        if recordCount > 0 {
            guard isMDLS0002,
                  recordCount <= (end - cursor - 1) / preReferenceRecordByteCount
            else { return nil }
            for _ in 0..<recordCount {
                guard data[cursor] == 0,
                      readUInt32(data, at: cursor + 1) < UInt32(boneCount),
                      readUInt32(data, at: cursor + 5) <= 1
                else { return nil }
                cursor += preReferenceRecordByteCount
            }
        }
        return data[cursor] <= 1 ? (cursor, recordCount) : nil
    }

    private static func readPlanarConstraint(
        in data: Data, recordsStart: Int, referenceEnd: Int, hasReference: Bool,
        bound: Int, bones: [SceneMdlPuppetRig.Bone]
    ) -> SceneMdlPuppetRig.PlanarConstraint? {
        let firstRole = readUInt32(data, at: recordsStart + 5)
        let secondRecord = recordsStart + preReferenceRecordByteCount
        guard firstRole != readUInt32(data, at: secondRecord + 5),
              readUInt32(data, at: recordsStart + 1) == readUInt32(data, at: secondRecord + 1)
        else { return nil }
        let end = Int(readUInt32(data, at: recordsStart + 1))
        let goalTrack = Int(firstRole)
        let guideTrack = 1 - goalTrack

        var cursor = referenceEnd + (hasReference ? 2 * matrixByteCount : 0)
        let lengthsEnd = cursor + 6 + bones.count * 4
        guard lengthsEnd <= bound, readUInt32(data, at: cursor) == 0,
              readUInt16(data, at: cursor + 4) == bones.count else { return nil }
        cursor = lengthsEnd
        for _ in bones {
            guard bound - cursor >= 2 else { return nil }
            cursor += 2 + readUInt16(data, at: cursor) * 16
        }
        // The compiled group contains variable ancestry lists. This record is
        // the one-root, one-effector layout with a three-joint ordered path.
        guard bound - cursor >= 52, readUInt16(data, at: cursor) == 1 else { return nil }
        cursor += 2
        guard readUInt16(data, at: cursor + 12) == 1,
              readUInt16(data, at: cursor + 18) == 1,
              readUInt16(data, at: cursor + 36) == 3 else { return nil }
        let root = Int(readUInt32(data, at: cursor + 38))
        let joint = Int(readUInt32(data, at: cursor + 42))
        guard root < bones.count, joint < bones.count, bones[joint].parentIndex == root,
              Int(readUInt32(data, at: cursor)) == root,
              Int(readUInt32(data, at: cursor + 14)) == root,
              Int(readUInt32(data, at: cursor + 20)) == end,
              Int(readUInt32(data, at: cursor + 46)) == end,
              bones[end].parentIndex == joint else { return nil }

        let goal = hasReference ? referenceEnd + goalTrack * matrixByteCount
            : recordsStart + goalTrack * preReferenceRecordByteCount + 9
        let guide = hasReference ? referenceEnd + guideTrack * matrixByteCount
            : recordsStart + guideTrack * preReferenceRecordByteCount + 9
        let goalAxis = SIMD2(readFloat(data, at: goal), readFloat(data, at: goal + 4))
        guard goalAxis.x.isFinite, goalAxis.y.isFinite else { return nil }
        let referenceGoal = SIMD3(readFloat(data, at: goal + 48), readFloat(data, at: goal + 52),
                                  atan2(goalAxis.y, goalAxis.x))
        let referenceGuide = SIMD2(readFloat(data, at: guide + 48), readFloat(data, at: guide + 52))
        guard referenceGoal.x.isFinite, referenceGoal.y.isFinite, referenceGoal.z.isFinite,
              referenceGuide.x.isFinite, referenceGuide.y.isFinite else { return nil }
        return .init(root: root, joint: joint, end: end, goalTrackIndex: goalTrack,
                     referenceGoal: referenceGoal, referenceGuide: referenceGuide)
    }

    private static func readVertexWeights(
        data: Data,
        layout: VertexLayout,
        skeletonOffset: Int,
        boneCount: Int
    ) throws -> [SceneMdlPuppetRig.VertexWeights] {
        let magic = layout.version
        guard let contract = versionContracts[magic],
              contract.vertexStrides.contains(layout.vertexStride)
        else {
            throw SceneMdlPuppetRigReadError.unsupportedVertexStride(layout.vertexStride)
        }
        let vertexDataOffset = layout.vertexDataOffset
        guard vertexDataOffset >= markerSize,
              vertexDataOffset <= skeletonOffset, layout.vertexCount >= 0,
              layout.vertexCount <= (skeletonOffset - vertexDataOffset) / layout.vertexStride
        else {
            throw SceneMdlPuppetRigReadError.vertexCountMismatch(
                expected: layout.vertexCount,
                actual: 0
            )
        }
        let indexOffset = layout.vertexStride - 40
        let weightOffset = layout.vertexStride - 24
        var result: [SceneMdlPuppetRig.VertexWeights] = []
        result.reserveCapacity(layout.vertexCount)
        for vertexIndex in 0..<layout.vertexCount {
            let base = vertexDataOffset + vertexIndex * layout.vertexStride
            let indices = SIMD4<UInt32>(
                readUInt32(data, at: base + indexOffset),
                readUInt32(data, at: base + indexOffset + 4),
                readUInt32(data, at: base + indexOffset + 8),
                readUInt32(data, at: base + indexOffset + 12)
            )
            let weights = SIMD4<Float>(
                readFloat(data, at: base + weightOffset),
                readFloat(data, at: base + weightOffset + 4),
                readFloat(data, at: base + weightOffset + 8),
                readFloat(data, at: base + weightOffset + 12)
            )
            var sum: Float = 0
            var hasWeight = false
            for influence in 0 ..< 4 {
                let weight = weights[influence]
                guard indices[influence] < UInt32(boneCount),
                      weight.isFinite,
                      weight >= 0,
                      weight <= 1 + weightTolerance
                else {
                    throw SceneMdlPuppetRigReadError.invalidVertexWeights(vertexIndex)
                }
                sum += weight
                hasWeight = hasWeight || weight > weightTolerance
            }
            guard hasWeight, abs(sum - 1) <= weightTolerance else {
                throw SceneMdlPuppetRigReadError.invalidVertexWeights(vertexIndex)
            }
            result.append(.init(boneIndices: indices, boneWeights: weights))
        }
        guard result.count == layout.vertexCount else {
            throw SceneMdlPuppetRigReadError.vertexCountMismatch(
                expected: layout.vertexCount,
                actual: result.count
            )
        }
        return result
    }

    private static func readMatrix(
        data: Data,
        at offset: Int,
        boneIndex: Int
    ) throws -> [Float] {
        var values: [Float] = []
        values.reserveCapacity(16)
        for component in 0 ..< 16 {
            let value = readFloat(data, at: offset + component * 4)
            guard value.isFinite, abs(value) <= maxAbsoluteMatrixValue else {
                throw SceneMdlPuppetRigReadError.invalidBindMatrix(boneIndex)
            }
            values.append(value)
        }
        let epsilon: Float = 0.0001
        guard abs(values[3]) <= epsilon,
              abs(values[7]) <= epsilon,
              abs(values[11]) <= epsilon,
              abs(values[15] - 1) <= epsilon
        else {
            throw SceneMdlPuppetRigReadError.invalidBindMatrix(boneIndex)
        }
        // Match the affine value accepted above before any bind/reference
        // composition; preserving tolerated W noise can reject valid skinning.
        values[3] = 0
        values[7] = 0
        values[11] = 0
        values[15] = 1
        return values
    }

    private static func nullTerminator(
        in data: Data,
        from offset: Int,
        bound: Int,
        maxBytes: Int
    ) -> Int? {
        guard offset < bound else { return nil }
        let limit = min(bound, offset + maxBytes + 1)
        return data[offset ..< limit].firstIndex(of: 0)
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { buffer in
            data.copyBytes(to: buffer, from: offset ..< (offset + 4))
        }
        return UInt32(littleEndian: value)
    }

    private static func readInt32(_ data: Data, at offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32(data, at: offset))
    }

    private static func readFloat(_ data: Data, at offset: Int) -> Float {
        Float(bitPattern: readUInt32(data, at: offset))
    }
}
