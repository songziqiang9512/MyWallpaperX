"""Real Graph/Root key semantics in isolated en/tr/az processes, without GPU.

The optional task-private before qualification substitutes the actual retained
pre-D3 Graph source and compiles ACTUAL_BEFORE_GRAPH. Normal regression runs use
only current product sources and do not require a retained task directory.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_particle_assets as assets


HARNESS = r'''
import Foundation

@main enum Harness {
    static func directoryURL(_ resource: SceneResourceIndex.Resource) -> URL {
#if ACTUAL_BEFORE_GRAPH
        resource.url
#else
        resource.directoryURL!
#endif
    }
    // ACTUAL_BEFORE_PROJECTION
    static func main() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MWX_PARTICLE_CASEFOLD_ROOT"]!)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var rows: [[String: Any]] = []
        func run(_ name: String, file: String, request: String,
                 texture: String? = nil, lowerTexture: String? = nil,
                 peerFile: String? = nil, selectedIsBad: Bool = false) throws {
            let directory = root.appendingPathComponent(name)
            let primary = directory.appendingPathComponent("primary")
            let lower = directory.appendingPathComponent("lower")
            for folder in [primary, lower] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            let definitionURL = primary.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: definitionURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let material = "materials/\(name).json"
            try JSONSerialization.data(withJSONObject: ["material": material,
                "emitter": [["name": "boxRandom"]]]).write(to: definitionURL)
            let peerMaterial = "materials/\(name)-peer.json"
            if let peerFile {
                let peer = primary.appendingPathComponent(peerFile)
                try FileManager.default.createDirectory(at: peer.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: ["material": peerMaterial,
                    "emitter": [["name": "boxRandom"]]]).write(to: peer)
            }
            for (folder, path) in [(primary, texture), (lower, lowerTexture)] {
                guard let path else { continue }
                let url = folder.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try Data([1]).write(to: url)
            }
            let selected = SceneResourceIndexBuilder().build(rootURL: primary).resources.first {
                SceneParticleAssetGraphLoader.normalizedPath($0.relativePath)
                    == SceneParticleAssetGraphLoader.normalizedPath(request)
            }
            if selectedIsBad, let selected { try Data("{bad".utf8).write(to: directoryURL(selected)) }
            let expectedMaterial = selected == nil || selectedIsBad ? ""
                : (selected?.relativePath == file ? material : peerMaterial)
            let view = SceneResourceView(projectRootURL: lower, packageRootURL: primary,
                                         stockAssetsRootURL: nil)
            let pass = SceneParticleMaterialPass(materialPath: material, shaderPath: "genericparticle",
                texturePaths: ["I"], blending: "translucent")
            let graph: SceneParticleAssetGraph
#if ACTUAL_BEFORE_GRAPH
            graph = SceneParticleAssetGraphLoader(resourceView: view, stockTextureBundleURL: nil)
                .load(rootPaths: [request], materialPasses: [pass], cacheDirectory: primary)
#else
            graph = try SceneParticleAssetGraphLoader(resourceView: view, stockTextureBundleURL: nil)
                .load(rootPaths: [request], materialPasses: [pass])
#endif
            let asset = graph.assetsByPath[SceneParticleAssetGraphLoader.normalizedPath(request)]
            let texturePath: String
            if case let .file(input)? = asset?.textureSource {
                let directoryPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
                #if ACTUAL_BEFORE_GRAPH
                let selectedURL = input
#else
                let selectedURL = URL(fileURLWithPath: input.diagnosticPath)
#endif
                texturePath = String(selectedURL.resolvingSymlinksInPath().standardizedFileURL.path
                    .dropFirst(directoryPath.count + 1))
            } else { texturePath = "" }
            rows.append(["name": name, "material": asset?.definition.materialPath ?? "",
                "texture": texturePath, "expectedMaterial": expectedMaterial,
                "selectedRelativePath": selected?.relativePath ?? "",
                "invalid": graph.diagnostics.contains { $0.kind == .invalidDefinition },
                "missing": graph.diagnostics.contains { $0.kind == .missingDefinition }])
        }
        try run("ascii-lower", file: "particles/I.JSON", request: "particles/i.json", texture: "materials/I.TEX")
        try run("ascii-variants", file: "particles/I.JSON", request: " ./Particles\\I.JSON ")
        try run("dotted-lower", file: "particles/İ.JSON", request: "particles/i\u{307}.json")
        try run("dotted-upper", file: "particles/İ.JSON", request: "particles/İ.JSON")
        try run("dotless-neighbor", file: "particles/I.JSON", request: "particles/ı.json")
        try run("dotted-neighbor", file: "particles/İ.JSON", request: "particles/i.json")
        try run("outer-whitespace", file: " particles/I.JSON ", request: "particles/i.json", texture: " materials/I.TEX ")
        try run("global-localized", file: "particles/ordinary.json", request: "particles/ordinary.json",
                lowerTexture: "materials/I.TEX")
        try run("posix-backslash", file: "particles\\I.JSON", request: "particles/i.json")
        try run("posix-backslash-peer", file: "particles\\I.JSON", request: "particles/i.json",
                peerFile: "particles/I.JSON")
        try run("posix-selected-bad", file: "particles\\I.JSON", request: "particles/i.json",
                peerFile: "particles/I.JSON", selectedIsBad: true)
        let first = SceneResourceIndex.Resource(relativePath: "./particles/I.JSON",
            url: root.appendingPathComponent("first.json"), kind: .particle, fileSize: 1)
        let second = SceneResourceIndex.Resource(relativePath: "particles/i.json ",
            url: root.appendingPathComponent("second.json"), kind: .particle, fileSize: 1)
        let plainFirst = SceneResourceIndex.Resource(relativePath: "particles/I.JSON",
            url: directoryURL(first), kind: .particle, fileSize: 1)
        let plainSecond = SceneResourceIndex.Resource(relativePath: "particles/i.json",
            url: directoryURL(second), kind: .particle, fileSize: 1)
        var rootChecks: [String: Bool] = [:]
        for (label, resources, expected) in [("forward", [first, second], "first.json"),
                                             ("reverse", [second, first], "second.json")] {
            let index = SceneResourceIndex(rootURL: root, resources: resources)
#if ACTUAL_BEFORE_GRAPH
            let selected = beforeInvariantURL(index, relativePath: "particles/i.json")
#else
            let namespace = SceneResourceView.Root(source: .package, url: root, index: index)
            let selected = namespace.invariantResource(relativePath: "particles/i.json")?.directoryURL
#endif
            rootChecks["collision-" + label + "-keeps-index-first"] = selected?.lastPathComponent == expected
        }
        let plainIndex = SceneResourceIndex(rootURL: root, resources: [plainFirst, plainSecond])
        let namespace = SceneResourceView.Root(source: .package, url: root, index: plainIndex)
        let localizedExpected = Locale.current.identifier.hasPrefix("tr") || Locale.current.identifier.hasPrefix("az")
            ? "second.json" : "first.json"
        rootChecks["default-localized-lookup-keeps-original-rule"] = namespace.resource(
            relativePath: "particles/i.json").map(directoryURL)?.lastPathComponent == localizedExpected
        let result: [String: Any] = ["locale": Locale.current.identifier, "rows": rows,
                                    "rootChecks": rootChecks, "gpuDeviceCreated": false]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneParticleCasefoldTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if not swiftc:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-particle-casefold-")
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Casefold.swift"
        harness.write_text(HARNESS)
        cls.binary = directory / "casefold"
        result = subprocess.run([swiftc, *(str(path) for path in assets.SWIFT_SOURCES), str(harness),
            "-module-cache-path", str(directory / "module-cache"), "-o", str(cls.binary)],
            capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr)

    def test_graph_invariant_keys_and_localized_fallback_remain_separate(self) -> None:
        for locale in ["en_US", "tr_TR", "az_AZ"]:
            with self.subTest(locale=locale), tempfile.TemporaryDirectory(prefix="mwx-particle-locale-home-") as home:
                environment = dict(os.environ, HOME=home, CFFIXED_USER_HOME=home,
                    MWX_PARTICLE_CASEFOLD_ROOT=str(Path(home) / "input"))
                result = subprocess.run([str(self.binary), "-AppleLocale", locale],
                    env=environment, capture_output=True, text=True, check=True)
                report = json.loads(result.stdout)
                self.assertEqual(report["locale"], locale)
                self.assertFalse(report["gpuDeviceCreated"])
                rows = {row["name"]: row for row in report["rows"]}
                for name in ["ascii-lower", "ascii-variants", "dotted-lower", "dotted-upper", "outer-whitespace", "global-localized"]:
                    self.assertEqual(rows[name]["material"], "materials/" + name + ".json")
                    self.assertFalse(rows[name]["missing"])
                for name in ["posix-backslash", "posix-backslash-peer"]:
                    self.assertEqual(rows[name]["material"], rows[name]["expectedMaterial"])
                    self.assertFalse(rows[name]["missing"])
                self.assertEqual(rows["posix-backslash"]["selectedRelativePath"], "particles\\I.JSON")
                self.assertEqual(rows["posix-selected-bad"]["material"], "")
                self.assertTrue(rows["posix-selected-bad"]["invalid"])
                self.assertFalse(rows["posix-selected-bad"]["missing"])
                for name in ["dotless-neighbor", "dotted-neighbor"]:
                    self.assertEqual(rows[name]["material"], "")
                    self.assertTrue(rows[name]["missing"])
                self.assertEqual(rows["ascii-lower"]["texture"], "primary/materials/I.TEX")
                self.assertEqual(rows["outer-whitespace"]["texture"], "primary/ materials/I.TEX ")
                self.assertEqual(rows["global-localized"]["texture"], "lower/materials/I.TEX" if locale == "en_US" else "")
                for name, passed in report["rootChecks"].items():
                    with self.subTest(check=name):
                        self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
