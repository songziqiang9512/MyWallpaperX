import Foundation
import Darwin
import CoreFoundation

nonisolated enum DaemonCommandBufferLimits {
    static let maximumPendingControlCount = 256
    static let maximumPendingControlBytes = 8 * 1_024 * 1_024
}

/// Ordered command buffer with latest-only coalescing inside each control
/// segment. A control is a barrier: values on opposite sides can never replace
/// or overtake each other, while repeated high-rate values in one segment keep
/// only the newest payload.
nonisolated struct DaemonCommandBuffer<Control, Droppable> {
    enum Entry {
        case control(Control, byteCount: Int)
        case droppable(Droppable)
    }

    private var entries: [Entry] = []
    private(set) var controlCount = 0
    private(set) var controlBytes = 0

    @discardableResult
    mutating func enqueueControl(
        _ control: Control,
        byteCount: Int,
        maximumCount: Int,
        maximumBytes: Int
    ) -> Bool {
        guard byteCount >= 0,
              controlCount < maximumCount,
              byteCount <= maximumBytes - controlBytes else {
            return false
        }
        entries.append(.control(control, byteCount: byteCount))
        controlCount += 1
        controlBytes += byteCount
        return true
    }

    mutating func enqueueDroppable(_ droppable: Droppable) {
        if case .droppable = entries.last {
            entries[entries.count - 1] = .droppable(droppable)
        } else {
            entries.append(.droppable(droppable))
        }
    }

    mutating func takeFirst() -> Entry? {
        guard !entries.isEmpty else { return nil }
        let entry = entries.removeFirst()
        if case let .control(_, byteCount) = entry {
            controlCount -= 1
            controlBytes -= byteCount
        }
        return entry
    }

    mutating func discardDroppable() {
        entries.removeAll { entry in
            if case .droppable = entry { return true }
            return false
        }
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: false)
        controlCount = 0
        controlBytes = 0
    }
}

/// Physical renderer ownership survives logical active/candidate/idle retirement.
/// Only explicitly marked playback transports enter this registry.
nonisolated final class DaemonPlaybackProcessRegistry: @unchecked Sendable {
    static let shared = DaemonPlaybackProcessRegistry()

    struct ShutdownResult: Sendable {
        let remainingProcessIdentifiers: [Int32]
        var allExited: Bool { remainingProcessIdentifiers.isEmpty }
    }

    private let lock = NSRecursiveLock()
    private let queue = DispatchQueue(label: "com.mywallpaperx.playback-process-exit")
    private var transports: [ObjectIdentifier: DaemonProcessTransport] = [:]
    private var admissionClosed = false
    private var result: ShutdownResult?
    typealias Completion = @MainActor @Sendable (ShutdownResult) -> Void
    private var completions: [Completion] = []
    private let gracePeriod: TimeInterval
    private let terminatePeriod: TimeInterval
    private let killPeriod: TimeInterval

    init(gracePeriod: TimeInterval = 2, terminatePeriod: TimeInterval = 1,
         killPeriod: TimeInterval = 1) {
        self.gracePeriod = gracePeriod
        self.terminatePeriod = terminatePeriod
        self.killPeriod = killPeriod
    }

    var acceptsNewProcesses: Bool {
        lock.lock(); defer { lock.unlock() }
        return !admissionClosed
    }

    var liveProcessIdentifiers: [Int32] {
        lock.lock(); defer { lock.unlock() }
        return transports.values.map { $0.process.processIdentifier }.sorted()
    }

    func start(_ transport: DaemonProcessTransport, launch: () throws -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        guard !admissionClosed else {
            throw NSError(domain: "DaemonPlaybackProcessRegistry", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Playback process admission is closed"])
        }
        let id = ObjectIdentifier(transport)
        transports[id] = transport
        do { try launch() }
        catch {
            if !transport.isRunning { transports.removeValue(forKey: id) }
            throw error
        }
    }

    func didExit(_ transport: DaemonProcessTransport) {
        lock.lock()
        transports.removeValue(forKey: ObjectIdentifier(transport))
        if admissionClosed, transports.isEmpty { finishLocked() }
        lock.unlock()
    }

    /// Starts the common wall-clock deadline before any engine teardown work.
    func closeAdmission() {
        lock.lock()
        guard !admissionClosed else { lock.unlock(); return }
        admissionClosed = true
        let start = DispatchTime.now()
        queue.asyncAfter(deadline: start + gracePeriod) { [self] in
            for transport in snapshot() { transport.terminate() }
        }
        queue.asyncAfter(deadline: start + gracePeriod + terminatePeriod) { [self] in
            for transport in snapshot() { transport.killIfRunning() }
        }
        queue.asyncAfter(deadline: start + gracePeriod + terminatePeriod + killPeriod) { [self] in
            lock.lock(); finishLocked(); lock.unlock()
        }
        if transports.isEmpty { finishLocked() }
        lock.unlock()
    }

    func waitForExit(completion: @escaping Completion) {
        closeAdmission()
        lock.lock()
        if let result { Self.deliver(result, to: [completion]) }
        else { completions.append(completion) }
        lock.unlock()
    }

    private func snapshot() -> [DaemonProcessTransport] {
        lock.lock(); defer { lock.unlock() }
        return Array(transports.values)
    }

    private func finishLocked() {
        guard result == nil || (transports.isEmpty && result?.allExited == false) else { return }
        let value = ShutdownResult(remainingProcessIdentifiers:
            transports.values.map { $0.process.processIdentifier }.sorted())
        result = value
        let callbacks = completions
        completions.removeAll()
        Self.deliver(value, to: callbacks)
    }

    private static func deliver(_ result: ShutdownResult, to callbacks: [Completion]) {
        guard !callbacks.isEmpty else { return }
        RunLoop.main.perform(inModes: [.common, .init("NSModalPanelRunLoopMode")]) {
            MainActor.assumeIsolated { callbacks.forEach { $0(result) } }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}

/// One child process wired to stdin/stdout/stderr pipes. Protocol payloads,
/// session identity, and restart decisions stay with the owning engine client.
nonisolated final class DaemonProcessTransport: @unchecked Sendable {
    let process: Process
    let inputPipe: Pipe
    let outputPipe: Pipe
    let errorPipe: Pipe

    var onOutput: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    var onTermination: ((Int32) -> Void)?

    private(set) var hasStarted = false
    private let playbackRegistry: DaemonPlaybackProcessRegistry?
    private let lifetimeLock = NSLock()
    private var physicalExitRecorded = false
    private var terminationDeadline: DispatchTime?
    private let terminationQueue = DispatchQueue(label: "com.mywallpaperx.daemon-stop-deadline")
    private let inputStateLock = NSLock()
    private let inputWriteQueue = DispatchQueue(
        label: "com.mywallpaperx.daemon-input-writer",
        qos: .userInitiated
    )
    private var pendingInputs = DaemonCommandBuffer<Data, Data>()
    private var inputPumpScheduled = false
    private var inputCloseRequested = false
    private var inputClosed = false

    private enum OutputStreamKind { case output, error }
    private struct ReceivedChunk {
        let stream: OutputStreamKind
        let data: Data
    }
    // Admission happens before scheduling main work. Otherwise a blocked main
    // loop merely moves an unbounded pipe backlog into queued closures.
    private let receiveLock = NSLock()
    private let receiveQueue = DispatchQueue(label: "com.mywallpaperx.daemon-output-reader")
    private var outputReader: DispatchSourceRead?
    private var errorReader: DispatchSourceRead?
    private var pendingReceived: [ReceivedChunk] = []
    private var pendingOutputBytes = 0
    private var pendingErrorBytes = 0
    private var receiveDrainScheduled = false
    private var receiveClosed = false
    private var receiveGeneration: UInt64 = 0
    private var outputEOF = false
    private var errorEOF = false
    private var exitStatus: Int32?
    private var didDeliverTermination = false
    private var receiveFailure: String?
    // A complete 8 MiB protocol frame plus subsequent small events fits even
    // while main is blocked. stderr has its own smaller diagnostic allowance.
    private static let maximumOutputBytes = 16 * 1_024 * 1_024
    private static let maximumErrorBytes = 2 * 1_024 * 1_024
    private static let maximumReceivedChunks = 1_024

    init(executableURL: URL, arguments: [String], playbackRenderer: Bool = false,
         playbackRegistry: DaemonPlaybackProcessRegistry = .shared) {
        self.playbackRegistry = playbackRenderer ? playbackRegistry : nil
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        if playbackRenderer {
            var environment = ProcessInfo.processInfo.environment
            environment["MWX_PLAYBACK_PARENT_PID"] = String(getpid())
            process.environment = environment
        }
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
    }

    var isRunning: Bool { process.isRunning }

    func start() throws {
        precondition(!hasStarted, "A daemon transport can only be started once")
        hasStarted = true
        _ = fcntl(
            inputPipe.fileHandleForWriting.fileDescriptor,
            F_SETNOSIGPIPE,
            1
        )
        // Keep the transport alive even after its engine removes a logical
        // session. The cycle ends only after Foundation observes actual exit.
        process.terminationHandler = { [self] process in
            recordExit(process.terminationStatus)
            process.terminationHandler = nil
        }
        do {
            if let playbackRegistry {
                try playbackRegistry.start(self) { try process.run() }
            } else {
                try process.run()
            }
            try startReader(outputPipe.fileHandleForReading, stream: .output)
            try startReader(errorPipe.fileHandleForReading, stream: .error)
        } catch {
            if !process.isRunning { process.terminationHandler = nil }
            terminate()
            throw error
        }
    }

    @discardableResult
    func send(_ data: Data) -> Bool {
        enqueueInput(data, droppable: false)
    }

    /// Required controls fail closed. A live child that cannot admit ordered
    /// control state must be replaced instead of silently diverging from its
    /// owner while it continues to render stale state.
    @discardableResult
    func sendRequired(_ data: Data) -> Bool {
        let accepted = send(data)
        if !accepted { terminate() }
        return accepted
    }

    /// Enqueues one high-rate payload without ever waiting on the child pipe.
    /// At most one droppable payload is retained between adjacent controls.
    /// Controls are barriers, so a later value cannot overtake an earlier
    /// control and an earlier value cannot be replayed after it.
    @discardableResult
    func sendLatest(_ data: Data) -> Bool {
        enqueueInput(data, droppable: true)
    }

    func closeInput() {
        inputStateLock.lock()
        guard !inputClosed else {
            inputStateLock.unlock()
            return
        }
        inputCloseRequested = true
        pendingInputs.discardDroppable()
        scheduleInputPumpLocked()
        inputStateLock.unlock()
    }

    func closeIO() {
        receiveLock.lock()
        let readers = [outputReader, errorReader].compactMap { $0 }
        outputReader = nil; errorReader = nil
        receiveClosed = true
        receiveGeneration &+= 1
        outputEOF = true; errorEOF = true
        pendingReceived.removeAll()
        pendingOutputBytes = 0; pendingErrorBytes = 0
        scheduleReceiveDrainLocked()
        receiveLock.unlock()
        readers.forEach { $0.cancel() }
        inputStateLock.lock()
        inputClosed = true
        inputCloseRequested = false
        pendingInputs.removeAll()
        inputStateLock.unlock()
        try? inputPipe.fileHandleForWriting.close()
        try? outputPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()
    }

    private func startReader(_ handle: FileHandle, stream: OutputStreamKind) throws {
        let descriptor = fcntl(handle.fileDescriptor, F_DUPFD_CLOEXEC, 0)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            let code = errno
            _ = Darwin.close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        let reader = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: receiveQueue)
        reader.setEventHandler { [weak self] in self?.readAvailable(descriptor, stream: stream) }
        // The duplicate belongs only to this source. Cancellation never closes
        // a descriptor concurrently with the serial event handler's read.
        reader.setCancelHandler { _ = Darwin.close(descriptor) }
        receiveLock.lock()
        let closed = receiveClosed
        if !closed {
            switch stream {
            case .output: outputReader = reader
            case .error: errorReader = reader
            }
        }
        receiveLock.unlock()
        reader.resume()
        if closed { reader.cancel() }
    }

    private func readAvailable(_ descriptor: Int32, stream: OutputStreamKind) {
        var bytes = [UInt8](repeating: 0, count: 65_536)
        var count: Int
        repeat {
            count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
        } while count < 0 && errno == EINTR
        if count > 0 {
            admitReceived(Data(bytes.prefix(count)), stream: stream)
        } else if count == 0 {
            finishReader(stream)
        } else if errno != EAGAIN && errno != EWOULDBLOCK {
            failReceiving("transport-read-failed errno=\(errno)")
        }
    }

    private func admitReceived(_ data: Data, stream: OutputStreamKind) {
        receiveLock.lock()
        guard !receiveClosed else { receiveLock.unlock(); return }
        let fits = pendingReceived.count < Self.maximumReceivedChunks && {
            switch stream {
            case .output: return data.count <= Self.maximumOutputBytes - pendingOutputBytes
            case .error: return data.count <= Self.maximumErrorBytes - pendingErrorBytes
            }
        }()
        guard fits else {
            receiveLock.unlock()
            failReceiving("transport-output-limit-exceeded stream=\(stream)")
            return
        }
        pendingReceived.append(.init(stream: stream, data: data))
        switch stream {
        case .output: pendingOutputBytes += data.count
        case .error: pendingErrorBytes += data.count
        }
        scheduleReceiveDrainLocked()
        receiveLock.unlock()
    }

    private func finishReader(_ stream: OutputStreamKind) {
        receiveLock.lock()
        let reader: DispatchSourceRead?
        switch stream {
        case .output: outputEOF = true; reader = outputReader; outputReader = nil
        case .error: errorEOF = true; reader = errorReader; errorReader = nil
        }
        scheduleReceiveDrainLocked()
        receiveLock.unlock()
        reader?.cancel()
    }

    private func recordExit(_ status: Int32) {
        lifetimeLock.lock()
        physicalExitRecorded = true
        lifetimeLock.unlock()
        // This precedes protocol-tail delivery and never depends on main being
        // available. Output EOF is a separate protocol concern.
        playbackRegistry?.didExit(self)
        receiveLock.lock()
        exitStatus = status
        scheduleReceiveDrainLocked()
        receiveLock.unlock()
        // A descendant may accidentally inherit a write end. Do not leave the
        // owner's exit notification waiting forever for that unrelated process.
        receiveQueue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.receiveLock.lock()
            let waitingForEOF = !self.outputEOF || !self.errorEOF
            self.receiveLock.unlock()
            if waitingForEOF { self.failReceiving("transport-output-eof-timeout") }
        }
    }

    private func failReceiving(_ message: String) {
        receiveLock.lock()
        guard !receiveClosed, receiveFailure == nil else { receiveLock.unlock(); return }
        receiveFailure = message
        receiveClosed = true
        receiveGeneration &+= 1
        pendingReceived.removeAll()
        pendingOutputBytes = 0; pendingErrorBytes = 0
        scheduleReceiveDrainLocked()
        receiveLock.unlock()
        // No truncated protocol stream is presented as a successful endpoint.
        // The explicit failure is delivered before the termination callback.
        terminate()
        terminationQueue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.killIfRunning() }
    }

    private func scheduleReceiveDrainLocked() {
        guard !receiveDrainScheduled else { return }
        receiveDrainScheduled = true
        RunLoop.main.perform(inModes: [.common, .init("NSModalPanelRunLoopMode")]) { [weak self] in self?.drainReceived() }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    private func drainReceived() {
        // Yield between bounded batches even if a producer remains busy.
        var deliveredBytes = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 0.002
        while deliveredBytes < 256 * 1_024,
              deliveredBytes == 0 || ProcessInfo.processInfo.systemUptime < deadline {
            receiveLock.lock()
            if let failure = receiveFailure {
                receiveFailure = nil
                receiveLock.unlock()
                onError?(failure)
                continue
            }
            guard !pendingReceived.isEmpty else { receiveLock.unlock(); break }
            let chunk = pendingReceived.removeFirst()
            let generation = receiveGeneration
            switch chunk.stream {
            case .output: pendingOutputBytes -= chunk.data.count
            case .error: pendingErrorBytes -= chunk.data.count
            }
            receiveLock.unlock()
            receiveLock.lock()
            let current = generation == receiveGeneration
            receiveLock.unlock()
            guard current else { continue }
            deliveredBytes += chunk.data.count
            switch chunk.stream {
            case .output: onOutput?(chunk.data)
            case .error: onError?(String(decoding: chunk.data, as: UTF8.self))
            }
        }
        receiveLock.lock()
        receiveDrainScheduled = false
        let status = pendingReceived.isEmpty && receiveFailure == nil && outputEOF && errorEOF
            && !didDeliverTermination ? exitStatus : nil
        if status != nil { didDeliverTermination = true }
        if !pendingReceived.isEmpty || receiveFailure != nil { scheduleReceiveDrainLocked() }
        receiveLock.unlock()
        if let status { onTermination?(status) }
    }

    func terminate() {
        lifetimeLock.lock()
        if !physicalExitRecorded, process.isRunning { process.terminate() }
        lifetimeLock.unlock()
        closeIO()
        if playbackRegistry != nil {
            terminationQueue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.killIfRunning() }
        }
    }

    func killIfRunning() {
        lifetimeLock.lock(); defer { lifetimeLock.unlock() }
        guard !physicalExitRecorded, process.isRunning else { return }
        _ = Darwin.kill(process.processIdentifier, SIGKILL)
    }

    /// Preserve ordered shutdown controls before EOF. An unresponsive reader
    /// cannot extend the process-specific TERM/KILL deadline.
    func requestGracefulStop(_ command: Data? = nil, gracePeriod: TimeInterval = 2) {
        if let command { _ = send(command) }
        closeInput()
        scheduleForcedTermination(after: gracePeriod)
    }

    private func enqueueInput(_ data: Data, droppable: Bool) -> Bool {
        inputStateLock.lock()
        guard process.isRunning, !inputClosed, !inputCloseRequested else {
            inputStateLock.unlock()
            return false
        }
        if droppable {
            pendingInputs.enqueueDroppable(data)
        } else {
            guard pendingInputs.enqueueControl(
                data,
                byteCount: data.count,
                maximumCount:
                    DaemonCommandBufferLimits.maximumPendingControlCount,
                maximumBytes:
                    DaemonCommandBufferLimits.maximumPendingControlBytes
            ) else {
                inputStateLock.unlock()
                return false
            }
        }
        scheduleInputPumpLocked()
        inputStateLock.unlock()
        return true
    }

    private func scheduleInputPumpLocked() {
        guard !inputPumpScheduled else { return }
        inputPumpScheduled = true
        inputWriteQueue.async { [weak self] in
            self?.drainInput()
        }
    }

    private func drainInput() {
        while true {
            inputStateLock.lock()
            if inputClosed {
                inputPumpScheduled = false
                inputStateLock.unlock()
                return
            }
            let payload: Data?
            switch pendingInputs.takeFirst() {
            case let .control(data, _):
                payload = data
            case let .droppable(data):
                payload = data
            case nil:
                payload = nil
            }
            let shouldClose = payload == nil && inputCloseRequested
            if payload == nil {
                inputPumpScheduled = false
                if shouldClose {
                    inputClosed = true
                    inputCloseRequested = false
                }
            }
            inputStateLock.unlock()

            if let payload {
                if !writeInput(payload) {
                    terminate()
                    return
                }
                continue
            }
            if shouldClose {
                try? inputPipe.fileHandleForWriting.close()
            }
            return
        }
    }

    private func writeInput(_ payload: Data) -> Bool {
        // closeIO may run on another queue. Retain this write's pipe identity
        // under the same state lock, without keeping the lock across blocking
        // I/O. FileHandle.write can raise an Objective-C exception when its
        // handle is concurrently closed; Swift catch cannot recover from it.
        inputStateLock.lock()
        guard !inputClosed else {
            inputStateLock.unlock()
            return false
        }
        let descriptor = fcntl(
            inputPipe.fileHandleForWriting.fileDescriptor,
            F_DUPFD_CLOEXEC,
            0
        )
        inputStateLock.unlock()
        guard descriptor >= 0 else { return false }
        defer { _ = Darwin.close(descriptor) }
        guard fcntl(descriptor, F_SETNOSIGPIPE, 1) == 0 else { return false }

        return payload.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    bytes.baseAddress!.advanced(by: offset),
                    bytes.count - offset
                )
                if written > 0 {
                    offset += written
                } else if written < 0 && errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }

    func scheduleForcedTermination(after delay: TimeInterval) {
        let deadline = DispatchTime.now() + max(0, delay)
        lifetimeLock.lock()
        guard !physicalExitRecorded,
              terminationDeadline == nil || deadline < terminationDeadline! else {
            lifetimeLock.unlock(); return
        }
        terminationDeadline = deadline
        lifetimeLock.unlock()
        terminationQueue.asyncAfter(deadline: deadline) { [weak self] in self?.terminate() }
    }
}

/// Shared bounded exponential retry schedule. A client owns the counter and
/// decides when a successful endpoint event is strong enough to reset it.
struct DaemonRestartBackoff: Equatable, Sendable {
    private(set) var consecutiveFailureCount = 0
    let maximumDelay: TimeInterval

    init(maximumDelay: TimeInterval = 30) {
        self.maximumDelay = maximumDelay
    }

    mutating func nextDelay() -> TimeInterval {
        let delay = Self.delay(
            forConsecutiveFailureCount: consecutiveFailureCount,
            maximumDelay: maximumDelay
        )
        consecutiveFailureCount += 1
        return delay
    }

    mutating func reset() {
        consecutiveFailureCount = 0
    }

    static func delay(
        forConsecutiveFailureCount count: Int,
        maximumDelay: TimeInterval = 30
    ) -> TimeInterval {
        guard count > 0 else { return 0 }
        return min(pow(2, Double(count - 1)), maximumDelay)
    }
}
