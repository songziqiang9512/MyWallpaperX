import Foundation

extension Data {
    func uint32LE(at offset: Int) -> UInt32 {
        withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }

    func int32LE(at offset: Int) -> Int32 {
        withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(fromByteOffset: offset, as: Int32.self).littleEndian
        }
    }

    func float32LE(at offset: Int) -> Float {
        Float(bitPattern: uint32LE(at: offset))
    }

    func skipNullTerminatedString(at offset: inout Int) throws {
        guard let terminator = self[offset...].firstIndex(of: 0) else {
            throw SceneTexContainerReader.ReadError.invalidMipTable
        }
        offset = terminator + 1
    }
}
