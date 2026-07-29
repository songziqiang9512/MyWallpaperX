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
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredLocalContrastPlanner.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionChain.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectChainPlanner+StageResolution.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectXRayPrefix.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionPlan+Backend.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredPreciseBlurPlanner+Topology.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredStandardBlurPlanner.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan+Extent.swift",
]
CHAIN_PLANNER_SOURCE = (
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionChain.swift"
)
# stage 解析（逐 planner 尝试 + backend 构造）拆在扩展文件中，文本标记检查读拼接。
CHAIN_STAGE_RESOLUTION_SOURCE = (
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectChainPlanner+StageResolution.swift"
)
CHAIN_BACKEND_SOURCE = (
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionPlan+Backend.swift"
)
CHAIN_RENDERER_SOURCE = (
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectChainRenderer.swift"
)
IRIS_SUFFIX_SOURCE = (
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectIrisInlineSuffix.swift"
)
IRIS_SUFFIX_PLANNER_SOURCE = (
    SOURCE_ROOT / "RenderGraph/SceneAuthoredIrisInlineSuffixPlanner.swift"
)
COMPOSITOR_SOURCE = SOURCE_ROOT / "Rendering/SceneImageLayerCompositor.swift"
DRAW_REQUEST_SOURCE = SOURCE_ROOT / "Rendering/SceneImageLayerDrawRequest.swift"
EFFECT_TEXTURE_LOADER_SOURCE = (
    SOURCE_ROOT / "Resources/SceneLayerEffectTextureLoader.swift"
)

SAMPLE_STAGE_FIXTURES = {
    "2998757800": (
        (0, "shake"),
        (1, "shake"),
        (2, "shake"),
        (3, "shake"),
        (4, "foliageSway"),
        (5, "xRay"),
    ),
    "3757555836": (
        (0, "xRay"),
        (1, "waterFlow"),
        (2, "waterRipple"),
        (3, "waterFlow"),
        (4, "shake"),
    ),
}

STAGE_SOURCE_MARKERS = {
    "shake": ("SceneAuthoredShakePlanner.plan", "case shake", "case .shake"),
    "foliageSway": (
        "SceneAuthoredFoliageSwayPlanner.plan",
        "case foliageSway",
        "case .foliageSway",
    ),
    "xRay": ("SceneAuthoredXRayPlanner.plan", "case xRay", "case .xRay"),
    "waterFlow": (
        "SceneAuthoredWaterFlowPlanner.plan",
        "case waterFlow",
        "case .waterFlow",
    ),
    "waterRipple": (
        "SceneAuthoredWaterRipplePlanner.plan",
        "case waterRipple",
        "case .waterRipple",
    ),
}


HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let valueKind: String
        let userBinding: String?
        let components: [Double]?

        init(
            valueKind: String = "vector",
            userBinding: String? = nil,
            components: [Double]?
        ) {
            self.valueKind = valueKind
            self.userBinding = userBinding
            self.components = components
        }
    }
}

struct SceneEffectTextureInput {
    let name: String
}

struct SceneGaussianBlurPlan {
    let horizontalStep: Float
    let verticalStep: Float
    let sampleResolutionScale: Float
    let isPrecise: Bool
}

struct SceneWorkshopShadowExecutionPlan: Equatable, Sendable {
    let alpha: Float
    let color: SIMD3<Float>
    let drawBorder: Float
    let offset: SIMD2<Float>
}

struct SceneOpacityExecutionPlan: Sendable {
    var liveAlphaTarget: SceneDynamicTarget? { nil }

    func resolvedAlpha(in snapshot: SceneDynamicSnapshot) -> Float { 1 }
}

struct SceneColorKeyExecutionPlan: Sendable {}
struct SceneWorkshopShiftHueExecutionPlan: Sendable {}
struct SceneWorkshopAudioBarsExecutionPlan: Sendable {
    enum Profile: Sendable {
        case enhancedSegmented(shape: Int)
        case simple
    }

    let profile: Profile
    var liveConsumerTargets: Set<SceneDynamicTarget> { [] }
}
struct SceneWorkshopGradientExecutionPlan: Sendable {}
struct SceneWorkshopAudioHueShiftExecutionPlan: Sendable {}
struct SceneSpinExecutionPlan: Sendable {}
struct SceneProceduralNoiseExecutionPlan: Sendable {}
struct SceneFilmGrainExecutionPlan: Sendable {}
struct SceneLightShaftsExecutionPlan: Sendable {}
struct SceneAuthoredShaderExecutionPlan: Sendable {
    let offscreenSize: CGSize?

    func offscreenSize(for requestedSize: CGSize) -> CGSize? { offscreenSize }
}

enum SceneAuthoredShaderExecutionPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole
    ) -> SceneAuthoredShaderExecutionPlan? {
        nil
    }
}

enum SceneAuthoredOpacityPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneOpacityExecutionPlan? {
        nil
    }
}

enum SceneAuthoredColorKeyPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneColorKeyExecutionPlan? {
        nil
    }
}

enum SceneAuthoredWorkshopShiftHuePlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWorkshopShiftHueExecutionPlan? {
        nil
    }
}

enum SceneAuthoredWorkshopAudioBarsPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWorkshopAudioBarsExecutionPlan? {
        nil
    }
}

enum SceneAuthoredWorkshopSimpleAudioBarsPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWorkshopAudioBarsExecutionPlan? {
        nil
    }
}

enum SceneAuthoredWorkshopGradientPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWorkshopGradientExecutionPlan? {
        nil
    }
}

enum SceneAuthoredWorkshopAudioHueShiftPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWorkshopAudioHueShiftExecutionPlan? {
        nil
    }
}

enum SceneAuthoredWorkshopShadowPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWorkshopShadowExecutionPlan? {
        nil
    }
}

enum SceneAuthoredSpinPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneSpinExecutionPlan? {
        nil
    }
}

enum SceneAuthoredProceduralNoisePlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneProceduralNoiseExecutionPlan? {
        nil
    }
}

enum SceneAuthoredFilmGrainPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneFilmGrainExecutionPlan? {
        nil
    }
}

enum SceneAuthoredLightShaftsPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneLightShaftsExecutionPlan? {
        nil
    }
}

struct SceneShakeExecutionPlan {}

enum SceneAuthoredShakePlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneShakeExecutionPlan? {
        graph.effects.first?.definitionPath.lowercased()
            == "effects/shake/effect.json" ? SceneShakeExecutionPlan() : nil
    }
}

struct SceneWaterFlowExecutionPlan {}

enum SceneAuthoredWaterFlowPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWaterFlowExecutionPlan? {
        graph.effects.first?.definitionPath.lowercased()
            == "effects/waterflow/effect.json" ? SceneWaterFlowExecutionPlan() : nil
    }
}

struct SceneWaterWavesExecutionPlan {}

enum SceneAuthoredWaterWavesPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWaterWavesExecutionPlan? {
        nil
    }
}

struct SceneCursorRippleExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}
struct SceneIrisInlineSuffixPlan {}

enum SceneAuthoredCursorRipplePlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneCursorRippleExecutionPlan? {
        nil
    }
}

extension SceneAuthoredEffectChainPlanner {
    static func irisInlineSuffix(
        plannedStages: [SceneAuthoredEffectExecutionPlan],
        unsupportedOrdinal: Int,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> SceneAuthoredEffectExecutionChain? {
        nil
    }

    static func isolatedCursorRippleChain(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> SceneAuthoredEffectExecutionChain? {
        nil
    }

    static func isolatedShineChain(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> SceneAuthoredEffectExecutionChain? {
        nil
    }
}

struct SceneFoliageSwayExecutionPlan {}

enum SceneAuthoredFoliageSwayPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneFoliageSwayExecutionPlan? {
        graph.effects.first?.definitionPath.lowercased()
            == "effects/foliagesway/effect.json"
            ? SceneFoliageSwayExecutionPlan()
            : nil
    }
}

struct SceneWaterRippleExecutionPlan {}

enum SceneAuthoredWaterRipplePlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWaterRippleExecutionPlan? {
        graph.effects.first?.definitionPath.lowercased()
            == "effects/waterripple/effect.json"
            ? SceneWaterRippleExecutionPlan()
            : nil
    }
}

struct SceneXRayExecutionPlan {
    var liveConsumerTargets: Set<SceneDynamicTarget> { [] }
}

struct SceneClippingMaskExecutionPlan {}

enum SceneAuthoredXRayPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneXRayExecutionPlan? {
        graph.effects.first?.definitionPath.lowercased()
            == "effects/xray/effect.json" ? SceneXRayExecutionPlan() : nil
    }
}

enum SceneAuthoredClippingMaskPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneClippingMaskExecutionPlan? {
        nil
    }
}

struct SceneBlendExecutionPlan {
    var executedUserPropertyKeys: Set<String> { [] }
}

enum SceneAuthoredBlendPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneBlendExecutionPlan? {
        nil
    }
}

struct SceneTintExecutionPlan {
    var liveConsumerTargets: Set<SceneDynamicTarget> { [] }
}

struct SceneTransformStaticFallbackDiagnostic {
    var reportValue: String { "" }
}

struct SceneTransformExecutionPlan {
    var staticFallbackDiagnostics: [SceneTransformStaticFallbackDiagnostic] { [] }
}

enum SceneAuthoredTransformPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneTransformExecutionPlan? {
        nil
    }
}

struct SceneFisheyeZeroDistortionPlan {}

enum SceneAuthoredFisheyeZeroDistortionPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneFisheyeZeroDistortionPlan? {
        nil
    }
}

struct ScenePulseExecutionPlan {
    var liveConsumerTargets: Set<SceneDynamicTarget> { [] }
}

enum SceneAuthoredPulsePlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> ScenePulseExecutionPlan? {
        graph.effects.first?.definitionPath.lowercased()
            == "effects/pulse/effect.json" ? ScenePulseExecutionPlan() : nil
    }
}

struct SceneGodraysPlan {
    var liveConsumerTargets: Set<SceneDynamicTarget> { [] }
}

enum SceneAuthoredGodraysPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneGodraysPlan? {
        nil
    }
}

struct SceneShineExecutionPlan {}

enum SceneAuthoredShinePlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneShineExecutionPlan? {
        nil
    }
}

enum SceneAuthoredTintPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneTintExecutionPlan? {
        graph.effects.first?.definitionPath.lowercased()
            == "effects/tint/effect.json" ? SceneTintExecutionPlan() : nil
    }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }

        let id: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let parentID: Int?
        let visible: Bool?
        let contentKind: String
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let shaderPath: String?
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
}

enum SceneLayerVisibility {
    static func visibleLayerIDs(in descriptor: SceneRenderDescriptor) -> Set<Int> {
        let byID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        return Set(descriptor.layers.compactMap { layer in
            var current: SceneRenderDescriptor.Layer? = layer
            var visited = Set<Int>()
            while let candidate = current {
                guard candidate.visible != false, visited.insert(candidate.id).inserted else {
                    return nil
                }
                current = candidate.parentID.flatMap { byID[$0] }
            }
            return layer.id
        })
    }
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static func texture(
        _ kind: Graph.TextureKind,
        layerID: Int,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func instanceEffect(
        layerID: Int,
        scale: Double = 1.28,
        scaleComponents: [Double]? = nil,
        valueKind: String = "vector",
        userBinding: String? = nil,
        duplicateScaleKey: Bool = false,
        legacyCompose: Bool = false
    ) -> SceneRenderDescriptor.EffectDescriptor {
        var scaleValues = [
            "scale": SceneDocument.ShaderValue(
                valueKind: valueKind,
                userBinding: userBinding,
                components: scaleComponents ?? [scale, scale]
            ),
        ]
        if duplicateScaleKey {
            scaleValues["Scale"] = .init(components: [scale, scale])
        }
        return .init(
            id: "\(layerID)#effect#1",
            visible: true,
            passes: [
                .init(
                    passIndex: 0, textureSlots: [], userTextureInputs: [], combos: [:],
                    constantShaderValues: scaleValues
                ),
                .init(
                    passIndex: 1, textureSlots: [], userTextureInputs: [],
                    combos: legacyCompose
                        ? ["VERTICAL": 1]
                        : ["VERTICAL": 1, "ENABLEMASK": 1],
                    constantShaderValues: scaleValues
                ),
            ]
        )
    }

    static func materials(
        shader: String = "workshop/1/effects/blur_precise_gaussian",
        blending: String = "normal",
        verticalCombos: [String: Int] = ["VERTICAL": 1, "ENABLEMASK": 1]
    ) -> [SceneRenderDescriptor.MaterialPassDescriptor] {
        [
            .init(
                id: "materials/x.json#0", materialPath: "materials/x.json",
                shaderPath: shader, textureSlots: [], userTextureInputs: [],
                combos: [:], constantShaderValues: [:],
                blending: blending, depthTest: "disabled", depthWrite: "disabled", cullMode: "nocull"
            ),
            .init(
                id: "materials/y.json#0", materialPath: "materials/y.json",
                shaderPath: shader, textureSlots: [], userTextureInputs: [],
                combos: verticalCombos,
                constantShaderValues: [:], blending: blending, depthTest: "disabled",
                depthWrite: "disabled", cullMode: "nocull"
            ),
        ]
    }

    static func descriptorForLayer10(
        effect: SceneRenderDescriptor.EffectDescriptor
    ) -> SceneRenderDescriptor {
        .init(
            layers: [
                .init(
                    id: 10, parentID: nil, visible: true, contentKind: "text",
                    effects: [effect]
                ),
            ],
            materialPasses: materials()
        )
    }

    static func graph(
        layerID: Int,
        blockers: [Graph.Blocker] = [],
        extraEffect: Bool = false,
        unique: Bool = false,
        maskCombo: Bool = false,
        legacyCompose: Bool = false
    ) -> Graph {
        let key = Graph.EffectKey(
            layerID: layerID, effectIndex: 0, descriptorID: "\(layerID)#effect#1"
        )
        let source = texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let rt = texture(.framebuffer, layerID: layerID, effect: key, name: "full")
        let verticalBindings: [Graph.Binding] = [
            .init(slot: 0, authoredName: "full", texture: rt, conditions: nil),
        ] + (!legacyCompose ? [
            .init(
                slot: maskCombo ? 2 : 1, authoredName: "previous",
                texture: source, conditions: nil
            ),
        ] : [])
        let nodes = [
            Graph.Node(
                nodeIndex: 0, effect: key, definitionPassIndex: 0, materialOrdinal: 0,
                instancePassIndex: 0, kind: .material, materialPath: "materials/x.json",
                materialPassID: "materials/x.json#0", target: rt,
                bindings: legacyCompose
                    ? [.init(slot: 0, authoredName: "previous", texture: source, conditions: nil)]
                    : [],
                commandSource: nil, commandTarget: nil, compose: nil, conditions: nil
            ),
            Graph.Node(
                nodeIndex: 1, effect: key, definitionPassIndex: 1, materialOrdinal: 1,
                instancePassIndex: 1, kind: .material, materialPath: "materials/y.json",
                materialPassID: "materials/y.json#0", target: output,
                bindings: verticalBindings, commandSource: nil, commandTarget: nil,
                compose: nil, conditions: nil
            ),
        ]
        let effect = Graph.Effect(
            key: key, definitionPath: "effects/workshop/1/blurprecise/effect.json", input: source,
            output: output, nodeIndices: [0, 1]
        )
        return Graph(
            layerID: layerID,
            effects: extraEffect ? [effect, effect] : [effect],
            renderTargets: [
                .init(
                    texture: rt,
                    extent: legacyCompose
                        ? .init(kind: .scale, first: 1, second: nil)
                        : .init(kind: .input, first: nil, second: nil),
                    format: "rgba_backbuffer", declaredUnique: unique, clear: nil,
                    uvs: nil, conditions: nil
                ),
            ],
            nodes: nodes,
            finalOutput: output,
            blockers: blockers
        )
    }

    static func interleavedGraph(
        commandKind: Graph.NodeKind,
        commandAfterVertical: Bool = false,
        commandCompose: SceneJSONValue? = nil
    ) -> Graph {
        let layerID = 10
        let key = Graph.EffectKey(
            layerID: layerID, effectIndex: 0, descriptorID: "\(layerID)#effect#1"
        )
        let source = texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let first = texture(.framebuffer, layerID: layerID, effect: key, name: "first")
        let second = texture(.framebuffer, layerID: layerID, effect: key, name: "second")
        let commandIndex = commandAfterVertical ? 2 : 1
        let verticalIndex = commandAfterVertical ? 1 : 2
        let horizontal = Graph.Node(
            nodeIndex: 0, effect: key, definitionPassIndex: 0, materialOrdinal: 0,
            instancePassIndex: 0, kind: .material, materialPath: "materials/x.json",
            materialPassID: "materials/x.json#0", target: first, bindings: [],
            commandSource: nil, commandTarget: nil, compose: nil, conditions: nil
        )
        let command = Graph.Node(
            nodeIndex: commandIndex, effect: key, definitionPassIndex: 1,
            materialOrdinal: nil, instancePassIndex: nil, kind: commandKind,
            materialPath: nil, materialPassID: nil, target: nil, bindings: [],
            commandSource: first, commandTarget: second, compose: commandCompose,
            conditions: nil
        )
        let vertical = Graph.Node(
            nodeIndex: verticalIndex, effect: key, definitionPassIndex: 2,
            materialOrdinal: 1, instancePassIndex: 1, kind: .material,
            materialPath: "materials/y.json", materialPassID: "materials/y.json#0",
            target: output,
            bindings: [
                .init(slot: 0, authoredName: "second", texture: second, conditions: nil),
                .init(slot: 1, authoredName: "previous", texture: source, conditions: nil),
            ],
            commandSource: nil, commandTarget: nil, compose: nil, conditions: nil
        )
        let nodes = commandAfterVertical
            ? [horizontal, vertical, command]
            : [horizontal, command, vertical]
        return Graph(
            layerID: layerID,
            effects: [
                .init(
                    key: key,
                    definitionPath: "effects/workshop/1/blurprecise/effect.json",
                    input: source,
                    output: output,
                    nodeIndices: nodes.map(\.nodeIndex)
                ),
            ],
            renderTargets: [
                .init(
                    texture: first, extent: .init(kind: .input, first: nil, second: nil),
                    format: "rgba_backbuffer", declaredUnique: false, clear: nil,
                    uvs: nil, conditions: nil
                ),
                .init(
                    texture: second, extent: .init(kind: .input, first: nil, second: nil),
                    format: "rgba_backbuffer", declaredUnique: commandKind == .swap,
                    clear: nil, uvs: nil, conditions: nil
                ),
            ],
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
    }

    static func standardBlurInstanceEffect(
        layerID: Int = 530,
        gaussianCombos: [String: Int] = [:],
        combineCombos: [String: Int] = [:]
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let scale = SceneDocument.ShaderValue(
            valueKind: "binding", userBinding: "newproperty", components: [0.6]
        )
        return .init(
            id: "\(layerID)#effect#0",
            visible: true,
            passes: [
                .init(
                    passIndex: 0, textureSlots: [], userTextureInputs: [], combos: [:],
                    constantShaderValues: [:]
                ),
                .init(
                    passIndex: 1, textureSlots: [], userTextureInputs: [],
                    combos: gaussianCombos, constantShaderValues: ["scale": scale]
                ),
                .init(
                    passIndex: 2, textureSlots: [], userTextureInputs: [], combos: [:],
                    constantShaderValues: ["scale": scale]
                ),
                .init(
                    passIndex: 3, textureSlots: [], userTextureInputs: [],
                    combos: combineCombos,
                    constantShaderValues: [
                        "compositecolor": .init(components: [1, 1, 1]),
                    ]
                ),
            ]
        )
    }

    static func standardBlurMaterials(
        gaussianShader: String = "effects/blur_gaussian",
        blending: String = "normal",
        combineCombos: [String: Int] = [:]
    ) -> [SceneRenderDescriptor.MaterialPassDescriptor] {
        func material(
            _ name: String,
            shader: String,
            combos: [String: Int] = [:]
        ) -> SceneRenderDescriptor.MaterialPassDescriptor {
            .init(
                id: "materials/effects/\(name).json#0",
                materialPath: "materials/effects/\(name).json",
                shaderPath: shader, textureSlots: [], userTextureInputs: [], combos: combos,
                constantShaderValues: [:], blending: blending, depthTest: "disabled",
                depthWrite: "disabled", cullMode: "nocull"
            )
        }
        return [
            material("blur_downsample4", shader: "effects/blur_downsample4"),
            material("blur_gaussian_x", shader: gaussianShader),
            material(
                "blur_gaussian_y", shader: gaussianShader,
                combos: ["VERTICAL": 1]
            ),
            material(
                "blur_combine", shader: "effects/blur_combine", combos: combineCombos
            ),
        ]
    }

    static func standardBlurDescriptor(
        effect: SceneRenderDescriptor.EffectDescriptor = standardBlurInstanceEffect(),
        materials: [SceneRenderDescriptor.MaterialPassDescriptor] = standardBlurMaterials()
    ) -> SceneRenderDescriptor {
        .init(
            layers: [
                .init(
                    id: 530, parentID: nil, visible: true, contentKind: "composition",
                    effects: [effect]
                ),
            ],
            materialPasses: materials
        )
    }

    static func standardBlurGraph(
        wrongExtent: Bool = false,
        wrongBinding: Bool = false,
        extraMixedEffect: Bool = false
    ) -> Graph {
        let layerID = 530
        let key = Graph.EffectKey(
            layerID: layerID, effectIndex: 0, descriptorID: "530#effect#0"
        )
        let source = texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let quarterA = texture(
            .framebuffer, layerID: layerID, effect: key,
            name: "_rt_QuarterCompoBuffer1"
        )
        let quarterB = texture(
            .framebuffer, layerID: layerID, effect: key,
            name: "_rt_QuarterCompoBuffer2"
        )
        let materials = [
            "materials/effects/blur_downsample4.json",
            "materials/effects/blur_gaussian_x.json",
            "materials/effects/blur_gaussian_y.json",
            "materials/effects/blur_combine.json",
        ]
        let bindings: [[Graph.Binding]] = [
            [
                .init(
                    slot: wrongBinding ? 1 : 0, authoredName: "previous",
                    texture: source, conditions: nil
                ),
            ],
            [.init(slot: 0, authoredName: "_rt_QuarterCompoBuffer1", texture: quarterA, conditions: nil)],
            [.init(slot: 0, authoredName: "_rt_QuarterCompoBuffer2", texture: quarterB, conditions: nil)],
            [
                .init(slot: 0, authoredName: "_rt_QuarterCompoBuffer1", texture: quarterA, conditions: nil),
                .init(slot: 2, authoredName: "previous", texture: source, conditions: nil),
            ],
        ]
        let targets: [Graph.TextureIdentity] = [quarterA, quarterB, quarterA, output]
        let nodes = materials.indices.map { ordinal in
            Graph.Node(
                nodeIndex: ordinal, effect: key, definitionPassIndex: ordinal,
                materialOrdinal: ordinal, instancePassIndex: ordinal, kind: .material,
                materialPath: materials[ordinal],
                materialPassID: "\(materials[ordinal])#0", target: targets[ordinal],
                bindings: bindings[ordinal], commandSource: nil, commandTarget: nil,
                compose: nil, conditions: nil
            )
        }
        let effect = Graph.Effect(
            key: key, definitionPath: "effects/blur/effect.json", input: source,
            output: output, nodeIndices: [0, 1, 2, 3]
        )
        let mixedKey = Graph.EffectKey(
            layerID: layerID, effectIndex: 1, descriptorID: "530#effect#1"
        )
        let mixed = Graph.Effect(
            key: mixedKey, definitionPath: "effects/water/effect.json", input: output,
            output: texture(.effectOutput, layerID: layerID, effect: mixedKey),
            nodeIndices: []
        )
        return Graph(
            layerID: layerID,
            effects: extraMixedEffect ? [effect, mixed] : [effect],
            renderTargets: [quarterA, quarterB].enumerated().map { index, texture in
                .init(
                    texture: texture,
                    extent: .init(
                        kind: wrongExtent && index == 0 ? .input : .scale,
                        first: wrongExtent && index == 0 ? nil : 4,
                        second: nil
                    ),
                    format: "rgba_backbuffer", declaredUnique: false, clear: nil,
                    uvs: nil, conditions: nil
                )
            },
            nodes: nodes, finalOutput: output, blockers: []
        )
    }

    static func resolverPrecedence() -> [[String]] {
        let key = Graph.EffectKey(layerID: 99, effectIndex: 0, descriptorID: "resolver")
        let graphTexture = texture(.layerSource, layerID: 99)
        let node = Graph.Node(
            nodeIndex: 0, effect: key, definitionPassIndex: 0, materialOrdinal: 0,
            instancePassIndex: 0, kind: .material, materialPath: "materials/resolver.json",
            materialPassID: "materials/resolver.json#0", target: graphTexture,
            bindings: [.init(slot: 1, authoredName: "previous", texture: graphTexture, conditions: nil)],
            commandSource: nil, commandTarget: nil, compose: nil, conditions: nil
        )
        let effect = Graph.Effect(
            key: key, definitionPath: "effect.json", input: graphTexture,
            output: graphTexture, nodeIndices: [0]
        )
        let graph = Graph(
            layerID: 99, effects: [effect], renderTargets: [], nodes: [node],
            finalOutput: graphTexture, blockers: []
        )
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            textureSlots: [nil, "instance-one", "instance-two"],
            userTextureInputs: [nil, nil, .init(name: "user-two")],
            combos: ["INSTANCE": 2],
            constantShaderValues: ["value": .init(components: [2])]
        )
        let descriptor = SceneRenderDescriptor(
            layers: [
                .init(
                    id: 99, parentID: nil, visible: true, contentKind: "image",
                    effects: [.init(id: "resolver", visible: true, passes: [pass])]
                ),
            ],
            materialPasses: [
                .init(
                    id: "materials/resolver.json#0", materialPath: "materials/resolver.json",
                    shaderPath: "effects/test",
                    textureSlots: ["material-zero", "material-one", "material-two"],
                    userTextureInputs: [nil, .init(name: "material-user-one")],
                    combos: ["MATERIAL": 1],
                    constantShaderValues: ["value": .init(components: [1])],
                    blending: "normal", depthTest: "disabled", depthWrite: "disabled", cullMode: "nocull"
                ),
            ]
        )
        let resolution = SceneAuthoredMaterialResolver.resolve(
            node: node, graph: graph, descriptor: descriptor
        )
        return resolution.node!.textureSlots.map { slot in
            slot?.candidates.map(\.provenance.rawValue) ?? ["hole"]
        }
    }

    static func sampleChain(
        layerID: Int,
        stageNames: [String]
    ) -> (graph: Graph, descriptor: SceneRenderDescriptor) {
        var priorOutput = texture(.layerSource, layerID: layerID)
        var effects: [Graph.Effect] = []
        var nodes: [Graph.Node] = []
        var descriptors: [SceneRenderDescriptor.EffectDescriptor] = []
        for (effectIndex, stageName) in stageNames.enumerated() {
            let key = Graph.EffectKey(
                layerID: layerID,
                effectIndex: effectIndex,
                descriptorID: "\(layerID)#effect#\(effectIndex)"
            )
            let output = texture(.effectOutput, layerID: layerID, effect: key)
            let definitionPath = "effects/\(stageName.lowercased())/effect.json"
            effects.append(.init(
                key: key,
                definitionPath: definitionPath,
                input: priorOutput,
                output: output,
                nodeIndices: [effectIndex]
            ))
            nodes.append(.init(
                nodeIndex: effectIndex,
                effect: key,
                definitionPassIndex: 0,
                materialOrdinal: 0,
                instancePassIndex: 0,
                kind: .material,
                materialPath: "materials/\(stageName.lowercased()).json",
                materialPassID: "materials/\(stageName.lowercased()).json#0",
                target: output,
                bindings: [],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            ))
            descriptors.append(.init(id: key.descriptorID, visible: true, passes: []))
            priorOutput = output
        }
        return (
            Graph(
                layerID: layerID,
                effects: effects,
                renderTargets: [],
                nodes: nodes,
                finalOutput: priorOutput,
                blockers: []
            ),
            SceneRenderDescriptor(
                layers: [
                    .init(
                        id: layerID,
                        parentID: nil,
                        visible: true,
                        contentKind: "image",
                        effects: descriptors
                    ),
                ],
                materialPasses: []
            )
        )
    }

    static func stageEvidence(
        _ chain: SceneAuthoredEffectExecutionChain?
    ) -> [[Any]] {
        chain?.stages.map { stage in
            let effectIndex = stage.renderGraph.effects[0].key.effectIndex
            let backend: String
            switch stage.backend {
            case .preciseGaussian: backend = "preciseGaussian"
            case .standardBlur: backend = "standardBlur"
            case .localContrast: backend = "localContrast"
            case .opacity: backend = "opacity"
            case .colorKey: backend = "colorKey"
            case .workshopShiftHue: backend = "workshopShiftHue"
            case .workshopAudioBars: backend = "workshopAudioBars"
            case .workshopGradient: backend = "workshopGradient"
            case .workshopAudioHueShift: backend = "workshopAudioHueShift"
            case .workshopShadow: backend = "workshopShadow"
            case .spin: backend = "spin"
            case .proceduralNoise: backend = "proceduralNoise"
            case .filmGrain: backend = "filmGrain"
            case .lightShafts: backend = "lightShafts"
            case .shake: backend = "shake"
            case .waterFlow: backend = "waterFlow"
            case .waterWaves: backend = "waterWaves"
            case .cursorRipple: backend = "cursorRipple"
            case .foliageSway: backend = "foliageSway"
            case .waterRipple: backend = "waterRipple"
            case .xRay: backend = "xRay"
            case .clippingMask: backend = "clippingMask"
            case .blend: backend = "blend"
            case .tint: backend = "tint"
            case .transform: backend = "transform"
            case .fisheyeZeroDistortion: backend = "fisheyeZeroDistortion"
            case .pulse: backend = "pulse"
            case .godrays: backend = "godrays"
            case .shine: backend = "shine"
            case .authoredShader: backend = "authoredShader"
            }
            return [effectIndex, backend]
        } ?? []
    }

    static func main() throws {
        let layers: [SceneRenderDescriptor.Layer] = [
            .init(id: 10, parentID: nil, visible: true, contentKind: "text", effects: [instanceEffect(layerID: 10, scale: 1.28)]),
            .init(id: 20, parentID: nil, visible: false, contentKind: "text", effects: [instanceEffect(layerID: 20, scale: 0.43)]),
            .init(id: 21, parentID: 20, visible: true, contentKind: "text", effects: [instanceEffect(layerID: 21, scale: 1.33)]),
            .init(id: 30, parentID: nil, visible: true, contentKind: "text", effects: [instanceEffect(layerID: 30, scale: 0.43)]),
        ]
        let descriptor = SceneRenderDescriptor(layers: layers, materialPasses: materials())
        let catalog = SceneAuthoredEffectExecutionCatalog(
            descriptor: descriptor,
            authoredPlans: [
                graph(layerID: 10), graph(layerID: 20), graph(layerID: 21),
                graph(layerID: 30, extraEffect: true),
            ]
        )
        let visiblePlan = catalog.plansByLayerID[10]!
        let preciseBlur = visiblePlan.gaussianBlur!
        let preciseRenderTargetPlan: SceneGraphRenderTargetPlan = {
            switch SceneGraphRenderTargetPlan.make(
                executionPlan: visiblePlan,
                graph: visiblePlan.renderGraph,
                inputWidth: 1279,
                inputHeight: 719
            ) {
            case .success(let plan): return plan
            case .failure(let failure):
                fatalError("precise render target plan failed: \(failure.rawValue)")
            }
        }()
        let preciseBackendMatched: Bool = {
            if case .preciseGaussian = visiblePlan.backend { return true }
            return false
        }()
        let badStateDescriptor = SceneRenderDescriptor(layers: layers, materialPasses: materials(blending: "additive"))
        let badShaderDescriptor = SceneRenderDescriptor(layers: layers, materialPasses: materials(shader: "effects/unknown"))
        let duplicateComboDescriptor = SceneRenderDescriptor(
            layers: layers,
            materialPasses: materials(verticalCombos: ["VERTICAL": 1, "vertical": 1, "ENABLEMASK": 1])
        )
        let dynamicScaleDescriptor = descriptorForLayer10(
            effect: instanceEffect(layerID: 10, scale: 1.28, userBinding: "user.scale")
        )
        let outOfRangeScaleDescriptor = descriptorForLayer10(
            effect: instanceEffect(layerID: 10, scale: -1)
        )
        let duplicateScaleDescriptor = descriptorForLayer10(
            effect: instanceEffect(layerID: 10, scale: 1.28, duplicateScaleKey: true)
        )
        let threeComponentScaleDescriptor = descriptorForLayer10(
            effect: instanceEffect(layerID: 10, scaleComponents: [1.28, 1.28, 1.28])
        )
        let missingMaterialDescriptor = SceneRenderDescriptor(layers: layers, materialPasses: [])
        let blocker = Graph.Blocker(
            effect: Graph.EffectKey(layerID: 10, effectIndex: 0, descriptorID: "10#effect#1"),
            definitionPassIndex: nil, reason: .unsupportedCondition, detail: "fixture"
        )
        let standardDescriptor = standardBlurDescriptor()
        let standardGraph = standardBlurGraph()
        let standardPlan = SceneAuthoredStandardBlurPlanner.plan(
            graph: standardGraph, descriptor: standardDescriptor
        )!
        let standardBlur = standardPlan.standardBlur!
        let standardRenderTargetPlan: SceneGraphRenderTargetPlan = {
            switch SceneGraphRenderTargetPlan.make(
                executionPlan: standardPlan,
                graph: standardPlan.renderGraph,
                inputWidth: 1920,
                inputHeight: 1080
            ) {
            case .success(let plan): return plan
            case .failure(let failure):
                fatalError("standard render target plan failed: \(failure.rawValue)")
            }
        }()
        let standardBackendMatched: Bool = {
            if case .standardBlur = standardPlan.backend { return true }
            return false
        }()
        let standardCatalog = SceneAuthoredEffectExecutionCatalog(
            descriptor: standardDescriptor, authoredPlans: [standardGraph]
        )
        let copyGraph = interleavedGraph(commandKind: .copy)
        let swapGraph = interleavedGraph(commandKind: .swap)
        let copyPlan = SceneAuthoredEffectExecutionPlanner.plan(
            graph: copyGraph, descriptor: descriptor
        )
        let swapPlan = SceneAuthoredEffectExecutionPlanner.plan(
            graph: swapGraph, descriptor: descriptor
        )
        let copyTargetPlan = copyPlan.flatMap { executionPlan -> SceneGraphRenderTargetPlan? in
            guard case .success(let plan) = SceneGraphRenderTargetPlan.make(
                executionPlan: executionPlan,
                graph: copyGraph,
                inputWidth: 1920,
                inputHeight: 1080
            ) else { return nil }
            return plan
        }
        let swapTargetPlan = swapPlan.flatMap { executionPlan -> SceneGraphRenderTargetPlan? in
            guard case .success(let plan) = SceneGraphRenderTargetPlan.make(
                executionPlan: executionPlan,
                graph: swapGraph,
                inputWidth: 1920,
                inputHeight: 1080
            ) else { return nil }
            return plan
        }
        let legacyComposeDescriptor = SceneRenderDescriptor(
            layers: [
                .init(
                    id: 10, parentID: nil, visible: true, contentKind: "text",
                    effects: [
                        instanceEffect(
                            layerID: 10, scale: 1.28, legacyCompose: true
                        ),
                    ]
                ),
            ],
            materialPasses: materials(verticalCombos: ["VERTICAL": 1])
        )
        let legacyComposePlan = SceneAuthoredEffectExecutionPlanner.plan(
            graph: graph(layerID: 10, legacyCompose: true),
            descriptor: legacyComposeDescriptor
        )
        let legacyComposeTargetPlan = legacyComposePlan.flatMap {
            executionPlan -> SceneGraphRenderTargetPlan? in
            guard case .success(let plan) = SceneGraphRenderTargetPlan.make(
                executionPlan: executionPlan,
                graph: executionPlan.renderGraph,
                inputWidth: 1920,
                inputHeight: 1080
            ) else { return nil }
            return plan
        }
        let legacyKernelRejected = SceneAuthoredEffectExecutionPlanner.plan(
            graph: graph(layerID: 10, legacyCompose: true),
            descriptor: SceneRenderDescriptor(
                layers: legacyComposeDescriptor.layers,
                materialPasses: materials(
                    verticalCombos: ["VERTICAL": 1, "KERNEL": 2]
                )
            )
        ) == nil
        let standardBadStateDescriptor = standardBlurDescriptor(
            materials: standardBlurMaterials(blending: "additive")
        )
        let standardBadShaderDescriptor = standardBlurDescriptor(
            materials: standardBlurMaterials(gaussianShader: "effects/unknown")
        )
        let standardKernelDescriptor = standardBlurDescriptor(
            effect: standardBlurInstanceEffect(gaussianCombos: ["KERNEL": 2])
        )
        let standardCompositeDescriptor = standardBlurDescriptor(
            effect: standardBlurInstanceEffect(combineCombos: ["COMPOSITE": 2])
        )
        func standardRejected(
            graph: Graph = standardGraph,
            descriptor: SceneRenderDescriptor = standardDescriptor
        ) -> Bool {
            SceneAuthoredStandardBlurPlanner.plan(graph: graph, descriptor: descriptor) == nil
        }
        func standardLegacyBlocked(
            graph: Graph,
            descriptor: SceneRenderDescriptor = standardDescriptor
        ) -> [Int] {
            SceneAuthoredEffectExecutionCatalog(
                descriptor: descriptor, authoredPlans: [graph]
            ).legacyGaussianBlurBlockedLayerIDs.sorted()
        }
        let sample2998757800 = sampleChain(
            layerID: 2998757800,
            stageNames: [
                "shake", "shake", "shake", "shake", "foliageSway", "xRay",
            ]
        )
        let sample3757555836 = sampleChain(
            layerID: 3757555836,
            stageNames: ["xRay", "waterFlow", "waterRipple", "waterFlow", "shake"]
        )
        let result: [String: Any] = [
            "planned": catalog.plansByLayerID.keys.sorted(),
            "hidden": catalog.hiddenEligibleLayerIDs,
            "legacyBlurBlocked": catalog.legacyGaussianBlurBlockedLayerIDs.sorted(),
            "scale": [preciseBlur.horizontalStep, preciseBlur.verticalStep],
            "nodes": visiblePlan.materialNodeCount,
            "targets": visiblePlan.logicalRenderTargetCount,
            "preciseGraphTargetCount": preciseRenderTargetPlan.logicalTargets.count,
            "preciseGraphTargetExtents": preciseRenderTargetPlan.logicalTargets.map {
                [$0.extent.width, $0.extent.height]
            },
            "preciseGraphIdentityMatched":
                preciseRenderTargetPlan.layerID == visiblePlan.renderGraph.layerID
                && preciseRenderTargetPlan.input == visiblePlan.renderGraph.effects[0].input
                && preciseRenderTargetPlan.output == visiblePlan.renderGraph.finalOutput
                && preciseRenderTargetPlan.logicalTargets.map(\.identity)
                    == visiblePlan.renderGraph.renderTargets.map(\.texture),
            "preciseBackendMatched": preciseBackendMatched
                && visiblePlan.standardBlur == nil
                && visiblePlan.requiresExactInputExtent,
            "copyInterleavedPlanned": copyPlan?.logicalRenderTargetCount == 2
                && copyTargetPlan?.commands.map(\.nodeIndex) == [1],
            "swapInterleavedPlanned": swapPlan?.logicalRenderTargetCount == 2
                && swapTargetPlan?.commands.map(\.nodeIndex) == [1]
                && swapTargetPlan?.logicalTargets.filter(\.lifetime.requiresHistorySeed).count == 1,
            "legacyComposePlanned": legacyComposePlan?.usesLegacyComposeNormalization == true
                && legacyComposeTargetPlan?.logicalTargets.map(\.extent)
                    == [.init(width: 1920, height: 1080)],
            "legacyKernelRejected": legacyKernelRejected,
            "lateCommandRejected": SceneAuthoredEffectExecutionPlanner.plan(
                graph: interleavedGraph(commandKind: .copy, commandAfterVertical: true),
                descriptor: descriptor
            ) == nil,
            "composedCommandRejected": SceneAuthoredEffectExecutionPlanner.plan(
                graph: interleavedGraph(
                    commandKind: .copy,
                    commandCompose: .bool(true)
                ),
                descriptor: descriptor
            ) == nil,
            "precedence": resolverPrecedence(),
            "extraEffectRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10, extraEffect: true), descriptor: descriptor) == nil,
            "blockerRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10, blockers: [blocker]), descriptor: descriptor) == nil,
            "uniqueRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10, unique: true), descriptor: descriptor) == nil,
            "bindingRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10, maskCombo: true), descriptor: descriptor) == nil,
            "stateRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10), descriptor: badStateDescriptor) == nil,
            "shaderRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10), descriptor: badShaderDescriptor) == nil,
            "duplicateComboRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10), descriptor: duplicateComboDescriptor) == nil,
            "dynamicScaleRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10), descriptor: dynamicScaleDescriptor) == nil,
            "outOfRangeScaleRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10), descriptor: outOfRangeScaleDescriptor) == nil,
            "duplicateScaleRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10), descriptor: duplicateScaleDescriptor) == nil,
            "threeComponentScaleRejected": SceneAuthoredEffectExecutionPlanner.plan(graph: graph(layerID: 10), descriptor: threeComponentScaleDescriptor) == nil,
            "badShaderLegacyBlocked": SceneAuthoredEffectExecutionCatalog(descriptor: badShaderDescriptor, authoredPlans: [graph(layerID: 10)]).legacyGaussianBlurBlockedLayerIDs.sorted(),
            "missingMaterialLegacyBlocked": SceneAuthoredEffectExecutionCatalog(descriptor: missingMaterialDescriptor, authoredPlans: [graph(layerID: 10)]).legacyGaussianBlurBlockedLayerIDs.sorted(),
            "standardPlanned": standardCatalog.plansByLayerID.keys.sorted(),
            "standardScale": [standardBlur.horizontalStep, standardBlur.verticalStep],
            "standardRTScale": standardBlur.renderTargetScale,
            "standardNodes": standardPlan.materialNodeCount,
            "standardTargets": standardPlan.logicalRenderTargetCount,
            "standardGraphTargetCount": standardRenderTargetPlan.logicalTargets.count,
            "standardGraphTargetExtents": standardRenderTargetPlan.logicalTargets.map {
                [$0.extent.width, $0.extent.height]
            },
            "standardGraphIdentityMatched":
                standardRenderTargetPlan.layerID == standardPlan.renderGraph.layerID
                && standardRenderTargetPlan.input == standardPlan.renderGraph.effects[0].input
                && standardRenderTargetPlan.output == standardPlan.renderGraph.finalOutput
                && standardRenderTargetPlan.logicalTargets.map(\.identity)
                    == standardPlan.renderGraph.renderTargets.map(\.texture),
            "standardBackendMatched": standardBackendMatched
                && standardPlan.gaussianBlur == nil
                && !standardPlan.requiresExactInputExtent,
            "standardLegacyBlocked": standardCatalog.legacyGaussianBlurBlockedLayerIDs.sorted(),
            "standardWrongExtentRejected": standardRejected(graph: standardBlurGraph(wrongExtent: true)),
            "standardWrongBindingRejected": standardRejected(graph: standardBlurGraph(wrongBinding: true)),
            "standardBadShaderRejected": standardRejected(descriptor: standardBadShaderDescriptor),
            "standardBadStateRejected": standardRejected(descriptor: standardBadStateDescriptor),
            "standardKernelRejected": standardRejected(descriptor: standardKernelDescriptor),
            "standardCompositeRejected": standardRejected(descriptor: standardCompositeDescriptor),
            "standardMixedEffectRejected": standardRejected(graph: standardBlurGraph(extraMixedEffect: true)),
            "standardWrongExtentLegacyBlocked": standardLegacyBlocked(graph: standardBlurGraph(wrongExtent: true)),
            "standardWrongBindingLegacyBlocked": standardLegacyBlocked(graph: standardBlurGraph(wrongBinding: true)),
            "standardBadShaderLegacyBlocked": standardLegacyBlocked(graph: standardGraph, descriptor: standardBadShaderDescriptor),
            "standardBadStateLegacyBlocked": standardLegacyBlocked(graph: standardGraph, descriptor: standardBadStateDescriptor),
            "standardKernelLegacyBlocked": standardLegacyBlocked(graph: standardGraph, descriptor: standardKernelDescriptor),
            "standardCompositeLegacyBlocked": standardLegacyBlocked(graph: standardGraph, descriptor: standardCompositeDescriptor),
            "standardMixedEffectLegacyBlocked": standardLegacyBlocked(graph: standardBlurGraph(extraMixedEffect: true)),
            "sample2998757800Stages": stageEvidence(
                SceneAuthoredEffectChainPlanner.plan(
                    graph: sample2998757800.graph,
                    descriptor: sample2998757800.descriptor,
                    shaderContracts: []
                )
            ),
            "sample3757555836Stages": stageEvidence(
                SceneAuthoredEffectChainPlanner.plan(
                    graph: sample3757555836.graph,
                    descriptor: sample3757555836.descriptor,
                    shaderContracts: []
                )
            ),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneAuthoredEffectExecutionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-authored-execution-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "scene-authored-execution"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness), "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_only_effectively_visible_complete_graph_is_planned(self) -> None:
        self.assertEqual(self.result["planned"], [10])
        self.assertEqual(self.result["hidden"], [20, 21])
        self.assertEqual(self.result["legacyBlurBlocked"], [30])
        self.assertEqual(self.result["nodes"], 2)
        self.assertEqual(self.result["targets"], 1)
        self.assertAlmostEqual(self.result["scale"][0], 1.28, places=5)
        self.assertAlmostEqual(self.result["scale"][1], 1.28, places=5)
        self.assertEqual(self.result["preciseGraphTargetCount"], 1)
        self.assertEqual(self.result["preciseGraphTargetExtents"], [[1279, 719]])
        self.assertTrue(self.result["preciseGraphIdentityMatched"])
        self.assertTrue(self.result["preciseBackendMatched"])

    def test_precise_blur_accepts_only_ordered_copy_swap_interleave(self) -> None:
        self.assertTrue(self.result["copyInterleavedPlanned"])
        self.assertTrue(self.result["swapInterleavedPlanned"])
        self.assertTrue(self.result["lateCommandRejected"])
        self.assertTrue(self.result["composedCommandRejected"])

    def test_precise_blur_accepts_exact_legacy_compose_profile(self) -> None:
        self.assertTrue(self.result["legacyComposePlanned"])
        self.assertTrue(self.result["legacyKernelRejected"])

    def test_default_standard_blur_graph_is_planned(self) -> None:
        self.assertEqual(self.result["standardPlanned"], [530])
        self.assertEqual(self.result["standardLegacyBlocked"], [])
        self.assertEqual(self.result["standardNodes"], 4)
        self.assertEqual(self.result["standardTargets"], 2)
        self.assertEqual(self.result["standardRTScale"], 4)
        self.assertAlmostEqual(self.result["standardScale"][0], 0.6, places=5)
        self.assertAlmostEqual(self.result["standardScale"][1], 0.6, places=5)
        self.assertEqual(self.result["standardGraphTargetCount"], 2)
        self.assertEqual(
            self.result["standardGraphTargetExtents"],
            [[480, 270], [480, 270]],
        )
        self.assertTrue(self.result["standardGraphIdentityMatched"])
        self.assertTrue(self.result["standardBackendMatched"])

    def test_texture_precedence_preserves_slots(self) -> None:
        self.assertEqual(
            self.result["precedence"],
            [
                ["material"],
                ["material", "userTexture", "instance", "explicitBinding"],
                ["material", "instance", "userTexture"],
                ["hole"], ["hole"], ["hole"], ["hole"], ["hole"],
            ],
        )

    def test_unsupported_graph_shapes_fail_closed(self) -> None:
        for key in (
            "extraEffectRejected",
            "blockerRejected",
            "uniqueRejected",
            "bindingRejected",
            "stateRejected",
            "shaderRejected",
            "duplicateComboRejected",
            "dynamicScaleRejected",
            "outOfRangeScaleRejected",
            "duplicateScaleRejected",
            "threeComponentScaleRejected",
        ):
            self.assertTrue(self.result[key], key)
        self.assertEqual(self.result["badShaderLegacyBlocked"], [10])
        self.assertEqual(self.result["missingMaterialLegacyBlocked"], [10])

    def test_unsupported_standard_blur_shapes_fail_closed(self) -> None:
        rejection_keys = (
            "standardWrongExtentRejected",
            "standardWrongBindingRejected",
            "standardBadShaderRejected",
            "standardBadStateRejected",
            "standardKernelRejected",
            "standardCompositeRejected",
            "standardMixedEffectRejected",
        )
        for key in rejection_keys:
            self.assertTrue(self.result[key], key)
        blocking_keys = (
            "standardWrongExtentLegacyBlocked",
            "standardWrongBindingLegacyBlocked",
            "standardBadShaderLegacyBlocked",
            "standardBadStateLegacyBlocked",
            "standardKernelLegacyBlocked",
            "standardCompositeLegacyBlocked",
            "standardMixedEffectLegacyBlocked",
        )
        for key in blocking_keys:
            self.assertEqual(self.result[key], [530], key)

    def assert_ordered_stage_fixture(self, sample_id: str) -> None:
        planner = CHAIN_PLANNER_SOURCE.read_text(encoding="utf-8") \
            + CHAIN_STAGE_RESOLUTION_SOURCE.read_text(encoding="utf-8")
        backend = CHAIN_BACKEND_SOURCE.read_text(encoding="utf-8")
        renderer = CHAIN_RENDERER_SOURCE.read_text(encoding="utf-8")
        compositor = COMPOSITOR_SOURCE.read_text(encoding="utf-8")
        fixture = SAMPLE_STAGE_FIXTURES[sample_id]

        self.assertEqual(
            [effect_index for effect_index, _ in fixture],
            list(range(len(fixture))),
            f"{sample_id} fixture must preserve authored effect indexes",
        )
        loop = planner.index("for (ordinal, effect) in graph.effects.enumerated()")
        append = planner.index("stages.append(stage)", loop)
        returned_chain = planner.index(
            "return SceneAuthoredEffectExecutionChain(",
            append,
        )
        self.assertLess(loop, append)
        self.assertLess(append, returned_chain)

        for stage in dict.fromkeys(stage for _, stage in fixture):
            planner_marker, backend_marker, renderer_marker = STAGE_SOURCE_MARKERS[stage]
            self.assertIn(
                planner_marker,
                planner,
                f"{sample_id} is missing the {stage} authored planner",
            )
            self.assertIn(
                backend_marker,
                backend,
                f"{sample_id} is missing the {stage} backend",
            )
            self.assertIn(
                renderer_marker,
                renderer,
                f"{sample_id} is missing the {stage} ordered renderer",
            )

        self.assertNotIn(
            "if let xRayPlan",
            compositor,
            f"{sample_id} must not append X-Ray after the ordered chain",
        )

    def test_2998757800_preserves_shake_foliage_then_xray_stage_order(self) -> None:
        self.assertEqual(
            SAMPLE_STAGE_FIXTURES["2998757800"],
            (
                (0, "shake"),
                (1, "shake"),
                (2, "shake"),
                (3, "shake"),
                (4, "foliageSway"),
                (5, "xRay"),
            ),
        )
        self.assertEqual(
            self.result["sample2998757800Stages"],
            [list(stage) for stage in SAMPLE_STAGE_FIXTURES["2998757800"]],
        )
        self.assert_ordered_stage_fixture("2998757800")

    def test_3757555836_preserves_xray_then_water_and_shake_stage_order(self) -> None:
        self.assertEqual(
            SAMPLE_STAGE_FIXTURES["3757555836"],
            (
                (0, "xRay"),
                (1, "waterFlow"),
                (2, "waterRipple"),
                (3, "waterFlow"),
                (4, "shake"),
            ),
        )
        self.assertEqual(
            self.result["sample3757555836Stages"],
            [list(stage) for stage in SAMPLE_STAGE_FIXTURES["3757555836"]],
        )
        self.assert_ordered_stage_fixture("3757555836")

    def test_later_authored_stages_retain_required_resources(self) -> None:
        source = DRAW_REQUEST_SOURCE.read_text(encoding="utf-8")
        start = source.index(
            "var authoredEffectResourcesOnly: SceneImageLayerMasks"
        )
        end = source.index("static let empty", start)
        resources_only = source[start:end]
        for resource in (
            "water",
            "foliage",
            "waterRippleNormal",
            "blendEffects",
            "xRay",
        ):
            self.assertIn(f"{resource}: {resource}", resources_only)
            self.assertNotIn(f"{resource}: nil", resources_only)

        loader = EFFECT_TEXTURE_LOADER_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "pass.textureSlots.count == 2 || pass.textureSlots.count == 3",
            loader,
        )

    def test_iris_inline_suffix_is_terminal_strict_and_keeps_exact_prefix(self) -> None:
        suffix = IRIS_SUFFIX_SOURCE.read_text(encoding="utf-8")
        planner = IRIS_SUFFIX_PLANNER_SOURCE.read_text(encoding="utf-8")
        compositor = COMPOSITOR_SOURCE.read_text(encoding="utf-8")

        for marker in (
            "!plannedStages.isEmpty",
            "unsupportedOrdinal == graph.effects.count - 1",
            "plannedStages.count == unsupportedOrdinal",
            "inputRole: .priorEffectOutput",
            "irisInlineSuffix: suffix",
        ):
            self.assertIn(marker, suffix)
        for marker in (
            "graph.blockers.isEmpty",
            "graph.effects.count == 1",
            "graph.nodes.count == 1",
            "graph.renderTargets.isEmpty",
            'definition.replacementKey == "iris"',
            "SceneIrisShaderProfile.resolve(shaderContracts)",
        ):
            self.assertIn(marker, planner)
        self.assertIn("irisSuffix?.inputs ?? .neutral", compositor)
        self.assertIn("irisSuffix == nil ? .empty : masks", compositor)


if __name__ == "__main__":
    unittest.main()
