#!/usr/bin/env python3

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
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects/colorkey"
)
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContractLoader.swift",
    SOURCE_ROOT / "RenderGraph/SceneColorKeyExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredColorKeyPlanner.swift",
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
        let alphaWriting: String? = nil
    }
    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    static var definitionPath = "effects/colorkey/effect.json"
    static var materialPath = "materials/effects/colorkey.json"
    static var shaderIdentity = "effects/colorkey"

    struct Options {
        var contentKind = "solid"
        var visible: Bool? = true
        var alpha = 0.0
        var fuzziness = 0.0
        var tolerance = 0.1
        var color = [0.0, 0.0, 0.0]
        var binding: String?
        var combos: [String: Int] = [:]
        var omitConstants = false
        var extraConstant = false
        var texture = false
        var materialTexture = false
        var materialHash =
            "02d5f948d42690e5a697be56d9b43f59ab30e633db7dd042f4ac9d20537b4a0c"
        var definitionVersion = 1
        var blending = "normal"
    }

    static func value(
        _ components: [Double],
        kind: String,
        binding: String? = nil
    ) -> SceneDocument.ShaderValue {
        .init(
            rawValue: components.map { String($0) }.joined(separator: " "),
            valueKind: binding == nil ? kind : "binding",
            userBinding: binding,
            components: components
        )
    }

    static func constants(_ options: Options) -> [String: SceneDocument.ShaderValue] {
        guard !options.omitConstants else { return [:] }
        var result = [
            "alpha": value([options.alpha], kind: "number", binding: options.binding),
            "fuzziness": value([options.fuzziness], kind: "number"),
            "tolerance": value([options.tolerance], kind: "number"),
            "color": value(options.color, kind: "vector"),
        ]
        if options.extraConstant { result["extra"] = value([1], kind: "number") }
        return result
    }

    static func definition(version: Int = 1) -> SceneEffectDefinition {
        SceneEffectDefinition(
            relativePath: definitionPath,
            version: version,
            replacementKey: "colorkey",
            name: "ui_editor_effect_color_key_title",
            description: "ui_editor_effect_color_key_description",
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
                "shaders/\(shaderIdentity).frag",
                "shaders/\(shaderIdentity).vert",
            ],
            functions: nil,
            gizmos: nil,
            extraFields: [:],
            unknownFieldPaths: []
        )
    }

    static func descriptor(
        _ options: Options = .init(),
        priorInput: Bool = false
    ) -> SceneRenderDescriptor {
        let paths = options.texture ? ["unexpected.png"] : []
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            texturePaths: paths,
            textureSlots: paths,
            userTextureInputs: [],
            combos: options.combos,
            constantShaderValues: constants(options)
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
        let materialPaths = options.materialTexture ? ["unexpected.png"] : []
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "\(materialPath)#0",
            materialPath: materialPath,
            materialRawSHA256: options.materialHash,
            passIndex: 0,
            shaderPath: shaderIdentity,
            texturePaths: materialPaths,
            textureSlots: materialPaths,
            userTextureInputs: [],
            combos: [:],
            constantShaderValues: [:],
            blending: options.blending,
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
            effectDefinitions: [definition(version: options.definitionVersion)]
        )
    }

    static func graph(priorInput: Bool = false, blocker: Bool = false) -> Graph {
        let key = Graph.EffectKey(
            layerID: 945,
            effectIndex: priorInput ? 1 : 0,
            descriptorID: "945#effect#946"
        )
        let priorKey = Graph.EffectKey(
            layerID: 945,
            effectIndex: 0,
            descriptorID: "945#effect#900"
        )
        let input = Graph.TextureIdentity(
            kind: priorInput ? .effectOutput : .layerSource,
            layerID: 945,
            effect: priorInput ? priorKey : nil,
            name: nil
        )
        let output = Graph.TextureIdentity(
            kind: .effectOutput,
            layerID: 945,
            effect: key,
            name: nil
        )
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
            layerID: 945,
            effects: [effect],
            renderTargets: [],
            nodes: [node],
            finalOutput: output,
            blockers: blocker ? [
                .init(
                    effect: key,
                    definitionPassIndex: 0,
                    reason: .unsupportedCondition,
                    detail: "fixture"
                )
            ] : []
        )
    }

    static func plan(
        _ options: Options = .init(),
        contracts: [SceneShaderContract],
        priorInput: Bool = false,
        role: SceneAuthoredEffectInputRole = .layerSource,
        blocker: Bool = false
    ) -> SceneColorKeyExecutionPlan? {
        SceneAuthoredColorKeyPlanner.plan(
            graph: graph(priorInput: priorInput, blocker: blocker),
            descriptor: descriptor(options, priorInput: priorInput),
            shaderContracts: contracts,
            inputRole: role
        )
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let contracts = SceneShaderContractLoader().load(
            shaderReferences: [shaderIdentity],
            rootURL: root
        )
        let stock = plan(contracts: contracts)!
        var combos = Options(); combos.combos = ["INVERT": 1, "FLATTEN": 1]
        var defaults = Options(); defaults.omitConstants = true
        var badAlpha = Options(); badAlpha.alpha = 1.01
        var badFuzz = Options(); badFuzz.fuzziness = -0.01
        var badTolerance = Options(); badTolerance.tolerance = 3.01
        var badColor = Options(); badColor.color = [0, 0, .infinity]
        var bound = Options(); bound.binding = "coloropacity"
        var extra = Options(); extra.extraConstant = true
        var texture = Options(); texture.texture = true
        var comboRange = Options(); comboRange.combos = ["INVERT": 2]
        var comboUnknown = Options(); comboUnknown.combos = ["OTHER": 0]
        var hidden = Options(); hidden.visible = false
        var content = Options(); content.contentKind = "particle"
        var hash = Options(); hash.materialHash = String(repeating: "0", count: 64)
        var version = Options(); version.definitionVersion = 2

        var result: [String: Bool] = [
            "stockAccepted": stock.keyAlpha == 0 && stock.fuzziness == 0
                && stock.tolerance == 0.1 && stock.keyColor == SIMD3(repeating: 0)
                && !stock.invert && !stock.flatten,
            "combosAccepted": plan(combos, contracts: contracts)?.invert == true
                && plan(combos, contracts: contracts)?.flatten == true,
            "defaultsAccepted": plan(defaults, contracts: contracts)?.keyColor
                == SIMD3(repeating: 1),
            "priorAccepted": plan(
                contracts: contracts,
                priorInput: true,
                role: .priorEffectOutput
            ) != nil,
            "roleMismatchRejected": plan(contracts: contracts, priorInput: true) == nil,
            "parametersRejected": [badAlpha, badFuzz, badTolerance, badColor, bound, extra]
                .allSatisfy { plan($0, contracts: contracts) == nil },
            "shapeRejected": [texture, comboRange, comboUnknown, hidden, content, version]
                .allSatisfy { plan($0, contracts: contracts) == nil },
            "materialSerializationAccepted": plan(hash, contracts: contracts) != nil,
            "blockerRejected": plan(contracts: contracts, blocker: true) == nil,
            "contractRejected": plan(contracts: []) == nil
                && plan(contracts: contracts + contracts) == nil,
            "stockCandidateDetected": SceneAuthoredColorKeyPlanner.containsCandidate(graph: graph()),
        ]

        definitionPath = "effects/workshop/fixture/colorkey/effect.json"
        materialPath = "materials/workshop/fixture/effects/colorkey.json"
        shaderIdentity = "workshop/fixture/effects/colorkey"
        let relocatedRoot = URL(
            fileURLWithPath: CommandLine.arguments[2],
            isDirectory: true
        )
        let relocatedContracts = SceneShaderContractLoader().load(
            shaderReferences: [shaderIdentity],
            rootURL: relocatedRoot
        )
        let mutatedRoot = URL(
            fileURLWithPath: CommandLine.arguments[3],
            isDirectory: true
        )
        let mutatedContracts = SceneShaderContractLoader().load(
            shaderReferences: [shaderIdentity],
            rootURL: mutatedRoot
        )
        var materialTexture = Options(); materialTexture.materialTexture = true
        var renderState = Options(); renderState.blending = "additive"

        result["relocatedAccepted"] = plan(contracts: relocatedContracts) != nil
        result["relocatedExecutableRejected"] = plan(contracts: mutatedContracts) == nil
        result["relocatedMaterialContractRejected"] = [materialTexture, renderState]
            .allSatisfy { plan($0, contracts: relocatedContracts) == nil }
        result["relocatedCandidateDetected"] = SceneAuthoredColorKeyPlanner.containsCandidate(
            graph: graph()
        )
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneColorKeyPlannerTests(unittest.TestCase):
    @staticmethod
    def _write_relocated_shader_fixture(root: Path, *, mutate: bool) -> None:
        shader_root = root / "shaders/workshop/fixture/effects"
        shader_root.mkdir(parents=True)
        for suffix in ("vert", "frag"):
            source = (STOCK_ROOT / f"shaders/effects/colorkey.{suffix}").read_text()
            if suffix == "frag":
                source = source.replace(
                    '{"material":"color","label":"ui_editor_properties_color", '
                    '"type": "color", "default":"1 1 1"}',
                    '{"default":"1 1 1","label":"ui_editor_properties_color",'
                    '"material":"color","type":"color"}',
                )
                if mutate:
                    source = source.replace("albedo.a *= mix", "albedo.a += mix")
            (shader_root / f"colorkey.{suffix}").write_text(source)

    def test_stock_profile_is_exact_and_fail_closed(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="scene-colorkey-planner-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "scene-colorkey-planner"
            relocated_root = root / "relocated"
            mutated_root = root / "mutated"
            self._write_relocated_shader_fixture(relocated_root, mutate=False)
            self._write_relocated_shader_fixture(mutated_root, mutate=True)
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
                [
                    str(binary),
                    str(STOCK_ROOT),
                    str(relocated_root),
                    str(mutated_root),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        self.assertTrue(result)
        self.assertTrue(all(result.values()), result)


if __name__ == "__main__":
    unittest.main()
