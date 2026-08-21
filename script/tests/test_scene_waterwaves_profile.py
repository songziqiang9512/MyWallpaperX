#!/usr/bin/env python3
"""waterwaves 多指纹 shader profile 的准入与语义参数测试。

语料 5 种可执行指纹逐 profile 断言：
- stock 2.8.42：五键全齐 exact、mask 必绑、gizmos 必含；
- reversedDirectionV1（`2131872317`）：方向基向量 `(0,-1)` 折算 +π；
- directV1（两个 fragment 指纹）与 reducedV2：基向量同 stock；
- legacy 族共同语义：常量可缺省（default 5/200/0.1/0）、`exponent` 键拒绝、
  `perspective` 仅接受 0、mask 可缺省（等价 mask=1）、v1 族 definition 无 gizmos。
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
import sys
from pathlib import Path

SOURCE_SET_SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SOURCE_SET_SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SOURCE_SET_SCRIPT_ROOT))

from scene_swift_source_sets import scene_swift_sources


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
AUTHORED_EFFECT_PLANNING_SOURCES = scene_swift_sources(
    "authored_effect_planning_support"
)
STOCK_SHADERS = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects/waterwaves/shaders/effects"
)
SWIFT_SOURCES = [
    *AUTHORED_EFFECT_PLANNING_SOURCES,
    SOURCE_ROOT / "RenderGraph/SceneWaterWavesShaderProfile.swift",
    SOURCE_ROOT / "RenderGraph/SceneWaterWavesAssetFamily.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredWaterWavesPlanner.swift",
]

# 由样本 pkg 提取的真实 legacy 源字节（生成脚本见本文件 git 历史；不得手写）。
LEGACY_SOURCES_JSON = REPOSITORY_ROOT / "script/tests/fixtures/waterwaves_legacy_shaders.json"


HARNESS = r'''
import Foundation
import simd

struct SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
    }
}

struct SceneEffectTextureInput { let name: String }

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }
        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }
    struct Layer {
        let id: Int
        let contentKind: String
        let effects: [EffectDescriptor]
    }
    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let materialRawSHA256: String
        let shaderPathIndependentSHA256: String
        let passIndex: Int
        let shaderPath: String?
        let texturePaths: [String]
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        var userShaderValues: [String: String] { [:] }
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String? = nil
    }
    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    static let definitionPath = "effects/waterwaves/effect.json"
    static let materialPath = "materials/effects/waterwaves.json"
    static let shaderIdentity = "effects/waterwaves"
    static let relocatedDefinitionPath =
        "effects/workshop/912345678/waterwaves/effect.json"
    static let relocatedMaterialPath =
        "materials/workshop/912345678/effects/waterwaves.json"
    static let relocatedShaderIdentity =
        "workshop/912345678/effects/waterwaves"

    struct Options {
        var constants: [String: SceneDocument.ShaderValue] = [
            "direction": value([1.5], kind: "number"),
            "speed": value([5], kind: "number"),
            "scale": value([200], kind: "number"),
            "exponent": value([1], kind: "number"),
            "strength": value([0.1], kind: "number"),
        ]
        var slots: [String?] = [nil, "masks/waves_mask_a"]
        var paths: [String] = ["masks/waves_mask_a"]
        var includeGizmos = true
        var contentKind = "image"
        var visible: Bool? = true
    }

    static func value(_ components: [Double], kind: String) -> SceneDocument.ShaderValue {
        .init(
            rawValue: components.map { String($0) }.joined(separator: " "),
            valueKind: kind,
            userBinding: nil,
            components: components
        )
    }

    static func gizmos() -> SceneJSONValue {
        .array([
            .object([
                "condition": .object(["PERSPECTIVE": .number(1)]),
                "type": .string("EffectPerspectiveUV"),
                "vars": .object([
                    "p0": .string("point0"),
                    "p1": .string("point1"),
                    "p2": .string("point2"),
                    "p3": .string("point3"),
                ]),
            ]),
        ])
    }

    static func descriptor(_ options: Options) -> SceneRenderDescriptor {
        descriptor(
            options,
            definitionPath: definitionPath,
            materialPath: materialPath,
            shaderIdentity: shaderIdentity,
            materialSemanticSHA256:
                "f07dfa1b7f21c1c99742c66dfa14ab8c747ebc78a1a7573680329950ad40e121"
        )
    }

    static func descriptor(
        _ options: Options,
        definitionPath: String,
        materialPath: String,
        shaderIdentity: String,
        materialSemanticSHA256: String
    ) -> SceneRenderDescriptor {
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            texturePaths: options.paths,
            textureSlots: options.slots,
            userTextureInputs: [],
            combos: [:],
            constantShaderValues: options.constants
        )
        let waves = SceneRenderDescriptor.EffectDescriptor(
            id: "20#effect#21",
            file: definitionPath,
            visible: options.visible,
            passes: [pass]
        )
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "\(materialPath)#0",
            materialPath: materialPath,
            materialRawSHA256:
                "2d465e099edb237ace15febe68a19eb833702a636972830bb43409e961c246b5",
            shaderPathIndependentSHA256: materialSemanticSHA256,
            passIndex: 0,
            shaderPath: shaderIdentity,
            texturePaths: [],
            textureSlots: [],
            userTextureInputs: [],
            combos: [:],
            constantShaderValues: [:],
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull"
        )
        let pass0 = SceneEffectDefinition.Pass(
            passIndex: 0,
            materialPath: materialPath,
            target: nil,
            bindings: [],
            compose: nil,
            command: nil,
            source: nil,
            conditions: nil,
            extraFields: [:]
        )
        let definition = SceneEffectDefinition(
            relativePath: definitionPath,
            version: 1,
            replacementKey: "waterwaves",
            name: "ui_editor_effect_water_waves_title",
            description: "ui_editor_effect_water_waves_description",
            group: "animate",
            performance: nil,
            previewPath: "preview/project.json",
            editable: nil,
            passes: [pass0],
            framebuffers: [],
            dependencies: [
                materialPath,
                "shaders/\(shaderIdentity).frag",
                "shaders/\(shaderIdentity).vert",
            ],
            functions: nil,
            gizmos: options.includeGizmos ? gizmos() : nil,
            extraFields: [:],
            unknownFieldPaths: []
        )
        return .init(
            layers: [.init(
                id: 20,
                contentKind: options.contentKind,
                effects: [waves]
            )],
            materialPasses: [material],
            effectDefinitions: [definition]
        )
    }

    static func texture(
        _ kind: Graph.TextureKind,
        effect: Graph.EffectKey? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: 20, effect: effect, name: nil)
    }

    static func graph() -> Graph {
        graph(definitionPath: definitionPath, materialPath: materialPath)
    }

    static func graph(definitionPath: String, materialPath: String) -> Graph {
        let key = Graph.EffectKey(
            layerID: 20, effectIndex: 0, descriptorID: "20#effect#21"
        )
        let input = texture(.layerSource)
        let output = texture(.effectOutput, effect: key)
        let node = Graph.Node(
            nodeIndex: 0,
            effect: key,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: materialPath,
            materialPassID: "\(materialPath)#0",
            target: output,
            bindings: [],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
        let effect = Graph.Effect(
            key: key,
            definitionPath: definitionPath,
            input: input,
            output: output,
            nodeIndices: [0]
        )
        return .init(
            layerID: 20,
            effects: [effect],
            renderTargets: [],
            nodes: [node],
            finalOutput: output,
            blockers: []
        )
    }

    static func planned(
        _ options: Options,
        contracts: [SceneShaderContract]
    ) -> SceneWaterWavesExecutionPlan? {
        SceneAuthoredWaterWavesPlanner.plan(
            graph: graph(),
            descriptor: descriptor(options),
            shaderContracts: contracts,
            inputRole: .layerSource
        )
    }

    static func relocatedPlan(
        _ options: Options,
        contracts: [SceneShaderContract],
        materialSemanticSHA256: String =
            "f07dfa1b7f21c1c99742c66dfa14ab8c747ebc78a1a7573680329950ad40e121"
    ) -> SceneWaterWavesExecutionPlan? {
        SceneAuthoredWaterWavesPlanner.plan(
            graph: graph(
                definitionPath: relocatedDefinitionPath,
                materialPath: relocatedMaterialPath
            ),
            descriptor: descriptor(
                options,
                definitionPath: relocatedDefinitionPath,
                materialPath: relocatedMaterialPath,
                shaderIdentity: relocatedShaderIdentity,
                materialSemanticSHA256: materialSemanticSHA256
            ),
            shaderContracts: contracts,
            inputRole: .layerSource
        )
    }

    static func main() throws {
        let roots = CommandLine.arguments.dropFirst().map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let loader = SceneShaderContractLoader()
        // 顺序：stock, reversed(v1-b), directV1(v1-c), directV1MaskCombo(v1-d), v2
        let contracts = roots.prefix(5).map {
            loader.load(shaderReferences: [shaderIdentity], rootURL: $0)
        }
        let relocatedContracts = loader.load(
            shaderReferences: [relocatedShaderIdentity],
            rootURL: roots[5]
        )
        let mutatedContracts = loader.load(
            shaderReferences: [shaderIdentity],
            rootURL: roots[6]
        )
        let profiles = contracts.map { SceneWaterWavesShaderProfile.resolve($0) }

        var stockOptions = Options()
        let stockPlan = planned(stockOptions, contracts: contracts[0])

        var legacyFull = Options()
        legacyFull.includeGizmos = false
        legacyFull.constants = [
            "direction": value([1.5], kind: "number"),
            "speed": value([3], kind: "number"),
            "scale": value([100], kind: "number"),
            "strength": value([0.2], kind: "number"),
            "perspective": value([0], kind: "number"),
        ]
        let reversedPlan = planned(legacyFull, contracts: contracts[1])

        var legacyOmitted = Options()
        legacyOmitted.includeGizmos = false
        legacyOmitted.constants = ["strength": value([0.05], kind: "number")]
        let omittedPlan = planned(legacyOmitted, contracts: contracts[2])

        var legacyNoMask = Options()
        legacyNoMask.includeGizmos = false
        legacyNoMask.constants = [:]
        legacyNoMask.slots = []
        legacyNoMask.paths = []
        let noMaskPlan = planned(legacyNoMask, contracts: contracts[3])

        var v2Options = Options()
        v2Options.constants = [
            "direction": value([0.5], kind: "number"),
            "speed": value([5], kind: "number"),
            "scale": value([200], kind: "number"),
            "strength": value([0.1], kind: "number"),
            "perspective": value([0], kind: "number"),
        ]
        let v2Plan = planned(v2Options, contracts: contracts[4])

        var relocatedOptions = legacyFull
        let relocatedExecution = relocatedPlan(
            relocatedOptions,
            contracts: relocatedContracts
        )

        var legacyExponent = Options()
        legacyExponent.includeGizmos = false
        legacyExponent.constants = [
            "exponent": value([2], kind: "number"),
            "strength": value([0.1], kind: "number"),
        ]
        var legacyPerspective = Options()
        legacyPerspective.includeGizmos = false
        legacyPerspective.constants = [
            "perspective": value([0.1], kind: "number"),
            "strength": value([0.1], kind: "number"),
        ]
        var legacyUnknownKey = Options()
        legacyUnknownKey.includeGizmos = false
        legacyUnknownKey.constants = [
            "ui_editor_properties_strength": value([0.1], kind: "number")
        ]
        var stockOmitted = Options()
        stockOmitted.constants = ["strength": value([0.1], kind: "number")]
        var stockNoMask = Options()
        stockNoMask.slots = []
        stockNoMask.paths = []
        var legacyWithGizmos = Options()
        legacyWithGizmos.includeGizmos = true
        legacyWithGizmos.constants = ["strength": value([0.05], kind: "number")]
        var stockWithoutGizmos = Options()
        stockWithoutGizmos.includeGizmos = false

        let result: [String: Any] = [
            "profilesResolved": profiles[0] == .stock2842
                && profiles[1] == .reversedDirectionV1
                && profiles[2] == .directV1
                && profiles[3] == .directV1
                && profiles[4] == .reducedV2,
            "dedicatedFallbackRetainedOnlyForLegacy":
                !profiles[0]!.retainsDedicatedFallback
                && profiles[1]!.retainsDedicatedFallback
                && profiles[2]!.retainsDedicatedFallback
                && profiles[3]!.retainsDedicatedFallback
                && profiles[4]!.retainsDedicatedFallback,
            "reversedDirectionOffset": profiles[1]!.directionOffset == Float.pi
                && profiles[2]!.directionOffset == 0
                && profiles[4]!.directionOffset == 0
                && profiles[0]!.directionOffset == 0,
            "stockPlanned": stockPlan != nil
                && stockPlan!.shaderProfile == .stock2842
                && stockPlan!.direction == 1.5
                && stockPlan!.maskTexturePath == "masks/waves_mask_a",
            "reversedPlanApplied": reversedPlan != nil
                && reversedPlan!.shaderProfile == .reversedDirectionV1
                && reversedPlan!.direction == 1.5 + Float.pi
                && reversedPlan!.exponent == 1
                && reversedPlan!.speed == 3
                && reversedPlan!.scale == 100
                && reversedPlan!.strength == 0.2,
            "omittedDefaultsApplied": omittedPlan != nil
                && omittedPlan!.direction == 0
                && omittedPlan!.speed == 5
                && omittedPlan!.scale == 200
                && omittedPlan!.strength == 0.05
                && omittedPlan!.exponent == 1,
            "noMaskPlanned": noMaskPlan != nil
                && noMaskPlan!.maskTexturePath == nil
                && noMaskPlan!.strength == 0.1,
            "v2Planned": v2Plan != nil
                && v2Plan!.shaderProfile == .reducedV2
                && v2Plan!.direction == 0.5,
            "relocatedAnnotationOrderPlanned": relocatedExecution != nil
                && relocatedExecution!.shaderProfile == .directV1
                && relocatedExecution!.direction == 1.5
                && relocatedExecution!.maskTexturePath == "masks/waves_mask_a",
            "relocatedAssetFamilyDerived": {
                guard let assets = SceneWaterWavesAssetFamily(
                    definitionPath: relocatedDefinitionPath
                ) else { return false }
                return assets.materialPath == relocatedMaterialPath
                    && assets.shaderIdentity == relocatedShaderIdentity
                    && assets.dependencies == [
                        relocatedMaterialPath,
                        "shaders/\(relocatedShaderIdentity).frag",
                        "shaders/\(relocatedShaderIdentity).vert",
                    ]
                    && SceneWaterWavesAssetFamily(
                        definitionPath: "effects/workshop/../waterwaves/effect.json"
                    ) == nil
            }(),
            "relocatedMaterialShapeRejected": relocatedPlan(
                relocatedOptions,
                contracts: relocatedContracts,
                materialSemanticSHA256: "wrong"
            ) == nil,
            "shaderMathMutationRejected": SceneWaterWavesShaderProfile.resolve(
                mutatedContracts
            ) == nil,
            "legacyExponentRejected": planned(
                legacyExponent, contracts: contracts[1]
            ) == nil,
            "legacyPerspectiveNonZeroRejected": planned(
                legacyPerspective, contracts: contracts[1]
            ) == nil,
            "legacyUnknownKeyRejected": planned(
                legacyUnknownKey, contracts: contracts[1]
            ) == nil,
            "stockOmittedRejected": planned(stockOmitted, contracts: contracts[0]) == nil,
            "stockNoMaskRejected": planned(stockNoMask, contracts: contracts[0]) == nil,
            "gizmosMismatchRejected": planned(
                legacyWithGizmos, contracts: contracts[1]
            ) == nil
                && planned(stockWithoutGizmos, contracts: contracts[0]) == nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: result.mapValues { $0 as Any })
        print(String(data: data, encoding: .utf8)!)
    }
}
'''


class SceneWaterWavesProfileTests(unittest.TestCase):
    def test_profiles(self) -> None:
        swiftc = shutil.which("swiftc")
        self.assertIsNotNone(swiftc, "swiftc unavailable")
        legacy = json.loads(LEGACY_SOURCES_JSON.read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            roots: list[Path] = []
            stock_root = root / "stock"
            shader_dir = stock_root / "shaders/effects"
            shader_dir.mkdir(parents=True)
            shutil.copy(STOCK_SHADERS / "waterwaves.vert", shader_dir / "waterwaves.vert")
            shutil.copy(STOCK_SHADERS / "waterwaves.frag", shader_dir / "waterwaves.frag")
            roots.append(stock_root)
            for name in ("reversed", "direct-v1", "direct-v1-maskcombo", "v2"):
                entry = legacy[name]
                variant_root = root / name
                variant_dir = variant_root / "shaders/effects"
                variant_dir.mkdir(parents=True)
                import base64

                (variant_dir / "waterwaves.vert").write_bytes(
                    base64.b64decode(entry["vert"])
                )
                (variant_dir / "waterwaves.frag").write_bytes(
                    base64.b64decode(entry["frag"])
                )
                roots.append(variant_root)

            import base64

            relocated_root = root / "relocated"
            relocated_dir = (
                relocated_root / "shaders/workshop/912345678/effects"
            )
            relocated_dir.mkdir(parents=True)
            direct = legacy["direct-v1"]
            (relocated_dir / "waterwaves.vert").write_bytes(
                base64.b64decode(direct["vert"])
            )
            direct_fragment = base64.b64decode(direct["frag"])
            original_annotation = (
                b'{"material":"mask","label":"ui_editor_properties_opacity_mask",'
                b'"mode":"opacitymask","default":"util/white",'
                b'"paintdefaultcolor":"0 0 0 1"}'
            )
            reordered_annotation = (
                b'{"default":"util/white","label":"ui_editor_properties_opacity_mask",'
                b'"material":"mask","mode":"opacitymask",'
                b'"paintdefaultcolor":"0 0 0 1"}'
            )
            self.assertIn(original_annotation, direct_fragment)
            (relocated_dir / "waterwaves.frag").write_bytes(
                direct_fragment.replace(original_annotation, reordered_annotation)
            )
            roots.append(relocated_root)

            mutated_root = root / "mutated"
            mutated_dir = mutated_root / "shaders/effects"
            mutated_dir.mkdir(parents=True)
            (mutated_dir / "waterwaves.vert").write_bytes(
                base64.b64decode(direct["vert"])
            )
            self.assertIn(b"sin(distance)", direct_fragment)
            (mutated_dir / "waterwaves.frag").write_bytes(
                direct_fragment.replace(b"sin(distance)", b"cos(distance)")
            )
            roots.append(mutated_root)

            harness = root / "Harness.swift"
            executable = root / "waterwaves-harness"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    swiftc,
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-o",
                    str(executable),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(executable), *(str(path) for path in roots)],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                completed.returncode, 0,
                f"stdout={completed.stdout}\nstderr={completed.stderr}",
            )

        output = json.loads(completed.stdout)
        self.assertTrue(output)
        self.assertTrue(all(output.values()), output)


if __name__ == "__main__":
    unittest.main()
