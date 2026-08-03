#!/usr/bin/env python3
"""Exact stock Depth Parallax planner admission and fail-closed mutations."""

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
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects/depthparallax"
)
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderSourceGraph.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SOURCE_ROOT / "Resources/SceneShaderSourceGraphBuilder.swift",
    SOURCE_ROOT / "Resources/SceneShaderSourceResolver.swift",
    SOURCE_ROOT / "Resources/SceneResourceView.swift",
    SOURCE_ROOT / "Resources/SceneResourceIndex.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContractLoader.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContractLoader+SourceGraph.swift",
    SOURCE_ROOT / "RenderGraph/SceneDepthParallaxShaderProfile.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredDepthParallaxPlanner.swift",
]


HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
        let timeline: String?
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

    static let layerID = 85
    static let effectID = "85#effect#930"
    static let depthPath = "materials/depth_map"
    static let definitionPath = "effects/depthparallax/effect.json"
    static let definitionHash =
        "438775d010e2e35bbf7044766a736955d442542348fc4aff1510e982e07fc303"
    static let materialPath = "materials/effects/depthparallax.json"
    static let materialHash =
        "468a2a9fdb812bfa527e720426f69141cb99b2ae996e3fa951eaa74413874b3f"
    static let shaderIdentity = "effects/depthparallax"

    struct Options {
        var contentKind = "image"
        var effectCount = 1
        var visible: Bool? = true
        var instancePassCount = 1
        var slots: [String?] = [nil, Harness.depthPath]
        var paths = [Harness.depthPath]
        var userTexture = false
        var quality: Int? = nil
        var extraCombo = false
        var missingConstant = false
        var extraConstant = false
        var boundConstant = false
        var timelineConstant = false
        var scale = [-1.0, -1.0]
        var sensitivity = -1.59
        var center = 1.0
        var materialHash = Harness.materialHash
        var materialPath = Harness.materialPath
        var shaderIdentity = Harness.shaderIdentity
        var materialTexture = false
        var materialCombo = false
        var materialConstant = false
        var materialUserShader = false
        var blending = "normal"
        var depthTest = "disabled"
        var depthWrite = "disabled"
        var cullMode = "nocull"
        var alphaWriting: String? = nil
        var duplicateMaterial = false
        var definitionHash = Harness.definitionHash
        var definitionVersion = 1
        var definitionReplacement = "iris"
        var definitionGroup = "interactive"
        var definitionPerformance = "expensive"
        var definitionPassCount = 1
        var definitionBinding = false
        var definitionExtra = false
        var duplicateDefinition = false
    }

    struct GraphOptions {
        var blocker = false
        var extraEffect = false
        var extraNode = false
        var extraTarget = false
        var wrongDefinition = false
        var wrongNodeKind = false
        var wrongMaterial = false
        var binding = false
        var command = false
        var condition = false
        var wrongOutput = false
        var priorInput = false
    }

    static func value(
        _ components: [Double],
        vector: Bool = false,
        bound: Bool = false,
        timeline: Bool = false
    ) -> SceneDocument.ShaderValue {
        .init(
            rawValue: components.map { String($0) }.joined(separator: " "),
            valueKind: vector ? "vector" : "number",
            userBinding: bound ? "pointer" : nil,
            components: components,
            timeline: timeline ? "fixture" : nil,
            timelineDiagnostics: timeline ? ["fixture"] : []
        )
    }

    static func constants(
        _ options: Options
    ) -> [String: SceneDocument.ShaderValue] {
        var result = [
            "scale": value(
                options.scale,
                vector: true,
                bound: options.boundConstant,
                timeline: options.timelineConstant
            ),
            "sens": value([options.sensitivity]),
            "center": value([options.center]),
        ]
        if options.missingConstant { result.removeValue(forKey: "center") }
        if options.extraConstant { result["other"] = value([1]) }
        return result
    }

    static func combos(_ options: Options) -> [String: Int] {
        var result: [String: Int] = [:]
        if let quality = options.quality { result["QUALITY"] = quality }
        if options.extraCombo { result["OTHER"] = 1 }
        return result
    }

    static func definition(_ options: Options) -> SceneEffectDefinition {
        let pass = SceneEffectDefinition.Pass(
            passIndex: 0,
            materialPath: materialPath,
            target: nil,
            bindings: options.definitionBinding ? [.init(
                name: "g_Texture0",
                index: 0,
                conditions: nil,
                extraFields: [:]
            )] : [],
            compose: nil,
            command: nil,
            source: nil,
            conditions: nil,
            extraFields: [:]
        )
        return .init(
            relativePath: definitionPath,
            version: options.definitionVersion,
            replacementKey: options.definitionReplacement,
            name: "ui_editor_effect_depth_parallax_title",
            description: "ui_editor_effect_depth_parallax_description",
            group: options.definitionGroup,
            performance: options.definitionPerformance,
            previewPath: "preview/project.json",
            editable: nil,
            passes: Array(repeating: pass, count: options.definitionPassCount),
            framebuffers: [],
            dependencies: [
                materialPath,
                "shaders/effects/depthparallax.frag",
                "shaders/effects/depthparallax.vert",
            ],
            functions: nil,
            gizmos: nil,
            extraFields: options.definitionExtra ? ["other": .bool(true)] : [:],
            unknownFieldPaths: options.definitionExtra ? ["other"] : [],
            rawSHA256: options.definitionHash
        )
    }

    static func effect(_ options: Options) -> SceneRenderDescriptor.EffectDescriptor {
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            texturePaths: options.paths,
            textureSlots: options.slots,
            userTextureInputs: options.userTexture
                ? [nil, .init(name: "depth")] : [],
            combos: combos(options),
            constantShaderValues: constants(options)
        )
        return .init(
            id: effectID,
            file: definitionPath,
            visible: options.visible,
            passes: Array(repeating: pass, count: options.instancePassCount)
        )
    }

    static func descriptor(_ options: Options = .init()) -> SceneRenderDescriptor {
        let effect = effect(options)
        let effects = Array(repeating: effect, count: options.effectCount)
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "\(options.materialPath)#0",
            materialPath: options.materialPath,
            materialRawSHA256: options.materialHash,
            passIndex: 0,
            shaderPath: options.shaderIdentity,
            texturePaths: options.materialTexture ? ["other"] : [],
            textureSlots: options.materialTexture ? ["other"] : [],
            userTextureInputs: [],
            combos: options.materialCombo ? ["OTHER": 1] : [:],
            constantShaderValues: options.materialConstant
                ? ["other": value([1])] : [:],
            userShaderValues: options.materialUserShader
                ? ["other": "property"] : [:],
            blending: options.blending,
            depthTest: options.depthTest,
            depthWrite: options.depthWrite,
            cullMode: options.cullMode,
            alphaWriting: options.alphaWriting
        )
        let materials = Array(
            repeating: material,
            count: options.duplicateMaterial ? 2 : 1
        )
        let exactDefinition = definition(options)
        let definitions = Array(
            repeating: exactDefinition,
            count: options.duplicateDefinition ? 2 : 1
        )
        return .init(
            layers: [.init(
                id: layerID,
                contentKind: options.contentKind,
                effects: effects
            )],
            materialPasses: materials,
            effectDefinitions: definitions
        )
    }

    static func graph(_ options: GraphOptions = .init()) -> Graph {
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: effectID
        )
        let priorKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "prior"
        )
        let input = Graph.TextureIdentity(
            kind: options.priorInput ? .effectOutput : .layerSource,
            layerID: layerID,
            effect: options.priorInput ? priorKey : nil,
            name: nil
        )
        let output = Graph.TextureIdentity(
            kind: .effectOutput,
            layerID: layerID,
            effect: key,
            name: nil
        )
        let wrongOutput = Graph.TextureIdentity(
            kind: .framebuffer,
            layerID: layerID,
            effect: key,
            name: "other"
        )
        let effect = Graph.Effect(
            key: key,
            definitionPath: options.wrongDefinition
                ? "effects/other/effect.json" : definitionPath,
            input: input,
            output: options.wrongOutput ? wrongOutput : output,
            nodeIndices: [0]
        )
        let node = Graph.Node(
            nodeIndex: 0,
            effect: key,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: options.wrongNodeKind ? .copy : .material,
            materialPath: options.wrongMaterial ? "materials/other.json" : materialPath,
            materialPassID: "\(materialPath)#0",
            target: options.wrongOutput ? wrongOutput : output,
            bindings: options.binding ? [.init(
                slot: 0,
                authoredName: nil,
                texture: input,
                conditions: nil
            )] : [],
            commandSource: options.command ? input : nil,
            commandTarget: nil,
            compose: nil,
            conditions: options.condition ? .bool(true) : nil
        )
        return .init(
            layerID: layerID,
            effects: options.extraEffect ? [effect, effect] : [effect],
            renderTargets: options.extraTarget ? [.init(
                texture: wrongOutput,
                extent: .init(kind: .input, first: nil, second: nil),
                format: nil,
                declaredUnique: false,
                clear: nil,
                uvs: nil,
                conditions: nil
            )] : [],
            nodes: options.extraNode ? [node, node] : [node],
            finalOutput: options.wrongOutput ? wrongOutput : output,
            blockers: options.blocker ? [.init(
                effect: key,
                definitionPassIndex: 0,
                reason: .unsupportedCondition,
                detail: "fixture"
            )] : []
        )
    }

    static func accepted(
        options: Options = .init(),
        graphOptions: GraphOptions = .init(),
        contracts: [SceneShaderContract],
        role: SceneAuthoredEffectInputRole = .layerSource
    ) -> Bool {
        SceneAuthoredDepthParallaxPlanner.plan(
            graph: graph(graphOptions),
            descriptor: descriptor(options),
            shaderContracts: contracts,
            inputRole: role
        ) != nil
    }

    static func mutate(
        _ contracts: [SceneShaderContract],
        mode: String
    ) -> [SceneShaderContract] {
        guard let contract = contracts.first else { return contracts }
        var stages = contract.stages
        if ["source", "raw", "path"].contains(mode) {
            let stage = stages[0]
            stages[0] = .init(
                kind: stage.kind,
                relativePath: mode == "path"
                    ? "shaders/effects/other.vert" : stage.relativePath,
                source: mode == "source" ? stage.source + "x" : stage.source,
                rawSHA256: mode == "raw"
                    ? String(repeating: "0", count: 64) : stage.rawSHA256,
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
        let root = URL(
            fileURLWithPath: CommandLine.arguments[1],
            isDirectory: true
        )
        let contracts = SceneShaderContractLoader().load(
            shaderReferences: [shaderIdentity],
            rootURL: root
        )
        let plan = SceneAuthoredDepthParallaxPlanner.plan(
            graph: graph(),
            descriptor: descriptor(),
            shaderContracts: contracts
        )

        var basic = Options(); basic.quality = 0
        var quality = Options(); quality.quality = 2

        var wrongHash = Options()
        wrongHash.definitionHash = String(repeating: "0", count: 64)
        var wrongMaterialHash = Options()
        wrongMaterialHash.materialHash = String(repeating: "0", count: 64)
        var wrongVersion = Options(); wrongVersion.definitionVersion = 2
        var wrongReplacement = Options(); wrongReplacement.definitionReplacement = "other"
        var wrongGroup = Options(); wrongGroup.definitionGroup = "other"
        var wrongPerformance = Options(); wrongPerformance.definitionPerformance = "cheap"
        var extraDefinitionPass = Options(); extraDefinitionPass.definitionPassCount = 2
        var definitionBinding = Options(); definitionBinding.definitionBinding = true
        var definitionExtra = Options(); definitionExtra.definitionExtra = true
        var duplicateDefinition = Options(); duplicateDefinition.duplicateDefinition = true
        var hidden = Options(); hidden.visible = false
        var extraEffect = Options(); extraEffect.effectCount = 2
        var extraInstancePass = Options(); extraInstancePass.instancePassCount = 2
        var badSlots = Options(); badSlots.slots = [depthPath]
        var slotZero = Options(); slotZero.slots = [depthPath, nil]
        var badPaths = Options(); badPaths.paths = ["other"]
        var userTexture = Options(); userTexture.userTexture = true
        var badQuality = Options(); badQuality.quality = 3
        var extraCombo = Options(); extraCombo.extraCombo = true
        var missingConstant = Options(); missingConstant.missingConstant = true
        var extraConstant = Options(); extraConstant.extraConstant = true
        var boundConstant = Options(); boundConstant.boundConstant = true
        var timelineConstant = Options(); timelineConstant.timelineConstant = true
        var zeroScale = Options(); zeroScale.scale = [0, 1]
        var largeScale = Options(); largeScale.scale = [2.01, 1]
        var badSensitivity = Options(); badSensitivity.sensitivity = 5.01
        var badCenter = Options(); badCenter.center = -0.01
        var video = Options(); video.contentKind = "video"
        var materialPath = Options(); materialPath.materialPath = "materials/other.json"
        var shader = Options(); shader.shaderIdentity = "effects/other"
        var materialTexture = Options(); materialTexture.materialTexture = true
        var materialCombo = Options(); materialCombo.materialCombo = true
        var materialConstant = Options(); materialConstant.materialConstant = true
        var materialUserShader = Options(); materialUserShader.materialUserShader = true
        var blending = Options(); blending.blending = "additive"
        var depthTest = Options(); depthTest.depthTest = "enabled"
        var alphaWriting = Options(); alphaWriting.alphaWriting = "enabled"
        var duplicateMaterial = Options(); duplicateMaterial.duplicateMaterial = true

        let optionRejections = [
            wrongHash, wrongMaterialHash, wrongVersion, wrongReplacement,
            wrongGroup, wrongPerformance, extraDefinitionPass,
            definitionBinding, definitionExtra, duplicateDefinition, hidden,
            extraEffect, extraInstancePass, badSlots, slotZero, badPaths,
            userTexture, badQuality, extraCombo, missingConstant,
            extraConstant, boundConstant, timelineConstant, zeroScale,
            largeScale, badSensitivity, badCenter, video, materialPath,
            shader, materialTexture, materialCombo, materialConstant,
            materialUserShader,
            blending, depthTest, alphaWriting, duplicateMaterial,
        ]

        var blocker = GraphOptions(); blocker.blocker = true
        var graphEffect = GraphOptions(); graphEffect.extraEffect = true
        var graphNode = GraphOptions(); graphNode.extraNode = true
        var graphTarget = GraphOptions(); graphTarget.extraTarget = true
        var graphDefinition = GraphOptions(); graphDefinition.wrongDefinition = true
        var nodeKind = GraphOptions(); nodeKind.wrongNodeKind = true
        var graphMaterial = GraphOptions(); graphMaterial.wrongMaterial = true
        var binding = GraphOptions(); binding.binding = true
        var command = GraphOptions(); command.command = true
        var condition = GraphOptions(); condition.condition = true
        var output = GraphOptions(); output.wrongOutput = true
        var prior = GraphOptions(); prior.priorInput = true
        let graphRejections = [
            blocker, graphEffect, graphNode, graphTarget, graphDefinition,
            nodeKind, graphMaterial, binding, command, condition, output,
        ]
        let contractMutations = [
            "source", "raw", "path", "identity", "sourceKind",
            "diagnostic", "canonical", "duplicate",
        ]

        let result: [String: Bool] = [
            "accepted": plan != nil,
            "parametersPreserved": plan.map {
                $0.depthTexturePath == depthPath
                    && $0.scale.x == -1 && $0.scale.y == -1
                    && $0.sensitivity == -1.59
                    && $0.center == 1
                    && $0.quality.sampleCount == 24
            } ?? false,
            "qualityBranches": [
                SceneAuthoredDepthParallaxPlanner.plan(
                    graph: graph(), descriptor: descriptor(basic),
                    shaderContracts: contracts
                )?.quality.sampleCount,
                plan?.quality.sampleCount,
                SceneAuthoredDepthParallaxPlanner.plan(
                    graph: graph(), descriptor: descriptor(quality),
                    shaderContracts: contracts
                )?.quality.sampleCount,
            ] == [1, 24, 64],
            "optionsRejected": optionRejections.allSatisfy {
                !accepted(options: $0, contracts: contracts)
            },
            "graphsRejected": graphRejections.allSatisfy {
                !accepted(graphOptions: $0, contracts: contracts)
            },
            "wrongInputRoleRejected": !accepted(
                graphOptions: prior,
                contracts: contracts,
                role: .layerSource
            ),
            "contractsRejected": contractMutations.allSatisfy {
                !accepted(contracts: mutate(contracts, mode: $0))
            },
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneDepthParallaxPlannerTests(unittest.TestCase):
    def test_exact_profile_and_topology_fail_closed(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        if not (STOCK_ROOT / "effect.json").is_file():
            self.skipTest(f"stock Depth Parallax fixture unavailable: {STOCK_ROOT}")
        with tempfile.TemporaryDirectory(
            prefix="mwx-depth-parallax-planner-",
            dir="/private/tmp",
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "depth-parallax-planner"
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
                [str(binary), str(STOCK_ROOT)],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        self.assertTrue(all(result.values()), result)


if __name__ == "__main__":
    unittest.main()
