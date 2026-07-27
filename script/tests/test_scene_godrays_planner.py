#!/usr/bin/env python3
"""godrays planner 的 fail-closed 准入测试。

exact stock 5-pass / 2-half-RT profile：`CASTER=1`（Directional）、`COPYBG`、
`NOISE=0`、named-RT 实例绑定（`1937925563` 形态）、指纹变异与 RT 形状错误全部拒绝；
常量子集缺省回填注解默认，`SAMPLES`/`KERNEL` combo 与遮罩为受限正门。
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
STOCK_ROOT = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects/godrays"
)
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContractLoader.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Effects/SceneBlendModeShaderSource.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredGodraysPlanner.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredGodraysPlanner+Constants.swift",
]


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
        let passIndex: Int
        let shaderPath: String?
        let texturePaths: [String]
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
    }
    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    static let definitionPath = "effects/godrays/effect.json"
    static let materialPaths = [
        "materials/effects/godrays_downsample2.json",
        "materials/effects/godrays_cast.json",
        "materials/effects/godrays_gaussian_x.json",
        "materials/effects/godrays_gaussian_y.json",
        "materials/effects/godrays_combine.json",
    ]
    static let shaderIdentities = [
        "effects/godrays_downsample2",
        "effects/godrays_cast",
        "effects/godrays_gaussian",
        "effects/godrays_gaussian",
        "effects/godrays_combine",
    ]

    struct Options {
        var pass0Constants: [String: SceneDocument.ShaderValue] = [:]
        var pass1Constants: [String: SceneDocument.ShaderValue] = [:]
        var blurConstants: [String: SceneDocument.ShaderValue] = [:]
        var pass0Combos: [String: Int] = [:]
        var pass1Combos: [String: Int] = [:]
        var gaussianXCombos: [String: Int] = [:]
        var gaussianYCombos: [String: Int] = ["VERTICAL": 1]
        var combineCombos: [String: Int] = [:]
        var pass0Slots: [String?] = []
        var pass0Paths: [String] = []
        var combineSlots: [String?] = []
        var combinePaths: [String] = []
        var rtScale = 2
        var rtFormat = "rgba_backbuffer"
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

    static func descriptor(_ options: Options) -> SceneRenderDescriptor {
        let passCombos = [
            options.pass0Combos, options.pass1Combos,
            options.gaussianXCombos, options.gaussianYCombos, options.combineCombos,
        ]
        let passConstants = [
            options.pass0Constants, options.pass1Constants,
            options.blurConstants, options.blurConstants, [:],
        ]
        let passSlots: [[String?]] = [
            options.pass0Slots, [], [], [], options.combineSlots,
        ]
        let passPaths: [[String]] = [
            options.pass0Paths, [], [], [], options.combinePaths,
        ]
        let passes = (0 ..< 5).map { index in
            SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
                passIndex: index,
                texturePaths: passPaths[index],
                textureSlots: passSlots[index],
                userTextureInputs: [],
                combos: passCombos[index],
                constantShaderValues: passConstants[index]
            )
        }
        let godrays = SceneRenderDescriptor.EffectDescriptor(
            id: "20#effect#21",
            file: definitionPath,
            visible: options.visible,
            passes: passes
        )
        let materials = materialPaths.enumerated().map { index, path in
            SceneRenderDescriptor.MaterialPassDescriptor(
                id: "\(path)#0",
                materialPath: path,
                materialRawSHA256: "",
                passIndex: 0,
                shaderPath: shaderIdentities[index],
                texturePaths: [],
                textureSlots: [],
                userTextureInputs: [],
                combos: index == 3 ? ["VERTICAL": 1] : [:],
                constantShaderValues: [:],
                blending: "normal",
                depthTest: "disabled",
                depthWrite: "disabled",
                cullMode: "nocull"
            )
        }
        let definitionPasses = (0 ..< 5).map { index in
            SceneEffectDefinition.Pass(
                passIndex: index,
                materialPath: materialPaths[index],
                target: [
                    "_rt_HalfCompoBuffer1", "_rt_HalfCompoBuffer2",
                    "_rt_HalfCompoBuffer1", "_rt_HalfCompoBuffer2", nil,
                ][index],
                bindings: [],
                compose: nil,
                command: nil,
                source: nil,
                conditions: nil,
                extraFields: [:]
            )
        }
        let definition = SceneEffectDefinition(
            relativePath: definitionPath,
            version: 1,
            replacementKey: "godrays",
            name: "ui_editor_effect_godrays_title",
            description: "ui_editor_effect_godrays_description",
            group: "enhance",
            performance: "expensive",
            previewPath: "preview/project.json",
            editable: nil,
            passes: definitionPasses,
            framebuffers: [
                .init(
                    name: "_rt_HalfCompoBuffer1", scale: .number(2), width: nil,
                    height: nil, fit: nil, format: "rgba_backbuffer", unique: nil,
                    clear: nil, uvs: nil, conditions: nil, extraFields: [:]
                ),
                .init(
                    name: "_rt_HalfCompoBuffer2", scale: .number(2), width: nil,
                    height: nil, fit: nil, format: "rgba_backbuffer", unique: nil,
                    clear: nil, uvs: nil, conditions: nil, extraFields: [:]
                ),
            ],
            dependencies: [],
            functions: nil,
            gizmos: nil,
            extraFields: [:],
            unknownFieldPaths: []
        )
        return .init(
            layers: [.init(
                id: 20, contentKind: options.contentKind, effects: [godrays]
            )],
            materialPasses: materials,
            effectDefinitions: [definition]
        )
    }

    static func texture(
        _ kind: Graph.TextureKind,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: 20, effect: effect, name: name)
    }

    static func graph(_ options: Options) -> Graph {
        let key = Graph.EffectKey(
            layerID: 20, effectIndex: 0, descriptorID: "20#effect#21"
        )
        let input = texture(.layerSource)
        let output = texture(.effectOutput, effect: key)
        let half1 = texture(.framebuffer, effect: key, name: "_rt_halfcompobuffer1")
        let half2 = texture(.framebuffer, effect: key, name: "_rt_halfcompobuffer2")
        let targets = [half1, half2, half1, half2, output]
        let bindings: [[Graph.Binding]] = [
            [.init(slot: 0, authoredName: "previous", texture: input, conditions: nil)],
            [.init(slot: 0, authoredName: "_rt_HalfCompoBuffer1", texture: half1, conditions: nil)],
            [.init(slot: 0, authoredName: "_rt_HalfCompoBuffer2", texture: half2, conditions: nil)],
            [.init(slot: 0, authoredName: "_rt_HalfCompoBuffer1", texture: half1, conditions: nil)],
            [
                .init(slot: 0, authoredName: "_rt_HalfCompoBuffer2", texture: half2, conditions: nil),
                .init(slot: 1, authoredName: "previous", texture: input, conditions: nil),
            ],
        ]
        let nodes = (0 ..< 5).map { index in
            Graph.Node(
                nodeIndex: index,
                effect: key,
                definitionPassIndex: index,
                materialOrdinal: index,
                instancePassIndex: index,
                kind: .material,
                materialPath: materialPaths[index],
                materialPassID: "\(materialPaths[index])#0",
                target: targets[index],
                bindings: bindings[index],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            )
        }
        let effect = Graph.Effect(
            key: key,
            definitionPath: definitionPath,
            input: input,
            output: output,
            nodeIndices: Array(0 ..< 5)
        )
        let renderTargets = [half1, half2].map { identity in
            Graph.RenderTarget(
                texture: identity,
                extent: .init(kind: .scale, first: Double(options.rtScale), second: nil),
                format: options.rtFormat,
                declaredUnique: false,
                clear: nil,
                uvs: nil,
                conditions: nil
            )
        }
        return .init(
            layerID: 20,
            effects: [effect],
            renderTargets: renderTargets,
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
    }

    static func planned(
        _ options: Options,
        contracts: [SceneShaderContract]
    ) -> SceneGodraysPlan? {
        SceneAuthoredGodraysPlanner.plan(
            graph: graph(options),
            descriptor: descriptor(options),
            shaderContracts: contracts,
            inputRole: .layerSource
        )
    }

    static func mutate(
        _ contracts: [SceneShaderContract],
        identity: String
    ) -> [SceneShaderContract] {
        contracts.map { contract in
            guard contract.identity == identity else { return contract }
            return SceneShaderContract(
                identity: contract.identity,
                sourceKind: contract.sourceKind,
                stages: contract.stages,
                diagnostics: contract.diagnostics,
                canonicalSHA256: String(repeating: "0", count: 64)
            )
        }
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let contracts = SceneShaderContractLoader().load(
            shaderReferences: [
                "effects/godrays_downsample2", "effects/godrays_cast",
                "effects/godrays_gaussian", "effects/godrays_combine",
            ],
            rootURL: root
        )

        let defaults = planned(Options(), contracts: contracts)
        var full = Options()
        full.pass0Constants = [
            "raythreshold": value([0.3], kind: "number"),
            "noiseamount": value([0.6], kind: "number"),
            "noisescale": value([5], kind: "number"),
            "noisespeed": value([0.2], kind: "number"),
            "noisesmoothness": value([0.3], kind: "number"),
        ]
        full.pass1Constants = [
            "center": value([0.4, 0.6], kind: "vector"),
            "color": value([1, 0.5, 0.2], kind: "vector"),
            "raylength": value([0.8], kind: "number"),
            "rayintensity": value([1.5], kind: "number"),
        ]
        full.blurConstants = ["blurscale": value([1.2, 0.8], kind: "vector")]
        let fullPlan = planned(full, contracts: contracts)

        var masked = Options()
        masked.pass0Slots = [nil, "masks/godrays_mask_a", nil]
        masked.pass0Paths = ["masks/godrays_mask_a"]
        let maskedPlan = planned(masked, contracts: contracts)

        var samples50 = Options()
        samples50.pass1Combos = ["SAMPLES": 1]
        var kernel13 = Options()
        kernel13.gaussianXCombos = ["KERNEL": 0]
        kernel13.gaussianYCombos = ["KERNEL": 0, "VERTICAL": 1]
        var directional = Options()
        directional.pass1Combos = ["CASTER": 1]
        var copybg = Options()
        copybg.combineCombos = ["COPYBG": 1]
        var noiseOff = Options()
        noiseOff.pass0Combos = ["NOISE": 0]
        var namedRT = Options()
        namedRT.combineSlots = [nil, "_rt_imageLayerComposite_13_a"]
        namedRT.combinePaths = ["_rt_imageLayerComposite_13_a"]
        var kernelMismatch = Options()
        kernelMismatch.gaussianXCombos = ["KERNEL": 0]
        var quarterRT = Options()
        quarterRT.rtScale = 4
        var wrongFormat = Options()
        wrongFormat.rtFormat = "rgba8888"
        var hidden = Options()
        hidden.visible = false
        var badThreshold = Options()
        badThreshold.pass0Constants = ["raythreshold": value([1.5], kind: "number")]

        let result: [String: Any] = [
            "defaultsPlanned": defaults != nil
                && defaults!.threshold == 0.5
                && defaults!.noiseAmount == 0.4
                && defaults!.noiseScale == 3
                && defaults!.noiseSpeed == 0.15
                && defaults!.noiseSmoothness == 0.2
                && defaults!.center == SIMD2<Float>(0.5, 0.5)
                && defaults!.rayLength == 0.5
                && defaults!.rayIntensity == 1
                && defaults!.samples50 == false
                && defaults!.kernel13 == false
                && defaults!.blendMode == 9
                && defaults!.maskTexturePath == nil,
            "fullConstantsPlanned": fullPlan != nil
                && fullPlan!.threshold == 0.3
                && fullPlan!.center == SIMD2<Float>(0.4, 0.6)
                && fullPlan!.colorRays == SIMD3<Float>(1, 0.5, 0.2)
                && fullPlan!.rayLength == 0.8
                && fullPlan!.rayIntensity == 1.5
                && fullPlan!.blurScaleX == SIMD2<Float>(1.2, 0.8),
            "maskPlanned": maskedPlan != nil
                && maskedPlan!.maskTexturePath == "masks/godrays_mask_a",
            "samples50Planned": planned(samples50, contracts: contracts)?.samples50 == true,
            "kernel13Planned": planned(kernel13, contracts: contracts)?.kernel13 == true,
            "directionalRejected": planned(directional, contracts: contracts) == nil,
            "copybgRejected": planned(copybg, contracts: contracts) == nil,
            "noiseOffRejected": planned(noiseOff, contracts: contracts) == nil,
            "namedRTRejected": planned(namedRT, contracts: contracts) == nil,
            "kernelMismatchRejected": planned(kernelMismatch, contracts: contracts) == nil,
            "quarterRTRejected": planned(quarterRT, contracts: contracts) == nil,
            "wrongFormatRejected": planned(wrongFormat, contracts: contracts) == nil,
            "hiddenRejected": planned(hidden, contracts: contracts) == nil,
            "thresholdRangeRejected": planned(badThreshold, contracts: contracts) == nil,
            "contractRejected": [
                "effects/godrays_downsample2", "effects/godrays_cast",
                "effects/godrays_gaussian", "effects/godrays_combine",
            ].allSatisfy { identity in
                planned(Options(), contracts: mutate(contracts, identity: identity)) == nil
            },
        ]
        let data = try JSONSerialization.data(withJSONObject: result.mapValues { $0 as Any })
        print(String(data: data, encoding: .utf8)!)
    }
}
'''


class SceneGodraysPlannerTests(unittest.TestCase):
    def test_planner(self) -> None:
        swiftc = shutil.which("swiftc")
        self.assertIsNotNone(swiftc, "swiftc unavailable")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shader_dir = root / "stock/shaders/effects"
            shader_dir.mkdir(parents=True)
            for shader in (STOCK_ROOT / "shaders/effects").iterdir():
                shutil.copy(shader, shader_dir / shader.name)
            harness = root / "Harness.swift"
            executable = root / "godrays-harness"
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
                [str(executable), str(root / "stock")],
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
