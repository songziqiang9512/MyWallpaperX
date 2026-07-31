#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
STOCK_EFFECT_ROOT = (
    ROOT / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects/lightshafts"
)
SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContractLoader.swift",
    SCENE_ROOT / "RenderGraph/SceneLightShaftsExecutionPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredLightShaftsPlanner.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredLightShaftsPlanner+AssetValidation.swift",
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
        let childLayerIDs: [Int]
        let dependencyLayerIDs: [Int]
        let hasInlineScript: Bool
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
        let userShaderValues: [String: String]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?
    }
    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    static let definitionPath = "effects/lightshafts/effect.json"
    static let materialPath = "materials/effects/lightshafts.json"
    static let shaderIdentity = "effects/lightshafts"

    struct Options {
        var contentKind = "quad"
        var materialHash =
            "87c0abe860543b15dbc04606034484c7d1061e526af08388bd6945869985a078"
        var directDraw = 1
        var rendering: Int? = 1
        var rayMode: Int?
        var extraCombo = false
        var extraConstant = false
        var texture = false
        var binding = false
        var child = false
        var dependency = false
        var inlineScript = false
        var visible: Bool? = true
        var intensity = 1.21
        var radius = 0.14
        var noiseAmount = 0.33
        var noiseScale = 1.17
        var startAngle = 0.0
        var endAngle = 1.0
        var degeneratePoints = false
    }

    static func scalar(_ value: Double, binding: Bool = false) -> SceneDocument.ShaderValue {
        .init(
            rawValue: String(value),
            valueKind: binding ? "binding" : "number",
            userBinding: binding ? "property" : nil,
            components: [value]
        )
    }

    static func vector(_ values: [Double]) -> SceneDocument.ShaderValue {
        .init(
            rawValue: values.map { String($0) }.joined(separator: " "),
            valueKind: "vector",
            userBinding: nil,
            components: values
        )
    }

    static func constants(_ options: Options) -> [String: SceneDocument.ShaderValue] {
        let points = options.degeneratePoints
            ? Array(repeating: [0.5, 0.5], count: 4)
            : [[0.4, 0.25], [0.6, 0.25], [0.8, 0.8], [0.2, 0.8]]
        var values: [String: SceneDocument.ShaderValue] = [
            "colorastart": vector([1, 1, 1]),
            "colorend": vector([0.435294, 0.886274, 1]),
            "colorwexponent": scalar(options.rayMode == 1 ? 0 : 0.49),
            "colorwintensity": scalar(options.intensity, binding: options.binding),
            "noiseamount": scalar(options.noiseAmount),
            "noisescale": scalar(options.noiseScale),
            "point0": vector(points[0]),
            "point1": vector(points[1]),
            "point2": vector(points[2]),
            "point3": vector(points[3]),
            "rayfeather": vector([0.31, 0.31]),
            "rayradius": scalar(options.radius),
            "rayscale": vector([0.8, 0.2]),
            "raysmoothness": scalar(0.68),
            "rayspeed": scalar(0.39),
        ]
        if options.rayMode == 1 {
            values["rayzstartangle"] = scalar(options.startAngle)
            values["rayzzendangle"] = scalar(options.endAngle)
        }
        if options.extraConstant { values["other"] = scalar(1) }
        return values
    }

    static func combos(_ options: Options) -> [String: Int] {
        var values = ["DIRECTDRAW": options.directDraw]
        if let rendering = options.rendering { values["RENDERING"] = rendering }
        if let rayMode = options.rayMode { values["RAYMODE"] = rayMode }
        if options.extraCombo { values["UNKNOWN"] = 1 }
        return values
    }

    static func definition() -> SceneEffectDefinition {
        .init(
            relativePath: definitionPath,
            version: 1,
            replacementKey: "lightshafts",
            name: "ui_editor_effect_light_shafts_title",
            description: "ui_editor_effect_light_shafts_description",
            group: "colorize",
            performance: nil,
            previewPath: "preview/project.json",
            editable: nil,
            passes: [.init(
                passIndex: 0,
                materialPath: materialPath,
                target: nil,
                bindings: [],
                compose: nil,
                command: nil,
                source: nil,
                conditions: nil,
                extraFields: [:]
            )],
            framebuffers: [],
            dependencies: [
                materialPath,
                "shaders/effects/lightshafts.frag",
                "shaders/effects/lightshafts.vert",
            ],
            functions: nil,
            gizmos: .array([.object([
                "type": .string("EffectPerspectiveUV"),
                "vars": .object([
                    "p0": .string("point0"),
                    "p1": .string("point1"),
                    "p2": .string("point2"),
                    "p3": .string("point3"),
                ]),
            ])]),
            extraFields: [:],
            unknownFieldPaths: []
        )
    }

    static func descriptor(_ options: Options = .init()) -> SceneRenderDescriptor {
        let paths = options.texture ? ["materials/util/noise"] : []
        let effect = SceneRenderDescriptor.EffectDescriptor(
            id: "20#effect#702",
            file: definitionPath,
            visible: options.visible,
            passes: [.init(
                passIndex: 0,
                texturePaths: paths,
                textureSlots: paths,
                userTextureInputs: [],
                combos: combos(options),
                constantShaderValues: constants(options)
            )]
        )
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "\(materialPath)#0",
            materialPath: materialPath,
            materialRawSHA256: options.materialHash,
            passIndex: 0,
            shaderPath: shaderIdentity,
            texturePaths: [],
            textureSlots: [],
            userTextureInputs: [],
            combos: [:],
            constantShaderValues: [:],
            userShaderValues: [:],
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil
        )
        return .init(
            layers: [.init(
                id: 20,
                contentKind: options.contentKind,
                childLayerIDs: options.child ? [21] : [],
                dependencyLayerIDs: options.dependency ? [22] : [],
                hasInlineScript: options.inlineScript,
                effects: [effect]
            )],
            materialPasses: [material],
            effectDefinitions: [definition()]
        )
    }

    static func graph(
        priorInput: Bool = false,
        blocker: Bool = false,
        wrongNode: Bool = false
    ) -> Graph {
        let key = Graph.EffectKey(layerID: 20, effectIndex: 0, descriptorID: "20#effect#702")
        let priorKey = Graph.EffectKey(layerID: 20, effectIndex: 0, descriptorID: "prior")
        let input = Graph.TextureIdentity(
            kind: priorInput ? .effectOutput : .layerSource,
            layerID: 20,
            effect: priorInput ? priorKey : nil,
            name: nil
        )
        let output = Graph.TextureIdentity(
            kind: .effectOutput, layerID: 20, effect: key, name: nil
        )
        return .init(
            layerID: 20,
            effects: [.init(
                key: key,
                definitionPath: definitionPath,
                input: input,
                output: output,
                nodeIndices: [0]
            )],
            renderTargets: [],
            nodes: [.init(
                nodeIndex: 0,
                effect: key,
                definitionPassIndex: 0,
                materialOrdinal: 0,
                instancePassIndex: 0,
                kind: wrongNode ? .copy : .material,
                materialPath: materialPath,
                materialPassID: "\(materialPath)#0",
                target: output,
                bindings: [],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            )],
            finalOutput: output,
            blockers: blocker ? [.init(
                effect: key,
                definitionPassIndex: 0,
                reason: .unsupportedCondition,
                detail: "fixture"
            )] : []
        )
    }

    static func accepted(
        options: Options = .init(),
        contracts: [SceneShaderContract],
        priorInput: Bool = false,
        role: SceneAuthoredEffectInputRole = .layerSource,
        blocker: Bool = false,
        wrongNode: Bool = false
    ) -> Bool {
        SceneAuthoredLightShaftsPlanner.plan(
            graph: graph(priorInput: priorInput, blocker: blocker, wrongNode: wrongNode),
            descriptor: descriptor(options),
            shaderContracts: contracts,
            inputRole: role
        ) != nil
    }

    static func mutate(
        _ contracts: [SceneShaderContract],
        _ mode: String
    ) -> [SceneShaderContract] {
        guard let contract = contracts.first else { return contracts }
        var stages = contract.stages
        if mode == "source" || mode == "raw" {
            let stage = stages[0]
            stages[0] = .init(
                kind: stage.kind,
                relativePath: stage.relativePath,
                source: mode == "source" ? stage.source + "x" : stage.source,
                rawSHA256: mode == "raw" ? String(repeating: "0", count: 64) : stage.rawSHA256,
                includes: stage.includes,
                annotations: stage.annotations,
                declarations: stage.declarations
            )
        }
        return [.init(
            identity: contract.identity,
            sourceKind: contract.sourceKind,
            stages: stages,
            diagnostics: contract.diagnostics,
            canonicalSHA256: mode == "canonical"
                ? String(repeating: "0", count: 64)
                : contract.canonicalSHA256
        )]
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let contracts = SceneShaderContractLoader().load(
            shaderReferences: [shaderIdentity],
            rootURL: root
        )
        let plan = SceneAuthoredLightShaftsPlanner.plan(
            graph: graph(), descriptor: descriptor(), shaderContracts: contracts
        )
        var radial = Options(); radial.rendering = nil; radial.rayMode = 1
        let radialPlan = SceneAuthoredLightShaftsPlanner.plan(
            graph: graph(), descriptor: descriptor(radial), shaderContracts: contracts
        )
        var notDirect = Options(); notDirect.directDraw = 0
        var colorMode = Options(); colorMode.rendering = 0
        var radialGradient = radial; radialGradient.rendering = 1
        var corner = radial; corner.rayMode = 2
        var unknownCombo = Options(); unknownCombo.extraCombo = true
        var texture = Options(); texture.texture = true
        var binding = Options(); binding.binding = true
        var image = Options(); image.contentKind = "image"
        var child = Options(); child.child = true
        var dependency = Options(); dependency.dependency = true
        var script = Options(); script.inlineScript = true
        var hash = Options(); hash.materialHash = String(repeating: "0", count: 64)
        var extra = Options(); extra.extraConstant = true
        var intensity = Options(); intensity.intensity = 10.01
        var radius = Options(); radius.radius = 2.01
        var noiseAmount = Options(); noiseAmount.noiseAmount = 1.01
        var noiseScale = Options(); noiseScale.noiseScale = 10.01
        var hidden = Options(); hidden.visible = false
        var degenerate = Options(); degenerate.degeneratePoints = true
        var reversedAngles = radial; reversedAngles.startAngle = 0.8
        reversedAngles.endAngle = 0.2
        let rejected = [
            notDirect, colorMode, radialGradient, corner, unknownCombo, texture,
            binding, image, child, dependency, script, hash, extra, intensity,
            radius, noiseAmount, noiseScale, hidden, degenerate, reversedAngles,
        ].allSatisfy { !accepted(options: $0, contracts: contracts) }
        let result: [String: Bool] = [
            "accepted": plan != nil,
            "parametersPreserved": plan.map {
                $0.profile == .linearGradient
                    && $0.points.0 == SIMD2<Float>(0.4, 0.25)
                    && $0.points.2 == SIMD2<Float>(0.8, 0.8)
                    && $0.startColor == SIMD3<Float>(1, 1, 1)
                    && $0.endColor == SIMD3<Float>(0.435294, 0.886274, 1)
                    && $0.feather == SIMD2<Float>(0.31, 0.31)
                    && $0.scale == SIMD2<Float>(0.8, 0.2)
                    && $0.radius == Float(0.14)
                    && $0.noiseAmount == Float(0.33)
                    && $0.noiseScale == Float(1.17)
                    && $0.intensity == Float(1.21)
                    && $0.effectUVTransform.project(SIMD2<Float>(0.4, 0.25)).map {
                        simd_distance($0, SIMD2<Float>(0, 0)) < 0.001
                    } == true
                    && $0.effectUVTransform.project(SIMD2<Float>(0.8, 0.8)).map {
                        simd_distance($0, SIMD2<Float>(1, 1)) < 0.001
                    } == true
                    && $0.effectUVTransform.project(SIMD2<Float>(0.6, 0.25)).map {
                        simd_distance($0, SIMD2<Float>(1, 0)) < 0.001
                    } == true
                    && $0.effectUVTransform.project(SIMD2<Float>(0.2, 0.8)).map {
                        simd_distance($0, SIMD2<Float>(0, 1)) < 0.001
                    } == true
                    && $0.noiseTexturePath == "materials/util/noise"
                    && $0.gradientTexturePath
                        == "materials/gradient/gradient_iridescent"
            } ?? false,
            "radialColorAccepted": radialPlan.map {
                $0.profile == .radialColor
                    && $0.exponent == 0
                    && $0.startAngle == 0
                    && $0.endAngle == 1
                    && $0.startColor == SIMD3<Float>(1, 1, 1)
                    && $0.endColor == SIMD3<Float>(0.435294, 0.886274, 1)
            } ?? false,
            "profileRejected": rejected,
            "priorInputRejected": !accepted(
                contracts: contracts,
                priorInput: true,
                role: .priorEffectOutput
            ),
            "graphRejected": !accepted(contracts: contracts, blocker: true)
                && !accepted(contracts: contracts, wrongNode: true),
            "contractsRejected": ["source", "raw", "canonical"].allSatisfy {
                !accepted(contracts: mutate(contracts, $0))
            },
            "candidateDetected":
                SceneAuthoredLightShaftsPlanner.containsCandidate(graph: graph()),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneLightShaftsPlannerTests(unittest.TestCase):
    def test_exact_profile_is_admitted_and_mutations_fail_closed(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        self.assertTrue(
            (STOCK_EFFECT_ROOT / "shaders/effects/lightshafts.frag").is_file()
        )
        with tempfile.TemporaryDirectory(prefix="scene-light-shafts-planner-") as directory:
            temporary = Path(directory)
            harness = temporary / "Harness.swift"
            binary = temporary / "scene-light-shafts-planner"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "swiftc",
                    "-parse-as-library",
                    *(str(path) for path in SOURCES),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary), str(STOCK_EFFECT_ROOT)],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        self.assertTrue(all(result.values()), result)


if __name__ == "__main__":
    unittest.main()
