import Foundation

struct SceneMdlPuppetAttachment {
    let boneIndex: Int
    let name: String
    let modelBindFrameColumnMajor: [Float]

    nonisolated var sceneBindFrameColumnMajor: [Float] {
        let axisSign: [Float] = [1, -1, 1, 1]
        return modelBindFrameColumnMajor.enumerated().map { index, value in
            let column = index / 4
            let row = index % 4
            return value * axisSign[row] * axisSign[column]
        }
    }
}

enum SceneMdlPuppetAttachmentReadError: Error, CustomStringConvertible, Equatable, Sendable {
    case unsupportedMagic(String)
    case skeletonBlockMissing
    case invalidSkeletonBounds
    case invalidBoneCount(Int)
    case invalidBoneRecord(Int)
    case invalidBoneParent(boneIndex: Int, parentIndex: Int)
    case invalidMatrix(record: String)
    case invalidAttachmentBounds
    case invalidAttachmentCount(Int)
    case invalidAttachmentBone(name: String, boneIndex: Int)
    case invalidAttachmentName
    case duplicateAttachmentName(String)

    nonisolated var description: String {
        switch self {
        case .unsupportedMagic(let magic):
            return "unsupported attachment mdl magic \(magic)"
        case .skeletonBlockMissing:
            return "MDAT requires a preceding MDLS0004 block"
        case .invalidSkeletonBounds:
            return "invalid MDLS0004 bounds"
        case .invalidBoneCount(let count):
            return "invalid MDLS0004 bone count \(count)"
        case .invalidBoneRecord(let index):
            return "invalid MDLS0004 bone record \(index)"
        case .invalidBoneParent(let boneIndex, let parentIndex):
            return "invalid parent \(parentIndex) for bone \(boneIndex)"
        case .invalidMatrix(let record):
            return "invalid affine matrix for \(record)"
        case .invalidAttachmentBounds:
            return "invalid MDAT0001 bounds"
        case .invalidAttachmentCount(let count):
            return "invalid MDAT0001 attachment count \(count)"
        case .invalidAttachmentBone(let name, let boneIndex):
            return "attachment \(name) references missing bone \(boneIndex)"
        case .invalidAttachmentName:
            return "empty or oversized MDAT0001 attachment name"
        case .duplicateAttachmentName(let name):
            return "duplicate MDAT0001 attachment name \(name)"
        }
    }
}

// Restricted reader for the MDLS0004 bind skeleton and MDAT0001 attachment
// blocks verified for the MDLV0023 container contract. This does not interpret
// weights, constraints, or MDLA animation data.
enum SceneMdlPuppetAttachmentReader {
    private static let mdlMagic = "MDLV0023"
    private static let markerSize = 9
    private static let matrixByteCount = 64
    private static let maxBoneCount = 4_096
    private static let maxAttachmentCount = 1_024
    private static let maxNameBytes = 1_024
    private static let maxMetadataBytes = 64 * 1_024
    private static let maxAbsoluteMatrixValue: Float = 1_000_000

    static func read(data rawData: Data) throws -> [SceneMdlPuppetAttachment] {
        let data = rawData.startIndex == 0 ? rawData : Data(rawData)
        guard let attachmentOffset = occurrence(of: "MDAT0001", in: data) else {
            return []
        }
        let magic = String(decoding: data.prefix(8), as: UTF8.self)
        guard magic == mdlMagic else {
            throw SceneMdlPuppetAttachmentReadError.unsupportedMagic(magic)
        }
        guard let skeletonOffset = occurrence(of: "MDLS0004", in: data),
              skeletonOffset < attachmentOffset else {
            throw SceneMdlPuppetAttachmentReadError.skeletonBlockMissing
        }
        let boneFrames = try readBoneFrames(
            data: data,
            blockOffset: skeletonOffset,
            expectedEndOffset: attachmentOffset
        )
        return try readAttachments(
            data: data,
            blockOffset: attachmentOffset,
            boneFrames: boneFrames
        )
    }

    private static func readBoneFrames(
        data: Data,
        blockOffset: Int,
        expectedEndOffset: Int
    ) throws -> [[Float]] {
        var cursor = blockOffset + markerSize
        guard cursor + 8 <= data.count else {
            throw SceneMdlPuppetAttachmentReadError.invalidSkeletonBounds
        }
        let endOffset = Int(readUInt32(data, at: cursor))
        cursor += 4
        guard endOffset == expectedEndOffset, endOffset <= data.count else {
            throw SceneMdlPuppetAttachmentReadError.invalidSkeletonBounds
        }
        let boneCount = Int(readUInt32(data, at: cursor))
        cursor += 4
        guard boneCount > 0, boneCount <= maxBoneCount else {
            throw SceneMdlPuppetAttachmentReadError.invalidBoneCount(boneCount)
        }

        var worldFrames: [[Float]] = []
        worldFrames.reserveCapacity(boneCount)
        for boneIndex in 0..<boneCount {
            guard let nameEnd = nullTerminator(
                in: data, from: cursor, bound: endOffset, maxBytes: maxNameBytes
            ) else {
                throw SceneMdlPuppetAttachmentReadError.invalidBoneRecord(boneIndex)
            }
            cursor = nameEnd + 1
            guard cursor + 12 + matrixByteCount <= endOffset else {
                throw SceneMdlPuppetAttachmentReadError.invalidBoneRecord(boneIndex)
            }
            let state = readUInt32(data, at: cursor)
            cursor += 4
            let parentIndex = Int(readInt32(data, at: cursor))
            cursor += 4
            let byteCount = Int(readUInt32(data, at: cursor))
            cursor += 4
            guard state <= 1, byteCount == matrixByteCount else {
                throw SceneMdlPuppetAttachmentReadError.invalidBoneRecord(boneIndex)
            }
            guard parentIndex >= -1, parentIndex < boneIndex else {
                throw SceneMdlPuppetAttachmentReadError.invalidBoneParent(
                    boneIndex: boneIndex,
                    parentIndex: parentIndex
                )
            }
            let localFrame = try readMatrix(
                data: data,
                at: cursor,
                record: "bone \(boneIndex)"
            )
            cursor += matrixByteCount
            guard let metadataEnd = nullTerminator(
                in: data, from: cursor, bound: endOffset, maxBytes: maxMetadataBytes
            ) else {
                throw SceneMdlPuppetAttachmentReadError.invalidBoneRecord(boneIndex)
            }
            cursor = metadataEnd + 1
            let worldFrame = parentIndex >= 0
                ? multiply(worldFrames[parentIndex], localFrame)
                : localFrame
            worldFrames.append(worldFrame)
        }
        return worldFrames
    }

    private static func readAttachments(
        data: Data,
        blockOffset: Int,
        boneFrames: [[Float]]
    ) throws -> [SceneMdlPuppetAttachment] {
        var cursor = blockOffset + markerSize
        guard cursor + 6 <= data.count else {
            throw SceneMdlPuppetAttachmentReadError.invalidAttachmentBounds
        }
        let endOffset = Int(readUInt32(data, at: cursor))
        cursor += 4
        guard endOffset > cursor, endOffset <= data.count else {
            throw SceneMdlPuppetAttachmentReadError.invalidAttachmentBounds
        }
        let count = Int(readUInt16(data, at: cursor))
        cursor += 2
        guard count > 0, count <= maxAttachmentCount else {
            throw SceneMdlPuppetAttachmentReadError.invalidAttachmentCount(count)
        }

        var names: Set<String> = []
        var attachments: [SceneMdlPuppetAttachment] = []
        attachments.reserveCapacity(count)
        for index in 0..<count {
            guard cursor + 2 <= endOffset else {
                throw SceneMdlPuppetAttachmentReadError.invalidAttachmentBounds
            }
            let boneIndex = Int(readUInt16(data, at: cursor))
            cursor += 2
            guard let nameEnd = nullTerminator(
                in: data, from: cursor, bound: endOffset, maxBytes: maxNameBytes
            ) else {
                throw SceneMdlPuppetAttachmentReadError.invalidAttachmentName
            }
            let name = String(decoding: data[cursor..<nameEnd], as: UTF8.self)
            cursor = nameEnd + 1
            guard name.isEmpty == false else {
                throw SceneMdlPuppetAttachmentReadError.invalidAttachmentName
            }
            guard names.insert(name).inserted else {
                throw SceneMdlPuppetAttachmentReadError.duplicateAttachmentName(name)
            }
            guard boneFrames.indices.contains(boneIndex) else {
                throw SceneMdlPuppetAttachmentReadError.invalidAttachmentBone(
                    name: name,
                    boneIndex: boneIndex
                )
            }
            guard cursor + matrixByteCount <= endOffset else {
                throw SceneMdlPuppetAttachmentReadError.invalidAttachmentBounds
            }
            let localFrame = try readMatrix(
                data: data,
                at: cursor,
                record: "attachment \(index)"
            )
            cursor += matrixByteCount
            attachments.append(SceneMdlPuppetAttachment(
                boneIndex: boneIndex,
                name: name,
                modelBindFrameColumnMajor: multiply(boneFrames[boneIndex], localFrame)
            ))
        }
        guard cursor == endOffset else {
            throw SceneMdlPuppetAttachmentReadError.invalidAttachmentBounds
        }
        return attachments
    }

    private static func readMatrix(
        data: Data,
        at offset: Int,
        record: String
    ) throws -> [Float] {
        var values: [Float] = []
        values.reserveCapacity(16)
        for index in 0..<16 {
            let value = readFloat(data, at: offset + index * 4)
            guard value.isFinite, abs(value) <= maxAbsoluteMatrixValue else {
                throw SceneMdlPuppetAttachmentReadError.invalidMatrix(record: record)
            }
            values.append(value)
        }
        let epsilon: Float = 0.0001
        guard abs(values[3]) <= epsilon,
              abs(values[7]) <= epsilon,
              abs(values[11]) <= epsilon,
              abs(values[15] - 1) <= epsilon else {
            throw SceneMdlPuppetAttachmentReadError.invalidMatrix(record: record)
        }
        return values
    }

    private static func multiply(_ lhs: [Float], _ rhs: [Float]) -> [Float] {
        var result = Array(repeating: Float.zero, count: 16)
        for column in 0..<4 {
            for row in 0..<4 {
                for index in 0..<4 {
                    result[column * 4 + row] += lhs[index * 4 + row]
                        * rhs[column * 4 + index]
                }
            }
        }
        return result
    }

    private static func occurrence(of marker: String, in data: Data) -> Int? {
        data.range(of: Data(marker.utf8))?.lowerBound
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
