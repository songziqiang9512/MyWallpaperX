#!/usr/bin/env python3

"""Executable admission checks for generic SceneScript layer transforms."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
RUNTIME_MODEL_SOURCE = SCENE / "Runtime/SceneRuntimeModel.swift"
REMOVED_SUPPRESSION_SOURCE = (
    SCENE / "Properties/SceneScriptedLayerTransformProjection.swift"
)
SOURCES = [
    SCENE / "Resources/SceneNamedTextureReference.swift",
    SCENE
    / "RenderGraph/LayerDependencies/SceneNamedTextureDependencyReferenceAnalysis.swift",
    SCENE / "Properties/SceneScriptDynamicProviderHostContract.swift",
    SCENE / "Runtime/SceneScript/SceneScriptVectorCandidateCatalog.swift",
]

HARNESS = r'''
import Foundation

nonisolated enum SceneScriptScalarRuntimeFailure: Error, Sendable {
    case invalid
}

nonisolated enum SceneDynamicValueType: String, Sendable {
    case bool, vector2, vector3
}

nonisolated enum SceneDynamicValue: Equatable, Sendable {
    case bool(Bool)
    case vector2(Double, Double)
    case vector3(Double, Double, Double)
}

nonisolated enum SceneDynamicLayerField: Hashable, Sendable {
    case visibility, origin, scale, angles, color
}

nonisolated enum SceneDynamicTextField: Hashable, Sendable {
    case color
}

nonisolated enum SceneDynamicTarget: Hashable, Sendable {
    case layer(layerID: Int, field: SceneDynamicLayerField)
    case text(layerID: Int, field: SceneDynamicTextField)
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
}

nonisolated struct SceneDynamicTargetDefinition: Sendable {
    let target: SceneDynamicTarget
    let valueType: SceneDynamicValueType
    let authoredValue: SceneDynamicValue
}

nonisolated enum SceneJSONValue: Sendable {
    case bool(Bool)
    case number(Double)
    case string(String)

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }
}

nonisolated enum SceneScriptBindingValueType: Sendable {
    case boolean, string
}

nonisolated enum SceneScriptBindingPathComponent: Equatable, Sendable {
    case key(String)
    case index(Int)
}

nonisolated struct SceneScriptBindingOwner: Sendable {
    enum Kind: Sendable { case object, pass }
    let kind: Kind
    let objectIndex: Int?
    let objectID: Int?
    let effectIndex: Int?
    let effectID: Int?
    let passIndex: Int?
    let passID: Int?
}

nonisolated struct SceneScriptBindingIR: Sendable {
    let source: String
    let owner: SceneScriptBindingOwner
    let targetPath: [SceneScriptBindingPathComponent]
    let properties: [String: SceneJSONValue]
    let authoredValue: SceneJSONValue?
    let valueType: SceneScriptBindingValueType
    let wrapperKeys: [String]?

    var targetKey: String {
        guard case let .key(key)? = targetPath.last else { return "" }
        return key
    }
}

nonisolated struct SceneScriptPropertyInput: Sendable {}

nonisolated enum SceneScriptPropertyInputCodec {
    static func inputs(
        _ properties: [String: SceneJSONValue]
    ) -> [String: SceneScriptPropertyInput]? {
        var result: [String: SceneScriptPropertyInput] = [:]
        for (key, value) in properties {
            guard validName(key), let input = propertyInput(value) else {
                return nil
            }
            result[key] = input
        }
        return result
    }

    static func propertyInput(
        _ value: SceneJSONValue
    ) -> SceneScriptPropertyInput? {
        switch value {
        case .bool, .string:
            return .init()
        case let .number(number):
            return number.isFinite ? .init() : nil
        }
    }

    static func vector2(_ value: String) -> SIMD2<Double>? {
        let values = value.split(separator: " ").compactMap { Double($0) }
        guard values.count == 2, values.allSatisfy(\.isFinite) else { return nil }
        return .init(values[0], values[1])
    }

    static func vector3(_ value: String) -> SIMD3<Double>? {
        let values = value.split(separator: " ").compactMap { Double($0) }
        guard values.count == 3, values.allSatisfy(\.isFinite) else { return nil }
        return .init(values[0], values[1], values[2])
    }

    static func validName(_ value: String) -> Bool {
        !value.isEmpty
    }

    static func liveConsumerTargets(
        binding: SceneScriptBindingIR,
        inputs: [String: SceneScriptPropertyInput]
    ) -> Set<SceneDynamicTarget> {
        []
    }
}

nonisolated struct SceneScriptDynamicImageReference: Equatable, Hashable, Sendable {
    let authoredPath: String
    let modelPath: String
}

nonisolated enum SceneScriptDynamicImageReferenceAnalysis {
    static func references(
        in source: String,
        descriptor: SceneRenderDescriptor
    ) -> [SceneScriptDynamicImageReference]? { nil }
}

nonisolated struct SceneShaderContract {}

nonisolated struct SceneEffectTextureInput: Sendable {
    enum Kind: Sendable { case system, property }

    let kind: Kind
    let value: String
}

nonisolated enum SceneBaseMaterialColorModulationCompiler {
    struct Binding {
        let modelPath: String
        let sourceLayerID: Int
        let scriptSource: String
        let scriptProperties: [String: SceneJSONValue]
        let authoredColor: SIMD3<Double>
    }

    static func compile(
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        dynamicImageModelPaths: Set<String>,
        admittedLayerColorConsumerIDs: Set<Int>
    ) -> [Binding] { [] }
}

nonisolated struct SceneRenderDescriptor: Sendable {
    enum SceneShaderUserValueKind: Sendable { case null }

    struct TextStyle: Sendable {}

    struct ShaderValue: Sendable {
        let scriptSource: String?
        let components: [Double]?
        let userValueKind: SceneShaderUserValueKind?
        var bindingKeys: [String] = []
        var timeline: Int? = nil
        var timelineDiagnostics: [String] = []
        var scriptProperties: [String: SceneJSONValue]? = nil
    }

    struct EffectDescriptor: Sendable {
        struct PassDescriptor: Sendable {
            let passIndex: Int
            let id: Int?
            let constantShaderValues: [String: ShaderValue]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
        }

        let id: String
        let name: String?
        let effectID: Int?
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer: Sendable {
        let id: Int
        let layerIndex: Int
        let originXYZ: [Float]?
        let scaleXYZ: [Float]?
        let anglesXYZ: [Float]?
        var colorRGB: [Float]? = nil
        var staticModelPath: String? = nil
        var spotLight: Int? = nil
        var directionalLight: Int? = nil
        var effects: [EffectDescriptor]
        var visible: Bool? = true
        var contentKind = "image"
        var parentID: Int? = nil
        var childLayerIDs: [Int] = []
        var effectFiles: [String] = []
        var dependencyLayerIDs: [Int] = []
        var authoredDependencies: [Int] = []
        var utilityLayer: Int? = nil
        var text: String? = nil
        var textStyle: TextStyle? = nil

        var supportsDirectLayerColorConsumer: Bool {
            contentKind == "solid"
                || (contentKind == "image" && effects.isEmpty)
        }
    }

    struct ModelMaterialLink: Sendable {
        let modelPath: String
        let materialPath: String?
    }

    struct MaterialPassDescriptor: Sendable {
        let materialPath: String
        let passIndex: Int
        let constantShaderValues: [String: ShaderValue]
    }

    var layers: [Layer]
    var modelMaterialLinks: [ModelMaterialLink] = []
    var materialPasses: [MaterialPassDescriptor] = []
}

nonisolated enum SceneScriptVectorProgram {}

func binding(
    key: String,
    value: String,
    pathKey: String? = nil,
    properties: [String: SceneJSONValue] = [:],
    wrapperKeys: [String]? = nil
) -> SceneScriptBindingIR {
    .init(
        source: "export function update(value) { return value; }",
        owner: .init(
            kind: .object,
            objectIndex: 0,
            objectID: 101,
            effectIndex: nil,
            effectID: nil,
            passIndex: nil,
            passID: nil
        ),
        targetPath: [
            .key("objects"), .index(0), .key(pathKey ?? key),
        ],
        properties: properties,
        authoredValue: .string(value),
        valueType: .string,
        wrapperKeys: wrapperKeys ?? (properties.isEmpty
            ? ["script", "value"]
            : ["script", "scriptproperties", "value"])
    )
}

@main
enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: [.init(
            id: 101,
            layerIndex: 0,
            originXYZ: [1, 2, 3],
            scaleXYZ: [4, 5, 6],
            anglesXYZ: [7, 8, 9],
            effects: []
        )])
        let family = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: [
                binding(key: "origin", value: "1 2 3"),
                binding(key: "scale", value: "4 5 6"),
                binding(key: "angles", value: "7 8 9"),
            ]
        )
        let duplicate = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: [
                binding(key: "angles", value: "7 8 9"),
                binding(key: "angles", value: "7 8 9"),
            ]
        )
        let mismatched = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: [binding(key: "angles", value: "7 8 10")]
        )
        let wrongPath = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: [
                binding(key: "angles", value: "7 8 9", pathKey: "origin"),
            ]
        )
        var colorDescriptor = descriptor
        colorDescriptor.layers[0].colorRGB = [0.25, 0.5, 0.75]
        let color = SceneScriptVectorProgram.project(
            descriptor: colorDescriptor,
            scriptBindings: [binding(key: "color", value: "0.25 0.5 0.75")],
            admittedLayerColorConsumerIDs: [101]
        )
        let unclaimedColor = SceneScriptVectorProgram.project(
            descriptor: colorDescriptor,
            scriptBindings: [binding(key: "color", value: "0.25 0.5 0.75")]
        )
        let mismatchedColor = SceneScriptVectorProgram.project(
            descriptor: colorDescriptor,
            scriptBindings: [binding(key: "color", value: "0.25 0.5 0.7")],
            admittedLayerColorConsumerIDs: [101]
        )
        var hiddenColorDescriptor = colorDescriptor
        hiddenColorDescriptor.layers[0].visible = false
        let hiddenColor = SceneScriptVectorProgram.project(
            descriptor: hiddenColorDescriptor,
            scriptBindings: [binding(key: "color", value: "0.25 0.5 0.75")],
            admittedLayerColorConsumerIDs: [101]
        )
        var effectColorDescriptor = colorDescriptor
        effectColorDescriptor.layers[0].effects = [.init(
            id: "effect", name: "effect", effectID: 1, visible: true,
            passes: []
        )]
        let effectColor = SceneScriptVectorProgram.project(
            descriptor: effectColorDescriptor,
            scriptBindings: [binding(key: "color", value: "0.25 0.5 0.75")],
            admittedLayerColorConsumerIDs: [101]
        )
        var textColorDescriptor = effectColorDescriptor
        textColorDescriptor.layers[0].contentKind = "text"
        textColorDescriptor.layers[0].text = "renamed text"
        textColorDescriptor.layers[0].textStyle = .init()
        let textColor = SceneScriptVectorProgram.project(
            descriptor: textColorDescriptor,
            scriptBindings: [binding(
                key: "color", value: "0.25 0.5 0.75",
                properties: [
                    "dynamic": .bool(false),
                    "tint": .string("0.1 0.2 0.3"),
                ]
            )],
            admittedLayerColorConsumerIDs: [101]
        )
        let duplicateColor = SceneScriptVectorProgram.project(
            descriptor: colorDescriptor,
            scriptBindings: [
                binding(key: "color", value: "0.25 0.5 0.75"),
                binding(key: "color", value: "0.25 0.5 0.75"),
            ],
            admittedLayerColorConsumerIDs: [101]
        )
        let expectedTargets: Set<SceneDynamicTarget> = [
            .layer(layerID: 101, field: .origin),
            .layer(layerID: 101, field: .scale),
            .layer(layerID: 101, field: .angles),
        ]
        let payload: [String: Any] = [
            "familyTargetsComplete": family.targets == expectedTargets,
            "angleDefinition": family.definitions.contains {
                $0.target == .layer(layerID: 101, field: .angles)
                    && $0.valueType == .vector3
                    && $0.authoredValue == .vector3(7, 8, 9)
            },
            "duplicateRejected": duplicate.uniqueCandidates.isEmpty
                && duplicate.duplicateTargets == [
                    .layer(layerID: 101, field: .angles),
                ],
            "mismatchRejected": mismatched.candidates.isEmpty,
            "wrongPathRejected": wrongPath.candidates.isEmpty,
            "colorDefinition": color.definitions.contains {
                $0.target == .layer(layerID: 101, field: .color)
                    && $0.valueType == .vector3
                    && $0.authoredValue == .vector3(0.25, 0.5, 0.75)
            },
            "unclaimedColorRejected": unclaimedColor.candidates.isEmpty,
            "mismatchedColorRejected": mismatchedColor.candidates.isEmpty,
            "hiddenColorRejected": hiddenColor.candidates.isEmpty,
            "effectColorRejected": effectColor.candidates.isEmpty,
            "effectfulTextColorDefinition": textColor.definitions.contains {
                $0.target == .text(layerID: 101, field: .color)
                    && $0.valueType == .vector3
                    && $0.authoredValue == .vector3(0.25, 0.5, 0.75)
            } && textColor.candidates.first?.properties.count == 2,
            "duplicateColorRejected": duplicateColor.uniqueCandidates.isEmpty
                && duplicateColor.duplicateTargets == [
                    .layer(layerID: 101, field: .color),
                ],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneScriptLayerTransformProjectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-script-layer-transform-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "layer-transform-projection"
        compilation = subprocess.run(
            ["swiftc", *map(str, SOURCES), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        cls.result = json.loads(subprocess.run(
            [str(binary)],
            check=True,
            capture_output=True,
            text=True,
        ).stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_full_authored_transform_family_is_projected(self) -> None:
        self.assertTrue(self.result["familyTargetsComplete"])
        self.assertTrue(self.result["angleDefinition"])

    def test_identity_and_duplicate_fail_closed(self) -> None:
        self.assertTrue(self.result["duplicateRejected"])
        self.assertTrue(self.result["mismatchRejected"])
        self.assertTrue(self.result["wrongPathRejected"])

    def test_image_color_requires_exact_visible_direct_consumer(self) -> None:
        self.assertTrue(self.result["colorDefinition"])
        self.assertTrue(self.result["unclaimedColorRejected"])
        self.assertTrue(self.result["mismatchedColorRejected"])
        self.assertTrue(self.result["hiddenColorRejected"])
        self.assertTrue(self.result["effectColorRejected"])
        self.assertTrue(self.result["duplicateColorRejected"])

    def test_effectful_text_color_uses_the_dynamic_text_consumer(self) -> None:
        self.assertTrue(self.result["effectfulTextColorDefinition"])

    def test_unadmitted_scale_script_keeps_the_resolved_layer_current(self) -> None:
        runtime_model = RUNTIME_MODEL_SOURCE.read_text(encoding="utf-8")
        self.assertFalse(REMOVED_SUPPRESSION_SOURCE.exists())
        self.assertNotIn("SceneScriptedLayerTransformProjection.apply", runtime_model)
        self.assertIn("let runtimeDescriptor = particleProjectedDescriptor", runtime_model)


if __name__ == "__main__":
    unittest.main()
