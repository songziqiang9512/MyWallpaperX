"""Real package/SourceFacts failures preserve cancellation and current source boundaries.

Malformed/unavailable packages may use complete loose inputs, never stale output.
No extractor, report, injected package leaf, App or GPU path is involved.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest

from script.tests import test_scene_static_model_parts as parts
from script.tests.scene_pkg_fixture import make_package


MAIN = r'''
import Darwin
@main enum PackageFailureProbe {
    static let fm = FileManager.default
    static func isOpen(_ url: URL) -> Bool {
        let expected = url.resolvingSymlinksInPath().standardizedFileURL.path
        var current = stat()
        guard lstat(url.path, &current) == 0 else { return false }
        return (0..<512).contains { descriptor in
            var opened = stat()
            guard fstat(Int32(descriptor), &opened) == 0,
                  opened.st_dev == current.st_dev, opened.st_ino == current.st_ino else { return false }
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            return fcntl(Int32(descriptor), F_GETPATH, &path) == 0
                && URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().standardizedFileURL.path == expected
        }
    }
    static func sourceSelections(_ root: URL) throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let cases: [(String, SceneResourceView.Source?, Int?)] = [
            ("valid-main-unused-bad", .package, 701),
            ("bad-main-loose", .loose, 702),
            ("bad-main-directory-loose", .loose, 703),
            ("bad-main-no-loose", nil, nil),
            ("case-folded-peer", .package, 704),
            ("case-exact-peer", .package, 705),
            ("bad-first-alias", .package, 706),
            ("valid-range-bad-json", .package, nil)
        ]
        for (name, expectedSource, expectedID) in cases {
            let folder = root.appendingPathComponent(name)
            let facts = try SceneRuntimeSourceFactsBuilder().build(rootURL: folder)
            guard let project = facts.project else { fatalError("fixture project must parse: " + name) }
            let selected = try facts.resourceView.literalEntry(relativePath: project.entryPath)
            checks[name + "-selectsActualExpectedRoot"] = selected?.source == expectedSource
            checks[name + "-neverMountsStaleExtraction"] = facts.resourceView.roots.allSatisfy {
                $0.directoryURL?.lastPathComponent != ".scene-extracted"
            }
            if let selected {
                let expected = try Data(contentsOf: folder.appendingPathComponent("expected.bin"))
                checks[name + "-readsExpectedBytes"] = try selected.readBytes() == expected
                if name == "bad-first-alias" {
                    guard case let .package(identity) = try selected.currentIdentity() else { fatalError("expected package identity") }
                    checks["bad-first-alias-usesFirstSafeRawEntry"] = identity.rawEntryPath == "nested/scene.json"
                }
            }
            if let expectedID {
                checks[name + "-loadsActualSceneObjects"] = facts.sceneDocument?.objects.map(\.id) == [expectedID]
                    && facts.sceneDocumentLoadErrorDescription == nil && facts.renderDescriptor != nil
                _ = try SceneRuntimeModelBuilder().build(rootURL: folder)
                checks[name + "-modelBuildsFromCurrentSelectedSource"] = true
            } else {
                checks[name + "-doesNotSubstituteAnotherDocument"] = facts.sceneDocument == nil
                    && facts.sceneDocumentLoadErrorDescription != nil && facts.renderDescriptor == nil
                do {
                    _ = try SceneRuntimeModelBuilder().build(rootURL: folder)
                    checks[name + "-missingActualDocumentReallyFails"] = false
                } catch SceneRuntimeModelBuilder.BuildError.missingSceneDocument {
                    checks[name + "-missingActualDocumentReallyFails"] = true
                }
            }
        }
        return checks
    }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let package = root.appendingPathComponent("scene.pkg")
        let valid = try Data(contentsOf: root.appendingPathComponent("valid.pkg"))
        let looseScene = root.appendingPathComponent("scene.json")
        let looseBytes = try Data(contentsOf: looseScene)
        var checks: [String: Bool] = [:]
        let mounted = try SceneRuntimeSourceFactsBuilder().build(rootURL: root)
        checks["normalPackageUsesOneVirtualRoot"] = mounted.renderDescriptor != nil
            && mounted.resourceView.roots.filter { $0.source == .package }.count == 1
            && mounted.resourceView.roots.first?.directoryURL == nil
        for caller in ["facts", "model"] {
            for cancellation in [true, false] {
                try valid.write(to: package, options: .atomic)
                var rootsReady = false, reached = false
                let name = caller + (cancellation ? "-cancel" : "-sourceChanged")
                func check() throws {
                    guard !reached, isOpen(package), cancellation || rootsReady else { return }
                    reached = true
                    if cancellation { throw CancellationError() }
                    var changed = valid
                    changed[changed.count - 1] ^= 1
                    try changed.write(to: package)
                }
                do {
                    if caller == "facts" {
                        _ = try SceneRuntimeSourceFactsBuilder().build(rootURL: root,
                            checkCancellation: check, willReadResourceRoots: { _ in rootsReady = true })
                    } else {
                        // Mutate while the actual Reader FD is open. Keep the
                        // same file length so parser failure cannot hide revision change.
                        rootsReady = true
                        _ = try SceneRuntimeModelBuilder().build(rootURL: root, checkCancellation: check)
                    }
                    checks[name + "-escapesWithoutLooseFallback"] = false
                } catch is CancellationError {
                    checks[name + "-escapesWithoutLooseFallback"] = cancellation && reached
                } catch SceneResourceView.ReadError.sourceChanged {
                    checks[name + "-escapesWithoutLooseFallback"] = !cancellation && reached
                } catch ScenePkgReader.ReadError.sourceChanged {
                    checks[name + "-escapesWithoutLooseFallback"] = !cancellation && reached
                }
            }
        }
        try valid.write(to: package, options: .atomic)
        checks["hardFailureDoesNotPoisonNextRequest"] = try SceneRuntimeSourceFactsBuilder().build(rootURL: root).renderDescriptor != nil
        for kind in ["bad-range", "invalid-magic", "directory", "missing"] {
            try? fm.removeItem(at: package)
            if kind == "directory" { try fm.createDirectory(at: package, withIntermediateDirectories: true) }
            else if kind == "invalid-magic" { try Data("not PKGV".utf8).write(to: package) }
            else if kind == "bad-range" { try Data(contentsOf: root.appendingPathComponent("bad-range.pkg")).write(to: package) }
            let complete = try SceneRuntimeSourceFactsBuilder().build(rootURL: root)
            checks[kind + "-completeLooseStillPlays"] = try complete.sceneDocument != nil
                && complete.renderDescriptor != nil && complete.sceneDocumentLoadErrorDescription == nil
                && complete.resourceView.literalEntry(relativePath: "scene.json")?.source == .loose
                && complete.resourceView.literalEntry(relativePath: "scene.json")?.readBytes() == looseBytes
            try fm.removeItem(at: looseScene)
            let missing = try SceneRuntimeSourceFactsBuilder().build(rootURL: root)
            checks[kind + "-staleExtractionIsNeverMounted"] = try missing.sceneDocument == nil
                && missing.sceneDocumentLoadErrorDescription != nil
                && missing.resourceView.literalEntry(relativePath: "scene.json") == nil
                && missing.resourceView.roots.allSatisfy { $0.directoryURL?.lastPathComponent != ".scene-extracted" }
            do {
                _ = try SceneRuntimeModelBuilder().build(rootURL: root)
                checks[kind + "-incompleteLooseReallyFails"] = false
            } catch SceneRuntimeModelBuilder.BuildError.missingSceneDocument {
                checks[kind + "-incompleteLooseReallyFails"] = true
            }
            try looseBytes.write(to: looseScene)
        }
        checks.merge(try sourceSelections(root.appendingPathComponent("source-choices"))) { _, next in next }
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class ScenePackageFailurePropagationTests(unittest.TestCase):
    def test_actual_root_facts_and_model_preserve_hard_source_errors(self):
        if shutil.which("xcrun") is None:
            self.skipTest("Xcode tools unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-pkg-failure-") as temporary:
            work = Path(temporary)
            root = work / "fixture"
            entries, _ = parts.native_fixture(1)
            normal = make_package(list(entries.items()))
            entries["scene.pkg"] = normal
            entries["valid.pkg"] = normal
            entries["bad-range.pkg"] = make_package([("scene.json", b"{}")])[:-1]
            entries[".scene-extracted/scene.json"] = b'{"objects":[]}'
            for relative, data in entries.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            def scene(identifier):
                return json.dumps({"objects": [{"id": identifier, "name": "selected", "solid": True,
                                                "size": "32 32", "color": "1 0 0"}]}).encode()

            def package_with_ranges(package_entries, bad_positions=()):
                data = bytearray(make_package(package_entries))
                cursor = 4 + struct.unpack_from("<I", data, 0)[0] + 4
                for position, (path, _) in enumerate(package_entries):
                    length = struct.unpack_from("<I", data, cursor)[0]
                    cursor += 4 + length
                    if position in bad_positions:
                        struct.pack_into("<II", data, cursor, 0xFFFFFFFF, 1)
                    cursor += 8
                return bytes(data)

            source_cases = [
                ("valid-main-unused-bad", "scene.json", [("scene.json", scene(701)), ("unused/bad.tex", b"unused")],
                 [1], None, scene(701)),
                ("bad-main-loose", "scene.json", [("scene.json", b"not readable")], [0], scene(702), scene(702)),
                ("bad-main-directory-loose", "scene.json",
                 [("scene.json", b"not readable"), ("scene.json/child.bin", b"valid child")],
                 [0], scene(703), scene(703)),
                ("bad-main-no-loose", "scene.json", [("scene.json", b"not readable")], [0], None, None),
                ("case-folded-peer", "scene.json", [("scene.json", b"bad metadata"), ("SCENE.JSON", scene(704))],
                 [0], scene(709), scene(704)),
                ("case-exact-peer", "scene.json", [("SCENE.JSON", scene(708)), ("scene.json", scene(705)),
                                                   ("unused/bad.tex", b"unused")], [2], scene(709), scene(705)),
                ("bad-first-alias", "nested/scene.json",
                 [("nested\\scene.json", b"bad metadata"), ("nested/scene.json", scene(706)),
                  ("nested\\scene.json", scene(707))], [0], None, scene(706)),
                ("valid-range-bad-json", "scene.json", [("scene.json", b"{broken"), ("scene.json", scene(707))],
                 [], scene(709), b"{broken"),
            ]
            for name, entry, package_entries, bad_positions, loose_bytes, expected in source_cases:
                folder = root / "source-choices" / name
                folder.mkdir(parents=True)
                (folder / "project.json").write_text(json.dumps({"type": "scene", "file": entry}))
                (folder / "scene.pkg").write_bytes(package_with_ranges(package_entries, bad_positions))
                stale = folder / ".scene-extracted" / entry
                stale.parent.mkdir(parents=True)
                stale.write_bytes(scene(999))
                if loose_bytes is not None:
                    destination = folder / entry
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(loose_bytes)
                if expected is not None:
                    (folder / "expected.bin").write_bytes(expected)
            sources = list(dict.fromkeys([*parts.builder.SWIFT_SOURCES, *parts.reader.SWIFT_SOURCES]))
            harness, binary = work / "Harness.swift", work / "probe"
            harness.write_text(parts.builder_support().split("@main enum PartsDependencies", 1)[0] + MAIN)
            identities = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources, harness]}
            built = subprocess.run(["xcrun", "swiftc", "-swift-version", "5", *map(str, sources),
                str(harness), "-module-cache-path", str(work / "module-cache"),
                "-framework", "Metal", "-o", str(binary)], capture_output=True, text=True, timeout=240)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            ran = subprocess.run([str(binary), str(root)], capture_output=True, text=True, timeout=30)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            for path, identity in identities.items():
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), identity)
            result = json.loads(ran.stdout)
            self.assertTrue(result)
            for name, passed in result.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True)


if __name__ == "__main__":
    unittest.main()
