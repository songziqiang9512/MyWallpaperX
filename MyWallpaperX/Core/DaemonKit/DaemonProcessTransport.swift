import Foundation

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
        guard process.isRunning else { return false }
        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }

    func closeInput() {
        try? inputPipe.fileHandleForWriting.close()
    }

    func closeIO() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
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
