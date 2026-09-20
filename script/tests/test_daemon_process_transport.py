"""DaemonKit process transport and restart schedule gates."""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
TRANSPORT = ROOT / "MyWallpaperX/Core/DaemonKit/DaemonProcessTransport.swift"

HARNESS = r'''
import Foundation

@main enum Harness {
    static func main() throws {
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
        while received.isEmpty && RunLoop.current.run(mode: .default, before: deadline) {}
        precondition(String(data: received, encoding: .utf8) == "transport-round-trip\n")
        transport.terminate()
        let terminationDeadline = Date().addingTimeInterval(3)
        while !didTerminate
            && RunLoop.current.run(mode: .default, before: terminationDeadline) {}
        precondition(didTerminate)

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
        while !stalledDidTerminate
            && RunLoop.current.run(
                mode: .default,
                before: stalledTerminationDeadline
            ) {}
        precondition(stalledDidTerminate)
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
                [str(binary)], capture_output=True, text=True, timeout=10
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn("daemon-process-transport-pass", completed.stdout)


if __name__ == "__main__":
    unittest.main()
