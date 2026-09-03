#!/usr/bin/env python3

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Properties/SceneUserProperty.swift",
    SCENE_ROOT / "Properties/SceneScriptDynamicProviderHostContract.swift",
    SCENE_ROOT / "Properties/SceneUserPropertyBindings.swift",
    SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "Properties/ScenePuppetAnimationPropertyTarget.swift",
    SCENE_ROOT / "Properties/ScenePropertyBindingProgram.swift",
    SCENE_ROOT / "Properties/ScenePropertyBindingCompiler+TargetMapping.swift",
    SCENE_ROOT / "Properties/ScenePropertyBindingProgramValidator.swift",
    SCENE_ROOT / "Properties/SceneStaticModelMaterialPropertyBindingCompiler.swift",
]

STUBS = r'''
enum SceneShaderUserValueKind {
    case null, boolean, number, string, array, object
}

struct SceneDocument {
    struct ShaderValue {
        let userBinding: String?
        let userValueKind: SceneShaderUserValueKind?
        let components: [Double]?
        let bindingKeys: [String]
    }
}

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let staticModelPath: String?
    }

    struct ModelMaterialLink {
        let modelPath: String
        let materialPath: String?
    }

    struct MaterialPassDescriptor {
        let materialPath: String
        let passIndex: Int
        let constantShaderValues: [String: SceneDocument.ShaderValue]
    }

    let layers: [Layer]
    let modelMaterialLinks: [ModelMaterialLink]
    let materialPasses: [MaterialPassDescriptor]
}
'''

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() {
        let values: [String: SceneDocument.ShaderValue] = [
            "color": wrapper("tint", [1, 1, 1]),
            "emissivecolor": wrapper("emissive", [1, 0.5, 0.25]),
            "alpha": wrapper("opacity", [0.8]),
            "brightness": wrapper("brightness", [1]),
            "emissivebrightness": wrapper("emissiveBrightness", [2]),
            "metallic": wrapper("metallic", [1]),
            "roughness": .init(
                userBinding: "roughness", userValueKind: .string,
                components: [1], bindingKeys: ["extra", "user", "value"]
            ),
        ]
        let pass0 = SceneRenderDescriptor.MaterialPassDescriptor(
            materialPath: "materials/model.json",
            passIndex: 0,
            constantShaderValues: values
        )
        let pass1 = SceneRenderDescriptor.MaterialPassDescriptor(
            materialPath: "materials/model.json",
            passIndex: 1,
            constantShaderValues: [:]
        )
        let descriptor = SceneRenderDescriptor(
            layers: [
                .init(id: 7, staticModelPath: "models/a.mdl"),
                .init(id: 8, staticModelPath: "MODELS\\A.MDL"),
            ],
            modelMaterialLinks: [
                .init(
                    modelPath: "models/a.mdl",
                    materialPath: "MATERIALS\\MODEL.JSON"
                ),
            ],
            materialPasses: [pass0, pass1]
        )
        let bindings = SceneStaticModelMaterialPropertyBindingCompiler.compile(
            descriptor: descriptor
        )
        precondition(bindings.count == 10)

        let compiler = ScenePropertyBindingCompiler()
        let compilation = compiler.compile(
            report: .init(bindings: bindings, diagnostics: []),
            catalog: .init(definitions: [
                property("tint", .color, .string("1 1 1")),
                property("emissive", .color, .string("1 0.5 0.25")),
                property("opacity", .slider, .number(0.8), 0, 1),
                property("brightness", .slider, .number(1), 0, 2),
                property("emissiveBrightness", .slider, .number(2), 0, 10),
                property("metallic", .slider, .number(1), 0, 1),
                property("roughness", .slider, .number(1), 0, 1),
            ])
        )
        precondition(compilation.diagnostics.isEmpty)
        precondition(compilation.program.definitions.count == 10)
        precondition(compilation.program.instructions.count == 10)
        let evaluation = compilation.program.evaluate(effectiveValues: [
            "tint": .string("0.2 0.4 0.6"),
            "emissive": .string("0.9 0.3 0.1"),
            "opacity": .number(0.4),
            "brightness": .number(1.75),
            "emissiveBrightness": .number(3),
            "metallic": .number(0.2),
            "roughness": .number(0.2),
        ])
        precondition(evaluation.diagnostics.isEmpty)
        let snapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 4,
            generation: 9,
            definitions: compilation.program.definitions,
            userValues: evaluation.userValues
        ).snapshot
        for layerID in [7, 8] {
            precondition(snapshot[.materialConstant(
                layerID: layerID, passIndex: 0, name: "color"
            )]?.value == .vector3(0.2, 0.4, 0.6))
            precondition(snapshot[.materialConstant(
                layerID: layerID, passIndex: 0, name: "emissivecolor"
            )]?.value == .vector3(0.9, 0.3, 0.1))
            precondition(snapshot[.materialConstant(
                layerID: layerID, passIndex: 0, name: "alpha"
            )]?.value == .scalar(0.4))
            precondition(snapshot[.materialConstant(
                layerID: layerID, passIndex: 0, name: "brightness"
            )]?.value == .scalar(1.75))
            precondition(snapshot[.materialConstant(
                layerID: layerID, passIndex: 0,
                name: "emissivebrightness"
            )]?.value == .scalar(3))
        }

        let invalidEvaluation = compilation.program.evaluate(effectiveValues: [
            "tint": .string("0.2 0.4 0.6"),
            "emissive": .string("0.9 0.3 0.1"),
            "opacity": .number(0.4),
            "brightness": .number(3),
            "emissiveBrightness": .number(3),
        ])
        precondition(invalidEvaluation.userValues[.materialConstant(
            layerID: 7, passIndex: 0, name: "brightness"
        )] == nil)

        let duplicatePassDescriptor = SceneRenderDescriptor(
            layers: [.init(id: 7, staticModelPath: "models/a.mdl")],
            modelMaterialLinks: descriptor.modelMaterialLinks,
            materialPasses: [pass0, pass0]
        )
        precondition(SceneStaticModelMaterialPropertyBindingCompiler.compile(
            descriptor: duplicatePassDescriptor
        ).isEmpty)
    }

    static func wrapper(
        _ property: String,
        _ components: [Double]
    ) -> SceneDocument.ShaderValue {
        .init(
            userBinding: property,
            userValueKind: .string,
            components: components,
            bindingKeys: ["user", "value"]
        )
    }

    static func property(
        _ key: String,
        _ kind: SceneUserPropertyKind,
        _ value: SceneUserPropertyValue,
        _ minimum: Double? = nil,
        _ maximum: Double? = nil
    ) -> SceneUserPropertyDefinition {
        .init(
            key: key, title: key, kind: kind, runtimeType: kind.rawValue,
            order: 0, index: nil, minimumValue: minimum,
            maximumValue: maximum, stepValue: nil,
            allowsFractionalValues: true, fractionalPrecision: nil,
            displayCondition: nil, defaultValue: value, options: []
        )
    }
}
'''


class SceneStaticModelMaterialPropertyTests(unittest.TestCase):
    def test_material_wrappers_reach_shared_typed_snapshot(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-model-material-property-") as tmp:
            root = Path(tmp)
            stubs = root / "Stubs.swift"
            harness = root / "Harness.swift"
            executable = root / "Harness"
            stubs.write_text(STUBS, encoding="utf-8")
            harness.write_text(HARNESS, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-modules")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-modules")
            compiled = subprocess.run(
                [
                    swiftc,
                    *map(str, SOURCES),
                    str(stubs),
                    str(harness),
                    "-o", str(executable),
                ],
                capture_output=True,
                text=True,
                env=environment,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            completed = subprocess.run(
                [str(executable)], capture_output=True, text=True, env=environment
            ) if compiled.returncode == 0 else compiled
        self.assertEqual(completed.returncode, 0, completed.stderr)


if __name__ == "__main__":
    unittest.main()
