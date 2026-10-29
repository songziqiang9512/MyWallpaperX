import Darwin
import Foundation
import OSLog

/// The App's only socket-to-policy adapter. User pause and other interruption
/// reasons stay with the existing policy/multiplexer OR; this owns one reason.
@MainActor final class ScreenSaverActivityMonitor {
    static let shared = ScreenSaverActivityMonitor()
    private let explicitRoot: URL?
    private let listener = Listener()
    private var started = false
    private var generation: UInt64 = 0
    private var lastRevision: UInt64 = 0
    private(set) var isActive = false

    init(root: URL? = nil) { explicitRoot = root.map(ScreenSaverActivityWire.canonicalRoot) }

    deinit { listener.stop() }

    func start() {
        guard !started else { return }
        started = true
        generation &+= 1
        lastRevision = 0
        let currentGeneration = generation
        listener.start(root: explicitRoot) { [weak self] revision, active in
            Task { @MainActor [weak self] in
                guard let self, self.started, self.generation == currentGeneration,
                      revision > self.lastRevision else { return }
                self.lastRevision = revision
                self.apply(active)
            }
        }
    }

    func stop() {
        guard started else { return }
        started = false
        generation &+= 1
        listener.stop()
        apply(false)
    }

    private func apply(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        PlaybackPolicyController.shared.setInterruption(.screenSaver, active: active)
    }

    /// All path operations, descriptors and callbacks belong to this queue.
    /// FileHandle owns readiness cancellation and descriptor closure together.
    private nonisolated final class Listener: @unchecked Sendable {
        private nonisolated struct Peer {
            let handle: FileHandle
            var active = false
        }
        private let queue = DispatchQueue(label: "com.songziqiang.MyWallpaperX.screenSaverActivity.monitor", qos: .utility)
        private var socket: FileHandle?
        private var ownerLock: FileHandle?
        private var peers: [Int32: Peer] = [:]
        private var ownedPath: String?
        private var ownedInode: (dev_t, ino_t)?
        private var callback: (@Sendable (UInt64, Bool) -> Void)?
        private var revision: UInt64 = 0
        private var lastPublished: Bool?

        func start(root explicitRoot: URL?, callback: @escaping @Sendable (UInt64, Bool) -> Void) {
            queue.async { [self] in
                closeListener()
                self.callback = callback
                revision = 0
                lastPublished = nil
                publish()
                do {
                    let root = try explicitRoot ?? ScreenSaverActivityWire.canonicalRoot(ScreenSaverPaths.currentUserRoot())
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                            attributes: [.posixPermissions: 0o700])
                    // Preserve this inode. flock releases on process failure;
                    // it prevents a second monitor from removing a live socket.
                    let lockPath = root.appendingPathComponent("lifecycle.lock").path
                    let lockFD = Darwin.open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
                    guard lockFD >= 0 else { throw ScreenSaverActivityWire.lastError() }
                    let lock = FileHandle(fileDescriptor: lockFD, closeOnDealloc: true)
                    guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw ScreenSaverActivityWire.lastError() }
                    ownerLock = lock
                    let path = ScreenSaverActivityWire.socketPath(root: root)
                    var info = stat()
                    if lstat(path, &info) == 0 {
                        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK), info.st_uid == getuid() else {
                            throw POSIXError(.EEXIST)
                        }
                        guard Darwin.unlink(path) == 0 else { throw ScreenSaverActivityWire.lastError() }
                    } else if errno != ENOENT {
                        throw ScreenSaverActivityWire.lastError()
                    }
                    let handle = try ScreenSaverActivityWire.makeSocket()
                    guard try ScreenSaverActivityWire.withAddress(root: root, {
                        Darwin.bind(handle.fileDescriptor, $0, $1)
                    }) == 0 else { throw ScreenSaverActivityWire.lastError() }
                    ownedPath = path
                    if lstat(path, &info) == 0 { ownedInode = (info.st_dev, info.st_ino) }
                    guard chmod(path, 0o600) == 0, Darwin.listen(handle.fileDescriptor, 16) == 0 else {
                        throw ScreenSaverActivityWire.lastError()
                    }
                    socket = handle
                    handle.readabilityHandler = { [weak self] handle in
                        guard let self else { return }
                        self.queue.async { [weak self] in self?.acceptConnections(handle) }
                    }
                    // Listener readiness precedes the one event. A client that
                    // missed it can still connect when its surface starts.
                    DistributedNotificationCenter.default().postNotificationName(
                        ScreenSaverActivityWire.appReady, object: root.path,
                        userInfo: nil, deliverImmediately: true)
                } catch {
                    closeListener()
                    ScreenSaverActivityWire.logger.error("Activity listener unavailable code=\((error as NSError).code, privacy: .public)")
                }
            }
        }

        func stop() { queue.async { [self] in closeListener() } }

        private func acceptConnections(_ listener: FileHandle) {
            guard socket === listener else { return }
            while true {
                let fd = Darwin.accept(listener.fileDescriptor, nil, nil)
                if fd < 0 {
                    if errno == EINTR { continue }
                    return
                }
                guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0, fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
                    Darwin.close(fd)
                    continue
                }
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                peers[fd] = Peer(handle: handle)
                handle.readabilityHandler = { [weak self] handle in
                    guard let self else { return }
                    self.queue.async { [weak self] in self?.readPeer(handle, descriptor: fd) }
                }
            }
        }

        private func readPeer(_ handle: FileHandle, descriptor fd: Int32) {
            guard let peer = peers[fd], peer.handle === handle else { return }
            var bytes = [UInt8](repeating: 0, count: 2)
            let count = bytes.withUnsafeMutableBytes { Darwin.recv(fd, $0.baseAddress, $0.count, MSG_DONTWAIT) }
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) { return }
            if !peer.active, count == 1, bytes[0] == ScreenSaverActivityWire.activeMarker {
                peers[fd]?.active = true
                publish()
            } else {
                // EOF, peer failure or extra payload removes just this lease.
                // The byte is framing, not a credential or authorization test.
                peers[fd] = nil
                handle.readabilityHandler = nil
                try? handle.close()
                publish()
            }
        }

        private func publish() {
            let active = peers.values.contains { $0.active }
            guard lastPublished != active else { return }
            lastPublished = active
            revision &+= 1
            callback?(revision, active)
        }

        private func closeListener() {
            if let socket {
                self.socket = nil
                socket.readabilityHandler = nil
                try? socket.close()
            }
            for peer in peers.values {
                peer.handle.readabilityHandler = nil
                try? peer.handle.close()
            }
            peers.removeAll()
            publish()
            if let path = ownedPath, let inode = ownedInode {
                var info = stat()
                if lstat(path, &info) == 0, info.st_dev == inode.0, info.st_ino == inode.1 {
                    Darwin.unlink(path)
                }
            }
            ownedPath = nil
            ownedInode = nil
            try? ownerLock?.close()
            ownerLock = nil
            callback = nil
        }
    }
}
