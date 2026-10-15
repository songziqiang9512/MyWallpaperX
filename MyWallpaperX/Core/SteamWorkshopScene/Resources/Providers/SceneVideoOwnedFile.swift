import Darwin
import Foundation

/// One file lifetime shared by preparation, playback and any still-running
/// worker. Releasing the final lease removes only this private file.
nonisolated final class SceneVideoOwnedFile: Sendable {
    enum Operation: String, Sendable {
        case openSource, inspectSource, readSource, closeSource
        case createSnapshot, writeSnapshot, closeSnapshot
    }

    enum Failure: Error, Equatable, Sendable {
        case invalidSourceURL
        case invalidCacheDirectory
        case invalidFileExtension
        case invalidMaximumBytes
        case sourceNotRegularFile
        case sourceSizeInvalid
        case byteLimitExceeded
        case sourceChanged
        case cancelled
        case deadlineExceeded
        case directoryCreation(domain: String, code: Int)
        case io(operation: Operation, code: Int32)
    }

    let url: URL

    private init(url: URL) { self.url = url }

    /// Reserves an unguessable pathname, leaving the file absent for the
    /// existing payload writer (including AVAssetWriter) to create once.
    static func allocate(
        cacheDirectory: URL, fileExtension: String = "mp4"
    ) throws -> SceneVideoOwnedFile {
        SceneVideoOwnedFile(url: try allocateURL(
            cacheDirectory: cacheDirectory, fileExtension: fileExtension
        ))
    }

    /// Copies a regular source once, never reading more than 1 MiB at a time.
    /// The caller owns source identity semantics. Identity-check errors escape
    /// unchanged; cancellation and the 30-second deadline are checked between
    /// I/O operations, not promises to interrupt a blocked OS call.
    static func snapshot(
        from sourceURL: URL,
        cacheDirectory: URL,
        maximumBytes: Int = 1_024 * 1_024 * 1_024,
        isCancelled: () -> Bool = { false },
        isSourceCurrent: () throws -> Bool
    ) throws -> SceneVideoOwnedFile {
        guard sourceURL.isFileURL else { throw Failure.invalidSourceURL }
        guard maximumBytes >= 0 else { throw Failure.invalidMaximumBytes }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        func checkpoint() throws {
            guard !isCancelled() else { throw Failure.cancelled }
            guard clock.now < deadline else { throw Failure.deadlineExceeded }
        }
        try checkpoint()
        guard try isSourceCurrent() else { throw Failure.sourceChanged }
        try checkpoint()

        // Nonblocking open also prevents a substituted FIFO from hanging
        // before fstat can reject it. Callers pass their resolved source URL.
        let input = Darwin.open(sourceURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard input >= 0 else { throw Failure.io(operation: .openSource, code: errno) }
        var inputOpen = true
        defer { if inputOpen { closeDuringCleanup(input) } }
        var initial = stat()
        guard Darwin.fstat(input, &initial) == 0 else {
            throw Failure.io(operation: .inspectSource, code: errno)
        }
        guard initial.st_mode & S_IFMT == S_IFREG else { throw Failure.sourceNotRegularFile }
        guard let expectedBytes = Int(exactly: initial.st_size), expectedBytes >= 0 else {
            throw Failure.sourceSizeInvalid
        }
        guard expectedBytes <= maximumBytes else { throw Failure.byteLimitExceeded }
        try checkpoint()

        let destination = try allocateURL(cacheDirectory: cacheDirectory, fileExtension: "mp4")
        try checkpoint()
        let output = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard output >= 0 else { throw Failure.io(operation: .createSnapshot, code: errno) }
        // Ownership starts after exclusive creation; an open failure must not
        // remove a file it did not create.
        let owned = SceneVideoOwnedFile(url: destination)
        var outputOpen = true
        defer { if outputOpen { closeDuringCleanup(output) } }
        var buffer = [UInt8](repeating: 0, count: 1_024 * 1_024)
        var copied = 0
        while true {
            try checkpoint()
            // At the initial end, a one-byte probe distinguishes EOF from a
            // growing source without reading another whole chunk over budget.
            let requested = min(buffer.count, max(1, expectedBytes - copied))
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(input, bytes.baseAddress!, requested)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw Failure.io(operation: .readSource, code: errno)
            }
            try checkpoint()
            if count == 0 { break }
            guard count <= maximumBytes - copied else { throw Failure.byteLimitExceeded }
            guard count <= expectedBytes - copied else { throw Failure.sourceChanged }
            var written = 0
            while written < count {
                try checkpoint()
                let amount = buffer.withUnsafeBytes { bytes in
                    Darwin.write(output, bytes.baseAddress!.advanced(by: written), count - written)
                }
                if amount < 0 {
                    if errno == EINTR { continue }
                    throw Failure.io(operation: .writeSnapshot, code: errno)
                }
                guard amount > 0 else { throw Failure.io(operation: .writeSnapshot, code: EIO) }
                written += amount
            }
            copied += count
        }
        guard copied == expectedBytes else { throw Failure.sourceChanged }
        var final = stat()
        guard Darwin.fstat(input, &final) == 0 else {
            throw Failure.io(operation: .inspectSource, code: errno)
        }
        guard final.st_mode & S_IFMT == S_IFREG, final.st_size == initial.st_size else {
            throw Failure.sourceChanged
        }
        try checkpoint()
        guard try isSourceCurrent() else { throw Failure.sourceChanged }
        try checkpoint()
        let outputClose = Darwin.close(output)
        outputOpen = false
        guard outputClose == 0 else { throw Failure.io(operation: .closeSnapshot, code: errno) }
        let inputClose = Darwin.close(input)
        inputOpen = false
        guard inputClose == 0 else { throw Failure.io(operation: .closeSource, code: errno) }
        try checkpoint()
        return owned
    }

    private static func allocateURL(cacheDirectory: URL, fileExtension: String) throws -> URL {
        guard cacheDirectory.isFileURL else { throw Failure.invalidCacheDirectory }
        guard (1...16).contains(fileExtension.utf8.count), fileExtension.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }) else { throw Failure.invalidFileExtension }
        let directory = cacheDirectory.appendingPathComponent(
            ".mywallpaperx-scene-video-payloads", isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            let failure = error as NSError
            throw Failure.directoryCreation(domain: failure.domain, code: failure.code)
        }
        var metadata = stat()
        guard Darwin.lstat(directory.path, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFDIR else { throw Failure.invalidCacheDirectory }
        return directory.appendingPathComponent("video-\(UUID().uuidString).\(fileExtension)")
    }

    private static func closeDuringCleanup(_ descriptor: Int32) {
        if Darwin.close(descriptor) != 0 {
            NSLog("MWX video owned-file cleanup failed: operation=close errno=%d", errno)
        }
    }

    deinit {
        if Darwin.unlink(url.path) != 0 && errno != ENOENT {
            NSLog("MWX video owned-file cleanup failed: operation=unlink errno=%d", errno)
        }
    }
}
