#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from scene_real_test_fixtures import sample_cache_root


ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
REAL_SAMPLE_CACHE = sample_cache_root("3767460992")
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContractLoader.swift",
    SOURCE_ROOT / "RenderGraph/SceneProceduralNoiseShaderProfile.swift",
]

HARNESS = r'''
import Foundation

@main
enum Harness {
    static let identity = "workshop/2906937488/effects/procedural_noise"

    static func mutate(
        _ contracts: [SceneShaderContract], mode: String
    ) -> [SceneShaderContract] {
        guard let contract = contracts.first else { return contracts }
        var stages = contract.stages
        if ["source", "raw", "path"].contains(mode) {
            let stage = stages[0]
            stages[0] = .init(
                kind: stage.kind,
                relativePath: mode == "path" ? "shaders/other.vert" : stage.relativePath,
                source: mode == "source" ? stage.source + "x" : stage.source,
                rawSHA256: mode == "raw" ? String(repeating: "0", count: 64) : stage.rawSHA256,
                includes: stage.includes,
                annotations: stage.annotations,
                declarations: stage.declarations
            )
        }
        var diagnostics = contract.diagnostics
        if mode == "diagnostic" {
            diagnostics.append(.init(
                code: .malformedAnnotation,
                message: "fixture",
                relativePath: nil,
                line: nil
            ))
        }
        let changed = SceneShaderContract(
            identity: mode == "identity" ? "workshop/other" : contract.identity,
            sourceKind: mode == "sourceKind" ? .hostBuiltin : contract.sourceKind,
            stages: stages,
            diagnostics: diagnostics,
            canonicalSHA256: mode == "canonical"
                ? String(repeating: "0", count: 64)
                : contract.canonicalSHA256
        )
        return mode == "duplicate" ? [contract, contract] : [changed]
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let contracts = SceneShaderContractLoader().load(
            shaderReferences: [identity], rootURL: root
        )
        let mutationModes = [
            "source", "raw", "path", "identity", "sourceKind",
            "diagnostic", "canonical", "duplicate",
        ]
        let result: [String: Bool] = [
            "accepted": SceneProceduralNoiseShaderProfile.matches(contracts),
            "mutationsRejected": mutationModes.allSatisfy {
                !SceneProceduralNoiseShaderProfile.matches(mutate(contracts, mode: $0))
            },
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneProceduralNoiseProfileTests(unittest.TestCase):
    def test_real_shader_is_admitted_and_mutations_fail_closed(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        shader = (
            REAL_SAMPLE_CACHE
            / "shaders/workshop/2906937488/effects/procedural_noise.frag"
        )
        if not shader.is_file():
            self.skipTest(f"real Procedural Noise fixture unavailable: {shader}")
        with tempfile.TemporaryDirectory(prefix="scene-procedural-noise-profile-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "scene-procedural-noise-profile"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "swiftc", "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness), "-o", str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary), str(REAL_SAMPLE_CACHE)],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        self.assertTrue(all(result.values()), result)


if __name__ == "__main__":
    unittest.main()
