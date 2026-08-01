#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Format/SceneObjectDependency.swift"

HARNESS_SOURCE = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let parsed = SceneObjectDependencies(rawValue: [
            7,
            ["id": 38, "index": 0, "type": " EmitterImage "],
            ["id": "bad", "index": 0, "type": "emitterimage"],
            ["id": 9, "index": "bad", "type": " "],
        ] as [Any])
        let result: [String: Any] = [
            "legacy": parsed.legacyLayerIDs,
            "authored": parsed.authored.map {
                ["id": $0.layerID, "index": $0.index as Any, "type": $0.type as Any]
            },
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneObjectDependencyTests(unittest.TestCase):
    def test_legacy_and_typed_dependencies_stay_in_separate_channels(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-scene-dependency-") as raw_directory:
            directory = Path(raw_directory)
            harness = directory / "Harness.swift"
            harness.write_text(HARNESS_SOURCE, encoding="utf-8")
            binary = directory / "dependency"
            subprocess.run(
                ["swiftc", str(SOURCE), str(harness), "-o", str(binary)],
                check=True,
                capture_output=True,
                text=True,
            )
            completed = subprocess.run(
                [str(binary)], check=True, capture_output=True, text=True
            )
        result = json.loads(completed.stdout)
        self.assertEqual(result["legacy"], [7])
        self.assertEqual(
            result["authored"],
            [
                {"id": 38, "index": 0, "type": "emitterimage"},
                {"id": 9, "index": None, "type": None},
            ],
        )


if __name__ == "__main__":
    unittest.main()
