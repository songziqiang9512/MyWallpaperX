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
    SCENE_ROOT / "Compilation/ShaderContract/SceneBuiltinShaderIdentity.swift",
    SCENE_ROOT / "Runtime/Frame/SceneStaticModelMaterialBindings.swift",
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Compilation/Material/SceneEffectTextureInput.swift",
    SCENE_ROOT / "Systems/Script/SceneScriptPropertyInput.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneScriptDynamicProviderHostContract.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserPropertyBindings.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePuppetAnimationPropertyTarget.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingProgram.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingCompiler+TargetMapping.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingProgramValidator.swift",
    SCENE_ROOT / "Systems/Properties/ScenePropertyLiveUpdateState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneMaterialPropertyBindingCompiler.swift",
]

STUBS = r'''
enum SceneScriptBindingPathComponent { case key(String), index(Int) }
struct SceneScriptBindingIR {
    struct Owner { let objectID: Int? }
    let owner: Owner
    let targetPath: [SceneScriptBindingPathComponent]
}
enum SceneBaseMaterialColorModulationCompiler {
    struct Binding {
        let modelPath: String
        let sourceLayerID: Int
        let materialPath: String
        let colorKey: String
        let scriptSource: String?
        let scriptProperties: [String: SceneJSONValue]
        let authoredColor: SIMD3<Double>
        var alphaKey: String? = nil
        var authoredAlpha: Float = 1
        var alphaUserPropertyKey: String? = nil
        var alphaPropertyTarget: SceneDynamicTarget? {
            guard alphaUserPropertyKey != nil, let alphaKey else { return nil }
            return .materialConstant(layerID: sourceLayerID, passIndex: 0,
                name: alphaKey, materialPath: materialPath)
        }
        var colorUserPropertyKey: String? = nil
        var colorPropertyTarget: SceneDynamicTarget? {
            guard colorUserPropertyKey != nil else { return nil }
            return .materialConstant(layerID: sourceLayerID, passIndex: 0,
                name: colorKey, materialPath: materialPath)
        }
        var colorBindingPath: [SceneUserPropertyPathComponent] {
            [.key("materials"), .key(materialPath), .key("passes"), .index(0),
             .key("constantshadervalues"), .key(colorKey)]
        }
    }
}

enum SceneShaderUserValueKind {
    case null, boolean, number, string, array, object
}

struct SceneDocument {
    struct SceneLayerMaterialInstance { let isMalformed: Bool; let combos: [String:Int]; let scalarShaderValues: [String:ShaderValue]? }
    struct ShaderValue {
        let userBinding: String?
        let userValueKind: SceneShaderUserValueKind?
        let components: [Double]?
        let bindingKeys: [String]
        let scriptSource: String? = nil
        let scriptProperties: [String: SceneJSONValue]? = nil
        let timeline: Int? = nil
        let timelineDiagnostics: [String] = []
        let rawValue: String
        let valueKind: String

        init(
            userBinding: String?, userValueKind: SceneShaderUserValueKind?,
            components: [Double]?, bindingKeys: [String],
            rawValue: String? = nil, valueKind: String? = nil
        ) {
            self.userBinding = userBinding
            self.userValueKind = userValueKind
            self.components = components
            self.bindingKeys = bindingKeys
            self.rawValue = rawValue ?? (components ?? []).map { String($0) }.joined(separator: " ")
            self.valueKind = valueKind ?? (userBinding == nil
                ? (components?.count == 1 ? "number" : "vector") : "binding")
        }
    }
}

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let puppetMeshPath: String? = nil
        let staticModelPath: String?
        let isImageRenderable = false
        let imagePath: String? = nil
        var staticBaseTexturePath: String? = nil
    }

    struct ModelMaterialLink {
        let modelPath: String
        let materialPath: String?
    }

    struct MaterialPassDescriptor {
        let materialPath: String
        let passIndex: Int
        var shaderPath: String? = nil
        var combos: [String:Int] = [:]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        var userShaderValues: [String: String] = [:]
        var texturePaths: [String] = []
        var textureSlots: [String?] = []
        var userTextureInputs: [SceneEffectTextureInput?] = []
        var staticModelMaterialBindings: SceneStaticModelMaterialBindings? = nil
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
        let bindings = SceneMaterialPropertyBindingCompiler.compile(
            descriptor: descriptor, materialInstancesByLayerID: [:]
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
                layerID: layerID, passIndex: 0, name: "color", materialPath: "materials/model.json"
            )]?.value == .vector3(0.2, 0.4, 0.6))
            precondition(snapshot[.materialConstant(
                layerID: layerID, passIndex: 0, name: "emissivecolor", materialPath: "materials/model.json"
            )]?.value == .vector3(0.9, 0.3, 0.1))
            precondition(snapshot[.materialConstant(
                layerID: layerID, passIndex: 0, name: "alpha", materialPath: "materials/model.json"
            )]?.value == .scalar(0.4))
            precondition(snapshot[.materialConstant(
                layerID: layerID, passIndex: 0, name: "brightness", materialPath: "materials/model.json"
            )]?.value == .scalar(1.75))
            precondition(snapshot[.materialConstant(
                layerID: layerID, passIndex: 0,
                name: "emissivebrightness", materialPath: "materials/model.json"
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
            layerID: 7, passIndex: 0, name: "brightness", materialPath: "materials/model.json"
        )] == nil)

        let duplicatePassDescriptor = SceneRenderDescriptor(
            layers: [.init(id: 7, staticModelPath: "models/a.mdl")],
            modelMaterialLinks: descriptor.modelMaterialLinks,
            materialPasses: [pass0, pass0]
        )
        precondition(SceneMaterialPropertyBindingCompiler.compile(
            descriptor: duplicatePassDescriptor, materialInstancesByLayerID: [:]
        ).isEmpty)

        let multipart = SceneRenderDescriptor(
            layers: descriptor.layers,
            modelMaterialLinks: descriptor.modelMaterialLinks + [
                .init(modelPath: "models/a.mdl", materialPath: "materials/other.json")
            ],
            materialPasses: [pass0, .init(
                materialPath: "materials/other.json", passIndex: 0,
                constantShaderValues: ["color": wrapper("emissive", [1, 0.5, 0.25])]
            )]
        )
        let multiBindings = SceneMaterialPropertyBindingCompiler.compile(descriptor: multipart, materialInstancesByLayerID: [:])
        precondition(multiBindings.count == 12)
        let mapped = multiBindings.compactMap {
            ScenePropertyBindingCompiler.map($0, propertyKind: nil)?.target
        }
        precondition(Set(mapped).count == 12)
        for layerID in [7, 8] {
            precondition(mapped.contains(.materialConstant(
                layerID: layerID, passIndex: 0, name: "color", materialPath: "materials/other.json"
            )))
            precondition(mapped.contains(.materialConstant(
                layerID: layerID, passIndex: 0, name: "color", materialPath: "materials/model.json"
            )))
        }
        nestedMaterialInputs()
    }

    static func nestedMaterialInputs() {
        let brightnessInputs = SceneScriptPropertyInputCodec.inputs([
            "minvalue": .object(["user": .string("minimum"), "value": .number(0)]),
            "smooth": .object(["user": .string("smooth"), "value": .number(0)]),
            "literal": .number(2),
        ])!
        let colorInputs = SceneScriptPropertyInputCodec.inputs([
            "green": .object(["user": .string("green"), "value": .number(0.2)]),
        ])!
        // Reuse one material asset while preserving each layer and field's VM identity.
        let descriptor = SceneRenderDescriptor(
            layers: [.init(id: 7, staticModelPath: "models/a.mdl"),
                     .init(id: 8, staticModelPath: "models/a.mdl"),
                     .init(id: 9, staticModelPath: nil)],
            modelMaterialLinks: [.init(modelPath: "models/a.mdl", materialPath: "materials/model.json")],
            materialPasses: [.init(materialPath: "materials/model.json", passIndex: 0,
                                  constantShaderValues: [:])]
        )
        var entries: [(target: SceneDynamicTarget, inputs: [String: SceneScriptPropertyInput])] = []
        var expectedTargets: Set<SceneDynamicTarget> = []
        for layerID in [7, 8] {
            for (name, inputs) in [("emissivebrightness", brightnessInputs), ("emissivecolor", colorInputs)] {
                entries.append((.materialConstant(layerID: layerID, passIndex: 0,
                    name: name, materialPath: "materials/model.json"), inputs))
                let path: [SceneUserPropertyPathComponent] = [
                    .key("materials"), .key("materials/model.json"), .key("passes"), .index(0),
                    .key("constantshadervalues"), .key(name),
                ]
                expectedTargets.formUnion(SceneScriptPropertyInputCodec.liveConsumerTargets(
                    layerID: layerID, targetPath: SceneScriptPropertyTargetPath.encoded(path), inputs: inputs
                ))
            }
        }
        let bindings = SceneMaterialPropertyBindingCompiler.compile(
            descriptor: descriptor, materialInstancesByLayerID: [:], modelScriptInputs: entries
        )
        precondition(bindings.count == 6)
        let compilation = ScenePropertyBindingCompiler().compile(
            report: .init(bindings: bindings, diagnostics: []),
            catalog: .init(definitions: [
                property("minimum", .slider, .number(1), 0, 1),
                property("smooth", .slider, .number(0), 0, 28),
                property("green", .slider, .number(0.2), 0, 1),
            ])
        )
        precondition(compilation.diagnostics.isEmpty)
        let targets = Set(compilation.program.instructions.map(\.target))
        precondition(targets == expectedTargets && targets.count == 6)
        precondition(compilation.program.rebuildRequiredPropertyKeys.isEmpty)
        // Inputs remain script-instance properties; only the VM produces material constants.
        precondition(targets.allSatisfy { if case .scriptInstanceProperty = $0 { return true }; return false })
        var state = ScenePropertyLiveUpdateState(
            program: compilation.program,
            effectiveValues: ["minimum": .number(1), "smooth": .number(0), "green": .number(0.2)],
            activeConsumerTargets: targets
        )
        precondition(state.apply(.number(0), forPropertyKey: "minimum"))
        precondition(state.apply(replacements: ["smooth": .number(4), "green": .number(0.8)],
                                 changedPropertyKeys: ["smooth", "green"]))
        precondition(state.revision == 2)
        for instruction in compilation.program.instructions {
            let expected: Double = instruction.propertyKey == "minimum" ? 0
                : instruction.propertyKey == "smooth" ? 4 : 0.8
            precondition(state.userValues[instruction.target] == .scalar(expected))
        }
        let json = SceneScriptPropertyInputCodec.scriptPropertiesJSON(
            brightnessInputs, effectiveValues: state.effectiveValues
        )!
        let object = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Double]
        precondition(object == ["minvalue": 0, "smooth": 4, "literal": 2])
        let before = state
        for invalid in [SceneUserPropertyValue.string("bad"), .number(.nan), .number(2)] {
            precondition(!state.apply(replacements: ["minimum": invalid, "smooth": .number(5)],
                                      changedPropertyKeys: ["minimum", "smooth"]))
            unchanged(state, before)
        }
        let unavailable = compilation.program.instructions.first { $0.propertyKey == "smooth" }!.target
        precondition(!state.apply(.number(5), forPropertyKey: "smooth", unavailableConsumerTargets: [unavailable]))
        unchanged(state, before)
        var missingConsumer = ScenePropertyLiveUpdateState(
            program: compilation.program, effectiveValues: state.effectiveValues,
            activeConsumerTargets: targets.subtracting([unavailable])
        )
        let missingBefore = missingConsumer
        precondition(!missingConsumer.apply(.number(5), forPropertyKey: "smooth"))
        unchanged(missingConsumer, missingBefore)
        precondition(SceneMaterialPropertyBindingCompiler.compile(
            descriptor: descriptor, materialInstancesByLayerID: [:], modelScriptInputs: [
                (.layer(layerID: 7, field: .color), brightnessInputs),
                (.materialConstant(layerID: 9, passIndex: 0, name: "emissivebrightness",
                    materialPath: "materials/model.json"), brightnessInputs),
                (.materialConstant(layerID: 404, passIndex: 0, name: "emissivebrightness",
                    materialPath: "materials/model.json"), brightnessInputs),
            ]
        ).isEmpty)
        // Candidate admission still owns malformed nested wrappers.
        precondition(SceneScriptPropertyInputCodec.inputs([
            "minvalue": .object(["user": .string("minimum"), "value": .number(0), "extra": .bool(true)])
        ]) == nil)
        print("nested-material-live-transaction: OK")
    }

    static func unchanged(_ state: ScenePropertyLiveUpdateState, _ before: ScenePropertyLiveUpdateState) {
        precondition(state.effectiveValues == before.effectiveValues)
        precondition(state.userValues == before.userValues)
        precondition(state.revision == before.revision)
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
        self.assertIn("nested-material-live-transaction: OK", completed.stdout)


if __name__ == "__main__":
    unittest.main()
