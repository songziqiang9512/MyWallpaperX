import Foundation

// Bind-pose mesh extracted from a Wallpaper Engine puppet `.mdl` file.
//
// Contract provenance: the MDLV block layout (versioned magic, first "MDLS"
// offset as the mesh search bound, a `u32 vertexBytes` header followed by
// tightly packed vertices, then `u32 indexBytes` and uint16 triangle indices,
// position at vertex offset 0 and UV in the trailing 8 bytes) matches the
// auditable third-party player interpretation and was cross-checked against
// real Workshop puppet assets. It is NOT an official public format contract;
// anything outside the verified shape fails closed.
struct SceneMdlPuppetMesh {
    struct Vertex {
        let x: Float
        let y: Float
        let z: Float
        let u: Float
        let v: Float
    }

    let version: String
    let vertexStride: Int
    let meshBlockOffset: Int
    let vertices: [Vertex]
    let indices: [UInt16]

    nonisolated var triangleCount: Int { indices.count / 3 }
}

enum SceneMdlPuppetMeshReadError: Error, CustomStringConvertible, Equatable, Sendable {
    case fileTooSmall
    case unsupportedMagic(String)
    case meshBlockNotFound
    case nonFiniteVertexData(vertexIndex: Int)
    case vertexDataOutOfRange(vertexIndex: Int)

    nonisolated var description: String {
        switch self {
        case .fileTooSmall:
            return "puppet mdl smaller than header"
        case .unsupportedMagic(let magic):
            return "unsupported puppet mdl magic \(magic)"
        case .meshBlockNotFound:
            return "no strict bind-pose mesh block found"
        case .nonFiniteVertexData(let vertexIndex):
            return "non-finite vertex data at index \(vertexIndex)"
        case .vertexDataOutOfRange(let vertexIndex):
            return "vertex data out of accepted range at index \(vertexIndex)"
        }
    }
}

// Parses the single bind-pose mesh block out of a puppet `.mdl`. Skeleton
// ("MDLS"), animation ("MDLA") and attachment ("MDAT") blocks are read-only
// bounds here; this reader never interprets them.
enum SceneMdlPuppetMeshReader {
    private static let supportedMagics = ["MDLV0021", "MDLV0023"]
    private static let magicLength = 8
    // Magic + trailing NUL, matching the audited player's marker size.
    private static let markerSize = 9
    private static let meshHeaderSize = 8
    // Verified vertex layouts: 80 bytes (6 tail/arm assets) and 84 bytes
    // (skinned base asset). Position is 3 floats at offset 0, UV the final
    // 2 floats. Other strides fail closed until a real asset proves them.
    private static let vertexStrideCandidates = [80, 84]
    private static let maxAbsolutePosition: Float = 1_000_000
    private static let maxAbsoluteUV: Float = 64

    static func read(data rawData: Data) throws -> SceneMdlPuppetMesh {
        // Normalize to a zero-based Data so absolute offsets stay valid for slices.
        let data = rawData.startIndex == 0 ? rawData : Data(rawData)
        guard data.count > markerSize + meshHeaderSize else {
            throw SceneMdlPuppetMeshReadError.fileTooSmall
        }
        let magic = String(decoding: data.prefix(magicLength), as: UTF8.self)
        guard supportedMagics.contains(magic) else {
            throw SceneMdlPuppetMeshReadError.unsupportedMagic(magic)
        }
        let searchBound = firstOccurrence(of: "MDLS", in: data) ?? data.count
        guard let block = findMeshBlock(in: data, bound: searchBound) else {
            throw SceneMdlPuppetMeshReadError.meshBlockNotFound
        }
        return try decode(block: block, magic: magic, data: data)
    }

    private struct MeshBlock {
        let offset: Int
        let stride: Int
        let vertexCount: Int
        let vertexBytesOffset: Int
        let indexCount: Int
        let indexBytesOffset: Int
    }

    // Scans [marker, bound) for the first offset whose u32-at-offset+4 forms a
    // self-consistent vertex/index block. The index list must reference every
    // vertex slot exactly up to vertexCount-1, which uniquely determines the
    // stride: max(index) == vertexBytes/strideA - 1 and == vertexBytes/strideB - 1
    // cannot both hold for distinct strides.
    private static func findMeshBlock(in data: Data, bound: Int) -> MeshBlock? {
        guard bound > markerSize + meshHeaderSize + 4 else { return nil }
        for offset in markerSize..<(bound - meshHeaderSize - 4) {
            let vertexBytes = Int(readUInt32(data, at: offset + 4))
            guard vertexBytes > 0 else { continue }
            let verticesOffset = offset + meshHeaderSize
            let indexLengthOffset = verticesOffset + vertexBytes
            guard indexLengthOffset + 4 <= bound else { continue }
            let indexBytes = Int(readUInt32(data, at: indexLengthOffset))
            guard indexBytes > 0,
                  indexBytes % 6 == 0,
                  indexLengthOffset + 4 + indexBytes <= bound else { continue }
            let strides = vertexStrideCandidates.filter { stride in
                vertexBytes % stride == 0 && vertexBytes / stride >= 3
            }
            guard strides.isEmpty == false else { continue }
            let indicesOffset = indexLengthOffset + 4
            guard let maxIndex = maxUInt16(
                data, at: indicesOffset, count: indexBytes / 2
            ) else { continue }
            for stride in strides {
                let vertexCount = vertexBytes / stride
                guard Int(maxIndex) == vertexCount - 1 else { continue }
                return MeshBlock(
                    offset: offset,
                    stride: stride,
                    vertexCount: vertexCount,
                    vertexBytesOffset: verticesOffset,
                    indexCount: indexBytes / 2,
                    indexBytesOffset: indicesOffset
                )
            }
        }
        return nil
    }

    private static func decode(
        block: MeshBlock,
        magic: String,
        data: Data
    ) throws -> SceneMdlPuppetMesh {
        var vertices: [SceneMdlPuppetMesh.Vertex] = []
        vertices.reserveCapacity(block.vertexCount)
        let uvOffset = block.stride - 8
        for index in 0..<block.vertexCount {
            let base = block.vertexBytesOffset + index * block.stride
            let x = readFloat(data, at: base)
            let y = readFloat(data, at: base + 4)
            let z = readFloat(data, at: base + 8)
            let u = readFloat(data, at: base + uvOffset)
            let v = readFloat(data, at: base + uvOffset + 4)
            guard x.isFinite, y.isFinite, z.isFinite, u.isFinite, v.isFinite else {
                throw SceneMdlPuppetMeshReadError.nonFiniteVertexData(vertexIndex: index)
            }
            guard abs(x) <= maxAbsolutePosition,
                  abs(y) <= maxAbsolutePosition,
                  abs(z) <= maxAbsolutePosition,
                  abs(u) <= maxAbsoluteUV,
                  abs(v) <= maxAbsoluteUV else {
                throw SceneMdlPuppetMeshReadError.vertexDataOutOfRange(vertexIndex: index)
            }
            vertices.append(.init(x: x, y: y, z: z, u: u, v: v))
        }
        var indices: [UInt16] = []
        indices.reserveCapacity(block.indexCount)
        for index in 0..<block.indexCount {
            indices.append(readUInt16(data, at: block.indexBytesOffset + index * 2))
        }
        return SceneMdlPuppetMesh(
            version: magic,
            vertexStride: block.stride,
            meshBlockOffset: block.offset,
            vertices: vertices,
            indices: indices
        )
    }

    private static func firstOccurrence(of marker: String, in data: Data) -> Int? {
        guard let range = data.range(
            of: Data(marker.utf8),
            options: [],
            in: markerSize..<data.count
        ) else { return nil }
        return range.lowerBound
    }

    private static func maxUInt16(_ data: Data, at offset: Int, count: Int) -> UInt16? {
        guard count > 0, offset + count * 2 <= data.count else { return nil }
        var maxValue: UInt16 = 0
        for index in 0..<count {
            maxValue = max(maxValue, readUInt16(data, at: offset + index * 2))
        }
        return maxValue
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { buffer in
            data.copyBytes(to: buffer, from: offset..<(offset + 4))
        }
        return UInt32(littleEndian: value)
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        var value: UInt16 = 0
        _ = withUnsafeMutableBytes(of: &value) { buffer in
            data.copyBytes(to: buffer, from: offset..<(offset + 2))
        }
        return UInt16(littleEndian: value)
    }

    private static func readFloat(_ data: Data, at offset: Int) -> Float {
        Float(bitPattern: readUInt32(data, at: offset))
    }
}
