#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SOURCE_SET_SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SOURCE_SET_SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SOURCE_SET_SCRIPT_ROOT))

from scene_swift_source_sets import scene_swift_sources_by_basename


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES = scene_swift_sources_by_basename(
    "shader_contract_resource_resolution"
)
RUNTIME_INPUT_SOURCE = SCENE_ROOT / "Runtime/SceneRuntimeInput.swift"
RUNTIME_MODEL_SOURCE = SCENE_ROOT / "Runtime/SceneRuntimeModel.swift"
DIAGNOSTICS_SOURCE = SCENE_ROOT / "Runtime/SceneDiagnostics.swift"
HOST_SOURCE = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost.swift"
HOST_LAUNCH_SOURCE = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+Launch.swift"
DEBUG_RUNNER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/App/DebugScenePlaybackRunner.swift"
PLAYBACK_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Modules/SteamWorkshop/Scene/SteamWorkshopSceneService+ScenePlayback.swift"
)
ASSET_CATALOG_SOURCE = SCENE_ROOT / "Resources/SceneAssetCatalog.swift"
SHADER_CONTRACT_SOURCE = SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES[
    "SceneShaderContract.swift"
]
SHADER_LEGACY_ANNOTATION_SOURCE = SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES[
    "SceneShaderLegacyAnnotationJSON.swift"
]
SHADER_CONTRACT_LOADER_SOURCE = SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES[
    "SceneShaderContractLoader.swift"
]
SHADER_CONTRACT_GRAPH_LOADER_SOURCE = (
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES[
        "SceneShaderContractLoader+SourceGraph.swift"
    ]
)
SWIFT_SOURCES = [
    SCENE_ROOT / "Properties/SceneUserProperty.swift",
    SCENE_ROOT / "Properties/SceneUserPropertyBindings.swift",
    SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "Properties/ScenePuppetAnimationPropertyTarget.swift",
    SCENE_ROOT / "Properties/ScenePropertyBindingProgram.swift",
    SCENE_ROOT / "Properties/ScenePropertyBindingCompiler+TargetMapping.swift",
    SCENE_ROOT / "Properties/ScenePropertyBindingProgramValidator.swift",
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES["SceneJSONValue.swift"],
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES[
        "SceneShaderSourceGraph.swift"
    ],
    SHADER_LEGACY_ANNOTATION_SOURCE,
    SHADER_CONTRACT_SOURCE,
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES["SceneResourceIndex.swift"],
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES["SceneResourceView.swift"],
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES[
        "SceneShaderSourceResolver.swift"
    ],
    SHADER_CONTRACT_RESOURCE_RESOLUTION_SOURCES[
        "SceneShaderSourceGraphBuilder.swift"
    ],
    SHADER_CONTRACT_LOADER_SOURCE,
    SHADER_CONTRACT_GRAPH_LOADER_SOURCE,
    RUNTIME_INPUT_SOURCE,
]

HARNESS = r'''
import Foundation

struct SceneRenderDescriptor: Codable, Equatable {
    let entryPath: String
}

struct SceneAuthoredEffectRenderPlan: Codable, Equatable {
    let layerID: Int
}

enum SceneAuthoredEffectRenderPlanner {
    static func plans(for descriptor: SceneRenderDescriptor) -> [SceneAuthoredEffectRenderPlan] {
        [SceneAuthoredEffectRenderPlan(layerID: descriptor.entryPath.count)]
    }
}

@main
enum Harness {
    static func main() throws {
        let target = SceneDynamicTarget.layer(layerID: 42, field: .alpha)
        let path = SceneUserPropertyPath(components: [
            .key("objects"), .index(0), .key("alpha"),
        ])
        let program = ScenePropertyBindingProgram(
            definitions: [
                .init(target: target, valueType: .scalar, authoredValue: .scalar(0.25)),
            ],
            instructions: [
                .init(propertyKey: "opacity", path: path, target: target, valueType: .scalar),
            ]
        )
        let effectiveValues: [String: SceneUserPropertyValue] = [
            "label": .string("demo"),
            "opacity": .number(0.75),
            "visible": .bool(true),
        ]
        let shaderContracts = SceneShaderContractLoader().load(
            shaderReferences: ["genericimage2"],
            rootURL: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        )
        let input = SceneRuntimeInput(
            renderDescriptor: .init(entryPath: "scene.json"),
            propertyBindingProgram: program,
            effectivePropertyValues: effectiveValues,
            shaderContracts: shaderContracts
        )
        let payload: [String: Any] = [
            "entryPath": input.renderDescriptor.entryPath,
            "authoredPlanCount": input.authoredEffectRenderPlans.count,
            "programRetained": input.propertyBindingProgram == program,
            "valuesRetained": input.effectivePropertyValues == effectiveValues,
            "contractsRetained": input.shaderContracts == shaderContracts,
            "hostBuiltinContract": shaderContracts.count == 1
                && shaderContracts[0].sourceKind == .hostBuiltin
                && shaderContracts[0].stages.isEmpty
                && shaderContracts[0].diagnostics.isEmpty,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneRuntimeInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-runtime-input-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-runtime-input"
        compilation = subprocess.run(
            ["swiftc", *map(str, SWIFT_SOURCES), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary), str(directory)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_runtime_input_retains_complete_in_memory_contract(self) -> None:
        self.assertEqual(self.result["entryPath"], "scene.json")
        self.assertEqual(self.result["authoredPlanCount"], 1)
        self.assertTrue(self.result["programRetained"])
        self.assertTrue(self.result["valuesRetained"])
        self.assertTrue(self.result["contractsRetained"])
        self.assertTrue(self.result["hostBuiltinContract"])

    def test_builder_compiles_runtime_input_without_file_round_trip(self) -> None:
        source = RUNTIME_MODEL_SOURCE.read_text(encoding="utf-8")
        diagnostics = DIAGNOSTICS_SOURCE.read_text(encoding="utf-8")
        self.assertIn("let runtimeInput: SceneRuntimeInput", source)
        self.assertIn("runtimeInput: runtimeInput", source)
        self.assertIn("sceneDocument.userPropertyResolution.bindingReport", source)
        self.assertIn("shaderContracts: assetCatalog.shaderContracts", source)
        self.assertIn("sceneDocumentLoadErrorDescription", diagnostics)
        self.assertIn(
            "diagnostics.sceneDocumentLoadErrorDescription",
            source,
        )
        self.assertNotIn("SceneInterpretation", source)

    def test_production_playback_passes_the_original_project_root(self) -> None:
        playback = PLAYBACK_SOURCE.read_text(encoding="utf-8")
        host = HOST_LAUNCH_SOURCE.read_text(encoding="utf-8")
        diagnostics = DIAGNOSTICS_SOURCE.read_text(encoding="utf-8")
        self.assertIn("rootURL: record.folderURL", playback)
        self.assertNotIn("SceneDiagnosticsBuilder", playback)
        self.assertIn("rootURL: URL", host)
        self.assertIn("SceneRuntimeModelBuilder().build(", host)
        self.assertNotIn("Interpretation", diagnostics)

    def test_legacy_files_are_not_part_of_the_swift_playback_contract(self) -> None:
        source = "\n".join(
            path.read_text(encoding="utf-8") for path in SCENE_ROOT.rglob("*.swift")
        )
        debug_runner = DEBUG_RUNNER_SOURCE.read_text(encoding="utf-8")
        self.assertNotIn("SceneInterpretationFile", source)
        self.assertNotIn(".mywallpaperx-scene-interpretation.json", source)
        self.assertNotIn(".mywallpaperx-scene-preview-log.txt", source)
        self.assertIn("--mwx-debug-scene-evidence-dir", debug_runner)
        self.assertIn("scene-runtime-evidence.json", debug_runner)

    def test_asset_catalog_generates_contracts_from_material_shaders(self) -> None:
        source = ASSET_CATALOG_SOURCE.read_text(encoding="utf-8")
        self.assertIn("let shaderContracts: [SceneShaderContract]", source)
        self.assertIn("SceneShaderContractLoader().load(", source)
        self.assertIn("shaderReferences: shaderReferences", source)
        self.assertIn("resourceView: resourceView", source)
        self.assertNotIn("shaderReferences.flatMap", source)
        self.assertNotIn("shaderRootURL", source)


if __name__ == "__main__":
    unittest.main()
