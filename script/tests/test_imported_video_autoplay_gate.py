#!/usr/bin/env python3

import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
GATE_SOURCES = [
    REPO_ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackResourceLifetime.swift",
    REPO_ROOT / "MyWallpaperX/Core/PlaybackControl/ImportedVideoAutoplayGate.swift",
    REPO_ROOT / "MyWallpaperX/Core/PlaybackControl/WallpaperRuntimeSwitch.swift",
]


class ImportedVideoAutoplayGateTests(unittest.TestCase):
    def test_latest_runtime_intent_controls_autoplay(self) -> None:
        program = """
        import Foundation

        let gate = ImportedVideoAutoplayGate.shared
        final class TestLifetime: PlaybackResourceLifetime {}

        let firstRequest = gate.claim()
        let latestRequest = gate.claim()
        precondition(!gate.isCurrent(firstRequest))
        precondition(gate.isCurrent(latestRequest))

        // A delayed import cannot replace the latest explicit playback intent.
        precondition(!gate.isCurrent(firstRequest))

        let staleAfterRuntimeSwitch = gate.claim()
        postWallpaperRuntimeWillSwitch(to: .web)
        precondition(!gate.isCurrent(staleAfterRuntimeSwitch))

        let replacedSameItem = gate.claim()
        let currentSameItem = gate.claim()
        precondition(!gate.isCurrent(replacedSameItem))
        precondition(gate.isCurrent(currentSameItem))

        var decodedRequest: ImportedVideoPlaybackRequest?
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("AutoplayGateTest"), object: nil, queue: nil
        ) { notification in
            decodedRequest = ImportedVideoPlaybackRequest(notification: notification)
        }
        let lifetime = TestLifetime()
        ImportedVideoPlaybackRequest(
            localURL: URL(fileURLWithPath: "/tmp/latest.mp4"),
            autoplayToken: currentSameItem,
            resourceLifetime: lifetime
        ).post(name: Notification.Name("AutoplayGateTest"))
        NotificationCenter.default.removeObserver(observer)
        precondition(decodedRequest?.localURL.path == "/tmp/latest.mp4")
        precondition(decodedRequest?.autoplayToken == currentSameItem)
        precondition(decodedRequest?.resourceLifetime === lifetime)

        print("imported-video-autoplay-gate-pass")
        """
        with tempfile.TemporaryDirectory() as directory:
            directory_path = Path(directory)
            main_source = directory_path / "main.swift"
            executable = directory_path / "gate-test"
            main_source.write_text(program, encoding="utf-8")
            subprocess.run(
                [
                    "/usr/bin/xcrun",
                    "swiftc",
                    *(str(source) for source in GATE_SOURCES),
                    str(main_source),
                    "-o",
                    str(executable),
                ],
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run(
                [str(executable)],
                check=True,
                capture_output=True,
                text=True,
            )
        self.assertEqual(result.stdout.strip(), "imported-video-autoplay-gate-pass")


if __name__ == "__main__":
    unittest.main()
