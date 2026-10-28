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
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceIndex.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceView.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/../SteamWorkshopStorage/ScenePlaybackSource.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Format/ScenePkgReader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceIdentity.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceView+Backing.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceReferenceIndex.swift",
]

HARNESS_SOURCE = r'''
import Foundation

struct SceneDocument {
    let referencedResourcePaths: [String]
}

@main
enum Harness {
    static func main() throws {
        let rootURL = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let resourceIndex = SceneResourceIndex(
            rootURL: rootURL,
            resources: [
                .init(
                    relativePath: "models/example.json",
                    url: rootURL.appendingPathComponent("models/example.json"),
                    kind: .model,
                    fileSize: 1
                ),
                .init(
                    relativePath: "materials/workshop/3571866376/Album art 3  test .tex",
                    url: rootURL.appendingPathComponent(
                        "materials/workshop/3571866376/Album art 3  test .tex"
                    ),
                    kind: .texture,
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
            "workshop/3571866376/Album art 3  test ",
            "workshop/3571866376/Album art 3  test",
            "materials/missing",
        ]
        let index = SceneResourceReferenceIndexBuilder().build(
            document: SceneDocument(referencedResourcePaths: references),
            resourceView: SceneResourceView(projectRoot: .init(source: .loose, url: rootURL, index: resourceIndex),
                packageRoot: nil, stockRoot: nil)
        )

        let alternatives = (0..<5).map { index -> [String] in
            let path = "pick-\(index)"
            return [path, path + ".json", "materials/" + path + ".json",
                    "materials/" + path + ".tex", path + ".tex"]
        }
        let candidatePaths = alternatives.enumerated().flatMap { index, paths in
            paths.dropFirst(index).map { $0.uppercased().replacingOccurrences(of: "/", with: "\\") }
        }
        let candidateResources = candidatePaths.map { path in
            SceneResourceIndex.Resource(relativePath: path, url: rootURL.appendingPathComponent(path),
                kind: .other, fileSize: 1)
        }
        let stockURL = rootURL.appendingPathComponent("stock-fixture")
        try FileManager.default.createDirectory(at: stockURL, withIntermediateDirectories: true)
        let stockResources = ["DuPe\\Item.TeX", "dupe/item.tex"].map { path in
            SceneResourceIndex.Resource(relativePath: path, url: stockURL.appendingPathComponent(path),
                kind: .texture, fileSize: 1)
        }
        let candidateView = SceneResourceView(
            projectRoot: .init(source: .loose, url: rootURL,
                index: .init(rootURL: rootURL, resources: candidateResources)), packageRoot: nil,
            stockRoot: .init(source: .stock, url: stockURL,
                index: .init(rootURL: stockURL, resources: stockResources)))
        let candidateReferences = (0..<5).map { "PICK-\($0)" }
            + ["ASSETS\\DUPE\\ITEM.TEX", "  PICK-0  "]
        let candidateIndex = SceneResourceReferenceIndexBuilder().build(
            document: SceneDocument(referencedResourcePaths: candidateReferences), resourceView: candidateView)

        let result: [String: Any] = [
            "resolvedCount": index.resolvedCount,
            "builtInCount": index.builtInReferenceCount,
            "runtimeProvidedCount": index.runtimeProvidedReferenceCount,
            "missingReferences": index.missingReferences,
            "matches": index.matches.map { match in
                [
                    "path": match.referencedPath,
                    "matchedPath": match.matchedPath as Any? ?? NSNull(),
                    "resolved": match.isResolved,
                    "builtIn": match.isBuiltInReference,
                    "runtimeProvided": match.isRuntimeProvidedReference,
                    "missing": match.isMissing,
                ] as [String: Any]
            },
            "normalizedStockAliasCopies": candidateView.availableRelativePaths.filter {
                $0.replacingOccurrences(of: "\\", with: "/").localizedLowercase == "assets/dupe/item.tex"
            }.count,
            "candidateMatches": candidateIndex.matches.map { match in
                ["path": match.referencedPath, "matchedPath": match.matchedPath as Any? ?? NSNull(),
                 "resolved": match.isResolved, "builtIn": match.isBuiltInReference,
                 "runtimeProvided": match.isRuntimeProvidedReference, "missing": match.isMissing] as [String: Any]
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
                "xcrun", "--sdk", "macosx", "swiftc", "-D", "DEBUG",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary), str(directory / "resources")], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_counts_distinguish_disk_built_in_runtime_and_missing(self) -> None:
        self.assertEqual(self.result["resolvedCount"], 2)
        self.assertEqual(self.result["builtInCount"], 1)
        self.assertEqual(self.result["runtimeProvidedCount"], 3)
        self.assertEqual(
            self.result["missingReferences"],
            [
                "_rt_imageLayerComposite_bad_a",
                "_rt_imageLayerComposite_42_c",
                "_rt_imagelayercomposite_42_a",
                "workshop/3571866376/Album art 3  test",
                "materials/missing",
            ],
        )

    def test_file_reference_whitespace_is_part_of_the_path_identity(self) -> None:
        matches = {match["path"]: match for match in self.result["matches"]}
        self.assertTrue(matches["workshop/3571866376/Album art 3  test "]["resolved"])
        self.assertFalse(matches["workshop/3571866376/Album art 3  test"]["resolved"])

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

    def test_normalized_membership_retains_all_candidate_priorities(self) -> None:
        self.assertEqual(self.result["normalizedStockAliasCopies"], 2)
        expected_paths = ["pick-0", "pick-1.json", "materials/pick-2.json",
                          "materials/pick-3.tex", "pick-4.tex", "assets/dupe/item.tex", None]
        for match, expected in zip(self.result["candidateMatches"], expected_paths, strict=True):
            self.assertEqual(match["matchedPath"], expected, match["path"])
            self.assertEqual(match["resolved"], expected is not None, match["path"])
            self.assertEqual(match["missing"], expected is None, match["path"])
            self.assertFalse(match["builtIn"], match["path"])
            self.assertFalse(match["runtimeProvided"], match["path"])


if __name__ == "__main__":
    unittest.main()
