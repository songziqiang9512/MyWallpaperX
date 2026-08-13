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
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects/fisheye"
)
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
    SOURCE_ROOT / "RenderGraph/SceneFisheyeZeroDistortionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneFisheyeZeroDistortionShaderProfile.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredFisheyeZeroDistortionPlanner.swift",
]


HARNESS = r'''
import Foundation

struct SceneEffectTextureInput {}

struct SceneUtilityLayer {
    enum Kind {
        case composition
    }
    let kind: Kind
}

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
            let constantShaderValueKeys: [String]
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
        let childLayerIDs: [Int]
        let dependencyLayerIDs: [Int]
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
    static let layerID = 151
    static let descriptorID = "151#effect#18139"
    static let definitionPath = "effects/fisheye/effect.json"
    static let materialPath = "materials/effects/fisheye.json"

    struct Options {
        var center = [0.5, 0.5]
        var distortion = [0.0]
        var distortionKind = "number"
        var distortionBinding: String?
        var distortionTimeline: Int?
        var distortionDiagnostics: [String] = []
        var size = [1.2]
        var background = 0
        var omitBackground = false
        var extraConstant = false
        var extraCombo = false
        var definitionHash =
            "1cef719d7da1b7ed4d1c12d34092a19d8ea94ff3cd60c5374bbad80bae528a6c"
        var definitionExtra = false
        var materialHash =
            "cdb481996f3e2da67a3cf42d790dbce53db43cac806b46493f1a50b77ddd416e"
        var blending = "normal"
        var userShaderValues: [String: String] = [:]
        var alphaWriting: String?
        var visible: Bool? = true
        var utilityChildren: [Int] = []
        var utilityDependencies: [Int] = []
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

    static func constants(
        _ options: Options
    ) -> [String: SceneDocument.ShaderValue] {
        var result = [
            "center": value(options.center, kind: "vector"),
            "distortion": value(
                options.distortion,
                kind: options.distortionKind,
                binding: options.distortionBinding,
                timeline: options.distortionTimeline,
                diagnostics: options.distortionDiagnostics
            ),
            "size": value(options.size, kind: "number"),
        ]
        if options.extraConstant {
            result["future"] = value([1], kind: "number")
        }
        return result
    }

    static func combos(_ options: Options) -> [String: Int] {
        var result: [String: Int] = options.omitBackground
            ? [:]
            : ["BACKGROUND": options.background]
        if options.extraCombo {
            result["FUTURE"] = 1
        }
        return result
    }

    static func definition(_ options: Options) -> SceneEffectDefinition {
        .init(
            relativePath: definitionPath,
            version: 1,
            replacementKey: "fisheye",
            name: "ui_editor_effect_fisheye_title",
            description: "ui_editor_effect_fisheye_description",
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
                "shaders/effects/fisheye.frag",
                "shaders/effects/fisheye.vert",
            ],
            functions: nil,
            gizmos: nil,
            extraFields: options.definitionExtra ? ["future": .bool(true)] : [:],
            unknownFieldPaths: options.definitionExtra ? ["future"] : [],
            rawSHA256: options.definitionHash
        )
    }

    static func descriptor(_ options: Options = .init()) -> SceneRenderDescriptor {
        let authoredConstants = constants(options)
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
                constantShaderValues: authoredConstants,
                constantShaderValueKeys: Array(authoredConstants.keys).sorted()
            )]
        )
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "\(materialPath)#0",
            materialPath: materialPath,
            materialRawSHA256: options.materialHash,
            passIndex: 0,
            shaderPath: "effects/fisheye",
            texturePaths: [],
            textureSlots: [],
            userTextureInputs: [],
            combos: [:],
            constantShaderValues: [:],
            userShaderValues: options.userShaderValues,
            blending: options.blending,
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: options.alphaWriting
        )
        return .init(
            layers: [.init(
                id: layerID,
                contentKind: "composition",
                utilityLayer: .init(kind: .composition),
                childLayerIDs: options.utilityChildren,
                dependencyLayerIDs: options.utilityDependencies,
                effects: [effect]
            )],
            materialPasses: [material],
            effectDefinitions: [definition(options)]
        )
    }

    static func graph(blocker: Bool = false) -> Graph {
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: descriptorID
        )
        let input = Graph.TextureIdentity(
            kind: .layerSource,
            layerID: layerID,
            effect: nil,
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
        blocker: Bool = false
    ) -> SceneFisheyeZeroDistortionPlan? {
        SceneAuthoredFisheyeZeroDistortionPlanner.plan(
            graph: graph(blocker: blocker),
            descriptor: descriptor(options),
            shaderContracts: contracts
        )
    }

    static func mutatedContract(
        _ contract: SceneShaderContract
    ) -> SceneShaderContract {
        let stage = contract.stages[1]
        let mutated = SceneShaderContract.Stage(
            kind: stage.kind,
            relativePath: stage.relativePath,
            source: stage.source + " ",
            rawSHA256: stage.rawSHA256,
            includes: stage.includes,
            annotations: stage.annotations,
            declarations: stage.declarations
        )
        return .init(
            identity: contract.identity,
            sourceKind: contract.sourceKind,
            stages: [contract.stages[0], mutated],
            diagnostics: contract.diagnostics,
            canonicalSHA256: contract.canonicalSHA256
        )
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let contracts = SceneShaderContractLoader().load(
            shaderReferences: ["effects/fisheye"],
            rootURL: root
        )
        let accepted = plan(contracts: contracts)

        var center = Options(); center.center = [0.49, 0.5]
        var distortion = Options(); distortion.distortion = [0.15]
        var dynamic = Options()
        dynamic.distortionKind = "binding"; dynamic.distortionBinding = "strength"
        var timeline = Options(); timeline.distortionTimeline = 1
        var diagnostics = Options(); diagnostics.distortionDiagnostics = ["unsupported"]
        var size = Options(); size.size = [1.0]
        var background = Options(); background.background = 1
        var missingBackground = Options(); missingBackground.omitBackground = true
        var extraConstant = Options(); extraConstant.extraConstant = true
        var extraCombo = Options(); extraCombo.extraCombo = true
        var definitionHash = Options()
        definitionHash.definitionHash = String(repeating: "0", count: 64)
        var definitionExtra = Options(); definitionExtra.definitionExtra = true
        var materialHash = Options()
        materialHash.materialHash = String(repeating: "0", count: 64)
        var state = Options(); state.blending = "additive"
        var userShader = Options(); userShader.userShaderValues = ["size": "property"]
        var alphaWriting = Options(); alphaWriting.alphaWriting = "enabled"
        var hidden = Options(); hidden.visible = false
        var children = Options(); children.utilityChildren = [1]
        var dependencies = Options(); dependencies.utilityDependencies = [1]

        let rejected = [
            center, distortion, dynamic, timeline, diagnostics, size,
            background, missingBackground, extraConstant, extraCombo,
            definitionHash, definitionExtra, materialHash, state,
            userShader, alphaWriting, hidden, children, dependencies,
        ].allSatisfy { plan(options: $0, contracts: contracts) == nil }
        let shaderMutationRejected = contracts.first.map {
            plan(contracts: [mutatedContract($0)]) == nil
        } ?? false
        let result: [String: Any] = [
            "canonical": contracts.first?.canonicalSHA256 ?? "",
            "profileResolved":
                SceneFisheyeZeroDistortionShaderProfile.resolve(contracts) == .stock,
            "accepted": accepted != nil,
            "center": accepted.map { [$0.center.x, $0.center.y] } ?? [],
            "size": accepted?.size ?? -1,
            "utilityCaptureShape": accepted?.renderGraph.renderTargets.isEmpty == true,
            "strictVariantsRejected": rejected,
            "shaderMutationRejected": shaderMutationRejected,
            "blockerRejected": plan(contracts: contracts, blocker: true) == nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneFisheyeZeroDistortionPlannerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-fisheye-zero-distortion-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-fisheye-zero-distortion"
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
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary), str(STOCK_ROOT)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_exact_stock_zero_distortion_profile_is_admitted(self) -> None:
        self.assertTrue(self.result["profileResolved"])
        self.assertTrue(self.result["accepted"])
        self.assertEqual(self.result["center"], [0.5, 0.5])
        self.assertAlmostEqual(self.result["size"], 1.2, places=6)
        self.assertTrue(self.result["utilityCaptureShape"])

    def test_dynamic_nonzero_and_stock_variants_fail_closed(self) -> None:
        self.assertTrue(self.result["strictVariantsRejected"])
        self.assertTrue(self.result["shaderMutationRejected"])
        self.assertTrue(self.result["blockerRejected"])

    def test_shader_contract_fingerprint_is_stable(self) -> None:
        self.assertEqual(
            self.result["canonical"],
            "4b3aefcf2a7a96a5180d064925b8246fe073e0c1f6ff4c1a4b2b002fb97d94c2",
        )


if __name__ == "__main__":
    unittest.main()
