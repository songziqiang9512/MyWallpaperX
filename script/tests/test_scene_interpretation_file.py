#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
INTERPRETATION_SOURCE = SCENE_ROOT / "Format/SceneInterpretationFile.swift"
DIAGNOSTICS_SOURCE = SCENE_ROOT / "Runtime/SceneDiagnostics.swift"
RUNTIME_MODEL_SOURCE = SCENE_ROOT / "Runtime/SceneRuntimeModel.swift"
ASSET_CATALOG_SOURCE = SCENE_ROOT / "Resources/SceneAssetCatalog.swift"
SHADER_CONTRACT_SOURCE = SCENE_ROOT / "RenderGraph/SceneShaderContract.swift"
SHADER_CONTRACT_LOADER_SOURCE = SCENE_ROOT / "RenderGraph/SceneShaderContractLoader.swift"
SWIFT_SOURCES = [
    SCENE_ROOT / "Properties/SceneUserProperty.swift",
    SCENE_ROOT / "Properties/SceneUserPropertyBindings.swift",
    SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "Properties/ScenePropertyBindingProgram.swift",
    SCENE_ROOT / "Properties/ScenePropertyBindingCompiler+TargetMapping.swift",
    SCENE_ROOT / "Properties/ScenePropertyBindingProgramValidator.swift",
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SHADER_CONTRACT_SOURCE,
    SHADER_CONTRACT_LOADER_SOURCE,
    INTERPRETATION_SOURCE,
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
        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
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
            rootURL: outputDirectory
        )
        let writer = SceneInterpretationFileWriter()
        let url = try writer.write(
            renderDescriptor: .init(entryPath: "scene.json"),
            propertyBindingProgram: program,
            effectivePropertyValues: effectiveValues,
            shaderContracts: shaderContracts,
            outputDirectory: outputDirectory
        )
        let file = try SceneInterpretationFileReader().read(from: url)
        let rawData = try Data(contentsOf: url)
        let raw = try JSONSerialization.jsonObject(with: rawData) as! [String: Any]

        var legacy = raw
        legacy["formatVersion"] = 20
        let legacyURL = outputDirectory.appendingPathComponent("legacy.json")
        try JSONSerialization.data(withJSONObject: legacy).write(to: legacyURL)
        let legacyRejected: Bool
        do {
            _ = try SceneInterpretationFileReader().read(from: legacyURL)
            legacyRejected = false
        } catch SceneInterpretationFileError.unsupportedFormatVersion(20) {
            legacyRejected = true
        }

        var legacyMissingContracts = legacy
        legacyMissingContracts.removeValue(forKey: "shaderContracts")
        let legacyMissingContractsURL = outputDirectory.appendingPathComponent(
            "legacy-missing-contracts.json"
        )
        try JSONSerialization.data(withJSONObject: legacyMissingContracts).write(
            to: legacyMissingContractsURL
        )

        var missingContracts = raw
        missingContracts.removeValue(forKey: "shaderContracts")
        let missingContractsURL = outputDirectory.appendingPathComponent(
            "missing-contracts.json"
        )
        try JSONSerialization.data(withJSONObject: missingContracts).write(
            to: missingContractsURL
        )

        var missingProgram = raw
        missingProgram.removeValue(forKey: "propertyBindingProgram")
        let missingProgramURL = outputDirectory.appendingPathComponent("missing-program.json")
        try JSONSerialization.data(withJSONObject: missingProgram).write(to: missingProgramURL)

        var missingValues = raw
        missingValues.removeValue(forKey: "effectivePropertyValues")
        let missingValuesURL = outputDirectory.appendingPathComponent("missing-values.json")
        try JSONSerialization.data(withJSONObject: missingValues).write(to: missingValuesURL)

        let payload: [String: Any] = [
            "formatVersion": file.formatVersion,
            "sourceEntryPath": file.sourceEntryPath,
            "authoredPlanCount": file.authoredEffectRenderPlans.count,
            "programRoundTrip": file.propertyBindingProgram == program,
            "valuesRoundTrip": file.effectivePropertyValues == effectiveValues,
            "contractsRoundTrip": file.shaderContracts == shaderContracts,
            "hostBuiltinContract": shaderContracts.count == 1
                && shaderContracts[0].sourceKind == .hostBuiltin
                && shaderContracts[0].stages.isEmpty
                && shaderContracts[0].diagnostics.isEmpty,
            "rawHasProgram": raw["propertyBindingProgram"] != nil,
            "rawHasValues": raw["effectivePropertyValues"] != nil,
            "rawHasContracts": raw["shaderContracts"] != nil,
            "legacyRejected": legacyRejected,
            "legacyMissingContractsRejected": readFails(legacyMissingContractsURL),
            "missingContractsRejected": readFails(missingContractsURL),
            "missingProgramRejected": readFails(missingProgramURL),
            "missingValuesRejected": readFails(missingValuesURL),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func readFails(_ url: URL) -> Bool {
        do {
            _ = try SceneInterpretationFileReader().read(from: url)
            return false
        } catch {
            return true
        }
    }
}
'''


class SceneInterpretationFileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-interpretation-v21-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-interpretation-v21"
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

    def test_v25_round_trips_program_values_and_shader_contracts(self) -> None:
        self.assertEqual(self.result["formatVersion"], 27)
        self.assertEqual(self.result["sourceEntryPath"], "scene.json")
        self.assertEqual(self.result["authoredPlanCount"], 1)
        self.assertTrue(self.result["programRoundTrip"])
        self.assertTrue(self.result["valuesRoundTrip"])
        self.assertTrue(self.result["contractsRoundTrip"])
        self.assertTrue(self.result["hostBuiltinContract"])
        self.assertTrue(self.result["rawHasProgram"])
        self.assertTrue(self.result["rawHasValues"])
        self.assertTrue(self.result["rawHasContracts"])

    def test_old_and_incomplete_cache_files_are_rejected(self) -> None:
        self.assertTrue(self.result["legacyRejected"])
        self.assertTrue(self.result["legacyMissingContractsRejected"])
        self.assertTrue(self.result["missingContractsRejected"])
        self.assertTrue(self.result["missingProgramRejected"])
        self.assertTrue(self.result["missingValuesRejected"])

    def test_asset_catalog_generates_contracts_from_material_shaders(self) -> None:
        source = ASSET_CATALOG_SOURCE.read_text(encoding="utf-8")
        self.assertIn("let shaderContracts: [SceneShaderContract]", source)
        self.assertIn("SceneShaderContractLoader().load(", source)
        self.assertIn("shaderReferences: shaderReferences", source)

    def test_diagnostics_compiles_unresolved_bindings_and_effective_values(self) -> None:
        source = DIAGNOSTICS_SOURCE.read_text(encoding="utf-8")
        self.assertIn("sceneDocument.userPropertyResolution.bindingReport", source)
        self.assertIn("catalog: project.userProperties", source)
        self.assertIn("project.userProperties.effectiveValues(", source)
        self.assertIn("overrides: propertyOverrides", source)
        self.assertIn("shaderContracts: assetCatalog.shaderContracts", source)

    def test_runtime_model_retains_the_complete_interpretation_contract(self) -> None:
        source = RUNTIME_MODEL_SOURCE.read_text(encoding="utf-8")
        self.assertIn("let interpretationFile: SceneInterpretationFile", source)
        self.assertIn("interpretationFile: rendererInput", source)
        self.assertIn("shaderContracts: assetCatalog.shaderContracts", source)
        self.assertNotIn("propertyBindingProgram: ScenePropertyBindingProgram?", source)


if __name__ == "__main__":
    unittest.main()
