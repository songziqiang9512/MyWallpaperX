import Foundation

/// Incrementally splits a pipe byte stream into non-empty newline-delimited
/// frames. An incomplete final frame remains buffered for the next append.
struct DaemonNewlineFrameBuffer {
    private var storage = Data()

    var pendingByteCount: Int { storage.count }

    mutating func append(_ chunk: Data) -> [Data] {
        storage.append(chunk)
        var frames: [Data] = []
        var frameStart = storage.startIndex

        while frameStart < storage.endIndex,
              let newlineIndex = storage[frameStart...].firstIndex(of: 0x0A) {
            if frameStart < newlineIndex {
                frames.append(Data(storage[frameStart..<newlineIndex]))
            }
            frameStart = storage.index(after: newlineIndex)
        }

        if frameStart > storage.startIndex {
            storage.removeSubrange(storage.startIndex..<frameStart)
        }
        return frames
    }
}

/// The shared wire framing for daemon commands and events. Protocol payload
/// types remain owned by their video or Scene endpoint.
enum DaemonNewlineJSON {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        framed(try JSONEncoder().encode(value))
    }

    static func encodeJSONObject(
        _ value: Any,
        options: JSONSerialization.WritingOptions = []
    ) throws -> Data {
        framed(try JSONSerialization.data(withJSONObject: value, options: options))
    }

    private static func framed(_ payload: Data) -> Data {
        var result = Data()
        result.reserveCapacity(payload.count + 1)
        result.append(payload)
        result.append(0x0A)
        return result
    }
}
