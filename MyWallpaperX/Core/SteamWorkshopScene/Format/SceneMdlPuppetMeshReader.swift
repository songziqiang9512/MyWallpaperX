import Foundation

/// Bind-pose mesh extracted from a Wallpaper Engine puppet `.mdl` file.
///
/// Contract provenance: the MDLV block layout (versioned magic, first "MDLS"
/// offset as the mesh search bound, a `u32 vertexBytes` header followed by
/// tightly packed vertices, then `u32 indexBytes` and uint16 triangle indices,
/// position at vertex offset 0 and UV in the trailing 8 bytes) matches the
/// auditable third-party player interpretation and was cross-checked against
/// real Workshop puppet assets. It is NOT an official public format contract;
/// anything outside the verified shape fails closed.
struct SceneMdlPuppetMesh {
    struct Vertex {
        let x: Float
        let y: Float
        let z: Float
        let u: Float
        let v: Float
    }

    struct DrawPart: Equatable {
        let ordinal: Int
        // Authored words are retained without identifying them as bone IDs.
        let id: UInt32
        let flags: UInt32
        let indexOffset: Int
        let indexCount: Int
    }

    struct ClipRecord: Equatable {
        let id: UInt32
        let flags: UInt32
        let rawOptions: SIMD2<UInt32>
        let maskTexturePath: String
        let targetPartOrdinal: Int
        let sourcePartOrdinals: [Int]
    }

    let version: String
    let vertexStride: Int
    let meshBlockOffset: Int
    let vertices: [Vertex]
    let indices: [UInt16]
    let drawParts: [DrawPart]
    let clipRecords: [ClipRecord]

    init(
        version: String, vertexStride: Int, meshBlockOffset: Int,
        vertices: [Vertex], indices: [UInt16],
        drawParts: [DrawPart] = [], clipRecords: [ClipRecord] = []
    ) {
        self.version = version
        self.vertexStride = vertexStride
        self.meshBlockOffset = meshBlockOffset
        self.vertices = vertices
        self.indices = indices
        self.drawParts = drawParts
        self.clipRecords = clipRecords
    }

    nonisolated var triangleCount: Int {
        indices.count / 3
    }
}

enum SceneMdlPuppetMeshReadError: Error, CustomStringConvertible, Equatable {
    case fileTooSmall
    case unsupportedMagic(String)
    case meshBlockNotFound
    case nonFiniteVertexData(vertexIndex: Int)
    case vertexDataOutOfRange(vertexIndex: Int)
    case invalidClippingLayout
    case invalidDrawPart(ordinal: Int)
    case invalidClipRecord(index: Int)
    case unsupportedClippingOptions(index: Int)

    nonisolated var description: String {
        switch self {
        case .fileTooSmall:
            return "puppet mdl smaller than header"
        case let .unsupportedMagic(magic):
            return "unsupported puppet mdl magic \(magic)"
        case .meshBlockNotFound:
            return "no strict bind-pose mesh block found"
        case let .nonFiniteVertexData(vertexIndex):
            return "non-finite vertex data at index \(vertexIndex)"
        case let .vertexDataOutOfRange(vertexIndex):
            return "vertex data out of accepted range at index \(vertexIndex)"
        case .invalidClippingLayout:
            return "invalid MDLV0023 draw-part/clipping envelope"
        case let .invalidDrawPart(ordinal):
            return "invalid puppet draw-part range at ordinal \(ordinal)"
        case let .invalidClipRecord(index):
            return "invalid puppet clipping relation at record \(index)"
        case let .unsupportedClippingOptions(index):
            return "unsupported puppet clipping options at record \(index)"
        }
    }
}

/// Parses the single bind-pose mesh block out of a puppet `.mdl`. Skeleton
/// ("MDLS"), animation ("MDLA") and attachment ("MDAT") blocks are read-only
/// bounds here; this reader never interprets them.
enum SceneMdlPuppetMeshReader {
    private static let vertexStridesByMagic = [
        "MDLV0014": [52],
        "MDLV0016": [52],
        "MDLV0017": [80, 84],
        "MDLV0019": [80],
        "MDLV0021": [80, 84],
        // 48: proven by the real Workshop puppet asset in sample 3767232084
        // (224 vertices, indices 0...223 with full coverage, finite positions
        // spanning the authored 1920x1080 layer and UVs in [0, 1]).
        "MDLV0023": [48, 80, 84],
    ]
    private static let magicLength = 8
    // Magic + trailing NUL, matching the audited player's marker size.
    private static let markerSize = 9
    private static let meshHeaderSize = 8
    // Verified vertex layouts: 52 bytes across MDLV0014/0016 assets, 80 bytes
    // across MDLV0017/0023 assets, 84 bytes for the verified skinned base
    // asset, and 48 bytes proven by the real Workshop puppet asset in sample
    // 3767232084 (224 vertices, indices 0...223 with full coverage, finite
    // positions spanning the authored 1920x1080 layer, UVs within
    // [-0.004, 1.005]). Other version/stride pairs fail closed until a real
    // asset proves them.
    private static let maxAbsolutePosition: Float = 1_000_000
    private static let maxAbsoluteUV: Float = 64

    static func read(data rawData: Data) throws -> SceneMdlPuppetMesh {
        // Normalize to a zero-based Data so absolute offsets stay valid for slices.
        let data = rawData.startIndex == 0 ? rawData : Data(rawData)
        guard data.count > markerSize + meshHeaderSize else {
            throw SceneMdlPuppetMeshReadError.fileTooSmall
        }
        let magic = String(decoding: data.prefix(magicLength), as: UTF8.self)
        guard let vertexStrides = vertexStridesByMagic[magic] else {
            throw SceneMdlPuppetMeshReadError.unsupportedMagic(magic)
        }
        let searchBound = firstOccurrence(of: "MDLS", in: data) ?? data.count
        guard let block = findMeshBlock(
            in: data,
            bound: searchBound,
            vertexStrides: vertexStrides
        ) else {
            throw SceneMdlPuppetMeshReadError.meshBlockNotFound
        }
        return try decode(block: block, magic: magic, data: data, meshBound: searchBound)
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
    // self-consistent vertex/index block. Preserve the established first match
    // whose maximum index reaches the last vertex (this does not imply every
    // vertex is used). If no such match exists, an unreferenced tail is legal
    // only when the entire bounded scan has exactly one index-safe layout.
    private static func findMeshBlock(
        in data: Data,
        bound: Int,
        vertexStrides: [Int]
    ) -> MeshBlock? {
        guard bound > markerSize + meshHeaderSize + 4 else { return nil }
        var unusedTailCandidate: MeshBlock?
        var unusedTailIsAmbiguous = false
        for offset in markerSize ..< (bound - meshHeaderSize - 4) {
            let vertexBytes = Int(readUInt32(data, at: offset + 4))
            guard vertexBytes > 0 else { continue }
            let verticesOffset = offset + meshHeaderSize
            let indexLengthOffset = verticesOffset + vertexBytes
            guard indexLengthOffset + 4 <= bound else { continue }
            let indexBytes = Int(readUInt32(data, at: indexLengthOffset))
            guard indexBytes > 0,
                  indexBytes % 6 == 0,
                  indexLengthOffset + 4 + indexBytes <= bound else { continue }
            let strides = vertexStrides.filter { stride in
                vertexBytes % stride == 0 && vertexBytes / stride >= 3
            }
            guard strides.isEmpty == false else { continue }
            let indicesOffset = indexLengthOffset + 4
            guard let maxIndex = maxUInt16(
                data, at: indicesOffset, count: indexBytes / 2
            ) else { continue }
            for stride in strides {
                let vertexCount = vertexBytes / stride
                // The old terminal-index proof implicitly bounded the vertex
                // count to UInt16's address space. Keep that allocation bound.
                guard vertexCount <= Int(UInt16.max) + 1,
                      Int(maxIndex) < vertexCount else { continue }
                let candidate = MeshBlock(
                    offset: offset,
                    stride: stride,
                    vertexCount: vertexCount,
                    vertexBytesOffset: verticesOffset,
                    indexCount: indexBytes / 2,
                    indexBytesOffset: indicesOffset
                )
                if Int(maxIndex) == vertexCount - 1 { return candidate }
                if unusedTailCandidate == nil {
                    unusedTailCandidate = candidate
                } else {
                    unusedTailIsAmbiguous = true
                }
            }
        }
        return unusedTailIsAmbiguous ? nil : unusedTailCandidate
    }

    private static func decode(
        block: MeshBlock,
        magic: String,
        data: Data,
        meshBound: Int
    ) throws -> SceneMdlPuppetMesh {
        var vertices: [SceneMdlPuppetMesh.Vertex] = []
        vertices.reserveCapacity(block.vertexCount)
        let uvOffset = block.stride - 8
        for index in 0 ..< block.vertexCount {
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
                  abs(v) <= maxAbsoluteUV
            else {
                throw SceneMdlPuppetMeshReadError.vertexDataOutOfRange(vertexIndex: index)
            }
            vertices.append(.init(x: x, y: y, z: z, u: u, v: v))
        }
        var indices: [UInt16] = []
        indices.reserveCapacity(block.indexCount)
        for index in 0 ..< block.indexCount {
            indices.append(readUInt16(data, at: block.indexBytesOffset + index * 2))
        }
        let metadata = try readClippingMetadata(
            data: data, magic: magic,
            offset: block.indexBytesOffset + block.indexCount * 2,
            bound: meshBound, vertexCount: block.vertexCount, indexCount: block.indexCount
        )
        return SceneMdlPuppetMesh(
            version: magic,
            vertexStride: block.stride,
            meshBlockOffset: block.offset,
            vertices: vertices,
            indices: indices,
            drawParts: metadata.parts,
            clipRecords: metadata.clips
        )
    }

    // Public authored MDLV0023 data and controlled official record-removal
    // probes establish this suffix. The optional vec3 stream remains opaque;
    // it does not replace the current prepared position/weight stream.
    private static func readClippingMetadata(
        data: Data, magic: String, offset: Int, bound: Int,
        vertexCount: Int, indexCount: Int
    ) throws -> (parts: [SceneMdlPuppetMesh.DrawPart], clips: [SceneMdlPuppetMesh.ClipRecord]) {
        // Older versions keep their existing mesh-only contract. Bare meshes
        // and synthetic bind/attachment fixtures have no suffix to consume.
        guard magic == "MDLV0023", offset < bound else { return ([], []) }
        // Existing exports also use a seven-zero-byte empty suffix. Preserve
        // this exact no-stream/no-parts/no-clips shape without interpreting
        // its final byte or swallowing malformed populated metadata.
        if bound - offset == 7, data[offset ..< bound].allSatisfy({ $0 == 0 }) {
            return ([], [])
        }
        var cursor = offset
        let hasExtraStream = try readPresence(data, cursor: &cursor, bound: bound)
        if hasExtraStream {
            guard cursor + 8 <= bound,
                  readUInt32(data, at: cursor) == 1 else {
                throw SceneMdlPuppetMeshReadError.invalidClippingLayout
            }
            let byteCount = Int(readUInt32(data, at: cursor + 4))
            cursor += 8
            guard byteCount == vertexCount * 12, byteCount <= bound - cursor else {
                throw SceneMdlPuppetMeshReadError.invalidClippingLayout
            }
            cursor += byteCount
        }
        let hasParts = try readPresence(data, cursor: &cursor, bound: bound)
        var parts: [SceneMdlPuppetMesh.DrawPart] = []
        if hasParts {
            guard cursor + 4 <= bound else {
                throw SceneMdlPuppetMeshReadError.invalidClippingLayout
            }
            let byteCount = Int(readUInt32(data, at: cursor))
            cursor += 4
            guard byteCount > 0, byteCount % 16 == 0, byteCount <= bound - cursor else {
                throw SceneMdlPuppetMeshReadError.invalidClippingLayout
            }
            let partCount = byteCount / 16
            parts.reserveCapacity(partCount)
            var expectedIndexOffset = 0
            for ordinal in 0 ..< partCount {
                let id = readUInt32(data, at: cursor)
                let flags = readUInt32(data, at: cursor + 4)
                let start = Int(readUInt32(data, at: cursor + 8))
                let count = Int(readUInt32(data, at: cursor + 12))
                guard flags == 0, start == expectedIndexOffset,
                      count % 3 == 0, count <= indexCount - start else {
                    throw SceneMdlPuppetMeshReadError.invalidDrawPart(ordinal: ordinal)
                }
                parts.append(.init(ordinal: ordinal, id: id, flags: flags,
                                   indexOffset: start, indexCount: count))
                expectedIndexOffset += count
                cursor += 16
            }
            guard expectedIndexOffset == indexCount else {
                throw SceneMdlPuppetMeshReadError.invalidDrawPart(ordinal: partCount - 1)
            }
        }
        guard cursor + 4 <= bound else {
            throw SceneMdlPuppetMeshReadError.invalidClippingLayout
        }
        let clipCount = Int(readUInt32(data, at: cursor))
        cursor += 4
        // Each supported record has two words, a nonempty NUL path, four
        // relation words, and at least one source ordinal.
        guard clipCount <= (bound - cursor) / 30 else {
            throw SceneMdlPuppetMeshReadError.invalidClippingLayout
        }
        var clips: [SceneMdlPuppetMesh.ClipRecord] = []
        var targets: Set<Int> = []
        clips.reserveCapacity(clipCount)
        for index in 0 ..< clipCount {
            guard cursor + 8 <= bound else {
                throw SceneMdlPuppetMeshReadError.invalidClipRecord(index: index)
            }
            let id = readUInt32(data, at: cursor)
            let flags = readUInt32(data, at: cursor + 4)
            cursor += 8
            let path = try readMaskPath(data, cursor: &cursor, bound: bound, recordIndex: index)
            guard cursor + 16 <= bound else {
                throw SceneMdlPuppetMeshReadError.invalidClipRecord(index: index)
            }
            let options = SIMD2(readUInt32(data, at: cursor), readUInt32(data, at: cursor + 4))
            let target = Int(readUInt32(data, at: cursor + 8))
            let sourceCount = Int(readUInt32(data, at: cursor + 12))
            cursor += 16
            guard flags == 0, options == SIMD2<UInt32>(0, 1) else {
                throw SceneMdlPuppetMeshReadError.unsupportedClippingOptions(index: index)
            }
            guard parts.indices.contains(target), targets.insert(target).inserted,
                  sourceCount > 0, sourceCount <= (bound - cursor) / 4 else {
                throw SceneMdlPuppetMeshReadError.invalidClipRecord(index: index)
            }
            var sources: [Int] = []
            sources.reserveCapacity(sourceCount)
            for _ in 0 ..< sourceCount {
                let source = Int(readUInt32(data, at: cursor))
                guard parts.indices.contains(source) else {
                    throw SceneMdlPuppetMeshReadError.invalidClipRecord(index: index)
                }
                // Keep raw self candidates. Painted coverage and the prepared
                // execution contract decide participation, not ordinal equality.
                sources.append(source)
                cursor += 4
            }
            clips.append(.init(id: id, flags: flags, rawOptions: options,
                maskTexturePath: path, targetPartOrdinal: target, sourcePartOrdinals: sources))
        }
        guard cursor == bound else {
            throw SceneMdlPuppetMeshReadError.invalidClippingLayout
        }
        return (parts, clips)
    }

    private static func readPresence(_ data: Data, cursor: inout Int, bound: Int) throws -> Bool {
        guard cursor < bound, data[cursor] <= 1 else {
            throw SceneMdlPuppetMeshReadError.invalidClippingLayout
        }
        let result = data[cursor] == 1
        cursor += 1
        return result
    }

    private static func readMaskPath(
        _ data: Data, cursor: inout Int, bound: Int, recordIndex: Int
    ) throws -> String {
        guard cursor < bound,
              let terminator = data[cursor ..< bound].firstIndex(of: 0), terminator > cursor,
              let value = String(data: data[cursor ..< terminator], encoding: .utf8) else {
            throw SceneMdlPuppetMeshReadError.invalidClipRecord(index: recordIndex)
        }
        cursor = terminator + 1
        return value
    }

    private static func firstOccurrence(of marker: String, in data: Data) -> Int? {
        guard let range = data.range(
            of: Data(marker.utf8),
            options: [],
            in: markerSize ..< data.count
        ) else { return nil }
        return range.lowerBound
    }

    private static func maxUInt16(_ data: Data, at offset: Int, count: Int) -> UInt16? {
        guard count > 0, offset + count * 2 <= data.count else { return nil }
        var maxValue: UInt16 = 0
        for index in 0 ..< count {
            maxValue = max(maxValue, readUInt16(data, at: offset + index * 2))
        }
        return maxValue
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { buffer in
            data.copyBytes(to: buffer, from: offset ..< (offset + 4))
        }
        return UInt32(littleEndian: value)
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        var value: UInt16 = 0
        _ = withUnsafeMutableBytes(of: &value) { buffer in
            data.copyBytes(to: buffer, from: offset ..< (offset + 2))
        }
        return UInt16(littleEndian: value)
    }

    private static func readFloat(_ data: Data, at offset: Int) -> Float {
        Float(bitPattern: readUInt32(data, at: offset))
    }
}
