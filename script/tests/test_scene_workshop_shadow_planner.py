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
    SOURCE_ROOT / "RenderGraph/SceneAuthoredWorkshopShadowPlanner.swift",
]

VERTEX_BASE64 = "I2luY2x1ZGUgImNvbW1vbi5oIg0KI2luY2x1ZGUgImNvbW1vbl9wZXJzcGVjdGl2ZS5oIg0KDQp1bmlmb3JtIG1hdDQgZ19Nb2RlbFZpZXdQcm9qZWN0aW9uTWF0cml4Ow0KdW5pZm9ybSB2ZWM0IGdfVGV4dHVyZTFSZXNvbHV0aW9uOw0KDQphdHRyaWJ1dGUgdmVjMyBhX1Bvc2l0aW9uOw0KYXR0cmlidXRlIHZlYzIgYV9UZXhDb29yZDsNCg0KdmFyeWluZyB2ZWM0IHZfVGV4Q29vcmQ7DQp2YXJ5aW5nIHZlYzIgdl9SZWZsZWN0ZWRDb29yZDsNCg0KdW5pZm9ybSB2ZWMzIHVfU2hhZG93T2Zmc2V0OyAvLyB7ImRlZmF1bHQiOiIyIC0yIDAiLCJkZXNjcmlwdGlvbiI6IngveTrlgY/np7vph48gejrml4vovazop5LluqYo5byn5bqmKSIsImxhYmVsIjoic2hhZG93T2Zmc2V0L+mYtOW9seWBj+enuyIsIm1hdGVyaWFsIjoic2hhZG93T2Zmc2V0In0NCg0Kdm9pZCBtYWluKCkgew0KICAgIGdsX1Bvc2l0aW9uID0gbXVsKHZlYzQoYV9Qb3NpdGlvbiwgMS4wKSwgZ19Nb2RlbFZpZXdQcm9qZWN0aW9uTWF0cml4KTsNCiAgICB2X1RleENvb3JkID0gYV9UZXhDb29yZC54eXh5Ow0KDQogICAgI2lmIE1BU0sNCiAgICAgICAgdl9UZXhDb29yZC56ICo9IGdfVGV4dHVyZTFSZXNvbHV0aW9uLnogLyBnX1RleHR1cmUxUmVzb2x1dGlvbi54Ow0KICAgICAgICB2X1RleENvb3JkLncgKj0gZ19UZXh0dXJlMVJlc29sdXRpb24udyAvIGdfVGV4dHVyZTFSZXNvbHV0aW9uLnk7DQogICAgI2VuZGlmDQoNCiAgICB2ZWMyIGNlbnRlciA9IHZlYzIoMC41LCAwLjUpOw0KICAgIHZlYzIgZGVsdGEgPSBhX1RleENvb3JkIC0gY2VudGVyOw0KICAgIA0KICAgIGZsb2F0IHNpblJvdCA9IHNpbih1X1NoYWRvd09mZnNldC56KTsNCiAgICBmbG9hdCBjb3NSb3QgPSBjb3ModV9TaGFkb3dPZmZzZXQueik7DQogICAgZGVsdGEgPSB2ZWMyKA0KICAgICAgICBkZWx0YS54ICogY29zUm90IC0gZGVsdGEueSAqIHNpblJvdCwNCiAgICAgICAgZGVsdGEueCAqIHNpblJvdCArIGRlbHRhLnkgKiBjb3NSb3QNCiAgICApOw0KICAgIA0KICAgIGRlbHRhICs9IHVfU2hhZG93T2Zmc2V0Lnh5IC8gMTAwLjA7DQogICAgdl9SZWZsZWN0ZWRDb29yZCA9IGNlbnRlciArIGRlbHRhOw0KfQ=="
FRAGMENT_BASE64 = "Ly8gW0NPTUJPXSB7Im1hdGVyaWFsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfYmxlbmRfbW9kZSIsImNvbWJvIjoiQkxFTkRNT0RFIiwidHlwZSI6ImltYWdlYmxlbmRpbmciLCJkZWZhdWx0IjowfQ0KLy8gW0NPTUJPXSB7Im1hdGVyaWFsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfbWFzayIsImNvbWJvIjoiTUFTSyIsInR5cGUiOiJvcHRpb25zIiwiZGVmYXVsdCI6MH0NCg0KI2luY2x1ZGUgImNvbW1vbi5oIg0KI2luY2x1ZGUgImNvbW1vbl9ibGVuZGluZy5oIg0KDQp1bmlmb3JtIHZlYzMgdV9Db2xvcjsgLy8geyJkZWZhdWx0IjoiMCAwIDAiLCJsYWJlbCI6IkNvbG9yIiwibWF0ZXJpYWwiOiJzaGFkb3dDb2xvciIsInR5cGUiOiJjb2xvciJ9DQp1bmlmb3JtIGZsb2F0IHVfc2hhZG93RHJhd0JvcmRlcjsgLy8geyJtYXRlcmlhbCI6InNoYWRvd0RyYXdCb3JkZXIiLCJsYWJlbCI6InNoYWRvd0RyYXdCb3JkZXIv6Zi05b2x6L656LedIiwiZGVmYXVsdCI6MC41LCJyYW5nZSI6WzAsMV19DQoNCnZhcnlpbmcgdmVjNCB2X1RleENvb3JkOw0KdmFyeWluZyB2ZWMyIHZfUmVmbGVjdGVkQ29vcmQ7DQoNCnVuaWZvcm0gc2FtcGxlcjJEIGdfVGV4dHVyZTA7IC8vIHsiaGlkZGVuIjp0cnVlfQ0KdW5pZm9ybSBzYW1wbGVyMkQgZ19UZXh0dXJlMTsgLy8geyJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX21hc2siLCJtb2RlIjoib3BhY2l0eW1hc2siLCJjb21ibyI6Ik1BU0siLCJwYWludGRlZmF1bHRjb2xvciI6IjAgMCAwIDEifQ0KDQp1bmlmb3JtIGZsb2F0IGdfUmVmbGVjdGlvbkFscGhhOyAvLyB7Im1hdGVyaWFsIjoiYWxwaGEiLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX2FscGhhIiwiZGVmYXVsdCI6MC41LCJyYW5nZSI6WzAuMCwgMV19DQoNCnZvaWQgbWFpbigpIHsNCiAgICB2ZWM0IGFsYmVkbyA9IHRleFNhbXBsZTJEKGdfVGV4dHVyZTAsIHZfVGV4Q29vcmQueHkpOw0KICAgIHZlYzQgcmVmbGVjdGVkID0gdGV4U2FtcGxlMkQoZ19UZXh0dXJlMCwgdl9SZWZsZWN0ZWRDb29yZCk7DQoNCiAgICAjaWYgTUFTSw0KICAgICAgICBmbG9hdCBtYXNrID0gdGV4U2FtcGxlMkQoZ19UZXh0dXJlMSwgdl9UZXhDb29yZC56dykucjsNCiAgICAjZWxzZQ0KICAgICAgICBmbG9hdCBtYXNrID0gMS4wOw0KICAgICNlbmRpZg0KDQogICAgaWYgKGFsYmVkby5hID4gdV9zaGFkb3dEcmF3Qm9yZGVyKSB7DQogICAgICAgIGdsX0ZyYWdDb2xvciA9IGFsYmVkbzsNCiAgICB9IGVsc2UgaWYgKHJlZmxlY3RlZC5hID4gMC4wKSB7DQogICAgICAgIGdsX0ZyYWdDb2xvci5yZ2IgPSBBcHBseUJsZW5kaW5nKEJMRU5ETU9ERSwgYWxiZWRvLnJnYiwgdV9Db2xvci5yZ2IsIGdfUmVmbGVjdGlvbkFscGhhICogbWFzayk7DQogICAgICAgIGdsX0ZyYWdDb2xvci5hID0gbWluKDEuMCwgYWxiZWRvLmEgKyByZWZsZWN0ZWQuYSAqIGdfUmVmbGVjdGlvbkFscGhhICogbWFzayk7DQogICAgfSBlbHNlIHsNCiAgICAgICAgZ2xfRnJhZ0NvbG9yID0gYWxiZWRvOw0KICAgIH0NCn0="


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
    static let definitionPath = "effects/workshop/3488490208/shadow_____________/effect.json"
    static let materialPath = "materials/workshop/3488490208/effects/shadow_____________.json"
    static let shaderIdentity = "workshop/3488490208/effects/shadow_____________"

    struct Options {
        var contentKind = "text"
        var alpha = 0.5
        var color = [0.0, 0.0, 0.0]
        var border = 0.5
        var offset = [2.0, -2.0, 0.0]
        var valueKindMutation: String?
        var bindingMutation: String?
        var missingConstant: String?
        var instanceCombos: [String: Int] = [:]
        var instanceTexture = false
        var materialCombos: [String: Int] = [:]
        var materialTexture = false
        var materialConstant = false
        var blending = "normal"
        var definitionMutation = "none"
        var visible: Bool? = true
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
    }

    static func value(
        _ components: [Double],
        kind: String,
        binding: String? = nil
    ) -> SceneDocument.ShaderValue {
        .init(
            rawValue: components.map { String($0) }.joined(separator: " "),
            valueKind: kind,
            userBinding: binding,
            components: components
        )
    }

    static func constants(_ options: Options) -> [String: SceneDocument.ShaderValue] {
        var values = [
            "alpha": value([options.alpha], kind: "number"),
            "shadowColor": value(options.color, kind: "vector"),
            "shadowDrawBorder": value([options.border], kind: "number"),
            "shadowOffset": value(options.offset, kind: "vector"),
        ]
        if let key = options.missingConstant { values.removeValue(forKey: key) }
        if let key = options.valueKindMutation, let current = values[key] {
            values[key] = value(current.components ?? [], kind: "binding")
        }
        if let key = options.bindingMutation, let current = values[key] {
            values[key] = value(current.components ?? [], kind: current.valueKind, binding: "property")
        }
        return values
    }

    static func definition(_ mutation: String) -> SceneEffectDefinition {
        let pass = SceneEffectDefinition.Pass(
            passIndex: 0,
            materialPath: materialPath,
            target: mutation == "passTarget" ? "other" : nil,
            bindings: [],
            compose: nil,
            command: nil,
            source: nil,
            conditions: nil,
            extraFields: mutation == "passExtra" ? ["extra": .bool(true)] : [:]
        )
        return SceneEffectDefinition(
            relativePath: definitionPath,
            version: mutation == "version" ? 2 : 1,
            replacementKey: "shadow_____________",
            name: mutation == "name" ? "Other" : "Shadow/\u{6dfb}\u{52a0}\u{9634}\u{5f71}",
            description: nil,
            group: "localeffects",
            performance: nil,
            previewPath: nil,
            editable: false,
            passes: [pass],
            framebuffers: mutation == "framebuffer" ? [
                .init(name: "rt", scale: nil, width: nil, height: nil, fit: nil,
                      format: nil, unique: nil, clear: nil, uvs: nil, conditions: nil,
                      extraFields: [:])
            ] : [],
            dependencies: mutation == "dependencies" ? [] : [
                materialPath,
                "shaders/workshop/3488490208/effects/shadow_____________.frag",
                "shaders/workshop/3488490208/effects/shadow_____________.vert",
            ],
            functions: mutation == "functions" ? .object([:]) : nil,
            gizmos: nil,
            extraFields: mutation == "extra" ? ["extra": .bool(true)] : [:],
            unknownFieldPaths: mutation == "extra" ? ["extra"] : []
        )
    }

    static func descriptor(_ options: Options = .init(), priorInput: Bool = false) -> SceneRenderDescriptor {
        let shadowPass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            texturePaths: options.instanceTexture ? ["asset.png"] : [],
            textureSlots: options.instanceTexture ? ["asset.png"] : [],
            userTextureInputs: [],
            combos: options.instanceCombos,
            constantShaderValues: constants(options)
        )
        let shadow = SceneRenderDescriptor.EffectDescriptor(
            id: priorInput ? "20#effect#305" : "20#effect#21",
            file: definitionPath,
            visible: options.visible,
            passes: [shadowPass]
        )
        let dummy = SceneRenderDescriptor.EffectDescriptor(
            id: "20#effect#21", file: "effects/other/effect.json", visible: true, passes: []
        )
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "\(materialPath)#0",
            materialPath: materialPath,
            passIndex: 0,
            shaderPath: shaderIdentity,
            texturePaths: options.materialTexture ? ["asset.png"] : [],
            textureSlots: options.materialTexture ? ["asset.png"] : [],
            userTextureInputs: [],
            combos: options.materialCombos,
            constantShaderValues: options.materialConstant
                ? ["extra": value([1], kind: "number")]
                : [:],
            blending: options.blending,
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull"
        )
        let definitions = options.definitionMutation == "missing"
            ? []
            : [definition(options.definitionMutation)]
        return .init(
            layers: [.init(
                id: 20,
                contentKind: options.contentKind,
                effects: priorInput ? [dummy, shadow] : [shadow]
            )],
            materialPasses: [material],
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
        let previousKey = Graph.EffectKey(layerID: 20, effectIndex: 0, descriptorID: "20#effect#21")
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
            materialPath: materialPath,
            materialPassID: "\(materialPath)#0",
            target: output,
            bindings: options.binding
                ? [.init(slot: 0, authoredName: "previous", texture: input, conditions: nil)]
                : [],
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
        let blockers: [Graph.Blocker] = options.blocker ? [
            .init(effect: key, definitionPassIndex: 0, reason: .unsupportedCondition, detail: "bad")
        ] : []
        return .init(
            layerID: 20,
            effects: [effect],
            renderTargets: options.extraTarget ? [target] : [],
            nodes: [node],
            finalOutput: options.outputMismatch ? input : output,
            blockers: blockers
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
                relativePath: stage.relativePath,
                source: mode == "source" ? stage.source + "x" : stage.source,
                rawSHA256: mode == "raw" ? String(repeating: "0", count: 64) : stage.rawSHA256,
                includes: mode == "metadata" ? [] : stage.includes,
                annotations: stage.annotations,
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
        SceneAuthoredWorkshopShadowPlanner.plan(
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
        let plan = SceneAuthoredWorkshopShadowPlanner.plan(
            graph: graph(), descriptor: descriptor(), shaderContracts: contracts
        )
        var prior = GraphOptions(); prior.priorInput = true
        var blocker = GraphOptions(); blocker.blocker = true
        var target = GraphOptions(); target.extraTarget = true
        var binding = GraphOptions(); binding.binding = true
        var command = GraphOptions(); command.command = true
        var condition = GraphOptions(); condition.condition = true
        var wrongDefinition = GraphOptions(); wrongDefinition.definitionPath = "effects/other/effect.json"
        var wrongOutput = GraphOptions(); wrongOutput.outputMismatch = true
        var copy = GraphOptions(); copy.nodeKind = .copy
        var wrongContent = Options(); wrongContent.contentKind = "particle"
        var hidden = Options(); hidden.visible = false
        var materialMask = Options(); materialMask.materialCombos = ["MASK": 1]
        var materialExtraCombo = Options(); materialExtraCombo.materialCombos = ["OTHER": 0]
        var instanceBlend = Options(); instanceBlend.instanceCombos = ["BLENDMODE": 1]
        var materialTexture = Options(); materialTexture.materialTexture = true
        var instanceTexture = Options(); instanceTexture.instanceTexture = true
        var materialConstant = Options(); materialConstant.materialConstant = true
        var wrongState = Options(); wrongState.blending = "additive"
        var missing = Options(); missing.missingConstant = "alpha"
        var bound = Options(); bound.bindingMutation = "shadowOffset"
        var wrongKind = Options(); wrongKind.valueKindMutation = "alpha"
        var alphaLow = Options(); alphaLow.alpha = -0.01
        var alphaHigh = Options(); alphaHigh.alpha = 1.01
        var color = Options(); color.color = [0, 0, 0.01]
        var border = Options(); border.border = 1.01
        var offset = Options(); offset.offset = [Double.infinity, 0, 0]
        var overflowingOffset = Options(); overflowingOffset.offset = [Double.greatestFiniteMagnitude, 0, 0]
        var rotation = Options(); rotation.offset = [2, -2, 0.01]

        let definitionMutations = [
            "missing", "version", "name", "passTarget", "passExtra",
            "framebuffer", "dependencies", "functions", "extra",
        ]
        let definitionRejected = definitionMutations.allSatisfy { mutation in
            var options = Options(); options.definitionMutation = mutation
            return !accepted(descriptorOptions: options, contracts: contracts)
        }
        let contractRejected = ["source", "raw", "metadata", "builtin", "canonical", "duplicate"]
            .allSatisfy { !accepted(contracts: mutate(contracts, $0)) }

        let output: [String: Any] = [
            "canonicalContract": contracts.first?.canonicalSHA256
                == "4537fd70eb7502278f0a7b32cfae84b035ebd44f3198522ea15195638add3df1",
            "validStatic": plan?.alpha == 0.5 && plan?.color == SIMD3(0, 0, 0)
                && plan?.drawBorder == 0.5 && plan?.offset == SIMD2(2, -2),
            "candidateDetected": SceneAuthoredWorkshopShadowPlanner.containsCandidate(graph: graph()),
            "priorInputAccepted": accepted(
                graphOptions: prior, contracts: contracts, role: .priorEffectOutput
            ),
            "roleMismatchRejected": !accepted(graphOptions: prior, contracts: contracts),
            "blockerRejected": !accepted(graphOptions: blocker, contracts: contracts),
            "targetRejected": !accepted(graphOptions: target, contracts: contracts),
            "bindingRejected": !accepted(graphOptions: binding, contracts: contracts),
            "commandRejected": !accepted(graphOptions: command, contracts: contracts),
            "conditionRejected": !accepted(graphOptions: condition, contracts: contracts),
            "definitionPathRejected": !accepted(graphOptions: wrongDefinition, contracts: contracts),
            "outputRejected": !accepted(graphOptions: wrongOutput, contracts: contracts),
            "commandKindRejected": !accepted(graphOptions: copy, contracts: contracts),
            "definitionShapeRejected": definitionRejected,
            "contentRejected": !accepted(descriptorOptions: wrongContent, contracts: contracts),
            "hiddenRejected": !accepted(descriptorOptions: hidden, contracts: contracts),
            "materialMaskRejected": !accepted(descriptorOptions: materialMask, contracts: contracts),
            "materialExtraComboRejected": !accepted(
                descriptorOptions: materialExtraCombo, contracts: contracts
            ),
            "instanceBlendRejected": !accepted(descriptorOptions: instanceBlend, contracts: contracts),
            "materialTextureRejected": !accepted(descriptorOptions: materialTexture, contracts: contracts),
            "instanceTextureRejected": !accepted(descriptorOptions: instanceTexture, contracts: contracts),
            "materialConstantRejected": !accepted(descriptorOptions: materialConstant, contracts: contracts),
            "stateRejected": !accepted(descriptorOptions: wrongState, contracts: contracts),
            "missingConstantRejected": !accepted(descriptorOptions: missing, contracts: contracts),
            "bindingConstantRejected": !accepted(descriptorOptions: bound, contracts: contracts),
            "constantKindRejected": !accepted(descriptorOptions: wrongKind, contracts: contracts),
            "alphaLowRejected": !accepted(descriptorOptions: alphaLow, contracts: contracts),
            "alphaHighRejected": !accepted(descriptorOptions: alphaHigh, contracts: contracts),
            "colorRejected": !accepted(descriptorOptions: color, contracts: contracts),
            "borderRejected": !accepted(descriptorOptions: border, contracts: contracts),
            "offsetRejected": !accepted(descriptorOptions: offset, contracts: contracts),
            "overflowingOffsetRejected": !accepted(
                descriptorOptions: overflowingOffset, contracts: contracts
            ),
            "rotationRejected": !accepted(descriptorOptions: rotation, contracts: contracts),
            "contractRejected": contractRejected,
        ]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
'''


class SceneWorkshopShadowPlannerTests(unittest.TestCase):
    def test_exact_workshop_profile_is_fail_closed(self) -> None:
        swiftc = shutil.which("swiftc")
        if not swiftc:
            self.skipTest("swiftc is unavailable")

        with tempfile.TemporaryDirectory(prefix="scene-workshop-shadow-") as directory:
            root = Path(directory)
            shader_root = root / "shaders/workshop/3488490208/effects"
            shader_root.mkdir(parents=True)
            (shader_root / "shadow_____________.vert").write_bytes(
                base64.b64decode(VERTEX_BASE64)
            )
            (shader_root / "shadow_____________.frag").write_bytes(
                base64.b64decode(FRAGMENT_BASE64)
            )
            harness = root / "Harness.swift"
            executable = root / "workshop-shadow-harness"
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
