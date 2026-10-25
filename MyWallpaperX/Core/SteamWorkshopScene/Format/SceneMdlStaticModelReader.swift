import Foundation
import simd

nonisolated enum SceneMdlStaticModelReadError: Error, CustomStringConvertible,
    Equatable, Sendable {
    case truncated(section: String)
    case unsupportedMagic(String)
    case unsupportedHeaderFormat(UInt32)
    case unsupportedMeshCount(UInt32)
    case unsupportedMaterialCount(UInt32)
    case materialSegmentBudgetExceeded(UInt32)
    case invalidMaterialPath
    case unsupportedIndexFlag(UInt32)
    case invalidBounds
    case unsupportedVertexFormat(UInt32)
    case invalidVertexByteCount(UInt32)
    case vertexBudgetExceeded(UInt32)
    case nonFiniteVertexData(vertexIndex: Int)
    case vertexDataOutOfRange(vertexIndex: Int)
    case invalidIndexByteCount(UInt32)
    case indexBudgetExceeded(UInt32)
    case indexOutOfRange(indexPosition: Int, value: UInt32, vertexCount: Int)
    case invalidTrailer
    case invalidRequiredRig(String)

    nonisolated var description: String {
        switch self {
        case .truncated(let section):
            return "static mdl truncated in \(section)"
        case .unsupportedMagic(let magic):
            return "unsupported static mdl magic \(magic)"
        case .unsupportedHeaderFormat(let value):
            return "unsupported static mdl header format \(value)"
        case .unsupportedMeshCount(let value):
            return "unsupported static mdl mesh count \(value)"
        case .unsupportedMaterialCount(let value):
            return "unsupported static mdl material count \(value)"
        case .materialSegmentBudgetExceeded(let value):
            return "static mdl material segment work budget exceeded: \(value)"
        case .invalidMaterialPath:
            return "invalid static mdl material path"
        case .unsupportedIndexFlag(let value):
            return "unsupported static mdl index flag \(value)"
        case .invalidBounds:
            return "invalid static mdl bounds"
        case .unsupportedVertexFormat(let value):
            return "unsupported static mdl vertex format \(value)"
        case .invalidVertexByteCount(let value):
            return "invalid static mdl vertex byte count \(value)"
        case .vertexBudgetExceeded(let value):
            return "static mdl vertex byte budget exceeded: \(value)"
        case .nonFiniteVertexData(let vertexIndex):
            return "non-finite static mdl vertex data at index \(vertexIndex)"
        case .vertexDataOutOfRange(let vertexIndex):
            return "static mdl vertex data out of range at index \(vertexIndex)"
        case .invalidIndexByteCount(let value):
            return "invalid static mdl index byte count \(value)"
        case .indexBudgetExceeded(let value):
            return "static mdl index byte budget exceeded: \(value)"
        case let .indexOutOfRange(position, value, vertexCount):
            return "static mdl index \(value) at \(position) exceeds vertex count \(vertexCount)"
        case .invalidTrailer:
            return "invalid static mdl trailer"
        case .invalidRequiredRig(let reason):
            return "invalid required bind rig: \(reason)"
        }
    }
}

/// Strict reader for the direct static-model shapes observed in bounded authored
/// MDLV0016/MDLV0023 content, plus one fully validated MDLV0023 rigged bind
/// layout. Animation admission is separate; no mesh search or image projection
/// can replace the complete direct-model envelope proof.
nonisolated enum SceneMdlStaticModelReader {
    private static let boundsHeaderVersion = "MDLV0023"
    private static let derivedBoundsVersion = "MDLV0016"
    private static let supportedVersions: Set<String> = [
        boundsHeaderVersion, derivedBoundsVersion,
    ]
    private static let magicByteCount = 9
    private static let supportedFormat: UInt32 = 15
    private static let riggedBindFormat: UInt32 = 0x0180000f
    private static let boundsHeaderTrailerByteCount = 7
    private static let derivedBoundsTrailerByteCount = 1
    private static let maximumPathByteCount = 4_096
    /// Per-model load work budget, not a format maximum.
    private static let maximumMaterialSegmentCount: UInt32 = 64
    private static let maximumVertexByteCount: UInt32 = 256 * 1_024 * 1_024
    private static let maximumIndexByteCount: UInt32 = 32 * 1_024 * 1_024
    private static let maximumAbsoluteValue: Float = 1_000_000

    static func read(data rawData: Data) throws -> SceneMdlStaticModel {
        let parts = try readParts(data: rawData)
        guard parts.count == 1 else {
            throw SceneMdlStaticModelReadError.unsupportedMaterialCount(UInt32(parts.count))
        }
        return parts[0]
    }

    /// Each authored material segment retains its own geometry and local indices.
    /// Validate the complete model before publishing any segment.
    static func readParts(data rawData: Data) throws -> [SceneMdlStaticModel] {
        try rawData.withUnsafeBytes { bytes in
            var cursor = Cursor(data: bytes)
            return try readParts(cursor: &cursor, sourceData: rawData)
        }
    }

    private static func readParts(
        cursor: inout Cursor, sourceData: Data
    ) throws -> [SceneMdlStaticModel] {
        let header = try readHeader(cursor: &cursor)
        var parts: [SceneMdlStaticModel] = []
        var totalVertexBytes: UInt32 = 0
        var totalIndexBytes: UInt32 = 0
        let bindOnly = header.geometryState == .bindOnlyAnimationUnqualified
        for ordinal in 0..<header.materialCount {
            let materialPath: String
            if ordinal == 0 {
                materialPath = header.materialPath
            } else {
                let separator = try cursor.readBytes(
                    count: header.version == boundsHeaderVersion ? 6 : 0,
                    section: "material separator"
                )
                guard separator.allSatisfy({ $0 == 0 }) else {
                    throw SceneMdlStaticModelReadError.invalidTrailer
                }
                materialPath = try readMaterialPath(cursor: &cursor)
            }
            let flag = try cursor.readUInt32(section: "index flag")
            guard flag <= 1, !bindOnly || flag == 0 else {
                throw SceneMdlStaticModelReadError.unsupportedIndexFlag(flag)
            }
            let bounds = header.version == boundsHeaderVersion
                ? try readBounds(cursor: &cursor) : nil
            let format = try cursor.readUInt32(section: "vertex format")
            guard format == header.headerFormat else {
                throw SceneMdlStaticModelReadError.unsupportedVertexFormat(format)
            }
            let vertexBytes = try cursor.readUInt32(section: "vertex byte count")
            guard vertexBytes > 0,
                  vertexBytes % UInt32(header.vertexStride) == 0 else {
                throw SceneMdlStaticModelReadError.invalidVertexByteCount(vertexBytes)
            }
            guard vertexBytes <= maximumVertexByteCount - totalVertexBytes else {
                throw SceneMdlStaticModelReadError.vertexBudgetExceeded(vertexBytes)
            }
            totalVertexBytes += vertexBytes
            let vertexDataOffset = cursor.offset
            let vertices = try readVertices(
                cursor: &cursor, byteCount: vertexBytes, authoredBounds: bounds,
                stride: header.vertexStride
            )
            let indexBytes = try cursor.readUInt32(section: "index byte count")
            let elementSize = flag == 0 ? 2 : 4
            guard indexBytes > 0, indexBytes % UInt32(elementSize * 3) == 0 else {
                throw SceneMdlStaticModelReadError.invalidIndexByteCount(indexBytes)
            }
            guard indexBytes <= maximumIndexByteCount - totalIndexBytes else {
                throw SceneMdlStaticModelReadError.indexBudgetExceeded(indexBytes)
            }
            totalIndexBytes += indexBytes
            let indices = try readIndices(
                cursor: &cursor, byteCount: indexBytes,
                vertexCount: Int(vertexBytes) / header.vertexStride, elementSize: elementSize
            )
            var rig: SceneMdlPuppetRig?
            if bindOnly {
                // Exact empty extra-stream/part/clip suffix. The required rig
                // starts here; neither a marker scan nor first-mesh recovery
                // may skip malformed direct-model fields.
                let suffix = try cursor.readBytes(count: 6, section: "bind mesh suffix")
                guard suffix.allSatisfy({ $0 == 0 }) else {
                    throw SceneMdlStaticModelReadError.invalidTrailer
                }
                do {
                    rig = try SceneMdlPuppetRigReader.read(
                        data: sourceData,
                        vertexLayout: .init(
                            version: header.version, vertexStride: header.vertexStride,
                            vertexDataOffset: vertexDataOffset,
                            vertexCount: Int(vertexBytes) / header.vertexStride
                        ), skeletonOffset: cursor.offset
                    )
                } catch {
                    // Rig safety is mandatory even though animation is not
                    // consumed. Its failure rejects this complete model.
                    throw SceneMdlStaticModelReadError.invalidRequiredRig(
                        String(describing: error)
                    )
                }
            }
            parts.append(.init(
                version: header.version, headerFormat: Int(header.headerFormat),
                vertexFormat: Int(format), vertexStride: header.vertexStride,
                indexElementSize: elementSize, materialPath: materialPath,
                bounds: bounds ?? derivedBounds(vertices: vertices),
                vertices: vertices, indices: indices,
                geometryState: header.geometryState, rig: rig
            ))
        }
        // The bind-only branch consumes exactly through the mesh/rig boundary.
        // Optional MDLA and unprojected skeleton fields are not animation proof.
        if bindOnly { return parts }
        let trailer = try cursor.readBytes(
            count: header.version == boundsHeaderVersion
                ? boundsHeaderTrailerByteCount : derivedBoundsTrailerByteCount,
            section: "trailer"
        )
        guard trailer.allSatisfy({ $0 == 0 }), cursor.isAtEnd else {
            throw SceneMdlStaticModelReadError.invalidTrailer
        }
        return parts
    }

    private struct Header {
        let version: String
        let headerFormat: UInt32
        let materialPath: String
        let materialCount: Int
        let vertexStride: Int
        let geometryState: SceneMdlStaticModel.GeometryState
    }

    private static func readHeader(cursor: inout Cursor) throws -> Header {
        let magicBytes = try cursor.readBytes(
            count: magicByteCount,
            section: "magic"
        )
        let version = String(decoding: magicBytes.prefix(8), as: UTF8.self)
        guard supportedVersions.contains(version), magicBytes.last == 0 else {
            throw SceneMdlStaticModelReadError.unsupportedMagic(version)
        }

        let headerFormat = try cursor.readUInt32(section: "header format")
        let bindOnly = version == boundsHeaderVersion && headerFormat == riggedBindFormat
        guard headerFormat == supportedFormat || bindOnly else {
            throw SceneMdlStaticModelReadError.unsupportedHeaderFormat(headerFormat)
        }
        let meshCount = try cursor.readUInt32(section: "mesh count")
        guard meshCount == 1 else {
            throw SceneMdlStaticModelReadError.unsupportedMeshCount(meshCount)
        }
        let materialCount = try cursor.readUInt32(section: "material count")
        guard materialCount > 0,
              materialCount == 1 || (version == boundsHeaderVersion && !bindOnly) else {
            throw SceneMdlStaticModelReadError.unsupportedMaterialCount(materialCount)
        }
        guard materialCount <= maximumMaterialSegmentCount else {
            throw SceneMdlStaticModelReadError.materialSegmentBudgetExceeded(materialCount)
        }
        let materialPath = try readMaterialPath(cursor: &cursor)
        return .init(
            version: version, headerFormat: headerFormat,
            materialPath: materialPath, materialCount: Int(materialCount),
            vertexStride: bindOnly ? 80 : 48,
            geometryState: bindOnly ? .bindOnlyAnimationUnqualified : .authoredStatic
        )
    }

    private static func readMaterialPath(cursor: inout Cursor) throws -> String {
        let bytes = try cursor.readNullTerminatedBytes(
            maximumCount: maximumPathByteCount,
            section: "material path"
        )
        guard let rawPath = String(bytes: bytes, encoding: .utf8) else {
            throw SceneMdlStaticModelReadError.invalidMaterialPath
        }
        let normalized = rawPath.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard normalized.isEmpty == false,
              normalized.hasPrefix("/") == false,
              normalized.hasSuffix("/") == false,
              normalized.contains(":") == false,
              normalized.unicodeScalars.allSatisfy({ $0.value >= 0x20 }),
              components.allSatisfy({
                  $0.isEmpty == false && $0 != "." && $0 != ".."
              }) else {
            throw SceneMdlStaticModelReadError.invalidMaterialPath
        }
        return normalized
    }

    private static func readBounds(
        cursor: inout Cursor
    ) throws -> SceneMdlStaticModel.Bounds {
        let minimum = try (0..<3).map { _ in
            try cursor.readFloat(section: "bounds")
        }
        let maximum = try (0..<3).map { _ in
            try cursor.readFloat(section: "bounds")
        }
        guard minimum.allSatisfy(isAcceptedFiniteValue),
              maximum.allSatisfy(isAcceptedFiniteValue),
              zip(minimum, maximum).allSatisfy({ $0.0 <= $0.1 }) else {
            throw SceneMdlStaticModelReadError.invalidBounds
        }
        return .init(minimum: minimum, maximum: maximum)
    }

    private static func readVertices(
        cursor: inout Cursor,
        byteCount: UInt32,
        authoredBounds: SceneMdlStaticModel.Bounds?,
        stride: Int
    ) throws -> [SceneMdlStaticModel.Vertex] {
        let count = Int(byteCount) / stride
        let bytes = try cursor.readBuffer(count: Int(byteCount), section: "vertex data")
        var vertices: [SceneMdlStaticModel.Vertex] = []
        vertices.reserveCapacity(count)
        var values = [Float](repeating: 0, count: 12)
        for index in 0..<count {
            for component in values.indices {
                // Position/normal/tangent retain their first forty bytes in
                // both profiles; UV follows the rig fields only in the 80B one.
                let componentOffset = component < 10 ? component * 4
                    : stride - 8 + (component - 10) * 4
                let word = bytes.loadUnaligned(
                    fromByteOffset: index * stride + componentOffset,
                    as: UInt32.self
                )
                values[component] = Float(bitPattern: UInt32(littleEndian: word))
            }
            guard values.allSatisfy({ $0.isFinite }) else {
                throw SceneMdlStaticModelReadError.nonFiniteVertexData(
                    vertexIndex: index
                )
            }
            let position = SIMD3<Float>(values[0], values[1], values[2])
            guard values.allSatisfy(isAcceptedFiniteValue) else {
                throw SceneMdlStaticModelReadError.vertexDataOutOfRange(
                    vertexIndex: index
                )
            }
            if let bounds = authoredBounds,
               !(position.x >= bounds.minimum[0]
                   && position.y >= bounds.minimum[1]
                   && position.z >= bounds.minimum[2]
                   && position.x <= bounds.maximum[0]
                   && position.y <= bounds.maximum[1]
                   && position.z <= bounds.maximum[2]) {
                throw SceneMdlStaticModelReadError.vertexDataOutOfRange(
                    vertexIndex: index
                )
            }
            vertices.append(.init(
                position: position,
                normal: SIMD3<Float>(values[3], values[4], values[5]),
                tangent: SIMD4<Float>(values[6], values[7], values[8], values[9]),
                uv: SIMD2<Float>(values[10], values[11])
            ))
        }
        return vertices
    }

    private static func derivedBounds(
        vertices: [SceneMdlStaticModel.Vertex]
    ) -> SceneMdlStaticModel.Bounds {
        var minimum = vertices[0].position
        var maximum = minimum
        for vertex in vertices.dropFirst() {
            minimum = simd.min(minimum, vertex.position)
            maximum = simd.max(maximum, vertex.position)
        }
        return .init(
            minimum: [minimum.x, minimum.y, minimum.z],
            maximum: [maximum.x, maximum.y, maximum.z]
        )
    }

    private static func readIndices(
        cursor: inout Cursor,
        byteCount: UInt32,
        vertexCount: Int,
        elementSize: Int
    ) throws -> [UInt32] {
        let bytes = try cursor.readBuffer(count: Int(byteCount), section: "index data")
        let count = Int(byteCount) / elementSize
        var indices: [UInt32] = []
        indices.reserveCapacity(count)
        for position in 0..<count {
            let value = elementSize == 2
                ? UInt32(UInt16(littleEndian: bytes.loadUnaligned(
                    fromByteOffset: position * elementSize, as: UInt16.self)))
                : UInt32(littleEndian: bytes.loadUnaligned(
                    fromByteOffset: position * elementSize, as: UInt32.self))
            guard Int(value) < vertexCount else {
                throw SceneMdlStaticModelReadError.indexOutOfRange(
                    indexPosition: position,
                    value: value,
                    vertexCount: vertexCount
                )
            }
            indices.append(value)
        }
        return indices
    }

    private static func isAcceptedFiniteValue(_ value: Float) -> Bool {
        value.isFinite && abs(value) <= maximumAbsoluteValue
    }

    /// Borrowed only inside a public reader's withUnsafeBytes scope. Decoded
    /// values own their storage; no pointer is retained by the returned model.
    private struct Cursor {
        let data: UnsafeRawBufferPointer
        private(set) var offset = 0

        var isAtEnd: Bool { offset == data.count }

        mutating func require(count: Int, section: String) throws {
            guard count >= 0,
                  offset <= data.count,
                  count <= data.count - offset else {
                throw SceneMdlStaticModelReadError.truncated(section: section)
            }
        }

        mutating func readBytes(count: Int, section: String) throws -> Data {
            try require(count: count, section: section)
            defer { offset += count }
            return Data(data[offset..<(offset + count)])
        }

        mutating func readNullTerminatedBytes(
            maximumCount: Int,
            section: String
        ) throws -> Data {
            let availableCount = min(maximumCount + 1, data.count - offset)
            guard availableCount > 0,
                  let end = data[offset..<(offset + availableCount)]
                    .firstIndex(of: 0) else {
                throw SceneMdlStaticModelReadError.truncated(section: section)
            }
            let value = Data(data[offset..<end])
            offset = end + 1
            return value
        }

        /// Validate the entire fixed-stride block before any indexed load.
        /// The caller consumes this borrow synchronously inside the reader scope.
        mutating func readBuffer(count: Int, section: String) throws -> UnsafeRawBufferPointer {
            try require(count: count, section: section)
            defer { offset += count }
            return UnsafeRawBufferPointer(rebasing: data[offset..<(offset + count)])
        }

        mutating func readUInt32(section: String) throws -> UInt32 {
            try require(count: 4, section: section)
            let value = data.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            offset += 4
            return UInt32(littleEndian: value)
        }

        mutating func readFloat(section: String) throws -> Float {
            Float(bitPattern: try readUInt32(section: section))
        }
    }
}
