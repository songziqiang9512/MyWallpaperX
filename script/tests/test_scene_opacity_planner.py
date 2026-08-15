#!/usr/bin/env python3

from __future__ import annotations

import base64
import json
import shutil
import subprocess
import tempfile
import unittest
import sys
from pathlib import Path


SOURCE_SET_SCRIPT_ROOT = Path(__file__).resolve().parents[1]
if str(SOURCE_SET_SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SOURCE_SET_SCRIPT_ROOT))

from scene_swift_source_sets import scene_swift_sources


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
AUTHORED_EFFECT_PLANNING_SOURCES = scene_swift_sources(
    "authored_effect_planning_support"
)
SWIFT_SOURCES = [
    *AUTHORED_EFFECT_PLANNING_SOURCES,
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredOpacityPlanner.swift",
]

VERTEX_BASE64 = (
    "DQp1bmlmb3JtIG1hdDQgZ19Nb2RlbFZpZXdQcm9qZWN0aW9uTWF0cml4Ow0K"
    "dW5pZm9ybSB2ZWM0IGdfVGV4dHVyZTFSZXNvbHV0aW9uOw0KDQphdHRyaWJ1"
    "dGUgdmVjMyBhX1Bvc2l0aW9uOw0KYXR0cmlidXRlIHZlYzIgYV9UZXhDb29y"
    "ZDsNCg0KdmFyeWluZyB2ZWM0IHZfVGV4Q29vcmQ7DQoNCnZvaWQgbWFpbigp"
    "IHsNCglnbF9Qb3NpdGlvbiA9IG11bCh2ZWM0KGFfUG9zaXRpb24sIDEuMCks"
    "IGdfTW9kZWxWaWV3UHJvamVjdGlvbk1hdHJpeCk7DQoJdl9UZXhDb29yZC54"
    "eSA9IGFfVGV4Q29vcmQ7DQoJdl9UZXhDb29yZC56dyA9IHZlYzIodl9UZXhD"
    "b29yZC54ICogZ19UZXh0dXJlMVJlc29sdXRpb24ueiAvIGdfVGV4dHVyZTFS"
    "ZXNvbHV0aW9uLngsDQoJCQkJCQl2X1RleENvb3JkLnkgKiBnX1RleHR1cmUx"
    "UmVzb2x1dGlvbi53IC8gZ19UZXh0dXJlMVJlc29sdXRpb24ueSk7DQp9DQo="
)
FRAGMENT_BASE64 = (
    "DQp2YXJ5aW5nIHZlYzQgdl9UZXhDb29yZDsNCg0KdW5pZm9ybSBzYW1wbGVy"
    "MkQgZ19UZXh0dXJlMDsgLy8geyJoaWRkZW4iOnRydWV9DQp1bmlmb3JtIHNh"
    "bXBsZXIyRCBnX1RleHR1cmUxOyAvLyB7ImxhYmVsIjoidWlfZWRpdG9yX3By"
    "b3BlcnRpZXNfb3BhY2l0eV9tYXNrIiwibW9kZSI6Im9wYWNpdHltYXNrIiwi"
    "Y29tYm8iOiJNQVNLIiwicGFpbnRkZWZhdWx0Y29sb3IiOiIwIDAgMCAxIn0N"
    "Cg0KdW5pZm9ybSBmbG9hdCBnX1VzZXJBbHBoYTsgLy8geyJtYXRlcmlhbCI6"
    "ImFscGhhIiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19hbHBoYSIs"
    "ImRlZmF1bHQiOjEuMCwicmFuZ2UiOlswLjAxLCAxXX0NCg0Kdm9pZCBtYWlu"
    "KCkgew0KCXZlYzQgYWxiZWRvID0gdGV4U2FtcGxlMkQoZ19UZXh0dXJlMCwg"
    "dl9UZXhDb29yZC54eSk7DQojaWYgTUFTSw0KCWZsb2F0IG1hc2sgPSB0ZXhT"
    "YW1wbGUyRChnX1RleHR1cmUxLCB2X1RleENvb3JkLnp3KS5yOw0KI2Vsc2UN"
    "CglmbG9hdCBtYXNrID0gMS4wOw0KI2VuZGlmDQoJYWxiZWRvLmEgKj0gbWFz"
    "ayAqIGdfVXNlckFscGhhOw0KCQ0KCWdsX0ZyYWdDb2xvciA9IGFsYmVkbzsN"
    "Cn0NCg=="
)


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
            rawValue: String,
            valueKind: String,
            userBinding: String?,
            components: [Double]?,
            timeline: Int? = nil,
            timelineDiagnostics: [String] = [],
            scriptSource: String? = nil,
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
    static let definitionPath = "effects/opacity/effect.json"
    static let materialPath = "materials/effects/opacity.json"
    static let shaderIdentity = "effects/opacity"

    struct Options {
        var contentKind = "text"
        var alpha = 0.4
        var alphaKind = "number"
        var userBinding: String?
        var scriptSource: String?
        var bindingKeys: [String] = []
        var includesAlpha = true
        var extraInstanceConstant = false
        var instanceCombos: [String: Int] = [:]
        var instanceTexture = false
        var maskTexture = false
        var instanceUserTexture = false
        var materialCombos: [String: Int] = [:]
        var materialTexture = false
        var materialUserTexture = false
        var materialConstant = false
        var blending = "normal"
        var depthTest = "disabled"
        var materialPath = Harness.materialPath
        var materialRawSHA256 =
            "f32a0ee2080b2c79ee395e950ea072e28778d279c5d62e1cc76adbcd2d733747"
        var materialPassIndex = 0
        var shaderIdentity = Harness.shaderIdentity
        var visible: Bool? = true
        var definitionMutation = "none"
        var duplicateMaterial = false
    }

    struct GraphOptions {
        var priorInput = false
        var definitionPath = Harness.definitionPath
        var blocker = false
        var extraTarget = false
        var binding = false
        var command = false
        var condition = false
        var nodeKind = Graph.NodeKind.material
        var outputMismatch = false
        var extraEffect = false
        var extraNode = false
        var materialPath = Harness.materialPath
    }

    static func value(
        _ components: [Double],
        kind: String,
        binding: String? = nil,
        scriptSource: String? = nil,
        bindingKeys: [String] = []
    ) -> SceneDocument.ShaderValue {
        .init(
            rawValue: components.map { String($0) }.joined(separator: " "),
            valueKind: kind,
            userBinding: binding,
            components: components,
            scriptSource: scriptSource,
            bindingKeys: bindingKeys
        )
    }

    static func constants(_ options: Options) -> [String: SceneDocument.ShaderValue] {
        var result: [String: SceneDocument.ShaderValue] = [:]
        if options.includesAlpha {
            result["alpha"] = value(
                [options.alpha],
                kind: options.alphaKind,
                binding: options.userBinding,
                scriptSource: options.scriptSource,
                bindingKeys: options.bindingKeys
            )
        }
        if options.extraInstanceConstant {
            result["extra"] = value([1], kind: "number")
        }
        return result
    }

    static func definition(_ mutation: String) -> SceneEffectDefinition {
        let pass = SceneEffectDefinition.Pass(
            passIndex: 0,
            materialPath: mutation == "passMaterial" ? "materials/other.json" : materialPath,
            target: mutation == "passTarget" ? "other" : nil,
            bindings: mutation == "passBinding" ? [
                .init(name: "previous", index: 0, conditions: nil, extraFields: [:])
            ] : [],
            compose: mutation == "compose" ? .bool(true) : nil,
            command: nil,
            source: nil,
            conditions: nil,
            extraFields: mutation == "passExtra" ? ["extra": .bool(true)] : [:]
        )
        let dependencies = [
            materialPath,
            "shaders/effects/opacity.frag",
            "shaders/effects/opacity.vert",
        ]
        return SceneEffectDefinition(
            relativePath: definitionPath,
            version: mutation == "version" ? 2 : 1,
            replacementKey: mutation == "replacement" ? "other" : "opacity",
            name: mutation == "name" ? "Other" : "ui_editor_effect_opacity_title",
            description: mutation == "description"
                ? "Other"
                : "ui_editor_effect_opacity_description",
            group: mutation == "group" ? "other" : "colorize",
            performance: mutation == "performance" ? "high" : nil,
            previewPath: mutation == "preview" ? "other/project.json" : "preview/project.json",
            editable: mutation == "editable" ? true : nil,
            passes: [pass],
            framebuffers: mutation == "framebuffer" ? [
                .init(
                    name: "rt", scale: nil, width: nil, height: nil, fit: nil,
                    format: nil, unique: nil, clear: nil, uvs: nil, conditions: nil,
                    extraFields: [:]
                )
            ] : [],
            dependencies: mutation == "dependencies" ? Array(dependencies.reversed()) : dependencies,
            functions: mutation == "functions" ? .object([:]) : nil,
            gizmos: mutation == "gizmos" ? .array([]) : nil,
            extraFields: mutation == "extra" ? ["extra": .bool(true)] : [:],
            unknownFieldPaths: mutation == "extra" ? ["extra"] : []
        )
    }

    static func descriptor(
        _ options: Options = .init(),
        priorInput: Bool = false
    ) -> SceneRenderDescriptor {
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            texturePaths: options.maskTexture
                ? ["mask.png"]
                : options.instanceTexture ? ["asset.png"] : [],
            textureSlots: options.maskTexture
                ? [nil, "mask.png"]
                : options.instanceTexture ? ["asset.png"] : [],
            userTextureInputs: options.instanceUserTexture
                ? [.init(name: "mask")]
                : [],
            combos: options.instanceCombos,
            constantShaderValues: constants(options)
        )
        let opacity = SceneRenderDescriptor.EffectDescriptor(
            id: priorInput ? "20#effect#305" : "20#effect#21",
            file: definitionPath,
            visible: options.visible,
            passes: [pass]
        )
        let dummy = SceneRenderDescriptor.EffectDescriptor(
            id: "20#effect#21",
            file: "effects/other/effect.json",
            visible: true,
            passes: []
        )
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "\(options.materialPath)#0",
            materialPath: options.materialPath,
            materialRawSHA256: options.materialRawSHA256,
            passIndex: options.materialPassIndex,
            shaderPath: options.shaderIdentity,
            texturePaths: options.materialTexture ? ["asset.png"] : [],
            textureSlots: options.materialTexture ? ["asset.png"] : [],
            userTextureInputs: options.materialUserTexture
                ? [.init(name: "mask")]
                : [],
            combos: options.materialCombos,
            constantShaderValues: options.materialConstant
                ? ["extra": value([1], kind: "number")]
                : [:],
            blending: options.blending,
            depthTest: options.depthTest,
            depthWrite: "disabled",
            cullMode: "nocull"
        )
        var materials = [material]
        if options.duplicateMaterial { materials.append(material) }
        let definitions = options.definitionMutation == "missing"
            ? []
            : [definition(options.definitionMutation)]
        return .init(
            layers: [.init(
                id: 20,
                contentKind: options.contentKind,
                effects: priorInput ? [dummy, opacity] : [opacity]
            )],
            materialPasses: materials,
            effectDefinitions: definitions
        )
    }

    static func texture(
        _ kind: Graph.TextureKind,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: 20, effect: effect, name: name)
    }

    static func graph(_ options: GraphOptions = .init()) -> Graph {
        let effectIndex = options.priorInput ? 1 : 0
        let key = Graph.EffectKey(
            layerID: 20,
            effectIndex: effectIndex,
            descriptorID: options.priorInput ? "20#effect#305" : "20#effect#21"
        )
        let previousKey = Graph.EffectKey(
            layerID: 20,
            effectIndex: 0,
            descriptorID: "20#effect#21"
        )
        let input = options.priorInput
            ? texture(.effectOutput, effect: previousKey)
            : texture(.layerSource)
        let output = texture(.effectOutput, effect: key)
        let node = Graph.Node(
            nodeIndex: options.priorInput ? 2 : 0,
            effect: key,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: options.nodeKind,
            materialPath: options.materialPath,
            materialPassID: "\(options.materialPath)#0",
            target: output,
            bindings: options.binding ? [
                .init(slot: 0, authoredName: "previous", texture: input, conditions: nil)
            ] : [],
            commandSource: options.command ? input : nil,
            commandTarget: nil,
            compose: nil,
            conditions: options.condition ? .bool(true) : nil
        )
        let effect = Graph.Effect(
            key: key,
            definitionPath: options.definitionPath,
            input: input,
            output: output,
            nodeIndices: [node.nodeIndex]
        )
        let target = Graph.RenderTarget(
            texture: texture(.framebuffer, effect: key, name: "extra"),
            extent: .init(kind: .input, first: nil, second: nil),
            format: "rgba_backbuffer",
            declaredUnique: false,
            clear: nil,
            uvs: nil,
            conditions: nil
        )
        let blocker: [Graph.Blocker] = options.blocker ? [
            .init(effect: key, definitionPassIndex: 0, reason: .unsupportedCondition, detail: "bad")
        ] : []
        return .init(
            layerID: 20,
            effects: options.extraEffect ? [effect, effect] : [effect],
            renderTargets: options.extraTarget ? [target] : [],
            nodes: options.extraNode ? [node, node] : [node],
            finalOutput: options.outputMismatch ? input : output,
            blockers: blocker
        )
    }

    static func mutate(
        _ contracts: [SceneShaderContract],
        _ mode: String
    ) -> [SceneShaderContract] {
        guard mode != "none", let contract = contracts.first else { return contracts }
        var stages = contract.stages
        if mode == "source" || mode == "raw" {
            let stage = stages[0]
            stages[0] = .init(
                kind: stage.kind,
                relativePath: stage.relativePath,
                source: mode == "source" ? stage.source + "x" : stage.source,
                rawSHA256: mode == "raw" ? String(repeating: "0", count: 64) : stage.rawSHA256,
                includes: stage.includes,
                annotations: stage.annotations,
                declarations: stage.declarations
            )
        }
        if mode == "metadata" {
            let stage = stages[1]
            stages[1] = .init(
                kind: stage.kind,
                relativePath: stage.relativePath,
                source: stage.source,
                rawSHA256: stage.rawSHA256,
                includes: stage.includes,
                annotations: [],
                declarations: stage.declarations
            )
        }
        let changed = SceneShaderContract(
            identity: contract.identity,
            sourceKind: mode == "builtin" ? .hostBuiltin : contract.sourceKind,
            stages: stages,
            diagnostics: contract.diagnostics,
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
        SceneAuthoredOpacityPlanner.plan(
            graph: graph(graphOptions),
            descriptor: descriptor(descriptorOptions, priorInput: graphOptions.priorInput),
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
        let staticPlan = SceneAuthoredOpacityPlanner.plan(
            graph: graph(), descriptor: descriptor(), shaderContracts: contracts
        )!
        var boundOptions = Options()
        boundOptions.alphaKind = "binding"
        boundOptions.userBinding = "newproperty50"
        let boundPlan = SceneAuthoredOpacityPlanner.plan(
            graph: graph(), descriptor: descriptor(boundOptions), shaderContracts: contracts
        )!
        let target = boundPlan.liveAlphaTarget!
        let targetDefinition = SceneDynamicTargetDefinition(
            target: target,
            valueType: .scalar,
            authoredValue: .scalar(0.4)
        )
        let liveSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 1,
            definitions: [targetDefinition],
            userValues: [target: .scalar(0.75)]
        ).snapshot
        let invalidSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 2,
            generation: 2,
            definitions: [targetDefinition],
            userValues: [target: .scalar(1.5)]
        ).snapshot
        var sceneScriptOptions = Options()
        sceneScriptOptions.alphaKind = "binding"
        sceneScriptOptions.scriptSource =
            "'use strict'; export function update(value){if(shared.panel){value=0;}else{value=1;}return value;}"
        sceneScriptOptions.bindingKeys = ["script", "value"]
        let sceneScriptPlan = SceneAuthoredOpacityPlanner.plan(
            graph: graph(),
            descriptor: descriptor(sceneScriptOptions),
            shaderContracts: contracts
        )!
        let sceneScriptTarget = sceneScriptPlan.liveAlphaTarget!
        let sceneScriptDefinition = SceneDynamicTargetDefinition(
            target: sceneScriptTarget,
            valueType: .scalar,
            authoredValue: .scalar(0.4)
        )
        let authoredOnlySnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 3,
            generation: 3,
            definitions: [sceneScriptDefinition]
        ).snapshot
        let sceneScriptSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 4,
            generation: 4,
            definitions: [sceneScriptDefinition],
            sceneScriptValues: [sceneScriptTarget: .scalar(0)]
        ).snapshot

        var prior = GraphOptions(); prior.priorInput = true
        var blocker = GraphOptions(); blocker.blocker = true
        var targetGraph = GraphOptions(); targetGraph.extraTarget = true
        var binding = GraphOptions(); binding.binding = true
        var command = GraphOptions(); command.command = true
        var condition = GraphOptions(); condition.condition = true
        var copy = GraphOptions(); copy.nodeKind = .copy
        var output = GraphOptions(); output.outputMismatch = true
        var effectCount = GraphOptions(); effectCount.extraEffect = true
        var nodeCount = GraphOptions(); nodeCount.extraNode = true
        var workshop = GraphOptions()
        workshop.definitionPath = "effects/workshop/123/opacity/effect.json"
        var graphMaterial = GraphOptions(); graphMaterial.materialPath = "materials/other.json"

        var alphaZero = Options(); alphaZero.alpha = 0
        var alphaOne = Options(); alphaOne.alpha = 1
        var script = Options(); script.alphaKind = "binding"
        var wrongBindingKind = Options(); wrongBindingKind.userBinding = "newproperty50"
        var emptyBinding = Options(); emptyBinding.alphaKind = "binding"; emptyBinding.userBinding = "  "
        var missingAlpha = Options(); missingAlpha.includesAlpha = false
        var extraConstant = Options(); extraConstant.extraInstanceConstant = true
        var lowAlpha = Options(); lowAlpha.alpha = -0.01
        var highAlpha = Options(); highAlpha.alpha = 1.01
        var nonFiniteAlpha = Options(); nonFiniteAlpha.alpha = .infinity
        var instanceMask = Options(); instanceMask.instanceCombos = ["MASK": 0]
        var materialMask = Options(); materialMask.materialCombos = ["MASK": 0]
        var maskOne = Options(); maskOne.instanceCombos = ["MASK": 1]
        var unknownCombo = Options(); unknownCombo.materialCombos = ["OTHER": 0]
        var instanceTexture = Options(); instanceTexture.instanceTexture = true
        var maskTexture = Options(); maskTexture.maskTexture = true
        var instanceUserTexture = Options(); instanceUserTexture.instanceUserTexture = true
        var materialTexture = Options(); materialTexture.materialTexture = true
        var materialUserTexture = Options(); materialUserTexture.materialUserTexture = true
        var materialConstant = Options(); materialConstant.materialConstant = true
        var state = Options(); state.blending = "additive"
        var depth = Options(); depth.depthTest = "enabled"
        var materialPath = Options(); materialPath.materialPath = "materials/other.json"
        var materialHash = Options(); materialHash.materialRawSHA256 = String(repeating: "0", count: 64)
        var materialPass = Options(); materialPass.materialPassIndex = 1
        var shader = Options(); shader.shaderIdentity = "effects/other"
        var hidden = Options(); hidden.visible = false
        var content = Options(); content.contentKind = "particle"
        var duplicateMaterial = Options(); duplicateMaterial.duplicateMaterial = true

        let definitionMutations = [
            "missing", "version", "replacement", "name", "description", "group",
            "performance", "preview", "editable", "passMaterial", "passTarget",
            "passBinding", "compose", "passExtra", "framebuffer", "dependencies",
            "functions", "gizmos", "extra",
        ]
        let definitionRejected = definitionMutations.allSatisfy { mutation in
            var options = Options(); options.definitionMutation = mutation
            return !accepted(descriptorOptions: options, contracts: contracts)
        }
        let contractRejected = ["source", "raw", "metadata", "builtin", "canonical", "duplicate"]
            .allSatisfy { !accepted(contracts: mutate(contracts, $0)) }
        let direct = boundPlan.directAlphaBinding!
        let result: [String: Any] = [
            "canonicalContract": contracts.first?.canonicalSHA256
                == "89d4ee2fed510c7a81a1d1e8d0d0a353798b607fbe3d637c836fb47efb0c1cd2",
            "staticAccepted": staticPlan.staticOrFallbackAlpha == 0.4
                && staticPlan.directAlphaBinding == nil
                && staticPlan.requiredSceneScriptAlphaTarget == nil,
            "endpointsAccepted": accepted(descriptorOptions: alphaZero, contracts: contracts)
                && accepted(descriptorOptions: alphaOne, contracts: contracts),
            "directBindingAccepted": direct.propertyKey == "newproperty50"
                && direct.layerID == 20 && direct.effectIndex == 0
                && direct.passIndex == 0 && direct.constantName == "alpha",
            "snapshotApplied": boundPlan.resolvedAlpha(in: liveSnapshot) == 0.75,
            "snapshotFallback": boundPlan.resolvedAlpha(in: invalidSnapshot) == 0.4,
            "sceneScriptAccepted": sceneScriptPlan.requiredSceneScriptAlphaTarget
                == sceneScriptTarget,
            "sceneScriptRequiresProducer": sceneScriptPlan.resolvedAlpha(
                in: authoredOnlySnapshot
            ) == nil,
            "sceneScriptApplied": sceneScriptPlan.resolvedAlpha(
                in: sceneScriptSnapshot
            ) == 0,
            "candidateDetected": SceneAuthoredOpacityPlanner.containsCandidate(graph: graph()),
            "priorInputAccepted": accepted(
                graphOptions: prior, contracts: contracts, role: .priorEffectOutput
            ),
            "roleMismatchRejected": !accepted(graphOptions: prior, contracts: contracts),
            "workshopVariantRejected": !accepted(graphOptions: workshop, contracts: contracts),
            "graphShapeRejected": [blocker, targetGraph, binding, command, condition, copy,
                                   output, effectCount, nodeCount, graphMaterial]
                .allSatisfy { !accepted(graphOptions: $0, contracts: contracts) },
            "definitionRejected": definitionRejected,
            "sceneScriptRejected": !accepted(descriptorOptions: script, contracts: contracts),
            "wrongBindingKindRejected": !accepted(
                descriptorOptions: wrongBindingKind, contracts: contracts
            ),
            "emptyBindingRejected": !accepted(descriptorOptions: emptyBinding, contracts: contracts),
            "alphaShapeRejected": [missingAlpha, extraConstant, lowAlpha, highAlpha, nonFiniteAlpha]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "maskDefaultsAccepted": accepted(descriptorOptions: instanceMask, contracts: contracts)
                && accepted(descriptorOptions: materialMask, contracts: contracts),
            // 官方 opacity.frag 的 MASK 分支读 g_Texture1，槽位 1 绑图就是绑了遮罩。
            // plan 必须把这个路径记下来交给渲染层，没绑图时必须是 nil。
            "maskTexturePathRecorded": SceneAuthoredOpacityPlanner.plan(
                graph: graph(),
                descriptor: descriptor(maskTexture),
                shaderContracts: contracts
            )?.maskTexturePath == "mask.png"
                && staticPlan.maskTexturePath == nil,
            "comboRejected": !accepted(descriptorOptions: maskOne, contracts: contracts)
                && !accepted(descriptorOptions: unknownCombo, contracts: contracts),
            "textureRejected": [instanceTexture, instanceUserTexture, materialTexture,
                                materialUserTexture]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "materialRejected": [materialConstant, state, depth, materialPath, materialHash,
                                 materialPass, shader, duplicateMaterial]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "layerRejected": !accepted(descriptorOptions: hidden, contracts: contracts)
                && !accepted(descriptorOptions: content, contracts: contracts),
            "contractRejected": contractRejected,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
'''


class SceneOpacityPlannerTests(unittest.TestCase):
    def test_stock_profile_is_exact_and_fail_closed(self) -> None:
        swiftc = shutil.which("swiftc")
        if not swiftc:
            self.skipTest("swiftc is unavailable")

        with tempfile.TemporaryDirectory(prefix="scene-opacity-") as directory:
            root = Path(directory)
            shader_root = root / "shaders/effects"
            shader_root.mkdir(parents=True)
            (shader_root / "opacity.vert").write_bytes(base64.b64decode(VERTEX_BASE64))
            (shader_root / "opacity.frag").write_bytes(base64.b64decode(FRAGMENT_BASE64))
            harness = root / "Harness.swift"
            executable = root / "opacity-harness"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    swiftc,
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-o",
                    str(executable),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(executable), str(root)],
                check=True,
                capture_output=True,
                text=True,
            )

        output = json.loads(completed.stdout)
        self.assertTrue(output)
        self.assertTrue(all(output.values()), output)


if __name__ == "__main__":
    unittest.main()
