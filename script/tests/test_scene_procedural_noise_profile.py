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
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderSourceGraph.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderContract.swift",
    SOURCE_ROOT / "Resources/SceneShaderSourceGraphBuilder.swift",
    SOURCE_ROOT / "Resources/SceneShaderSourceResolver.swift",
    SOURCE_ROOT / "Resources/SceneResourceView.swift",
    SOURCE_ROOT / "Resources/SceneResourceIndex.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderContractLoader.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderContractLoader+SourceGraph.swift",
    SOURCE_ROOT / "RenderGraph/SceneProceduralNoiseShaderProfile.swift",
]

HARNESS = r'''
import Foundation

@main
enum Harness {
    static let identities = [
        "workshop/2906937488/effects/procedural_noise",
        "workshop/2924967132/effects/procedural_noise",
    ]

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
        let mutationModes = [
            "source", "raw", "path", "identity", "sourceKind",
            "diagnostic", "canonical", "duplicate",
        ]
        let profiles = identities.map { identity -> [String: Bool] in
            let contracts = SceneShaderContractLoader().load(
                shaderReferences: [identity], rootURL: root
            )
            return [
                "accepted": SceneProceduralNoiseShaderProfile.matches(contracts),
                "mutationsRejected": mutationModes.allSatisfy {
                    !SceneProceduralNoiseShaderProfile.matches(
                        mutate(contracts, mode: $0)
                    )
                },
            ]
        }
        let expectedDefinitionPaths = [
            "effects/workshop/2906937488/procedural_noise/effect.json",
            "effects/workshop/2924967132/procedural_noise/effect.json",
        ]
        let result: [String: Any] = [
            "profiles": profiles,
            "definitionPathsAccepted": zip(
                SceneProceduralNoiseShaderProfile.Profile.allCases,
                expectedDefinitionPaths
            ).allSatisfy { $0.definitionPath == $1 },
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
        legacy_cache = sample_cache_root("3768903841")
        required = [
            (
                REAL_SAMPLE_CACHE
                / "shaders/workshop/2906937488/effects/procedural_noise.frag"
            ),
            (
                legacy_cache
                / "shaders/workshop/2924967132/effects/procedural_noise.frag"
            ),
        ]
        missing = [path for path in required if not path.is_file()]
        if missing:
            self.skipTest(f"real Procedural Noise fixture unavailable: {missing}")
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
            fixture_root = root / "fixture"
            fixture_root.mkdir()
            for cache in (REAL_SAMPLE_CACHE, legacy_cache):
                shutil.copytree(cache / "shaders", fixture_root / "shaders", dirs_exist_ok=True)
            completed = subprocess.run(
                [str(binary), str(fixture_root)],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        self.assertEqual(len(result["profiles"]), 2, result)
        self.assertTrue(
            all(all(item.values()) for item in result["profiles"]),
            result,
        )
        self.assertTrue(result["definitionPathsAccepted"], result)


if __name__ == "__main__":
    unittest.main()
