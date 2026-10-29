import Darwin
import Foundation
import OSLog

/// A connection is an energy-policy hint, never proof of lock or media access.
/// The caller starts only actual full-screen surfaces, not a settings thumbnail
/// or an application preview. Multiple views in one host share one connection.
nonisolated final class ScreenSaverActivityClient: Sendable {
    private let root: URL
    private let leaseID = UUID()
    private static let queue = DispatchQueue(label: "com.songziqiang.MyWallpaperX.screenSaverActivity.client", qos: .utility)
    // Both this table and every Session field are confined to queue.
    nonisolated(unsafe) private static var sessions: [String: Session] = [:]

    init(root: URL) {
        self.root = ScreenSaverActivityWire.canonicalRoot(root)
    }

    deinit { stop() }

    func start() {
        let root = root, leaseID = leaseID
        Self.queue.async {
            let session = Self.sessions[root.path] ?? Session(root: root, queue: Self.queue)
            Self.sessions[root.path] = session
            session.add(leaseID)
        }
    }

    func stop() {
        let key = root.path, leaseID = leaseID
        Self.queue.async {
            guard let session = Self.sessions[key] else { return }
            session.remove(leaseID)
            if session.leases.isEmpty { Self.sessions[key] = nil }
        }
    }

    private nonisolated final class Session: @unchecked Sendable {
        let root: URL
        let queue: DispatchQueue
        var leases: Set<UUID> = []
        private var observer: NSObjectProtocol?
        private var socket: FileHandle?
        private var awaitingHello = false
        private var connectDeadline: DispatchWorkItem?
#if DEBUG
        private var didLogFailure = false
#endif

        init(root: URL, queue: DispatchQueue) {
            self.root = root
            self.queue = queue
        }

        deinit {
            if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
            connectDeadline?.cancel()
            socket?.readabilityHandler = nil
            socket?.writeabilityHandler = nil
            try? socket?.close()
        }

        func add(_ id: UUID) {
            guard leases.insert(id).inserted else { return }
            if observer == nil {
                // Register first, then connect: an App-ready event missed before
                // registration is covered by the immediate connection attempt.
                observer = DistributedNotificationCenter.default().addObserver(
                    forName: ScreenSaverActivityWire.appReady, object: root.path, queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    self.queue.async { [weak self] in
                        guard let self, !self.leases.isEmpty else { return }
                        // An old monitor's EOF may still be queued behind ready.
                        // Replace that connection so it cannot swallow the restart.
                        self.closeSocket()
                        self.connect()
                    }
                }
            }
            connect()
        }

        func remove(_ id: UUID) {
            guard leases.remove(id) != nil, leases.isEmpty else { return }
            if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
            observer = nil
            closeSocket()
        }

        private func connect() {
            guard !leases.isEmpty, socket == nil else { return }
            do {
                let handle = try ScreenSaverActivityWire.makeSocket()
                var one: Int32 = 1
                guard setsockopt(handle.fileDescriptor, SOL_SOCKET, SO_NOSIGPIPE,
                                 &one, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
                    throw ScreenSaverActivityWire.lastError()
                }
                socket = handle
                awaitingHello = true
                let result = try ScreenSaverActivityWire.withAddress(root: root) {
                    Darwin.connect(handle.fileDescriptor, $0, $1)
                }
                if result == 0 {
                    finishHello(handle)
                } else if errno == EINPROGRESS {
                    watchWritable(handle)
                } else {
                    throw ScreenSaverActivityWire.lastError()
                }
                if awaitingHello { armDeadline(handle) }
            } catch {
                closeSocket()
#if DEBUG
                logFailureOnce(error)
#endif
            }
        }

        private func watchWritable(_ handle: FileHandle) {
            handle.writeabilityHandler = { [weak self] handle in
                guard let self else { return }
                self.queue.async { [weak self] in self?.finishHello(handle) }
            }
        }

        private func finishHello(_ handle: FileHandle) {
            guard socket === handle, awaitingHello, !leases.isEmpty else { return }
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(handle.fileDescriptor, SOL_SOCKET, SO_ERROR, &error, &length) == 0,
                  error == 0 else {
#if DEBUG
                let code = error == 0 ? errno : error
#endif
                closeSocket()
#if DEBUG
                logFailureOnce(POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO))
#endif
                return
            }
            var marker = ScreenSaverActivityWire.activeMarker
            let count = Darwin.send(handle.fileDescriptor, &marker, 1, MSG_DONTWAIT)
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                watchWritable(handle)
                return
            }
            guard count == 1 else {
#if DEBUG
                let error = ScreenSaverActivityWire.lastError()
#endif
                closeSocket()
#if DEBUG
                logFailureOnce(error)
#endif
                return
            }
            awaitingHello = false
            connectDeadline?.cancel()
            connectDeadline = nil
            handle.writeabilityHandler = nil
            handle.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                self.queue.async { [weak self] in self?.readClosure(handle) }
            }
        }

        private func readClosure(_ handle: FileHandle) {
            guard socket === handle else { return }
            var byte: UInt8 = 0
            let count = Darwin.recv(handle.fileDescriptor, &byte, 1, MSG_DONTWAIT)
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) { return }
            // The monitor sends no payload. EOF or unexpected bytes end this
            // lease; a later App-ready event is the only reconnection trigger.
            closeSocket()
        }

        private func armDeadline(_ handle: FileHandle) {
            let work = DispatchWorkItem { [weak self, weak handle] in
                guard let self, let handle, self.socket === handle, self.awaitingHello else { return }
                self.closeSocket()
#if DEBUG
                self.logFailureOnce(POSIXError(.ETIMEDOUT))
#endif
            }
            connectDeadline = work
            queue.asyncAfter(deadline: .now() + 1, execute: work)
        }

        private func closeSocket() {
            connectDeadline?.cancel()
            connectDeadline = nil
            awaitingHello = false
            guard let handle = socket else { return }
            socket = nil
            handle.readabilityHandler = nil
            handle.writeabilityHandler = nil
            try? handle.close()
        }

#if DEBUG
        private func logFailureOnce(_ error: Error) {
            guard !didLogFailure else { return }
            didLogFailure = true
            ScreenSaverActivityWire.logger.debug("Activity socket unavailable code=\((error as NSError).code, privacy: .public); awaiting App-ready")
        }
#endif
    }
}

/// Shared one-byte wire format and socket setup. No identity/authentication API.
nonisolated enum ScreenSaverActivityWire {
    static let appReady = Notification.Name("com.songziqiang.MyWallpaperX.ScreenSaver.appReady")
    static let activeMarker: UInt8 = 0x41
    static let logger = Logger(subsystem: "com.songziqiang.MyWallpaperX.ScreenSaver", category: "activity")

    /// Foundation may shorten an existing /private/tmp path to /tmp while
    /// retaining /private/tmp for its missing child. Normalize the nearest
    /// existing ancestor once, then append the uncreated directory suffix.
    static func canonicalRoot(_ root: URL) -> URL {
        var ancestor = root.standardizedFileURL
        var missing: [String] = []
        while ancestor.path != "/", !FileManager.default.fileExists(atPath: ancestor.path) {
            missing.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var result = ancestor.resolvingSymlinksInPath().standardizedFileURL
        for component in missing.reversed() { result.appendPathComponent(component, isDirectory: true) }
        return result
    }

    static func socketPath(root: URL) -> String { root.appendingPathComponent("lifecycle.sock").path }

    static func lastError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    static func makeSocket() throws -> FileHandle {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw lastError() }
        guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0, fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
            let error = lastError()
            Darwin.close(fd)
            throw error
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    static func withAddress<T>(root: URL, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) throws -> T {
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath(root: root).utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            bytes.withUnsafeBytes { target.copyMemory(from: $0) }
        }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
}
