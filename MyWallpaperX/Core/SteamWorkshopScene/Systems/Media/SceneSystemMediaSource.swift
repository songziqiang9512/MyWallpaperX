import Darwin
import Foundation

/// Owns one experimental system-media transport. Selection and publication
/// remain with SceneSystemMediaProvider; this endpoint never touches the inbox.
@MainActor
final class SceneSystemMediaSource {
    nonisolated static let maximumLineByteCount = 24 * 1_024 * 1_024
    nonisolated static let maximumArtworkByteCount = 16 * 1_024 * 1_024
    nonisolated static let heartbeatTimeout: TimeInterval = 12

    nonisolated struct Snapshot: Sendable {
        let source: String
        let identity: String
        let title: String?
        let artist: String?
        let album: String?
        let playbackState: Int?
        let position: Double?
        let duration: Double?
        let artworkIdentifier: String?
        let artworkChanged: Bool
        let artworkData: Data?
        let artworkFailure: Failure?
    }

    nonisolated enum Result: Sendable {
        case snapshot(Snapshot)
        case noSession
        case unavailable(Failure)
    }

    nonisolated enum Failure: Error, Equatable, Sendable {
        case missingResource
        case launchFailed(Int)
        case readFailed(Int)
        case heartbeatTimeout
        case processExited(Int32)
        case lineByteLimit
        case incompleteFrame
        case invalidJSON
        case unsupportedVersion
        case invalidFields
        case inheritedArtworkWithoutMatchingTrack
        case invalidArtwork
        case artworkByteLimit
        case helperUnavailable
    }

    /// Stateful wire validation only; no artwork cache or media publication.
    nonisolated struct Decoder {
        private var previousSource: String?
        private var previousIdentity: String?
        private var previousArtworkIdentifier: String?

        private nonisolated struct Wire: Decodable {
            let version: Int
            let status: String
            let source: String?
            let identity: String?
            let title: String?
            let artist: String?
            let album: String?
            let playbackState: Int?
            let position: Double?
            let duration: Double?
            let artworkIdentifier: String?
            let artworkChanged: Bool?
            let artworkData: String?
        }

        mutating func decode(_ frame: Data) throws -> Result {
            guard frame.count <= maximumLineByteCount else { throw Failure.lineByteLimit }
            let wire: Wire
            do { wire = try JSONDecoder().decode(Wire.self, from: frame) }
            catch { throw Failure.invalidJSON }
            guard wire.version == 1 else { throw Failure.unsupportedVersion }
            for value in [wire.source, wire.identity, wire.title, wire.artist, wire.album,
                          wire.artworkIdentifier].compactMap({ $0 }) {
                guard value.utf8.count <= 4 * 1_024,
                      !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    throw Failure.invalidFields
                }
            }
            guard wire.playbackState.map({ (0...2).contains($0) }) ?? true,
                  wire.position.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  wire.duration.map({ $0.isFinite && $0 >= 0 }) ?? true else {
                throw Failure.invalidFields
            }
            switch wire.status {
            case "noSession", "unavailable":
                previousSource = nil
                previousIdentity = nil
                previousArtworkIdentifier = nil
                return wire.status == "noSession" ? .noSession : .unavailable(.helperUnavailable)
            case "snapshot": break
            default: throw Failure.invalidFields
            }
            guard let source = wire.source, !source.isEmpty,
                  let identity = wire.identity, !identity.isEmpty,
                  let changed = wire.artworkChanged else { throw Failure.invalidFields }
            if !changed {
                guard wire.artworkData == nil, previousSource == source,
                      previousIdentity == identity,
                      previousArtworkIdentifier == wire.artworkIdentifier else {
                    throw Failure.inheritedArtworkWithoutMatchingTrack
                }
            }
            var artwork: Data?
            var artworkFailure: Failure?
            if let encoded = wire.artworkData {
                let maximumEncodedBytes = ((maximumArtworkByteCount + 2) / 3) * 4
                if encoded.utf8.count > maximumEncodedBytes {
                    artworkFailure = .artworkByteLimit
                } else if let bytes = Data(base64Encoded: encoded), !bytes.isEmpty {
                    if bytes.count <= maximumArtworkByteCount { artwork = bytes }
                    else { artworkFailure = .artworkByteLimit }
                } else {
                    artworkFailure = .invalidArtwork
                }
            }
            previousSource = source
            previousIdentity = identity
            previousArtworkIdentifier = wire.artworkIdentifier
            return .snapshot(Snapshot(
                source: source, identity: identity, title: wire.title, artist: wire.artist,
                album: wire.album, playbackState: wire.playbackState,
                position: wire.position, duration: wire.duration,
                artworkIdentifier: wire.artworkIdentifier, artworkChanged: changed,
                artworkData: artwork, artworkFailure: artworkFailure
            ))
        }
    }

    nonisolated struct StreamDecoder {
        private var framing = DaemonNewlineFrameBuffer()
        private var decoder = Decoder()

        var hasIncompleteFrame: Bool { framing.pendingByteCount != 0 }

        mutating func append(_ chunk: Data) throws -> [Result] {
            // The reader supplies at most 64 KiB, so an oversized pending line
            // can exceed its budget by only that bounded read before rejection.
            let frames = framing.append(chunk)
            guard framing.pendingByteCount <= maximumLineByteCount else { throw Failure.lineByteLimit }
            return try frames.map { try decoder.decode($0) }
        }
    }

    private let resourceURL: URL?
    private var generation: UInt64 = 0
    private var session: Session?

    init(bundle: Bundle = .main) {
        resourceURL = bundle.resourceURL?.appendingPathComponent("SceneMediaObserver/SceneMediaObserver.dylib")
    }

    deinit { session?.cancel() }

    func start(_ receive: @escaping @MainActor @Sendable (Result) -> Void) {
        guard session == nil else { return }
        guard let resourceURL,
              (try? resourceURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
            receive(.unavailable(.missingResource))
            return
        }
        generation &+= 1
        let requestGeneration = generation
        let child = Session(resourceURL: resourceURL) { [weak self] result, terminal, acknowledged in
            Task { @MainActor in
                defer { acknowledged.signal() }
                guard let self, self.generation == requestGeneration, self.session != nil else { return }
                if terminal { self.session = nil }
                receive(result)
            }
        }
        session = child
        child.start()
    }

    func stop() {
        generation &+= 1
        let child = session
        session = nil
        child?.cancel()
    }

    /// All pipe reading, JSON work and reaping happen on the worker. The lock
    /// protects cancellation and the single pending delivery acknowledgement.
    private nonisolated final class Session: @unchecked Sendable {
        private let resourceURL: URL
        private let delivery: @Sendable (Result, Bool, DispatchSemaphore) -> Void
        private let lock = NSLock()
        private var cancelled = false
        private var process: Process?
        private var acknowledgement: DispatchSemaphore?

        init(resourceURL: URL, delivery: @escaping @Sendable (Result, Bool, DispatchSemaphore) -> Void) {
            self.resourceURL = resourceURL
            self.delivery = delivery
        }

        func start() { DispatchQueue.global(qos: .utility).async { self.run() } }

        func cancel() {
            lock.lock()
            cancelled = true
            let child = process
            let pending = acknowledgement
            lock.unlock()
            pending?.signal()
            if let child { terminate(child) }
        }

        private var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        private func emit(_ result: Result, terminal: Bool = false) {
            let completed = DispatchSemaphore(value: 0)
            lock.lock()
            guard !cancelled else { lock.unlock(); return }
            acknowledgement = completed
            lock.unlock()
            delivery(result, terminal, completed)
            completed.wait()
            lock.lock()
            acknowledgement = nil
            lock.unlock()
        }

        private func terminate(_ child: Process) {
            guard child.isRunning else { return }
            child.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                // Escalate only this still-owned child if normal termination
                // did not finish. The reader then waitUntilExit() reaps it.
                if child.isRunning { _ = Darwin.kill(child.processIdentifier, SIGKILL) }
            }
        }

        private func run() {
            if isCancelled { return }
            let child = Process()
            let output = Pipe()
            child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            child.arguments = ["-e", "use DynaLoader; my $h=DynaLoader::dl_load_file($ARGV[0],0); die DynaLoader::dl_error() unless $h; my $s=DynaLoader::dl_find_symbol($h,'mwx_scene_media_run'); die DynaLoader::dl_error() unless $s; my $f=DynaLoader::dl_install_xsub('MWXSceneMedia::run',$s,$ARGV[0]); die DynaLoader::dl_error() unless $f; MWXSceneMedia::run();", resourceURL.path]
            child.standardOutput = output
            child.standardError = FileHandle.nullDevice
            child.standardInput = FileHandle.nullDevice
            lock.lock()
            process = child
            lock.unlock()
            do { try child.run() }
            catch {
                try? output.fileHandleForReading.close()
                try? output.fileHandleForWriting.close()
                emit(.unavailable(.launchFailed((error as NSError).code)), terminal: true)
                return
            }
            try? output.fileHandleForWriting.close()
            if isCancelled { terminate(child) }
            var stream = StreamDecoder()
            var failure: Failure?
            var lastRecord = ProcessInfo.processInfo.systemUptime
            do {
                while !isCancelled {
                    let remaining = lastRecord + heartbeatTimeout - ProcessInfo.processInfo.systemUptime
                    guard remaining > 0 else { throw Failure.heartbeatTimeout }
                    var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor,
                                            events: Int16(POLLIN | POLLHUP), revents: 0)
                    let ready = Darwin.poll(&descriptor, 1, Int32(ceil(min(1, remaining) * 1_000)))
                    if ready < 0 {
                        if errno == EINTR { continue }
                        throw Failure.readFailed(Int(errno))
                    }
                    if ready == 0 { continue }
                    var bytes = [UInt8](repeating: 0, count: 64 * 1_024)
                    let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
                    if count < 0 {
                        if errno == EINTR { continue }
                        throw Failure.readFailed(Int(errno))
                    }
                    if count == 0 { break }
                    let chunk = Data(bytes.prefix(count))
                    let results = try stream.append(chunk)
                    if !results.isEmpty { lastRecord = ProcessInfo.processInfo.systemUptime }
                    for result in results { emit(result) }
                }
                if !isCancelled && stream.hasIncompleteFrame { failure = .incompleteFrame }
            } catch let error as Failure { failure = error }
            catch { failure = .readFailed((error as NSError).code) }
            // EOF also ends the transport. A helper that closed stdout but
            // kept its run loop alive must not leave a child behind.
            terminate(child)
            child.waitUntilExit()
            try? output.fileHandleForReading.close()
            if !isCancelled {
                emit(.unavailable(failure ?? .processExited(child.terminationStatus)), terminal: true)
            }
        }
    }
}
