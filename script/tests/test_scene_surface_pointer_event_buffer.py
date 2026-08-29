#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneSurfacePointerState.swift"
)

HARNESS_SOURCE = r'''
import Foundation
import simd

@main
enum Harness {
    static func event(_ x: Float, _ down: Bool) -> SceneSurfacePointerEvent {
        SceneSurfacePointerEvent(
            normalizedPosition: SIMD2(x, 0),
            isInside: true,
            primaryButtonIsDown: down
        )
    }

    static func main() throws {
        var rapid = SceneSurfacePointerEventBuffer()
        rapid.append(event(0.1, false))
        rapid.append(event(0.1, true))
        rapid.append(event(0.1, false))
        let ordered = rapid.drain()

        var overflow = SceneSurfacePointerEventBuffer()
        for index in 0...SceneSurfacePointerEventBuffer.maximumEventCount {
            overflow.append(event(Float(index), index.isMultiple(of: 2)))
        }
        let rejected = overflow.drain()
        overflow.append(event(0.5, true))
        let recovered = overflow.drain()

        let result: [String: Any] = [
            "rapidStates": ordered.events.map(\.primaryButtonIsDown),
            "rapidOverflowed": ordered.overflowed,
            "overflowRejectedAll": rejected.overflowed && rejected.events.isEmpty,
            "recovered": !recovered.overflowed
                && recovered.events.map(\.primaryButtonIsDown) == [true],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneSurfacePointerEventBufferTests(unittest.TestCase):
    def test_rapid_edges_remain_ordered_and_overflow_is_atomic(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-pointer-events-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "pointer-events"
            harness.write_text(HARNESS_SOURCE, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    str(SOURCE), str(harness), "-o", str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                compilation.returncode,
                0,
                compilation.stdout + compilation.stderr,
            )
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                completed.returncode,
                0,
                completed.stdout + completed.stderr,
            )
            payload = json.loads(completed.stdout)
            self.assertEqual(payload["rapidStates"], [False, True, False])
            self.assertFalse(payload["rapidOverflowed"])
            self.assertTrue(payload["overflowRejectedAll"])
            self.assertTrue(payload["recovered"])


if __name__ == "__main__":
    unittest.main()
