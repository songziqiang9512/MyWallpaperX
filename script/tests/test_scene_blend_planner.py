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
LEGACY_SAMPLE = sample_cache_root("2067939514")
CURRENT_STOCK_SAMPLE = sample_cache_root("2134765860")
SIBLING_SAMPLE = sample_cache_root("2419444134")
BUNDLE_STOCK = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects/blend"
)
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
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
    SOURCE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Properties/SceneTimeOfDayEffectScriptProgram.swift",
    SOURCE_ROOT / "Properties/SceneTimeOfDayEffectScriptCompiler.swift",
    SOURCE_ROOT / "RenderGraph/SceneBlendShaderProfile.swift",
    SOURCE_ROOT / "RenderGraph/SceneBlendExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredBlendPlanner.swift",
]


HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
        let timeline: Int?
        let timelineDiagnostics: [String]
        let scriptSource: String?
        let bindingKeys: [String]

        init(
            rawValue: String, valueKind: String, userBinding: String?,
            components: [Double]?, timeline: Int? = nil,
            timelineDiagnostics: [String] = [], scriptSource: String? = nil,
            bindingKeys: [String] = []
        ) {
            self.rawValue = rawValue
            self.valueKind = valueKind
            self.userBinding = userBinding
            self.components = components
            self.timeline = timeline
            self.timelineDiagnostics = timelineDiagnostics
            self.scriptSource = scriptSource
            self.bindingKeys = bindingKeys
        }
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
    let texturePropertyKeys: [String]
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    static let layerID = 342
    static let descriptorID = "342#effect#0"
    static let definitionPath = "effects/blend/effect.json"
    static let materialPath = "materials/effects/blend.json"
    static let shaderIdentity = "effects/blend"
    static let assetPath = "materials/882671 (1).tex"

    struct Options {
        var contentKind = "solid"
        var materialHash =
            "c2478eb0d0692751dcb504995efb02a684d21ced44de1ea04212eb221e824fa7"
        var definitionVersion = 1
        var visible: Bool? = true
        var propertyKey: String? = "custombackground"
        var propertyKind = SceneEffectTextureInput.Kind.property
        var declaredProperty = true
        var asset = assetPath
        var texturePathsMatch = true
        var blendMode = 0
        var writeAlpha = 0
        var transformUV = 0
        var transformRepeat = 0
        var opacityMask = 0
        var textureCount = 1
        var multiply = 1.0
        var alpha = 1.0
        var boundAlpha = false
        var angle = 0.0
        var scale = 1.0
        var offset = [0.0, 0.0]
        var boundMultiply = false
        var timeOfDayMultiply = false
        var extraCombo = false
        var extraConstant = false
        var renderState = "normal"
    }

    static func value(
        _ components: [Double],
        kind: String = "number",
        binding: Bool = false
    ) -> SceneDocument.ShaderValue {
        .init(
            rawValue: components.map { String($0) }.joined(separator: " "),
            valueKind: binding ? "binding" : kind,
            userBinding: binding ? "fixture" : nil,
            components: components
        )
    }

    static func combos(_ options: Options) -> [String: Int] {
        var result = [
            "BLENDMODE": options.blendMode,
            "WRITEALPHA": options.writeAlpha,
            "TRANSFORMUV": options.transformUV,
            "TRANSFORMREPEAT": options.transformRepeat,
            "OPACITYMASK": options.opacityMask,
            "NUMBLENDTEXTURES": options.textureCount,
        ]
        if options.extraCombo { result["OTHER"] = 1 }
        return result
    }

    static func constants(_ options: Options) -> [String: SceneDocument.ShaderValue] {
        var result = [
            "multiply": value([options.multiply], binding: options.boundMultiply),
            "alpha": value([options.alpha], binding: options.boundAlpha),
            "blendangle": value([options.angle]),
            "blendoffset": value(options.offset, kind: "vector"),
            "blendscale": value([options.scale]),
        ]
        if options.timeOfDayMultiply {
            result["multiply"] = .init(
                rawValue: "1", valueKind: "binding", userBinding: nil, components: [1],
                scriptSource: timeOfDaySource,
                bindingKeys: ["script", "user", "value"]
            )
        }
        if options.extraConstant { result["other"] = value([1]) }
        return result
    }

    static func definition(_ options: Options) -> SceneEffectDefinition {
        .init(
            relativePath: definitionPath,
            version: options.definitionVersion,
            replacementKey: "blend",
            name: "ui_editor_effect_blend_title",
            description: "ui_editor_effect_blend_description",
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
                "shaders/effects/blend.frag",
                "shaders/effects/blend.vert",
            ],
            functions: nil,
            gizmos: nil,
            extraFields: [:],
            unknownFieldPaths: []
        )
    }

    static func descriptor(_ options: Options = .init()) -> SceneRenderDescriptor {
        let userInputs: [SceneEffectTextureInput?] = options.propertyKey.map {
            [nil, .init(kind: options.propertyKind, value: $0)]
        } ?? []
        let effect = SceneRenderDescriptor.EffectDescriptor(
            id: descriptorID,
            file: definitionPath,
            visible: options.visible,
            passes: [.init(
                passIndex: 0,
                texturePaths: options.texturePathsMatch ? [options.asset] : ["other.tex"],
                textureSlots: [nil, options.asset],
                userTextureInputs: userInputs,
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
            blending: options.renderState,
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
            effectDefinitions: [definition(options)],
            texturePropertyKeys: options.declaredProperty ? ["custombackground"] : []
        )
    }

    static func graph(
        priorInput: Bool = false,
        blocker: Bool = false,
        wrongNode: Bool = false,
        namedAsset: Bool = false
    ) -> Graph {
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: descriptorID
        )
        let priorKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "prior"
        )
        let input = Graph.TextureIdentity(
            kind: priorInput ? .effectOutput : .layerSource,
            layerID: layerID,
            effect: priorInput ? priorKey : nil,
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
        SceneAuthoredBlendPlanner.plan(
            graph: graph(
                priorInput: priorInput,
                blocker: blocker,
                wrongNode: wrongNode
            ),
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
        let roots = CommandLine.arguments.dropFirst().map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let loader = SceneShaderContractLoader()
        let contracts = loader.load(
            shaderReferences: [shaderIdentity],
            rootURL: roots[0]
        )
        let currentStock = loader.load(shaderReferences: [shaderIdentity], rootURL: roots[1])
        let sibling = loader.load(shaderReferences: [shaderIdentity], rootURL: roots[2])
        let plan = SceneAuthoredBlendPlanner.plan(
            graph: graph(),
            descriptor: descriptor(),
            shaderContracts: contracts
        )
        var dynamic = Options(); dynamic.timeOfDayMultiply = true
        let dynamicPlan = SceneAuthoredBlendPlanner.plan(
            graph: graph(), descriptor: descriptor(dynamic), shaderContracts: contracts
        )
        var writeAlpha = Options(); writeAlpha.writeAlpha = 1; writeAlpha.alpha = 0.5
        let writeAlphaPlan = SceneAuthoredBlendPlanner.plan(
            graph: graph(), descriptor: descriptor(writeAlpha), shaderContracts: contracts
        )

        var badHash = Options(); badHash.materialHash = String(repeating: "0", count: 64)
        var badVersion = Options(); badVersion.definitionVersion = 2
        var hidden = Options(); hidden.visible = false
        var text = Options(); text.contentKind = "text"
        var video = Options(); video.contentKind = "video"
        var system = Options(); system.propertyKind = .system
        var undeclared = Options(); undeclared.declaredProperty = false
        var named = Options(); named.asset = "_rt_imageLayerComposite_1_a"
        var paths = Options(); paths.texturePathsMatch = false
        var mode = Options(); mode.blendMode = 1
        var invalidWriteAlpha = Options(); invalidWriteAlpha.writeAlpha = 2
        var transform = Options(); transform.transformUV = 1
        var repeatUV = Options(); repeatUV.transformRepeat = 1
        var mask = Options(); mask.opacityMask = 1
        var count = Options(); count.textureCount = 2
        var multiply = Options(); multiply.multiply = 2.1
        var outputAlpha = Options(); outputAlpha.alpha = 0.5
        var boundOutputAlpha = writeAlpha; boundOutputAlpha.boundAlpha = true
        var angle = Options(); angle.angle = 1
        var scale = Options(); scale.scale = 0.5
        var offset = Options(); offset.offset = [0.1, 0]
        var bound = Options(); bound.boundMultiply = true
        var combo = Options(); combo.extraCombo = true
        var constant = Options(); constant.extraConstant = true
        var state = Options(); state.renderState = "additive"
        var assetOnly = Options(); assetOnly.propertyKey = nil

        let contractMutations = [
            "source", "raw", "path", "identity", "sourceKind", "diagnostic",
            "canonical", "duplicate",
        ]
        let result: [String: Bool] = [
            "profileResolved": SceneBlendShaderProfile.resolve(contracts)
                == .legacySingleTexture,
            "currentStockProfileResolved": SceneBlendShaderProfile.resolve(currentStock)
                == .transformRepeatRequirementSingleTexture,
            "currentStockProfileAccepted": accepted(contracts: currentStock),
            "parametersPreserved": plan.map {
                $0.layerID == layerID
                    && $0.effectKey.descriptorID == descriptorID
                    && $0.blendMode == 0
                    && $0.multiply == 1
                    && $0.assetTexturePath == assetPath
                    && $0.userPropertyKey == "custombackground"
                    && $0.executedUserPropertyKeys == ["custombackground"]
            } ?? false,
            "timeOfDayMultiplyAccepted": dynamicPlan.map {
                $0.dynamicMultiplyBinding?.definition.target
                    == .effectConstant(
                        layerID: layerID, effectIndex: 0, passIndex: 0, name: "multiply"
                    )
                    && $0.liveMultiplyTarget == $0.dynamicMultiplyBinding?.definition.target
            } ?? false,
            "writeAlphaAccepted": writeAlphaPlan.map {
                $0.writesAlpha && $0.alphaMultiply == 0.5
            } ?? false,
            "assetFallbackAccepted": accepted(options: assetOnly, contracts: contracts),
            "priorAccepted": accepted(
                contracts: contracts,
                priorInput: true,
                role: .priorEffectOutput
            ),
            "wrongRoleRejected": !accepted(
                contracts: contracts,
                priorInput: true,
                role: .layerSource
            ),
            "profileMutationsRejected": contractMutations.allSatisfy {
                !accepted(contracts: mutate(contracts, $0))
            },
            "siblingProfileRejected": SceneBlendShaderProfile.resolve(sibling) == nil
                && !accepted(contracts: sibling),
            "descriptorMutationsRejected": [
                badHash, badVersion, hidden, text, video, system, undeclared,
                named, paths, mode, invalidWriteAlpha, transform, repeatUV, mask, count,
                multiply, outputAlpha, boundOutputAlpha, angle, scale, offset, bound, combo,
                constant, state,
            ].allSatisfy { !accepted(options: $0, contracts: contracts) },
            "graphMutationsRejected": !accepted(contracts: contracts, blocker: true)
                && !accepted(contracts: contracts, wrongNode: true),
            "candidateDetected": SceneAuthoredBlendPlanner.containsCandidate(graph: graph()),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static let timeOfDaySource = """
    'use strict';
    import * as WEMath from 'WEMath';
    const START_HOUR = 7;
    const END_HOUR = 18;
    export function update(value) {
        return Math.max(
            WEMath.smoothStep(START_HOUR / 24, (START_HOUR - 0.004) / 24, engine.timeOfDay),
            WEMath.smoothStep((END_HOUR - 0.004) / 24, END_HOUR / 24, engine.timeOfDay)
        );
    }
    """
}
'''


class SceneBlendPlannerTests(unittest.TestCase):
    def test_exact_legacy_profile_is_admitted_and_siblings_fail_closed(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        roots = [LEGACY_SAMPLE, CURRENT_STOCK_SAMPLE, SIBLING_SAMPLE, BUNDLE_STOCK]
        for root in roots:
            shader = root / "shaders/effects/blend.frag"
            if not shader.is_file():
                self.skipTest(f"Blend shader fixture unavailable: {shader}")
        with tempfile.TemporaryDirectory(prefix="scene-blend-planner-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "scene-blend-planner"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-module-cache-path", str(root / "module-cache"),
                    "-o", str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary), *(str(path) for path in roots)],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        self.assertTrue(all(result.values()), result)


if __name__ == "__main__":
    unittest.main()
