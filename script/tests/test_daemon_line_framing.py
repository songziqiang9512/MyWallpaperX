"""Shared daemon newline framing preserves split/coalesced pipe payloads."""

from pathlib import Path
import json
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
FRAMING = ROOT / "MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift"
PROJECT = ROOT / "MyWallpaperX.xcodeproj/project.pbxproj"

HARNESS = r'''
import Foundation

struct Message: Codable, Equatable {
    let value: Int
}

@main enum Harness {
    static func main() throws {
        var buffer = DaemonNewlineFrameBuffer()
        precondition(buffer.append(Data(#"{"value":1}"#.utf8)).isEmpty)
        precondition(buffer.pendingByteCount > 0)

        let middle = buffer.append(Data("\n\n{\"value\":2}\n{\"value\":".utf8))
        precondition(middle.count == 2)
        let first = try JSONDecoder().decode(Message.self, from: middle[0])
        let second = try JSONDecoder().decode(Message.self, from: middle[1])
        precondition(first == Message(value: 1))
        precondition(second == Message(value: 2))
        precondition(buffer.pendingByteCount > 0)

        let final = buffer.append(Data("3}\n".utf8))
        precondition(final.count == 1)
        let third = try JSONDecoder().decode(Message.self, from: final[0])
        precondition(third == Message(value: 3))
        precondition(buffer.pendingByteCount == 0)

        let codable = try DaemonNewlineJSON.encode(Message(value: 4))
        precondition(codable.last == 0x0A)
        let fourth = try JSONDecoder().decode(Message.self, from: Data(codable.dropLast()))
        precondition(fourth == Message(value: 4))

        let object = try DaemonNewlineJSON.encodeJSONObject(["value": 5], options: [.sortedKeys])
        precondition(object.last == 0x0A)
        let decoded = try JSONSerialization.jsonObject(with: Data(object.dropLast())) as? [String: Int]
        precondition(decoded == ["value": 5])

        print("daemon-line-framing-pass")
    }
}
'''


class DaemonLineFramingTests(unittest.TestCase):
    def test_split_coalesced_and_blank_frames_round_trip(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-daemon-framing-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "harness"
            harness.write_text(HARNESS, encoding="utf-8")
            compiled = subprocess.run(
                [
                    "xcrun", "swiftc", "-parse-as-library",
                    str(FRAMING), str(harness), "-o", str(binary),
                ],
                capture_output=True, text=True, timeout=60,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            completed = subprocess.run(
                [str(binary)], capture_output=True, text=True, timeout=10
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn("daemon-line-framing-pass", completed.stdout)

    def test_shared_source_has_real_app_scene_and_video_tool_consumers(self) -> None:
        project = PROJECT.read_text(encoding="utf-8")
        self.assertIn("Core/DaemonKit/DaemonNewlineJSON.swift", project)

        consumers = [
            ROOT / "MyWallpaperX/Core/Playback/WallpaperEngine.swift",
            ROOT / "MyWallpaperX/Core/Playback/WallpaperEngine+DaemonEvents.swift",
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonRuntime.swift",
            ROOT / "WallpaperDaemonSources/Daemon/Support/CommandReader.swift",
            ROOT / "WallpaperDaemonSources/Daemon/Support/WallpaperDaemon+Events.swift",
        ]
        sources = [path.read_text(encoding="utf-8") for path in consumers]
        self.assertIn("DaemonNewlineFrameBuffer", sources[0])
        self.assertIn("DaemonNewlineJSON", sources[1])
        self.assertIn("DaemonNewlineJSON", sources[2])
        self.assertIn("DaemonNewlineFrameBuffer", sources[3])
        self.assertIn("DaemonNewlineJSON", sources[4])


if __name__ == "__main__":
    unittest.main()
