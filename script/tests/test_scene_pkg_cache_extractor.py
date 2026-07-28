#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/ScenePkgReader.swift",
    SCENE_ROOT / "Format/ScenePkgCacheExtractor.swift",
]

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let packageURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let projectRootURL = URL(
            fileURLWithPath: CommandLine.arguments[2], isDirectory: true
        )
        let replacementPackageURL = URL(fileURLWithPath: CommandLine.arguments[3])
        let originalModifiedAt = try FileManager.default.attributesOfItem(
            atPath: packageURL.path
        )[.modificationDate] as! Date
        let extractor = ScenePkgCacheExtractor()
        let cold = try extractor.extract(
            packageURL: packageURL, projectRootURL: projectRootURL
        )
        let textureURL = cold.outputURL.appendingPathComponent("materials/shared.tex")
        let preservedModifiedAt = Date(timeIntervalSince1970: 1_234)
        try FileManager.default.setAttributes(
            [.modificationDate: preservedModifiedAt],
            ofItemAtPath: textureURL.path
        )
        let warm = try extractor.extract(
            packageURL: packageURL, projectRootURL: projectRootURL
        )
        let warmBytes = try Data(contentsOf: textureURL)
        let warmModifiedAt = try FileManager.default.attributesOfItem(
            atPath: textureURL.path
        )[.modificationDate] as! Date
        try Data("corrupt-texture".utf8).write(to: textureURL)
        let sameSizeRepaired = try extractor.extract(
            packageURL: packageURL, projectRootURL: projectRootURL
        )
        let sameSizeRepairedBytes = try Data(contentsOf: textureURL)
        try Data("short".utf8).write(to: textureURL)
        let truncatedRepaired = try extractor.extract(
            packageURL: packageURL, projectRootURL: projectRootURL
        )
        let truncatedRepairedBytes = try Data(contentsOf: textureURL)
        let staleURL = truncatedRepaired.outputURL.appendingPathComponent(
            "materials/stale.tex"
        )
        try Data("stale".utf8).write(to: staleURL)
        let extraFileRepaired = try extractor.extract(
            packageURL: packageURL, projectRootURL: projectRootURL
        )
        let markerURL = extraFileRepaired.outputURL.appendingPathComponent(
            ".mwx-scene-pkg-cache-v1.json"
        )
        let replacementData = try Data(contentsOf: replacementPackageURL)
        try replacementData.write(to: packageURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.modificationDate: originalModifiedAt],
            ofItemAtPath: packageURL.path
        )
        let updated = try extractor.extract(
            packageURL: packageURL, projectRootURL: projectRootURL
        )
        let updatedBytes = try Data(
            contentsOf: updated.outputURL.appendingPathComponent("materials/shared.tex")
        )
        let result: [String: Any] = [
            "paths": cold.extractedPaths,
            "warmPaths": warm.extractedPaths,
            "sameSizeRepairedPaths": sameSizeRepaired.extractedPaths,
            "truncatedRepairedPaths": truncatedRepaired.extractedPaths,
            "warmPreserved": String(decoding: warmBytes, as: UTF8.self),
            "warmModificationPreserved":
                warmModifiedAt.timeIntervalSince1970 == preservedModifiedAt.timeIntervalSince1970,
            "sameSizeRepaired": String(decoding: sameSizeRepairedBytes, as: UTF8.self),
            "truncatedRepaired": String(decoding: truncatedRepairedBytes, as: UTF8.self),
            "extraFileRemoved": !FileManager.default.fileExists(atPath: staleURL.path),
            "updated": String(decoding: updatedBytes, as: UTF8.self),
            "updatedOutputChanged": updated.outputURL != cold.outputURL,
            "markerExists": FileManager.default.fileExists(atPath: markerURL.path),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


def make_package(entries: list[tuple[str, bytes]]) -> bytes:
    magic = b"PKGV001"
    table = bytearray(struct.pack("<I", len(magic)) + magic)
    table.extend(struct.pack("<I", len(entries)))
    offset = 0
    payload = bytearray()
    for path, value in entries:
        encoded_path = path.encode("utf-8")
        table.extend(struct.pack("<I", len(encoded_path)))
        table.extend(encoded_path)
        table.extend(struct.pack("<II", offset, len(value)))
        payload.extend(value)
        offset += len(value)
    return bytes(table + payload)


class ScenePkgCacheExtractorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-pkg-cache-"
        )
        root = Path(cls.temporary_directory.name)
        cls.home = root / "home"
        cls.project = root / "project"
        cls.home.mkdir()
        cls.project.mkdir()
        cls.package = cls.project / "scene.pkg"
        original_package = make_package(
            [
                ("scene.json", b"{}"),
                ("materials/shared.tex", b"package-texture"),
                ("ignored.bin", b"ignored"),
            ]
        )
        replacement_package = make_package(
            [
                ("scene.json", b"{}"),
                ("materials/shared.tex", b"updated-texture"),
                ("ignored.bin", b"ignored"),
            ]
        )
        if len(original_package) != len(replacement_package):
            raise AssertionError("replacement fixture must preserve package size")
        cls.package.write_bytes(original_package)
        cls.replacement_package = cls.project / "replacement.pkg"
        cls.replacement_package.write_bytes(replacement_package)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "scene-pkg-cache-harness"
        subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-o", str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        completed = subprocess.run(
            [
                str(cls.binary),
                str(cls.package),
                str(cls.project),
                str(cls.replacement_package),
            ],
            env={"HOME": str(cls.home), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"},
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_extracts_only_supported_paths_and_writes_completion_marker(self) -> None:
        self.assertEqual(
            self.result["paths"], ["materials/shared.tex", "scene.json"]
        )
        self.assertTrue(self.result["markerExists"])

    def test_valid_warm_cache_is_reused_without_rewriting_entries(self) -> None:
        self.assertEqual(self.result["warmPaths"], self.result["paths"])
        self.assertEqual(self.result["warmPreserved"], "package-texture")
        self.assertTrue(self.result["warmModificationPreserved"])

    def test_same_size_and_truncated_cache_damage_are_rebuilt(self) -> None:
        self.assertEqual(self.result["sameSizeRepairedPaths"], self.result["paths"])
        self.assertEqual(self.result["truncatedRepairedPaths"], self.result["paths"])
        self.assertEqual(self.result["sameSizeRepaired"], "package-texture")
        self.assertEqual(self.result["truncatedRepaired"], "package-texture")

    def test_extra_cache_files_are_removed(self) -> None:
        self.assertTrue(self.result["extraFileRemoved"])

    def test_same_metadata_package_replacement_uses_new_content(self) -> None:
        self.assertEqual(self.result["updated"], "updated-texture")
        self.assertTrue(self.result["updatedOutputChanged"])


if __name__ == "__main__":
    unittest.main()
