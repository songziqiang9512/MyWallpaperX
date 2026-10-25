"""Actual SourceFacts MDL preparation, current FD reads and complete CPU parsing.

A test-only counter is inserted in a copy of the real public readParts entry;
its parsing body is unchanged. No Metal or product instrumentation is created.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_prepared_script_resource_catalog import swift_declaration
from script.tests.test_scene_static_model_reader import SWIFT_SOURCES, build_model


REPO = Path(__file__).resolve().parents[2]
SCENE = REPO / "MyWallpaperX/Core/SteamWorkshopScene"
FACTS = SCENE / "Runtime/Frame/SceneRuntimeSourceFacts.swift"
READER = SCENE / "Format/SceneMdlStaticModelReader.swift"
SOURCES = [*SWIFT_SOURCES, SCENE / "Format/SceneMdlPuppetAnimationReader.swift",
           SCENE / "Format/SceneMdlPuppetAnimation.swift", SCENE / "Format/SceneMdlPuppetAttachmentReader.swift",
           SCENE / "Resources/Assets/SceneResourceIndex.swift",
           SCENE / "Resources/Assets/SceneResourceView.swift",
           SCENE / "../SteamWorkshopStorage/ScenePlaybackSource.swift", SCENE / "Format/ScenePkgReader.swift",
           SCENE / "Resources/Assets/SceneResourceIdentity.swift", SCENE / "Resources/Assets/SceneResourceView+Backing.swift"]

CARRIER = r'''
import Foundation
struct SceneDocument {
    struct Object { let staticModelPath: String?; var puppetAnimationLayers: [Int] = [] }
    let objects: [Object]
}
struct SceneRenderDescriptor {
    struct ModelMaterialLink { let modelPath: String; let materialPath: String? }
}
enum ModelParseProbe { static var calls = 0 }
extension SceneMdlStaticModel {
// PRODUCT_PREPARED_SOURCE
}
struct SourceFactsPreparationProbe {
// PRODUCT_PREPARATION
    static func prepare(_ paths: [String], _ view: SceneResourceView,
                        checkCancellation: (() throws -> Void)? = nil) throws
        -> (links: [SceneRenderDescriptor.ModelMaterialLink], sources: [String: SceneMdlStaticModel.PreparedSource]) {
        var sources: [String: SceneMdlStaticModel.PreparedSource] = [:]
        let links = try Self().directStaticModelMaterialLinks(
            document: .init(objects: paths.map { .init(staticModelPath: $0) }),
            resourceView: view, checkCancellation: checkCancellation,
            preparedStaticModel: { sources[$0] = $1 })
        return (links, sources)
    }
}
'''

HARNESS = r'''
import Foundation
import Darwin

@main enum ModelReadProbe {
    enum Stop: Error { case cancelled }
    static func openedOffset(_ target: URL) -> Int? {
        let expected = target.resolvingSymlinksInPath().standardizedFileURL.path
        for descriptor: Int32 in 0..<512 {
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if fcntl(descriptor, F_GETPATH, &path) == 0,
               URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().standardizedFileURL.path == expected {
                return Int(lseek(descriptor, 0, SEEK_CUR))
            }
        }
        return nil
    }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let package = root.appendingPathComponent("package")
        let loose = root.appendingPathComponent("loose")
        let view = SceneResourceView(projectRootURL: loose, packageRootURL: package,
                                     stockAssetsRootURL: nil)
        let target = package.appendingPathComponent("models/selected.mdl")
        let original = try Data(contentsOf: target)
        let other = try Data(contentsOf: loose.appendingPathComponent("models/selected.mdl"))
        var checks: [String: Bool] = [:]
        var opens = 0, wasOpen = false
        ModelParseProbe.calls = 0
        let captured = try SourceFactsPreparationProbe.prepare(
            ["MODELS/SELECTED.MDL", "models/selected.mdl"], view,
            checkCancellation: {
                let open = openedOffset(target) != nil
                if open && !wasOpen { opens += 1 }
                wasOpen = open
            })
        let prepared = captured.sources["models/selected.mdl"]!
        checks["oneReadAndOneCompleteParseForRepeatedInstances"] =
            opens == 1 && ModelParseProbe.calls == 1 && captured.sources.count == 1
        checks["globalChosenRootAndAuthoredCaseRemain"] =
            captured.links.compactMap(\.materialPath) == ["materials/first.json"]
                && prepared.parts.first?.materialPath == "materials/first.json"
        checks["staticSourceDoesNotPrepareAnimation"] = prepared.animations == nil
        try other.write(to: target, options: .atomic)
        checks["linksAndGeometryConsumeSameCompletedSnapshot"] =
            captured.links.first?.materialPath == prepared.parts.first?.materialPath
                && prepared.parts.first?.materialPath == "materials/first.json"
        let current = try SourceFactsPreparationProbe.prepare(["models/selected.mdl"], view)
        checks["newPreparationAcceptsCurrentMutableDirectoryBytes"] =
            current.sources["models/selected.mdl"]?.parts.first?.materialPath == "materials/other.json"
        try original.write(to: target, options: .atomic)
        var changed = false
        do {
            _ = try SourceFactsPreparationProbe.prepare(["models/selected.mdl"], view,
                checkCancellation: {
                    if !changed, openedOffset(target) != nil {
                        try other.write(to: target, options: .atomic)
                        changed = true
                    }
                })
            checks["sourceChangeEscapesReadLeaf"] = false
        } catch SceneResourceView.ReadError.sourceChanged {
            checks["sourceChangeEscapesReadLeaf"] = changed
        }
        try original.write(to: target, options: .atomic)
        var cancelled = false
        do {
            _ = try SourceFactsPreparationProbe.prepare(["models/selected.mdl"], view,
                checkCancellation: {
                    if openedOffset(target) != nil { cancelled = true; throw Stop.cancelled }
                })
            checks["nonReadCancellationEscapesOpenedRead"] = false
        } catch Stop.cancelled {
            checks["nonReadCancellationEscapesOpenedRead"] = cancelled
        }
        let missing = try SourceFactsPreparationProbe.prepare(["models/missing.mdl"], view)
        checks["ordinaryMissingModelIsLocal"] = missing.sources.isEmpty && missing.links.isEmpty
        let mixed = try SourceFactsPreparationProbe.prepare(["models/bad-tail.mdl", "models/selected.mdl"], view)
        checks["badModelIsLocalAndDoesNotPoisonHealthyPeer"] =
            mixed.sources.count == 1 && mixed.links.compactMap(\.materialPath) == ["materials/first.json"]
        let large = package.appendingPathComponent("models/large.mdl")
        var greatestOffset = 0
        let rejected = try SourceFactsPreparationProbe.prepare(["models/large.mdl"], view,
            checkCancellation: { greatestOffset = max(greatestOffset, openedOffset(large) ?? 0) })
        checks["readLeafAddsNoShaderSizedCap"] = greatestOffset == 600_000 && rejected.sources.isEmpty
        try FileManager.default.removeItem(at: target)
        let removed = try SourceFactsPreparationProbe.prepare(["models/selected.mdl"], view)
        checks["selectedMissingHandleDoesNotRetryLowerRoot"] = removed.sources.isEmpty
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneModelResourceReadTests(unittest.TestCase):
    def test_actual_read_leaf_and_complete_cpu_reader(self):
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-model-resource-reads-") as temporary:
            work = Path(temporary)
            for name in ["package", "loose"]:
                (work / name / "models").mkdir(parents=True)
            first = build_model(material=b"materials/first.json")
            (work / "package/models/selected.mdl").write_bytes(first)
            (work / "loose/models/selected.mdl").write_bytes(build_model(material=b"materials/other.json"))
            (work / "package/models/bad-tail.mdl").write_bytes(first[:-1] + b"\x01")
            (work / "package/models/large.mdl").write_bytes(b"x" * 600_000)
            source_facts = FACTS.read_text()
            method = swift_declaration(source_facts, "    private func directStaticModelMaterialLinks(")
            prepared_type = swift_declaration(source_facts, "    struct PreparedSource {")
            carrier = work / "ProductionModelPreparation.swift"
            carrier.write_text(CARRIER.replace("// PRODUCT_PREPARATION", method)
                .replace("// PRODUCT_PREPARED_SOURCE", prepared_type))
            counted_reader = work / "SceneMdlStaticModelReader.swift"
            counted_reader.write_text(READER.read_text().replace(
                "static func readParts(data rawData: Data) throws -> [SceneMdlStaticModel] {\n        try rawData.withUnsafeBytes",
                "static func readParts(data rawData: Data) throws -> [SceneMdlStaticModel] {\n        ModelParseProbe.calls += 1\n        return try rawData.withUnsafeBytes", 1))
            harness, binary = work / "Harness.swift", work / "probe"
            harness.write_text(HARNESS)
            inputs = [*SOURCES, FACTS, Path(__file__), carrier, counted_reader, harness]
            identities = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
            compile_sources = [counted_reader if path == READER else path for path in SOURCES]
            built = subprocess.run(["swiftc", *map(str, compile_sources), str(carrier), str(harness),
                "-module-cache-path", str(work / "module-cache"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            ran = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=30)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            for path, identity in identities.items():
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), identity,
                                 f"input modified during CPU gate: {path}")
            result = json.loads(ran.stdout)
            self.assertIn("oneReadAndOneCompleteParseForRepeatedInstances", result)
            for name, passed in result.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
