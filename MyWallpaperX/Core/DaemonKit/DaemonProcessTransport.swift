import Foundation
import Darwin

enum DaemonCommandBufferLimits {
    static let maximumPendingControlCount = 256
    static let maximumPendingControlBytes = 8 * 1_024 * 1_024
}

/// Ordered command buffer with latest-only coalescing inside each control
/// segment. A control is a barrier: values on opposite sides can never replace
/// or overtake each other, while repeated high-rate values in one segment keep
/// only the newest payload.
struct DaemonCommandBuffer<Control, Droppable> {
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

/// One child process wired to stdin/stdout/stderr pipes. Protocol payloads,
/// session identity, and restart decisions stay with the owning engine client.
final class DaemonProcessTransport: @unchecked Sendable {
    let process: Process
    let inputPipe: Pipe
    let outputPipe: Pipe
    let errorPipe: Pipe

    var onOutput: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    var onTermination: ((Int32) -> Void)?

    private(set) var hasStarted = false
    private let inputStateLock = NSLock()
    private let inputWriteQueue = DispatchQueue(
        label: "com.mywallpaperx.daemon-input-writer",
        qos: .userInitiated
    )
    private var pendingInputs = DaemonCommandBuffer<Data, Data>()
    private var inputPumpScheduled = false
    private var inputCloseRequested = false
    private var inputClosed = false

    init(executableURL: URL, arguments: [String]) {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
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
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onOutput?(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let text = String(data: data, encoding: .utf8),
                  !text.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onError?(text)
            }
        }
        process.terminationHandler = { [weak self] process in
            RunLoop.main.perform(inModes: [.common]) { [weak self] in
                self?.onTermination?(process.terminationStatus)
            }
        }
        do {
            try process.run()
        } catch {
            closeIO()
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
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        inputStateLock.lock()
        inputClosed = true
        inputCloseRequested = false
        pendingInputs.removeAll()
        inputStateLock.unlock()
        try? inputPipe.fileHandleForWriting.close()
        try? outputPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
        closeIO()
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
                do {
                    try inputPipe.fileHandleForWriting.write(contentsOf: payload)
                } catch {
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

    func scheduleForcedTermination(after delay: TimeInterval) {
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + delay
        ) { [weak self] in
            guard let self, self.process.isRunning else { return }
            self.terminate()
        }
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
