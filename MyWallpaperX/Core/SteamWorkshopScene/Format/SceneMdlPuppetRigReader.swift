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

    let bones: [Bone]
    let vertexWeights: [VertexWeights]
    /// Optional assembled character pose, independent of the mesh's skinning bind.
    let referenceLocalMatricesColumnMajor: [[Float]]?
    let referencePoseDiagnostic: String?

    init(bones: [Bone], vertexWeights: [VertexWeights],
         referenceLocalMatricesColumnMajor: [[Float]]? = nil,
         referencePoseDiagnostic: String? = nil) {
        self.bones = bones
        self.vertexWeights = vertexWeights
        self.referenceLocalMatricesColumnMajor = referenceLocalMatricesColumnMajor
        self.referencePoseDiagnostic = referencePoseDiagnostic
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
/// fields. MDLV0014/MDLS0002, MDLV0016/MDLS0002, MDLV0017/MDLS0002, and
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
            permitsReferencePose: contract.skeletonMarker == Data("MDLS0002\0".utf8))
        let weights = try readVertexWeights(
            data: data,
            layout: vertexLayout,
            skeletonOffset: skeletonOffset,
            boneCount: skeleton.bones.count
        )
        return SceneMdlPuppetRig(bones: skeleton.bones, vertexWeights: weights,
            referenceLocalMatricesColumnMajor: skeleton.reference,
            referencePoseDiagnostic: skeleton.diagnostic)
    }

    private static func readBones(
        data: Data,
        blockOffset: Int,
        permitsReferencePose: Bool
    ) throws -> (bones: [SceneMdlPuppetRig.Bone], reference: [[Float]]?, diagnostic: String?) {
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
            let state = readUInt32(data, at: cursor)
            let parentIndex = Int(readInt32(data, at: cursor + 4))
            let byteCount = Int(readUInt32(data, at: cursor + 8))
            cursor += 12
            guard state <= 1, byteCount == matrixByteCount else {
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
        // Existing assets and fixtures may end immediately after the bone records.
        // Only the verified flag prefix identifies the optional matrix segment;
        // subsequent MDLS fields retain their existing, unprojected behavior.
        guard cursor < endOffset else { return (bones, nil, nil) }
        guard endOffset - cursor >= 3,
              data[cursor] == 0, data[cursor + 1] == 0,
              data[cursor + 2] <= 1 else {
            return (bones, nil, "unsupported-reference-pose-prefix")
        }
        guard data[cursor + 2] == 1 else { return (bones, nil, nil) }
        guard permitsReferencePose else {
            throw SceneMdlPuppetRigReadError.unsupportedReferencePose
        }
        cursor += 3
        guard boneCount * matrixByteCount <= endOffset - cursor else {
            throw SceneMdlPuppetRigReadError.invalidReferenceBounds
        }
        var reference: [[Float]] = []
        reference.reserveCapacity(boneCount)
        for boneIndex in 0..<boneCount {
            do {
                reference.append(try readMatrix(data: data, at: cursor, boneIndex: boneIndex))
            } catch {
                throw SceneMdlPuppetRigReadError.invalidReferenceMatrix(boneIndex)
            }
            cursor += matrixByteCount
        }
        return (bones, reference, nil)
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
