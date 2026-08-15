import Darwin
import Foundation

/// Runs one fixed, bundled compiler helper outside the App process. Author
/// source never selects the executable or its arguments outside this type.
nonisolated enum SceneGenericShaderCompilerProcess {
    struct Output {
        let stdout: Data
        let stderr: Data
        let durationMilliseconds: Double
    }

    enum Failure: Error, Equatable {
        case spawn
        case timeout
        case diagnosticBudget
        case residentBudget
        case signaled(signal: Int32)
        case rejected(exitCode: Int32)
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Data()

        private var exceeded = false

        func append(_ data: Data, maximumBytes: Int) -> Bool {
            lock.withLock {
                guard !exceeded else { return false }
                let remaining = maximumBytes - value.count
                if data.count > remaining {
                    if remaining > 0 { value.append(data.prefix(remaining)) }
                    exceeded = true
                    return false
                } else {
                    value.append(data)
                    return true
                }
            }
        }

        func load() -> Data {
            lock.withLock { value }
        }

        func budgetExceeded() -> Bool {
            lock.withLock { exceeded }
        }
    }

    static func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutMilliseconds: Int,
        maximumDiagnosticBytes: Int,
        maximumResidentBytes: Int = .max,
        expectedExitCode: Int32 = 0
    ) -> Result<Output, Failure> {
        guard timeoutMilliseconds > 0, maximumDiagnosticBytes > 0 else {
            return .failure(.spawn)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LC_ALL": "C",
        ]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdout = DataBox()
        let stderr = DataBox()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            read(
                stdoutPipe.fileHandleForReading,
                into: stdout,
                maximumBytes: maximumDiagnosticBytes
            )
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            read(
                stderrPipe.fileHandleForReading,
                into: stderr,
                maximumBytes: maximumDiagnosticBytes
            )
            readers.leave()
        }

        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }
        let started = ContinuousClock.now
        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForWriting.closeFile()
            stderrPipe.fileHandleForWriting.closeFile()
            readers.wait()
            return .failure(.spawn)
        }
        let deadline = DispatchTime.now() + .milliseconds(timeoutMilliseconds)
        var completion: DispatchTimeoutResult = .timedOut
        var residentExceeded = false
        var diagnosticExceeded = false
        repeat {
            completion = terminated.wait(timeout: .now() + .milliseconds(10))
            if completion == .success { break }
            if stdout.budgetExceeded() || stderr.budgetExceeded() {
                diagnosticExceeded = true
                break
            }
            if residentBytes(process.processIdentifier) > UInt64(maximumResidentBytes) {
                residentExceeded = true
                break
            }
        } while DispatchTime.now() < deadline
        guard completion == .success, !residentExceeded, !diagnosticExceeded else {
            process.terminate()
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            readers.wait()
            if residentExceeded { return .failure(.residentBudget) }
            if diagnosticExceeded { return .failure(.diagnosticBudget) }
            return .failure(.timeout)
        }
        readers.wait()
        let elapsed = started.duration(to: .now)
        let stdoutData = stdout.load()
        let stderrData = stderr.load()
        guard !stdout.budgetExceeded(), !stderr.budgetExceeded(),
              stdoutData.count <= maximumDiagnosticBytes,
              stderrData.count <= maximumDiagnosticBytes else {
            return .failure(.diagnosticBudget)
        }
        guard process.terminationReason == .exit else {
            return .failure(.signaled(signal: process.terminationStatus))
        }
        guard process.terminationStatus == expectedExitCode else {
            return .failure(.rejected(exitCode: process.terminationStatus))
        }
        let components = elapsed.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return .success(.init(
            stdout: stdoutData,
            stderr: stderrData,
            durationMilliseconds: milliseconds
        ))
    }

    private static func residentBytes(_ processID: pid_t) -> UInt64 {
        guard processID > 0 else { return 0 }
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(processID, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? usage.ri_phys_footprint : 0
    }

    private static func read(
        _ handle: FileHandle,
        into box: DataBox,
        maximumBytes: Int
    ) {
        while true {
            guard let chunk = try? handle.read(upToCount: 16 * 1_024),
                  !chunk.isEmpty else { return }
            if !box.append(chunk, maximumBytes: maximumBytes) { return }
        }
    }
}
