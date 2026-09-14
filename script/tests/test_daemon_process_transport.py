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

        let transport = DaemonProcessTransport(
            executableURL: URL(fileURLWithPath: "/bin/cat"),
            arguments: []
        )
        var received = Data()
        transport.onOutput = { received.append($0) }
        try transport.start()
        precondition(transport.send(Data("transport-round-trip\n".utf8)))
        let deadline = Date().addingTimeInterval(3)
        while received.isEmpty && RunLoop.current.run(mode: .default, before: deadline) {}
        precondition(String(data: received, encoding: .utf8) == "transport-round-trip\n")
        transport.terminate()
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
