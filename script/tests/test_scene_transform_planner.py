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
SAMPLE_ROOT = sample_cache_root("2067939514")
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContractLoader.swift",
    SOURCE_ROOT / "RenderGraph/SceneTransformShaderProfile.swift",
    SOURCE_ROOT / "RenderGraph/SceneTransformExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredTransformPlanner.swift",
]


HARNESS = r'''
import Foundation

struct SceneEffectTextureInput {}

struct SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
        let timeline: Int?
        let timelineDiagnostics: [String]
    }
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
    static let layerID = 161
    static let descriptorID = "161#effect#1064"
    static let definitionPath = "effects/transform/effect.json"
    static let materialPath = "materials/effects/transform.json"

    struct Options {
        var contentKind = "image"
        var mode = 1
        var clamp: Int?
        var angle = [0.0]
        var offset = [0.0, 0.0]
        var scale = [1.0, 1.0]
        var scaleKind = "binding"
        var scaleBinding: String?
        var scaleTimeline: Int?
        var scaleDiagnostics: [String] = []
        var extraConstant = false
        var extraCombo = false
        var materialHash =
            "995444d008b2b699c8a98fd530a4528f75938a9f8596ae42c7da3adf1a8821d9"
        var blending = "normal"
        var visible: Bool? = true
    }

    static func value(
        _ components: [Double],
        kind: String,
        binding: String? = nil,
        timeline: Int? = nil,
        diagnostics: [String] = []
    ) -> SceneDocument.ShaderValue {
        .init(
            rawValue: components.map { String($0) }.joined(separator: " "),
            valueKind: kind,
            userBinding: binding,
            components: components,
            timeline: timeline,
            timelineDiagnostics: diagnostics
        )
    }

    static func constants(_ options: Options) -> [String: SceneDocument.ShaderValue] {
        var result = [
            "angle": value(options.angle, kind: "number"),
            "offset": value(options.offset, kind: "vector"),
            "scale": value(
                options.scale,
                kind: options.scaleKind,
                binding: options.scaleBinding,
                timeline: options.scaleTimeline,
                diagnostics: options.scaleDiagnostics
            ),
        ]
        if options.extraConstant {
            result["other"] = value([1], kind: "number")
        }
        return result
    }

    static func combos(_ options: Options) -> [String: Int] {
        var result = ["MODE": options.mode]
        if let clamp = options.clamp { result["CLAMP"] = clamp }
        if options.extraCombo { result["OTHER"] = 1 }
        return result
    }

    static func definition() -> SceneEffectDefinition {
        .init(
            relativePath: definitionPath,
            version: 1,
            replacementKey: "transform",
            name: "ui_editor_effect_transform_title",
            description: "ui_editor_effect_transform_description",
            group: "distort",
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
                "shaders/effects/transform.frag",
                "shaders/effects/transform.vert",
            ],
            functions: nil,
            gizmos: nil,
            extraFields: [:],
            unknownFieldPaths: []
        )
    }

    static func descriptor(_ options: Options = .init()) -> SceneRenderDescriptor {
        let effect = SceneRenderDescriptor.EffectDescriptor(
            id: descriptorID,
            file: definitionPath,
            visible: options.visible,
            passes: [.init(
                passIndex: 0,
                texturePaths: [],
                textureSlots: [],
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
            shaderPath: "effects/transform",
            texturePaths: [],
            textureSlots: [],
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
                id: layerID,
                contentKind: options.contentKind,
                effects: [effect]
            )],
            materialPasses: [material],
            effectDefinitions: [definition()]
        )
    }

    static func graph(
        priorInput: Bool = false,
        blocker: Bool = false
    ) -> Graph {
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: descriptorID
        )
        let prior = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "prior"
        )
        let input = Graph.TextureIdentity(
            kind: priorInput ? .effectOutput : .layerSource,
            layerID: layerID,
            effect: priorInput ? prior : nil,
            name: nil
        )
        let output = Graph.TextureIdentity(
            kind: .effectOutput,
            layerID: layerID,
            effect: key,
            name: nil
        )
        return .init(
            layerID: layerID,
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
            blockers: blocker ? [.init(
                effect: key,
                definitionPassIndex: 0,
                reason: .unsupportedCondition,
                detail: "fixture"
            )] : []
        )
    }

    static func plan(
        options: Options = .init(),
        contracts: [SceneShaderContract],
        priorInput: Bool = false,
        role: SceneAuthoredEffectInputRole = .layerSource,
        blocker: Bool = false
    ) -> SceneTransformExecutionPlan? {
        SceneAuthoredTransformPlanner.plan(
            graph: graph(priorInput: priorInput, blocker: blocker),
            descriptor: descriptor(options),
            shaderContracts: contracts,
            inputRole: role
        )
    }

    static func main() {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let contracts = SceneShaderContractLoader().load(
            shaderReferences: ["effects/transform"],
            rootURL: root
        )
        let fallback = plan(contracts: contracts)
        var staticOptions = Options()
        staticOptions.scaleKind = "vector"
        let staticPlan = plan(options: staticOptions, contracts: contracts)

        var mode = Options(); mode.mode = 0
        var clamp = Options(); clamp.clamp = 0
        var angle = Options(); angle.angle = [0.1]
        var offset = Options(); offset.offset = [0.1, 0]
        var scale = Options(); scale.scale = [1.01, 1]
        var user = Options(); user.scaleBinding = "property"
        var timeline = Options(); timeline.scaleTimeline = 1
        var diagnostic = Options(); diagnostic.scaleDiagnostics = ["unsupported"]
        var extraConstant = Options(); extraConstant.extraConstant = true
        var extraCombo = Options(); extraCombo.extraCombo = true
        var hash = Options(); hash.materialHash = String(repeating: "0", count: 64)
        var state = Options(); state.blending = "additive"
        var video = Options(); video.contentKind = "video"
        var hidden = Options(); hidden.visible = false

        let rejected = [
            mode, clamp, angle, offset, scale, user, timeline, diagnostic,
            extraConstant, extraCombo, hash, state, video, hidden,
        ].allSatisfy { plan(options: $0, contracts: contracts) == nil }
        let result: [String: Bool] = [
            "profileResolved": SceneTransformShaderProfile.resolve(contracts) == .stock2842,
            "fallbackAccepted": fallback != nil,
            "fallbackReported": fallback?.staticFallbackDiagnostics.map(\.reportValue) == [
                "effect=0,pass=0,constant=scale,"
                    + "reason=unsupported-dynamic-binding-static-fallback"
            ],
            "staticAcceptedWithoutDiagnostic":
                staticPlan?.staticFallbackDiagnostics.isEmpty == true,
            "priorAccepted": plan(
                contracts: contracts,
                priorInput: true,
                role: .priorEffectOutput
            ) != nil,
            "wrongRoleRejected": plan(
                contracts: contracts,
                priorInput: true,
                role: .layerSource
            ) == nil,
            "emptyProfileRejected": plan(contracts: []) == nil,
            "mutationsRejected": rejected,
            "blockerRejected": plan(contracts: contracts, blocker: true) == nil,
            "candidateDetected":
                SceneAuthoredTransformPlanner.containsCandidate(graph: graph()),
        ]
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneTransformPlannerTests(unittest.TestCase):
    def test_identity_and_static_fallback_contract(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        shader = SAMPLE_ROOT / "shaders/effects/transform.frag"
        if not shader.is_file():
            self.skipTest(f"Transform shader fixture unavailable: {shader}")
        with tempfile.TemporaryDirectory(prefix="scene-transform-planner-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "scene-transform-planner"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary), str(SAMPLE_ROOT)],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        self.assertTrue(all(result.values()), result)


if __name__ == "__main__":
    unittest.main()
