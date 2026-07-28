#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.scene_real_test_fixtures import sample_cache_root


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
RUNTIME_PLAN_SOURCE = SOURCE_ROOT / "Effects/SceneEffectRuntimePlan.swift"
REAL_SAMPLE_CACHE = sample_cache_root("3122339805")
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContractLoader.swift",
    SOURCE_ROOT / "RenderGraph/SceneWorkshopAudioBarsExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredWorkshopSimpleAudioBarsPlanner.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredWorkshopSimpleAudioBarsPlanner+Profile.swift",
]


HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
    }
}

struct SceneEffectTextureInput { let name: String }

struct SceneUtilityLayer {
    enum Kind { case composition, project, fullscreen }
    let kind: Kind
}

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
        let utilityLayer: SceneUtilityLayer?
        let dependencyLayerIDs: [Int]
        let childLayerIDs: [Int]
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
    static let definitionPath =
        "effects/workshop/2084198056/Simple_Audio_Bars/effect.json"
    static let materialPath =
        "materials/workshop/2084198056/effects/Simple_Audio_Bars.json"
    static let shaderIdentity =
        "workshop/2084198056/effects/Simple_Audio_Bars"

    enum Content {
        case solid
        case composition
        case image
        case project
        case compositionWithDependency
    }

    struct Options {
        var profile64 = true
        var content = Content.solid
        var comboMutation = "none"
        var constantMutation = "none"
        var materialHash =
            "a283c6fa4cda8c6c91f2e8a737f9c42739473bbd900a0590b50458088b390de9"
        var definitionMutation = false
        var texture = false
        var visible: Bool? = true
        var blocker = false
        var priorInput = false
    }

    static func value(
        _ components: [Double],
        kind: String? = nil,
        binding: String? = nil
    ) -> SceneDocument.ShaderValue {
        .init(
            rawValue: components.map { String($0) }.joined(separator: " "),
            valueKind: binding == nil
                ? (kind ?? (components.count == 1 ? "number" : "vector"))
                : "binding",
            userBinding: binding,
            components: components
        )
    }

    static func constants(_ options: Options) -> [String: SceneDocument.ShaderValue] {
        var values = [
            "Bar Count": value([options.profile64 ? 66 : 15]),
            "Bar Color": value(
                options.profile64 ? [0.99608, 0.09804, 1] : [0.07451, 0.08235, 0.07843],
                binding: options.profile64 ? "basecolor" : "newproperty11"
            ),
            "Bar Spacing": value([0.30000001]),
            "Lower/Upper Bar Bounds": value(
                options.profile64 ? [0.001, 0.85] : [0, 0.14]
            ),
            "ui_editor_properties_opacity": value([1]),
        ]
        if !options.profile64 {
            values["Anti-alias blurring"] = value([1, 1])
        }
        switch options.constantMutation {
        case "count":
            values["Bar Count"] = value([201])
        case "hugecount":
            values["Bar Count"] = value([Double.greatestFiniteMagnitude])
        case "color":
            values["Bar Color"] = value([1, 0, 1])
        case "anonymous":
            values["Bar Color"] = value([1, 0, 1], binding: " ")
        case "spacing":
            values["Bar Spacing"] = value([0.4])
        case "bounds":
            values["Lower/Upper Bar Bounds"] = value([0.8, 0.2])
        case "opacity":
            values["ui_editor_properties_opacity"] = value([2])
        case "inactive":
            values["Anti-alias blurring"] = value([Double.nan, 1])
        case "unknown":
            values["Other"] = value([1])
        default:
            break
        }
        return values
    }

    static func combos(_ options: Options) -> [String: Int] {
        var values = options.profile64
            ? ["RESOLUTION": 64, "CLIP_HIGH": 1]
            : ["CLIP_LOW": 1]
        switch options.comboMutation {
        case "cross":
            values = options.profile64
                ? ["RESOLUTION": 64, "CLIP_LOW": 1]
                : ["CLIP_HIGH": 1]
        case "shape":
            values["SHAPE"] = 1
        case "transparency":
            values["TRANSPARENCY"] = 2
        case "smooth":
            values["A_SMOOTH_CURVE"] = 1
        case "unknown":
            values["OTHER"] = 1
        default:
            break
        }
        return values
    }

    static func definition(mutated: Bool) -> SceneEffectDefinition {
        .init(
            relativePath: definitionPath,
            version: 1,
            replacementKey: "Simple_Audio_Bars",
            name: mutated ? "Other" : "Simple Audio Bars",
            description: "Adds a cusomizable audio bar effect to the layer. Supports various "
                + "positions (left, right, both, center, etc.) and as many bars as you'd like.",
            group: "localeffects",
            performance: nil,
            previewPath: "preview/project.json",
            editable: false,
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
                "shaders/workshop/2084198056/effects/Simple_Audio_Bars.frag",
                "shaders/workshop/2084198056/effects/Simple_Audio_Bars.vert",
            ],
            functions: nil,
            gizmos: nil,
            extraFields: [:],
            unknownFieldPaths: []
        )
    }

    static func descriptor(_ options: Options) -> SceneRenderDescriptor {
        let texturePaths = options.texture ? ["unexpected.png"] : []
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            texturePaths: texturePaths,
            textureSlots: texturePaths,
            userTextureInputs: [],
            combos: combos(options),
            constantShaderValues: constants(options)
        )
        let effect = SceneRenderDescriptor.EffectDescriptor(
            id: "64#effect#66",
            file: definitionPath,
            visible: options.visible,
            passes: [pass]
        )
        let utility: SceneUtilityLayer?
        let contentKind: String
        let dependencies: [Int]
        switch options.content {
        case .solid:
            utility = nil
            contentKind = "solid"
            dependencies = []
        case .composition:
            utility = .init(kind: .composition)
            contentKind = "composition"
            dependencies = []
        case .image:
            utility = nil
            contentKind = "image"
            dependencies = []
        case .project:
            utility = .init(kind: .project)
            contentKind = "project"
            dependencies = []
        case .compositionWithDependency:
            utility = .init(kind: .composition)
            contentKind = "composition"
            dependencies = [2]
        }
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
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull"
        )
        return .init(
            layers: [.init(
                id: 64,
                contentKind: contentKind,
                utilityLayer: utility,
                dependencyLayerIDs: dependencies,
                childLayerIDs: [],
                effects: [effect]
            )],
            materialPasses: [material],
            effectDefinitions: [definition(mutated: options.definitionMutation)]
        )
    }

    static func graph(_ options: Options) -> Graph {
        let key = Graph.EffectKey(
            layerID: 64,
            effectIndex: 0,
            descriptorID: "64#effect#66"
        )
        let prior = Graph.EffectKey(
            layerID: 64,
            effectIndex: 1,
            descriptorID: "64#effect#prior"
        )
        let input = Graph.TextureIdentity(
            kind: options.priorInput ? .effectOutput : .layerSource,
            layerID: 64,
            effect: options.priorInput ? prior : nil,
            name: nil
        )
        let output = Graph.TextureIdentity(
            kind: .effectOutput,
            layerID: 64,
            effect: key,
            name: nil
        )
        return .init(
            layerID: 64,
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
                kind: .material,
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
            blockers: options.blocker ? [.init(
                effect: key,
                definitionPassIndex: 0,
                reason: .unsupportedCondition,
                detail: "fixture"
            )] : []
        )
    }

    static func accepted(
        _ options: Options,
        contracts: [SceneShaderContract],
        role: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWorkshopAudioBarsExecutionPlan? {
        SceneAuthoredWorkshopSimpleAudioBarsPlanner.plan(
            graph: graph(options),
            descriptor: descriptor(options),
            shaderContracts: contracts,
            inputRole: role
        )
    }

    static func mutatedContracts(
        _ contracts: [SceneShaderContract],
        mode: String
    ) -> [SceneShaderContract] {
        guard let contract = contracts.first else { return contracts }
        if mode == "duplicate" { return [contract, contract] }
        var stages = contract.stages
        if mode == "source" {
            let stage = stages[0]
            stages[0] = .init(
                kind: stage.kind,
                relativePath: stage.relativePath,
                source: stage.source + "x",
                rawSHA256: stage.rawSHA256,
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
        var profile32 = Options()
        profile32.profile64 = false
        profile32.content = .composition
        let plan64 = accepted(.init(), contracts: contracts)
        let plan32 = accepted(profile32, contracts: contracts)

        let target = plan64?.liveConsumerTargets.first
        let dynamic = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 1,
            definitions: target.map {
                [.init(target: $0, valueType: .vector3, authoredValue: .vector3(1, 0, 1))]
            } ?? [],
            userValues: target.map { [$0: .vector3(0.25, 0.5, 0.75)] } ?? [:]
        ).snapshot
        let resolvedColor = plan64?.resolvedSimpleParameters(in: dynamic)?.color

        var rejectionOptions: [Options] = []
        for mutation in ["cross", "shape", "transparency", "smooth", "unknown"] {
            var option = Options()
            option.comboMutation = mutation
            rejectionOptions.append(option)
        }
        for mutation in [
            "count", "hugecount", "color", "anonymous", "spacing", "bounds",
            "opacity", "inactive", "unknown",
        ] {
            var option = Options()
            option.constantMutation = mutation
            rejectionOptions.append(option)
        }
        for content in [
            Content.image, .project, .compositionWithDependency,
        ] {
            var option = Options()
            option.content = content
            rejectionOptions.append(option)
        }
        var badHash = Options()
        badHash.materialHash = String(repeating: "0", count: 64)
        rejectionOptions.append(badHash)
        var badDefinition = Options()
        badDefinition.definitionMutation = true
        rejectionOptions.append(badDefinition)
        var texture = Options()
        texture.texture = true
        rejectionOptions.append(texture)
        var hidden = Options()
        hidden.visible = false
        rejectionOptions.append(hidden)
        var blocker = Options()
        blocker.blocker = true
        rejectionOptions.append(blocker)
        var prior = Options()
        prior.priorInput = true

        let result: [String: Bool] = [
            "profile64Accepted": plan64?.resolvedSimpleParameters(
                in: .empty(frameIndex: 0)
            )?.parameters.profile == .bottomReplace64ClipHigh,
            "profile32Accepted": plan32?.resolvedSimpleParameters(
                in: .empty(frameIndex: 0)
            )?.parameters.profile == .bottomReplace32ClipLow,
            "dynamicColorResolved": resolvedColor == SIMD3<Float>(0.25, 0.5, 0.75),
            "bindingTargetExact": target == .effectConstant(
                layerID: 64,
                effectIndex: 0,
                passIndex: 0,
                name: "bar color"
            ),
            "mutationsRejected": rejectionOptions.allSatisfy {
                accepted($0, contracts: contracts) == nil
            },
            "priorRejected": accepted(
                prior,
                contracts: contracts,
                role: .priorEffectOutput
            ) == nil,
            "contractsRejected": ["source", "canonical", "duplicate"].allSatisfy {
                accepted(.init(), contracts: mutatedContracts(contracts, mode: $0)) == nil
            },
            "candidateDetected":
                SceneAuthoredWorkshopSimpleAudioBarsPlanner.containsCandidate(
                    graph: graph(.init())
                ),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneWorkshopSimpleAudioBarsPlannerTests(unittest.TestCase):
    def test_executed_audio_bars_are_not_reported_as_route_only(self) -> None:
        source = RUNTIME_PLAN_SOURCE.read_text(encoding="utf-8")
        self.assertIn("authoredEffectPlan?.workshopAudioBars != nil", source)
        self.assertIn("effect runtime workshop-audio-bars-authored;", source)

    def test_exact_profiles_and_dynamic_color_are_admitted(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        self.assertTrue(REAL_SAMPLE_CACHE.is_dir(), REAL_SAMPLE_CACHE)
        with tempfile.TemporaryDirectory(prefix="mwx-simple-audio-bars-plan-") as tmp:
            root = Path(tmp)
            harness = root / "Harness.swift"
            binary = root / "simple-audio-bars-plan"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary), str(REAL_SAMPLE_CACHE)],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        self.assertTrue(result)
        self.assertTrue(all(result.values()), result)


if __name__ == "__main__":
    unittest.main()
