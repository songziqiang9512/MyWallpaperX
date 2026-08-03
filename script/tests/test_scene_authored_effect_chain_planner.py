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
    SOURCE_ROOT / "RenderGraph/SceneShaderSourceGraph.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectStageCompileModel.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan+Clear.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan+Extent.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredLocalContrastPlanner.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectChainAdmission.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectStageGraphAdmission.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionChain.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectChainPlanner+StageResolution.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectStageCompiler.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectXRayPrefix.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectStageProgram.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectStageAdmission.swift",
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

enum SceneGaussianBlurKernel: Int {
    case large = 0
    case medium = 1
    case small = 2
}

struct SceneGaussianBlurPlan {
    let horizontalStep: Float
    let verticalStep: Float
    let sampleResolutionScale: Float
    let isPrecise: Bool
    let kernel: SceneGaussianBlurKernel
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
struct SceneColorGradingExecutionPlan: Sendable {}
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
struct SceneProceduralNoiseExecutionPlan: Sendable {
    enum Variant: Sendable {
        case legacyWorleyColor
    }

    let variant: Variant
    let dependencySlotIndex: Int?
}
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
    nonisolated(unsafe) static var compiledEffectIndices: [Int] = []

    static func compile(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageBackendCompileResult<SceneAuthoredShaderExecutionPlan> {
        if let effectIndex = input.stageGraph.effects.first?.key.effectIndex {
            compiledEffectIndices.append(effectIndex)
        }
        if input.stageGraph.effects.first?.definitionPath.lowercased()
            == "effects/generic/effect.json" {
            return .accepted(SceneAuthoredShaderExecutionPlan())
        }
        return .notApplicable
    }

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

enum SceneAuthoredColorGradingPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneColorGradingExecutionPlan? {
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
    nonisolated(unsafe) static var callCount = 0

    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWorkshopAudioBarsExecutionPlan? {
        callCount += 1
        return graph.effects.first?.definitionPath.lowercased()
            == "effects/overlap/effect.json" && inputRole == .layerSource
            ? SceneWorkshopAudioBarsExecutionPlan(profile: .enhancedSegmented(shape: 7))
            : nil
    }
}

enum SceneAuthoredWorkshopSimpleAudioBarsPlanner {
    nonisolated(unsafe) static var callCount = 0

    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWorkshopAudioBarsExecutionPlan? {
        callCount += 1
        let path = graph.effects.first?.definitionPath.lowercased()
        return (path == "effects/simple/effect.json"
            || path == "effects/overlap/effect.json")
            && inputRole == .layerSource
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

struct SceneWaterCausticsExecutionPlan {}

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

enum SceneAuthoredWaterCausticsPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole
    ) -> SceneWaterCausticsExecutionPlan? {
        nil
    }
}

struct SceneCursorRippleExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}
struct SceneIrisInlineSuffixPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}

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
        graph.effects.count == 1
            && graph.effects.first?.definitionPath == "effects/xray/effect.json"
            ? SceneXRayExecutionPlan()
            : nil
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
    var liveMultiplyTarget: SceneDynamicTarget? { nil }
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
        let file: String
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
        var userShaderValues: [String: String] { [:] }
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String? = nil
    }

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
}

nonisolated protocol HarnessDedicatedPlanner {
    associatedtype DedicatedPlan

    static var compilerBackend: SceneEffectStageCompilerBackend { get }

    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole
    ) -> DedicatedPlan?

    static func isCandidate(_ input: SceneEffectStageCompileInput) -> Bool
}

extension HarnessDedicatedPlanner {
    nonisolated static func isCandidate(
        _ input: SceneEffectStageCompileInput
    ) -> Bool {
        false
    }

    nonisolated static func compile(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageBackendCompileResult<DedicatedPlan> {
        SceneEffectStageDedicatedCompilerAdapter.compile(
            backend: compilerBackend,
            candidate: { isCandidate(input) },
            plan: {
                plan(
                    graph: input.stageGraph,
                    descriptor: input.descriptor,
                    shaderContracts: input.shaderContracts,
                    inputRole: input.inputRole
                )
            }
        )
    }
}

extension SceneAuthoredEffectExecutionPlanner {
    nonisolated static func compile(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageBackendCompileResult<SceneAuthoredEffectExecutionPlan> {
        SceneEffectStageDedicatedCompilerAdapter.compile(
            backend: .preciseGaussian,
            candidate: {
                containsAuthoredPreciseBlurCandidate(
                    graph: input.stageGraph,
                    descriptor: input.descriptor
                )
            },
            plan: {
                plan(
                    graph: input.stageGraph,
                    descriptor: input.descriptor,
                    inputRole: input.inputRole
                )
            }
        )
    }
}

extension SceneAuthoredStandardBlurPlanner {
    nonisolated static func compile(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageBackendCompileResult<SceneAuthoredEffectExecutionPlan> {
        SceneEffectStageDedicatedCompilerAdapter.compile(
            backend: .standardBlur,
            candidate: { containsCandidate(graph: input.stageGraph) },
            plan: {
                plan(
                    graph: input.stageGraph,
                    descriptor: input.descriptor,
                    inputRole: input.inputRole
                )
            }
        )
    }
}

extension SceneAuthoredLocalContrastPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneLocalContrastPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .localContrast }
}
extension SceneAuthoredOpacityPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneOpacityExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .opacity }
}
extension SceneAuthoredColorKeyPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneColorKeyExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .colorKey }
}
extension SceneAuthoredColorGradingPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneColorGradingExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .colorGrading }
}
extension SceneAuthoredWorkshopShiftHuePlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneWorkshopShiftHueExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .workshopShiftHue }
}
extension SceneAuthoredWorkshopAudioBarsPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneWorkshopAudioBarsExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .workshopAudioBars }
}
extension SceneAuthoredWorkshopSimpleAudioBarsPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneWorkshopAudioBarsExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend {
        .workshopSimpleAudioBars
    }
}
extension SceneAuthoredWorkshopGradientPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneWorkshopGradientExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .workshopGradient }
}
extension SceneAuthoredWorkshopAudioHueShiftPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneWorkshopAudioHueShiftExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend {
        .workshopAudioHueShift
    }
}
extension SceneAuthoredWorkshopShadowPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneWorkshopShadowExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .workshopShadow }
}
extension SceneAuthoredSpinPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneSpinExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .spin }
}
extension SceneAuthoredProceduralNoisePlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneProceduralNoiseExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .proceduralNoise }
}
extension SceneAuthoredFilmGrainPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneFilmGrainExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .filmGrain }
}
extension SceneAuthoredLightShaftsPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneLightShaftsExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .lightShafts }
}
extension SceneAuthoredShakePlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneShakeExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .shake }
}
extension SceneAuthoredWaterFlowPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneWaterFlowExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .waterFlow }

    nonisolated static func isCandidate(_ input: SceneEffectStageCompileInput) -> Bool {
        input.stageGraph.effects.contains {
            $0.definitionPath.lowercased().hasPrefix("effects/waterflow/")
        }
    }
}
extension SceneAuthoredWaterWavesPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneWaterWavesExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .waterWaves }
}
extension SceneAuthoredWaterCausticsPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneWaterCausticsExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .waterCaustics }
}
extension SceneAuthoredCursorRipplePlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneCursorRippleExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .cursorRipple }
}
extension SceneAuthoredFoliageSwayPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneFoliageSwayExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .foliageSway }
}
extension SceneAuthoredWaterRipplePlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneWaterRippleExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .waterRipple }
}
extension SceneAuthoredDepthParallaxPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneDepthParallaxExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .depthParallax }
}
extension SceneAuthoredXRayPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneXRayExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .xRay }
}
extension SceneAuthoredClippingMaskPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneClippingMaskExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .clippingMask }
}
extension SceneAuthoredBlendPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneBlendExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .blend }
}
extension SceneAuthoredTintPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneTintExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .tint }
}
extension SceneAuthoredTransformPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneTransformExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .transform }
}
extension SceneAuthoredFisheyeZeroDistortionPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneFisheyeZeroDistortionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend {
        .fisheyeZeroDistortion
    }
}
extension SceneAuthoredPulsePlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = ScenePulseExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .pulse }
}
extension SceneAuthoredGodraysPlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneGodraysPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .godrays }
}
extension SceneAuthoredShinePlanner: HarnessDedicatedPlanner {
    typealias DedicatedPlan = SceneShineExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .shine }
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
        visible: Bool? = true,
        kernel: Int = 0,
        verticalCombos: [String: Int] = ["VERTICAL": 1, "ENABLEMASK": 1]
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let scale = SceneDocument.ShaderValue(components: [0.75, 0.75])
        let horizontalCombos = kernel == 0 ? [:] : ["KERNEL": kernel]
        var resolvedVerticalCombos = verticalCombos
        if kernel != 0 {
            resolvedVerticalCombos["KERNEL"] = kernel
        }
        return .init(
            id: "42#effect#\(index)",
            file: "effects/workshop/blurprecise/effect.json",
            visible: visible,
            passes: [
                .init(
                    passIndex: 0,
                    textureSlots: [],
                    userTextureInputs: [],
                    combos: horizontalCombos,
                    constantShaderValues: ["scale": scale]
                ),
                .init(
                    passIndex: 1,
                    textureSlots: [],
                    userTextureInputs: [],
                    combos: resolvedVerticalCombos,
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
        unsupportedSecond: Bool = false,
        contentKind: String = "text"
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
                    contentKind: contentKind,
                    effects: [
                        effectDescriptor(index: 0),
                        effectDescriptor(index: 1, kernel: 1, verticalCombos: secondCombos),
                    ]
                ),
            ],
            materialPasses: materials()
        )
    }

    static func threeStageDescriptor() -> SceneRenderDescriptor {
        let base = descriptor(unsupportedSecond: true)
        let layer = base.layers[0]
        return .init(
            layers: [.init(
                id: layer.id,
                parentID: layer.parentID,
                visible: layer.visible,
                contentKind: layer.contentKind,
                effects: layer.effects + [effectDescriptor(index: 2, kernel: 1)]
            )],
            materialPasses: base.materialPasses
        )
    }

    static func chainGraph(
        discontinuousInput: Bool = false,
        duplicateNodeIndex: Bool = false,
        extraTarget: Bool = false,
        firstDefinitionPath: String = "effects/workshop/blurprecise/effect.json",
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
                definitionPath: firstDefinitionPath,
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

    static func threeStageChainGraph() -> Graph {
        let base = chainGraph()
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 2,
            descriptorID: "42#effect#2"
        )
        let input = base.effects[1].output
        let output = texture(.effectOutput, effect: key)
        let target = texture(.framebuffer, effect: key, name: "third")
        let effect = Graph.Effect(
            key: key,
            definitionPath: "effects/workshop/blurprecise/effect.json",
            input: input,
            output: output,
            nodeIndices: [4, 5]
        )
        let horizontal = Graph.Node(
            nodeIndex: 4,
            effect: key,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: "materials/precise_x.json",
            materialPassID: "materials/precise_x.json#0",
            target: target,
            bindings: [],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
        let vertical = Graph.Node(
            nodeIndex: 5,
            effect: key,
            definitionPassIndex: 1,
            materialOrdinal: 1,
            instancePassIndex: 1,
            kind: .material,
            materialPath: "materials/precise_y.json",
            materialPassID: "materials/precise_y.json#0",
            target: output,
            bindings: [
                .init(slot: 0, authoredName: "third", texture: target, conditions: nil),
                .init(slot: 1, authoredName: "previous", texture: input, conditions: nil),
            ],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
        let renderTarget = Graph.RenderTarget(
            texture: target,
            extent: .init(kind: .input, first: nil, second: nil),
            format: "rgba_backbuffer",
            declaredUnique: false,
            clear: nil,
            uvs: nil,
            conditions: nil
        )
        return .init(
            layerID: layerID,
            effects: base.effects + [effect],
            renderTargets: base.renderTargets + [renderTarget],
            nodes: base.nodes + [horizontal, vertical],
            finalOutput: output,
            blockers: []
        )
    }

    static func simpleFisheyeGraph(
        audioBarsPath: String = "effects/simple/effect.json",
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
                    definitionPath: audioBarsPath,
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
            "xRayPrefixes": catalog.xRayPrefixOmittedEffectPathsByLayerID
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value.joined(separator: ","))" },
            "admissions": admissionState(catalog.stageAdmissions),
            "reportLines": catalog.reportLines,
        ]
    }

    static func admissionState(
        _ admissions: [SceneAuthoredEffectStageAdmission]
    ) -> [[String: Any]] {
        admissions.map { admission in
            [
                "layer": admission.key.layerID,
                "effect": admission.key.effectIndex,
                "descriptor": admission.key.descriptorID,
                "activity": admission.activity.rawValue,
                "strict": admission.strictAdmission.rawValue,
                "coverage": admission.coverage.rawValue,
                "backend": admission.backendName ?? "-",
                "profile": admission.profileName ?? "-",
                "reason": admission.reasonCode ?? "-",
            ]
        }
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

    static func rejectionCode(
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> String {
        SceneAuthoredEffectChainPlanner.admit(
            graph: graph,
            descriptor: descriptor,
            shaderContracts: []
        ).rejection?.code.rawValue ?? "accepted"
    }

    static func probeOutcomeName(
        _ outcome: SceneEffectStageCompilerProbe.Outcome
    ) -> String {
        switch outcome {
        case .notApplicable:
            "not-applicable"
        case .rejected(let failure):
            "rejected:\(failure.phase.rawValue):\(failure.code.rawValue)"
        }
    }

    static func main() throws {
        let validDescriptor = descriptor()
        let validGraph = chainGraph()
        let chain = SceneAuthoredEffectChainPlanner.plan(
            graph: validGraph,
            descriptor: validDescriptor,
            shaderContracts: []
        )!
        let firstEffect = validGraph.effects[0]
        let firstStageGraph = SceneAuthoredEffectChainPlanner.stageGraph(
            effect: firstEffect,
            in: validGraph
        )!
        let firstCompile = SceneAuthoredEffectChainPlanner.compileStage(.init(
            stageGraph: firstStageGraph,
            authoredOrdinal: 0,
            effectKey: firstEffect.key,
            definitionPath: firstEffect.definitionPath,
            inputRole: .layerSource,
            descriptor: validDescriptor,
            shaderContracts: []
        ))
        let firstProgram: SceneEffectStageProgram
        guard case .accepted(let acceptedProgram) = firstCompile else {
            fatalError("first dedicated stage must compile")
        }
        firstProgram = acceptedProgram
        let firstCompilerBackend: String
        switch firstProgram.selection {
        case .dedicated(let backend):
            firstCompilerBackend = backend.rawValue
        case .authoredShader:
            firstCompilerBackend = "authored-shader"
        }
        let firstLegacyPlan = chain.stages[0]
        let firstProjectionPreserved =
            firstProgram.authoredOrdinal == 0
            && firstProgram.effectKey == firstEffect.key
            && firstProgram.definitionPath == firstEffect.definitionPath
            && firstProgram.inputRole == .layerSource
            && firstProgram.executionPlan.layerID == firstLegacyPlan.layerID
            && firstProgram.executionPlan.backend.stableName
                == firstLegacyPlan.backend.stableName
            && firstProgram.executionPlan.materialNodeCount
                == firstLegacyPlan.materialNodeCount
            && firstProgram.executionPlan.logicalRenderTargetCount
                == firstLegacyPlan.logicalRenderTargetCount
            && firstProgram.executionPlan.inputRole == firstLegacyPlan.inputRole
            && firstProgram.executionPlan.usesLegacyComposeNormalization
                == firstLegacyPlan.usesLegacyComposeNormalization
            && firstProgram.executionPlan.renderGraph.effects.map(\.key)
                == firstLegacyPlan.renderGraph.effects.map(\.key)
            && firstProgram.executionPlan.renderGraph.nodes.map(\.nodeIndex)
                == firstLegacyPlan.renderGraph.nodes.map(\.nodeIndex)
            && firstProgram.executionPlan.renderGraph.renderTargets.count
                == firstLegacyPlan.renderGraph.renderTargets.count
        let firstInput = SceneEffectStageCompileInput(
            stageGraph: firstStageGraph,
            authoredOrdinal: 0,
            effectKey: firstEffect.key,
            definitionPath: firstEffect.definitionPath,
            inputRole: .layerSource,
            descriptor: validDescriptor,
            shaderContracts: []
        )
        let backendInvariantRejected = SceneEffectStageProgram(
            input: firstInput,
            compilerBackend: .waterFlow,
            executionPlan: firstLegacyPlan
        ) == nil
        let mismatchedGraph = Graph(
            layerID: firstStageGraph.layerID,
            effects: firstStageGraph.effects,
            renderTargets: firstStageGraph.renderTargets,
            nodes: [],
            finalOutput: firstStageGraph.finalOutput,
            blockers: firstStageGraph.blockers
        )
        let mismatchedGraphPlan = SceneAuthoredEffectExecutionPlan(
            layerID: firstLegacyPlan.layerID,
            renderGraph: mismatchedGraph,
            backend: firstLegacyPlan.backend,
            materialNodeCount: firstLegacyPlan.materialNodeCount,
            logicalRenderTargetCount: firstLegacyPlan.logicalRenderTargetCount,
            inputRole: firstLegacyPlan.inputRole,
            usesLegacyComposeNormalization:
                firstLegacyPlan.usesLegacyComposeNormalization
        )
        let graphInvariantRejected = SceneEffectStageProgram(
            input: firstInput,
            compilerBackend: .preciseGaussian,
            executionPlan: mismatchedGraphPlan
        ) == nil
        let invariantAggregate = SceneEffectStageCompileResult.accepted(
            firstLegacyPlan,
            compilerBackend: .standardBlur,
            input: firstInput,
            precedingProbes: [.init(
                backend: .preciseGaussian,
                outcome: .notApplicable
            )]
        )
        let invariantAggregateCode: String
        let invariantAggregateOutcomes: [String]
        switch invariantAggregate {
        case .accepted:
            invariantAggregateCode = "accepted"
            invariantAggregateOutcomes = []
        case .unsupported(let failure):
            invariantAggregateCode = failure.code.rawValue
            invariantAggregateOutcomes = failure.probes.map {
                probeOutcomeName($0.outcome)
            }
        }

        let overlapGraph = simpleFisheyeGraph(
            audioBarsPath: "effects/overlap/effect.json"
        )
        let overlapEffect = overlapGraph.effects[0]
        let overlapStageGraph = SceneAuthoredEffectChainPlanner.stageGraph(
            effect: overlapEffect,
            in: overlapGraph
        )!
        SceneAuthoredWorkshopAudioBarsPlanner.callCount = 0
        SceneAuthoredWorkshopSimpleAudioBarsPlanner.callCount = 0
        SceneAuthoredShaderExecutionPlanner.compiledEffectIndices = []
        let overlapCompile = SceneAuthoredEffectChainPlanner.compileStage(.init(
            stageGraph: overlapStageGraph,
            authoredOrdinal: 0,
            effectKey: overlapEffect.key,
            definitionPath: overlapEffect.definitionPath,
            inputRole: .layerSource,
            descriptor: validDescriptor,
            shaderContracts: []
        ))
        guard case .accepted(let overlapProgram) = overlapCompile else {
            fatalError("overlapping Audio Bars stage must compile")
        }
        let overlapCompilerBackend: String
        switch overlapProgram.selection {
        case .dedicated(let backend):
            overlapCompilerBackend = backend.rawValue
        case .authoredShader:
            overlapCompilerBackend = "authored-shader"
        }
        let overlapEnhancedCalls = SceneAuthoredWorkshopAudioBarsPlanner.callCount
        let overlapSimpleCalls = SceneAuthoredWorkshopSimpleAudioBarsPlanner.callCount
        let overlapGenericCalls = SceneAuthoredShaderExecutionPlanner.compiledEffectIndices

        let genericGraph = simpleFisheyeGraph(
            fisheyePath: "effects/generic/effect.json"
        )
        let genericEffect = genericGraph.effects[1]
        let genericStageGraph = SceneAuthoredEffectChainPlanner.stageGraph(
            effect: genericEffect,
            in: genericGraph
        )!
        let genericCompile = SceneAuthoredEffectChainPlanner.compileStage(.init(
            stageGraph: genericStageGraph,
            authoredOrdinal: 1,
            effectKey: genericEffect.key,
            definitionPath: genericEffect.definitionPath,
            inputRole: .priorEffectOutput,
            descriptor: validDescriptor,
            shaderContracts: []
        ))
        guard case .accepted(let genericProgram) = genericCompile else {
            fatalError("generic authored stage must compile")
        }
        let genericSelectionIsAuthored: Bool
        switch genericProgram.selection {
        case .authoredShader:
            genericSelectionIsAuthored = true
        case .dedicated:
            genericSelectionIsAuthored = false
        }
        let unknownGraph = simpleFisheyeGraph(
            audioBarsPath: "effects/unknown/effect.json"
        )
        let unknownEffect = unknownGraph.effects[0]
        let unknownStageGraph = SceneAuthoredEffectChainPlanner.stageGraph(
            effect: unknownEffect,
            in: unknownGraph
        )!
        let unknownCompile = SceneAuthoredEffectChainPlanner.compileStage(.init(
            stageGraph: unknownStageGraph,
            authoredOrdinal: 0,
            effectKey: unknownEffect.key,
            definitionPath: unknownEffect.definitionPath,
            inputRole: .layerSource,
            descriptor: validDescriptor,
            shaderContracts: []
        ))
        let unknownProbes: [SceneEffectStageCompilerProbe]
        switch unknownCompile {
        case .accepted:
            unknownProbes = []
        case .unsupported(let failure):
            unknownProbes = failure.probes
        }
        let waterFlowRejectedGraph = simpleFisheyeGraph(
            audioBarsPath: "effects/waterflow/unsupported-profile/effect.json"
        )
        let waterFlowRejectedEffect = waterFlowRejectedGraph.effects[0]
        let waterFlowRejectedStageGraph = SceneAuthoredEffectChainPlanner.stageGraph(
            effect: waterFlowRejectedEffect,
            in: waterFlowRejectedGraph
        )!
        let waterFlowRejectedCompile = SceneAuthoredEffectChainPlanner.compileStage(.init(
            stageGraph: waterFlowRejectedStageGraph,
            authoredOrdinal: 0,
            effectKey: waterFlowRejectedEffect.key,
            definitionPath: waterFlowRejectedEffect.definitionPath,
            inputRole: .layerSource,
            descriptor: validDescriptor,
            shaderContracts: []
        ))
        let waterFlowRejectedProbes: [SceneEffectStageCompilerProbe]
        switch waterFlowRejectedCompile {
        case .accepted:
            waterFlowRejectedProbes = []
        case .unsupported(let failure):
            waterFlowRejectedProbes = failure.probes
        }
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
        let firstKey = validGraph.effects[0].key
        let secondKey = validGraph.effects[1].key
        let genericStage = SceneAuthoredEffectExecutionPlan(
            layerID: layerID,
            renderGraph: chain.stages[0].renderGraph,
            backend: .authoredShader(SceneAuthoredShaderExecutionPlan()),
            materialNodeCount: 1,
            logicalRenderTargetCount: 0
        )
        func admissionVariant(
            stages: [SceneAuthoredEffectExecutionPlan],
            irisSuffix: SceneIrisInlineSuffixPlan? = nil,
            coverage: SceneAuthoredEffectChainAdmission.Coverage
        ) -> [[String: Any]] {
            let variantChain = SceneAuthoredEffectExecutionChain(
                layerID: layerID,
                renderGraph: validGraph,
                stages: stages,
                irisInlineSuffix: irisSuffix
            )
            return admissionState(SceneAuthoredEffectStageAdmissionBuilder.make(
                layer: validDescriptor.layers[0],
                graphCandidates: [validGraph],
                chainAdmission: .accepted(chain: variantChain, coverage: coverage),
                layerIsVisible: true
            ))
        }

        let unsupportedDescriptor = descriptor(unsupportedSecond: true)
        let threeStageGraph = threeStageChainGraph()
        let threeDescriptor = threeStageDescriptor()
        SceneAuthoredShaderExecutionPlanner.compiledEffectIndices = []
        let threeStageAdmission = SceneAuthoredEffectChainPlanner.admit(
            graph: threeStageGraph,
            descriptor: threeDescriptor,
            shaderContracts: []
        )
        let threeStageCompilerCalls =
            SceneAuthoredShaderExecutionPlanner.compiledEffectIndices
        let threeStageAdmissions = SceneAuthoredEffectStageAdmissionBuilder.make(
            layer: threeDescriptor.layers[0],
            graphCandidates: [threeStageGraph],
            chainAdmission: threeStageAdmission,
            layerIsVisible: true
        )
        let threeStageCompileFailure = threeStageAdmission.rejection?
            .stageCompileFailure
        let threeStageProbes = threeStageCompileFailure?.probes ?? []
        let mixedGraph = chainGraph(
            secondDefinitionPath: "effects/water/effect.json"
        )
        let xRayPrefixCatalog = catalogState(
            descriptor: descriptor(
                unsupportedSecond: true,
                contentKind: "composition"
            ),
            graphs: [chainGraph(
                firstDefinitionPath: "effects/xray/effect.json",
                secondDefinitionPath: "effects/unknown/effect.json"
            )]
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
        let inactiveDescriptor = SceneRenderDescriptor(
            layers: [
                .init(
                    id: layerID,
                    parentID: nil,
                    visible: true,
                    contentKind: "text",
                    effects: [
                        effectDescriptor(index: 0, visible: false),
                        effectDescriptor(index: 1),
                    ]
                ),
            ],
            materialPasses: materials()
        )
        let inactiveCatalog = SceneAuthoredEffectExecutionCatalog(
            descriptor: inactiveDescriptor,
            authoredPlans: []
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
            "typedCompilation": [
                "firstCompilerBackend": firstCompilerBackend,
                "firstProjectionPreserved": firstProjectionPreserved,
                "backendInvariantRejected": backendInvariantRejected,
                "graphInvariantRejected": graphInvariantRejected,
                "invariantAggregateCode": invariantAggregateCode,
                "invariantAggregateOutcomes": invariantAggregateOutcomes,
                "overlapCompilerBackend": overlapCompilerBackend,
                "overlapEnhancedCalls": overlapEnhancedCalls,
                "overlapSimpleCalls": overlapSimpleCalls,
                "overlapGenericCalls": overlapGenericCalls,
                "overlapPrecedingProbeCount": overlapProgram.precedingProbes.count,
                "overlapPrecedingProbeOutcomes": overlapProgram.precedingProbes.map {
                    probeOutcomeName($0.outcome)
                },
                "genericSelectionIsAuthored": genericSelectionIsAuthored,
                "genericPrecedingProbeCount": genericProgram.precedingProbes.count,
                "genericPrecedingProbeOutcomes": genericProgram.precedingProbes.map {
                    probeOutcomeName($0.outcome)
                },
                "unknownProbeBackends": unknownProbes.map { $0.backend.rawValue },
                "unknownProbeOutcomes": unknownProbes.map {
                    probeOutcomeName($0.outcome)
                },
                "waterFlowRejectedProbeBackends": waterFlowRejectedProbes.map {
                    $0.backend.rawValue
                },
                "waterFlowRejectedProbeOutcomes": waterFlowRejectedProbes.map {
                    probeOutcomeName($0.outcome)
                },
                "threeStageChainRejected": threeStageAdmission.chain == nil,
                "threeStageTopLevelReason":
                    threeStageAdmission.rejection?.code.rawValue ?? "accepted",
                "threeStageAdmissionReasons": threeStageAdmissions.map {
                    $0.reasonCode ?? "-"
                },
                "threeStageCompilerCalls": threeStageCompilerCalls,
                "aggregateReason": threeStageCompileFailure?.code.rawValue ?? "-",
                "probeBackends": threeStageProbes.map { $0.backend.rawValue },
                "probeOutcomes": threeStageProbes.map {
                    probeOutcomeName($0.outcome)
                },
                "probeIdentityComplete":
                    Set(threeStageProbes.map(\.backend))
                        == Set(SceneEffectStageCompilerBackend.allCases),
                "probeIdentityUnique":
                    Set(threeStageProbes.map(\.backend)).count
                        == threeStageProbes.count,
                "outerGraphHasNoStageFailure":
                    SceneAuthoredEffectChainPlanner.admit(
                        graph: chainGraph(hasBlocker: true),
                        descriptor: validDescriptor,
                        shaderContracts: []
                    ).rejection?.stageCompileFailure == nil,
            ],
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
                "kernels": chain.stages.map { $0.gaussianBlur?.kernel.rawValue ?? -1 },
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
                "admissions": admissionState(catalog.stageAdmissions),
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
            "directRejectionCodes": [
                "unsupportedSecond": rejectionCode(
                    graph: validGraph,
                    descriptor: unsupportedDescriptor
                ),
                "blocker": rejectionCode(
                    graph: chainGraph(hasBlocker: true),
                    descriptor: validDescriptor
                ),
                "discontinuousInput": rejectionCode(
                    graph: chainGraph(discontinuousInput: true),
                    descriptor: validDescriptor
                ),
                "duplicateNode": rejectionCode(
                    graph: chainGraph(duplicateNodeIndex: true),
                    descriptor: validDescriptor
                ),
                "extraTarget": rejectionCode(
                    graph: chainGraph(extraTarget: true),
                    descriptor: validDescriptor
                ),
                "mixedUnsupported": rejectionCode(
                    graph: mixedGraph,
                    descriptor: unsupportedDescriptor
                ),
            ],
            "admissionVariants": [
                "generic": admissionVariant(
                    stages: [genericStage, chain.stages[1]],
                    coverage: .complete
                ),
                "iris": admissionVariant(
                    stages: [chain.stages[0]],
                    irisSuffix: .init(effectKey: secondKey),
                    coverage: .terminalIrisInlineSuffix(effect: secondKey)
                ),
                "prefix": admissionVariant(
                    stages: [chain.stages[0]],
                    coverage: .xRayPrefix(omitted: [secondKey])
                ),
                "isolation": admissionVariant(
                    stages: [chain.stages[1]],
                    coverage: .isolatedShine(
                        executed: secondKey,
                        omitted: [firstKey]
                    )
                ),
            ],
            "xRayPrefixCatalog": xRayPrefixCatalog,
            "failureCatalogs": failureCatalogs,
            "hidden": [
                "chainLayers": hiddenCatalog.chainsByLayerID.keys.sorted(),
                "singleStageLayers": hiddenCatalog.plansByLayerID.keys.sorted(),
                "eligible": hiddenCatalog.hiddenEligibleLayerIDs,
                "legacyBlocked": hiddenCatalog.legacyGaussianBlurBlockedLayerIDs.sorted(),
                "admissions": admissionState(hiddenCatalog.stageAdmissions),
            ],
            "inactive": [
                "admissions": admissionState(inactiveCatalog.stageAdmissions),
                "reportLines": inactiveCatalog.reportLines,
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
        self.assertEqual(success["kernels"], [0, 1])
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
        self.assertEqual(
            catalog["admissions"],
            [
                {
                    "layer": 42,
                    "effect": 0,
                    "descriptor": "42#effect#0",
                    "activity": "active",
                    "strict": "admitted-dedicated",
                    "coverage": "complete",
                    "backend": "precise-gaussian",
                    "profile": "-",
                    "reason": "-",
                },
                {
                    "layer": 42,
                    "effect": 1,
                    "descriptor": "42#effect#1",
                    "activity": "active",
                    "strict": "admitted-dedicated",
                    "coverage": "complete",
                    "backend": "precise-gaussian",
                    "profile": "-",
                    "reason": "-",
                },
            ],
        )
        for line in (
            "authoredEffectGraphPlannedCount: 1",
            "authoredEffectGraphMaterialNodeCount: 4",
            "authoredEffectGraphLogicalRTCount: 2",
            "authoredEffectGraphChainCount: 1",
            "authoredEffectGraphStageCount: 2",
            "authoredEffectStageDescriptorCount: 2",
            "authoredEffectStageParsedCount: 2",
            "authoredEffectStageActivityCounts: author-disabled=0,layer-hidden=0,active=2",
            "authoredEffectStageStrictAdmissionCounts: inactive=0,admitted-dedicated=2,admitted-generic=0,not-admitted=0",
            "authoredEffectStageDescriptorIdentityConserved: true",
            "authoredEffectStageActivityConserved: true",
            "authoredEffectStageInactiveAdmissionConserved: true",
            "authoredEffectStageActiveAdmissionConserved: true",
            "authoredEffectStageStrictIdentityConserved: true",
            "authoredEffectStageCompileFailureCount: 0",
            "authoredEffectStageCompileFailureCodes: ",
            "authoredEffectStageCompilerProbeOutcomeCounts: ",
            "authoredEffectStageCompilerFailureCodes: ",
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

    def test_typed_stage_compilation_preserves_projection_and_failure_order(self) -> None:
        typed = self.result["typedCompilation"]
        self.assertEqual(typed["firstCompilerBackend"], "precise-gaussian")
        self.assertTrue(typed["firstProjectionPreserved"])
        self.assertTrue(typed["backendInvariantRejected"])
        self.assertTrue(typed["graphInvariantRejected"])
        self.assertEqual(typed["overlapCompilerBackend"], "workshop-audio-bars")
        self.assertEqual(typed["overlapEnhancedCalls"], 1)
        self.assertEqual(typed["overlapSimpleCalls"], 0)
        self.assertEqual(typed["overlapGenericCalls"], [])
        self.assertEqual(typed["overlapPrecedingProbeCount"], 7)
        self.assertEqual(
            typed["overlapPrecedingProbeOutcomes"],
            ["not-applicable"] * 7,
        )
        self.assertTrue(typed["genericSelectionIsAuthored"])
        self.assertEqual(typed["genericPrecedingProbeCount"], 33)
        self.assertEqual(
            typed["genericPrecedingProbeOutcomes"],
            ["not-applicable"] * 33,
        )
        self.assertTrue(typed["threeStageChainRejected"])
        self.assertEqual(typed["threeStageTopLevelReason"], "unsupported-stage")
        self.assertEqual(
            typed["threeStageAdmissionReasons"],
            [
                "discarded-strict-prefix",
                "unsupported-stage",
                "not-evaluated-after-chain-rejection",
            ],
        )
        self.assertEqual(typed["threeStageCompilerCalls"], [1])
        self.assertEqual(typed["aggregateReason"], "no-backend-accepted")
        expected_backends = [
            "precise-gaussian",
            "standard-blur",
            "local-contrast",
            "opacity",
            "color-key",
            "color-grading",
            "workshop-shift-hue",
            "workshop-audio-bars",
            "workshop-simple-audio-bars",
            "workshop-gradient",
            "workshop-audio-hue-shift",
            "workshop-shadow",
            "spin",
            "procedural-noise",
            "film-grain",
            "light-shafts",
            "shake",
            "water-flow",
            "water-waves",
            "water-caustics",
            "cursor-ripple",
            "foliage-sway",
            "water-ripple",
            "depth-parallax",
            "x-ray",
            "clipping-mask",
            "blend",
            "tint",
            "transform",
            "fisheye-zero-distortion",
            "pulse",
            "godrays",
            "shine",
            "authored-shader",
        ]
        self.assertEqual(typed["probeBackends"], expected_backends)
        self.assertEqual(typed["unknownProbeBackends"], expected_backends)
        self.assertEqual(
            typed["unknownProbeOutcomes"],
            ["not-applicable"] * 34,
        )
        self.assertEqual(typed["waterFlowRejectedProbeBackends"], expected_backends)
        water_flow_outcomes = ["not-applicable"] * 34
        water_flow_outcomes[17] = (
            "rejected:compatibility:dedicated-profile-rejected"
        )
        self.assertEqual(
            typed["waterFlowRejectedProbeOutcomes"],
            water_flow_outcomes,
        )
        self.assertTrue(typed["probeIdentityComplete"])
        self.assertTrue(typed["probeIdentityUnique"])
        self.assertEqual(
            typed["probeOutcomes"],
            ["rejected:compatibility:dedicated-profile-rejected"]
                + ["not-applicable"] * 33,
        )
        self.assertTrue(typed["outerGraphHasNoStageFailure"])
        report_lines = self.result["failureCatalogs"]["unsupportedSecond"][
            "reportLines"
        ]
        self.assertIn("authoredEffectStageCompileFailureCount: 1", report_lines)
        self.assertIn(
            "authoredEffectStageCompileFailureCodes: no-backend-accepted=1",
            report_lines,
        )
        self.assertIn(
            "authoredEffectStageCompilerProbeOutcomeCounts: "
            "not-applicable=33,rejected=1",
            report_lines,
        )
        compiler_failures = next(
            line for line in report_lines
            if line.startswith("authoredEffectStageCompilerFailureCodes: ")
        )
        self.assertIn(
            "precise-gaussian/compatibility/dedicated-profile-rejected=1",
            compiler_failures,
        )

    def test_stage_program_invariant_is_a_typed_aggregate_failure(self) -> None:
        typed = self.result["typedCompilation"]
        self.assertEqual(
            typed["invariantAggregateCode"],
            "stage-program-invariant",
        )
        self.assertEqual(
            typed["invariantAggregateOutcomes"],
            [
                "not-applicable",
                "rejected:invariant:stage-program-invariant",
            ],
        )

    def test_invalid_second_stage_or_outer_graph_fails_the_whole_chain(self) -> None:
        for name, rejected in self.result["directRejections"].items():
            self.assertTrue(rejected, name)

        for name, catalog in self.result["failureCatalogs"].items():
            self.assertEqual(catalog["chainLayers"], [], name)
            self.assertEqual(catalog["singleStageLayers"], [], name)
            self.assertEqual(catalog["hidden"], [], name)
            self.assertEqual(catalog["legacyBlocked"], [42], name)
            expected_coverages = {
                "multipleCandidates": ["rejected-ambiguous-graph"] * 2,
                "mixedUnsupported": [
                    "rejected-chain",
                    "rejected-graph-mismatch",
                ],
            }.get(name, ["rejected-chain"] * 2)
            self.assertEqual(len(catalog["admissions"]), 2, name)
            self.assertTrue(
                all(item["activity"] == "active" for item in catalog["admissions"]),
                name,
            )
            self.assertTrue(
                all(item["strict"] == "not-admitted" for item in catalog["admissions"]),
                name,
            )
            self.assertEqual(
                [item["coverage"] for item in catalog["admissions"]],
                expected_coverages,
                name,
            )

        self.assertEqual(
            self.result["directRejectionCodes"],
            {
                "unsupportedSecond": "unsupported-stage",
                "blocker": "graph-blocked",
                "discontinuousInput": "discontinuous-effect-input",
                "duplicateNode": "duplicate-effect-node-reference",
                "extraTarget": "unsupported-stage",
                "mixedUnsupported": "unsupported-stage",
            },
        )
        self.assertEqual(
            [item["reason"] for item in self.result["failureCatalogs"]["unsupportedSecond"]["admissions"]],
            ["discarded-strict-prefix", "unsupported-stage"],
        )
        self.assertEqual(
            [item["reason"] for item in self.result["failureCatalogs"]["discontinuousInput"]["admissions"]],
            ["discarded-strict-prefix", "discontinuous-effect-input"],
        )

    def test_partial_chain_coverage_and_generic_executor_are_explicit(self) -> None:
        variants = self.result["admissionVariants"]
        self.assertEqual(
            [(item["strict"], item["coverage"], item["backend"], item["profile"])
             for item in variants["generic"]],
            [
                ("admitted-generic", "complete", "authored-shader", "generic-framebuffer"),
                ("admitted-dedicated", "complete", "precise-gaussian", "-"),
            ],
        )
        self.assertEqual(
            [(item["strict"], item["coverage"], item["reason"])
             for item in variants["iris"]],
            [
                ("admitted-dedicated", "terminal-inline-prefix", "-"),
                ("not-admitted", "terminal-inline-suffix", "terminal-inline-suffix"),
            ],
        )
        self.assertEqual(
            [(item["strict"], item["coverage"], item["reason"])
             for item in variants["prefix"]],
            [
                ("admitted-dedicated", "prefix-accepted", "-"),
                ("not-admitted", "prefix-omitted", "prefix-omitted"),
            ],
        )
        self.assertEqual(
            [(item["strict"], item["coverage"], item["reason"])
             for item in variants["isolation"]],
            [
                ("not-admitted", "isolated-omitted", "isolated-omitted"),
                ("admitted-dedicated", "isolated-accepted", "-"),
            ],
        )
        self.assertEqual(
            self.result["xRayPrefixCatalog"]["xRayPrefixes"],
            ["42=effects/unknown/effect.json"],
        )

    def test_hidden_complete_chain_is_not_runtime_eligible(self) -> None:
        hidden = self.result["hidden"]
        self.assertEqual(hidden["chainLayers"], [])
        self.assertEqual(hidden["singleStageLayers"], [])
        self.assertEqual(hidden["eligible"], [42])
        self.assertEqual(hidden["legacyBlocked"], [])
        self.assertEqual(
            [(item["activity"], item["strict"], item["coverage"])
             for item in hidden["admissions"]],
            [("layer-hidden", "inactive", "inactive")] * 2,
        )

    def test_author_disabled_and_missing_graph_are_separate_axes(self) -> None:
        inactive = self.result["inactive"]
        self.assertEqual(
            [(item["activity"], item["strict"], item["coverage"])
             for item in inactive["admissions"]],
            [
                ("author-disabled", "inactive", "inactive"),
                ("active", "not-admitted", "rejected-missing-graph"),
            ],
        )
        for line in (
            "authoredEffectStageDescriptorCount: 2",
            "authoredEffectStageParsedCount: 2",
            "authoredEffectStageActivityCounts: author-disabled=1,layer-hidden=0,active=1",
            "authoredEffectStageStrictAdmissionCounts: inactive=1,admitted-dedicated=0,admitted-generic=0,not-admitted=1",
            "authoredEffectStageDescriptorIdentityConserved: true",
            "authoredEffectStageActivityConserved: true",
            "authoredEffectStageInactiveAdmissionConserved: true",
            "authoredEffectStageActiveAdmissionConserved: true",
            "authoredEffectStageStrictIdentityConserved: true",
        ):
            self.assertIn(line, inactive["reportLines"])

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
