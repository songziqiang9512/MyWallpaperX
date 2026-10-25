import Foundation

enum WebStaticFileSignalScanner {
    private nonisolated static let maximumScanBytes: UInt64 = 1024 * 1024

    nonisolated static func containsServiceWorkerRegistration(in fileURL: URL) -> Bool {
        contains(
            asciiSignals: ["serviceworker.register", "navigator.serviceworker"],
            in: fileURL
        )
    }

    nonisolated static func containsServiceWorkerRegistration(data: Data) -> Bool {
        guard data.count <= maximumScanBytes else { return false }
        let lowered = Data(data.map { $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 })
        return ["serviceworker.register", "navigator.serviceworker"].contains { lowered.range(of: Data($0.utf8)) != nil }
    }

    private nonisolated static func contains(asciiSignals: [String], in fileURL: URL) -> Bool {
        let signals = asciiSignals.map { Data($0.utf8) }
        let overlapCount = max(0, (signals.map(\.count).max() ?? 1) - 1)
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd(), fileSize <= maximumScanBytes else {
            return false
        }
        try? handle.seek(toOffset: 0)

        var overlap = Data()
        while let data = try? handle.read(upToCount: 64 * 1024), !data.isEmpty {
            var bytes = overlap
            bytes.append(data)
            bytes.withUnsafeMutableBytes { rawBuffer in
                for index in rawBuffer.indices {
                    let byte = rawBuffer[index]
                    if byte >= 65 && byte <= 90 {
                        rawBuffer[index] = byte + 32
                    }
                }
            }
            if signals.contains(where: { bytes.range(of: $0) != nil }) {
                return true
            }
            overlap = Data(bytes.suffix(overlapCount))
        }
        return false
    }
}
