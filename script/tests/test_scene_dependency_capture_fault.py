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
    / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/LayerDependencies"
    / "SceneDependencyCaptureFault.swift"
)

HARNESS_SOURCE = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let key = SceneDependencyCaptureFault.environmentKey
        let providers = [10, 20]
        var first = SceneDependencyCaptureFault(environment: [key: "1"])
        var second = SceneDependencyCaptureFault(environment: [key: "2"])
        var invalid = SceneDependencyCaptureFault(environment: [key: "0"])
        var outOfRange = SceneDependencyCaptureFault(environment: [key: "3"])

        let result: [String: Any] = [
            "contains": SceneDependencyCaptureFault.containsRequest(
                in: [key: "2"]
            ),
            "missing": SceneDependencyCaptureFault.requestedOrdinal(
                in: [:]
            ) as Any,
            "invalid": SceneDependencyCaptureFault.requestedOrdinal(
                in: [key: "0"]
            ) as Any,
            "ordinal": SceneDependencyCaptureFault.requestedOrdinal(
                in: [key: "2"]
            ) as Any,
            "firstSequence": [
                first.shouldDropCapture(
                    for: 20, orderedProviderLayerIDs: providers
                ),
                first.shouldDropCapture(
                    for: 10, orderedProviderLayerIDs: providers
                ),
                first.shouldDropCapture(
                    for: 10, orderedProviderLayerIDs: providers
                ),
                first.observeSuccessfulCapture(for: 20),
                first.observeSuccessfulCapture(for: 10),
                first.observeSuccessfulCapture(for: 10),
            ],
            "secondSequence": [
                second.shouldDropCapture(
                    for: 10, orderedProviderLayerIDs: providers
                ),
                second.shouldDropCapture(
                    for: 20, orderedProviderLayerIDs: providers
                ),
                second.shouldDropCapture(
                    for: 20, orderedProviderLayerIDs: providers
                ),
                second.observeSuccessfulCapture(for: 20),
                second.observeSuccessfulCapture(for: 20),
            ],
            "invalidSequence": [
                invalid.shouldDropCapture(
                    for: 10, orderedProviderLayerIDs: providers
                ),
                invalid.shouldDropCapture(
                    for: 20, orderedProviderLayerIDs: providers
                ),
            ],
            "outOfRangeSequence": [
                outOfRange.shouldDropCapture(
                    for: 10, orderedProviderLayerIDs: providers
                ),
                outOfRange.shouldDropCapture(
                    for: 20, orderedProviderLayerIDs: providers
                ),
            ],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result, options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneDependencyCaptureFaultTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-dependency-capture-fault-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-dependency-capture-fault"
        subprocess.run(
            [
                "swiftc",
                "-D",
                "DEBUG",
                str(SOURCE),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            check=True,
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        completed = subprocess.run(
            [str(cls.binary)],
            check=True,
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_request_is_positive_one_based_ordinal(self) -> None:
        self.assertTrue(self.result["contains"])
        self.assertIsNone(self.result["missing"])
        self.assertIsNone(self.result["invalid"])
        self.assertEqual(self.result["ordinal"], 2)

    def test_fault_drops_only_selected_provider_once_then_recovers_once(self) -> None:
        self.assertEqual(
            self.result["firstSequence"],
            [False, True, False, False, True, False],
        )
        self.assertEqual(
            self.result["secondSequence"],
            [False, True, False, True, False],
        )
        self.assertEqual(self.result["invalidSequence"], [False, False])
        self.assertEqual(self.result["outOfRangeSequence"], [False, False])


if __name__ == "__main__":
    unittest.main()
