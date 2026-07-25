import Foundation

struct SceneMdlPuppetRig {
    struct Bone {
        let parentIndex: Int
        let bindLocalMatrixColumnMajor: [Float]
    }

    struct VertexWeights {
        let boneIndices: SIMD4<UInt32>
        let boneWeights: SIMD4<Float>
    }

    let bones: [Bone]
    let vertexWeights: [VertexWeights]
}

enum SceneMdlPuppetRigReadError: Error, CustomStringConvertible, Equatable, Sendable {
    case unsupportedMagic(String)
    case skeletonBlockMissing
    case invalidSkeletonBounds
    case invalidBoneCount(Int)
    case invalidBoneRecord(Int)
    case invalidBoneParent(boneIndex: Int, parentIndex: Int)
    case invalidBindMatrix(Int)
    case unsupportedVertexStride(Int)
    case vertexCountMismatch(expected: Int, actual: Int)
    case invalidVertexWeights(Int)

    nonisolated var description: String {
        switch self {
        case .unsupportedMagic(let magic):
            return "unsupported rig mdl magic \(magic)"
        case .skeletonBlockMissing:
            return "rig requires an MDLS0004 block"
        case .invalidSkeletonBounds:
            return "invalid MDLS0004 rig bounds"
        case .invalidBoneCount(let count):
            return "invalid MDLS0004 rig bone count \(count)"
        case .invalidBoneRecord(let index):
            return "invalid MDLS0004 rig bone record \(index)"
        case .invalidBoneParent(let boneIndex, let parentIndex):
            return "invalid rig parent \(parentIndex) for bone \(boneIndex)"
        case .invalidBindMatrix(let index):
            return "invalid bind matrix for rig bone \(index)"
        case .unsupportedVertexStride(let stride):
            return "unsupported skinned vertex stride \(stride)"
        case .vertexCountMismatch(let expected, let actual):
            return "rig has \(actual) vertex weights; expected \(expected)"
        case .invalidVertexWeights(let index):
            return "invalid puppet vertex weights at index \(index)"
        }
    }
}

// MDLS0004 bind hierarchy plus the four-index/four-weight vertex fields
// verified across sixteen animated MDLV0023 assets from three Workshop
// samples. The index fields begin at stride - 40 and weights at stride - 24
// for the verified 80- and 84-byte vertex records.
enum SceneMdlPuppetRigReader {
    private static let mdlMagic = "MDLV0023"
    private static let skeletonMarker = Data("MDLS0004\0".utf8)
    private static let markerSize = 9
    private static let matrixByteCount = 64
    private static let maxBoneCount = 4_096
    private static let maxNameBytes = 1_024
    private static let maxMetadataBytes = 64 * 1_024
    private static let maxAbsoluteMatrixValue: Float = 1_000_000
    private static let weightTolerance: Float = 0.0001

    static func read(
        data rawData: Data,
        mesh: SceneMdlPuppetMesh
    ) throws -> SceneMdlPuppetRig {
        let data = rawData.startIndex == 0 ? rawData : Data(rawData)
        let magic = String(decoding: data.prefix(8), as: UTF8.self)
        guard magic == mdlMagic, mesh.version == mdlMagic else {
            throw SceneMdlPuppetRigReadError.unsupportedMagic(magic)
        }
        guard let skeletonOffset = data.range(of: skeletonMarker)?.lowerBound else {
            throw SceneMdlPuppetRigReadError.skeletonBlockMissing
        }
        let bones = try readBones(data: data, blockOffset: skeletonOffset)
        let weights = try readVertexWeights(
            data: data,
            mesh: mesh,
            skeletonOffset: skeletonOffset,
            boneCount: bones.count
        )
        return SceneMdlPuppetRig(bones: bones, vertexWeights: weights)
    }

    private static func readBones(
        data: Data,
        blockOffset: Int
    ) throws -> [SceneMdlPuppetRig.Bone] {
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
        for boneIndex in 0..<boneCount {
            guard let nameEnd = nullTerminator(
                in: data,
                from: cursor,
                bound: endOffset,
                maxBytes: maxNameBytes
            ), String(data: data[cursor..<nameEnd], encoding: .utf8) != nil else {
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
            cursor = metadataEnd + 1
            bones.append(.init(
                parentIndex: parentIndex,
                bindLocalMatrixColumnMajor: matrix
            ))
        }
        return bones
    }

    private static func readVertexWeights(
        data: Data,
        mesh: SceneMdlPuppetMesh,
        skeletonOffset: Int,
        boneCount: Int
    ) throws -> [SceneMdlPuppetRig.VertexWeights] {
        guard mesh.vertexStride == 80 || mesh.vertexStride == 84 else {
            throw SceneMdlPuppetRigReadError.unsupportedVertexStride(mesh.vertexStride)
        }
        let vertexDataOffset = mesh.meshBlockOffset + 8
        let vertexDataEnd = vertexDataOffset + mesh.vertices.count * mesh.vertexStride
        guard vertexDataOffset >= markerSize,
              vertexDataEnd <= skeletonOffset else {
            throw SceneMdlPuppetRigReadError.vertexCountMismatch(
                expected: mesh.vertices.count,
                actual: 0
            )
        }
        let indexOffset = mesh.vertexStride - 40
        let weightOffset = mesh.vertexStride - 24
        var result: [SceneMdlPuppetRig.VertexWeights] = []
        result.reserveCapacity(mesh.vertices.count)
        for vertexIndex in mesh.vertices.indices {
            let base = vertexDataOffset + vertexIndex * mesh.vertexStride
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
            for influence in 0..<4 {
                let weight = weights[influence]
                guard indices[influence] < UInt32(boneCount),
                      weight.isFinite,
                      weight >= 0,
                      weight <= 1 + weightTolerance else {
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
        guard result.count == mesh.vertices.count else {
            throw SceneMdlPuppetRigReadError.vertexCountMismatch(
                expected: mesh.vertices.count,
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
        for component in 0..<16 {
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
              abs(values[15] - 1) <= epsilon else {
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
        return data[offset..<limit].firstIndex(of: 0)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { buffer in
            data.copyBytes(to: buffer, from: offset..<(offset + 4))
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
