#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from scene_real_test_fixtures import sample_cache_root


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
REAL_SAMPLE_CACHE = sample_cache_root("3767460992")
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContractLoader.swift",
    SOURCE_ROOT / "RenderGraph/SceneWorkshopShiftHueExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredWorkshopShiftHuePlanner.swift",
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
    static let definitionPath = "effects/workshop/2114826643/shift_hue/effect.json"
    static let materialPath = "materials/workshop/2114826643/effects/shift_hue.json"
    static let shaderIdentity = "workshop/2114826643/effects/shift_hue"

    struct Options {
        var contentKind = "image"
        var speed = 0.5
        var valueKind = "number"
        var binding: String?
        var extraConstant = false
        var texture = false
        var combo = false
        var visible: Bool? = true
        var materialHash =
            "7e3043ae3623e0a598b316b9c22d29c1f5c89610cc297c03678c5667adc284bd"
        var definitionMutation = "none"
    }

    struct GraphOptions {
        var priorInput = false
        var blocker = false
        var extraTarget = false
        var wrongOutput = false
        var nodeKind = Graph.NodeKind.material
        var binding = false
    }

    static func value(_ options: Options) -> SceneDocument.ShaderValue {
        .init(
            rawValue: String(options.speed),
            valueKind: options.binding == nil ? options.valueKind : "binding",
            userBinding: options.binding,
            components: [options.speed]
        )
    }

    static func definition(_ mutation: String) -> SceneEffectDefinition {
        SceneEffectDefinition(
            relativePath: definitionPath,
            version: mutation == "version" ? 2 : 1,
            replacementKey: "shift_hue",
            name: mutation == "name" ? "Other" : "Shift Hue",
            description: nil,
            group: "localeffects",
            performance: nil,
            previewPath: nil,
            editable: false,
            passes: [.init(
                passIndex: 0,
                materialPath: materialPath,
                target: mutation == "target" ? "other" : nil,
                bindings: [],
                compose: nil,
                command: nil,
                source: nil,
                conditions: nil,
                extraFields: [:]
            )],
            framebuffers: [],
            dependencies: mutation == "dependencies" ? [] : [
                materialPath,
                "shaders/workshop/2114826643/effects/shift_hue.frag",
                "shaders/workshop/2114826643/effects/shift_hue.vert",
            ],
            functions: nil,
            gizmos: nil,
            extraFields: mutation == "extra" ? ["extra": .bool(true)] : [:],
            unknownFieldPaths: mutation == "extra" ? ["extra"] : []
        )
    }

    static func descriptor(
        _ options: Options = .init(),
        priorInput: Bool = false
    ) -> SceneRenderDescriptor {
        var constants = ["Speed": value(options)]
        if options.extraConstant {
            constants["Other"] = .init(
                rawValue: "1", valueKind: "number", userBinding: nil, components: [1]
            )
        }
        let paths = options.texture ? ["unexpected.png"] : []
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            texturePaths: paths,
            textureSlots: paths,
            userTextureInputs: [],
            combos: options.combo ? ["OTHER": 1] : [:],
            constantShaderValues: constants
        )
        let effect = SceneRenderDescriptor.EffectDescriptor(
            id: "945#effect#946",
            file: definitionPath,
            visible: options.visible,
            passes: [pass]
        )
        let prior = SceneRenderDescriptor.EffectDescriptor(
            id: "945#effect#900",
            file: "effects/prior/effect.json",
            visible: true,
            passes: []
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
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull"
        )
        return .init(
            layers: [.init(
                id: 945,
                contentKind: options.contentKind,
                effects: priorInput ? [prior, effect] : [effect]
            )],
            materialPasses: [material],
            effectDefinitions: [definition(options.definitionMutation)]
        )
    }

    static func graph(_ options: GraphOptions = .init()) -> Graph {
        let key = Graph.EffectKey(
            layerID: 945,
            effectIndex: options.priorInput ? 1 : 0,
            descriptorID: "945#effect#946"
        )
        let prior = Graph.EffectKey(
            layerID: 945,
            effectIndex: 0,
            descriptorID: "945#effect#900"
        )
        let input = Graph.TextureIdentity(
            kind: options.priorInput ? .effectOutput : .layerSource,
            layerID: 945,
            effect: options.priorInput ? prior : nil,
            name: nil
        )
        let output = Graph.TextureIdentity(
            kind: .effectOutput, layerID: 945, effect: key, name: nil
        )
        let node = Graph.Node(
            nodeIndex: 0,
            effect: key,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: options.nodeKind,
            materialPath: materialPath,
            materialPassID: "\(materialPath)#0",
            target: output,
            bindings: options.binding
                ? [.init(slot: 0, authoredName: "unexpected", texture: input, conditions: nil)]
                : [],
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
        let target = Graph.RenderTarget(
            texture: .init(kind: .framebuffer, layerID: 945, effect: key, name: "extra"),
            extent: .init(kind: .input, first: nil, second: nil),
            format: "rgba_backbuffer",
            declaredUnique: false,
            clear: nil,
            uvs: nil,
            conditions: nil
        )
        return .init(
            layerID: 945,
            effects: [effect],
            renderTargets: options.extraTarget ? [target] : [],
            nodes: [node],
            finalOutput: options.wrongOutput ? input : output,
            blockers: options.blocker ? [
                .init(
                    effect: key,
                    definitionPassIndex: 0,
                    reason: .unsupportedCondition,
                    detail: "fixture"
                )
            ] : []
        )
    }

    static func mutate(
        _ contracts: [SceneShaderContract],
        _ mode: String
    ) -> [SceneShaderContract] {
        guard mode != "none", let contract = contracts.first else { return contracts }
        var stages = contract.stages
        if mode == "source" || mode == "raw" || mode == "metadata" {
            let stage = stages[0]
            stages[0] = .init(
                kind: stage.kind,
                relativePath: mode == "metadata" ? "shaders/changed.vert" : stage.relativePath,
                source: mode == "source" ? stage.source + "x" : stage.source,
                rawSHA256: mode == "raw" ? String(repeating: "0", count: 64) : stage.rawSHA256,
                includes: stage.includes,
                annotations: stage.annotations,
                declarations: stage.declarations
            )
        }
        let changed = SceneShaderContract(
            identity: mode == "identity" ? "other" : contract.identity,
            sourceKind: mode == "builtin" ? .hostBuiltin : contract.sourceKind,
            stages: stages,
            diagnostics: mode == "diagnostic" ? [] : contract.diagnostics,
            canonicalSHA256: mode == "canonical"
                ? String(repeating: "0", count: 64)
                : contract.canonicalSHA256
        )
        return mode == "duplicate" ? [contract, contract] : [changed]
    }

    static func accepted(
        graphOptions: GraphOptions = .init(),
        descriptorOptions: Options = .init(),
        contracts: [SceneShaderContract],
        role: SceneAuthoredEffectInputRole = .layerSource
    ) -> Bool {
        SceneAuthoredWorkshopShiftHuePlanner.plan(
            graph: graph(graphOptions),
            descriptor: descriptor(
                descriptorOptions,
                priorInput: graphOptions.priorInput
            ),
            shaderContracts: contracts,
            inputRole: role
        ) != nil
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let contracts = SceneShaderContractLoader().load(
            shaderReferences: [shaderIdentity],
            rootURL: root
        )
        let plan = SceneAuthoredWorkshopShiftHuePlanner.plan(
            graph: graph(), descriptor: descriptor(), shaderContracts: contracts
        )

        var prior = GraphOptions(); prior.priorInput = true
        var blocker = GraphOptions(); blocker.blocker = true
        var target = GraphOptions(); target.extraTarget = true
        var wrongOutput = GraphOptions(); wrongOutput.wrongOutput = true
        var copy = GraphOptions(); copy.nodeKind = .copy
        var binding = GraphOptions(); binding.binding = true
        var low = Options(); low.speed = -0.01
        var high = Options(); high.speed = 1.01
        var nan = Options(); nan.speed = .nan
        var bound = Options(); bound.binding = "property"
        var wrongKind = Options(); wrongKind.valueKind = "vector"
        var extra = Options(); extra.extraConstant = true
        var texture = Options(); texture.texture = true
        var combo = Options(); combo.combo = true
        var hidden = Options(); hidden.visible = false
        var particle = Options(); particle.contentKind = "particle"
        var badHash = Options(); badHash.materialHash = String(repeating: "0", count: 64)
        let definitionMutations = ["version", "name", "target", "dependencies", "extra"]
        let contractMutations = [
            "source", "raw", "metadata", "identity", "builtin",
            "diagnostic", "canonical", "duplicate",
        ]

        let result: [String: Bool] = [
            "exactAccepted": plan?.speed == 0.5,
            "priorAccepted": accepted(
                graphOptions: prior,
                contracts: contracts,
                role: .priorEffectOutput
            ),
            "roleMismatchRejected": !accepted(graphOptions: prior, contracts: contracts),
            "parametersRejected": [low, high, nan, bound, wrongKind, extra]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "shapeRejected": [texture, combo, hidden, particle, badHash]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "definitionRejected": definitionMutations.allSatisfy { mutation in
                var options = Options(); options.definitionMutation = mutation
                return !accepted(descriptorOptions: options, contracts: contracts)
            },
            "graphRejected": [blocker, target, wrongOutput, copy, binding]
                .allSatisfy { !accepted(graphOptions: $0, contracts: contracts) },
            "contractsRejected": contractMutations.allSatisfy {
                !accepted(contracts: mutate(contracts, $0))
            },
            "sourceRejected": !accepted(contracts: mutate(contracts, "source")),
            "rawRejected": !accepted(contracts: mutate(contracts, "raw")),
            "metadataRejected": !accepted(contracts: mutate(contracts, "metadata")),
            "identityRejected": !accepted(contracts: mutate(contracts, "identity")),
            "builtinRejected": !accepted(contracts: mutate(contracts, "builtin")),
            "diagnosticRejected": !accepted(contracts: mutate(contracts, "diagnostic")),
            "canonicalRejected": !accepted(contracts: mutate(contracts, "canonical")),
            "duplicateRejected": !accepted(contracts: mutate(contracts, "duplicate")),
            "candidateDetected": SceneAuthoredWorkshopShiftHuePlanner.containsCandidate(
                graph: graph()
            ),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneWorkshopShiftHuePlannerTests(unittest.TestCase):
    def test_exact_profile_is_admitted_and_mutations_fail_closed(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        shader = (
            REAL_SAMPLE_CACHE
            / "shaders/workshop/2114826643/effects/shift_hue.frag"
        )
        if not shader.is_file():
            self.skipTest(f"real Shift Hue fixture unavailable: {shader}")
        with tempfile.TemporaryDirectory(prefix="scene-shift-hue-planner-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "scene-shift-hue-planner"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "swiftc", "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness), "-o", str(binary),
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
