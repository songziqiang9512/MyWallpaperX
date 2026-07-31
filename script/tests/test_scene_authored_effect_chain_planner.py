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
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan+Extent.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredLocalContrastPlanner.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionChain.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectChainPlanner+StageResolution.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectXRayPrefix.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionCatalog+Reporting.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionPlan+Backend.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredPreciseBlurPlanner+Topology.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredStandardBlurPlanner.swift",
]


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
struct SceneAuthoredShaderExecutionPlan {
    enum Profile {
        case genericFramebuffer
        case scroll
    }

    let offscreenSize: CGSize? = nil
    let profile: Profile = .genericFramebuffer

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
        graph.effects.first?.definitionPath.lowercased()
            == "effects/simple/effect.json" && inputRole == .layerSource
            ? SceneWorkshopAudioBarsExecutionPlan(profile: .simple)
            : nil
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
        nil
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
        nil
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
        nil
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
        nil
    }
}

struct SceneDepthParallaxExecutionPlan {}

enum SceneAuthoredDepthParallaxPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneDepthParallaxExecutionPlan? {
        nil
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
        nil
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
        graph.effects.first?.definitionPath.lowercased()
            == "effects/fisheye/effect.json" && inputRole == .priorEffectOutput
            ? SceneFisheyeZeroDistortionPlan()
            : nil
    }
}

enum SceneAuthoredTintPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneTintExecutionPlan? {
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
        nil
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
        let alphaWriting: String? = nil
    }

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
}

enum SceneLayerVisibility {
    static func visibleLayerIDs(in descriptor: SceneRenderDescriptor) -> Set<Int> {
        let layers = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        return Set(descriptor.layers.compactMap { layer in
            var current: SceneRenderDescriptor.Layer? = layer
            var visited = Set<Int>()
            while let candidate = current {
                guard candidate.visible != false,
                      visited.insert(candidate.id).inserted else {
                    return nil
                }
                current = candidate.parentID.flatMap { layers[$0] }
            }
            return layer.id
        })
    }
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static let layerID = 42

    static func texture(
        _ kind: Graph.TextureKind,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func effectDescriptor(
        index: Int,
        verticalCombos: [String: Int] = ["VERTICAL": 1, "ENABLEMASK": 1]
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let scale = SceneDocument.ShaderValue(components: [0.75, 0.75])
        return .init(
            id: "42#effect#\(index)",
            visible: true,
            passes: [
                .init(
                    passIndex: 0,
                    textureSlots: [],
                    userTextureInputs: [],
                    combos: [:],
                    constantShaderValues: ["scale": scale]
                ),
                .init(
                    passIndex: 1,
                    textureSlots: [],
                    userTextureInputs: [],
                    combos: verticalCombos,
                    constantShaderValues: ["scale": scale]
                ),
            ]
        )
    }

    static func materials() -> [SceneRenderDescriptor.MaterialPassDescriptor] {
        func material(
            id: String,
            path: String,
            combos: [String: Int]
        ) -> SceneRenderDescriptor.MaterialPassDescriptor {
            .init(
                id: id,
                materialPath: path,
                shaderPath: "effects/blur_precise_gaussian",
                textureSlots: [],
                userTextureInputs: [],
                combos: combos,
                constantShaderValues: [:],
                blending: "normal",
                depthTest: "disabled",
                depthWrite: "disabled",
                cullMode: "nocull"
            )
        }
        return [
            material(id: "materials/precise_x.json#0", path: "materials/precise_x.json", combos: [:]),
            material(
                id: "materials/precise_y.json#0",
                path: "materials/precise_y.json",
                combos: ["VERTICAL": 1, "ENABLEMASK": 1]
            ),
        ]
    }

    static func descriptor(
        visible: Bool = true,
        unsupportedSecond: Bool = false
    ) -> SceneRenderDescriptor {
        let secondCombos = unsupportedSecond
            ? ["VERTICAL": 2, "ENABLEMASK": 1]
            : ["VERTICAL": 1, "ENABLEMASK": 1]
        return .init(
            layers: [
                .init(
                    id: layerID,
                    parentID: nil,
                    visible: visible,
                    contentKind: "text",
                    effects: [
                        effectDescriptor(index: 0),
                        effectDescriptor(index: 1, verticalCombos: secondCombos),
                    ]
                ),
            ],
            materialPasses: materials()
        )
    }

    static func chainGraph(
        discontinuousInput: Bool = false,
        duplicateNodeIndex: Bool = false,
        extraTarget: Bool = false,
        secondDefinitionPath: String = "effects/workshop/blurprecise/effect.json",
        hasBlocker: Bool = false
    ) -> Graph {
        let firstKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "42#effect#0"
        )
        let secondKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 1,
            descriptorID: "42#effect#1"
        )
        let source = texture(.layerSource)
        let firstOutput = texture(.effectOutput, effect: firstKey)
        let secondInput = discontinuousInput ? source : firstOutput
        let secondOutput = texture(.effectOutput, effect: secondKey)
        let firstTarget = texture(.framebuffer, effect: firstKey, name: "first")
        let secondTarget = texture(.framebuffer, effect: secondKey, name: "second")
        let extra = texture(.framebuffer, effect: secondKey, name: "extra")
        let secondFirstNodeIndex = duplicateNodeIndex ? 1 : 2

        func node(
            index: Int,
            effect: Graph.EffectKey,
            ordinal: Int,
            target: Graph.TextureIdentity,
            bindings: [Graph.Binding]
        ) -> Graph.Node {
            let material = ordinal == 0 ? "materials/precise_x.json" : "materials/precise_y.json"
            return .init(
                nodeIndex: index,
                effect: effect,
                definitionPassIndex: ordinal,
                materialOrdinal: ordinal,
                instancePassIndex: ordinal,
                kind: .material,
                materialPath: material,
                materialPassID: "\(material)#0",
                target: target,
                bindings: bindings,
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            )
        }

        let nodes = [
            node(index: 0, effect: firstKey, ordinal: 0, target: firstTarget, bindings: []),
            node(
                index: 1,
                effect: firstKey,
                ordinal: 1,
                target: firstOutput,
                bindings: [
                    .init(slot: 0, authoredName: "first", texture: firstTarget, conditions: nil),
                    .init(slot: 1, authoredName: "previous", texture: source, conditions: nil),
                ]
            ),
            node(
                index: secondFirstNodeIndex,
                effect: secondKey,
                ordinal: 0,
                target: secondTarget,
                bindings: []
            ),
            node(
                index: 3,
                effect: secondKey,
                ordinal: 1,
                target: secondOutput,
                bindings: [
                    .init(slot: 0, authoredName: "second", texture: secondTarget, conditions: nil),
                    .init(slot: 1, authoredName: "previous", texture: secondInput, conditions: nil),
                ]
            ),
        ]
        let effects = [
            Graph.Effect(
                key: firstKey,
                definitionPath: "effects/workshop/blurprecise/effect.json",
                input: source,
                output: firstOutput,
                nodeIndices: [0, 1]
            ),
            Graph.Effect(
                key: secondKey,
                definitionPath: secondDefinitionPath,
                input: secondInput,
                output: secondOutput,
                nodeIndices: [secondFirstNodeIndex, 3]
            ),
        ]
        var targets = [firstTarget, secondTarget].map {
            Graph.RenderTarget(
                texture: $0,
                extent: .init(kind: .input, first: nil, second: nil),
                format: "rgba_backbuffer",
                declaredUnique: false,
                clear: nil,
                uvs: nil,
                conditions: nil
            )
        }
        if extraTarget {
            targets.append(.init(
                texture: extra,
                extent: .init(kind: .input, first: nil, second: nil),
                format: "rgba_backbuffer",
                declaredUnique: false,
                clear: nil,
                uvs: nil,
                conditions: nil
            ))
        }
        let blockers: [Graph.Blocker] = hasBlocker ? [
            .init(
                effect: secondKey,
                definitionPassIndex: 1,
                reason: .unsupportedCondition,
                detail: "synthetic blocker"
            ),
        ] : []
        return .init(
            layerID: layerID,
            effects: effects,
            renderTargets: targets,
            nodes: nodes,
            finalOutput: secondOutput,
            blockers: blockers
        )
    }

    static func simpleFisheyeGraph(
        fisheyePath: String = "effects/fisheye/effect.json"
    ) -> Graph {
        let firstKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "42#effect#0"
        )
        let secondKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 1,
            descriptorID: "42#effect#1"
        )
        let source = texture(.layerSource)
        let firstOutput = texture(.effectOutput, effect: firstKey)
        let secondOutput = texture(.effectOutput, effect: secondKey)
        func node(
            index: Int,
            effect: Graph.EffectKey,
            target: Graph.TextureIdentity
        ) -> Graph.Node {
            .init(
                nodeIndex: index,
                effect: effect,
                definitionPassIndex: 0,
                materialOrdinal: 0,
                instancePassIndex: 0,
                kind: .material,
                materialPath: "materials/stub.json",
                materialPassID: "materials/stub.json#0",
                target: target,
                bindings: [],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            )
        }
        return .init(
            layerID: layerID,
            effects: [
                .init(
                    key: firstKey,
                    definitionPath: "effects/simple/effect.json",
                    input: source,
                    output: firstOutput,
                    nodeIndices: [0]
                ),
                .init(
                    key: secondKey,
                    definitionPath: fisheyePath,
                    input: firstOutput,
                    output: secondOutput,
                    nodeIndices: [1]
                ),
            ],
            renderTargets: [],
            nodes: [
                node(index: 0, effect: firstKey, target: firstOutput),
                node(index: 1, effect: secondKey, target: secondOutput),
            ],
            finalOutput: secondOutput,
            blockers: []
        )
    }

    static func roleName(_ role: SceneAuthoredEffectInputRole) -> String {
        switch role {
        case .layerSource: "layerSource"
        case .priorEffectOutput: "priorEffectOutput"
        }
    }

    static func catalogState(
        descriptor: SceneRenderDescriptor,
        graphs: [Graph]
    ) -> [String: Any] {
        let catalog = SceneAuthoredEffectExecutionCatalog(
            descriptor: descriptor,
            authoredPlans: graphs
        )
        return [
            "chainLayers": catalog.chainsByLayerID.keys.sorted(),
            "singleStageLayers": catalog.plansByLayerID.keys.sorted(),
            "hidden": catalog.hiddenEligibleLayerIDs,
            "legacyBlocked": catalog.legacyGaussianBlurBlockedLayerIDs.sorted(),
        ]
    }

    static func rejected(
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> Bool {
        SceneAuthoredEffectChainPlanner.plan(
            graph: graph,
            descriptor: descriptor,
            shaderContracts: []
        ) == nil
    }

    static func main() throws {
        let validDescriptor = descriptor()
        let validGraph = chainGraph()
        let chain = SceneAuthoredEffectChainPlanner.plan(
            graph: validGraph,
            descriptor: validDescriptor,
            shaderContracts: []
        )!
        let identityGraph = Graph(
            layerID: chain.stages[0].renderGraph.layerID,
            effects: chain.stages[0].renderGraph.effects,
            renderTargets: [],
            nodes: chain.stages[0].renderGraph.nodes,
            finalOutput: chain.stages[0].renderGraph.finalOutput,
            blockers: []
        )
        let identityStage = SceneAuthoredEffectExecutionPlan(
            layerID: identityGraph.layerID,
            renderGraph: identityGraph,
            backend: .tint(SceneTintExecutionPlan()),
            materialNodeCount: identityGraph.nodes.count,
            logicalRenderTargetCount: 0
        )
        func budgetStage(
            _ extent: Graph.TargetExtent,
            logicalTargetCount: Int = 1
        ) -> SceneAuthoredEffectExecutionPlan {
            let key = Graph.EffectKey(
                layerID: layerID,
                effectIndex: 0,
                descriptorID: "42#budget"
            )
            let target = texture(.framebuffer, effect: key, name: "budget")
            let graph = Graph(
                layerID: layerID,
                effects: [],
                renderTargets: [.init(
                    texture: target,
                    extent: extent,
                    format: "rgba_backbuffer",
                    declaredUnique: false,
                    clear: nil,
                    uvs: nil,
                    conditions: nil
                )],
                nodes: [],
                finalOutput: texture(.effectOutput, effect: key),
                blockers: []
            )
            return SceneAuthoredEffectExecutionPlan(
                layerID: layerID,
                renderGraph: graph,
                backend: .tint(SceneTintExecutionPlan()),
                materialNodeCount: 0,
                logicalRenderTargetCount: logicalTargetCount
            )
        }
        let absoluteExpanded = budgetStage(.init(
            width: 4096,
            height: 4096,
            fit: nil,
            scale: nil
        ))
        let singleAxisExpanded = budgetStage(.init(
            width: 8192,
            height: nil,
            fit: nil,
            scale: nil
        ))
        let scaleExpanded = budgetStage(.init(
            width: nil,
            height: nil,
            fit: nil,
            scale: 0.5
        ))
        let composedReduced = budgetStage(.init(
            width: 4096,
            height: nil,
            fit: 1024,
            scale: 2
        ))
        let invalidExtents = [
            Graph.TargetExtent(width: 0, height: nil, fit: nil, scale: nil),
            Graph.TargetExtent(width: nil, height: nil, fit: nil, scale: 0),
            Graph.TargetExtent(width: .nan, height: nil, fit: nil, scale: nil),
            Graph.TargetExtent(width: nil, height: .infinity, fit: nil, scale: nil),
        ]
        let catalog = SceneAuthoredEffectExecutionCatalog(
            descriptor: validDescriptor,
            authoredPlans: [validGraph]
        )
        let firstOutput = validGraph.effects[0].output

        let unsupportedDescriptor = descriptor(unsupportedSecond: true)
        let mixedGraph = chainGraph(
            secondDefinitionPath: "effects/water/effect.json"
        )
        let failureCatalogs: [String: [String: Any]] = [
            "unsupportedSecond": catalogState(
                descriptor: unsupportedDescriptor,
                graphs: [validGraph]
            ),
            "blocker": catalogState(
                descriptor: validDescriptor,
                graphs: [chainGraph(hasBlocker: true)]
            ),
            "discontinuousInput": catalogState(
                descriptor: validDescriptor,
                graphs: [chainGraph(discontinuousInput: true)]
            ),
            "duplicateNode": catalogState(
                descriptor: validDescriptor,
                graphs: [chainGraph(duplicateNodeIndex: true)]
            ),
            "extraTarget": catalogState(
                descriptor: validDescriptor,
                graphs: [chainGraph(extraTarget: true)]
            ),
            "mixedUnsupported": catalogState(
                descriptor: unsupportedDescriptor,
                graphs: [mixedGraph]
            ),
            "multipleCandidates": catalogState(
                descriptor: validDescriptor,
                graphs: [validGraph, validGraph]
            ),
        ]
        let hiddenCatalog = SceneAuthoredEffectExecutionCatalog(
            descriptor: descriptor(visible: false),
            authoredPlans: [validGraph]
        )
        let simpleFisheye = SceneAuthoredEffectChainPlanner.plan(
            graph: simpleFisheyeGraph(),
            descriptor: validDescriptor,
            shaderContracts: []
        )!
        let simpleFisheyeCatalog = SceneAuthoredEffectExecutionCatalog(
            descriptor: validDescriptor,
            authoredPlans: [simpleFisheyeGraph()]
        )

        let result: [String: Any] = [
            "success": [
                "effectOrder": chain.stages.map { $0.renderGraph.effects[0].key.effectIndex },
                "nodeIndices": chain.stages.map { $0.renderGraph.nodes.map(\.nodeIndex) },
                "effectNodeIndices": chain.stages.map { $0.renderGraph.effects[0].nodeIndices },
                "inputRoles": chain.stages.map { roleName($0.inputRole) },
                "secondInputIsPriorOutput": chain.stages[1].renderGraph.effects[0].input == firstOutput,
                "secondPreviousBindingIsPriorOutput":
                    chain.stages[1].renderGraph.nodes[1].bindings
                        .first(where: { $0.slot == 1 })?.texture == firstOutput,
                "stageCount": chain.stages.count,
                "materialNodeCount": chain.materialNodeCount,
                "logicalTargetCount": chain.logicalRenderTargetCount,
                "localContrastCount": chain.localContrastCount,
                "liveTargetCount": chain.liveConsumerTargets.count,
                "bothPrecise": chain.stages.allSatisfy { $0.gaussianBlur != nil },
                "fitsDefaultTextureBudget":
                    SceneAuthoredEffectChainPlanner.fitsDefaultTextureBudget(chain.stages),
                "mixedSevenUnitChainFitsBudget":
                    SceneAuthoredEffectChainPlanner.fitsDefaultTextureBudget(
                        [identityStage, chain.stages[0], identityStage]
                    ),
                "oversizedChainRejected":
                    !SceneAuthoredEffectChainPlanner.fitsDefaultTextureBudget(
                        chain.stages + [chain.stages[0]]
                    ),
                "absoluteBoundaryFits":
                    SceneAuthoredEffectChainPlanner.fitsDefaultTextureBudget(
                        [identityStage, absoluteExpanded]
                    ),
                "absoluteOnePastRejected":
                    !SceneAuthoredEffectChainPlanner.fitsDefaultTextureBudget(
                        [identityStage, absoluteExpanded, identityStage]
                    ),
                "singleAxisExpandedRejected":
                    !SceneAuthoredEffectChainPlanner.fitsDefaultTextureBudget(
                        [identityStage, singleAxisExpanded, identityStage]
                    ),
                "scaleBelowOneExpandedRejected":
                    !SceneAuthoredEffectChainPlanner.fitsDefaultTextureBudget(
                        [identityStage, scaleExpanded, identityStage]
                    ),
                "composedReducedFits":
                    SceneAuthoredEffectChainPlanner.fitsDefaultTextureBudget(
                        [identityStage, composedReduced, identityStage]
                    ),
                "invalidExtentsRejected": invalidExtents.allSatisfy {
                    !SceneAuthoredEffectChainPlanner.fitsDefaultTextureBudget([
                        budgetStage($0)
                    ])
                        && !SceneAuthoredEffectChainPlanner.fitsDefaultTextureBudget([
                            budgetStage($0, logicalTargetCount: 0)
                        ])
                },
            ],
            "catalog": [
                "chainLayers": catalog.chainsByLayerID.keys.sorted(),
                "singleStageLayers": catalog.plansByLayerID.keys.sorted(),
                "legacyBlocked": catalog.legacyGaussianBlurBlockedLayerIDs.sorted(),
                "liveTargetCount": catalog.liveConsumerTargets.count,
                "executedPropertyKeys": catalog.executedUserPropertyKeys.sorted(),
                "reportLines": catalog.reportLines,
            ],
            "directRejections": [
                "unsupportedSecond": rejected(
                    graph: validGraph,
                    descriptor: unsupportedDescriptor
                ),
                "blocker": rejected(
                    graph: chainGraph(hasBlocker: true),
                    descriptor: validDescriptor
                ),
                "discontinuousInput": rejected(
                    graph: chainGraph(discontinuousInput: true),
                    descriptor: validDescriptor
                ),
                "duplicateNode": rejected(
                    graph: chainGraph(duplicateNodeIndex: true),
                    descriptor: validDescriptor
                ),
                "extraTarget": rejected(
                    graph: chainGraph(extraTarget: true),
                    descriptor: validDescriptor
                ),
                "mixedUnsupported": rejected(
                    graph: mixedGraph,
                    descriptor: unsupportedDescriptor
                ),
            ],
            "failureCatalogs": failureCatalogs,
            "hidden": [
                "chainLayers": hiddenCatalog.chainsByLayerID.keys.sorted(),
                "singleStageLayers": hiddenCatalog.plansByLayerID.keys.sorted(),
                "eligible": hiddenCatalog.hiddenEligibleLayerIDs,
                "legacyBlocked": hiddenCatalog.legacyGaussianBlurBlockedLayerIDs.sorted(),
            ],
            "simpleFisheye": [
                "stageCount": simpleFisheye.stages.count,
                "audioBarsCount": simpleFisheye.workshopAudioBarsCount,
                "fisheyeCount": simpleFisheye.fisheyeZeroDistortionCount,
                "transformCount": simpleFisheye.transformCount,
                "inputRoles": simpleFisheye.stages.map { roleName($0.inputRole) },
                "utilityCapture": simpleFisheye.stages.allSatisfy(
                    \.supportsUtilityCapture
                ),
                "reportLines": simpleFisheyeCatalog.reportLines,
                "variantRejected": rejected(
                    graph: simpleFisheyeGraph(
                        fisheyePath: "effects/fisheye_variant/effect.json"
                    ),
                    descriptor: validDescriptor
                ),
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneAuthoredEffectChainPlannerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-authored-effect-chain-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "scene-authored-effect-chain"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
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

    def test_two_precise_stages_preserve_authored_chain_identity(self) -> None:
        success = self.result["success"]
        self.assertEqual(success["effectOrder"], [0, 1])
        self.assertEqual(success["nodeIndices"], [[0, 1], [2, 3]])
        self.assertEqual(success["effectNodeIndices"], [[0, 1], [2, 3]])
        self.assertEqual(success["inputRoles"], ["layerSource", "priorEffectOutput"])
        self.assertTrue(success["secondInputIsPriorOutput"])
        self.assertTrue(success["secondPreviousBindingIsPriorOutput"])
        self.assertTrue(success["bothPrecise"])
        self.assertEqual(success["stageCount"], 2)
        self.assertEqual(success["materialNodeCount"], 4)
        self.assertEqual(success["logicalTargetCount"], 2)
        self.assertEqual(success["localContrastCount"], 0)
        self.assertEqual(success["liveTargetCount"], 0)
        self.assertTrue(success["fitsDefaultTextureBudget"])
        self.assertTrue(success["mixedSevenUnitChainFitsBudget"])
        self.assertTrue(success["oversizedChainRejected"])
        self.assertTrue(success["absoluteBoundaryFits"])
        self.assertTrue(success["absoluteOnePastRejected"])
        self.assertTrue(success["singleAxisExpandedRejected"])
        self.assertTrue(success["scaleBelowOneExpandedRejected"])
        self.assertTrue(success["composedReducedFits"])
        self.assertTrue(success["invalidExtentsRejected"])

    def test_catalog_reports_chain_counts_without_exposing_single_stage_plan(self) -> None:
        catalog = self.result["catalog"]
        self.assertEqual(catalog["chainLayers"], [42])
        self.assertEqual(catalog["singleStageLayers"], [])
        self.assertEqual(catalog["legacyBlocked"], [])
        self.assertEqual(catalog["liveTargetCount"], 0)
        self.assertEqual(catalog["executedPropertyKeys"], [])
        for line in (
            "authoredEffectGraphPlannedCount: 1",
            "authoredEffectGraphMaterialNodeCount: 4",
            "authoredEffectGraphLogicalRTCount: 2",
            "authoredEffectGraphChainCount: 1",
            "authoredEffectGraphStageCount: 2",
            "authoredEffectGraphLocalContrastCount: 0",
            "authoredEffectGraphWorkshopAudioBarsCount: 0",
            "authoredEffectGraphWorkshopGradientCount: 0",
            "authoredEffectGraphWorkshopAudioHueShiftCount: 0",
            "authoredEffectGraphWorkshopShadowCount: 0",
            "authoredEffectGraphSpinCount: 0",
            "authoredEffectGraphProceduralNoiseCount: 0",
            "authoredEffectGraphLightShaftsCount: 0",
            "authoredEffectGraphBlendCount: 0",
        ):
            self.assertIn(line, catalog["reportLines"])

    def test_invalid_second_stage_or_outer_graph_fails_the_whole_chain(self) -> None:
        for name, rejected in self.result["directRejections"].items():
            self.assertTrue(rejected, name)

        for name, catalog in self.result["failureCatalogs"].items():
            self.assertEqual(catalog["chainLayers"], [], name)
            self.assertEqual(catalog["singleStageLayers"], [], name)
            self.assertEqual(catalog["hidden"], [], name)
            self.assertEqual(catalog["legacyBlocked"], [42], name)

    def test_hidden_complete_chain_is_not_runtime_eligible(self) -> None:
        hidden = self.result["hidden"]
        self.assertEqual(hidden["chainLayers"], [])
        self.assertEqual(hidden["singleStageLayers"], [])
        self.assertEqual(hidden["eligible"], [42])
        self.assertEqual(hidden["legacyBlocked"], [])

    def test_simple_audio_bars_then_strict_fisheye_is_an_ordered_public_chain(self) -> None:
        chain = self.result["simpleFisheye"]
        self.assertEqual(chain["stageCount"], 2)
        self.assertEqual(chain["audioBarsCount"], 1)
        self.assertEqual(chain["fisheyeCount"], 1)
        self.assertEqual(chain["transformCount"], 0)
        self.assertEqual(
            chain["inputRoles"],
            ["layerSource", "priorEffectOutput"],
        )
        self.assertTrue(chain["utilityCapture"])
        self.assertTrue(chain["variantRejected"])
        self.assertIn(
            "authoredEffectGraphFisheyeZeroDistortionCount: 1",
            chain["reportLines"],
        )
        self.assertIn(
            "authoredEffectGraphTransformCount: 0",
            chain["reportLines"],
        )


if __name__ == "__main__":
    unittest.main()
