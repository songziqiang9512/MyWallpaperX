"""DaemonKit process transport and restart schedule gates."""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
TRANSPORT = ROOT / "MyWallpaperX/Core/DaemonKit/DaemonProcessTransport.swift"

HARNESS = r'''
import Foundation
import Darwin
import CoreFoundation

@main enum Harness {
    static func main() throws {
        if let mode = ProcessInfo.processInfo.arguments.dropFirst().first {
            signal(SIGPIPE, SIG_IGN)
            switch mode {
            case "--child-final-output":
                var payload = Data(repeating: 0x64, count: 8 * 1_024 * 1_024 + 128)
                payload.append(Data("-FINAL\n".utf8))
                try FileHandle.standardOutput.write(contentsOf: payload)
                try FileHandle.standardError.write(contentsOf: Data("final-diagnostic\n".utf8))
                return
            case "--child-flood-output", "--child-flood-error":
                let destination = mode == "--child-flood-output"
                    ? FileHandle.standardOutput : FileHandle.standardError
                let chunk = Data(repeating: 0x65, count: 256 * 1_024)
                for _ in 0..<128 { try? destination.write(contentsOf: chunk) }
                Thread.sleep(forTimeInterval: 5)
                return
            case "--child-inherited-pipe":
                let descendant = Process()
                descendant.executableURL = URL(fileURLWithPath: "/bin/sleep")
                descendant.arguments = ["5"]
                descendant.standardOutput = FileHandle.standardOutput
                descendant.standardError = FileHandle.standardError
                try descendant.run()
                try FileHandle.standardOutput.write(contentsOf: Data("\(descendant.processIdentifier)\n".utf8))
                return
            default: preconditionFailure("unknown child mode")
            }
        }

        var backoff = DaemonRestartBackoff()
        precondition((0..<7).map { _ in backoff.nextDelay() } == [0, 1, 2, 4, 8, 16, 30])
        backoff.reset()
        precondition(backoff.nextDelay() == 0)

        var buffered = DaemonCommandBuffer<String, String>()
        buffered.enqueueDroppable("A1")
        precondition(buffered.enqueueControl(
            "C", byteCount: 1, maximumCount: 2, maximumBytes: 8
        ))
        buffered.enqueueDroppable("A2")
        buffered.enqueueDroppable("A3")
        guard case .droppable("A1")? = buffered.takeFirst(),
              case .control("C", 1)? = buffered.takeFirst(),
              case .droppable("A3")? = buffered.takeFirst(),
              buffered.takeFirst() == nil else {
            preconditionFailure("latest-only values crossed a control barrier")
        }
        buffered.enqueueDroppable("drop-before-close")
        precondition(buffered.enqueueControl(
            "shutdown", byteCount: 8, maximumCount: 2, maximumBytes: 8
        ))
        buffered.enqueueDroppable("drop-after-close")
        buffered.discardDroppable()
        guard case .control("shutdown", 8)? = buffered.takeFirst(),
              buffered.takeFirst() == nil else {
            preconditionFailure("close must retain controls and discard latest values")
        }

        var bounded = DaemonCommandBuffer<String, String>()
        bounded.enqueueDroppable("A1")
        precondition(bounded.enqueueControl(
            "C1", byteCount: 4, maximumCount: 2, maximumBytes: 8
        ))
        bounded.enqueueDroppable("A2")
        bounded.enqueueDroppable("A3")
        precondition(bounded.enqueueControl(
            "C2", byteCount: 4, maximumCount: 2, maximumBytes: 8
        ))
        bounded.enqueueDroppable("A4")
        precondition(!bounded.enqueueControl(
            "C3", byteCount: 1, maximumCount: 2, maximumBytes: 8
        ))
        guard bounded.controlCount == 2, bounded.controlBytes == 8,
              case .droppable("A1")? = bounded.takeFirst(),
              case .control("C1", 4)? = bounded.takeFirst(),
              case .droppable("A3")? = bounded.takeFirst(),
              case .control("C2", 4)? = bounded.takeFirst(),
              case .droppable("A4")? = bounded.takeFirst(),
              bounded.takeFirst() == nil,
              bounded.controlCount == 0,
              bounded.controlBytes == 0 else {
            preconditionFailure("bounded interleaved command admission failed")
        }
        precondition(!bounded.enqueueControl(
            "oversize", byteCount: 9, maximumCount: 2, maximumBytes: 8
        ))

        let transport = DaemonProcessTransport(
            executableURL: URL(fileURLWithPath: "/bin/cat"),
            arguments: []
        )
        var received = Data()
        var didTerminate = false
        transport.onOutput = { received.append($0) }
        transport.onTermination = { _ in didTerminate = true }
        try transport.start()
        precondition(transport.send(Data("transport-round-trip\n".utf8)))
        let deadline = Date().addingTimeInterval(3)
        while received.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(String(data: received, encoding: .utf8) == "transport-round-trip\n")
        transport.terminate()
        let terminationDeadline = Date().addingTimeInterval(3)
        while !didTerminate && Date() < terminationDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(didTerminate)

        let ownExecutable = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        // Exit can be observed before the final readable notification. All bytes
        // already written by a normally exiting child must precede termination,
        // including an entire maximum-size frame buffered while main is blocked.
        let finalOutput = DaemonProcessTransport(
            executableURL: ownExecutable, arguments: ["--child-final-output"]
        )
        var finalBytes = Data()
        var finalError = ""
        var finalTerminated = false
        var expectedFinal = Data(repeating: 0x64, count: 8 * 1_024 * 1_024 + 128)
        expectedFinal.append(Data("-FINAL\n".utf8))
        finalOutput.onOutput = { finalBytes.append($0) }
        finalOutput.onError = { finalError += $0 }
        finalOutput.onTermination = { status in
            precondition(status == 0)
            precondition(finalBytes == expectedFinal, "exit overtook complete stdout")
            precondition(finalError == "final-diagnostic\n", "exit overtook stderr")
            finalTerminated = true
        }
        try finalOutput.start()
        Thread.sleep(forTimeInterval: 0.2)
        precondition(finalBytes.isEmpty && !finalTerminated)
        let trackingMode = RunLoop.Mode("MWXTransportTracking")
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(rawValue: trackingMode.rawValue as CFString))
        let trackingTimer = Timer(timeInterval: 0.01, repeats: true) { _ in }
        RunLoop.current.add(trackingTimer, forMode: trackingMode)
        let finalDeadline = Date().addingTimeInterval(5)
        while !finalTerminated && Date() < finalDeadline {
            RunLoop.current.run(mode: trackingMode, before: Date().addingTimeInterval(0.01))
        }
        precondition(finalTerminated, "output callbacks must run in common modes")
        trackingTimer.invalidate()
        finalOutput.closeIO()

        // A real producer must be stopped by receive admission while the parent
        // cannot drain main. The old per-read main.async path kept both children
        // alive, retaining all 32 MiB in queued closures without reaching a limit.
        for mode in ["--child-flood-output", "--child-flood-error"] {
            let flood = DaemonProcessTransport(executableURL: ownExecutable, arguments: [mode])
            var floodFailure = ""
            var floodTerminated = false
            flood.onError = { floodFailure += $0 }
            flood.onTermination = { _ in
                precondition(floodFailure.contains("transport-output-limit-exceeded"))
                floodTerminated = true
            }
            try flood.start()
            let blockedDeadline = Date().addingTimeInterval(2)
            while flood.isRunning && Date() < blockedDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            precondition(!flood.isRunning, "receive limits depended on the blocked parent main loop")
            precondition(floodFailure.isEmpty && !floodTerminated)
            let drainDeadline = Date().addingTimeInterval(3)
            while !floodTerminated && Date() < drainDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            precondition(floodTerminated)
        }

        let inherited = DaemonProcessTransport(
            executableURL: ownExecutable, arguments: ["--child-inherited-pipe"]
        )
        var inheritedPIDBytes = Data()
        var inheritedFailure = ""
        var inheritedTerminated = false
        inherited.onOutput = { inheritedPIDBytes.append($0) }
        inherited.onError = { inheritedFailure += $0 }
        inherited.onTermination = { _ in inheritedTerminated = true }
        try inherited.start()
        let inheritedDeadline = Date().addingTimeInterval(3)
        while !inheritedTerminated && Date() < inheritedDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        guard let leakedPID = Int32(String(decoding: inheritedPIDBytes, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)) else {
            preconditionFailure("inherited-pipe fixture did not report its exact descendant")
        }
        _ = Darwin.kill(leakedPID, SIGTERM)
        precondition(inheritedTerminated, "a descendant's pipe delayed the exited child's callback")
        precondition(inheritedFailure.contains("transport-output-eof-timeout"))

        let stalled = DaemonProcessTransport(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["3"]
        )
        var stalledDidTerminate = false
        stalled.onTermination = { _ in stalledDidTerminate = true }
        try stalled.start()
        let droppableFrame = Data(repeating: 0x61, count: 16_384)
        let startedAt = Date()
        for _ in 0 ..< 10_000 {
            precondition(stalled.sendLatest(droppableFrame))
        }
        precondition(Date().timeIntervalSince(startedAt) < 0.5)
        let boundedControl = Data(repeating: 0x62, count: 1_048_576)
        let acceptedControls = (0 ..< 32).filter { _ in
            stalled.send(boundedControl)
        }.count
        precondition(acceptedControls > 0 && acceptedControls < 32)
        let terminationStartedAt = Date()
        precondition(!stalled.sendRequired(boundedControl))
        precondition(Date().timeIntervalSince(terminationStartedAt) < 0.5)
        let stalledTerminationDeadline = Date().addingTimeInterval(3)
        while !stalledDidTerminate && Date() < stalledTerminationDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(stalledDidTerminate)

        // Exercise both a queued writer and a write blocked in the pipe while
        // another queue closes the transport. A closed Foundation FileHandle
        // used by the writer can raise an uncaught Objective-C exception.
        for iteration in 0..<48 {
            let racing = DaemonProcessTransport(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["3"]
            )
            try racing.start()
            precondition(racing.send(Data(repeating: 0x63, count: 1_048_576)))
            if iteration % 3 != 0 {
                Thread.sleep(forTimeInterval: iteration % 3 == 1 ? 0.0001 : 0.001)
            }
            let closeFinished = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                racing.terminate()
                closeFinished.signal()
            }
            precondition(closeFinished.wait(timeout: .now() + 1) == .success)
            racing.process.waitUntilExit()
            precondition(!racing.isRunning)
            precondition(!racing.sendLatest(droppableFrame))
        }
        // Cancellation can also race a readable source, not only a blocked
        // stdin writer. Source-owned duplicate descriptors must never be closed
        // under an active read and then reused as another transport's pipe.
        for iteration in 0..<16 {
            let racing = DaemonProcessTransport(
                executableURL: URL(fileURLWithPath: "/bin/cat"), arguments: []
            )
            try racing.start()
            precondition(racing.send(Data(repeating: 0x72, count: 256 * 1_024)))
            Thread.sleep(forTimeInterval: iteration % 2 == 0 ? 0.0001 : 0.001)
            let closed = DispatchSemaphore(value: 0)
            DispatchQueue.global().async { racing.terminate(); closed.signal() }
            precondition(closed.wait(timeout: .now() + 1) == .success)
            racing.process.waitUntilExit()
            precondition(!racing.isRunning)
        }
        print("daemon-process-transport-pass")
    }
}
'''


class DaemonProcessTransportTests(unittest.TestCase):
    def test_transport_round_trip_and_bounded_backoff(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-daemon-transport-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "harness"
            harness.write_text(HARNESS, encoding="utf-8")
            compiled = subprocess.run(
                [
                    "xcrun", "swiftc", "-parse-as-library",
                    str(TRANSPORT), str(harness), "-o", str(binary),
                ],
                capture_output=True, text=True, timeout=60,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            completed = subprocess.run(
                [str(binary)], capture_output=True, text=True, timeout=20
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn("daemon-process-transport-pass", completed.stdout)


if __name__ == "__main__":
    unittest.main()
