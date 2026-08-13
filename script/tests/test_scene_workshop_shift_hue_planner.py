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


from scene_swift_source_sets import scene_swift_sources


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
AUTHORED_EFFECT_PLANNING_SOURCES = scene_swift_sources(
    "authored_effect_planning_support"
)
REAL_SAMPLE_CACHE = sample_cache_root("3767460992")
SWIFT_SOURCES = [
    *AUTHORED_EFFECT_PLANNING_SOURCES,
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "RenderGraph/SceneWorkshopShiftHueExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredWorkshopShiftHuePlanner.swift",
    SOURCE_ROOT / "RenderGraph/SceneWorkshopAudioBarsExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredWorkshopAudioBarsPlanner.swift",
    SOURCE_ROOT / "RenderGraph/SceneWorkshopGradientExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredWorkshopGradientPlanner.swift",
    SOURCE_ROOT / "Runtime/SceneAudioSpectrum.swift",
    SOURCE_ROOT / "Runtime/SceneAudioResponse.swift",
    SOURCE_ROOT / "RenderGraph/SceneAudioResponseAdmission.swift",
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
            diagnostics: mode == "diagnostic"
                ? contract.diagnostics + [.init(
                    code: .malformedAnnotation,
                    message: "fixture",
                    relativePath: nil,
                    line: nil
                )]
                : contract.diagnostics,
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

    static let audioDefinitionPath =
        "effects/workshop/3082978660/enhanced_simple_audio_bars/effect.json"
    static let audioMaterialPath =
        "materials/workshop/3082978660/effects/simple_audio_bars.json"
    static let audioShaderIdentity = "workshop/3082978660/effects/Simple_Audio_Bars"

    static func audioValue(_ components: [Double]) -> SceneDocument.ShaderValue {
        .init(
            rawValue: components.map { String($0) }.joined(separator: " "),
            valueKind: components.count == 1 ? "number" : "vector",
            userBinding: nil,
            components: components
        )
    }

    static func audioConstants(extra: Bool = false) -> [String: SceneDocument.ShaderValue] {
        var values = [
            "Anti-alias blurring ": audioValue([0.05, 0]),
            "Bar color": audioValue([1, 0, 1]),
            "Bar count": audioValue([32]),
            "Bar spacing": audioValue([0.45]),
            "Circle start/end angles": audioValue([0, 360]),
            "Lower/upper bar bounds": audioValue([0, 1]),
            "Minimum height (will be multiplied by the bar width)": audioValue([0]),
            "Radius": audioValue([1]),
            "Segment count": audioValue([24]),
            "Segment spacing": audioValue([0.26]),
            "Segment threshold": audioValue([1]),
            "ui_editor_properties_opacity": audioValue([1]),
            "Volume factor": audioValue([0.75]),
        ]
        if extra { values["unexpected"] = audioValue([1]) }
        return values
    }

    static func audioDefinition(mutated: Bool = false) -> SceneEffectDefinition {
        .init(
            relativePath: audioDefinitionPath,
            version: 1,
            replacementKey: "enhanced_simple_audio_bars",
            name: mutated ? "Other" : "Enhanced Simple Audio Bars",
            description: nil,
            group: "localeffects",
            performance: nil,
            previewPath: nil,
            editable: false,
            passes: [.init(
                passIndex: 0,
                materialPath: audioMaterialPath,
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
                audioMaterialPath,
                "shaders/workshop/3082978660/effects/simple_audio_bars.frag",
                "shaders/workshop/3082978660/effects/simple_audio_bars.vert",
            ],
            functions: nil,
            gizmos: nil,
            extraFields: [:],
            unknownFieldPaths: []
        )
    }

    static func audioDescriptor(
        shape: Int = 4,
        resolution: Int = 64,
        extraConstant: Bool = false,
        texture: Bool = false,
        badHash: Bool = false,
        definitionMutation: Bool = false,
        priorInput: Bool = false
    ) -> SceneRenderDescriptor {
        let paths = texture ? ["unexpected.png"] : []
        let combos = ["RESOLUTION": resolution, "SEGMENT": 1, "SHAPE": shape]
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            texturePaths: paths,
            textureSlots: paths,
            userTextureInputs: [],
            combos: combos,
            constantShaderValues: audioConstants(extra: extraConstant)
        )
        let effect = SceneRenderDescriptor.EffectDescriptor(
            id: "945#effect#947",
            file: audioDefinitionPath,
            visible: true,
            passes: [pass]
        )
        let prior = SceneRenderDescriptor.EffectDescriptor(
            id: "945#effect#900",
            file: "effects/prior/effect.json",
            visible: true,
            passes: []
        )
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "\(audioMaterialPath)#0",
            materialPath: audioMaterialPath,
            materialRawSHA256: badHash
                ? String(repeating: "0", count: 64)
                : "719776f9d2011b8e02848b7a77373131bc4d7655ee28eb5db884c18d3f963eb5",
            passIndex: 0,
            shaderPath: audioShaderIdentity,
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
                contentKind: "image",
                effects: priorInput ? [prior, effect] : [effect]
            )],
            materialPasses: [material],
            effectDefinitions: [audioDefinition(mutated: definitionMutation)]
        )
    }

    static func audioGraph(priorInput: Bool = false, blocker: Bool = false) -> Graph {
        let key = Graph.EffectKey(
            layerID: 945,
            effectIndex: priorInput ? 1 : 0,
            descriptorID: "945#effect#947"
        )
        let prior = Graph.EffectKey(
            layerID: 945, effectIndex: 0, descriptorID: "945#effect#900"
        )
        let input = Graph.TextureIdentity(
            kind: priorInput ? .effectOutput : .layerSource,
            layerID: 945,
            effect: priorInput ? prior : nil,
            name: nil
        )
        let output = Graph.TextureIdentity(
            kind: .effectOutput, layerID: 945, effect: key, name: nil
        )
        return .init(
            layerID: 945,
            effects: [.init(
                key: key,
                definitionPath: audioDefinitionPath,
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
                materialPath: audioMaterialPath,
                materialPassID: "\(audioMaterialPath)#0",
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

    static func audioAccepted(
        contracts: [SceneShaderContract],
        shape: Int = 4,
        resolution: Int = 64,
        extraConstant: Bool = false,
        texture: Bool = false,
        badHash: Bool = false,
        definitionMutation: Bool = false,
        priorInput: Bool = false,
        blocker: Bool = false,
        role: SceneAuthoredEffectInputRole = .layerSource
    ) -> Bool {
        SceneAuthoredWorkshopAudioBarsPlanner.plan(
            graph: audioGraph(priorInput: priorInput, blocker: blocker),
            descriptor: audioDescriptor(
                shape: shape,
                resolution: resolution,
                extraConstant: extraConstant,
                texture: texture,
                badHash: badHash,
                definitionMutation: definitionMutation,
                priorInput: priorInput
            ),
            shaderContracts: contracts,
            inputRole: role
        ) != nil
    }

    static let gradientDefinitionPath =
        "effects/workshop/3347128360/gradient_generator/effect.json"
    static let gradientMaterialPath =
        "materials/workshop/3347128360/effects/gradient_generator.json"
    static let gradientShaderIdentity =
        "workshop/3347128360/effects/gradient_generator"

    static func gradientConstants(extra: Bool = false) -> [String: SceneDocument.ShaderValue] {
        var values = [
            "Gamma": audioValue([2.2]),
            "center": audioValue([0, 0]),
            "color1": audioValue([1, 0, 0]),
            "color2": audioValue([1, 0.6470588235294118, 0]),
            "color3": audioValue([0, 0, 1]),
            "color4": audioValue([0, 1, 1]),
            "color5": audioValue([1, 0, 1]),
            "color6": audioValue([1, 1, 0]),
            "ratio": audioValue([1]),
            "rotation": audioValue([0]),
            "scale": audioValue([1]),
            "ui_editor_properties_feather": audioValue([1]),
            "ui_editor_properties_offset": audioValue([0]),
            "ui_editor_properties_opacity": audioValue([1]),
        ]
        if extra { values["unexpected"] = audioValue([1]) }
        return values
    }

    static func gradientDefinition(gizmos: Bool = true) -> SceneEffectDefinition {
        .init(
            relativePath: gradientDefinitionPath,
            version: 1,
            replacementKey: "gradient_generator",
            name: "Gradient Generator",
            description: nil,
            group: "localeffects",
            performance: nil,
            previewPath: nil,
            editable: false,
            passes: [.init(
                passIndex: 0,
                materialPath: gradientMaterialPath,
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
                gradientMaterialPath,
                "shaders/workshop/3347128360/effects/gradient_generator.frag",
                "shaders/workshop/3347128360/effects/gradient_generator.vert",
            ],
            functions: nil,
            gizmos: gizmos ? .array([]) : nil,
            extraFields: [:],
            unknownFieldPaths: []
        )
    }

    static func gradientDescriptor(
        shape: Int = 3,
        colorCount: Int = 24,
        extraConstant: Bool = false,
        texture: Bool = false,
        badHash: Bool = false,
        gizmos: Bool = true,
        priorInput: Bool = false
    ) -> SceneRenderDescriptor {
        let paths = texture ? ["unexpected.png"] : []
        let effect = SceneRenderDescriptor.EffectDescriptor(
            id: "945#effect#952",
            file: gradientDefinitionPath,
            visible: true,
            passes: [.init(
                passIndex: 0,
                texturePaths: paths,
                textureSlots: paths,
                userTextureInputs: [],
                combos: ["NCOLORS": colorCount, "SHAPE": shape],
                constantShaderValues: gradientConstants(extra: extraConstant)
            )]
        )
        let prior = SceneRenderDescriptor.EffectDescriptor(
            id: "945#effect#900",
            file: "effects/prior/effect.json",
            visible: true,
            passes: []
        )
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "\(gradientMaterialPath)#0",
            materialPath: gradientMaterialPath,
            materialRawSHA256: badHash
                ? String(repeating: "0", count: 64)
                : "b8f11556196ee64a4429da813cc007923b9426723533163e3e73152ef009d4ce",
            passIndex: 0,
            shaderPath: gradientShaderIdentity,
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
                contentKind: "solid",
                effects: priorInput ? [prior, effect] : [effect]
            )],
            materialPasses: [material],
            effectDefinitions: [gradientDefinition(gizmos: gizmos)]
        )
    }

    static func gradientGraph(priorInput: Bool = false) -> Graph {
        let key = Graph.EffectKey(
            layerID: 945,
            effectIndex: priorInput ? 1 : 0,
            descriptorID: "945#effect#952"
        )
        let prior = Graph.EffectKey(
            layerID: 945, effectIndex: 0, descriptorID: "945#effect#900"
        )
        let input = Graph.TextureIdentity(
            kind: priorInput ? .effectOutput : .layerSource,
            layerID: 945,
            effect: priorInput ? prior : nil,
            name: nil
        )
        let output = Graph.TextureIdentity(
            kind: .effectOutput, layerID: 945, effect: key, name: nil
        )
        return .init(
            layerID: 945,
            effects: [.init(
                key: key,
                definitionPath: gradientDefinitionPath,
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
                materialPath: gradientMaterialPath,
                materialPassID: "\(gradientMaterialPath)#0",
                target: output,
                bindings: [],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            )],
            finalOutput: output,
            blockers: []
        )
    }

    static func gradientAccepted(
        contracts: [SceneShaderContract],
        shape: Int = 3,
        colorCount: Int = 24,
        extraConstant: Bool = false,
        texture: Bool = false,
        badHash: Bool = false,
        gizmos: Bool = true,
        priorInput: Bool = false,
        role: SceneAuthoredEffectInputRole = .layerSource
    ) -> Bool {
        SceneAuthoredWorkshopGradientPlanner.plan(
            graph: gradientGraph(priorInput: priorInput),
            descriptor: gradientDescriptor(
                shape: shape,
                colorCount: colorCount,
                extraConstant: extraConstant,
                texture: texture,
                badHash: badHash,
                gizmos: gizmos,
                priorInput: priorInput
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
        let audioContracts = SceneShaderContractLoader().load(
            shaderReferences: [audioShaderIdentity],
            rootURL: root
        )
        let gradientContracts = SceneShaderContractLoader().load(
            shaderReferences: [gradientShaderIdentity],
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
            "audioShape4Accepted": audioAccepted(contracts: audioContracts),
            "audioShape5Accepted": audioAccepted(contracts: audioContracts, shape: 5),
            "audioPriorAccepted": audioAccepted(
                contracts: audioContracts,
                priorInput: true,
                role: .priorEffectOutput
            ),
            "audioProfileRejected": [
                audioAccepted(contracts: audioContracts, shape: 3),
                audioAccepted(contracts: audioContracts, resolution: 32),
                audioAccepted(contracts: audioContracts, extraConstant: true),
                audioAccepted(contracts: audioContracts, texture: true),
                audioAccepted(contracts: audioContracts, badHash: true),
                audioAccepted(contracts: audioContracts, definitionMutation: true),
                audioAccepted(contracts: audioContracts, blocker: true),
                audioAccepted(contracts: audioContracts, priorInput: true),
            ].allSatisfy { !$0 },
            "audioContractsRejected": contractMutations.allSatisfy {
                !audioAccepted(contracts: mutate(audioContracts, $0))
            },
            "audioCandidateDetected": SceneAuthoredWorkshopAudioBarsPlanner.containsCandidate(
                graph: audioGraph()
            ),
            "gradientAccepted": gradientAccepted(contracts: gradientContracts),
            "gradientPriorAccepted": gradientAccepted(
                contracts: gradientContracts,
                priorInput: true,
                role: .priorEffectOutput
            ),
            "gradientProfileRejected": [
                gradientAccepted(contracts: gradientContracts, shape: 2),
                gradientAccepted(contracts: gradientContracts, colorCount: 20),
                gradientAccepted(contracts: gradientContracts, extraConstant: true),
                gradientAccepted(contracts: gradientContracts, texture: true),
                gradientAccepted(contracts: gradientContracts, badHash: true),
                gradientAccepted(contracts: gradientContracts, gizmos: false),
                gradientAccepted(contracts: gradientContracts, priorInput: true),
            ].allSatisfy { !$0 },
            "gradientContractsRejected": contractMutations.allSatisfy {
                !gradientAccepted(contracts: mutate(gradientContracts, $0))
            },
            "gradientCandidateDetected": SceneAuthoredWorkshopGradientPlanner.containsCandidate(
                graph: gradientGraph()
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
