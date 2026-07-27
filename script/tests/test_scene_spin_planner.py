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
    SOURCE_ROOT / "RenderGraph/SceneSpinExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredSpinPlanner.swift",
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
    static let definitionPath = "effects/spin/effect.json"
    static let materialPath = "materials/effects/spin.json"
    static let shaderIdentity = "effects/spin"

    struct Options {
        var contentKind = "solid"
        var materialHash =
            "3c5900d2d9257b3e9792bede3ac8e69e9518052740bef10d1908b5089d740f67"
        var definitionVersion = 2
        var gizmoType = "EffectSpinUV"
        var visible: Bool? = true
        var texture = false
        var combo = false
        var extraConstant = false
        var binding = false
        var speed = 1.0
        var ratio = 1.0
        var angle = 0.0
    }

    static func value(_ components: [Double], binding: Bool = false) -> SceneDocument.ShaderValue {
        .init(
            rawValue: components.map { String($0) }.joined(separator: " "),
            valueKind: binding ? "binding" : (components.count == 1 ? "number" : "vector"),
            userBinding: binding ? "property" : nil,
            components: components
        )
    }

    static func constants(_ options: Options) -> [String: SceneDocument.ShaderValue] {
        var result = [
            "angle": value([options.angle]),
            "center": value([0.5, 0.5]),
            "feather": value([0.2]),
            "phase": value([0]),
            "ratio": value([options.ratio]),
            "size": value([0.50013167]),
            "speed": value([options.speed], binding: options.binding),
        ]
        if options.extraConstant { result["other"] = value([1]) }
        return result
    }

    static func definition(_ options: Options) -> SceneEffectDefinition {
        .init(
            relativePath: definitionPath,
            version: options.definitionVersion,
            replacementKey: "spin",
            name: "ui_editor_effect_spin_title",
            description: "ui_editor_effect_spin_description",
            group: "animate",
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
                "shaders/effects/spin.frag",
                "shaders/effects/spin.vert",
            ],
            functions: nil,
            gizmos: .array([.object([
                "type": .string(options.gizmoType),
                "vars": .object([
                    "center": .string("center"),
                    "ratio": .string("ratio"),
                    "angle": .string("angle"),
                    "size": .string("size"),
                ]),
            ])]),
            extraFields: [:],
            unknownFieldPaths: []
        )
    }

    static func descriptor(_ options: Options = .init()) -> SceneRenderDescriptor {
        let paths = options.texture ? ["mask.png"] : []
        let effect = SceneRenderDescriptor.EffectDescriptor(
            id: "945#effect#964",
            file: definitionPath,
            visible: options.visible,
            passes: [.init(
                passIndex: 0,
                texturePaths: paths,
                textureSlots: paths,
                userTextureInputs: [],
                combos: options.combo ? ["NOISE": 1] : [:],
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
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull"
        )
        return .init(
            layers: [.init(id: 945, contentKind: options.contentKind, effects: [effect])],
            materialPasses: [material],
            effectDefinitions: [definition(options)]
        )
    }

    static func graph(
        priorInput: Bool = false,
        blocker: Bool = false,
        wrongNode: Bool = false
    ) -> Graph {
        let key = Graph.EffectKey(layerID: 945, effectIndex: 0, descriptorID: "945#effect#964")
        let priorKey = Graph.EffectKey(layerID: 945, effectIndex: 0, descriptorID: "prior")
        let input = Graph.TextureIdentity(
            kind: priorInput ? .effectOutput : .layerSource,
            layerID: 945,
            effect: priorInput ? priorKey : nil,
            name: nil
        )
        let output = Graph.TextureIdentity(
            kind: .effectOutput, layerID: 945, effect: key, name: nil
        )
        return .init(
            layerID: 945,
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
        SceneAuthoredSpinPlanner.plan(
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
        if ["source", "raw", "path"].contains(mode) {
            let stage = stages[0]
            stages[0] = .init(
                kind: stage.kind,
                relativePath: mode == "path" ? "shaders/effects/other.vert" : stage.relativePath,
                source: mode == "source" ? stage.source + "x" : stage.source,
                rawSHA256: mode == "raw" ? String(repeating: "0", count: 64) : stage.rawSHA256,
                includes: stage.includes,
                annotations: stage.annotations,
                declarations: stage.declarations
            )
        }
        let changed = SceneShaderContract(
            identity: mode == "identity" ? "effects/other" : contract.identity,
            sourceKind: mode == "sourceKind" ? .hostBuiltin : contract.sourceKind,
            stages: stages,
            diagnostics: mode == "diagnostic" ? [.init(
                code: .malformedAnnotation,
                message: "fixture",
                relativePath: nil,
                line: nil
            )] : contract.diagnostics,
            canonicalSHA256: mode == "canonical"
                ? String(repeating: "0", count: 64)
                : contract.canonicalSHA256
        )
        return mode == "duplicate" ? [contract, contract] : [changed]
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let contracts = SceneShaderContractLoader().load(
            shaderReferences: [shaderIdentity], rootURL: root
        )
        var badHash = Options(); badHash.materialHash = String(repeating: "0", count: 64)
        var badVersion = Options(); badVersion.definitionVersion = 1
        var badGizmo = Options(); badGizmo.gizmoType = "Other"
        var hidden = Options(); hidden.visible = false
        var texture = Options(); texture.texture = true
        var combo = Options(); combo.combo = true
        var extra = Options(); extra.extraConstant = true
        var bound = Options(); bound.binding = true
        var speed = Options(); speed.speed = 5.01
        var ratio = Options(); ratio.ratio = 0
        var angle = Options(); angle.angle = Double.pi + 0.01
        var content = Options(); content.contentKind = "video"
        let contractMutations = [
            "source", "raw", "path", "identity", "sourceKind", "diagnostic",
            "canonical", "duplicate",
        ]
        let plan = SceneAuthoredSpinPlanner.plan(
            graph: graph(), descriptor: descriptor(), shaderContracts: contracts
        )
        let result: [String: Bool] = [
            "accepted": plan != nil,
            "parametersPreserved": plan.map {
                $0.center.x == 0.5 && $0.center.y == 0.5
                    && abs($0.size - 0.50013167) < 0.000001
                    && $0.feather == 0.2 && $0.speed == 1 && $0.ratio == 1
            } ?? false,
            "priorAccepted": accepted(
                contracts: contracts, priorInput: true, role: .priorEffectOutput
            ),
            "wrongRoleRejected": !accepted(
                contracts: contracts, priorInput: true, role: .layerSource
            ),
            "profileRejected": [
                badHash, badVersion, badGizmo, hidden, texture, combo, extra,
                bound, speed, ratio, angle, content,
            ].allSatisfy { !accepted(options: $0, contracts: contracts) },
            "graphRejected": !accepted(contracts: contracts, blocker: true)
                && !accepted(contracts: contracts, wrongNode: true),
            "contractsRejected": contractMutations.allSatisfy {
                !accepted(contracts: mutate(contracts, $0))
            },
            "candidateDetected": SceneAuthoredSpinPlanner.containsCandidate(graph: graph()),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneSpinPlannerTests(unittest.TestCase):
    def test_exact_profile_is_admitted_and_mutations_fail_closed(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        shader = REAL_SAMPLE_CACHE / "shaders/effects/spin.frag"
        if not shader.is_file():
            self.skipTest(f"real Spin fixture unavailable: {shader}")
        with tempfile.TemporaryDirectory(prefix="scene-spin-planner-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "scene-spin-planner"
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
        self.assertTrue(all(result.values()), result)


if __name__ == "__main__":
    unittest.main()
