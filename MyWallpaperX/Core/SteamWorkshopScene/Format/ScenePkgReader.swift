import Foundation

struct ScenePkgIndex {
    let magic: String
    let entries: [Entry]
    let dataStartOffset: Int
    let fileSize: Int

    struct Entry: Identifiable, Equatable {
        let path: String
        let offset: UInt32
        let size: UInt32

        var id: String { path }
    }
}

struct ScenePkgReader {
    enum ReadError: LocalizedError {
        case fileTooSmall
        case invalidMagic(String)
        case truncatedTable
        case invalidPathData
        case invalidEntry(path: String, offset: UInt32, size: UInt32)

        var errorDescription: String? {
            switch self {
            case .fileTooSmall:
                return "Scene 资源包过小，无法读取 PKGV 头。"
            case let .invalidMagic(magic):
                return "Scene 资源包 magic 不匹配：\(magic)"
            case .truncatedTable:
                return "Scene 资源包文件表不完整。"
            case .invalidPathData:
                return "Scene 资源包文件表包含无法解析的路径。"
            case let .invalidEntry(path, offset, size):
                return "Scene 资源包条目越界：\(path) offset=\(offset) size=\(size)"
            }
        }
    }

    func readIndex(packageURL: URL) throws -> ScenePkgIndex {
        let data = try Data(contentsOf: packageURL)
        return try readIndex(data: data)
    }

    func readEntryData(_ entry: ScenePkgIndex.Entry, in packageURL: URL) throws -> Data {
        let data = try Data(contentsOf: packageURL)
        let index = try readIndex(data: data)
        let dataStart = index.dataStartOffset
        let start = dataStart + Int(entry.offset)
        let end = start + Int(entry.size)
        guard start >= dataStart, end <= data.count else {
            throw ReadError.invalidEntry(path: entry.path, offset: entry.offset, size: entry.size)
        }
        return data.subdata(in: start..<end)
    }

    private func readIndex(data: Data) throws -> ScenePkgIndex {
        var cursor = 0

        func readUInt32() throws -> UInt32 {
            guard cursor + 4 <= data.count else { throw ReadError.truncatedTable }
            let value = data[cursor..<(cursor + 4)].withUnsafeBytes {
                $0.loadUnaligned(as: UInt32.self).littleEndian
            }
            cursor += 4
            return value
        }

        guard data.count >= 16 else { throw ReadError.fileTooSmall }
        let magicLength = Int(try readUInt32())
        guard magicLength > 0, cursor + magicLength <= data.count else {
            throw ReadError.truncatedTable
        }

        guard let magic = String(data: data[cursor..<(cursor + magicLength)], encoding: .utf8) else {
            throw ReadError.invalidPathData
        }
        cursor += magicLength
        guard magic.hasPrefix("PKGV") else {
            throw ReadError.invalidMagic(magic)
        }

        let entryCount = Int(try readUInt32())
        var entries: [ScenePkgIndex.Entry] = []
        entries.reserveCapacity(entryCount)

        for _ in 0..<entryCount {
            let pathLength = Int(try readUInt32())
            guard pathLength > 0, cursor + pathLength <= data.count else {
                throw ReadError.truncatedTable
            }
            guard let path = String(data: data[cursor..<(cursor + pathLength)], encoding: .utf8) else {
                throw ReadError.invalidPathData
            }
            cursor += pathLength

            let offset = try readUInt32()
            let size = try readUInt32()
            entries.append(ScenePkgIndex.Entry(path: path, offset: offset, size: size))
        }

        let dataStartOffset = cursor
        let payloadSize = data.count - dataStartOffset
        for entry in entries {
            let end = UInt64(entry.offset) + UInt64(entry.size)
            guard end <= UInt64(payloadSize) else {
                throw ReadError.invalidEntry(path: entry.path, offset: entry.offset, size: entry.size)
            }
        }

        return ScenePkgIndex(
            magic: magic,
            entries: entries,
            dataStartOffset: dataStartOffset,
            fileSize: data.count
        )
    }
}
