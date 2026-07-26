#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
ARCHIVE_PATH = REPOSITORY_ROOT / "MyWallpaperX/Resources/Videos.zip"
SOURCE_DIRECTORY = REPOSITORY_ROOT / "MyWallpaperX/Resources/Videos"
SWIFT_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Modules/VideoLibrary/Core/BundledVideoLibrary.swift"
)

HARNESS_SOURCE = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let firstArchive = URL(fileURLWithPath: CommandLine.arguments[1])
        let secondArchive = URL(fileURLWithPath: CommandLine.arguments[2])
        let destination = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let expected = ["Video1.mp4", "Video2.mp4"]

        let first = try BundledVideoLibrary.prepare(
            archiveURL: firstArchive,
            destinationDirectoryURL: destination,
            expectedFileNames: expected
        )
        let firstInode = inode(first)
        let firstContent = try String(
            contentsOf: first.appendingPathComponent("Video1.mp4"),
            encoding: .utf8
        )

        let reused = try BundledVideoLibrary.prepare(
            archiveURL: firstArchive,
            destinationDirectoryURL: destination,
            expectedFileNames: expected
        )
        let reusedInode = inode(reused)

        let updated = try BundledVideoLibrary.prepare(
            archiveURL: secondArchive,
            destinationDirectoryURL: destination,
            expectedFileNames: expected
        )
        let updatedContent = try String(
            contentsOf: updated.appendingPathComponent("Video1.mp4"),
            encoding: .utf8
        )
        let files = try FileManager.default.contentsOfDirectory(
            at: updated,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).map(\.lastPathComponent).sorted()

        let payload: [String: Any] = [
            "firstContent": firstContent,
            "reusedDirectory": firstInode == reusedInode,
            "updatedContent": updatedContent,
            "files": files
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func inode(_ url: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
    }
}
'''


class BundledVideoLibraryTests(unittest.TestCase):
    def test_repository_contains_only_the_fixed_video_archive(self) -> None:
        self.assertTrue(ARCHIVE_PATH.is_file())
        self.assertFalse(SOURCE_DIRECTORY.exists())
        with zipfile.ZipFile(ARCHIVE_PATH) as archive:
            self.assertEqual(
                archive.namelist(),
                [f"Video{index}.mp4" for index in range(1, 6)],
            )
            self.assertIsNone(archive.testzip())
            for name in archive.namelist():
                with archive.open(name) as video:
                    self.assertEqual(video.read(8)[4:8], b"ftyp")

    def test_prepare_extracts_reuses_and_refreshes_the_archive(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-bundled-videos-") as directory:
            root = Path(directory)
            first_archive = root / "first.zip"
            second_archive = root / "second.zip"
            self.write_fixture_archive(first_archive, "version-one")
            self.write_fixture_archive(second_archive, "version-two")
            harness = root / "Harness.swift"
            harness.write_text(HARNESS_SOURCE, encoding="utf-8")
            executable = root / "BundledVideoLibraryHarness"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "module-cache")
            subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    str(SWIFT_SOURCE),
                    str(harness),
                    "-o",
                    str(executable),
                ],
                check=True,
                cwd=REPOSITORY_ROOT,
                env=environment,
            )
            completed = subprocess.run(
                [
                    str(executable),
                    str(first_archive),
                    str(second_archive),
                    str(root / "extracted"),
                ],
                check=True,
                capture_output=True,
                text=True,
                env=environment,
            )
            result = json.loads(completed.stdout)
            self.assertEqual(result["firstContent"], "version-one")
            self.assertTrue(result["reusedDirectory"])
            self.assertEqual(result["updatedContent"], "version-two")
            self.assertEqual(result["files"], ["Video1.mp4", "Video2.mp4"])

    @staticmethod
    def write_fixture_archive(path: Path, video1_content: str) -> None:
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("Video1.mp4", video1_content)
            archive.writestr("Video2.mp4", "stable")


if __name__ == "__main__":
    unittest.main()
