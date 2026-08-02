#!/usr/bin/env python3
"""tint planner 的 fail-closed 准入测试。

与 opacity 的差别有两处刻意的偏离，这里各有一条专门断言：
- `色值` 是 vec3 用户绑定，走 `.vector3` 动态目标；
- 槽位 1 的遮罩只调整 Tint 混合权重，不改输出 alpha。

shader 源按 SceneTintShaderProfile 精确指纹白名单准入：stock 2.8.42、legacy 注解
变体（frag `98f97e9e9ed0…`，vert 与 stock 相同，样本 1937925563 / 2131872317）各自
resolve；legacy 的 `#if MASK` 分支是 mask 覆盖而非相乘，`MASK == 1` 与遮罩贴图在
两指纹下都整条拒绝。
"""

from __future__ import annotations

import base64
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContractLoader.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Effects/SceneBlendModeShaderSource.swift",
    SOURCE_ROOT / "RenderGraph/SceneTintShaderProfile.swift",
    SOURCE_ROOT / "RenderGraph/SceneTintAssetProfile.swift",
    SOURCE_ROOT / "RenderGraph/SceneTintExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredTintPlanner.swift",
]

VERTEX_BASE64 = (
    "DQp1bmlmb3JtIG1hdDQgZ19Nb2RlbFZpZXdQcm9qZWN0aW9uTWF0cml4Ow0K"
    "DQojaWYgTUFTSw0KdW5pZm9ybSB2ZWM0IGdfVGV4dHVyZTFSZXNvbHV0aW9u"
    "Ow0KI2VuZGlmDQoNCmF0dHJpYnV0ZSB2ZWMzIGFfUG9zaXRpb247DQphdHRy"
    "aWJ1dGUgdmVjMiBhX1RleENvb3JkOw0KDQp2YXJ5aW5nIHZlYzQgdl9UZXhD"
    "b29yZDsNCg0Kdm9pZCBtYWluKCkgew0KCWdsX1Bvc2l0aW9uID0gbXVsKHZl"
    "YzQoYV9Qb3NpdGlvbiwgMS4wKSwgZ19Nb2RlbFZpZXdQcm9qZWN0aW9uTWF0"
    "cml4KTsNCgl2X1RleENvb3JkID0gYV9UZXhDb29yZC54eXh5Ow0KCQ0KI2lm"
    "IE1BU0sNCgl2X1RleENvb3JkLnp3ID0gdmVjMih2X1RleENvb3JkLnggKiBn"
    "X1RleHR1cmUxUmVzb2x1dGlvbi56IC8gZ19UZXh0dXJlMVJlc29sdXRpb24u"
    "eCwNCgkJCQkJCXZfVGV4Q29vcmQueSAqIGdfVGV4dHVyZTFSZXNvbHV0aW9u"
    "LncgLyBnX1RleHR1cmUxUmVzb2x1dGlvbi55KTsNCiNlbmRpZg0KfQ0K"
)
FRAGMENT_BASE64 = (
    "DQovLyBbQ09NQk9dIHsibWF0ZXJpYWwiOiJ1aV9lZGl0b3JfcHJvcGVydGll"
    "c19ibGVuZF9tb2RlIiwiY29tYm8iOiJCTEVORE1PREUiLCJ0eXBlIjoiaW1h"
    "Z2VibGVuZGluZyIsImRlZmF1bHQiOjMwfQ0KDQojaW5jbHVkZSAiY29tbW9u"
    "X2JsZW5kaW5nLmgiDQoNCnZhcnlpbmcgdmVjNCB2X1RleENvb3JkOw0KDQp1"
    "bmlmb3JtIHNhbXBsZXIyRCBnX1RleHR1cmUwOyAvLyB7ImhpZGRlbiI6dHJ1"
    "ZX0NCnVuaWZvcm0gc2FtcGxlcjJEIGdfVGV4dHVyZTE7IC8vIHsibGFiZWwi"
    "OiJ1aV9lZGl0b3JfcHJvcGVydGllc19vcGFjaXR5X21hc2siLCJtb2RlIjoi"
    "b3BhY2l0eW1hc2siLCJjb21ibyI6Ik1BU0siLCJwYWludGRlZmF1bHRjb2xv"
    "ciI6IjAgMCAwIDEifQ0KDQp1bmlmb3JtIGZsb2F0IGdfQmxlbmRBbHBoYTsg"
    "Ly8geyJtYXRlcmlhbCI6ImFscGhhIiwgImxhYmVsIjoidWlfZWRpdG9yX3By"
    "b3BlcnRpZXNfYWxwaGEiLCJkZWZhdWx0IjoxLCJyYW5nZSI6WzAsMV19DQp1"
    "bmlmb3JtIHZlYzMgZ19UaW50Q29sb3I7IC8vIHsibWF0ZXJpYWwiOiJjb2xv"
    "ciIsICJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX2NvbG9yIiwgInR5"
    "cGUiOiAiY29sb3IiLCAiZGVmYXVsdCI6IjEgMCAwIn0NCg0Kdm9pZCBtYWlu"
    "KCkgew0KCXZlYzQgYWxiZWRvID0gdGV4U2FtcGxlMkQoZ19UZXh0dXJlMCwg"
    "dl9UZXhDb29yZC54eSk7DQoJZmxvYXQgbWFzayA9IGdfQmxlbmRBbHBoYTsN"
    "CgkNCiNpZiBNQVNLDQoJbWFzayAqPSB0ZXhTYW1wbGUyRChnX1RleHR1cmUx"
    "LCB2X1RleENvb3JkLnp3KS5yOw0KI2VuZGlmDQoJDQoJYWxiZWRvLnJnYiA9"
    "IEFwcGx5QmxlbmRpbmcoQkxFTkRNT0RFLCBhbGJlZG8ucmdiLCBnX1RpbnRD"
    "b2xvciwgbWFzayk7DQoJDQojaWYgQkxFTkRNT0RFID09IDANCglhbGJlZG8u"
    "YSA9IDEuMDsNCiNlbmRpZg0KCQ0KCWdsX0ZyYWdDb2xvciA9IGFsYmVkbzsN"
    "Cn0NCg=="
)
# 语料样本 2131872317 / 1937925563 的 scene.pkg 里 shaders/effects/tint.frag 原始
# 字节（两样本逐字节相同，SHA256 98f97e9e9ed0…）；vert 与 stock 相同，共用上面的
# VERTEX_BASE64。
LEGACY_FRAGMENT_BASE64 = (
    "DQovLyBbQ09NQk9dIHsibWF0ZXJpYWwiOiJ1aV9lZGl0b3JfcHJvcGVydGll"
    "c19ibGVuZF9tb2RlIiwiY29tYm8iOiJCTEVORE1PREUiLCJ0eXBlIjoiaW1h"
    "Z2VibGVuZGluZyIsImRlZmF1bHQiOjMwfQ0KDQojaW5jbHVkZSAiY29tbW9u"
    "X2JsZW5kaW5nLmgiDQoNCnZhcnlpbmcgdmVjNCB2X1RleENvb3JkOw0KDQp1"
    "bmlmb3JtIHNhbXBsZXIyRCBnX1RleHR1cmUwOyAvLyB7Im1hdGVyaWFsIjoi"
    "ZnJhbWVidWZmZXIiLCAibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19m"
    "cmFtZWJ1ZmZlciIsICJoaWRkZW4iOnRydWV9DQp1bmlmb3JtIHNhbXBsZXIy"
    "RCBnX1RleHR1cmUxOyAvLyB7Im1hdGVyaWFsIjoibWFzayIsICJsYWJlbCI6"
    "InVpX2VkaXRvcl9wcm9wZXJ0aWVzX29wYWNpdHlfbWFzayIsIm1vZGUiOiJv"
    "cGFjaXR5bWFzayIsImRlZmF1bHQiOiJ1dGlsL3doaXRlIiwiY29tYm8iOiJN"
    "QVNLIiwicGFpbnRkZWZhdWx0Y29sb3IiOiIwIDAgMCAxIn0NCg0KdW5pZm9y"
    "bSBmbG9hdCBnX0JsZW5kQWxwaGE7IC8vIHsibWF0ZXJpYWwiOiJhbHBoYSIs"
    "ICJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX2FscGhhIiwiZGVmYXVs"
    "dCI6MSwicmFuZ2UiOlswLDFdfQ0KdW5pZm9ybSB2ZWMzIGdfVGludENvbG9y"
    "OyAvLyB7Im1hdGVyaWFsIjoiY29sb3IiLCAibGFiZWwiOiJ1aV9lZGl0b3Jf"
    "cHJvcGVydGllc19jb2xvciIsICJ0eXBlIjogImNvbG9yIiwgImRlZmF1bHQi"
    "OiIxIDAgMCJ9DQoNCnZvaWQgbWFpbigpIHsNCgl2ZWM0IGFsYmVkbyA9IHRl"
    "eFNhbXBsZTJEKGdfVGV4dHVyZTAsIHZfVGV4Q29vcmQueHkpOw0KCWZsb2F0"
    "IG1hc2sgPSBnX0JsZW5kQWxwaGE7DQoJDQojaWYgTUFTSw0KCW1hc2sgPSB0"
    "ZXhTYW1wbGUyRChnX1RleHR1cmUxLCB2X1RleENvb3JkLnp3KS5yOw0KI2Vu"
    "ZGlmDQoJDQoJYWxiZWRvLnJnYiA9IEFwcGx5QmxlbmRpbmcoQkxFTkRNT0RF"
    "LCBhbGJlZG8ucmdiLCBnX1RpbnRDb2xvciwgbWFzayk7DQoJDQojaWYgQkxF"
    "TkRNT0RFID09IDANCglhbGJlZG8uYSA9IDEuMDsNCiNlbmRpZg0KCQ0KCWds"
    "X0ZyYWdDb2xvciA9IGFsYmVkbzsNCn0NCg=="
)


HARNESS = r'''
import Foundation
import simd

struct SceneDocument {
    struct Timeline {
        struct Options {
            let parent: Int?
            let children: [Int]
        }
        let isRelative: Bool
        let options: Options
        let componentCount: Int
        let hasExecutableWrapLoop: Bool
    }

    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
        let timeline: Timeline?
        let timelineDiagnostics: [String]
        let scriptSource: String?
        let bindingKeys: [String]
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
    static let definitionPath = "effects/tint/effect.json"
    static let materialPath = "materials/effects/tint.json"
    static let shaderIdentity = "effects/tint"

    struct Options {
        var contentKind = "image"
        var definitionPath = Harness.definitionPath
        var color: [Double] = [0.25, 0.6, 0.9]
        var colorKind = "vector"
        var colorBinding: String?
        var colorTimeline = false
        var colorBindingKeys: [String]?
        var includesColor = true
        var alpha = 0.4
        var alphaKind = "number"
        var alphaBinding: String?
        var alphaTimeline = false
        var alphaTimelineRelative = false
        var alphaTimelineParent: Int?
        var alphaTimelineComponentCount = 1
        var alphaTimelineExecutable = true
        var alphaTimelineDiagnostics: [String] = []
        var alphaScriptSource: String?
        var alphaBindingKeys: [String]?
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
        var materialUserShaderValue = false
        var alphaWriting: String?
        var blending = "normal"
        var depthTest = "disabled"
        var materialPath = Harness.materialPath
        var materialRawSHA256 =
            "d5a190abf6ebc13981b7e26ca623577d2cfe0783a343e05fc1a46dcce7cb5016"
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
        timeline: Bool = false,
        timelineRelative: Bool = false,
        timelineParent: Int? = nil,
        timelineComponentCount: Int = 1,
        timelineExecutable: Bool = true,
        timelineDiagnostics: [String] = [],
        scriptSource: String? = nil,
        bindingKeys: [String]? = nil
    ) -> SceneDocument.ShaderValue {
        .init(
            rawValue: components.map { String($0) }.joined(separator: " "),
            valueKind: kind,
            userBinding: binding,
            components: components,
            timeline: timeline ? .init(
                isRelative: timelineRelative,
                options: .init(parent: timelineParent, children: []),
                componentCount: timelineComponentCount,
                hasExecutableWrapLoop: timelineExecutable
            ) : nil,
            timelineDiagnostics: timelineDiagnostics,
            scriptSource: scriptSource,
            bindingKeys: bindingKeys ?? (binding == nil ? [] : ["user", "value"])
        )
    }

    static func constants(_ options: Options) -> [String: SceneDocument.ShaderValue] {
        var result: [String: SceneDocument.ShaderValue] = [:]
        if options.includesColor {
            result["color"] = value(
                options.color,
                kind: options.colorKind,
                binding: options.colorBinding,
                timeline: options.colorTimeline,
                bindingKeys: options.colorBindingKeys
            )
        }
        if options.includesAlpha {
            result["alpha"] = value(
                [options.alpha],
                kind: options.alphaKind,
                binding: options.alphaBinding,
                timeline: options.alphaTimeline,
                timelineRelative: options.alphaTimelineRelative,
                timelineParent: options.alphaTimelineParent,
                timelineComponentCount: options.alphaTimelineComponentCount,
                timelineExecutable: options.alphaTimelineExecutable,
                timelineDiagnostics: options.alphaTimelineDiagnostics,
                scriptSource: options.alphaScriptSource,
                bindingKeys: options.alphaBindingKeys
            )
        }
        if options.extraInstanceConstant {
            result["extra"] = value([1], kind: "number")
        }
        return result
    }

    static func definition(_ options: Options) -> SceneEffectDefinition {
        let mutation = options.definitionMutation
        let pass = SceneEffectDefinition.Pass(
            passIndex: 0,
            materialPath: mutation == "passMaterial"
                ? "materials/other.json" : options.materialPath,
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
            options.materialPath,
            "shaders/\(options.shaderIdentity).frag",
            "shaders/\(options.shaderIdentity).vert",
        ]
        return SceneEffectDefinition(
            relativePath: options.definitionPath,
            version: mutation == "version" ? 2 : 1,
            replacementKey: mutation == "replacement"
                ? "other"
                : mutation == "missingReplacement" ? nil : "tint",
            name: mutation == "name" ? "Other" : "ui_editor_effect_tint_title",
            description: mutation == "description"
                ? "Other"
                : "ui_editor_effect_tint_description",
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
            dependencies: mutation == "dependencies"
                ? Array(dependencies.reversed())
                : dependencies,
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
            userTextureInputs: options.instanceUserTexture ? [.init(name: "mask")] : [],
            combos: options.instanceCombos,
            constantShaderValues: constants(options)
        )
        let tint = SceneRenderDescriptor.EffectDescriptor(
            id: priorInput ? "20#effect#305" : "20#effect#21",
            file: options.definitionPath,
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
            userTextureInputs: options.materialUserTexture ? [.init(name: "mask")] : [],
            combos: options.materialCombos,
            constantShaderValues: options.materialConstant
                ? ["extra": value([1], kind: "number")]
                : [:],
            userShaderValues: options.materialUserShaderValue
                ? ["color": "property"] : [:],
            blending: options.blending,
            depthTest: options.depthTest,
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: options.alphaWriting
        )
        var materials = [material]
        if options.duplicateMaterial { materials.append(material) }
        let definitions = options.definitionMutation == "missing"
            ? []
            : [definition(options)]
        return .init(
            layers: [.init(
                id: 20,
                contentKind: options.contentKind,
                effects: priorInput ? [dummy, tint] : [tint]
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
            .init(
                effect: key,
                definitionPassIndex: 0,
                reason: .unsupportedCondition,
                detail: "bad"
            )
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

    static func planned(
        graphOptions: GraphOptions = .init(),
        descriptorOptions: Options = .init(),
        contracts: [SceneShaderContract],
        role: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneTintExecutionPlan? {
        SceneAuthoredTintPlanner.plan(
            graph: graph(graphOptions),
            descriptor: descriptor(descriptorOptions, priorInput: graphOptions.priorInput),
            shaderContracts: contracts,
            inputRole: role
        )
    }

    static func accepted(
        graphOptions: GraphOptions = .init(),
        descriptorOptions: Options = .init(),
        contracts: [SceneShaderContract],
        role: SceneAuthoredEffectInputRole = .layerSource
    ) -> Bool {
        planned(
            graphOptions: graphOptions,
            descriptorOptions: descriptorOptions,
            contracts: contracts,
            role: role
        ) != nil
    }

    static func blendMode(
        _ options: Options,
        contracts: [SceneShaderContract]
    ) -> Int? {
        planned(descriptorOptions: options, contracts: contracts)?.blendMode
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let legacyRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let contracts = SceneShaderContractLoader().load(
            shaderReferences: [shaderIdentity],
            rootURL: root
        )
        let legacyContracts = SceneShaderContractLoader().load(
            shaderReferences: [shaderIdentity],
            rootURL: legacyRoot
        )
        let staticPlan = planned(contracts: contracts)!
        let legacyStaticPlan = planned(contracts: legacyContracts)!

        var boundOptions = Options()
        boundOptions.colorKind = "binding"
        boundOptions.colorBinding = "newproperty50"
        boundOptions.alphaKind = "binding"
        boundOptions.alphaBinding = "newproperty51"
        let boundPlan = planned(descriptorOptions: boundOptions, contracts: contracts)!
        var timelineOptions = Options()
        timelineOptions.alphaKind = "binding"
        timelineOptions.alphaTimeline = true
        timelineOptions.alphaBindingKeys = ["animation", "value"]
        let timelinePlan = planned(
            descriptorOptions: timelineOptions, contracts: contracts
        )!
        let colorTarget = boundPlan.colorBinding!.dynamicTarget
        let alphaTarget = boundPlan.alphaBinding!.dynamicTarget
        let definitions = [
            SceneDynamicTargetDefinition(
                target: colorTarget,
                valueType: .vector3,
                authoredValue: .vector3(0.25, 0.6, 0.9)
            ),
            SceneDynamicTargetDefinition(
                target: alphaTarget,
                valueType: .scalar,
                authoredValue: .scalar(0.4)
            ),
        ]
        let liveSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 1,
            definitions: definitions,
            userValues: [colorTarget: .vector3(0.1, 0.2, 0.3), alphaTarget: .scalar(0.75)]
        ).snapshot
        let invalidSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 2,
            generation: 2,
            definitions: definitions,
            userValues: [colorTarget: .vector3(1.5, 0.2, 0.3), alphaTarget: .scalar(1.5)]
        ).snapshot
        let negativeOvershootSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 3,
            generation: 3,
            definitions: definitions,
            timelineValues: [alphaTarget: .scalar(-0.017034483)]
        ).snapshot
        let positiveOvershootSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 4,
            generation: 4,
            definitions: definitions,
            timelineValues: [alphaTarget: .scalar(1.017034483)]
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
        workshop.definitionPath = "effects/workshop/123/tint/effect.json"
        var graphMaterial = GraphOptions(); graphMaterial.materialPath = "materials/other.json"
        var relocatedGraph = GraphOptions()
        relocatedGraph.definitionPath = "effects/authored-copy/tint/effect.json"
        relocatedGraph.materialPath = "materials/authored-copy/tint.json"
        var relocatedAssets = Options()
        relocatedAssets.definitionPath = relocatedGraph.definitionPath
        relocatedAssets.materialPath = relocatedGraph.materialPath

        var missingAlpha = Options(); missingAlpha.includesAlpha = false
        var alphaZero = Options(); alphaZero.alpha = 0
        var alphaOne = Options(); alphaOne.alpha = 1
        var blackColor = Options(); blackColor.color = [0, 0, 0]
        var whiteColor = Options(); whiteColor.color = [1, 1, 1]

        var materialBlend = Options(); materialBlend.materialCombos = ["BLENDMODE": 12]
        var instanceBlend = Options(); instanceBlend.instanceCombos = ["BLENDMODE": 0]
        var overrideBlend = Options()
        overrideBlend.materialCombos = ["BLENDMODE": 12]
        overrideBlend.instanceCombos = ["BLENDMODE": 22]
        var maxBlend = Options(); maxBlend.instanceCombos = ["BLENDMODE": 32]
        var aboveMaxBlend = Options(); aboveMaxBlend.instanceCombos = ["BLENDMODE": 33]
        var negativeBlend = Options(); negativeBlend.instanceCombos = ["BLENDMODE": -1]
        var lowercaseBlend = Options(); lowercaseBlend.instanceCombos = ["blendmode": 18]

        var colorScript = Options(); colorScript.colorKind = "binding"
        var alphaScript = Options(); alphaScript.alphaKind = "binding"
        alphaScript.alphaScriptSource = "'unknown'"
        alphaScript.alphaBindingKeys = ["script", "value"]
        var diagnosedTimeline = timelineOptions
        diagnosedTimeline.alphaTimelineDiagnostics = ["invalidWrapLoop"]
        var extraTimelineKey = timelineOptions
        extraTimelineKey.alphaBindingKeys = ["animation", "extra", "value"]
        var colorTimeline = Options()
        colorTimeline.colorKind = "binding"
        colorTimeline.colorTimeline = true
        colorTimeline.colorBindingKeys = ["animation", "value"]
        var relativeTimeline = timelineOptions
        relativeTimeline.alphaTimelineRelative = true
        var combinedTimeline = timelineOptions
        combinedTimeline.alphaTimelineParent = 7
        var multiLaneTimeline = timelineOptions
        multiLaneTimeline.alphaTimelineComponentCount = 2
        var nonExecutableTimeline = timelineOptions
        nonExecutableTimeline.alphaTimelineExecutable = false
        var colorWrongKind = Options(); colorWrongKind.colorBinding = "newproperty50"
        var alphaWrongKind = Options(); alphaWrongKind.alphaBinding = "newproperty51"
        var emptyColorBinding = Options()
        emptyColorBinding.colorKind = "binding"
        emptyColorBinding.colorBinding = "  "

        var missingColor = Options(); missingColor.includesColor = false
        var shortColor = Options(); shortColor.color = [0.5, 0.5]
        var longColor = Options(); longColor.color = [0.5, 0.5, 0.5, 0.5]
        var lowColor = Options(); lowColor.color = [-0.01, 0.5, 0.5]
        var highColor = Options(); highColor.color = [1.01, 0.5, 0.5]
        var nonFiniteColor = Options(); nonFiniteColor.color = [.nan, 0.5, 0.5]
        var extraConstant = Options(); extraConstant.extraInstanceConstant = true
        var lowAlpha = Options(); lowAlpha.alpha = -0.01
        var highAlpha = Options(); highAlpha.alpha = 1.01
        var nonFiniteAlpha = Options(); nonFiniteAlpha.alpha = .infinity

        var instanceMask = Options(); instanceMask.instanceCombos = ["MASK": 0]
        var materialMask = Options(); materialMask.materialCombos = ["MASK": 0]
        var maskOne = Options(); maskOne.instanceCombos = ["MASK": 1]
        var unknownCombo = Options(); unknownCombo.materialCombos = ["OTHER": 0]
        var maskTexture = Options(); maskTexture.maskTexture = true
        var instanceTexture = Options(); instanceTexture.instanceTexture = true
        var instanceUserTexture = Options(); instanceUserTexture.instanceUserTexture = true
        var materialTexture = Options(); materialTexture.materialTexture = true
        var materialUserTexture = Options(); materialUserTexture.materialUserTexture = true

        var materialConstant = Options(); materialConstant.materialConstant = true
        var materialUserShader = Options(); materialUserShader.materialUserShaderValue = true
        var materialAlphaWriting = Options(); materialAlphaWriting.alphaWriting = "default"
        var state = Options(); state.blending = "additive"
        var depth = Options(); depth.depthTest = "enabled"
        var materialPathOption = Options()
        materialPathOption.materialPath = "materials/other.json"
        var materialHash = Options()
        materialHash.materialRawSHA256 = String(repeating: "0", count: 64)
        var materialPass = Options(); materialPass.materialPassIndex = 1
        var shader = Options(); shader.shaderIdentity = "effects/other"
        var missingReplacement = Options()
        missingReplacement.definitionMutation = "missingReplacement"
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

        let liveColor = boundPlan.resolvedColor(in: liveSnapshot)
        let fallbackColor = boundPlan.resolvedColor(in: invalidSnapshot)
        let result: [String: Any] = [
            "canonicalContract": contracts.first?.canonicalSHA256
                == "606ea00aef226fc0d7d1360f9bb4750af3c323831bc94399c64327084c9f5b36",
            "legacyCanonicalContract": legacyContracts.first?.canonicalSHA256
                == "3c418471e512703771cdf2bd3ffbfeda024113fa6edd426ddd37267605e087ee",
            "profilesResolved": SceneTintShaderProfile.resolve(contracts) == .stock2842
                && SceneTintShaderProfile.resolve(legacyContracts) == .legacyMaskOverride,
            "staticAccepted": staticPlan.staticOrFallbackColor
                == SIMD3<Float>(0.25, 0.6, 0.9)
                && staticPlan.staticOrFallbackAlpha == 0.4
                && staticPlan.colorBinding == nil
                && staticPlan.alphaBinding == nil
                && staticPlan.liveConsumerTargets.isEmpty,
            "legacyStaticAccepted": legacyStaticPlan.staticOrFallbackColor
                == SIMD3<Float>(0.25, 0.6, 0.9)
                && legacyStaticPlan.staticOrFallbackAlpha == 0.4
                && legacyStaticPlan.colorBinding == nil
                && legacyStaticPlan.alphaBinding == nil,
            // legacy 的 [COMBO]/常量注解与 stock 逐字符一致：BLENDMODE 默认同为 30、
            // 缺省 alpha 同为 1、显式 BLENDMODE 同样生效。
            "legacyDefaultBlendMode": legacyStaticPlan.blendMode == 30,
            "legacyMissingAlphaDefaultsToOne": planned(
                descriptorOptions: missingAlpha, contracts: legacyContracts
            )?.staticOrFallbackAlpha == 1,
            "legacyBlendModeResolved":
                blendMode(materialBlend, contracts: legacyContracts) == 12
                && blendMode(instanceBlend, contracts: legacyContracts) == 0,
            "legacyBindingsAccepted": planned(
                descriptorOptions: boundOptions, contracts: legacyContracts
            )?.colorBinding?.propertyKey == "newproperty50",
            // 遮罩按指纹分流：legacy 的 #if MASK 是覆盖语义，plan 记录 profile 供渲染分流；
            // 显式 MASK combo 声明（语料 0 次）在两个指纹下都仍整条拒绝。
            "legacyMaskRejected": !accepted(descriptorOptions: maskOne, contracts: legacyContracts),
            "legacyMaskAccepted": planned(
                descriptorOptions: maskTexture, contracts: legacyContracts
            )?.maskTexturePath == "mask.png"
                && planned(
                    descriptorOptions: maskTexture, contracts: legacyContracts
                )?.shaderProfile.maskMultipliesBlendAlpha == false,
            "legacyContractRejected": ["source", "raw", "metadata", "builtin", "canonical",
                                       "duplicate"]
                .allSatisfy { !accepted(contracts: mutate(legacyContracts, $0)) },
            // definition 白名单：legacy 包（1937925563）的 effect.json 缺 replacementkey，
            // 仅 legacy 指纹接受该形态；stock 指纹保持必须携带，错值两边都拒。
            "legacyMissingReplacementAccepted": accepted(
                descriptorOptions: missingReplacement, contracts: legacyContracts
            ) && !accepted(descriptorOptions: missingReplacement, contracts: contracts),
            // 官方 tint.frag 的 [COMBO] 默认值 30，未声明 BLENDMODE 时按 30 走。
            "defaultBlendMode": staticPlan.blendMode == 30,
            "missingAlphaDefaultsToOne": planned(
                descriptorOptions: missingAlpha, contracts: contracts
            )?.staticOrFallbackAlpha == 1,
            "endpointsAccepted": [alphaZero, alphaOne, blackColor, whiteColor]
                .allSatisfy { accepted(descriptorOptions: $0, contracts: contracts) },
            "blendModeResolved": blendMode(materialBlend, contracts: contracts) == 12
                && blendMode(instanceBlend, contracts: contracts) == 0
                && blendMode(overrideBlend, contracts: contracts) == 22
                && blendMode(maxBlend, contracts: contracts) == 32
                && blendMode(lowercaseBlend, contracts: contracts) == 18,
            "blendModeRangeRejected": [aboveMaxBlend, negativeBlend]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "bindingsAccepted": boundPlan.colorBinding!.propertyKey == "newproperty50"
                && boundPlan.colorBinding!.layerID == 20
                && boundPlan.colorBinding!.effectIndex == 0
                && boundPlan.colorBinding!.constantName == "color"
                && boundPlan.alphaBinding!.propertyKey == "newproperty51"
                && boundPlan.alphaBinding!.constantName == "alpha"
                && boundPlan.liveConsumerTargets.count == 2,
            "timelineBindingAccepted": timelinePlan.alphaBinding?.propertyKey == nil
                && timelinePlan.alphaBinding?.dynamicTarget == alphaTarget
                && timelinePlan.liveConsumerTargets == [alphaTarget],
            "snapshotApplied": liveColor == SIMD3<Float>(0.1, 0.2, 0.3)
                && boundPlan.resolvedAlpha(in: liveSnapshot) == 0.75,
            "snapshotFallback": fallbackColor == SIMD3<Float>(0.25, 0.6, 0.9)
                && boundPlan.resolvedAlpha(in: invalidSnapshot) == 0.4,
            "timelineOvershootClamped":
                timelinePlan.resolvedAlpha(in: negativeOvershootSnapshot) == 0
                && timelinePlan.resolvedAlpha(in: positiveOvershootSnapshot) == 1,
            "priorInputAccepted": accepted(
                graphOptions: prior, contracts: contracts, role: .priorEffectOutput
            ),
            "roleMismatchRejected": !accepted(graphOptions: prior, contracts: contracts),
            "contentDerivedPathsAccepted": accepted(
                graphOptions: relocatedGraph,
                descriptorOptions: relocatedAssets,
                contracts: contracts
            ),
            "workshopVariantRejected": !accepted(graphOptions: workshop, contracts: contracts),
            "graphShapeRejected": [blocker, targetGraph, binding, command, condition, copy,
                                   output, effectCount, nodeCount, graphMaterial]
                .allSatisfy { !accepted(graphOptions: $0, contracts: contracts) },
            "definitionRejected": definitionRejected,
            "sceneScriptRejected": [colorScript, alphaScript]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "invalidTimelineRejected": [
                diagnosedTimeline, extraTimelineKey, colorTimeline, relativeTimeline,
                combinedTimeline, multiLaneTimeline, nonExecutableTimeline,
            ]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "wrongBindingKindRejected": [colorWrongKind, alphaWrongKind]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "emptyBindingRejected": !accepted(
                descriptorOptions: emptyColorBinding, contracts: contracts
            ),
            "colorShapeRejected": [missingColor, shortColor, longColor, lowColor, highColor,
                                   nonFiniteColor, extraConstant]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "alphaShapeRejected": [lowAlpha, highAlpha, nonFiniteAlpha]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "maskDefaultsAccepted": accepted(descriptorOptions: instanceMask, contracts: contracts)
                && accepted(descriptorOptions: materialMask, contracts: contracts),
            "comboRejected": !accepted(descriptorOptions: maskOne, contracts: contracts)
                && !accepted(descriptorOptions: unknownCombo, contracts: contracts),
            // E-MASK-SLOT-COMBO 落地：槽位 1 绑图按官方遮罩语义执行（混合权重，
            // stock 与 g_BlendAlpha 相乘），不再整条拒绝。
            "maskTextureAccepted": planned(
                descriptorOptions: maskTexture, contracts: contracts
            )?.maskTexturePath == "mask.png"
                && planned(
                    descriptorOptions: maskTexture, contracts: contracts
                )?.shaderProfile.maskMultipliesBlendAlpha == true
                && planned(contracts: contracts)?.maskTexturePath == nil,
            "textureRejected": [instanceTexture, instanceUserTexture, materialTexture,
                                materialUserTexture]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "materialRejected": [materialConstant, materialUserShader, materialAlphaWriting,
                                 state, depth, materialPathOption, materialHash, materialPass,
                                 shader, duplicateMaterial]
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


class SceneTintPlannerTests(unittest.TestCase):
    def test_fingerprint_profiles_are_exact_and_fail_closed(self) -> None:
        swiftc = shutil.which("swiftc")
        if not swiftc:
            self.skipTest("swiftc is unavailable")

        with tempfile.TemporaryDirectory(prefix="scene-tint-") as directory:
            root = Path(directory)
            shader_root = root / "shaders/effects"
            shader_root.mkdir(parents=True)
            (shader_root / "tint.vert").write_bytes(base64.b64decode(VERTEX_BASE64))
            (shader_root / "tint.frag").write_bytes(base64.b64decode(FRAGMENT_BASE64))
            legacy_root = root / "legacy"
            legacy_shader_root = legacy_root / "shaders/effects"
            legacy_shader_root.mkdir(parents=True)
            (legacy_shader_root / "tint.vert").write_bytes(
                base64.b64decode(VERTEX_BASE64)
            )
            (legacy_shader_root / "tint.frag").write_bytes(
                base64.b64decode(LEGACY_FRAGMENT_BASE64)
            )
            harness = root / "Harness.swift"
            executable = root / "tint-harness"
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
                [str(executable), str(root), str(legacy_root)],
                check=True,
                capture_output=True,
                text=True,
            )

        output = json.loads(completed.stdout)
        self.assertTrue(output)
        self.assertTrue(all(output.values()), output)


if __name__ == "__main__":
    unittest.main()
