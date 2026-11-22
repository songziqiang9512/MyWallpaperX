from __future__ import annotations

import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SIGNAL_SOURCE = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core/WebStaticFileSignalScanner.swift"


class WebStaticContentSignalTests(unittest.TestCase):
    def test_truncated_files_receive_bounded_service_worker_scan(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")

        harness = textwrap.dedent(
            r'''
            import Foundation

            func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
                guard condition() else {
                    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
                    exit(1)
                }
            }

            let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let middle = root.appendingPathComponent("middle.js")
            let boundary = root.appendingPathComponent("boundary.js")
            let negative = root.appendingPathComponent("negative.js")
            let oversized = root.appendingPathComponent("oversized.js")

            var middleData = Data(repeating: 97, count: 300_000)
            middleData.replaceSubrange(218_000..<(218_000 + 23), with: Data("navigator.serviceWorker".utf8))
            try middleData.write(to: middle)

            var boundaryData = Data(repeating: 98, count: 300_000)
            let boundaryOffset = 65_530
            boundaryData.replaceSubrange(
                boundaryOffset..<(boundaryOffset + 22),
                with: Data("ServiceWorker.Register".utf8)
            )
            try boundaryData.write(to: boundary)
            try Data(repeating: 99, count: 300_000).write(to: negative)
            var oversizedData = Data(repeating: 100, count: 1024 * 1024 + 1)
            oversizedData.replaceSubrange(218_000..<(218_000 + 23), with: Data("navigator.serviceWorker".utf8))
            try oversizedData.write(to: oversized)

            expect(
                WebStaticFileSignalScanner.containsServiceWorkerRegistration(in: middle),
                "streaming scan should find a middle-of-file navigator signal"
            )
            expect(
                WebStaticFileSignalScanner.containsServiceWorkerRegistration(in: boundary),
                "streaming scan should match case-insensitively across chunk boundaries"
            )
            expect(
                WebStaticFileSignalScanner.containsServiceWorkerRegistration(in: negative) == false,
                "unrelated large files must remain negative"
            )
            expect(
                WebStaticFileSignalScanner.containsServiceWorkerRegistration(in: oversized) == false,
                "generated files above the scan budget must not delay cold startup"
            )
            print("Web static content signal tests passed")
            '''
        )

        with tempfile.TemporaryDirectory(prefix="mwx-web-static-signals-") as directory:
            temporary = Path(directory)
            harness_path = temporary / "main.swift"
            binary_path = temporary / "WebStaticContentSignalTests"
            harness_path.write_text(harness, encoding="utf-8")
            subprocess.run(
                [swiftc, str(SIGNAL_SOURCE), str(harness_path), "-o", str(binary_path)],
                cwd=ROOT,
                check=True,
            )
            completed = subprocess.run(
                [str(binary_path), str(temporary)],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("tests passed", completed.stdout)


if __name__ == "__main__":
    unittest.main()
