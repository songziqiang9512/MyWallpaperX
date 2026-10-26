#!/usr/bin/env python3

from __future__ import annotations

import json
import hashlib
import os
import plistlib
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
MIGRATION_SOURCE = SWIFT_SOURCE.with_name("WallpaperManager+BundledVideos.swift")
MODEL_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Models/VideoWallpaper.swift"

HARNESS_SOURCE = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let firstArchive = URL(fileURLWithPath: CommandLine.arguments[1])
        let secondArchive = URL(fileURLWithPath: CommandLine.arguments[2])
        let destination = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let oldExpected = (1...5).map { "Video\($0).mp4" }
        let expected = BundledVideoLibrary.expectedFileNames

        let first = try BundledVideoLibrary.prepare(
            archiveURL: firstArchive,
            destinationDirectoryURL: destination,
            expectedFileNames: oldExpected
        )
        let firstInode = inode(first)
        let firstContent = try String(
            contentsOf: first.appendingPathComponent("Video2.mp4"),
            encoding: .utf8
        )

        let reused = try BundledVideoLibrary.prepare(
            archiveURL: firstArchive,
            destinationDirectoryURL: destination,
            expectedFileNames: oldExpected
        )
        let reusedInode = inode(reused)

        let updated = try BundledVideoLibrary.prepare(
            archiveURL: secondArchive,
            destinationDirectoryURL: destination,
            expectedFileNames: expected
        )
        let updatedContent = try String(
            contentsOf: updated.appendingPathComponent("Video2.mp4"),
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

MIGRATION_HARNESS = r'''
import Foundation

@MainActor final class WallpaperManager {
    var persistRequests = 0
    func scheduleWallpapersAutoPersist() { persistRequests += 1 }
}

@main enum MigrationHarness {
    @MainActor static func main() throws {
        let mode = CommandLine.arguments[1]
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let archive = URL(fileURLWithPath: CommandLine.arguments[3])
        let manager = WallpaperManager(), fm = FileManager.default
        let home = root.appendingPathComponent("home", isDirectory: true)
        precondition(fm.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path == home.resolvingSymlinksInPath().path)
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        precondition(support.resolvingSymlinksInPath().path.hasPrefix(home.resolvingSymlinksInPath().path + "/"))
        let destination = support.appendingPathComponent(Bundle.main.bundleIdentifier!)
            .appendingPathComponent("BundledVideos", isDirectory: true)
        let resources = root.appendingPathComponent("Existing.app/Contents/Resources", isDirectory: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        let existing = resources.appendingPathComponent("Video2.mp4")
        try Data("existing-owned".utf8).write(to: existing)
        let linked = root.appendingPathComponent("linked-original.mov")
        try Data("linked-owned".utf8).write(to: linked)
        let symlink = resources.appendingPathComponent("Video3.mp4")
        try fm.createSymbolicLink(at: symlink, withDestinationURL: linked)
        let ordinary = ["movies/ordinary.mp4", "movies/Video2.mp4",
            "Old.app/Contents/Resources/Renamed.mp4", "Old.app/Contents/Resources/Video2.MP4",
            "Old.app/Contents/Resource/Video2.mp4", "Old.app/Contents/Resources2/Video2.mp4",
            "Old.appx/Contents/Resources/Video2.mp4"].map { root.appendingPathComponent($0).path }
        let untouched = (ordinary + [existing.path, symlink.path]).map { record($0) }
        for value in untouched {
            precondition(BundledVideoLibrary.migratedURL(forPersistedPath: value.path) == nil)
            precondition(manager.migratedBundledVideoWallpaper(value) == value)
        }
        precondition(manager.migratedBundledVideoIndex(untouched) == untouched && manager.persistRequests == 0)
        precondition(!fm.fileExists(atPath: destination.path))
        let retired = root.appendingPathComponent("Retired.app/Contents/Resources", isDirectory: true)
        try fm.createDirectory(at: retired, withIntermediateDirectories: true)
        let missing = retired.appendingPathComponent("Video2.mp4").path
        if mode == "missing-archive" {
            precondition(BundledVideoLibrary.migratedURL(forPersistedPath: missing) == nil)
            precondition(manager.migratedBundledVideoIndex([record(missing)]) == [record(missing)])
            precondition(manager.persistRequests == 0 && !fm.fileExists(atPath: destination.path))
        } else {
            // Lazy prepare must not have cached a failure during the probes above.
            try fm.copyItem(at: archive, to: Bundle.main.resourceURL!.appendingPathComponent("Videos.zip"))
            let migrated = BundledVideoLibrary.migratedURL(forPersistedPath: missing)!
            precondition(migrated.resolvingSymlinksInPath().path == destination.appendingPathComponent("Video2.mp4").resolvingSymlinksInPath().path)
            let migratedContent = try String(contentsOf: migrated, encoding: .utf8)
            precondition(migratedContent == "migrated-owned")
            let equivalent = retired.path + "//./Video2.mp4"
            precondition(BundledVideoLibrary.migratedURL(forPersistedPath: equivalent) == migrated)
            let broken = retired.appendingPathComponent("Video3.mp4")
            try fm.createSymbolicLink(at: broken, withDestinationURL: root.appendingPathComponent("absent.mov"))
            let brokenMigration = BundledVideoLibrary.migratedURL(forPersistedPath: broken.path)!
            precondition(brokenMigration.lastPathComponent == "Video3.mp4")
            let brokenContent = try String(contentsOf: brokenMigration, encoding: .utf8)
            precondition(brokenContent == "migrated-owned")
            let input = untouched + [record(missing), record(equivalent, dated: false), record(broken.path)]
            let expected = untouched + [record(migrated.path), record(migrated.path, dated: false), record(brokenMigration.path)]
            precondition(manager.migratedBundledVideoIndex(input) == expected && manager.persistRequests == 1)
            precondition(manager.migratedBundledVideoIndex(expected) == expected && manager.persistRequests == 1)
        }
        let existingContent = try String(contentsOf: existing, encoding: .utf8)
        let linkedContent = try String(contentsOf: symlink, encoding: .utf8)
        precondition(existingContent == "existing-owned" && linkedContent == "linked-owned")
        print("{\"mode\":\"\(mode)\",\"untouched\":\(untouched.count),\"persistRequests\":\(manager.persistRequests),\"passed\":true}")
    }

    static func record(_ path: String, dated: Bool = true) -> VideoWallpaper {
        VideoWallpaper(id: "owned-id", title: "Owned title", path: path,
            thumbnailPath: "thumb", staticFramePath: "frame", isFavorite: true,
            lastUsed: Date(timeIntervalSince1970: 123), tags: ["owned", "renamed"],
            fileSize: 456, duration: 78, resolution: "640x480",
            firstIndexedAt: dated ? Date(timeIntervalSince1970: 42) : nil)
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
                ["Video2.mp4", "Video3.mp4"],
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
            self.write_fixture_archive(first_archive, "version-one", range(1, 6))
            self.write_fixture_archive(second_archive, "version-two", (2, 3))
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
            self.assertEqual(result["files"], ["Video2.mp4", "Video3.mp4"])

    def test_real_migration_waits_for_missing_legacy_source_and_preserves_metadata(self) -> None:
        evidence = os.environ.get("MWX_BUNDLED_VIDEO_EVIDENCE")
        if evidence:
            Path(evidence).mkdir(parents=True, exist_ok=True)
        root = Path(tempfile.mkdtemp(prefix="mwx-bundled-migration-", dir=evidence))
        if not evidence:
            self.addCleanup(shutil.rmtree, root)
        template = root / "Template.app/Contents"
        (template / "MacOS").mkdir(parents=True)
        (template / "Resources").mkdir()
        (template / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.mywallpaperx.tests.bundled-migration",
            "CFBundlePackageType": "APPL", "CFBundleExecutable": "MigrationHarness",
            "CFBundleVersion": "1", "CFBundleName": "Owned migration fixture",
        }))
        harness = root / "MigrationHarness.swift"
        harness.write_text(MIGRATION_HARNESS)
        inputs = [Path(__file__), SWIFT_SOURCE, MIGRATION_SOURCE, MODEL_SOURCE, harness]
        before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(root / "clang-cache"))
        command = ["xcrun", "swiftc", "-parse-as-library", "-O", str(SWIFT_SOURCE),
            str(MIGRATION_SOURCE), str(MODEL_SOURCE), str(harness),
            "-module-cache-path", str(root / "modules"), "-o", str(template / "MacOS/MigrationHarness")]
        built = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=120)
        (root / "compile.json").write_text(json.dumps({"command": command, "returncode": built.returncode,
            "stdout": built.stdout, "stderr": built.stderr, "inputSHA256": before}, indent=2))
        self.assertEqual(built.returncode, 0, built.stderr)
        archive = root / "owned.zip"
        self.write_fixture_archive(archive, "migrated-owned", (2, 3))
        for mode in ("archive", "missing-archive"):
            with self.subTest(mode=mode):
                app = root / (mode + ".app")
                shutil.copytree(template.parent, app)
                work = root / mode
                (work / "home").mkdir(parents=True)
                env = dict(environment, HOME=str(work / "home"), CFFIXED_USER_HOME=str(work / "home"))
                ran = subprocess.run([str(app / "Contents/MacOS/MigrationHarness"), mode, str(work), str(archive)],
                    env=env, capture_output=True, text=True, timeout=30)
                (root / (mode + ".json")).write_text(json.dumps({"returncode": ran.returncode,
                    "stdout": ran.stdout, "stderr": ran.stderr}, indent=2))
                self.assertEqual(ran.returncode, 0, ran.stderr)
                report = json.loads(ran.stdout)
                self.assertTrue(report["passed"])
                self.assertEqual(report["untouched"], 9)
                self.assertEqual(report["persistRequests"], 1 if mode == "archive" else 0)
        self.assertEqual({str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}, before)

    @staticmethod
    def write_fixture_archive(path: Path, content: str, indices) -> None:
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for index in indices:
                archive.writestr(f"Video{index}.mp4", content)


if __name__ == "__main__":
    unittest.main()
