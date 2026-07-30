#!/usr/bin/env python3
"""Strict stock Shine graph admission and static-parameter boundary."""

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
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects/shine"
)
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContractLoader.swift",
    SOURCE_ROOT / "Effects/SceneBlendModeShaderSource.swift",
    SOURCE_ROOT / "RenderGraph/SceneShineExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredShinePlanner.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredShinePlanner+Constants.swift",
]


HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
        let timeline: Bool?
        let timelineDiagnostics: [String]
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
        let alphaWriting: String? = nil
    }
    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    static let definitionPath = "effects/shine/effect.json"
    static let materialPaths = [
        "materials/effects/shine_downsample2.json",
        "materials/effects/shine_cast.json",
        "materials/effects/shine_gaussian_x.json",
        "materials/effects/shine_gaussian_y.json",
        "materials/effects/shine_combine.json",
    ]
    static let shaderIdentities = [
        "effects/shine_downsample2",
        "effects/shine_cast",
        "effects/shine_gaussian",
        "effects/shine_gaussian",
        "effects/shine_combine",
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
        var rtFormat = "rgba_backbuffer"
        var definitionPerformance: String? = "expensive"
        var visible: Bool? = true
    }

    static func value(
        _ components: [Double],
        kind: String? = nil,
        timeline: Bool? = nil
    ) -> SceneDocument.ShaderValue {
        .init(
            rawValue: components.map { String($0) }.joined(separator: " "),
            valueKind: kind ?? (components.count == 1 ? "number" : "vector"),
            userBinding: nil,
            components: components,
            timeline: timeline,
            timelineDiagnostics: []
        )
    }

    static func definition(
        stockRoot: URL,
        options: Options
    ) throws -> SceneEffectDefinition {
        let loaded = try SceneEffectDefinitionLoader().load(
            from: stockRoot.appendingPathComponent("effect.json"),
            relativePath: definitionPath
        )
        let framebuffers = loaded.framebuffers.map {
            SceneEffectDefinition.Framebuffer(
                name: $0.name,
                scale: $0.scale,
                width: $0.width,
                height: $0.height,
                fit: $0.fit,
                format: options.rtFormat,
                unique: $0.unique,
                clear: $0.clear,
                uvs: $0.uvs,
                conditions: $0.conditions,
                extraFields: $0.extraFields
            )
        }
        return SceneEffectDefinition(
            relativePath: loaded.relativePath,
            version: loaded.version,
            replacementKey: loaded.replacementKey,
            name: loaded.name,
            description: loaded.description,
            group: loaded.group,
            performance: options.definitionPerformance,
            previewPath: loaded.previewPath,
            editable: loaded.editable,
            passes: loaded.passes,
            framebuffers: framebuffers,
            dependencies: loaded.dependencies,
            functions: loaded.functions,
            gizmos: loaded.gizmos,
            extraFields: loaded.extraFields,
            unknownFieldPaths: loaded.unknownFieldPaths
        )
    }

    static func descriptor(
        stockRoot: URL,
        options: Options
    ) throws -> SceneRenderDescriptor {
        let passCombos = [
            options.pass0Combos, options.pass1Combos,
            options.gaussianXCombos, options.gaussianYCombos,
            options.combineCombos,
        ]
        let passConstants = [
            options.pass0Constants, options.pass1Constants,
            options.blurConstants, options.blurConstants, [:],
        ]
        let passes = (0 ..< 5).map { index in
            SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
                passIndex: index,
                texturePaths: index == 0 ? options.pass0Paths : [],
                textureSlots: index == 0 ? options.pass0Slots : [],
                userTextureInputs: [],
                combos: passCombos[index],
                constantShaderValues: passConstants[index]
            )
        }
        let effect = SceneRenderDescriptor.EffectDescriptor(
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
        return .init(
            layers: [.init(id: 20, contentKind: "image", effects: [effect])],
            materialPasses: materials,
            effectDefinitions: [try definition(stockRoot: stockRoot, options: options)]
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
        return Graph(
            layerID: 20,
            effects: [.init(
                key: key,
                definitionPath: definitionPath,
                input: input,
                output: output,
                nodeIndices: Array(0 ..< 5)
            )],
            renderTargets: [half1, half2].map {
                .init(
                    texture: $0,
                    extent: .init(kind: .scale, first: 2, second: nil),
                    format: options.rtFormat,
                    declaredUnique: false,
                    clear: nil,
                    uvs: nil,
                    conditions: nil
                )
            },
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
    }

    static func planned(
        stockRoot: URL,
        options: Options,
        contracts: [SceneShaderContract]
    ) throws -> SceneShineExecutionPlan? {
        SceneAuthoredShinePlanner.plan(
            graph: graph(options),
            descriptor: try descriptor(stockRoot: stockRoot, options: options),
            shaderContracts: contracts
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
        let stockRoot = URL(
            fileURLWithPath: CommandLine.arguments[1],
            isDirectory: true
        )
        let contracts = SceneShaderContractLoader().load(
            shaderReferences: [
                "effects/shine_downsample2",
                "effects/shine_cast",
                "effects/shine_gaussian",
                "effects/shine_combine",
            ],
            rootURL: stockRoot
        )

        var positive = Options()
        positive.pass0Slots = [nil, "masks/shine", nil]
        positive.pass0Paths = ["masks/shine"]
        positive.pass0Constants = [
            "raythreshold": value([0.37]),
            "noiseamount": value([0.9]),
            "noisescale": value([2.27]),
            "noisespeed": value([0.09]),
        ]
        positive.pass1Combos = ["EDGES": 5, "SAMPLES": 3]
        positive.pass1Constants = [
            "color": value([0.9, 0.2, 0.2]),
            "direction": value([0.86]),
            "rayintensity": value([0.45]),
            "raylength": value([0.05]),
            "speed": value([0.1]),
        ]
        positive.blurConstants = ["scale": value([1.5, 1.5])]
        let plan = try planned(
            stockRoot: stockRoot,
            options: positive,
            contracts: contracts
        )

        var dynamic = positive
        dynamic.pass1Constants["rayintensity"] = value(
            [0.45], kind: "binding", timeline: true
        )
        var copyBackground = positive
        copyBackground.combineCombos = ["COPYBG": 1]
        var wrongNoise = positive
        wrongNoise.pass0Slots = [nil, "masks/shine", "util/noise"]
        wrongNoise.pass0Paths = ["masks/shine", "util/noise"]
        var legacyDefinition = positive
        legacyDefinition.definitionPerformance = nil
        legacyDefinition.rtFormat = "rgba8888"
        var smallKernel = positive
        smallKernel.gaussianXCombos = ["KERNEL": 2]
        smallKernel.gaussianYCombos = ["KERNEL": 2, "VERTICAL": 1]

        let result: [String: Any] = [
            "positive": plan != nil,
            "edgeCount": plan?.edgeCount ?? -1,
            "sampleCount": plan?.sampleCount ?? -1,
            "kernelRadius": plan?.kernelRadius ?? -1,
            "masked": plan?.maskTexturePath == "masks/shine",
            "unmasked": try planned(
                stockRoot: stockRoot,
                options: Options(),
                contracts: contracts
            ) != nil,
            "smallKernel": try planned(
                stockRoot: stockRoot,
                options: smallKernel,
                contracts: contracts
            )?.kernelRadius == 1,
            "dynamicRejected": try planned(
                stockRoot: stockRoot,
                options: dynamic,
                contracts: contracts
            ) == nil,
            "copyBackgroundRejected": try planned(
                stockRoot: stockRoot,
                options: copyBackground,
                contracts: contracts
            ) == nil,
            "unknownNoiseRejected": try planned(
                stockRoot: stockRoot,
                options: wrongNoise,
                contracts: contracts
            ) == nil,
            "legacyDefinitionRejected": try planned(
                stockRoot: stockRoot,
                options: legacyDefinition,
                contracts: contracts
            ) == nil,
            "fingerprintRejected": try planned(
                stockRoot: stockRoot,
                options: positive,
                contracts: mutate(contracts, identity: "effects/shine_cast")
            ) == nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneShinePlannerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("xcrun") is None:
            raise unittest.SkipTest("xcrun is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-shine-planner-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        cls.binary = root / "scene-shine-planner"
        harness.write_text(HARNESS, encoding="utf-8")
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_strict_stock_static_profile(self) -> None:
        completed = subprocess.run(
            [str(self.binary), str(STOCK_ROOT)],
            check=True,
            capture_output=True,
            text=True,
        )
        result = json.loads(completed.stdout)
        self.assertEqual(
            result,
            {
                "copyBackgroundRejected": True,
                "dynamicRejected": True,
                "edgeCount": 5,
                "fingerprintRejected": True,
                "kernelRadius": 6,
                "legacyDefinitionRejected": True,
                "masked": True,
                "positive": True,
                "sampleCount": 30,
                "smallKernel": True,
                "unknownNoiseRejected": True,
                "unmasked": True,
            },
        )


if __name__ == "__main__":
    unittest.main()
