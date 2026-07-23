#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SOURCE_ROOT / "Resources/SceneResourceIndex.swift",
    SOURCE_ROOT / "Resources/SceneResourceReferenceIndex.swift",
]

HARNESS_SOURCE = r'''
import Foundation

struct SceneDocument {
    let referencedResourcePaths: [String]
}

struct ScenePkgExtractionReport {
    let discoveredPaths: [String]
}

@main
enum Harness {
    static func main() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/scene-resource-reference-index")
        let resourceIndex = SceneResourceIndex(
            rootURL: rootURL,
            resources: [
                .init(
                    relativePath: "models/example.json",
                    url: rootURL.appendingPathComponent("models/example.json"),
                    kind: .model,
                    fileSize: 1
                )
            ]
        )
        let references = [
            "models/example",
            "models/util/solidlayer.json",
            "_rt_imageLayerComposite_42",
            "_rt_imageLayerComposite_42_a",
            "  _rt_imageLayerComposite_42_b  ",
            "_rt_imageLayerComposite_bad_a",
            "_rt_imageLayerComposite_42_c",
            "_rt_imagelayercomposite_42_a",
            "materials/missing",
        ]
        let index = SceneResourceReferenceIndexBuilder().build(
            document: SceneDocument(referencedResourcePaths: references),
            packageReport: nil,
            resourceIndex: resourceIndex
        )

        let result: [String: Any] = [
            "resolvedCount": index.resolvedCount,
            "builtInCount": index.builtInReferenceCount,
            "runtimeProvidedCount": index.runtimeProvidedReferenceCount,
            "missingReferences": index.missingReferences,
            "matches": index.matches.map { match in
                [
                    "path": match.referencedPath,
                    "resolved": match.isResolved,
                    "builtIn": match.isBuiltInReference,
                    "runtimeProvided": match.isRuntimeProvidedReference,
                    "missing": match.isMissing,
                ] as [String: Any]
            },
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneResourceReferenceIndexTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-resource-reference-index-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-resource-reference-index"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_counts_distinguish_disk_built_in_runtime_and_missing(self) -> None:
        self.assertEqual(self.result["resolvedCount"], 1)
        self.assertEqual(self.result["builtInCount"], 1)
        self.assertEqual(self.result["runtimeProvidedCount"], 3)
        self.assertEqual(
            self.result["missingReferences"],
            [
                "_rt_imageLayerComposite_bad_a",
                "_rt_imageLayerComposite_42_c",
                "_rt_imagelayercomposite_42_a",
                "materials/missing",
            ],
        )

    def test_runtime_references_are_recognized_only_by_typed_parser(self) -> None:
        matches = {match["path"]: match for match in self.result["matches"]}
        for path in (
            "_rt_imageLayerComposite_42",
            "_rt_imageLayerComposite_42_a",
            "  _rt_imageLayerComposite_42_b  ",
        ):
            self.assertTrue(matches[path]["runtimeProvided"])
            self.assertFalse(matches[path]["resolved"])
            self.assertFalse(matches[path]["missing"])

        for path in (
            "_rt_imageLayerComposite_bad_a",
            "_rt_imageLayerComposite_42_c",
            "_rt_imagelayercomposite_42_a",
        ):
            self.assertFalse(matches[path]["runtimeProvided"])
            self.assertTrue(matches[path]["missing"])


if __name__ == "__main__":
    unittest.main()
