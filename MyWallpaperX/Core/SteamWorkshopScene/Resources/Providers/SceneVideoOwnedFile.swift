import AVFoundation
import Darwin
import Foundation
import ObjectiveC

/// One file lifetime shared by preparation, playback and any still-running
/// worker. Releasing the final lease removes only this private file.
nonisolated final class SceneVideoOwnedFile: Sendable {
    nonisolated(unsafe) private static var assetLeaseKey: UInt8 = 0
    private static let payloadDirectoryName = ".mywallpaperx-scene-video-payloads"
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
        case aggregateDiskBudgetExceeded
        case directoryCreation(domain: String, code: Int)
        case io(operation: Operation, code: Int32)
    }

    /// All live and in-flight Scene payload files in this process share this
    /// byte ledger. This is independent of GPU/decoded memory and OS quotas.
    final class DiskBudget: @unchecked Sendable {
        static let shared = DiskBudget(maximumBytes: 8 * 1_024 * 1_024 * 1_024)
        let maximumBytes: UInt64
        private let lock = NSLock()
        private var reserved: UInt64 = 0

        init(maximumBytes: UInt64) { self.maximumBytes = maximumBytes }

        var reservedBytes: UInt64 {
            lock.lock(); defer { lock.unlock() }
            return reserved
        }

        fileprivate func reserve(_ bytes: UInt64) throws {
            lock.lock(); defer { lock.unlock() }
            guard bytes <= maximumBytes - reserved else {
                throw Failure.aggregateDiskBudgetExceeded
            }
            reserved += bytes
        }

        fileprivate func release(_ bytes: UInt64) {
            lock.lock(); defer { lock.unlock() }
            precondition(bytes <= reserved)
            reserved -= bytes
        }
    }

    private final class Reservation: @unchecked Sendable {
        let budget: DiskBudget
        private let lock = NSLock()
        private var bytes: UInt64 = 0

        init(budget: DiskBudget) { self.budget = budget }

        func grow(by amount: UInt64) throws {
            lock.lock(); defer { lock.unlock() }
            try budget.reserve(amount)
            bytes += amount
        }

        func releaseAfterRemoval(_ removed: Bool) {
            lock.lock()
            let amount = bytes
            bytes = 0
            lock.unlock()
            // An unlink failure keeps its charge conservatively until process
            // exit; losing the lease must not make an existing file free.
            if removed { budget.release(amount) }
        }

        deinit { releaseAfterRemoval(true) }
    }

    fileprivate struct OutputRevision: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let mode: mode_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init(_ value: stat) {
            device = value.st_dev; inode = value.st_ino; size = value.st_size
            mode = value.st_mode
            modifiedSeconds = value.st_mtimespec.tv_sec
            modifiedNanoseconds = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec
            changedNanoseconds = value.st_ctimespec.tv_nsec
        }
    }

    private struct PrivateDomain: Hashable {
        let path: String
        let device: dev_t
        let inode: ino_t
    }

    private enum SuccessfulFilePurpose: Hashable {
        case sourceSnapshot, webMRemux
    }

    private struct SuccessfulFileKey: Hashable {
        let source: SceneResourceView.PackageIdentity
        let domain: PrivateDomain
        let fileExtension: String
        let budget: ObjectIdentifier
        let purpose: SuccessfulFilePurpose
    }

    /// This index never owns the file, its budget, or an author Root. Borrowed
    /// files stay strong past unlock, including temporary promotions while
    /// pruning, so their last release cannot unlink under the table lock.
    private final class SuccessfulFiles: @unchecked Sendable {
        final class Entry {
            weak var file: SceneVideoOwnedFile?
            let revision: OutputRevision

            init(file: SceneVideoOwnedFile, revision: OutputRevision) {
                self.file = file; self.revision = revision
            }
        }

        struct Borrow {
            let file: SceneVideoOwnedFile
            let entry: Entry
        }

        private let lock = NSLock()
        private var entries: [SuccessfulFileKey: Entry] = [:]

        private func prune(holding files: inout [SceneVideoOwnedFile]) {
            entries = entries.filter { _, entry in
                guard let file = entry.file else { return false }
                files.append(file)
                return true
            }
        }

        func borrow(_ key: SuccessfulFileKey) -> Borrow? {
            lock.lock()
            let result: Borrow?
            if let entry = entries[key], let file = entry.file {
                result = Borrow(file: file, entry: entry)
            } else { result = nil }
            lock.unlock()
            return result
        }

        func remove(_ key: SuccessfulFileKey, matching entry: Entry) {
            lock.lock(); defer { lock.unlock() }
            if entries[key] === entry { entries.removeValue(forKey: key) }
        }

        func insert(_ key: SuccessfulFileKey, file: SceneVideoOwnedFile,
                    revision: OutputRevision) {
            var files: [SceneVideoOwnedFile] = []
            lock.lock()
            prune(holding: &files)
            entries[key] = Entry(file: file, revision: revision)
            lock.unlock()
            withExtendedLifetime(files) {}
        }
    }

    private static let successfulFiles = SuccessfulFiles()

    /// One unpublished file writer. Its lock serializes segment callbacks and
    /// close; the process ledger lock never spans IO. No callback queues Data.
    final class Writer: @unchecked Sendable {
        let file: SceneVideoOwnedFile
        private let lock = NSLock()
        private var descriptor: Int32?
        private let expectedBytes: UInt64?
        private var written: UInt64 = 0
        private var completed = false
        private var aborted = false
        private var completedRevision: OutputRevision?

        fileprivate init(file: SceneVideoOwnedFile, descriptor: Int32, expectedBytes: UInt64?) {
            self.file = file
            self.descriptor = descriptor
            self.expectedBytes = expectedBytes
        }

        func append(_ data: Data, checkCancellation: () throws -> Void = {}) throws {
            try data.withUnsafeBytes { try append($0, checkCancellation: checkCancellation) }
        }

        func append(_ bytes: UnsafeRawBufferPointer,
                    checkCancellation: () throws -> Void = {}) throws {
            lock.lock(); defer { lock.unlock() }
            try checkCancellation()
            guard let descriptor, !completed, !aborted else {
                throw Failure.io(operation: .writeSnapshot, code: EBADF)
            }
            let count = UInt64(bytes.count)
            if let expectedBytes {
                guard count <= expectedBytes - written else { throw Failure.sourceChanged }
            } else {
                // A remux segment's actual length is known before any part of
                // it is written. Rejection leaves the whole segment unwritten.
                try file.reservation.grow(by: count)
            }
            var offset = 0
            while offset < bytes.count {
                try checkCancellation()
                let amount = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset),
                    min(64 * 1_024, bytes.count - offset))
                if amount < 0 {
                    if errno == EINTR { continue }
                    throw Failure.io(operation: .writeSnapshot, code: errno)
                }
                guard amount > 0 else { throw Failure.io(operation: .writeSnapshot, code: EIO) }
                offset += amount
                written += UInt64(amount)
            }
        }

        func finish(checkCancellation: () throws -> Void = {}) throws -> SceneVideoOwnedFile {
            lock.lock(); defer { lock.unlock() }
            try checkCancellation()
            guard let descriptor, !completed, !aborted else {
                throw Failure.io(operation: .closeSnapshot, code: EBADF)
            }
            guard expectedBytes.map({ written == $0 }) ?? true else { throw Failure.sourceChanged }
            var metadata = stat()
            guard Darwin.fstat(descriptor, &metadata) == 0,
                  metadata.st_mode & S_IFMT == S_IFREG,
                  metadata.st_size >= 0, UInt64(metadata.st_size) == written else {
                throw Failure.io(operation: .inspectSource, code: EIO)
            }
            let revision = OutputRevision(metadata)
            let result = Darwin.close(descriptor)
            self.descriptor = nil
            guard result == 0 else { throw Failure.io(operation: .closeSnapshot, code: errno) }
            try checkCancellation()
            completedRevision = revision
            completed = true
            return file
        }

        fileprivate func revisionAfterFinish() -> OutputRevision? {
            lock.lock(); defer { lock.unlock() }
            return completedRevision
        }

        func abort() {
            lock.lock(); defer { lock.unlock() }
            guard !completed, !aborted else { return }
            aborted = true
            if let descriptor {
                SceneVideoOwnedFile.closeDuringCleanup(descriptor)
                self.descriptor = nil
            }
            file.removeFile()
        }

        deinit { abort() }
    }

    let url: URL
    private let reservation: Reservation

    private init(url: URL, reservation: Reservation) {
        self.url = url
        self.reservation = reservation
    }

    /// AV items and looper clones may outlive their Scene source. The actual
    /// asset retains this lease until its last borrower releases it.
    func retainForLifetime(of asset: AVAsset) {
        objc_setAssociatedObject(
            asset, &Self.assetLeaseKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    static func makeWriter(
        cacheDirectory: URL, fileExtension: String = "mp4",
        expectedBytes: UInt64? = nil, diskBudget: DiskBudget = .shared
    ) throws -> Writer {
        let reservation = Reservation(budget: diskBudget)
        if let expectedBytes { try reservation.grow(by: expectedBytes) }
        let destination = try allocateURL(cacheDirectory: cacheDirectory, fileExtension: fileExtension)
        let output = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard output >= 0 else { throw Failure.io(operation: .createSnapshot, code: errno) }
        let file = SceneVideoOwnedFile(url: destination, reservation: reservation)
        return Writer(file: file, descriptor: output, expectedBytes: expectedBytes)
    }

    static func snapshot(
        payload: Data, cacheDirectory: URL, diskBudget: DiskBudget = .shared,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneVideoOwnedFile {
        try checkCancellation?()
        let writer = try makeWriter(cacheDirectory: cacheDirectory,
            expectedBytes: UInt64(payload.count), diskBudget: diskBudget)
        try writer.append(payload, checkCancellation: { try checkCancellation?() })
        return try writer.finish(checkCancellation: { try checkCancellation?() })
    }

    /// The request entry supplies its current source identity. This table
    /// borrows only the completed private output, never the author source.
    static func borrowCompletedWebM(
        identity: SceneResourceView.PackageIdentity,
        cacheDirectory: URL, diskBudget: DiskBudget = .shared,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneVideoOwnedFile? {
        try checkCancellation?()
        var result: SceneVideoOwnedFile?
        if let key = successfulKey(identity: identity, cacheDirectory: cacheDirectory,
                                   fileExtension: "mp4", diskBudget: diskBudget, purpose: .webMRemux),
           let borrowed = successfulFiles.borrow(key) {
            if currentOutputRevision(borrowed.file.url) == borrowed.entry.revision,
               privateDomain(borrowed.file.url.deletingLastPathComponent()) == key.domain {
                result = borrowed.file
            } else {
                successfulFiles.remove(key, matching: borrowed.entry)
            }
        }
        try checkCancellation?()
        return result
    }

    /// Registers only a closed immutable result, not a source authorization.
    /// The worker carries captured bytes and identity. No source grant is kept
    /// through media preparation; the next request selects its own identity.
    static func publishCompletedWebM(
        _ writer: Writer, identity: SceneResourceView.PackageIdentity,
        cacheDirectory: URL, diskBudget: DiskBudget = .shared,
        checkCancellation: (() throws -> Void)? = nil
    ) throws {
        try checkCancellation?()
        let file = writer.file
        var reusable: (SuccessfulFileKey, OutputRevision)?
        if file.reservation.budget === diskBudget, file.url.pathExtension == "mp4",
           let revision = writer.revisionAfterFinish(),
           currentOutputRevision(file.url) == revision,
           let key = successfulKey(identity: identity, cacheDirectory: cacheDirectory,
                                   fileExtension: "mp4", diskBudget: diskBudget, purpose: .webMRemux),
           privateDomain(file.url.deletingLastPathComponent()) == key.domain {
            reusable = (key, revision)
        }
        try checkCancellation?()
        if let (key, revision) = reusable {
            successfulFiles.insert(key, file: file, revision: revision)
        }
    }

    /// Copies an already selected Scene resource through Root's single-FD
    /// reader. Sound keeps its format and no new per-file byte/deadline limit;
    /// the aggregate disk budget applies. Source/cancellation errors escape.
    static func snapshot(
        from source: SceneResourceView.Handle,
        cacheDirectory: URL,
        fileExtension: String,
        diskBudget: DiskBudget = .shared,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneVideoOwnedFile {
        try checkCancellation?()
        let packageIdentity: SceneResourceView.PackageIdentity?
        if source.owner.packageBacking != nil {
            guard case let .package(identity) = try source.currentIdentity(
                checkCancellation: checkCancellation
            ) else { throw SceneResourceView.ReadError.invalidHandle }
            packageIdentity = identity
            if let key = successfulKey(identity: identity, cacheDirectory: cacheDirectory,
                                       fileExtension: fileExtension, diskBudget: diskBudget),
               let borrowed = successfulFiles.borrow(key) {
                if currentOutputRevision(borrowed.file.url) == borrowed.entry.revision {
                    try checkCancellation?()
                    return borrowed.file
                }
                successfulFiles.remove(key, matching: borrowed.entry)
            }
        } else { packageIdentity = nil }
        var writer: Writer?
        try source.readChunks(checkCancellation: checkCancellation, prepare: { identity in
            try checkCancellation?()
            if let packageIdentity, identity != .package(packageIdentity) {
                throw SceneResourceView.ReadError.sourceChanged
            }
            writer = try makeWriter(cacheDirectory: cacheDirectory, fileExtension: fileExtension,
                expectedBytes: identity.size, diskBudget: diskBudget)
        }) { chunk in
            guard let writer else { throw Failure.io(operation: .writeSnapshot, code: EBADF) }
            try writer.append(chunk, checkCancellation: { try checkCancellation?() })
        }
        guard let writer else { throw Failure.io(operation: .createSnapshot, code: EIO) }
        let file = try writer.finish(checkCancellation: { try checkCancellation?() })
        guard let packageIdentity else { return file }
        // readChunks completed its same-FD stability check. The private file
        // now owns that snapshot; a later author write belongs to a new request.
        var reusable: (SuccessfulFileKey, OutputRevision)?
        if let revision = writer.revisionAfterFinish(),
           currentOutputRevision(file.url) == revision,
           let key = successfulKey(identity: packageIdentity, cacheDirectory: cacheDirectory,
                                   fileExtension: fileExtension, diskBudget: diskBudget),
           privateDomain(file.url.deletingLastPathComponent()) == key.domain {
            reusable = (key, revision)
        }
        try checkCancellation?()
        if let (key, revision) = reusable {
            successfulFiles.insert(key, file: file, revision: revision)
        }
        return file
    }

    /// Copies a regular source once, never reading more than 1 MiB at a time.
    /// The caller owns source identity semantics. Identity-check errors escape
    /// unchanged; cancellation and the 30-second deadline are checked between
    /// I/O operations, not promises to interrupt a blocked OS call.
    static func snapshot(
        from sourceURL: URL,
        cacheDirectory: URL,
        maximumBytes: Int = 1_024 * 1_024 * 1_024,
        diskBudget: DiskBudget = .shared,
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

        let writer = try makeWriter(cacheDirectory: cacheDirectory,
            expectedBytes: UInt64(expectedBytes), diskBudget: diskBudget)
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
            try buffer.withUnsafeBytes { bytes in
                try writer.append(UnsafeRawBufferPointer(rebasing: bytes[..<count]),
                    checkCancellation: checkpoint)
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
        let owned = try writer.finish(checkCancellation: checkpoint)
        let inputClose = Darwin.close(input)
        inputOpen = false
        guard inputClose == 0 else { throw Failure.io(operation: .closeSource, code: errno) }
        try checkpoint()
        return owned
    }

    private static func successfulKey(
        identity: SceneResourceView.PackageIdentity, cacheDirectory: URL,
        fileExtension: String, diskBudget: DiskBudget,
        purpose: SuccessfulFilePurpose = .sourceSnapshot
    ) -> SuccessfulFileKey? {
        guard cacheDirectory.isFileURL,
              let domain = privateDomain(cacheDirectory.appendingPathComponent(
                payloadDirectoryName, isDirectory: true)) else { return nil }
        return SuccessfulFileKey(source: identity, domain: domain,
            fileExtension: fileExtension, budget: ObjectIdentifier(diskBudget), purpose: purpose)
    }

    private static func privateDomain(_ directory: URL) -> PrivateDomain? {
        let canonical = directory.resolvingSymlinksInPath().standardizedFileURL
        var selected = stat(), resolved = stat()
        guard Darwin.lstat(directory.path, &selected) == 0,
              selected.st_mode & S_IFMT == S_IFDIR,
              Darwin.lstat(canonical.path, &resolved) == 0,
              resolved.st_mode & S_IFMT == S_IFDIR,
              selected.st_dev == resolved.st_dev, selected.st_ino == resolved.st_ino else { return nil }
        return PrivateDomain(path: canonical.path, device: resolved.st_dev, inode: resolved.st_ino)
    }

    private static func currentOutputRevision(_ url: URL) -> OutputRevision? {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { closeDuringCleanup(descriptor) }
        var opened = stat(), selected = stat(), final = stat()
        guard Darwin.fstat(descriptor, &opened) == 0,
              opened.st_mode & S_IFMT == S_IFREG, opened.st_size >= 0,
              Darwin.lstat(url.path, &selected) == 0,
              OutputRevision(selected) == OutputRevision(opened),
              Darwin.fstat(descriptor, &final) == 0,
              OutputRevision(final) == OutputRevision(opened) else { return nil }
        return OutputRevision(opened)
    }

    private static func allocateURL(cacheDirectory: URL, fileExtension: String) throws -> URL {
        guard cacheDirectory.isFileURL else { throw Failure.invalidCacheDirectory }
        guard (1...16).contains(fileExtension.utf8.count), fileExtension.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }) else { throw Failure.invalidFileExtension }
        let directory = cacheDirectory.appendingPathComponent(
            payloadDirectoryName, isDirectory: true
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
#if DEBUG
            NSLog("MWX video owned-file cleanup failed: operation=close errno=%d", errno)
#endif
        }
    }

    private func removeFile() {
        let removed = Darwin.unlink(url.path) == 0 || errno == ENOENT
        if !removed {
#if DEBUG
            NSLog("MWX video owned-file cleanup failed: operation=unlink errno=%d", errno)
#endif
        }
        reservation.releaseAfterRemoval(removed)
    }

    deinit { removeFile() }
}
