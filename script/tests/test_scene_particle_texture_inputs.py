"""Real particle selector precedence and selected Root inputs, without Metal work."""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_particle_assets as assets

HARNESS = r'''
import Foundation

@main enum Harness {
    static func main() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let primary = base.appendingPathComponent("primary")
        let lower = base.appendingPathComponent("lower")
        let global = base.appendingPathComponent("global")
        let custom = base.appendingPathComponent("custom")
        func write(_ path: String, _ bytes: Data, _ root: URL) throws {
            let target = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try bytes.write(to: target)
        }
        for (folder, path, byte) in [(primary, "materials/probe.tex", 11),
            (lower, "materials/probe", 22), (global, "materials/global.tex", 33),
            (custom, "assets/materials/particle/drop.tex", 44),
            (custom, "assets/materials/custom/noise.tex", 55),
            (custom, "assets/custom/noise.tex", 56)] {
            try write(path, Data([UInt8(byte)]), folder)
        }
        let names = ["probe", "global", "particle/drop", "particle/halo", "../escape"]
        for (index, _) in names.enumerated() {
            try write("particles/p\(index).json", JSONSerialization.data(withJSONObject: [
                "material": "materials/p\(index).json", "emitter": [["name": "boxRandom"]]
            ]), primary)
        }
        let view = SceneResourceView(projectRootURL: lower, packageRootURL: primary,
                                     stockAssetsRootURL: global)
        let graph = try SceneParticleAssetGraphLoader(resourceView: view, stockTextureBundleURL: custom)
            .load(rootPaths: names.indices.map { "particles/p\($0).json" },
                  materialPasses: names.enumerated().map { index, name in
                SceneParticleMaterialPass(materialPath: "materials/p\(index).json",
                    shaderPath: "genericparticle", texturePaths: [name], blending: "translucent")
            })
        func firstByte(_ source: SceneParticleTextureSource?) throws -> Int {
            guard case let .file(input)? = source else { return -1 }
#if D4_ACTUAL_BEFORE
            return Int(try Data(contentsOf: input).first ?? 0)
#else
            guard case .resource = input else { return -2 }
            return Int(try input.readSnapshot().data.first ?? 0)
#endif
        }
        var checks: [String: Bool] = [:]
        checks["primaryAllCandidatesBeforeLowerExact"] = try firstByte(graph.assetsByPath["particles/p0.json"]?.textureSource) == 11
        checks["globalFallback"] = try firstByte(graph.assetsByPath["particles/p1.json"]?.textureSource) == 33
        checks["customStockPrecedesBuiltin"] = try firstByte(graph.assetsByPath["particles/p2.json"]?.textureSource) == 44
        checks["builtinLast"] = graph.assetsByPath["particles/p3.json"]?.textureSource == SceneParticleTextureSource.builtIn(.halo)
        checks["escapingNameMissing"] = graph.assetsByPath["particles/p4.json"]?.textureSource == nil
        let resolver = SceneStockTextureResolver(bundleRoot: custom)!
#if D4_ACTUAL_BEFORE
        let stock = resolver.textureURL(for: " custom\\noise ")!
        checks["stockLiteralCandidateOrder"] = try Data(contentsOf: stock) == Data([55])
        checks["stockInvalidNamesRejected"] = ["../escape", "/escape", "custom//noise"].allSatisfy { resolver.textureURL(for: $0) == nil }
#else
        let stock = try resolver.textureInput(for: " custom\\noise ")!
        checks["stockLiteralCandidateOrder"] = try stock.readSnapshot().data == Data([55])
        checks["stockInvalidNamesRejected"] = try ["../escape", "/escape", "custom//noise"].allSatisfy { try resolver.textureInput(for: $0) == nil }
        // The resolver keeps its captured Root when its bundle path is redirected.
        let moved = base.appendingPathComponent("old-custom")
        try FileManager.default.moveItem(at: custom, to: moved)
        try FileManager.default.createSymbolicLink(at: custom, withDestinationURL: primary)
        do {
            _ = try resolver.textureInput(for: "particle/drop")
            checks["stockRootChangeNotMissingOrBuiltin"] = false
        } catch SceneResourceView.ReadError.sourceChanged { checks["stockRootChangeNotMissingOrBuiltin"] = true }
#endif
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneParticleTextureInputTests(unittest.TestCase):
    def test_real_selector_keeps_precedence_and_root_errors(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-particle-texture-input-") as temporary:
            root = Path(temporary)
            harness = root / "Main.swift"
            harness.write_text(HARNESS)
            binary = root / "selector"
            result = subprocess.run([shutil.which("swiftc") or "swiftc",
                *map(str, assets.SWIFT_SOURCES), str(harness), "-o", str(binary),
                "-module-cache-path", str(root / "module-cache")], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(all(checks.values()), checks)
