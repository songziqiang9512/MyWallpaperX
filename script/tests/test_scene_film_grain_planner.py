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
    SOURCE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderSourceGraph.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderContract.swift",
    SOURCE_ROOT / "Resources/SceneShaderSourceGraphBuilder.swift",
    SOURCE_ROOT / "Resources/SceneShaderSourceResolver.swift",
    SOURCE_ROOT / "Resources/SceneResourceView.swift",
    SOURCE_ROOT / "Resources/SceneResourceIndex.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderContractLoader.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderContractLoader+SourceGraph.swift",
    SOURCE_ROOT / "RenderGraph/SceneFilmGrainExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredFilmGrainPlanner.swift",
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
    static let definitionPath = "effects/filmgrain/effect.json"
    static let materialPath = "materials/effects/filmgrain.json"
    static let shaderIdentity = "effects/filmgrain"

    struct Options {
        var contentKind = "image"
        var materialHash =
            "5595a2eced03515da806c1949160c68106e542bcd05e1f8d921c3957915105be"
        var definitionVersion = 1
        var visible: Bool? = true
        var texture = false
        var blendMode = 14
        var greyscale = 0
        var extraCombo = false
        var extraConstant = false
        var binding = false
        var scale = 12.75
        var strength = 1.79
        var exponent = 3.8
    }

    static func value(_ component: Double, binding: Bool = false) -> SceneDocument.ShaderValue {
        .init(
            rawValue: String(component),
            valueKind: binding ? "binding" : "number",
            userBinding: binding ? "property" : nil,
            components: [component]
        )
    }

    static func constants(_ options: Options) -> [String: SceneDocument.ShaderValue] {
        var result = [
            "scale": value(options.scale),
            "strength": value(options.strength, binding: options.binding),
            "exponent": value(options.exponent),
        ]
        if options.extraConstant { result["other"] = value(1) }
        return result
    }

    static func combos(_ options: Options) -> [String: Int] {
        var result = ["BLENDMODE": options.blendMode, "GREYSCALE": options.greyscale]
        if options.extraCombo { result["OTHER"] = 1 }
        return result
    }

    static func definition(_ options: Options) -> SceneEffectDefinition {
        .init(
            relativePath: definitionPath,
            version: options.definitionVersion,
            replacementKey: "filmgrain",
            name: "ui_editor_effect_filmgrain_title",
            description: "ui_editor_effect_filmgrain_description",
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
                "shaders/effects/filmgrain.frag",
                "shaders/effects/filmgrain.vert",
            ],
            functions: nil,
            gizmos: nil,
            extraFields: [:],
            unknownFieldPaths: []
        )
    }

    static func descriptor(_ options: Options = .init()) -> SceneRenderDescriptor {
        let paths = options.texture ? ["noise.png"] : []
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
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull"
        )
        return .init(
            layers: [.init(id: 20, contentKind: options.contentKind, effects: [effect])],
            materialPasses: [material],
            effectDefinitions: [definition(options)]
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
        SceneAuthoredFilmGrainPlanner.plan(
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
        var badVersion = Options(); badVersion.definitionVersion = 2
        var hidden = Options(); hidden.visible = false
        var texture = Options(); texture.texture = true
        var blend = Options(); blend.blendMode = 13
        var greyscale = Options(); greyscale.greyscale = 1
        var combo = Options(); combo.extraCombo = true
        var extra = Options(); extra.extraConstant = true
        var bound = Options(); bound.binding = true
        var scale = Options(); scale.scale = 20.01
        var strength = Options(); strength.strength = 5.01
        var exponent = Options(); exponent.exponent = -0.01
        var content = Options(); content.contentKind = "video"
        let contractMutations = [
            "source", "raw", "path", "identity", "sourceKind", "diagnostic",
            "canonical", "duplicate",
        ]
        let plan = SceneAuthoredFilmGrainPlanner.plan(
            graph: graph(), descriptor: descriptor(), shaderContracts: contracts
        )
        let result: [String: Bool] = [
            "accepted": plan != nil,
            "parametersPreserved": plan.map {
                $0.scale == 12.75 && $0.strength == 1.79 && $0.exponent == 3.8
                    && $0.blendMode == 14 && !$0.greyscale
                    && $0.noiseTexturePath == "util/noise"
            } ?? false,
            "priorAccepted": accepted(
                contracts: contracts, priorInput: true, role: .priorEffectOutput
            ),
            "wrongRoleRejected": !accepted(
                contracts: contracts, priorInput: true, role: .layerSource
            ),
            "profileRejected": [
                badHash, badVersion, hidden, texture, blend, greyscale, combo,
                extra, bound, scale, strength, exponent, content,
            ].allSatisfy { !accepted(options: $0, contracts: contracts) },
            "graphRejected": !accepted(contracts: contracts, blocker: true)
                && !accepted(contracts: contracts, wrongNode: true),
            "contractsRejected": contractMutations.allSatisfy {
                !accepted(contracts: mutate(contracts, $0))
            },
            "candidateDetected": SceneAuthoredFilmGrainPlanner.containsCandidate(graph: graph()),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneFilmGrainPlannerTests(unittest.TestCase):
    def test_exact_profile_is_admitted_and_mutations_fail_closed(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        shader = REAL_SAMPLE_CACHE / "shaders/effects/filmgrain.frag"
        if not shader.is_file():
            self.skipTest(f"real Film Grain fixture unavailable: {shader}")
        with tempfile.TemporaryDirectory(prefix="scene-film-grain-planner-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "scene-film-grain-planner"
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
