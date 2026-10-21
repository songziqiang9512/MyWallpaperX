#!/usr/bin/env python3

from __future__ import annotations

import json
import fcntl
import hashlib
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import unicodedata
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT))
from script.tests.test_scene_static_model_document import SWIFT_SOURCES as DOCUMENT_SWIFT_SOURCES

SWIFT_SOURCES = [
    SCENE_ROOT / "Format/ScenePkgReader.swift",
    SCENE_ROOT / "Format/ScenePkgCacheExtractor.swift",
    *(path for path in DOCUMENT_SWIFT_SOURCES if path.name != "SceneUserPropertyResolutionStub.swift"),
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Shared/WorkshopPropertyDisplayResolver.swift",
    SCENE_ROOT / "Format/SceneProject.swift",
    SCENE_ROOT / "Format/ScenePkgExtractionReport.swift",
    SCENE_ROOT / "Resources/Assets/SceneResourceIndex.swift",
    SCENE_ROOT / "Systems/Properties/SceneUserProperty.swift",
    SCENE_ROOT / "Systems/Properties/SceneUserPropertyDefinitionParser.swift",
    SCENE_ROOT / "Systems/Properties/SceneUserPropertyBindings.swift",
    SCENE_ROOT / "Systems/Properties/SceneUserPropertyResolver.swift",
    SCENE_ROOT / "Systems/Text/SceneTextDescriptor.swift",
    SCENE_ROOT / "Systems/Text/SceneTextGeometry.swift",
]

HARNESS = r'''
import CryptoKit
import Darwin
import Foundation

@main
enum Harness {
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("rejected: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run() throws {
        if CommandLine.arguments[1] == "inspect" {
            let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            let urls = FileManager.default.enumerator(at: root,
                includingPropertiesForKeys: [.isRegularFileKey])!.allObjects as! [URL]
            let output: [String: Any] = ["rootURL": root.path,
                "canonicalRootURL": root.resolvingSymlinksInPath().path,
                "canonicalPath": try root.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath as Any,
                "enumeratedURLs": urls.map(\.path)]
            print(String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self))
            return
        }
        if CommandLine.arguments[1] == "document" {
            let package = URL(fileURLWithPath: CommandLine.arguments[2])
            let project = try SceneProjectLoader().load(from: package.deletingLastPathComponent())
            let result = try ScenePkgCacheExtractor().extract(
                packageURL: package, projectRootURL: project.rootURL)
            let report = ScenePkgExtractionReport(packageURL: package, outputURL: result.outputURL,
                status: .extracted, discoveredPaths: result.extractedPaths, packageIndex: result.index)
            let document = try SceneDocumentLoader().load(project: project, packageReport: report)
            let output: [String: Any] = ["outputURL": result.outputURL.path,
                "sourceURL": document.sourceURL.path, "paths": result.extractedPaths,
                "version": document.declaredVersion.integerValue as Any,
                "caseSensitive": try result.outputURL.resourceValues(
                    forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames as Any]
            print(String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self))
            return
        }
        if CommandLine.arguments[1] == "one" || CommandLine.arguments[1] == "parallel" {
            let package = URL(fileURLWithPath: CommandLine.arguments[2])
            let results = Results()
            let count = CommandLine.arguments[1] == "parallel" ? 4 : 1
            DispatchQueue.concurrentPerform(iterations: count) { _ in
                do {
                    let value = try ScenePkgCacheExtractor().extract(
                        packageURL: package, projectRootURL: package.deletingLastPathComponent())
                    results.lock.lock()
                    results.values.append(value)
                    results.lock.unlock()
                } catch {
                    results.lock.lock()
                    results.errors.append(String(describing: error))
                    results.lock.unlock()
                }
            }
            guard results.errors.isEmpty, let value = results.values.first else {
                throw NSError(domain: results.errors.joined(separator: ";"), code: 1)
            }
            var hashes: [String: String] = [:]
            for path in value.extractedPaths {
                hashes[path] = SHA256.hash(data: try Data(contentsOf:
                    value.outputURL.appendingPathComponent(path)))
                    .map { String(format: "%02x", $0) }.joined()
            }
            let output: [String: Any] = ["outputURL": value.outputURL.path,
                "paths": value.extractedPaths, "hashes": hashes,
                "completed": results.values.count,
                "sameOutput": results.values.allSatisfy { $0.outputURL == value.outputURL }]
            print(String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self))
            return
        }
        if CommandLine.arguments[1] == "index" {
            _ = try ScenePkgReader().readIndex(packageURL:
                URL(fileURLWithPath: CommandLine.arguments[2]))
            return
        }
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

private final class Results: @unchecked Sendable {
    let lock = NSLock()
    var values: [ScenePkgCacheExtractionResult] = []
    var errors: [String] = []
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
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        root = Path(cls.temporary_directory.name).resolve()
        cls.root = root
        cls.home = root / "home"
        cls.project = root / "project"
        cls.home.mkdir()
        cls.project.mkdir()
        cls.package = cls.project / "scene.pkg"
        original_package = make_package(
            [
                ("scene.json", b"{}"),
                ("materials/shared.tex", b"package-texture"),
                ("sounds/loop.flac", b"audio-payload"),
                ("sounds/unsafe.exe", b"not-audio"),
                ("ignored.bin", b"ignored"),
            ]
        )
        replacement_package = make_package(
            [
                ("scene.json", b"{}"),
                ("materials/shared.tex", b"updated-texture"),
                ("sounds/loop.flac", b"audio-payload"),
                ("sounds/unsafe.exe", b"not-audio"),
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
        compiled = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-o", str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if compiled.returncode:
            raise AssertionError(compiled.stderr)
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
        cls.volumes = {}
        for filesystem, case_sensitive in [("Case-sensitive APFS", True), ("APFS", False)]:
            volume_name = "APFSX" if case_sensitive else "APFS"
            image = root / (volume_name + ".sparseimage")
            mount = root / volume_name
            mount.mkdir()
            subprocess.run(["hdiutil", "create", "-size", "128m", "-type", "SPARSE",
                            "-fs", filesystem, "-volname", "MWX-PKG-" + volume_name,
                            "-nospotlight", str(image)], check=True, capture_output=True,
                           text=True, timeout=60)
            attached = subprocess.run(["hdiutil", "attach", "-nobrowse", "-mountpoint",
                                       str(mount), "-plist", str(image)], check=True,
                                      capture_output=True, timeout=60)
            entities = plistlib.loads(attached.stdout)["system-entities"]
            device = entities[0]["dev-entry"]
            cls.addClassCleanup(subprocess.run, ["hdiutil", "detach", device],
                                check=True, capture_output=True, timeout=60)
            # Verify the actual mounted filesystem independently of the extractor.
            probe = mount / "CaseProbe"
            probe.write_bytes(b"probe")
            if (mount / "caseprobe").exists() == case_sensitive:
                raise AssertionError(f"unexpected case semantics on {filesystem}")
            probe.unlink()
            cls.volumes[case_sensitive] = mount

    @classmethod
    def tearDownClass(cls) -> None:
        # Class cleanups detach our mounted images before deleting the temporary root.
        pass

    def test_extracts_only_supported_paths_and_writes_completion_marker(self) -> None:
        self.assertEqual(
            self.result["paths"],
            ["materials/shared.tex", "scene.json", "sounds/loop.flac"],
        )
        self.assertTrue(self.result["markerExists"])

    def test_valid_warm_cache_is_reused_without_rewriting_entries(self) -> None:
        self.assertEqual(self.result["warmPaths"], self.result["paths"])
        self.assertEqual(self.result["warmPreserved"], "package-texture")
        self.assertTrue(self.result["warmModificationPreserved"])

    def test_alias_home_warm_cache_keeps_physical_files_and_rejects_damage(self) -> None:
        entries = [("scene.json", b'{"version":3}'), ("textures/a.tex", b"first")]
        package, env = self.isolated_package("root-alias", entries, self.volumes[False])
        (package.parent / "project.json").write_text(
            json.dumps({"type": "scene", "file": "scene.json"}), encoding="utf-8")
        # Foundation home URLs use /var, while mounted-volume enumeration uses
        # the equivalent /private/var path. Exercise that real root alias.
        home = str(package.parent / "home")
        self.assertTrue(home.startswith("/private/var/"), home)
        env.update(HOME=home.removeprefix("/private"), CFFIXED_USER_HOME=home.removeprefix("/private"))
        cold = self.extract(package, env, "document")
        cache = Path(cold["outputURL"])
        inspection = self.extract(cache, env, "inspect")
        canonical = Path(inspection["canonicalPath"])
        self.assertNotEqual(inspection["rootURL"], str(canonical), inspection)
        self.assertEqual(cache.stat().st_ino, canonical.stat().st_ino)
        self.assertTrue(inspection["enumeratedURLs"])
        self.assertTrue(all(path.startswith(str(canonical) + "/")
                            for path in inspection["enumeratedURLs"]), inspection)
        with self.subTest(foundation=inspection):
            self.assert_warm_document(package, env, "scene.json", 3, False)
        texture = cache / "textures/a.tex"
        for damaged in [b"other", b"shorter"]:
            texture.write_bytes(damaged)
            self.assertEqual(self.extract(package, env, "document")["version"], 3)
            self.assertEqual(texture.read_bytes(), b"first")
            self.assert_warm_document(package, env, "scene.json", 3, False)
        package.write_bytes(make_package([("scene.json", b'{"version":7}'),
                                          ("textures/a.tex", b"other")]))
        updated = self.assert_warm_document(package, env, "scene.json", 7, False)
        self.assertNotEqual(updated["outputURL"], cold["outputURL"])
        self.assertEqual((Path(updated["outputURL"]) / "textures/a.tex").read_bytes(), b"other")

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

    def isolated_package(self, name: str, entries: list[tuple[str, bytes]],
                         volume: Path | None = None) -> tuple[Path, dict[str, str]]:
        root = (volume or self.root) / name
        root.mkdir()
        package = root / "scene.pkg"
        package.write_bytes(make_package(entries))
        env = os.environ.copy()
        env.update(HOME=str(root / "home"), CFFIXED_USER_HOME=str(root / "home"))
        return package, env

    def extract(self, package: Path, env: dict[str, str], mode: str = "one") -> dict:
        result = subprocess.run([str(self.binary), mode, str(package)], env=env,
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_renamed_reordered_and_zero_length_entries_keep_exact_bytes(self) -> None:
        entries = [("textures/重命名.tex", b"payload"), ("scene.json", b"{}"),
                   ("images/empty.png", b""), ("sounds/renamed.mp3", b"audio"),
                   ("textures/../escape.tex", b"bad"), ("misc/ignored.bin", b"ignored")]
        package, env = self.isolated_package("variants", entries)
        first = self.extract(package, env)
        expected = {p: hashlib.sha256(b).hexdigest() for p, b in entries[:4]}
        self.assertEqual(first["hashes"], expected)
        package.write_bytes(make_package(list(reversed(entries))))
        self.assertEqual(self.extract(package, env)["hashes"], expected)

    def test_packaged_ogg_names_and_neighbors_keep_exact_resource_bytes(self) -> None:
        # Extraction copies opaque bytes; these fixtures make no codec or
        # native playback claim and must not depend on AVFoundation support.
        supported = [
            ("scene.json", b"{}"),
            ("sounds/自然02.ogg", b"OggS-chinese-resource"),
            ("sounds/ambience/renamed-track.OGG", b"OggS-renamed-resource"),
            ("sounds\\alternate\\timbre.OgG", b"OggS-slash-resource"),
            ("sounds/kept.flac", b"flac-payload"),
            ("sounds/kept.mp3", b"mp3-payload"),
            ("sounds/kept.wav", b"wav-payload"),
        ]
        rejected = [
            ("sounds/not-audio.exe", b"executable"),
            ("sounds/pretend.ogg.exe", b"wrong-final-extension"),
            ("sounds/nearby.ogga", b"wrong-extension"),
            ("audio/outside-sound-root.ogg", b"wrong-root"),
            ("sounds/../escape.ogg", b"unsafe-path"),
        ]
        entries = supported + rejected
        package, env = self.isolated_package("ogg-resource-variants", entries)
        expected = {path.replace("\\", "/"): hashlib.sha256(value).hexdigest()
                    for path, value in supported}
        for ordered in (entries, list(reversed(entries))):
            package.write_bytes(make_package(ordered))
            result = self.extract(package, env)
            self.assertEqual(result["hashes"], expected)
            self.assertEqual(set(result["paths"]), set(expected))
            cache = Path(result["outputURL"])
            self.assertEqual({str(p.relative_to(cache)) for p in cache.rglob("*") if p.is_file()},
                             set(expected) | {".mwx-scene-pkg-cache-v1.json"})

    def test_old_cache_without_ogg_rebuilds_then_reuses_complete_manifest(self) -> None:
        legacy = [("scene.json", b"{}"), ("materials/retained.tex", b"texture"),
                  ("sounds/retained.flac", b"flac")]
        added = [("sounds/自然02.ogg", b"OggS-first"),
                 ("sounds/renamed/ambient.OGG", b"OggS-second")]
        package, env = self.isolated_package("ogg-old-completion-marker", legacy + added + [
            ("sounds/ignored.ogg.exe", b"not-audio"), ("audio/ignored.ogg", b"wrong-root")])
        first = self.extract(package, env)
        cache = Path(first["outputURL"])
        marker = cache / ".mwx-scene-pkg-cache-v1.json"
        legacy_paths = {path for path, _ in legacy}
        # Preserve the real marker's authored-path ordering so the legacy
        # cache is not rejected for an unrelated marker ordering difference.
        legacy_entries = [entry for entry in json.loads(marker.read_text())["entries"]
                          if entry["relativePath"] in legacy_paths]
        self.assertEqual({entry["relativePath"]: (entry["size"], entry["contentSHA256"])
                          for entry in legacy_entries},
                         {path: (len(value), hashlib.sha256(value).hexdigest())
                          for path, value in legacy})
        # Model a valid cache produced by the former extraction admission for
        # this exact package: only OGG files/manifest entries are absent. Do
        # not corrupt bytes, change package identity, bump a cache version or
        # remove its completion marker to force the repair by another cause.
        for path, _ in added:
            cached = cache / path
            if cached.exists():
                cached.unlink()
        legacy_marker = {"formatVersion": 1,
                         "packageSHA256": hashlib.sha256(package.read_bytes()).hexdigest(),
                         "entries": legacy_entries}
        marker.write_text(json.dumps(legacy_marker))
        self.assertEqual({str(p.relative_to(cache)) for p in cache.rglob("*") if p.is_file()},
                         legacy_paths | {marker.name})
        for path, value in legacy:
            self.assertEqual((cache / path).read_bytes(), value)
        repaired = self.extract(package, env)
        self.assertEqual(repaired["outputURL"], first["outputURL"])
        expected = {path: hashlib.sha256(value).hexdigest() for path, value in legacy + added}
        self.assertEqual(repaired["hashes"], expected)
        complete_marker = json.loads(marker.read_text())
        self.assertEqual(complete_marker["packageSHA256"], legacy_marker["packageSHA256"])
        self.assertEqual({entry["relativePath"]: (entry["size"], entry["contentSHA256"])
                          for entry in complete_marker["entries"]},
                         {path: (len(value), expected[path]) for path, value in legacy + added})
        files = [path for path in cache.rglob("*") if path.is_file()]
        self.assertEqual({str(path.relative_to(cache)) for path in files}, set(expected) | {marker.name})
        timestamp = 1_234_000_000_000
        for path in files:
            os.utime(path, ns=(timestamp, timestamp))
        before = {str(path.relative_to(cache)): (path.read_bytes(), path.stat().st_mtime_ns)
                  for path in files}
        self.assertEqual(self.extract(package, env), repaired)
        self.assertEqual({str(path.relative_to(cache)): (path.read_bytes(), path.stat().st_mtime_ns)
                          for path in cache.rglob("*") if path.is_file()}, before)

    def test_alias_collisions_and_reserved_marker_are_rejected(self) -> None:
        for name, paths in [("duplicate", ["textures/a.tex", "textures/a.tex"]),
                            ("slash", ["textures/a.tex", "textures\\a.tex"]),
                            ("case", ["textures/a.tex", "textures/A.tex"]),
                            ("unicode", ["textures/é.tex", "textures/e\u0301.tex"]),
                            ("marker", [".mwx-scene-pkg-cache-v1.json"])]:
            package, env = self.isolated_package(name, [(p, str(i).encode()) for i, p in enumerate(paths)],
                                                 self.volumes[False])
            result = subprocess.run([str(self.binary), "one", str(package)], env=env,
                                    capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 1, name)

    def test_identical_destination_aliases_reuse_one_resource(self) -> None:
        package, env = self.isolated_package("identical", [
            ("textures/é.tex", b"payload"), ("textures/é.tex", b"payload"),
            ("textures/E\u0301.tex", b"payload"), ("textures\\é.tex", b"payload")],
            self.volumes[False])
        result = self.extract(package, env)
        self.assertEqual(result["paths"], ["textures/é.tex"])
        self.assertEqual(result["hashes"], {"textures/é.tex": hashlib.sha256(b"payload").hexdigest()})
        self.assertEqual(self.extract(package, env)["hashes"], result["hashes"])

    def document_package(self, name: str, entries: list[tuple[str, bytes]],
                         entry_path: str, case_sensitive: bool,
                         loose: bool = False) -> tuple[Path, dict[str, str]]:
        package, env = self.isolated_package(name, entries, self.volumes[case_sensitive])
        (package.parent / "project.json").write_text(
            json.dumps({"type": "scene", "file": entry_path}), encoding="utf-8")
        if loose:
            (package.parent / entry_path).write_bytes(b'{"version":99}')
        return package, env

    def assert_warm_document(self, package: Path, env: dict[str, str],
                             entry_path: str, version: int, case_sensitive: bool) -> dict:
        cold = self.extract(package, env, "document")
        cache = Path(cold["outputURL"])
        self.assertEqual(unicodedata.normalize("NFC", cold["sourceURL"]),
                         unicodedata.normalize("NFC", str(cache / entry_path)))
        self.assertEqual(cold["version"], version)
        self.assertEqual(cold["caseSensitive"], case_sensitive)
        files = [path for path in cache.rglob("*") if path.is_file()]
        timestamp = 1_234_000_000_000
        for path in files:
            os.utime(path, ns=(timestamp, timestamp))
        before = {str(path.relative_to(cache)): (path.read_bytes(), path.stat().st_mtime_ns)
                  for path in files}
        self.assertEqual(self.extract(package, env, "document"), cold)
        after = {str(path.relative_to(cache)): (path.read_bytes(), path.stat().st_mtime_ns)
                 for path in cache.rglob("*") if path.is_file()}
        self.assertEqual(after, before)
        self.assertIn(".mwx-scene-pkg-cache-v1.json", before)
        return cold

    def test_case_sensitive_authored_entry_aliases_load_without_loose_fallback(self) -> None:
        for variant, paths in enumerate([("Scene.json", "scene.json"),
                                         ("ENTRÉE.json", "entrée.json")]):
            for same_bytes in [True, False]:
                entries = [(paths[0], b'{"version":3}'),
                           (paths[1], b'{"version":3}' if same_bytes else b'{"version":7}')]
                for reverse in [False, True]:
                    for entry_path in paths:
                        with self.subTest(paths=paths, same_bytes=same_bytes,
                                          reverse=reverse, entry_path=entry_path):
                            name = f"document-sensitive-{variant}-{same_bytes}-{reverse}-{entry_path}"
                            ordered = list(reversed(entries)) if reverse else entries
                            package, env = self.document_package(name, ordered, entry_path, True,
                                                                 loose=reverse)
                            version = 7 if entry_path == paths[1] and not same_bytes else 3
                            result = self.assert_warm_document(package, env, entry_path, version, True)
                            self.assertEqual(set(result["paths"]), set(paths))
                            for path, value in entries:
                                self.assertEqual((Path(result["outputURL"]) / path).read_bytes(), value)

    def test_case_insensitive_entry_aliases_reuse_or_reject_by_contents(self) -> None:
        for variant, paths in enumerate([("Scene.json", "scene.json"),
                                         ("RENOMMÉ.json", "renommé.json")]):
            for reverse in [False, True]:
                entries = [(path, b'{"version":3}') for path in paths]
                if reverse:
                    entries.reverse()
                package, env = self.document_package(f"document-insensitive-{variant}-{reverse}",
                                                     entries, paths[1], False, loose=True)
                result = self.assert_warm_document(package, env, paths[1], 3, False)
                self.assertEqual(result["paths"], [entries[0][0]])
                entries[1] = (entries[1][0], b'{"version":7}')
                package, env = self.document_package(f"document-conflict-{variant}-{reverse}",
                                                     entries, paths[1], False)
                rejected = subprocess.run([str(self.binary), "document", str(package)], env=env,
                                          capture_output=True, text=True, timeout=20)
                self.assertEqual(rejected.returncode, 1)
                self.assertIn("ambiguousPath", rejected.stderr)

    def test_same_physical_aliases_remain_checked_on_both_volumes(self) -> None:
        for sensitive, volume in self.volumes.items():
            for variant, paths in enumerate([("textures/a.tex", "textures/a.tex"),
                                             ("textures/a.tex", "textures\\a.tex"),
                                             ("textures/é.tex", "textures/e\u0301.tex")]):
                package, env = self.isolated_package(f"physical-{variant}-same",
                    [(path, b"payload") for path in paths], volume)
                result = self.extract(package, env)
                self.assertEqual(result["paths"], [paths[0]])
                self.assertEqual(self.extract(package, env), result)
                package, env = self.isolated_package(f"physical-{variant}-conflict",
                    [(paths[0], b"first"), (paths[1], b"second")], volume)
                rejected = subprocess.run([str(self.binary), "one", str(package)], env=env,
                                          capture_output=True, text=True, timeout=20)
                self.assertEqual(rejected.returncode, 1, (sensitive, paths))
                self.assertIn("ambiguousPath", rejected.stderr)

    def test_adjacent_case_sensitive_paths_and_marker_name_are_distinct(self) -> None:
        entries = [("textures/a.tex", b"first"), ("textures/A.tex", b"second"),
                   (".MWX-SCENE-PKG-CACHE-V1.JSON", b'{"version":3}')]
        package, env = self.isolated_package("adjacent-sensitive", entries, self.volumes[True])
        result = self.extract(package, env)
        self.assertEqual(result["hashes"], {p: hashlib.sha256(b).hexdigest() for p, b in entries})
        self.assertEqual(self.extract(package, env), result)
        package, env = self.isolated_package("adjacent-insensitive", [entries[2]], self.volumes[False])
        rejected = subprocess.run([str(self.binary), "one", str(package)], env=env,
                                  capture_output=True, text=True, timeout=20)
        self.assertEqual(rejected.returncode, 1)
        self.assertIn("ambiguousPath", rejected.stderr)

    def test_same_key_threads_and_processes_publish_complete_resources(self) -> None:
        entries = [("textures/large.tex", b"data" * 2_000_000), ("scene.json", b"{}")]
        package, env = self.isolated_package("concurrent", entries)
        threads = self.extract(package, env, "parallel")
        self.assertEqual(threads["completed"], 4)
        self.assertTrue(threads["sameOutput"])
        processes = [subprocess.Popen([str(self.binary), "one", str(package)], env=env,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(4)]
        for process in processes:
            stdout, stderr = process.communicate(timeout=20)
            self.assertEqual(process.returncode, 0, stderr.decode())
            self.assertEqual(json.loads(stdout)["hashes"], threads["hashes"])
        self.assertEqual(threads["hashes"], {p: hashlib.sha256(b).hexdigest() for p, b in entries})

    def test_key_lock_blocks_same_package_but_not_other_packages_and_releases(self) -> None:
        package, env = self.isolated_package("lock", [("scene.json", b"{}")])
        self.extract(package, env)
        cache_root = Path(env["HOME"]) / "Library/Caches/MyWallpaperX/SteamWorkshopScene"
        lock_path = next(cache_root.glob("*.lock"))
        with lock_path.open("rb") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            waiting = subprocess.Popen([str(self.binary), "one", str(package)], env=env,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                time.sleep(.2)
                self.assertIsNone(waiting.poll())
                other = package.parent / "other.pkg"
                other.write_bytes(make_package([("scene.json", b'{"other":true}')]))
                self.assertEqual(self.extract(other, env)["completed"], 1)
            finally:
                fcntl.flock(lock, fcntl.LOCK_UN)
            _, stderr = waiting.communicate(timeout=10)
            self.assertEqual(waiting.returncode, 0, stderr.decode())
        lock_path.unlink()
        lock_path.symlink_to(package)
        result = subprocess.run([str(self.binary), "one", str(package)], env=env,
                                capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 1)

    def test_cache_root_and_child_symlinks_are_rebuilt_without_changing_targets(self) -> None:
        package, env = self.isolated_package("symlinks", [("textures/a.tex", b"source")])
        cache = Path(self.extract(package, env)["outputURL"])
        outside = package.parent / "outside"
        outside.mkdir()
        target = outside / "a.tex"
        target.write_bytes(b"outside")
        cached = cache / "textures/a.tex"
        cached.unlink()
        cached.symlink_to(target)
        self.extract(package, env)
        self.assertFalse(cached.is_symlink())
        self.assertEqual(target.read_bytes(), b"outside")
        shutil.rmtree(cache)
        cache.symlink_to(outside, target_is_directory=True)
        self.extract(package, env)
        self.assertFalse(cache.is_symlink())
        self.assertEqual(target.read_bytes(), b"outside")
        marker = cache / ".mwx-scene-pkg-cache-v1.json"
        marker.unlink()
        os.mkfifo(marker)
        self.extract(package, env)
        self.assertTrue(marker.is_file())

    def test_process_exit_releases_key_lock_for_retry(self) -> None:
        package, env = self.isolated_package("exit-lock", [("scene.json", b"{}")])
        self.extract(package, env)
        lock_path = next((Path(env["HOME"]) /
            "Library/Caches/MyWallpaperX/SteamWorkshopScene").glob("*.lock"))
        holder = subprocess.Popen(["/usr/bin/python3", "-c",
            "import fcntl,sys,time; f=open(sys.argv[1],'rb'); "
            "fcntl.flock(f,fcntl.LOCK_EX); print('locked',flush=True); time.sleep(10)",
            str(lock_path)], stdout=subprocess.PIPE, text=True)
        waiting = None
        try:
            self.assertEqual(holder.stdout.readline().strip(), "locked")
            waiting = subprocess.Popen([str(self.binary), "one", str(package)], env=env,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            time.sleep(.2)
            self.assertIsNone(waiting.poll())
            holder.terminate()
            holder.wait(timeout=5)
            _, stderr = waiting.communicate(timeout=10)
            self.assertEqual(waiting.returncode, 0, stderr.decode())
        finally:
            if holder.poll() is None:
                holder.kill()
                holder.wait(timeout=5)
            holder.stdout.close()
            if waiting is not None and waiting.poll() is None:
                waiting.kill()
                waiting.communicate(timeout=5)

    def test_impossible_entry_count_and_payload_overrun_are_rejected(self) -> None:
        for name, data in [("count", struct.pack("<I", 7) + b"PKGV001" + struct.pack("<I", 0xFFFFFFFF) + b"x"),
                           ("overrun", make_package([("scene.json", b"{}")])[:-1])]:
            package, env = self.isolated_package(name, [])
            package.write_bytes(data)
            result = subprocess.run([str(self.binary), "index", str(package)], env=env,
                                    capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 1)


if __name__ == "__main__":
    unittest.main()
