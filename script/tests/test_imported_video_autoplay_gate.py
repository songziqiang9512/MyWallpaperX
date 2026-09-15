#!/usr/bin/env python3

import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
GATE_SOURCES = [
    REPO_ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackResourceLifetime.swift",
    REPO_ROOT / "MyWallpaperX/Shared/UI/ImportedVideoAutoplayGate.swift",
    REPO_ROOT / "MyWallpaperX/Modules/OnlineLibrary/Core/OnlineVideoAutoplayRequests.swift",
    REPO_ROOT / "MyWallpaperX/Shared/UI/WallpaperRuntimeSwitch.swift",
]


class ImportedVideoAutoplayGateTests(unittest.TestCase):
    def test_latest_runtime_intent_controls_autoplay(self) -> None:
        program = """
        import Foundation

        let gate = ImportedVideoAutoplayGate.shared
        let requests = OnlineVideoAutoplayRequests()
        final class TestLifetime: PlaybackResourceLifetime {}

        let firstRequest = requests.request(for: 101)
        let latestRequest = requests.request(for: 202)
        precondition(!gate.isCurrent(firstRequest))
        precondition(gate.isCurrent(latestRequest))

        // 下载可以逆序完成，但完成顺序不能改变原始用户意图顺序。
        precondition(requests.complete(for: 101) == firstRequest)
        precondition(requests.complete(for: 202) == latestRequest)
        precondition(gate.isCurrent(latestRequest))

        let staleAfterRuntimeSwitch = requests.request(for: 303)
        postWallpaperRuntimeWillSwitch(to: .web)
        precondition(!gate.isCurrent(staleAfterRuntimeSwitch))

        let replacedSameItem = requests.request(for: 404)
        let currentSameItem = requests.request(for: 404)
        precondition(!gate.isCurrent(replacedSameItem))
        precondition(requests.complete(for: 404) == currentSameItem)
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
