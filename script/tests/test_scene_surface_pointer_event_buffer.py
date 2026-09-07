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
        let bounds = CGRect(x: 10, y: 20, width: 100, height: 50)
        let points: [CGPoint] = [
            .init(x: 60, y: 45), .init(x: 60, y: 70),
            .init(x: 10, y: 20), .init(x: 110, y: 70),
            .init(x: 60, y: 70.01), .init(x: 9.99, y: 45),
            .init(x: 60, y: 69.99),
            .init(x: 10, y: 70), .init(x: 110, y: 20),
        ]
        let edgeSamples = points.map {
            SceneSurfacePointerEvent.sample(
                localPosition: $0, bounds: bounds, primaryButtonIsDown: true
            )!
        }
        let invalid = SceneSurfacePointerEvent.sample(
            localPosition: .init(x: CGFloat.nan, y: 20),
            bounds: bounds, primaryButtonIsDown: false
        )
        let empty = SceneSurfacePointerEvent.sample(
            localPosition: .zero, bounds: .zero, primaryButtonIsDown: false
        )
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

        var restored = SceneSurfacePointerEventBuffer()
        restored.append(event(0.1, false))
        restored.append(event(0.2, true))
        let drainedForRestore = restored.drain()
        restored.append(event(0.3, false))
        restored.restore(drainedForRestore)
        let restoredOrder = restored.drain()

        var overflowRestored = SceneSurfacePointerEventBuffer()
        for index in 0...SceneSurfacePointerEventBuffer.maximumEventCount {
            overflowRestored.append(event(Float(index), index.isMultiple(of: 2)))
        }
        let rejectedOverflow = overflowRestored.drain()
        overflowRestored.append(event(0.7, true))
        overflowRestored.restore(rejectedOverflow)
        let overflowRejectedAgain = overflowRestored.drain()

        let result: [String: Any] = [
            "edgeInside": edgeSamples.map(\.isInside),
            "edgePosition": edgeSamples.map {
                [$0.normalizedPosition.x, $0.normalizedPosition.y]
            },
            "edgeButtons": edgeSamples.allSatisfy(\.primaryButtonIsDown),
            "invalidRejected": invalid == nil && empty == nil,
            "rapidStates": ordered.events.map(\.primaryButtonIsDown),
            "rapidOverflowed": ordered.overflowed,
            "overflowRejectedAll": rejected.overflowed && rejected.events.isEmpty,
            "recovered": !recovered.overflowed
                && recovered.events.map(\.primaryButtonIsDown) == [true],
            "restoredOrder": restoredOrder.events.map {
                [$0.normalizedPosition.x, $0.primaryButtonIsDown ? 1 : 0]
            },
            "restoredNotOverflowed": !restoredOrder.overflowed,
            "overflowRestoredRejectsAgain": overflowRejectedAgain.overflowed
                && overflowRejectedAgain.events.isEmpty,
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
            self.assertEqual(payload["edgeInside"], [True, True, True, True, False, False, True, True, True])
            self.assertEqual(payload["edgePosition"][:4], [[0, 0], [0, 1], [-1, -1], [1, 1]])
            self.assertGreater(payload["edgePosition"][4][1], 1)
            self.assertLess(payload["edgePosition"][5][0], -1)
            self.assertLess(payload["edgePosition"][6][1], 1)
            self.assertEqual(payload["edgePosition"][7:], [[-1, 1], [1, -1]])
            self.assertTrue(payload["edgeButtons"])
            self.assertTrue(payload["invalidRejected"])
            self.assertEqual(payload["rapidStates"], [False, True, False])
            self.assertFalse(payload["rapidOverflowed"])
            self.assertTrue(payload["overflowRejectedAll"])
            self.assertTrue(payload["recovered"])
            # Restore re-inserts the drained batch at the front, so FIFO
            # order survives a dropped frame's rollback.
            self.assertEqual(len(payload["restoredOrder"]), 3)
            for restored, expected in zip(
                payload["restoredOrder"],
                [(0.1, 0), (0.2, 1), (0.3, 0)],
            ):
                self.assertAlmostEqual(restored[0], expected[0], places=5)
                self.assertEqual(restored[1], expected[1])
            self.assertTrue(payload["restoredNotOverflowed"])
            # Restoring a rejected overflowed batch keeps failing closed:
            # the next drain must reject the whole batch again instead of
            # synthesizing a partial press/release sequence.
            self.assertTrue(payload["overflowRestoredRejectsAgain"])


if __name__ == "__main__":
    unittest.main()
