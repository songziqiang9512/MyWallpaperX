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
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan+Clear.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan+Extent.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetTable.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphCommandRuntime.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphNodeScheduler.swift",
    SOURCE_ROOT / "Rendering/SceneMatrix.swift",
    SOURCE_ROOT / "Rendering/SceneMetalPipeline.swift",
    SOURCE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SOURCE_ROOT / "Runtime/SceneTextureAnimationPlaybackPlan.swift",
    SOURCE_ROOT / "Resources/SceneTextureAnimationPlaybackClock.swift",
    SOURCE_ROOT / "Rendering/SceneSpriteAnimation.swift",
    SOURCE_ROOT / "Rendering/SceneMainPassEncoder.swift",
    SOURCE_ROOT / "Rendering/SceneFramebufferSnapshot.swift",
    SOURCE_ROOT / "RenderGraph/SceneOffscreenResolutionPolicy.swift",
    SOURCE_ROOT / "RenderGraph/SceneOffscreenTexturePool.swift",
    SOURCE_ROOT / "Resources/SceneTextureSampling.swift",
    SOURCE_ROOT / "Resources/SceneTextureCandidate.swift",
    SOURCE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SOURCE_ROOT / "Rendering/SceneBaseImageTextureCandidateSupport.swift",
    SOURCE_ROOT / "Effects/SceneGaussianBlurPipeline.swift",
    SOURCE_ROOT / "Effects/SceneStandardBlurPipeline.swift",
    SOURCE_ROOT / "Effects/SceneStandardBlurRenderer.swift",
    SOURCE_ROOT / "Effects/SceneLocalContrastPipeline.swift",
    SOURCE_ROOT / "Effects/SceneLocalContrastRenderer.swift",
    SOURCE_ROOT / "Effects/SceneOpacityPipeline.swift",
    SOURCE_ROOT / "Effects/SceneOpacityRenderer.swift",
    SOURCE_ROOT / "Effects/SceneColorKeyPipeline.swift",
    SOURCE_ROOT / "Effects/SceneColorKeyRenderer.swift",
    SOURCE_ROOT / "Effects/SceneColorGradingPipeline.swift",
    SOURCE_ROOT / "Effects/SceneFisheyeZeroDistortionPipeline.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopShiftHuePipeline.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopShiftHueRenderer.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopAudioBarsPipeline.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopSimpleAudioBarsPipeline.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopGradientPipeline.swift",
    SOURCE_ROOT / "Effects/SceneSpinPipeline.swift",
    SOURCE_ROOT / "Effects/SceneProceduralNoisePipeline.swift",
    SOURCE_ROOT / "Effects/SceneProceduralNoisePipeline+Support.swift",
    SOURCE_ROOT / "Effects/SceneFilmGrainPipeline.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopShadowPipeline.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopShadowRenderer.swift",
    SOURCE_ROOT / "Rendering/SceneImageBlendPipeline.swift",
    SOURCE_ROOT / "Effects/SceneBlendPipeline.swift",
    SOURCE_ROOT / "Effects/SceneMediaThumbnailTransitionPipeline.swift",
    SOURCE_ROOT / "Effects/SceneGradientColorPipeline.swift",
    SOURCE_ROOT / "Effects/SceneBloomPipeline.swift",
    SOURCE_ROOT / "Effects/SceneLightShaftsPipeline.swift",
    SOURCE_ROOT / "Effects/SceneWaterRipplePipeline.swift",
    SOURCE_ROOT / "Effects/ScenePerspectiveOpacityPipeline.swift",
    SOURCE_ROOT / "Effects/SceneXRayPipeline.swift",
    SOURCE_ROOT / "Effects/SceneBlendModeShaderSource.swift",
    SOURCE_ROOT / "Rendering/SceneLayerColorBlendPipeline.swift",
    SOURCE_ROOT / "Effects/SceneTintPipeline.swift",
    SOURCE_ROOT / "Effects/ScenePulsePipeline.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectMaskSemantics.swift",
    SOURCE_ROOT / "Effects/SceneFoliageSwayRuntimePlan.swift",
    SOURCE_ROOT / "Effects/SceneGaussianBlurRuntimePlan.swift",
    SOURCE_ROOT / "Effects/SceneGradientColorRuntimePlan.swift",
    SOURCE_ROOT / "Rendering/SceneTextureMappedUVScale.swift",
    SOURCE_ROOT / "Effects/SceneWaterRippleRuntimePlan.swift",
    SOURCE_ROOT / "Effects/SceneInlineEffectRuntime.swift",
    SOURCE_ROOT / "Effects/SceneEffectRuntimeSupport.swift",
    SOURCE_ROOT / "Effects/SceneEffectRuntimePlan.swift",
    SOURCE_ROOT / "Effects/SceneEffectRuntimeModel.swift",
    SOURCE_ROOT / "Effects/SceneEffectStageRuntimeDisposition.swift",
    SOURCE_ROOT / "Effects/SceneLegacyEffectPlanningDecision.swift",
    SOURCE_ROOT / "Effects/SceneLegacyEffectPlanningDecision+Inline.swift",
    SOURCE_ROOT / "Effects/SceneLegacyEffectPlanningDecision+Execution.swift",
    SOURCE_ROOT / "Effects/SceneOffscreenEffectRenderer.swift",
    SOURCE_ROOT / "Effects/SceneOffscreenEffectRenderer+LegacyTelemetry.swift",
    SOURCE_ROOT / "Effects/SceneOffscreenEffectRenderer+Capture.swift",
    SOURCE_ROOT / "Runtime/SceneAudioSpectrum.swift",
    SOURCE_ROOT / "Runtime/SceneAudioResponse.swift",
    SOURCE_ROOT / "RenderGraph/SceneSpinExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneProceduralNoiseExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneFilmGrainExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneLightShaftsExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer.swift",
    SOURCE_ROOT
    / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+SpecializedStage.swift",
    SOURCE_ROOT
    / "RenderGraph/EffectExecution/SceneStandaloneAuthoredEffectRenderer.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+CursorRipple.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+WaterRipple.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+Rays.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+Blend.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+AuthoredShader.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+Opacity.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+AudioBars.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+SimpleAudioBars.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+AudioHueShift.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+WorkshopGradient.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+ColorKey.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+ColorGrading.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+Pulse.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+ShiftHue.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+Spin.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+ProceduralNoise.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+FilmGrain.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+ClippingMask.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+Tint.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+Transform.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+XRay.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+Topology.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+WorkshopStage.swift",
    SOURCE_ROOT / "Rendering/SceneImageEffectPipelineRepository.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectPipelineSet.swift",
    SOURCE_ROOT / "Rendering/SceneImageLayerDrawRequest.swift",
    SOURCE_ROOT / "Rendering/SceneImageLayerCompositor.swift",
    SOURCE_ROOT / "Rendering/SceneImageLayerCompositor+Uniforms.swift",
    SOURCE_ROOT / "Rendering/SceneImageLayerMainPassRenderer.swift",
    SOURCE_ROOT / "Runtime/SceneGPUCompletionTelemetry.swift",
    SOURCE_ROOT / "Runtime/SceneEffectExecutionFrameTrace.swift",
    SOURCE_ROOT / "Runtime/SceneEffectExecutionTelemetry.swift",
]

HARNESS_SOURCE = r'''
import Foundation
import Dispatch
import Metal
import simd

enum SceneTextureProviderState {}
struct SceneFrameTextureRegistrySnapshot {}

enum SceneFrameTextureRegistry {
    enum ProviderStatus {}
}

enum SceneMediaThumbnailTextureStore {
    struct Snapshot {}
}

final class SceneResolvedMaterialRuntimeBridge {
    var assetStates: [SceneAssetTextureIdentity: SceneTextureProviderState] { [:] }

    func systemProviderBlocks(
        for snapshot: SceneMediaThumbnailTextureStore.Snapshot
    ) -> [String: SceneFrameTextureRegistry.ProviderStatus] {
        [:]
    }

    func beginFrame(
        textureSnapshot: SceneFrameTextureRegistrySnapshot,
        dynamicSnapshot: SceneDynamicSnapshot,
        frameInputs: SceneAuthoredShaderFrameInputs
    ) {}

    func endFrame() {}

    func auditResolvedMaterials(
        graph: SceneAuthoredEffectRenderPlan,
        targets: SceneGraphRenderTargetTable
    ) {}
}

enum SceneMediaThumbnailTransitionTexture {
    struct Arguments {
        let texture: MTLTexture
        let uvScale: SIMD2<Float>
        let sampling: SceneTextureSampling
    }
}

struct SceneDocument {
    struct ShaderValue {
        let valueKind: String
        let userBinding: String?
        let components: [Double]?

        init(
            valueKind: String = "number",
            userBinding: String? = nil,
            components: [Double]?
        ) {
            self.valueKind = valueKind
            self.userBinding = userBinding
            self.components = components
        }
    }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [Int?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]

            init(
                passIndex: Int = 0,
                texturePaths: [String],
                textureSlots: [String?],
                userTextureInputs: [Int?] = [],
                combos: [String: Int],
                constantShaderValues: [String: SceneDocument.ShaderValue]
            ) {
                self.passIndex = passIndex
                self.texturePaths = texturePaths
                self.textureSlots = textureSlots
                self.userTextureInputs = userTextureInputs
                self.combos = combos
                self.constantShaderValues = constantShaderValues
            }
        }

        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
        var id: String { file }
    }

    struct Layer {
        let id: Int = 0
        let contentKind: String
        let colorRGB: [Float]?
        let colorBlendMode: Int?
        var brightness: Double? = nil
        let effects: [EffectDescriptor]
    }
}

enum SceneClippingMaskProfile: String {
    case classic
    case weightedNeutral
}

struct SceneClippingMaskExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let providerLayerID: Int
    let blendMode: Int
    let profile: SceneClippingMaskProfile
}

struct SceneTexContainer {
    struct SpriteFrame {
        let imageIndex: Int
        let duration: Float
        let origin: SIMD2<Float>
        let xAxis: SIMD2<Float>
        let yAxis: SIMD2<Float>
    }
    let spriteFrames: [SpriteFrame]
    let textureWidth: Int = 1
    let textureHeight: Int = 1
}

struct SceneTexContainerReader {
    func read(data: Data) throws -> SceneTexContainer {
        SceneTexContainer(spriteFrames: [])
    }
}

struct SceneWorkshopShadowExecutionPlan: Equatable, Sendable {
    let alpha: Float
    let color: SIMD3<Float>
    let drawBorder: Float
    let offset: SIMD2<Float>
}

struct SceneOpacityExecutionPlan: Equatable, Sendable {
    let staticOrFallbackAlpha: Float
    let liveEffectIndex: Int?
    let maskTexturePath: String?
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey

    init(
        staticOrFallbackAlpha: Float,
        liveEffectIndex: Int? = nil,
        maskTexturePath: String? = nil,
        effectKey: SceneAuthoredEffectRenderPlan.EffectKey = .init(
            layerID: 0, effectIndex: 0, descriptorID: ""
        )
    ) {
        self.staticOrFallbackAlpha = staticOrFallbackAlpha
        self.liveEffectIndex = liveEffectIndex
        self.maskTexturePath = maskTexturePath
        self.effectKey = effectKey
    }

    func resolvedAlpha(in snapshot: SceneDynamicSnapshot) -> Float {
        liveEffectIndex.flatMap { snapshot.opacitiesByEffectIndex[$0] }
            ?? staticOrFallbackAlpha
    }
}

struct SceneColorKeyExecutionPlan: Sendable {
    let keyAlpha: Float
    let fuzziness: Float
    let tolerance: Float
    let keyColor: SIMD3<Float>
    let invert: Bool
    let flatten: Bool
}

struct SceneColorGradingExecutionPlan: Sendable {
    let luminance: Float
    let saturation: Float
    let vibrance: Float
    let opacity: Float
    let channelInfluence: SIMD3<Float>
}

struct SceneWorkshopShiftHueExecutionPlan: Sendable {
    let speed: Float
}

struct SceneWorkshopAudioBarsExecutionPlan: Sendable {
    struct SimpleParameters: Sendable {
        enum Profile: Equatable, Sendable {
            case bottomReplace32ClipLow
            case bottomReplace64ClipHigh
            case stereoUpDown16IntersectAdd

            var resolution: Int {
                switch self {
                case .bottomReplace32ClipLow: 32
                case .bottomReplace64ClipHigh: 64
                case .stereoUpDown16IntersectAdd: 16
                }
            }

            var clipsLow: Bool { self == .bottomReplace32ClipLow }
            var clipsHigh: Bool { self == .bottomReplace64ClipHigh }
            var usesStereoUpDown: Bool { self == .stereoUpDown16IntersectAdd }
        }

        let profile: Profile
        let barCount: Int
        let barSpacing: Float
        let lowerBound: Float
        let upperBound: Float
        let opacity: Float
        let antiAliasSmoothing: SIMD2<Float>
    }

    enum Profile: Sendable {
        case enhancedSegmented(shape: Int)
        case simple(SimpleParameters)
    }

    let profile: Profile

    var shape: Int {
        guard case .enhancedSegmented(let shape) = profile else { return 0 }
        return shape
    }

    func resolvedSimpleParameters(
        in snapshot: SceneDynamicSnapshot
    ) -> (parameters: SimpleParameters, color: SIMD3<Float>, opacity: Float)? {
        guard case .simple(let parameters) = profile else { return nil }
        return (parameters, SIMD3(repeating: 1), parameters.opacity)
    }
}

struct SceneWorkshopGradientExecutionPlan: Sendable {
    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
}

struct SceneWorkshopAudioHueShiftExecutionPlan: Sendable {
    let audio: SceneAudioResponse.Parameters
}

struct SceneAuthoredShaderExecutionPlan: Sendable {
    enum Profile: Sendable {
        case genericFramebuffer
        case scroll

        var stableName: String {
            switch self {
            case .genericFramebuffer: "generic-framebuffer"
            case .scroll: "scroll"
            }
        }
    }

    let offscreenSize: CGSize?
    let profile: Profile

    init(
        offscreenSize: CGSize?,
        profile: Profile = .genericFramebuffer
    ) {
        self.offscreenSize = offscreenSize
        self.profile = profile
    }

    func offscreenSize(for requestedSize: CGSize) -> CGSize? { offscreenSize }
}

struct SceneAuthoredShaderFrameInputs: Sendable {}

final class SceneAuthoredShaderPipelineCache {
    init?(device: MTLDevice) {}
}

enum SceneAuthoredShaderRenderer {
    static func encode(
        plan: SceneAuthoredShaderExecutionPlan,
        source: MTLTexture,
        target: MTLTexture,
        frame: SceneAuthoredShaderFrameInputs,
        pipelineCache: SceneAuthoredShaderPipelineCache,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        false
    }
}

// 与 SceneOpacityEffectTextureLoader.swift 里的同名结构保持一致的替身：那个文件还依赖
// SceneTexturePathResolver/SceneTextureLoader，整条链拉进来会和本 harness 自带的
// SceneRenderDescriptor 桩冲突，沿用本文件对 SceneShakeEffectTextures 等的同类做法。
struct SceneOpacityEffectTextures {
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    let maskPath: String

    func matches(_ plan: SceneOpacityExecutionPlan) -> Bool {
        mask != nil && normalized(maskPath) == plan.maskTexturePath.map(normalized)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneBlendShaderProfile {
    case legacySingleTexture
}

struct SceneBlendExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let shaderProfile: SceneBlendShaderProfile
    let blendMode: Int
    let multiply: Float
    let alphaMultiply: Float
    let writesAlpha: Bool
    let assetTexturePath: String
    let userPropertyKey: String?

    func resolvedMultiply(in snapshot: SceneDynamicSnapshot) -> Float {
        multiply
    }
}

struct SceneTransformExecutionPlan {
    let renderGraph: SceneAuthoredEffectRenderPlan
}

struct SceneFisheyeZeroDistortionPlan {
    let renderGraph: SceneAuthoredEffectRenderPlan
    let center: SIMD2<Float>
    let size: Float
}

struct SceneBlendEffectTextures {
    struct ResolvedArguments {
        let blend: SceneTextureSlotBinding
        let uvScale: SIMD2<Float>
    }

    let blendBinding: SceneTextureSlotBinding?
    let assetPath: String
    let propertyKey: String?

    func resolvedArguments(for plan: SceneBlendExecutionPlan) -> ResolvedArguments? {
        guard normalized(assetPath) == normalized(plan.assetTexturePath),
              propertyKey == plan.userPropertyKey,
              let blendBinding,
              let uvScale = blendBinding.axisAlignedUVScale(
                  expectedSlotIndex: 1,
                  expectedPurpose: .premultipliedColor,
                  allowedPixelFormats: [.rgba8Unorm, .bgra8Unorm]
              ) else {
            return nil
        }
        return ResolvedArguments(blend: blendBinding, uvScale: uvScale)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

struct SceneLightShaftsEffectTextures {
    let noise: MTLTexture?
    let gradient: MTLTexture?
    let noisePath: String
    let gradientPath: String

    func matches(_ plan: SceneLightShaftsExecutionPlan) -> Bool {
        guard noise != nil,
              normalized(noisePath) == normalized(plan.noiseTexturePath) else {
            return false
        }
        return !plan.profile.requiresGradientTexture
            || (
                gradient != nil
                    && normalized(gradientPath) == normalized(plan.gradientTexturePath)
            )
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

struct SceneAuthoredEffectExecutionPlan {
    enum Backend {
        case preciseGaussian(SceneGaussianBlurPlan)
        case standardBlur(SceneStandardBlurPlan)
        case localContrast(SceneLocalContrastPlan)
        case opacity(SceneOpacityExecutionPlan)
        case colorKey(SceneColorKeyExecutionPlan)
        case colorGrading(SceneColorGradingExecutionPlan)
        case workshopShiftHue(SceneWorkshopShiftHueExecutionPlan)
        case workshopAudioBars(SceneWorkshopAudioBarsExecutionPlan)
        case workshopGradient(SceneWorkshopGradientExecutionPlan)
        case workshopAudioHueShift(SceneWorkshopAudioHueShiftExecutionPlan)
        case workshopShadow(SceneWorkshopShadowExecutionPlan)
        case spin(SceneSpinExecutionPlan)
        case proceduralNoise(SceneProceduralNoiseExecutionPlan)
        case filmGrain(SceneFilmGrainExecutionPlan)
        case lightShafts(SceneLightShaftsExecutionPlan)
        case shake(SceneShakeExecutionPlan)
        case waterFlow(SceneWaterFlowExecutionPlan)
        case waterWaves(SceneWaterWavesExecutionPlan)
        case waterCaustics(SceneWaterCausticsExecutionPlan)
        case cursorRipple(SceneCursorRippleExecutionPlan)
        case foliageSway(SceneFoliageSwayExecutionPlan)
        case waterRipple(SceneWaterRippleExecutionPlan)
        case depthParallax(SceneDepthParallaxExecutionPlan)
        case xRay(SceneXRayExecutionPlan)
        case clippingMask(SceneClippingMaskExecutionPlan)
        case blend(SceneBlendExecutionPlan)
        case tint(SceneTintExecutionPlan)
        case transform(SceneTransformExecutionPlan)
        case fisheyeZeroDistortion(SceneFisheyeZeroDistortionPlan)
        case pulse(ScenePulseExecutionPlan)
        case godrays(SceneGodraysPlan)
        case shine(SceneShineExecutionPlan)
        case authoredShader(SceneAuthoredShaderExecutionPlan)

        var stableName: String {
            switch self {
            case .preciseGaussian: "precise-gaussian"
            case .standardBlur: "standard-blur"
            case .localContrast: "local-contrast"
            case .opacity: "opacity"
            case .colorKey: "color-key"
            case .colorGrading: "color-grading"
            case .workshopShiftHue: "workshop-shift-hue"
            case .workshopAudioBars: "workshop-audio-bars"
            case .workshopGradient: "workshop-gradient"
            case .workshopAudioHueShift: "workshop-audio-hue-shift"
            case .workshopShadow: "workshop-shadow"
            case .spin: "spin"
            case .proceduralNoise: "procedural-noise"
            case .filmGrain: "film-grain"
            case .lightShafts: "light-shafts"
            case .shake: "shake"
            case .waterFlow: "water-flow"
            case .waterWaves: "water-waves"
            case .waterCaustics: "water-caustics"
            case .cursorRipple: "cursor-ripple"
            case .foliageSway: "foliage-sway"
            case .waterRipple: "water-ripple"
            case .depthParallax: "depth-parallax"
            case .xRay: "x-ray"
            case .clippingMask: "clipping-mask"
            case .blend: "blend"
            case .tint: "tint"
            case .transform: "transform"
            case .fisheyeZeroDistortion: "fisheye-zero-distortion"
            case .pulse: "pulse"
            case .godrays: "godrays"
            case .shine: "shine"
            case .authoredShader: "authored-shader"
            }
        }
    }

    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let backend: Backend
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    let usesLegacyComposeNormalization: Bool

    init(
        layerID: Int,
        renderGraph: SceneAuthoredEffectRenderPlan,
        backend: Backend,
        materialNodeCount: Int,
        logicalRenderTargetCount: Int,
        inputRole: SceneAuthoredEffectInputRole = .layerSource,
        usesLegacyComposeNormalization: Bool = false
    ) {
        self.layerID = layerID
        self.renderGraph = renderGraph
        self.backend = backend
        self.materialNodeCount = materialNodeCount
        self.logicalRenderTargetCount = logicalRenderTargetCount
        self.inputRole = inputRole
        self.usesLegacyComposeNormalization = usesLegacyComposeNormalization
    }

    var gaussianBlur: SceneGaussianBlurPlan? {
        guard case .preciseGaussian(let plan) = backend else { return nil }
        return plan
    }

    var standardBlur: SceneStandardBlurPlan? {
        guard case .standardBlur(let plan) = backend else { return nil }
        return plan
    }

    var localContrast: SceneLocalContrastPlan? {
        guard case .localContrast(let plan) = backend else { return nil }
        return plan
    }

    var opacity: SceneOpacityExecutionPlan? {
        guard case .opacity(let plan) = backend else { return nil }
        return plan
    }

    var cursorRipple: SceneCursorRippleExecutionPlan? {
        guard case .cursorRipple(let plan) = backend else { return nil }
        return plan
    }

    var depthParallax: SceneDepthParallaxExecutionPlan? {
        guard case .depthParallax(let plan) = backend else { return nil }
        return plan
    }

    var clippingMask: SceneClippingMaskExecutionPlan? {
        guard case .clippingMask(let plan) = backend else { return nil }
        return plan
    }

    var authoredShader: SceneAuthoredShaderExecutionPlan? {
        guard case .authoredShader(let plan) = backend else { return nil }
        return plan
    }

    var executionFamilyStableName: String {
        authoredShader?.profile.stableName ?? backend.stableName
    }

    var blend: SceneBlendExecutionPlan? {
        guard case .blend(let plan) = backend else { return nil }
        return plan
    }

    var workshopShadow: SceneWorkshopShadowExecutionPlan? {
        guard case .workshopShadow(let plan) = backend else { return nil }
        return plan
    }

    var workshopAudioBars: SceneWorkshopAudioBarsExecutionPlan? {
        guard case .workshopAudioBars(let plan) = backend else { return nil }
        return plan
    }

    var waterWaves: SceneWaterWavesExecutionPlan? {
        guard case .waterWaves(let plan) = backend else { return nil }
        return plan
    }

    var waterCaustics: SceneWaterCausticsExecutionPlan? {
        guard case .waterCaustics(let plan) = backend else { return nil }
        return plan
    }

    var requiresExactInputExtent: Bool {
        if case .preciseGaussian = backend { return !usesLegacyComposeNormalization }
        return false
    }

    func localContrastStrength(in snapshot: SceneDynamicSnapshot) -> Float? {
        guard let localContrast else { return nil }
        let effectIndex = renderGraph.effects.first?.key.effectIndex ?? -1
        return snapshot.strengthsByEffectIndex[effectIndex]
            ?? localContrast.staticOrFallbackStrength
    }

    func opacityAlpha(in snapshot: SceneDynamicSnapshot) -> Float? {
        opacity?.resolvedAlpha(in: snapshot)
    }

    func acceptsPreciseBlurHorizontalBindings(
        _ bindings: [SceneAuthoredEffectRenderPlan.Binding],
        effectInput: SceneAuthoredEffectRenderPlan.TextureIdentity
    ) -> Bool {
        if usesLegacyComposeNormalization {
            return bindings.count == 1
                && bindings.first?.slot == 0
                && bindings.first?.texture == effectInput
        }
        return bindings.isEmpty
    }
}

struct SceneShakeExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    var audio: SceneAudioResponse.Parameters? = nil
}

struct SceneShakeEffectTextures {}

struct SceneSpotLightPipeline {
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {}
}

struct SceneFilmGrainEffectTextures {
    let noise: MTLTexture?
    let noisePath: String

    func matches(_ plan: SceneFilmGrainExecutionPlan) -> Bool {
        noise != nil && noisePath == plan.noiseTexturePath
    }
}

struct SceneShakePipeline {
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {}
}

enum SceneShakeRenderer {
    static func render(
        plan: SceneShakeExecutionPlan,
        resources: SceneShakeEffectTextures,
        time: Float,
        audioPulse: Float?,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        pipeline: SceneShakePipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        nil
    }
}

struct SceneWaterFlowExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}

struct SceneWaterFlowEffectTextures {}

struct SceneWaterFlowPipeline {
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {}
}

enum SceneWaterFlowRenderer {
    static func renderCaptured(
        plan: SceneWaterFlowExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        waterFlowPipeline: SceneWaterFlowPipeline,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        nil
    }
}

struct SceneWaterWavesExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}

struct SceneWaterWavesEffectTextures {}

struct SceneWaterCausticsExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}

struct SceneWaterCausticsEffectTextures {}

struct SceneWaterCausticsPipeline {
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {}
}

struct SceneWaterWavesPipeline {
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {}
}

enum SceneWaterWavesRenderer {
    static func renderCaptured(
        plan: SceneWaterWavesExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        waterWavesPipeline: SceneWaterWavesPipeline,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        nil
    }
}

struct SceneCursorRippleExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}
struct SceneCursorRippleEffectTextures {}

struct SceneCursorRipplePipeline {
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {}
}

enum SceneCursorRippleRenderer {
    static func renderCaptured(
        plan: SceneCursorRippleExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        cursorRipplePipeline: SceneCursorRipplePipeline,
        currentCursorUV: SIMD2<Float>,
        previousCursorUV: SIMD2<Float>,
        pointerIsInside: Bool,
        previousPointerIsInside: Bool,
        frameTime: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        nil
    }
}

struct SceneFoliageSwayExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}
struct SceneFoliageSwayEffectTextures {}
struct SceneFoliageSwayPipeline {
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {}
}

enum SceneFoliageSwayRenderer {
    static func render(
        plan: SceneFoliageSwayExecutionPlan,
        sourceTexture: MTLTexture,
        resources: SceneFoliageSwayEffectTextures,
        target: MTLTexture,
        time: Float,
        pipeline: SceneFoliageSwayPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        nil
    }
}

struct SceneDepthParallaxExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}
struct SceneDepthParallaxEffectTextures {}
struct SceneDepthParallaxPipeline {
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {}
}

extension SceneAuthoredEffectChainRenderer {
    static func renderWaterCaustics(
        _ plan: SceneWaterCausticsExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        auxMask: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? { nil }

    static func renderDepthParallax(
        _ depthParallax: SceneDepthParallaxExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        auxMask: MTLTexture?,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        pipelines: SceneAuthoredEffectPipelineSet,
        cursorUV: SIMD2<Float>,
        pointerIsInside: Bool,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        nil
    }
}

struct SceneWaterRippleExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let runtimePlan: SceneWaterRippleNormalPlan
}
struct SceneWaterRippleEffectTextures {
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    let normal: MTLTexture?

    func matches(_ plan: SceneWaterRippleExecutionPlan) -> Bool { true }
}

enum SceneWaterRippleRenderer {
    static func render(
        plan: SceneWaterRippleExecutionPlan,
        sourceTexture: MTLTexture,
        resources: SceneWaterRippleEffectTextures,
        target: MTLTexture,
        time: Float,
        pipeline: SceneWaterRipplePipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        nil
    }
}

struct SceneTintShaderProfile {
    let maskMultipliesBlendAlpha: Bool

    static let stock = SceneTintShaderProfile(maskMultipliesBlendAlpha: true)
}

struct SceneTintExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let shaderProfile: SceneTintShaderProfile
    let blendMode: Int
    let staticOrFallbackColor: SIMD3<Float>
    let staticOrFallbackAlpha: Float
    let maskTexturePath: String?

    func resolvedColor(in snapshot: SceneDynamicSnapshot) -> SIMD3<Float> {
        staticOrFallbackColor
    }

    func resolvedAlpha(in snapshot: SceneDynamicSnapshot) -> Float {
        staticOrFallbackAlpha
    }
}

struct SceneTintEffectTextures {
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    let maskPath: String?

    func matches(_ plan: SceneTintExecutionPlan) -> Bool {
        guard let planPath = plan.maskTexturePath else { return maskPath == nil }
        return mask != nil && maskPath == planPath
    }
}

struct SceneGodraysPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let firstHalfTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    let secondHalfTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    let maskTexturePath: String?
}

struct SceneGodraysEffectTextures {
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    let maskPath: String?
    let noise: MTLTexture?

    func matches(_ plan: SceneGodraysPlan) -> Bool {
        noise != nil && (plan.maskTexturePath == nil ? maskPath == nil : mask != nil)
    }
}

struct SceneGodraysPipeline {
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {}
}

enum SceneGodraysRenderer {
    static func renderCaptured(
        plan: SceneGodraysPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        godraysPipeline: SceneGodraysPipeline,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        nil
    }
}

struct SceneShineExecutionPlan {}
struct SceneShineEffectTextures {}

struct SceneShinePipeline {
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {}
}

enum SceneShineRenderer {
    static func renderCaptured(
        plan: SceneShineExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
        targets: SceneGraphRenderTargetTable,
        sourceUniforms: SceneLayerFragmentUniforms,
        sourcePipeline: SceneImageLayerPipeline,
        shinePipeline: SceneShinePipeline,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        nil
    }
}

struct ScenePulseShaderProfile {
    let phaseOffset: Float
    let noiseUVScale: SIMD2<Float>
    let saturatesOutput: Bool

    static let stock = ScenePulseShaderProfile(
        phaseOffset: -1.57079632679,
        noiseUVScale: SIMD2(0.08333333, 0.02777777),
        saturatesOutput: false
    )
}

struct ScenePulseExecutionPlan {
    enum Constant: String {
        case speed, phase, amount, bounds, power
        case noiseSpeed = "noisespeed"
        case noiseAmount = "noiseamount"
        case tintLow = "tintlow"
        case tintHigh = "tinthigh"
    }

    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let shaderProfile: ScenePulseShaderProfile
    let blendMode: Int
    let pulseColor: Bool
    let pulseAlpha: Bool
    let maskTexturePath: String?
    let requiresNoiseTexture: Bool
    let values: [Constant: SIMD3<Double>]
    var audio: SceneAudioResponse.Parameters? = nil

    func resolvedComponents(
        _ constant: Constant,
        in snapshot: SceneDynamicSnapshot
    ) -> SIMD3<Double> {
        values[constant] ?? SIMD3(repeating: 0)
    }
}

struct ScenePulseEffectTextures {
    let noise: MTLTexture?
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    let maskPath: String?

    func matches(_ plan: ScenePulseExecutionPlan) -> Bool {
        let maskSatisfied = plan.maskTexturePath.map { path in
            mask != nil && normalized(maskPath ?? "") == normalized(path)
        } ?? true
        return maskSatisfied && (!plan.requiresNoiseTexture || noise != nil)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

struct SceneAuthoredEffectExecutionChain {
    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let stages: [SceneAuthoredEffectExecutionPlan]

    var irisInlineSuffix: SceneIrisInlineSuffixPlan? { nil }

    var singleStage: SceneAuthoredEffectExecutionPlan? {
        stages.count == 1 ? stages[0] : nil
    }

    var clippingMaskCount: Int {
        stages.filter { $0.clippingMask != nil }.count
    }

    func authoredShaderOffscreenSize(for requestedSize: CGSize) -> CGSize? {
        stages.compactMap { $0.authoredShader?.offscreenSize(for: requestedSize) }.min {
            $0.width * $0.height < $1.width * $1.height
        }
    }
}

struct SceneIrisInlineSuffixPlan {
    let effectKey = SceneAuthoredEffectRenderPlan.EffectKey(
        layerID: 0,
        effectIndex: 0,
        descriptorID: "framebuffer-harness-iris"
    )
    var inputs: SceneLayerEffectInputs { .neutral }
}

struct SceneDynamicSnapshot {
    let strengthsByEffectIndex: [Int: Float]
    let opacitiesByEffectIndex: [Int: Float]

    static func empty(frameIndex: UInt64, generation: UInt64 = 0) -> Self {
        Self(strengthsByEffectIndex: [:], opacitiesByEffectIndex: [:])
    }
}

struct SceneXRayEffectTextures {
    let blend: MTLTexture
    let halo: MTLTexture?
    let opacityMask: MTLTexture?
}

enum SceneXRayRuntimeResolution {
    case identity
    case render(SceneXRayRuntimePlan)
    case unsupported
}

struct SceneXRayRuntimePlan {
    let layerID: Int
    let effectIndex: Int
    let effectID: String
    let blendTexturePath: String
    let opacityMaskPath: String?
    let size: Float
    let multiply: Float
    let blendUVScale: SIMD2<Float>
    let opacityUVScale: SIMD2<Float>
}

struct SceneXRayExecutionPlan {
    let declaration: SceneXRayRuntimePlanner.Declaration
}

enum SceneXRayRuntimePlanner {
    struct Declaration {}

    static func resolve(
        declaration: Declaration,
        resources: SceneXRayEffectTextures?,
        snapshot: SceneDynamicSnapshot,
        pointerIsInside: Bool
    ) -> SceneXRayRuntimeResolution {
        guard pointerIsInside else { return .identity }
        guard resources != nil else { return .unsupported }
        return .render(SceneXRayRuntimePlan(
            layerID: 2998757800,
            effectIndex: 5,
            effectID: "2998757800#effect#5",
            blendTexturePath: "materials/xray/blend",
            opacityMaskPath: "materials/xray/opacity",
            size: 1,
            multiply: 1,
            blendUVScale: SIMD2(repeating: 1),
            opacityUVScale: SIMD2(repeating: 1)
        ))
    }
}

struct SceneStandardBlurPlan {
    let horizontalStep: Float
    let verticalStep: Float
    let renderTargetScale: Int
    let effectDescriptorID: String
    let maskTexturePath: String?

    init(
        horizontalStep: Float,
        verticalStep: Float,
        renderTargetScale: Int,
        effectDescriptorID: String = "",
        maskTexturePath: String? = nil
    ) {
        self.horizontalStep = horizontalStep
        self.verticalStep = verticalStep
        self.renderTargetScale = renderTargetScale
        self.effectDescriptorID = effectDescriptorID
        self.maskTexturePath = maskTexturePath
    }
}

enum SceneTextureLoadPurpose: Hashable {
    case premultipliedColor
    case straightAlbedo
    case preservedChannels
    case mask
    case noise
    case flow
    case phase
    case normal
    case depth
    case lookupTable

    var requiresVolumeTexture: Bool {
        self == .lookupTable
    }
}

struct SceneStandardBlurEffectTextures {
    let maskCandidate: SceneTextureCandidate?
    let maskPath: String

    func matches(_ plan: SceneStandardBlurPlan) -> Bool {
        // Keep this harness gate deliberately weaker than production so a
        // wrong-purpose candidate reaches the production Offscreen renderer's
        // own typed-purpose guard.
        maskCandidate != nil && maskPath == plan.maskTexturePath
    }
}

struct SceneLocalContrastPlan {
    let firstQuarterTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    let secondQuarterTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    let renderGraph: SceneAuthoredEffectRenderPlan
    let staticOrFallbackStrength: Float
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static let authoredBlendLayerID = 852
    static let authoredBlendEffectID = "852#effect#0"
    static let authoredBlendAssetPath = "materials/authored_blend_test.tex"

    static func graphTexture(
        _ kind: Graph.TextureKind,
        layerID: Int,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func preciseBlurGraph(
        layerID: Int = 10,
        commandKind: Graph.NodeKind? = nil,
        legacyCompose: Bool = false
    ) -> Graph {
        let effectKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "\(layerID)#effect#0"
        )
        let input = graphTexture(.layerSource, layerID: layerID)
        let output = graphTexture(.effectOutput, layerID: layerID, effect: effectKey)
        let first = graphTexture(
            .framebuffer,
            layerID: layerID,
            effect: effectKey,
            name: "first"
        )
        let second = graphTexture(
            .framebuffer,
            layerID: layerID,
            effect: effectKey,
            name: "second"
        )
        let verticalInput = commandKind == nil ? first : second
        let horizontal = Graph.Node(
            nodeIndex: 0,
            effect: effectKey,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: "materials/blur_precise_x.json",
            materialPassID: "materials/blur_precise_x.json#0",
            target: first,
            bindings: legacyCompose
                ? [.init(slot: 0, authoredName: "previous", texture: input, conditions: nil)]
                : [],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
        let vertical = Graph.Node(
            nodeIndex: commandKind == nil ? 1 : 2,
            effect: effectKey,
            definitionPassIndex: commandKind == nil ? 1 : 2,
            materialOrdinal: 1,
            instancePassIndex: 1,
            kind: .material,
            materialPath: "materials/blur_precise_y.json",
            materialPassID: "materials/blur_precise_y.json#0",
            target: output,
            bindings: [
                .init(
                    slot: 0,
                    authoredName: verticalInput.name,
                    texture: verticalInput,
                    conditions: nil
                ),
            ] + (!legacyCompose ? [
                .init(slot: 1, authoredName: "previous", texture: input, conditions: nil),
            ] : []),
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
        var nodes = [horizontal]
        if let commandKind {
            nodes.append(Graph.Node(
                nodeIndex: 1,
                effect: effectKey,
                definitionPassIndex: 1,
                materialOrdinal: nil,
                instancePassIndex: nil,
                kind: commandKind,
                materialPath: nil,
                materialPassID: nil,
                target: nil,
                bindings: [],
                commandSource: first,
                commandTarget: second,
                compose: nil,
                conditions: nil
            ))
        }
        nodes.append(vertical)
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath: "effects/blurprecise/effect.json",
            input: input,
            output: output,
            nodeIndices: nodes.map(\.nodeIndex)
        )
        var renderTargets = [
            Graph.RenderTarget(
                texture: first,
                extent: legacyCompose
                    ? .init(kind: .scale, first: 1, second: nil)
                    : .init(kind: .input, first: nil, second: nil),
                format: "rgba_backbuffer",
                declaredUnique: false,
                clear: nil,
                uvs: nil,
                conditions: nil
            ),
        ]
        if let commandKind {
            renderTargets.append(.init(
                texture: second,
                extent: .init(kind: .input, first: nil, second: nil),
                format: "rgba_backbuffer",
                declaredUnique: commandKind == .swap,
                clear: nil,
                uvs: nil,
                conditions: nil
            ))
        }
        return Graph(
            layerID: layerID,
            effects: [effect],
            renderTargets: renderTargets,
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
    }

    static func standardBlurGraph(
        layerID: Int = 530,
        effectIndex: Int = 0,
        input priorOutput: Graph.TextureIdentity? = nil
    ) -> Graph {
        let effectKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: "\(layerID)#effect#\(effectIndex)"
        )
        let input = priorOutput ?? graphTexture(.layerSource, layerID: layerID)
        let output = graphTexture(.effectOutput, layerID: layerID, effect: effectKey)
        let quarterA = graphTexture(
            .framebuffer,
            layerID: layerID,
            effect: effectKey,
            name: "_rt_QuarterCompoBuffer1"
        )
        let quarterB = graphTexture(
            .framebuffer,
            layerID: layerID,
            effect: effectKey,
            name: "_rt_QuarterCompoBuffer2"
        )
        let materialPaths = [
            "materials/effects/blur_downsample4.json",
            "materials/effects/blur_gaussian_x.json",
            "materials/effects/blur_gaussian_y.json",
            "materials/effects/blur_combine.json",
        ]
        let targets = [quarterA, quarterB, quarterA, output]
        let bindings: [[Graph.Binding]] = [
            [.init(slot: 0, authoredName: "previous", texture: input, conditions: nil)],
            [.init(slot: 0, authoredName: quarterA.name, texture: quarterA, conditions: nil)],
            [.init(slot: 0, authoredName: quarterB.name, texture: quarterB, conditions: nil)],
            [
                .init(slot: 0, authoredName: quarterA.name, texture: quarterA, conditions: nil),
                .init(slot: 2, authoredName: "previous", texture: input, conditions: nil),
            ],
        ]
        let nodes = materialPaths.indices.map { index in
            Graph.Node(
                nodeIndex: (effectIndex * materialPaths.count) + index,
                effect: effectKey,
                definitionPassIndex: index,
                materialOrdinal: index,
                instancePassIndex: index,
                kind: .material,
                materialPath: materialPaths[index],
                materialPassID: "\(materialPaths[index])#0",
                target: targets[index],
                bindings: bindings[index],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            )
        }
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath: "effects/blur/effect.json",
            input: input,
            output: output,
            nodeIndices: materialPaths.indices.map { (effectIndex * materialPaths.count) + $0 }
        )
        return Graph(
            layerID: layerID,
            effects: [effect],
            // Declaration order is intentionally not execution order.
            renderTargets: [quarterB, quarterA].map { texture in
                .init(
                    texture: texture,
                    extent: .init(kind: .scale, first: 4, second: nil),
                    format: "rgba_backbuffer",
                    declaredUnique: false,
                    clear: nil,
                    uvs: nil,
                    conditions: nil
                )
            },
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
    }

    static func authoredPreciseBlurPlan(
        commandKind: Graph.NodeKind? = nil,
        legacyCompose: Bool = false
    ) -> SceneAuthoredEffectExecutionPlan {
        let graph = preciseBlurGraph(
            commandKind: commandKind,
            legacyCompose: legacyCompose
        )
        return SceneAuthoredEffectExecutionPlan(
            layerID: graph.layerID,
            renderGraph: graph,
            backend: .preciseGaussian(SceneGaussianBlurPlan(
                horizontalStep: 1,
                verticalStep: 1,
                sampleResolutionScale: 1,
                isPrecise: true
            )),
            materialNodeCount: 2,
            logicalRenderTargetCount: graph.renderTargets.count,
            usesLegacyComposeNormalization: legacyCompose
        )
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.deviceUnavailable
        }
        guard let queue = device.makeCommandQueue() else {
            throw HarnessError.queueUnavailable
        }
        guard let pipeline = SceneImageLayerPipeline(device: device) else {
            throw HarnessError.imagePipelineUnavailable
        }
        guard let imageBlendPipeline = SceneImageBlendPipeline(device: device) else {
            throw HarnessError.imageBlendPipelineUnavailable
        }
        guard let compositor = SceneImageLayerCompositor(device: device) else {
            throw HarnessError.compositorUnavailable
        }
        guard let source = makeTexture(device: device, size: 8, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 8, usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.baseTextureUnavailable
        }
        fillQuadrants(source)

        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 1)
        )
        guard let baseEncoder = mainPass.encoder() else { throw HarnessError.encoderUnavailable }
        pipeline.bind(encoder: baseEncoder)
        pipeline.drawLayer(
            texture: source,
            shakeMaskTexture: nil,
            waterMaskTexture: nil,
            foliageMaskTexture: nil,
            auxMaskTexture: nil,
            mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
            uniforms: .neutral(),
            encoder: baseEncoder
        )

        let layer = SceneRenderDescriptor.Layer(
            contentKind: "composition",
            colorRGB: nil,
            colorBlendMode: nil,
            effects: []
        )
        let pool = SceneOffscreenTexturePool(device: device)
        let refusedWithoutPool = mainPass.withReadableTarget { readableTarget, _ in
            compositor.draw(
                SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: readableTarget,
                    masks: .empty,
                    textureFrame: .identity,
                    mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                    uniforms: SceneImageLayerUniformValues(
                        time: 0, alpha: 1, cursorUV: .zero
                    ),
                    offscreenTexturePool: nil,
                    offscreenSize: nil,
                    requiresSourceCopy: true,
                    finalCompositeAlpha: 1,
                    dependencyEffect: nil,
                    authoredEffectPlan: nil,
                    blocksLegacyGaussianBlur: false
                ),
                pipeline: pipeline,
                mainPass: mainPass
            )
        } ?? true
        let drew = mainPass.withReadableTarget { readableTarget, _ in
            compositor.draw(
                SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: readableTarget,
                    masks: .empty,
                    textureFrame: SceneTextureUVTransform(
                        origin: .zero,
                        xAxis: SIMD2(0.5, 0),
                        yAxis: SIMD2(0, 0.5)
                    ),
                    mvp: SceneMatrix.scale(SIMD3<Float>(1, 1, 1)),
                    uniforms: SceneImageLayerUniformValues(
                        time: 0, alpha: 1, cursorUV: .zero
                    ),
                    offscreenTexturePool: pool,
                    offscreenSize: CGSize(width: 4, height: 4),
                    requiresSourceCopy: true,
                    finalCompositeAlpha: 1,
                    dependencyEffect: nil,
                    authoredEffectPlan: nil,
                    blocksLegacyGaussianBlur: false
                ),
                pipeline: pipeline,
                mainPass: mainPass
            )
        } ?? false
        let telemetry = SceneGPUCompletionTelemetry(phase: "utility-capture")
        telemetry.record(layerID: 701, encoded: drew, on: commandBuffer)
        telemetry.record(layerID: 702, encoded: false, on: commandBuffer)
        telemetry.record(layerID: 703, encoded: false, on: commandBuffer)
        telemetry.record(layerID: 703, encoded: true, on: commandBuffer)
        let telemetryHandlersCompleted = DispatchSemaphore(value: 0)
        commandBuffer.addCompletedHandler { _ in
            telemetryHandlersCompleted.signal()
        }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        guard telemetryHandlersCompleted.wait(timeout: .now() + 5) == .success else {
            throw HarnessError.telemetryCompletionTimedOut
        }
        let telemetryEvidence: [String: Any] = [
            "completionHandler": gpuTelemetrySnapshotEvidence(telemetry.snapshot(layerID: 701)),
            "encodingFailure": gpuTelemetrySnapshotEvidence(telemetry.snapshot(layerID: 702)),
            "failureThenCompletion": gpuTelemetrySnapshotEvidence(
                telemetry.snapshot(layerID: 703)
            ),
            "reducer": gpuTelemetryReducerEvidence(),
        ]

        let noDependency = try dependencyBlendPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            blendMode: nil, alpha: 1
        )
        let normalDependency = try dependencyBlendPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            blendMode: 0, alpha: 1
        )
        let darkenDependency = try dependencyBlendPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            blendMode: 5, alpha: 1
        )
        let darkenHalfAlpha = try dependencyBlendPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            blendMode: 5, alpha: 0.5
        )
        let authoredClippingMask = try authoredClippingMaskPixel(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredCompositionClippingMask = try authoredClippingMaskPixel(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor,
            contentKind: "composition"
        )
        let solidTint = try layerTintPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            contentKind: "solid"
        )
        let imageTint = try layerTintPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            contentKind: "image"
        )
        let imageBrightness = try layerTintPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            contentKind: "image", brightness: 0.5, tint: SIMD3(repeating: 1)
        )
        let textBrightness = try layerTintPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            contentKind: "text", brightness: 0.5, tint: SIMD3(repeating: 1)
        )
        let vividLayerBlend = try layerColorBlendPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            blendMode: 14
        )
        let warmAdditiveLayerBlend = try layerColorBlendPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            blendMode: 31,
            sourceBGRA: [204, 204, 204, 255],
            background: MTLClearColorMake(0.05, 0.05, 0.05, 1),
            tint: SIMD3<Float>(0.94902, 0.76471, 0.6),
            brightness: 1.25
        )
        let invalidLayerBlendRefused = try layerColorBlendPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            blendMode: 33
        ) == nil
        let coarseBlur = blurPlan(path: "effects/blur/effect.json", scale: 0.6)
        let preciseBlur = blurPlan(path: "effects/blurprecise/effect.json", scale: 0.45)
        let blockedPreciseBlur = blurPlan(
            path: "effects/blurprecise/effect.json",
            scale: 0.45,
            blocksLegacyGaussianBlur: true
        )
        let authoredExtentMismatchRefused = try authoredExtentMismatchIsRefused(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredPreciseImpulse = try authoredPreciseBlurImpulseEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let gaussianKernelPixels = try gaussianKernelEvidence(
            device: device,
            queue: queue
        )
        let authoredLegacyComposeImpulse = try authoredPreciseBlurImpulseEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor,
            legacyCompose: true
        )
        let authoredLegacyComposeScaled = try authoredPreciseBlurImpulseEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor,
            legacyCompose: true,
            sourceSize: 16,
            maxDimension: 8
        )
        let authoredPreciseInterleave = try authoredPreciseInterleaveEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredStandardCheckerboard = try authoredStandardBlurCheckerboardEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredStandardCandidate = try authoredStandardBlurCandidateEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredTwoStageChain = try authoredTwoStageChainEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredOpacityLivePixels = try authoredOpacityLivePixels(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredOpacityMaskPixel = try authoredOpacityMaskPixels(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredBlendChainPixel = try authoredBlendChainPixel(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredWriteAlphaBlendChainPixel = try Self.authoredBlendChainPixel(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor,
            writesAlpha: true,
            alphaMultiply: 0.5
        )
        let authoredTransformChainPixel = try authoredTransformChainPixel(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredBlendRuntimeSummary = authoredBlendRuntimeSummary()
        let authoredTintChainPixels = try authoredTintChainPixels(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredFailedChain = try authoredFailedChainEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredStandardBlurOverridesLegacy = standardBlurOverridesLegacy()
        let standardBlurAlphaAwareDownsample = try alphaAwareDownsamplePixel(
            device: device,
            queue: queue
        )
        let standardBlurMaskPixels = try standardBlurMaskPixels(
            device: device,
            queue: queue
        )
        let foliage = foliageInputs(mode: 0)
        let unsupportedFoliage = foliageInputs(mode: 1)
        let mappedMaskScale = SceneTextureMappedUVScale.resolve(
            physicalWidth: 4096,
            physicalHeight: 4096,
            mappedWidth: 3840,
            mappedHeight: 2160
        )
        let decodedMappedScale = SceneTextureMappedUVScale.resolve(
            physicalWidth: 2048,
            physicalHeight: 2048,
            mappedWidth: 1415,
            mappedHeight: 2047,
            sampledWidth: 1415,
            sampledHeight: 2047
        )
        let imageBlend = try imageBlendPixel(
            device: device,
            queue: queue,
            pipeline: imageBlendPipeline,
            multiply: 1
        )
        let halfImageBlend = try imageBlendPixel(
            device: device,
            queue: queue,
            pipeline: imageBlendPipeline,
            multiply: 0.5
        )
        let partialAlphaImageBlend = try partialAlphaImageBlendPixel(
            device: device,
            queue: queue,
            pipeline: imageBlendPipeline
        )
        let standaloneGradientPixels = try gradientPixels(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor,
            sourceBGRA: [255, 255, 255, 255],
            dependencyBGRA: nil
        )
        let clippedGradientPixels = try gradientPixels(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor,
            sourceBGRA: [128, 128, 128, 128],
            dependencyBGRA: [0, 255, 0, 255]
        )
        let solidMappedEffectExtent = try solidMappedEffectExtentEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let xRayThreeTextureRoute = try xRayThreeTextureRouteEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let filmGrain = try filmGrainEvidence(device: device, queue: queue)
        let baseColorCandidate = try baseColorCandidateEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )

        let result: [String: Any] = [
            "drew": drew,
            "refusedWithoutPool": refusedWithoutPool,
            "centerBGRA": pixel(target, x: 4, y: 4),
            "bottomRightBGRA": pixel(target, x: 7, y: 7),
            "noDependencyBGRA": noDependency,
            "normalDependencyBGRA": normalDependency,
            "darkenDependencyBGRA": darkenDependency,
            "darkenHalfAlphaBGRA": darkenHalfAlpha,
            "authoredClippingMaskBGRA": authoredClippingMask,
            "authoredCompositionClippingMaskBGRA": authoredCompositionClippingMask,
            "solidTintBGRA": solidTint,
            "imageTintBGRA": imageTint,
            "imageBrightnessBGRA": imageBrightness,
            "textBrightnessBGRA": textBrightness,
            "vividLayerBlendBGRA": vividLayerBlend as Any,
            "warmAdditiveLayerBlendBGRA": warmAdditiveLayerBlend as Any,
            "invalidLayerBlendRefused": invalidLayerBlendRefused,
            "fragmentUniformSize": MemoryLayout<SceneLayerFragmentUniforms>.size,
            "dependencyBlendModeOffset": MemoryLayout<SceneLayerFragmentUniforms>.offset(
                of: \SceneLayerFragmentUniforms.dependencyBlendMode
            ) ?? -1,
            "coarseBlur": [
                coarseBlur?.horizontalStep ?? -1,
                coarseBlur?.verticalStep ?? -1,
                coarseBlur?.sampleResolutionScale ?? -1,
            ],
            "coarseBlurIsPrecise": coarseBlur?.isPrecise ?? true,
            "preciseBlur": [
                preciseBlur?.horizontalStep ?? -1,
                preciseBlur?.verticalStep ?? -1,
                preciseBlur?.sampleResolutionScale ?? -1,
            ],
            "preciseBlurIsPrecise": preciseBlur?.isPrecise ?? false,
            "blockedPreciseBlurIsNil": blockedPreciseBlur == nil,
            "authoredExtentMismatchRefused": authoredExtentMismatchRefused,
            "authoredPreciseImpulse": authoredPreciseImpulse,
            "gaussianKernelPixels": gaussianKernelPixels,
            "authoredLegacyComposeImpulse": authoredLegacyComposeImpulse,
            "authoredLegacyComposeScaled": authoredLegacyComposeScaled,
            "authoredPreciseInterleave": authoredPreciseInterleave,
            "authoredStandardCheckerboard": authoredStandardCheckerboard,
            "authoredStandardCandidate": authoredStandardCandidate,
            "authoredTwoStageChain": authoredTwoStageChain,
            "authoredOpacityLivePixels": authoredOpacityLivePixels,
            "authoredOpacityMaskPixel": authoredOpacityMaskPixel,
            "authoredBlendChainPixel": authoredBlendChainPixel,
            "authoredWriteAlphaBlendChainPixel": authoredWriteAlphaBlendChainPixel,
            "authoredTransformChainPixel": authoredTransformChainPixel,
            "authoredBlendRuntimeSummary": authoredBlendRuntimeSummary as Any,
            "authoredTintChainPixels": authoredTintChainPixels,
            "authoredFailedChain": authoredFailedChain,
            "authoredStandardBlurOverridesLegacy": authoredStandardBlurOverridesLegacy,
            "standardBlurAlphaAwareDownsampleBGRA": standardBlurAlphaAwareDownsample,
            "standardBlurMaskPixels": standardBlurMaskPixels,
            "foliageFlags": foliage.flags.rawValue,
            "foliageParams3": [
                foliage.params3.x, foliage.params3.y, foliage.params3.z, foliage.params3.w,
            ],
            "foliageParams4": [
                foliage.params4.x, foliage.params4.y, foliage.params4.z, foliage.params4.w,
            ],
            "unsupportedFoliageFlags": unsupportedFoliage.flags.rawValue,
            "mappedMaskScale": [mappedMaskScale.x, mappedMaskScale.y],
            "decodedMappedScale": [decodedMappedScale.x, decodedMappedScale.y],
            "imageBlendBGRA": imageBlend,
            "halfImageBlendBGRA": halfImageBlend,
            "partialAlphaImageBlendBGRA": partialAlphaImageBlend,
            "gradientTopBGRA": standaloneGradientPixels[0],
            "gradientBottomBGRA": standaloneGradientPixels[1],
            "clippedGradientTopBGRA": clippedGradientPixels[0],
            "solidMappedEffectExtent": solidMappedEffectExtent,
            "xRayThreeTextureRoute": xRayThreeTextureRoute,
            "filmGrain": filmGrain,
            "baseColorCandidate": baseColorCandidate,
            "gpuCompletionTelemetry": telemetryEvidence,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func gpuTelemetryReducerEvidence() -> [String: Any] {
        var failureThenSuccess = SceneGPUCompletionTelemetryReducer()
        let failureThenSuccessReports = [
            failureThenSuccess.reduce(.encodingFailed)?.rawValue ?? "none",
            failureThenSuccess.reduce(
                .commandBufferCompleted(succeeded: true)
            )?.rawValue ?? "none",
        ]

        var successThenFailure = SceneGPUCompletionTelemetryReducer()
        let firstSuccessReport = successThenFailure.reduce(
            .commandBufferCompleted(succeeded: true)
        )?.rawValue ?? "none"
        let observesAfterFirstSuccess = successThenFailure.needsCommandBufferObservation
        let laterFailureReport = successThenFailure.reduce(
            .commandBufferCompleted(succeeded: false)
        )?.rawValue ?? "none"
        let successThenFailureReports = [
            firstSuccessReport,
            laterFailureReport,
        ]

        var repeated = SceneGPUCompletionTelemetryReducer()
        let repeatedReports = [
            repeated.reduce(.encodingFailed)?.rawValue ?? "none",
            repeated.reduce(.encodingFailed)?.rawValue ?? "none",
            repeated.reduce(.commandBufferCompleted(succeeded: true))?.rawValue ?? "none",
            repeated.reduce(.commandBufferCompleted(succeeded: true))?.rawValue ?? "none",
            repeated.reduce(.commandBufferCompleted(succeeded: false))?.rawValue ?? "none",
        ]

        return [
            "failureThenSuccessReports": failureThenSuccessReports,
            "failureThenSuccess": gpuTelemetrySnapshotEvidence(failureThenSuccess.snapshot),
            "successThenFailureReports": successThenFailureReports,
            "successThenFailure": gpuTelemetrySnapshotEvidence(successThenFailure.snapshot),
            "observesAfterFirstSuccess": observesAfterFirstSuccess,
            "observesAfterBothCommandBufferOutcomes": (
                successThenFailure.needsCommandBufferObservation
            ),
            "repeatedReports": repeatedReports,
            "repeated": gpuTelemetrySnapshotEvidence(repeated.snapshot),
        ]
    }

    static func gpuTelemetrySnapshotEvidence(
        _ snapshot: SceneGPUCompletionTelemetrySnapshot
    ) -> [String: Bool] {
        [
            "encodingFailureObserved": snapshot.encodingFailureObserved,
            "commandBufferSuccessObserved": snapshot.commandBufferSuccessObserved,
            "commandBufferFailureObserved": snapshot.commandBufferFailureObserved,
            "reportedSuccess": snapshot.reportedSuccess,
            "reportedFailure": snapshot.reportedFailure,
        ]
    }

    static func filmGrainEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue
    ) throws -> [String: Any] {
        let noiseDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 8, height: 8, mipmapped: false
        )
        noiseDescriptor.storageMode = .shared
        noiseDescriptor.usage = .shaderRead
        guard let pipeline = SceneFilmGrainPipeline(device: device),
              let source = makeTexture(device: device, size: 8, usage: .shaderRead),
              let noise = device.makeTexture(descriptor: noiseDescriptor),
              let first = makeTexture(
                  device: device, size: 8, usage: [.renderTarget, .shaderRead]
              ),
              let second = makeTexture(
                  device: device, size: 8, usage: [.renderTarget, .shaderRead]
              ) else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: [64, 96, 128, 200])
        fillPixels(noise) { x, y in
            [
                UInt8(128 + ((x * 31 + y * 17) % 128)),
                UInt8(128 + ((x * 13 + y * 47) % 128)),
                UInt8(128 + ((x * 59 + y * 7) % 128)),
                255,
            ]
        }
        let graph = preciseBlurGraph()
        let plan = SceneFilmGrainExecutionPlan(
            layerID: graph.layerID,
            effectKey: graph.effects[0].key,
            renderGraph: graph,
            scale: 12.75,
            strength: 1.79,
            exponent: 3.8,
            blendMode: 14,
            greyscale: false,
            noiseTexturePath: "util/noise"
        )
        func render(_ target: MTLTexture, time: Float) throws -> [UInt8] {
            guard let command = queue.makeCommandBuffer(),
                  pipeline.encode(
                      source: source,
                      noise: noise,
                      target: target,
                      plan: plan,
                      time: time,
                      commandBuffer: command
                  ) else {
                throw HarnessError.drawRefused
            }
            command.commit()
            command.waitUntilCompleted()
            guard command.status == .completed else { throw HarnessError.commandFailed }
            return try textureBytes(target, queue: queue)
        }
        let firstBytes = try render(first, time: 0)
        let secondBytes = try render(second, time: 0.37)
        let sourceBytes = try textureBytes(source, queue: queue)
        let alphaPreserved = stride(from: 3, to: firstBytes.count, by: 4).allSatisfy {
            firstBytes[$0] == sourceBytes[$0]
        }
        let changedRGB = stride(from: 0, to: firstBytes.count, by: 4).filter { offset in
            firstBytes[offset..<(offset + 3)] != sourceBytes[offset..<(offset + 3)]
        }.count
        let animatedRGB = stride(from: 0, to: firstBytes.count, by: 4).filter { offset in
            firstBytes[offset..<(offset + 3)] != secondBytes[offset..<(offset + 3)]
        }.count
        let invalidPlan = SceneFilmGrainExecutionPlan(
            layerID: plan.layerID,
            effectKey: plan.effectKey,
            renderGraph: plan.renderGraph,
            scale: plan.scale,
            strength: plan.strength,
            exponent: plan.exponent,
            blendMode: 13,
            greyscale: plan.greyscale,
            noiseTexturePath: plan.noiseTexturePath
        )
        let invalidRejected = queue.makeCommandBuffer().map {
            !pipeline.encode(
                source: source, noise: noise, target: second,
                plan: invalidPlan, time: 0, commandBuffer: $0
            )
        } ?? false
        return [
            "alphaPreserved": alphaPreserved,
            "changedRGB": changedRGB,
            "animatedRGB": animatedRGB,
            "invalidRejected": invalidRejected,
        ]
    }

    static func baseColorCandidateEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [String: Any] {
        let size = 8
        guard let source = makeTexture(
                  device: device,
                  size: size,
                  usage: .shaderRead,
                  pixelFormat: .rgba8Unorm
              ),
              let other = makeTexture(
                  device: device,
                  size: size,
                  usage: .shaderRead,
                  pixelFormat: .rgba8Unorm
              ),
              let reference = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let accepted = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let rejected = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let effectfulReference = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let effectfulAccepted = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let effectfulRejected = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ) else {
            throw HarnessError.metalUnavailable
        }
        fillPixels(source) { x, y in
            switch (x >= size / 2, y >= size / 2) {
            case (false, false): [64, 32, 16, 128]
            case (true, false): [0, 255, 0, 255]
            case (false, true): [255, 0, 0, 255]
            case (true, true): [0, 0, 255, 255]
            }
        }
        fillPixels(other) { _, _ in [255, 255, 255, 255] }
        let candidate = textureCandidate(
            texture: source,
            purpose: .premultipliedColor,
            name: "base-color"
        )
        let referenceEncoded = try drawBaseColor(
            source: source, candidate: nil, target: reference,
            queue: queue, pipeline: pipeline, compositor: compositor
        )
        let candidateEncoded = try drawBaseColor(
            source: source, candidate: candidate, target: accepted,
            queue: queue, pipeline: pipeline, compositor: compositor
        )
        let wrongPurposeRejected = try !drawBaseColor(
            source: source,
            candidate: textureCandidate(
                texture: source, purpose: .normal, name: "wrong-purpose"
            ),
            target: rejected, queue: queue, pipeline: pipeline, compositor: compositor
        )
        let mismatchedTextureRejected = try !drawBaseColor(
            source: source,
            candidate: textureCandidate(
                texture: other, purpose: .premultipliedColor, name: "wrong-texture"
            ),
            target: rejected, queue: queue, pipeline: pipeline, compositor: compositor
        )
        let nonIdentityRejected = try !drawBaseColor(
            source: source,
            candidate: textureCandidate(
                texture: source, purpose: .premultipliedColor,
                name: "non-identity", mappedWidth: size / 2
            ),
            target: rejected, queue: queue, pipeline: pipeline, compositor: compositor
        )
        let nearestRejected = try !drawBaseColor(
            source: source,
            candidate: textureCandidate(
                texture: source, purpose: .premultipliedColor,
                name: "nearest", sampling: SceneTextureSampling(texFlags: 3)
            ),
            target: rejected, queue: queue, pipeline: pipeline, compositor: compositor
        )
        let repeatRejected = try !drawBaseColor(
            source: source,
            candidate: textureCandidate(
                texture: source, purpose: .premultipliedColor,
                name: "repeat", sampling: SceneTextureSampling(texFlags: 0)
            ),
            target: rejected, queue: queue, pipeline: pipeline, compositor: compositor
        )
        let clampBorderRejected = try !drawBaseColor(
            source: source,
            candidate: textureCandidate(
                texture: source, purpose: .premultipliedColor,
                name: "clamp-border", sampling: SceneTextureSampling(texFlags: 8)
            ),
            target: rejected, queue: queue, pipeline: pipeline, compositor: compositor
        )
        let effectfulReferenceEncoded = try drawBaseColor(
            source: source, candidate: nil, target: effectfulReference,
            queue: queue, pipeline: pipeline, compositor: compositor,
            effectful: true
        )
        let effectfulCandidateEncoded = try drawBaseColor(
            source: source, candidate: candidate, target: effectfulAccepted,
            queue: queue, pipeline: pipeline, compositor: compositor,
            effectful: true
        )
        let effectfulWrongPurposeRejected = try !drawBaseColor(
            source: source,
            candidate: textureCandidate(
                texture: source, purpose: .normal, name: "effectful-wrong-purpose"
            ),
            target: effectfulRejected,
            queue: queue, pipeline: pipeline, compositor: compositor,
            effectful: true
        )
        let effectfulMismatchedTextureRejected = try !drawBaseColor(
            source: source,
            candidate: textureCandidate(
                texture: other,
                purpose: .premultipliedColor,
                name: "effectful-wrong-texture"
            ),
            target: effectfulRejected,
            queue: queue, pipeline: pipeline, compositor: compositor,
            effectful: true
        )
        let referenceBytes = try textureBytes(reference, queue: queue)
        let acceptedBytes = try textureBytes(accepted, queue: queue)
        let effectfulReferenceBytes = try textureBytes(
            effectfulReference, queue: queue
        )
        let effectfulAcceptedBytes = try textureBytes(
            effectfulAccepted, queue: queue
        )
        let pixels = stride(from: 0, to: acceptedBytes.count, by: 4).map {
            Array(acceptedBytes[$0 ..< ($0 + 4)])
        }
        return [
            "referenceEncoded": referenceEncoded,
            "candidateEncoded": candidateEncoded,
            "matchesLegacyPixels":
                maxDifference(referenceBytes, acceptedBytes) <= 1,
            "fractionalPremultipliedPixelPreserved":
                pixels.contains([16, 32, 64, 128]),
            "wrongPurposeRejected": wrongPurposeRejected,
            "mismatchedTextureRejected": mismatchedTextureRejected,
            "nonIdentityRejected": nonIdentityRejected,
            "nearestRejected": nearestRejected,
            "repeatRejected": repeatRejected,
            "clampBorderRejected": clampBorderRejected,
            "effectfulReferenceEncoded": effectfulReferenceEncoded,
            "effectfulCandidateEncoded": effectfulCandidateEncoded,
            "effectfulMatchesLegacyPixels":
                maxDifference(effectfulReferenceBytes, effectfulAcceptedBytes) <= 1,
            "effectfulWrongPurposeRejected": effectfulWrongPurposeRejected,
            "effectfulMismatchedTextureRejected":
                effectfulMismatchedTextureRejected,
        ]
    }

    static func drawBaseColor(
        source: MTLTexture,
        candidate: SceneTextureCandidate?,
        target: MTLTexture,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        effectful: Bool = false
    ) throws -> Bool {
        guard let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        let effectPlan = effectful ? authoredPreciseBlurPlan() : nil
        let offscreenPool = effectful
            ? SceneOffscreenTexturePool(device: source.device)
            : nil
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let encoded = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: SceneRenderDescriptor.Layer(
                    contentKind: "image",
                    colorRGB: nil,
                    colorBlendMode: nil,
                    effects: []
                ),
                texture: source,
                baseTextureCandidate: candidate,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 0, alpha: 1, cursorUV: .zero
                ),
                offscreenTexturePool: offscreenPool,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: effectPlan,
                blocksLegacyGaussianBlur: false
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw HarnessError.commandFailed
        }
        return encoded
    }

    static func dependencyBlendPixel(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        blendMode: Int?,
        alpha: Float
    ) throws -> [UInt8] {
        guard let source = makeTexture(device: device, size: 8, usage: .shaderRead),
              let dependency = makeTexture(device: device, size: 8, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 8, usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: [32, 64, 128, 128])
        fill(dependency, bgra: [192, 32, 64, 255])
        let layer = SceneRenderDescriptor.Layer(
            contentKind: "image", colorRGB: nil, colorBlendMode: nil, effects: []
        )
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let drew = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: layer,
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 0, alpha: alpha, cursorUV: .zero
                ),
                offscreenTexturePool: nil,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: blendMode.map {
                    SceneDependencyEffectInput(texture: dependency, blendMode: $0)
                },
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        guard drew else { throw HarnessError.drawRefused }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return pixel(target, x: 4, y: 4)
    }

    static func authoredClippingMaskPixel(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        contentKind: String = "image"
    ) throws -> [UInt8] {
        guard let source = makeTexture(device: device, size: 8, usage: .shaderRead),
              let dependency = makeTexture(device: device, size: 8, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 8, usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: [32, 64, 128, 128])
        fill(dependency, bgra: [192, 32, 64, 255])
        let layer = SceneRenderDescriptor.Layer(
            contentKind: contentKind, colorRGB: nil, colorBlendMode: nil, effects: []
        )
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let drew = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: layer,
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 0, alpha: 1, cursorUV: .zero
                ),
                offscreenTexturePool: SceneOffscreenTexturePool(device: device),
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: SceneDependencyEffectInput(
                    texture: dependency,
                    blendMode: 0
                ),
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false,
                authoredEffectChain: authoredClippingMaskChain()
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        guard drew else { throw HarnessError.drawRefused }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return pixel(target, x: 4, y: 4)
    }

    static func layerTintPixel(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        contentKind: String,
        brightness: Double? = nil,
        tint: SIMD3<Float> = SIMD3(0.25, 0.5, 0.75)
    ) throws -> [UInt8] {
        guard let source = makeTexture(device: device, size: 1, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 1, usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: [255, 255, 255, 255])
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let drew = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: SceneRenderDescriptor.Layer(
                    contentKind: contentKind,
                    colorRGB: nil,
                    colorBlendMode: nil,
                    brightness: brightness,
                    effects: []
                ),
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 0,
                    alpha: 1,
                    cursorUV: .zero,
                    tint: tint
                ),
                offscreenTexturePool: nil,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        guard drew else { throw HarnessError.drawRefused }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return pixel(target, x: 0, y: 0)
    }

    static func layerColorBlendPixel(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        blendMode: Int,
        sourceBGRA: [UInt8] = [64, 96, 128, 128],
        background: MTLClearColor = MTLClearColorMake(0.2, 0.4, 0.6, 1),
        tint: SIMD3<Float> = SIMD3(repeating: 1),
        brightness: Double? = nil
    ) throws -> [UInt8]? {
        guard let source = makeTexture(device: device, size: 1, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 1, usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: sourceBGRA)
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: background
        )
        let drew = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: SceneRenderDescriptor.Layer(
                    contentKind: "image",
                    colorRGB: nil,
                    colorBlendMode: blendMode,
                    brightness: brightness,
                    effects: []
                ),
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 0, alpha: 1, cursorUV: .zero, tint: tint
                ),
                offscreenTexturePool: SceneOffscreenTexturePool(device: device),
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        guard drew else { return nil }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return pixel(target, x: 0, y: 0)
    }

    static func imageBlendPixel(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageBlendPipeline,
        multiply: Float
    ) throws -> [UInt8] {
        guard let source = makeTexture(device: device, size: 8, usage: .shaderRead),
              let blend = makeTexture(device: device, size: 8, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 8, usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: [0, 0, 0, 0])
        fill(blend, bgra: [192, 32, 64, 255])
        guard pipeline.encode(
            source: source,
            blend: blend,
            target: target,
            multiply: multiply,
            alphaMultiply: 1,
            writesAlpha: true,
            commandBuffer: commandBuffer
        ) else {
            throw HarnessError.encoderUnavailable
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return pixel(target, x: 4, y: 4)
    }

    static func partialAlphaImageBlendPixel(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageBlendPipeline
    ) throws -> [UInt8] {
        guard let source = makeTexture(device: device, size: 8, usage: .shaderRead),
              let blend = makeTexture(device: device, size: 8, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 8, usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: [0, 0, 128, 128])
        fill(blend, bgra: [128, 0, 0, 128])
        guard pipeline.encode(
            source: source,
            blend: blend,
            target: target,
            multiply: 1,
            alphaMultiply: 1,
            writesAlpha: true,
            commandBuffer: commandBuffer
        ) else {
            throw HarnessError.encoderUnavailable
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return pixel(target, x: 4, y: 4)
    }

    static func gradientPixels(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        sourceBGRA: [UInt8],
        dependencyBGRA: [UInt8]?
    ) throws -> [[UInt8]] {
        guard let source = makeTexture(device: device, size: 8, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 8, usage: [.renderTarget, .shaderRead]
              ), let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: sourceBGRA)
        let dependency = dependencyBGRA.flatMap { color -> MTLTexture? in
            guard let texture = makeTexture(device: device, size: 8, usage: .shaderRead) else {
                return nil
            }
            fill(texture, bgra: color)
            return texture
        }
        let layer = gradientLayer(includesClipping: dependency != nil)
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let drew = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: layer,
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(time: 0, alpha: 1, cursorUV: .zero),
                offscreenTexturePool: SceneOffscreenTexturePool(device: device),
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: dependency.map {
                    SceneDependencyEffectInput(texture: $0, blendMode: 0)
                },
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        guard drew else { throw HarnessError.drawRefused }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return [pixel(target, x: 4, y: 0), pixel(target, x: 4, y: 7)]
    }

    static func solidMappedEffectExtentEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [String: Any] {
        let width = 64
        let height = 36
        guard let source = makeTexture(device: device, size: 1, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: width, usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: [255, 255, 255, 255])
        let chain = authoredWorkshopGradientChain()
        let pool = SceneOffscreenTexturePool(device: device, maxDimension: width)
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let drew = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: SceneRenderDescriptor.Layer(
                    contentKind: "solid", colorRGB: [1, 1, 1],
                    colorBlendMode: nil, effects: []
                ),
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 0, alpha: 1, cursorUV: .zero, tint: SIMD3(repeating: 1)
                ),
                offscreenTexturePool: pool,
                offscreenSize: CGSize(width: CGFloat(width), height: CGFloat(height)),
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false,
                authoredEffectChain: chain
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        guard drew else { throw HarnessError.drawRefused }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed,
              let table = pool.graphTargets(
                  for: chain, requestedWidth: width, requestedHeight: height
              )?.first else {
            throw HarnessError.commandFailed
        }
        let output = try textureBytes(table.outputTexture, queue: queue)
        var colors = Set<UInt32>()
        for offset in stride(from: 0, to: output.count, by: 4) {
            colors.insert(
                UInt32(output[offset])
                    | UInt32(output[offset + 1]) << 8
                    | UInt32(output[offset + 2]) << 16
                    | UInt32(output[offset + 3]) << 24
            )
        }
        return [
            "encoded": true,
            "sourceSize": [source.width, source.height],
            "offscreenSize": [table.outputTexture.width, table.outputTexture.height],
            "uniqueColorCount": colors.count,
        ]
    }

    static func gradientLayer(includesClipping: Bool) -> SceneRenderDescriptor.Layer {
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            texturePaths: [],
            textureSlots: [],
            combos: ["AXIS": 1, "BLENDMODE": 0],
            constantShaderValues: [
                "Amount": .init(components: [1]),
                "Color 1": .init(components: [1, 0, 0]),
                "Color 2": .init(components: [0, 0, 1]),
                "Hue Speed": .init(components: [0]),
                "Opacity": .init(components: [1]),
                "Oscillate": .init(components: [0]),
            ]
        )
        var effects = [SceneRenderDescriptor.EffectDescriptor(
            file: "effects/workshop/2552475732/gradient_color/effect.json",
            visible: true,
            passes: [pass]
        )]
        if includesClipping {
            effects.append(.init(
                file: "effects/workshop/2800594362/clipping_mask/effect.json",
                visible: true,
                passes: []
            ))
        }
        return SceneRenderDescriptor.Layer(
            contentKind: "image", colorRGB: nil, colorBlendMode: nil, effects: effects
        )
    }

    static func blurPlan(
        path: String,
        scale: Double,
        blocksLegacyGaussianBlur: Bool = false
    ) -> SceneGaussianBlurPlan? {
        let empty = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            texturePaths: [], textureSlots: [], combos: [:], constantShaderValues: [:]
        )
        let scaled = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            texturePaths: [],
            textureSlots: [],
            combos: [:],
            constantShaderValues: ["scale": .init(components: [scale, scale])]
        )
        let passes = path.contains("blurprecise")
            ? [scaled, scaled]
            : [empty, scaled, scaled, empty]
        let layer = SceneRenderDescriptor.Layer(
            contentKind: "image",
            colorRGB: nil,
            colorBlendMode: nil,
            effects: [.init(file: path, visible: true, passes: passes)]
        )
        return SceneEffectRuntimePlanner.plan(
            for: layer,
            hasIrisMask: false,
            hasOpacityMask: false,
            hasWaterMask: false,
            hasFoliageMask: false,
            hasWaterRippleNormal: false,
            blocksLegacyGaussianBlur: blocksLegacyGaussianBlur
        ).gaussianBlur
    }

    static func authoredExtentMismatchIsRefused(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> Bool {
        guard let source = makeTexture(device: device, size: 8, usage: .shaderRead),
              let target = makeTexture(
                  device: device,
                  size: 8,
                  usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: [0, 0, 255, 255])
        let layer = SceneRenderDescriptor.Layer(
            contentKind: "image", colorRGB: nil, colorBlendMode: nil, effects: []
        )
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let encoded = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: layer,
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(time: 0, alpha: 1, cursorUV: .zero),
                offscreenTexturePool: SceneOffscreenTexturePool(device: device, maxDimension: 4),
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: authoredPreciseBlurPlan(),
                blocksLegacyGaussianBlur: false
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return !encoded
    }

    static func authoredPreciseBlurImpulseEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        legacyCompose: Bool = false,
        sourceSize: Int = 8,
        maxDimension: Int = 8
    ) throws -> [String: Any] {
        let size = sourceSize
        guard let source = makeTexture(device: device, size: size, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let blurPipeline = SceneGaussianBlurPipeline(device: device) else {
            throw HarnessError.metalUnavailable
        }
        fillPremultipliedImpulse(source)
        let plan = authoredPreciseBlurPlan(legacyCompose: legacyCompose)
        let pool = SceneOffscreenTexturePool(device: device, maxDimension: maxDimension)
        let layer = SceneRenderDescriptor.Layer(
            contentKind: "image", colorRGB: nil, colorBlendMode: nil, effects: []
        )
        try drawAuthoredBlur(
            source: source,
            target: target,
            layer: layer,
            plan: plan,
            pool: pool,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        guard let table = pool.graphTargets(
            for: plan, requestedWidth: size, requestedHeight: size
        ), let intermediateIdentity = table.plan.logicalTargets.first?.identity,
        let intermediate = table.texture(for: intermediateIdentity),
        let blur = plan.gaussianBlur,
        let referenceHorizontal = makeTexture(
            device: device,
            size: table.inputTexture.width,
            usage: [.renderTarget, .shaderRead]
        ),
        let referenceOutput = makeTexture(
            device: device,
            size: table.inputTexture.width,
            usage: [.renderTarget, .shaderRead]
        ),
        let targetNormalizedHorizontal = makeTexture(
            device: device,
            size: table.inputTexture.width,
            usage: [.renderTarget, .shaderRead]
        ),
        let targetNormalizedOutput = makeTexture(
            device: device,
            size: table.inputTexture.width,
            usage: [.renderTarget, .shaderRead]
        ),
        let commandBuffer = queue.makeCommandBuffer(), blurPipeline.encode(
            source: table.inputTexture,
            target: referenceHorizontal,
            step: SIMD2(
                blur.horizontalStep * blur.sampleResolutionScale / Float(size), 0
            ),
            commandBuffer: commandBuffer
        ), blurPipeline.encode(
            source: referenceHorizontal,
            target: referenceOutput,
            step: SIMD2(
                0, blur.verticalStep * blur.sampleResolutionScale / Float(size)
            ),
            commandBuffer: commandBuffer
        ), blurPipeline.encode(
            source: table.inputTexture,
            target: targetNormalizedHorizontal,
            step: SIMD2(
                blur.horizontalStep * blur.sampleResolutionScale
                    / Float(table.inputTexture.width),
                0
            ),
            commandBuffer: commandBuffer
        ), blurPipeline.encode(
            source: targetNormalizedHorizontal,
            target: targetNormalizedOutput,
            step: SIMD2(
                0,
                blur.verticalStep * blur.sampleResolutionScale
                    / Float(table.inputTexture.height)
            ),
            commandBuffer: commandBuffer
        ) else {
            throw HarnessError.drawRefused
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }

        let sourceBytes = try textureBytes(source, queue: queue)
        let inputBytes = try textureBytes(table.inputTexture, queue: queue)
        let horizontalBytes = try textureBytes(intermediate, queue: queue)
        let expectedHorizontalBytes = try textureBytes(referenceHorizontal, queue: queue)
        let outputBytes = try textureBytes(table.outputTexture, queue: queue)
        let expectedOutputBytes = try textureBytes(referenceOutput, queue: queue)
        let targetNormalizedOutputBytes = try textureBytes(
            targetNormalizedOutput,
            queue: queue
        )
        let mainBytes = try textureBytes(target, queue: queue)
        return [
            "encoded": true,
            "sourceWidth": source.width,
            "inputWidth": table.inputTexture.width,
            "inputMaxDelta": maxDifference(inputBytes, sourceBytes),
            "horizontalMaxDelta": maxDifference(
                horizontalBytes, expectedHorizontalBytes
            ),
            "outputMaxDelta": maxDifference(outputBytes, expectedOutputBytes),
            "targetNormalizedOutputDelta": maxDifference(
                outputBytes, targetNormalizedOutputBytes
            ),
            "mainMaxDelta": maxDifference(mainBytes, expectedOutputBytes),
            "horizontalToOutputDelta": maxDifference(horizontalBytes, outputBytes),
            "sourceToOutputDelta": maxDifference(sourceBytes, outputBytes),
            "sourceHasMixedAlpha": hasMixedAlpha(sourceBytes),
            "outputIsPremultiplied": isPremultiplied(outputBytes),
        ]
    }

    static func authoredPreciseInterleaveEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [String: Any] {
        let size = 8
        guard let source = makeTexture(device: device, size: size, usage: .shaderRead),
              let baselineTarget = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let copyTarget = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let swapTarget = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ) else {
            throw HarnessError.metalUnavailable
        }
        fillPremultipliedImpulse(source)
        let layer = SceneRenderDescriptor.Layer(
            contentKind: "image", colorRGB: nil, colorBlendMode: nil, effects: []
        )
        let cases: [(MTLTexture, Graph.NodeKind?)] = [
            (baselineTarget, nil),
            (copyTarget, Graph.NodeKind.copy),
            (swapTarget, Graph.NodeKind.swap),
        ]
        for (target, commandKind) in cases {
            try drawAuthoredBlur(
                source: source,
                target: target,
                layer: layer,
                plan: authoredPreciseBlurPlan(commandKind: commandKind),
                pool: SceneOffscreenTexturePool(device: device, maxDimension: size),
                queue: queue,
                pipeline: pipeline,
                compositor: compositor
            )
        }
        let baselineBytes = try textureBytes(baselineTarget, queue: queue)
        let copyBytes = try textureBytes(copyTarget, queue: queue)
        let swapBytes = try textureBytes(swapTarget, queue: queue)
        return [
            "copyMaxDelta": maxDifference(copyBytes, baselineBytes),
            "swapMaxDelta": maxDifference(swapBytes, baselineBytes),
            "copyHasPixels": copyBytes.contains(where: { $0 != 0 }),
            "swapHasPixels": swapBytes.contains(where: { $0 != 0 }),
            "copyIsPremultiplied": isPremultiplied(copyBytes),
            "swapIsPremultiplied": isPremultiplied(swapBytes),
        ]
    }

    static func authoredStandardBlurCheckerboardEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [String: Any] {
        let size = 16
        let quarterSize = 4
        guard let source = makeTexture(device: device, size: size, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let referenceQuarterA = makeTexture(
                  device: device, size: quarterSize,
                  usage: [.renderTarget, .shaderRead]
              ),
              let referenceQuarterB = makeTexture(
                  device: device, size: quarterSize,
                  usage: [.renderTarget, .shaderRead]
              ),
              let referenceOutput = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let blurPipeline = SceneStandardBlurPipeline(device: device) else {
            throw HarnessError.metalUnavailable
        }
        fillPremultipliedCheckerboard(source)
        let plan = authoredStandardBlurPlan()
        let pool = SceneOffscreenTexturePool(device: device, maxDimension: size)
        try drawAuthoredBlur(
            source: source,
            target: target,
            layer: standardBlurLayer(),
            plan: plan,
            pool: pool,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        guard let table = pool.graphTargets(
            for: plan, requestedWidth: size, requestedHeight: size
        ) else {
            throw HarnessError.drawRefused
        }
        let intermediates = table.plan.logicalTargets.sorted {
            $0.lifetime.firstWriteNodeIndex < $1.lifetime.firstWriteNodeIndex
        }
        guard intermediates.count == 2,
        let quarterA = table.texture(for: intermediates[0].identity),
        let quarterB = table.texture(for: intermediates[1].identity),
        let blur = plan.standardBlur,
        let commandBuffer = queue.makeCommandBuffer(), blurPipeline.encodeDownsample(
            source: table.inputTexture,
            target: referenceQuarterA,
            commandBuffer: commandBuffer
        ), blurPipeline.encodeGaussian(
            source: referenceQuarterA,
            target: referenceQuarterB,
            step: SIMD2(blur.horizontalStep / Float(quarterSize), 0),
            commandBuffer: commandBuffer
        ), blurPipeline.encodeGaussian(
            source: referenceQuarterB,
            target: referenceQuarterA,
            step: SIMD2(0, blur.verticalStep / Float(quarterSize)),
            commandBuffer: commandBuffer
        ), blurPipeline.encodeCombine(
            blurred: referenceQuarterA,
            previous: table.inputTexture,
            target: referenceOutput,
            commandBuffer: commandBuffer
        ) else {
            throw HarnessError.drawRefused
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }

        let sourceBytes = try textureBytes(source, queue: queue)
        let inputBytes = try textureBytes(table.inputTexture, queue: queue)
        let horizontalBytes = try textureBytes(quarterB, queue: queue)
        let expectedHorizontalBytes = try textureBytes(referenceQuarterB, queue: queue)
        let verticalBytes = try textureBytes(quarterA, queue: queue)
        let expectedVerticalBytes = try textureBytes(referenceQuarterA, queue: queue)
        let outputBytes = try textureBytes(table.outputTexture, queue: queue)
        let expectedOutputBytes = try textureBytes(referenceOutput, queue: queue)
        let mainBytes = try textureBytes(target, queue: queue)
        return [
            "encoded": true,
            "inputMaxDelta": maxDifference(inputBytes, sourceBytes),
            "horizontalMaxDelta": maxDifference(
                horizontalBytes, expectedHorizontalBytes
            ),
            "verticalMaxDelta": maxDifference(verticalBytes, expectedVerticalBytes),
            "horizontalToExpectedVerticalDelta": maxDifference(
                horizontalBytes, expectedVerticalBytes
            ),
            "verticalToExpectedHorizontalDelta": maxDifference(
                verticalBytes, expectedHorizontalBytes
            ),
            "outputMaxDelta": maxDifference(outputBytes, expectedOutputBytes),
            "mainMaxDelta": maxDifference(mainBytes, expectedOutputBytes),
            "horizontalToVerticalDelta": maxDifference(horizontalBytes, verticalBytes),
            "inputToOutputDelta": maxDifference(inputBytes, outputBytes),
            "sourceHasMixedAlpha": hasMixedAlpha(sourceBytes),
            "outputIsPremultiplied": isPremultiplied(outputBytes),
        ]
    }

    static func authoredStandardBlurCandidateEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [String: Any] {
        let size = 16
        let maskPath = "materials/test/standard_blur_mask.tex"
        guard let source = makeTexture(device: device, size: size, usage: .shaderRead),
              let mask = makeTexture(device: device, size: size, usage: .shaderRead),
              let acceptedTarget = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let rejectedTarget = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ) else {
            throw HarnessError.metalUnavailable
        }
        fillPremultipliedCheckerboard(source)
        fillPixels(mask) { x, _ in
            x < 10 ? [0, 0, 0, 255] : [0, 0, 255, 255]
        }
        let plan = authoredStandardBlurPlan(maskTexturePath: maskPath)
        let acceptedCandidate = textureCandidate(
            texture: mask,
            purpose: .mask,
            name: "standard-blur-mask",
            mappedWidth: size / 2
        )
        try drawAuthoredBlur(
            source: source,
            target: acceptedTarget,
            layer: standardBlurLayer(),
            plan: plan,
            pool: SceneOffscreenTexturePool(device: device, maxDimension: size),
            queue: queue,
            pipeline: pipeline,
            compositor: compositor,
            masks: standardBlurMasks(
                candidate: acceptedCandidate,
                path: maskPath,
                descriptorID: plan.standardBlur?.effectDescriptorID ?? ""
            )
        )

        let wrongPurposeCandidate = textureCandidate(
            texture: mask,
            purpose: .flow,
            name: "wrong-purpose-standard-blur-mask"
        )
        let wrongPurposeRejected: Bool
        do {
            try drawAuthoredBlur(
                source: source,
                target: rejectedTarget,
                layer: standardBlurLayer(),
                plan: plan,
                pool: SceneOffscreenTexturePool(device: device, maxDimension: size),
                queue: queue,
                pipeline: pipeline,
                compositor: compositor,
                masks: standardBlurMasks(
                    candidate: wrongPurposeCandidate,
                    path: maskPath,
                    descriptorID: plan.standardBlur?.effectDescriptorID ?? ""
                )
            )
            wrongPurposeRejected = false
        } catch HarnessError.drawRefused {
            wrongPurposeRejected = true
        }

        let sourceBytes = try textureBytes(source, queue: queue)
        let acceptedBytes = try textureBytes(acceptedTarget, queue: queue)
        return [
            "accepted": true,
            "paddedZeroMaskPreservedSource":
                maxDifference(sourceBytes, acceptedBytes) <= 2,
            "wrongPurposeRejected": wrongPurposeRejected,
        ]
    }

    static func textureCandidate(
        texture: MTLTexture,
        purpose: SceneTextureLoadPurpose,
        name: String,
        mappedWidth: Int? = nil,
        sampling: SceneTextureSampling = .linearClamp
    ) -> SceneTextureCandidate {
        let physicalSize = CGSize(width: texture.width, height: texture.height)
        let mappedSize = CGSize(
            width: mappedWidth ?? texture.width,
            height: texture.height
        )
        let scale = Float(mappedSize.width / physicalSize.width)
        let content: SceneTextureContent
        switch purpose {
        case .premultipliedColor:
            content = .color(.resolved(.premultipliedAlpha))
        case .straightAlbedo:
            content = .color(.resolved(.straightAlpha))
        default:
            content = .data
        }
        return SceneTextureCandidate(
            texture: texture,
            identity: .builtIn(name: name),
            generation: .immutable(revision: 1),
            purpose: purpose,
            content: content,
            physicalSize: physicalSize,
            mappedSize: mappedSize,
            uvTransform: SceneTextureUVTransform(
                origin: .zero,
                xAxis: SIMD2(scale, 0),
                yAxis: SIMD2(0, 1)
            ),
            sampling: sampling
        )
    }

    static func standardBlurMasks(
        candidate: SceneTextureCandidate,
        path: String,
        descriptorID: String
    ) -> SceneImageLayerMasks {
        SceneImageLayerMasks(
            iris: nil,
            opacity: nil,
            water: nil,
            waterUVScale: SIMD2(repeating: 1),
            foliage: nil,
            foliageUVScale: SIMD2(repeating: 1),
            waterRippleNormal: nil,
            foliageSwayEffects: [:],
            waterRippleEffects: [:],
            depthParallaxEffects: [:],
            blendEffects: [:],
            shakeEffects: [:],
            filmGrainEffects: [:],
            standardBlurEffects: [
                descriptorID: SceneStandardBlurEffectTextures(
                    maskCandidate: candidate,
                    maskPath: path
                ),
            ],
            waterFlowEffects: [:],
            waterWavesEffects: [:],
            waterCausticsEffects: [:],
            cursorRippleEffects: [:],
            opacityEffects: [:],
            pulseEffects: [:],
            tintEffects: [:],
            godraysEffects: [:],
            shineEffects: [:],
            xRay: nil
        )
    }

    static func authoredTwoStageChainEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [String: Any] {
        let size = 16
        guard let source = makeTexture(device: device, size: size, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ), let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fillPremultipliedCheckerboard(source)
        let chain = authoredTwoStageBlurChain()
        let pool = SceneOffscreenTexturePool(device: device, maxDimension: size)
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        guard compositor.draw(
            SceneImageLayerDrawRequest(
                layer: standardBlurLayer(),
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 3, alpha: 0.5, cursorUV: SIMD2(0.25, 0.75)
                ),
                offscreenTexturePool: pool,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false,
                authoredEffectChain: chain,
                dynamicValues: .empty(frameIndex: 17)
            ),
            pipeline: pipeline,
            mainPass: mainPass
        ) else {
            throw HarnessError.drawRefused
        }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed,
              let tables = pool.graphTargets(
                for: chain, requestedWidth: size, requestedHeight: size
              ), tables.count == 2 else {
            throw HarnessError.commandFailed
        }

        let sourceBytes = try textureBytes(source, queue: queue)
        let firstInput = try textureBytes(tables[0].inputTexture, queue: queue)
        let firstOutput = try textureBytes(tables[0].outputTexture, queue: queue)
        let secondInput = try textureBytes(tables[1].inputTexture, queue: queue)
        let secondOutput = try textureBytes(tables[1].outputTexture, queue: queue)
        let mainOutput = try textureBytes(target, queue: queue)
        return [
            "encoded": true,
            "sourceToFirstInputDelta": maxDifference(sourceBytes, firstInput),
            "firstOutputToSecondInputDelta": maxDifference(firstOutput, secondInput),
            "firstToSecondOutputDelta": maxDifference(firstOutput, secondOutput),
            "secondOutputToMainDelta": maxDifference(secondOutput, mainOutput),
        ]
    }

    static func authoredOpacityLivePixels(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [[UInt8]] {
        try [Float?.none, Float(0.2)].map { liveAlpha in
            guard let source = makeTexture(device: device, size: 1, usage: .shaderRead),
                  let target = makeTexture(
                      device: device, size: 1, usage: [.renderTarget, .shaderRead]
                  ), let commandBuffer = queue.makeCommandBuffer() else {
                throw HarnessError.metalUnavailable
            }
            fill(source, bgra: [40, 80, 160, 200])
            let mainPass = SceneMainPassEncoder(
                commandBuffer: commandBuffer,
                target: target,
                clearColor: MTLClearColorMake(0, 0, 0, 0)
            )
            let snapshot = SceneDynamicSnapshot(
                strengthsByEffectIndex: [:],
                opacitiesByEffectIndex: liveAlpha.map { [0: $0] } ?? [:]
            )
            guard compositor.draw(
                SceneImageLayerDrawRequest(
                    layer: SceneRenderDescriptor.Layer(
                        contentKind: "image", colorRGB: nil, colorBlendMode: nil, effects: []
                    ),
                    texture: source,
                    masks: .empty,
                    textureFrame: .identity,
                    mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                    uniforms: SceneImageLayerUniformValues(
                        time: 0, alpha: 1, cursorUV: .zero
                    ),
                    offscreenTexturePool: SceneOffscreenTexturePool(
                        device: device, maxDimension: 1
                    ),
                    offscreenSize: nil,
                    requiresSourceCopy: false,
                    finalCompositeAlpha: nil,
                    dependencyEffect: nil,
                    authoredEffectPlan: nil,
                    blocksLegacyGaussianBlur: false,
                    authoredEffectChain: authoredOpacityChain(),
                    dynamicValues: snapshot
                ),
                pipeline: pipeline,
                mainPass: mainPass
            ) else {
                throw HarnessError.drawRefused
            }
            mainPass.finishEnsuringClear()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            guard commandBuffer.status == .completed else {
                throw HarnessError.commandFailed
            }
            return pixel(target, x: 0, y: 0)
        }
    }

    // 官方 opacity.frag 在 MASK 下是 `albedo.a *= mask * g_UserAlpha`。legacy 路径靠 capture
    // 阶段的 `color *= auxMask * alpha` 实现；authored chain 路径的 capture uniforms 是
    // .neutral，遮罩必须由 opacity 后端自己乘。这里让同一层既带 opacity 遮罩又带 authored
    // chain，量出两条路径是否都只乘一次遮罩和 alpha；第三个用例声明了遮罩却不给贴图，
    // 必须整段拒绝而不是静默降级成无遮罩。
    static func authoredOpacityMaskPixels(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [String: Any] {
        var out: [String: Any] = [:]
        let maskPath = "masks/opacity_mask"
        let cases: [(key: String, chain: SceneAuthoredEffectExecutionChain?, binds: Bool)] = [
            ("authored", authoredOpacityChain(alpha: 0.5, maskTexturePath: maskPath), true),
            ("legacy", nil, false),
            ("missingMask", authoredOpacityChain(alpha: 0.5, maskTexturePath: maskPath), false),
        ]
        for item in cases {
            guard let source = makeTexture(device: device, size: 1, usage: .shaderRead),
                  let mask = makeTexture(device: device, size: 1, usage: .shaderRead),
                  let target = makeTexture(
                      device: device, size: 1, usage: [.renderTarget, .shaderRead]
                  ), let commandBuffer = queue.makeCommandBuffer() else {
                throw HarnessError.metalUnavailable
            }
            fill(source, bgra: [40, 80, 160, 200])
            fill(mask, bgra: [0, 0, 128, 255])
            let mainPass = SceneMainPassEncoder(
                commandBuffer: commandBuffer,
                target: target,
                clearColor: MTLClearColorMake(0, 0, 0, 0)
            )
            let effect = SceneRenderDescriptor.EffectDescriptor(
                file: "effects/opacity/effect.json",
                visible: true,
                passes: [SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
                    texturePaths: [maskPath],
                    textureSlots: [nil, maskPath],
                    combos: [:],
                    constantShaderValues: ["alpha": .init(components: [0.5])]
                )]
            )
            let encoded = compositor.draw(
                SceneImageLayerDrawRequest(
                    layer: SceneRenderDescriptor.Layer(
                        contentKind: "image",
                        colorRGB: nil,
                        colorBlendMode: nil,
                        effects: [effect]
                    ),
                    texture: source,
                    masks: SceneImageLayerMasks(
                        iris: nil,
                        opacity: mask,
                        water: nil,
                        waterUVScale: SIMD2<Float>(repeating: 1),
                        foliage: nil,
                        foliageUVScale: SIMD2<Float>(repeating: 1),
                        waterRippleNormal: nil,
                        foliageSwayEffects: [:],
                        waterRippleEffects: [:],
                        depthParallaxEffects: [:],
                        blendEffects: [:],
                        shakeEffects: [:],
                        filmGrainEffects: [:],
                        standardBlurEffects: [:],
                        waterFlowEffects: [:],
                        waterWavesEffects: [:],
                        waterCausticsEffects: [:],
                        cursorRippleEffects: [:],
                        opacityEffects: item.binds ? ["850#effect#0": SceneOpacityEffectTextures(
                            mask: mask,
                            maskUVScale: SIMD2<Float>(repeating: 1),
                            maskPath: maskPath
                        )] : [:],
                        pulseEffects: [:],
                        tintEffects: [:],
                        godraysEffects: [:],
                        shineEffects: [:],
                        xRay: nil
                    ),
                    textureFrame: .identity,
                    mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                    uniforms: SceneImageLayerUniformValues(time: 0, alpha: 1, cursorUV: .zero),
                    offscreenTexturePool: SceneOffscreenTexturePool(
                        device: device, maxDimension: 1
                    ),
                    offscreenSize: nil,
                    requiresSourceCopy: false,
                    finalCompositeAlpha: nil,
                    dependencyEffect: nil,
                    authoredEffectPlan: nil,
                    blocksLegacyGaussianBlur: false,
                    authoredEffectChain: item.chain,
                    dynamicValues: SceneDynamicSnapshot.empty(frameIndex: 0)
                ),
                pipeline: pipeline,
                mainPass: mainPass
            )
            if item.key == "missingMask" {
                out["missingMaskRefused"] = !encoded
                continue
            }
            guard encoded else { throw HarnessError.drawRefused }
            mainPass.finishEnsuringClear()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            guard commandBuffer.status == .completed else {
                throw HarnessError.commandFailed
            }
            out[item.key] = pixel(target, x: 0, y: 0)
        }
        return out
    }

    static func authoredBlendChainPixel(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        writesAlpha: Bool = false,
        alphaMultiply: Float = 1
    ) throws -> [String: Any] {
        let sourceBGRA: [UInt8] = [40, 80, 160, 200]
        let blendBGRA: [UInt8] = [100, 20, 60, 128]
        let multiply: Float = 0.5
        guard let source = makeTexture(device: device, size: 1, usage: .shaderRead),
              let blend = makeTexture(device: device, size: 1, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 1, usage: [.renderTarget, .shaderRead]
              ), let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.authoredBlendUnavailable
        }
        fill(source, bgra: sourceBGRA)
        fill(blend, bgra: blendBGRA)
        let blendCandidate = SceneTextureCandidate(
            texture: blend,
            identity: .builtIn(name: "authored-blend-fixture"),
            generation: .immutable(revision: 1),
            purpose: .premultipliedColor,
            content: .color(.resolved(.premultipliedAlpha)),
            physicalSize: CGSize(width: 1, height: 1),
            mappedSize: CGSize(width: 1, height: 1),
            uvTransform: .identity,
            sampling: .linearClamp
        )
        let chain = authoredBlendChain(
            multiply: multiply,
            alphaMultiply: alphaMultiply,
            writesAlpha: writesAlpha
        )
        let pool = SceneOffscreenTexturePool(device: device, maxDimension: 1)
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let encoded = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: SceneRenderDescriptor.Layer(
                    contentKind: "image", colorRGB: nil, colorBlendMode: nil, effects: []
                ),
                texture: source,
                masks: authoredEffectMasks(blendEffects: [
                    authoredBlendEffectID: SceneBlendEffectTextures(
                        blendBinding: SceneTextureSlotBinding(
                            slotIndex: 1,
                            candidate: blendCandidate
                        ),
                        assetPath: authoredBlendAssetPath,
                        propertyKey: nil
                    ),
                ]),
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(time: 0, alpha: 1, cursorUV: .zero),
                offscreenTexturePool: pool,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false,
                authoredEffectChain: chain,
                dynamicValues: SceneDynamicSnapshot.empty(frameIndex: 0)
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        guard encoded else { throw HarnessError.drawRefused }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw HarnessError.commandFailed
        }
        guard let stageTargets = pool.graphTargets(
            for: chain,
            requestedWidth: 1,
            requestedHeight: 1
        )?.first else {
            throw HarnessError.authoredBlendUnavailable
        }
        return [
            "encoded": encoded,
            "source": sourceBGRA,
            "blend": blendBGRA,
            "multiply": multiply,
            "alphaMultiply": alphaMultiply,
            "writesAlpha": writesAlpha,
            "capturedSourcePixel": pixel(stageTargets.inputTexture, x: 0, y: 0),
            "authoredPixel": pixel(stageTargets.outputTexture, x: 0, y: 0),
            "mainPixel": pixel(target, x: 0, y: 0),
        ]
    }

    static func authoredTransformChainPixel(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [String: Any] {
        let sourceBGRA: [UInt8] = [40, 80, 160, 200]
        guard let source = makeTexture(device: device, size: 1, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 1, usage: [.renderTarget, .shaderRead]
              ), let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.baseTextureUnavailable
        }
        fill(source, bgra: sourceBGRA)
        let chain = authoredTransformChain()
        let pool = SceneOffscreenTexturePool(device: device, maxDimension: 1)
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let encoded = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: SceneRenderDescriptor.Layer(
                    contentKind: "image", colorRGB: nil, colorBlendMode: nil, effects: []
                ),
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 0, alpha: 0.5, cursorUV: .zero
                ),
                offscreenTexturePool: pool,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false,
                authoredEffectChain: chain,
                dynamicValues: SceneDynamicSnapshot.empty(frameIndex: 0)
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        guard encoded else { throw HarnessError.drawRefused }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw HarnessError.commandFailed
        }
        guard let stageTargets = pool.graphTargets(
            for: chain,
            requestedWidth: 1,
            requestedHeight: 1
        )?.first else {
            throw HarnessError.baseTextureUnavailable
        }
        return [
            "encoded": encoded,
            "source": sourceBGRA,
            "authoredPixel": pixel(stageTargets.outputTexture, x: 0, y: 0),
            "mainPixel": pixel(target, x: 0, y: 0),
        ]
    }

    // 官方 tint.frag：mode 0 走 `mix(A, B, o)` 并强制 alpha=1；mode 30 走
    // `mix(A, max(A.r, A.g, A.b) * B, o)` 并保留源 alpha。两个模式共用同一条链，
    // 用来证明 plan 里的 blendMode/color/alpha 真的进了 shader，而不是写死一个模式。
    static func authoredTintChainPixels(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [[UInt8]] {
        // 第三个 case 用 mode 0 + 半灰遮罩：官方语义 mask = g_BlendAlpha * tex.r，
        // mix(A, B, 0.5) 且 mode 0 强制 alpha=1。
        try [(0, false), (30, false), (0, true)].map { blendMode, masked in
            guard let source = makeTexture(device: device, size: 1, usage: .shaderRead),
                  let target = makeTexture(
                      device: device, size: 1, usage: [.renderTarget, .shaderRead]
                  ), let commandBuffer = queue.makeCommandBuffer() else {
                throw HarnessError.metalUnavailable
            }
            fill(source, bgra: [40, 80, 160, 200])
            var maskTexture: MTLTexture?
            if masked {
                guard let mask = makeTexture(device: device, size: 1, usage: .shaderRead) else {
                    throw HarnessError.metalUnavailable
                }
                fill(mask, bgra: [128, 128, 128, 255])
                maskTexture = mask
            }
            let mainPass = SceneMainPassEncoder(
                commandBuffer: commandBuffer,
                target: target,
                clearColor: MTLClearColorMake(0, 0, 0, 0)
            )
            guard compositor.draw(
                SceneImageLayerDrawRequest(
                    layer: SceneRenderDescriptor.Layer(
                        contentKind: "image", colorRGB: nil, colorBlendMode: nil, effects: []
                    ),
                    texture: source,
                    masks: authoredEffectMasks(
                        tintMask: maskTexture,
                        tintMaskPath: masked ? "masks/tint_mask_test" : nil
                    ),
                    textureFrame: .identity,
                    mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                    uniforms: SceneImageLayerUniformValues(
                        time: 0, alpha: 1, cursorUV: .zero
                    ),
                    offscreenTexturePool: SceneOffscreenTexturePool(
                        device: device, maxDimension: 1
                    ),
                    offscreenSize: nil,
                    requiresSourceCopy: false,
                    finalCompositeAlpha: nil,
                    dependencyEffect: nil,
                    authoredEffectPlan: nil,
                    blocksLegacyGaussianBlur: false,
                    authoredEffectChain: authoredTintChain(
                        blendMode: blendMode,
                        maskPath: masked ? "masks/tint_mask_test" : nil
                    ),
                    dynamicValues: SceneDynamicSnapshot.empty(frameIndex: 0)
                ),
                pipeline: pipeline,
                mainPass: mainPass
            ) else {
                throw HarnessError.drawRefused
            }
            mainPass.finishEnsuringClear()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            guard commandBuffer.status == .completed else {
                throw HarnessError.commandFailed
            }
            return pixel(target, x: 0, y: 0)
        }
    }

    static func authoredFailedChainEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [String: Any] {
        let size = 16
        guard let source = makeTexture(device: device, size: size, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ), let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fillPremultipliedCheckerboard(source)
        let chain = authoredFailingSecondStageChain()
        let pool = SceneOffscreenTexturePool(device: device, maxDimension: size)
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let encoded = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: standardBlurLayer(),
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 0, alpha: 1, cursorUV: .zero
                ),
                offscreenTexturePool: pool,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false,
                authoredEffectChain: chain,
                dynamicValues: .empty(frameIndex: 18)
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed,
              let tables = pool.graphTargets(
                for: chain, requestedWidth: size, requestedHeight: size
              ), tables.count == 2 else {
            throw HarnessError.commandFailed
        }
        let firstOutput = try textureBytes(tables[0].outputTexture, queue: queue)
        return [
            "encoded": encoded,
            "mainPixel": pixel(target, x: size / 2, y: size / 2),
            "firstStageProducedPixels": firstOutput.contains(where: { $0 != 0 }),
        ]
    }

    static func xRayThreeTextureRouteEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [String: Any] {
        let size = 16
        guard let source = makeTexture(device: device, size: size, usage: .shaderRead),
              let blend = makeTexture(device: device, size: size, usage: .shaderRead),
              let opacity = makeTexture(device: device, size: size, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: [0, 0, 255, 255])
        fill(blend, bgra: [255, 0, 0, 255])
        fill(opacity, bgra: [0, 0, 255, 255])

        let pool = SceneOffscreenTexturePool(device: device, maxDimension: size)
        guard let textures = pool.textures(width: size, height: size) else {
            throw HarnessError.metalUnavailable
        }
        let poolTextures = [textures.primary, textures.secondary, textures.tertiary]
        let resources = [source, blend, opacity]
        let poolIsPairwiseDistinct = poolTextures.indices.allSatisfy { first in
            poolTextures.indices.allSatisfy { second in
                first == second || poolTextures[first] !== poolTextures[second]
            }
        }
        let resourcesDoNotAliasPool = resources.allSatisfy { resource in
            poolTextures.allSatisfy { resource !== $0 }
        }
        let resourcesArePairwiseDistinct = resources.indices.allSatisfy { first in
            resources.indices.allSatisfy { second in
                first == second || resources[first] !== resources[second]
            }
        }
        let layer = SceneRenderDescriptor.Layer(
            contentKind: "image",
            colorRGB: nil,
            colorBlendMode: nil,
            effects: []
        )
        let masks = SceneImageLayerMasks(
            iris: nil,
            opacity: nil,
            water: nil,
            waterUVScale: SIMD2(repeating: 1),
            foliage: nil,
            foliageUVScale: SIMD2(repeating: 1),
            waterRippleNormal: nil,
            foliageSwayEffects: [:],
            waterRippleEffects: [:],
            depthParallaxEffects: [:],
            blendEffects: [:],
            shakeEffects: [:],
            filmGrainEffects: [:],
            standardBlurEffects: [:],
            waterFlowEffects: [:],
            waterWavesEffects: [:],
            waterCausticsEffects: [:],
            cursorRippleEffects: [:],
            opacityEffects: [:],
            pulseEffects: [:],
            tintEffects: [:],
            godraysEffects: [:],
            shineEffects: [:],
            xRay: SceneXRayEffectTextures(blend: blend, halo: nil, opacityMask: opacity)
        )
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let encoded = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: layer,
                texture: source,
                masks: masks,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 0,
                    alpha: 1,
                    cursorUV: SIMD2(repeating: 0.5),
                    cursorIsInside: true
                ),
                offscreenTexturePool: pool,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false,
                authoredEffectChain: xRayChain(layerID: 2998757800),
                dynamicValues: .empty(frameIndex: 19)
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw HarnessError.commandFailed
        }

        let center = size / 2
        let mainPixel = pixel(target, x: center, y: center)
        let sourcePixel = pixel(source, x: center, y: center)
        let blendPixel = pixel(blend, x: center, y: center)
        let poolPixels = try poolTextures.map { texture -> [UInt8] in
            let bytes = try textureBytes(texture, queue: queue)
            let offset = ((center * texture.width) + center) * 4
            return Array(bytes[offset..<(offset + 4)])
        }
        return [
            "encoded": encoded,
            "poolIsPairwiseDistinct": poolIsPairwiseDistinct,
            "resourcesDoNotAliasPool": resourcesDoNotAliasPool,
            "resourcesArePairwiseDistinct": resourcesArePairwiseDistinct,
            "mainPixel": mainPixel,
            "sourcePixel": sourcePixel,
            "blendPixel": blendPixel,
            "mainMatchesPoolOutput": poolPixels.contains(mainPixel),
        ]
    }

    static func xRayChain(layerID: Int) -> SceneAuthoredEffectExecutionChain {
        let effectKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "\(layerID)#effect#0"
        )
        let input = graphTexture(.layerSource, layerID: layerID)
        let output = graphTexture(
            .effectOutput,
            layerID: layerID,
            effect: effectKey
        )
        let node = Graph.Node(
            nodeIndex: 0,
            effect: effectKey,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: "materials/effects/xray.json",
            materialPassID: "materials/effects/xray.json#0",
            target: output,
            bindings: [],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath: "effects/xray/effect.json",
            input: input,
            output: output,
            nodeIndices: [0]
        )
        let graph = Graph(
            layerID: layerID,
            effects: [effect],
            renderTargets: [],
            nodes: [node],
            finalOutput: output,
            blockers: []
        )
        let stage = SceneAuthoredEffectExecutionPlan(
            layerID: layerID,
            renderGraph: graph,
            backend: .xRay(SceneXRayExecutionPlan(
                declaration: SceneXRayRuntimePlanner.Declaration()
            )),
            materialNodeCount: 1,
            logicalRenderTargetCount: 0
        )
        return SceneAuthoredEffectExecutionChain(
            layerID: layerID,
            renderGraph: graph,
            stages: [stage]
        )
    }

    static func drawAuthoredBlur(
        source: MTLTexture,
        target: MTLTexture,
        layer: SceneRenderDescriptor.Layer,
        plan: SceneAuthoredEffectExecutionPlan,
        pool: SceneOffscreenTexturePool,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        masks: SceneImageLayerMasks = .empty
    ) throws {
        guard let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        guard compositor.draw(
            SceneImageLayerDrawRequest(
                layer: layer,
                texture: source,
                masks: masks,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 0, alpha: 1, cursorUV: .zero
                ),
                offscreenTexturePool: pool,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: plan,
                blocksLegacyGaussianBlur: false
            ),
            pipeline: pipeline,
            mainPass: mainPass
        ) else {
            throw HarnessError.drawRefused
        }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
    }

    static func alphaAwareDownsamplePixel(
        device: MTLDevice,
        queue: MTLCommandQueue
    ) throws -> [UInt8] {
        guard let pipeline = SceneStandardBlurPipeline(device: device),
              let source = makeTexture(device: device, size: 4, usage: .shaderRead),
              let target = makeTexture(
                  device: device,
                  size: 1,
                  usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        let colors: [[UInt8]] = [
            [0, 0, 255, 255],
            [0, 255, 0, 128],
            [255, 0, 0, 64],
            [255, 255, 255, 0],
        ]
        var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
        for y in 0..<source.height {
            for x in 0..<source.width {
                let quadrant = (y >= source.height / 2 ? 2 : 0)
                    + (x >= source.width / 2 ? 1 : 0)
                let offset = (y * source.width + x) * 4
                bytes.replaceSubrange(offset..<(offset + 4), with: colors[quadrant])
            }
        }
        source.replace(
            region: MTLRegionMake2D(0, 0, source.width, source.height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: source.width * 4
        )
        guard pipeline.encodeDownsample(
            source: source,
            target: target,
            commandBuffer: commandBuffer
        ) else {
            throw HarnessError.encoderUnavailable
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return pixel(target, x: 0, y: 0)
    }

    static func standardBlurMaskPixels(
        device: MTLDevice,
        queue: MTLCommandQueue
    ) throws -> [[UInt8]] {
        guard let pipeline = SceneStandardBlurPipeline(device: device),
              let blurred = makeTexture(device: device, size: 1, usage: .shaderRead),
              let previous = makeTexture(device: device, size: 1, usage: .shaderRead),
              let mask = makeTexture(device: device, size: 1, usage: .shaderRead),
              let output = makeTexture(
                  device: device,
                  size: 1,
                  usage: [.renderTarget, .shaderRead]
              ) else {
            throw HarnessError.metalUnavailable
        }
        let previousPixel: [UInt8] = [20, 40, 80, 100]
        let blurredPixel: [UInt8] = [100, 80, 40, 200]
        fill(previous, bgra: previousPixel)
        fill(blurred, bgra: blurredPixel)

        return try [0, 128, 255].map { maskValue in
            fill(mask, bgra: [0, 0, UInt8(maskValue), 255])
            guard let commandBuffer = queue.makeCommandBuffer(),
                  pipeline.encodeCombine(
                      blurred: blurred,
                      mask: mask,
                      maskUVScale: SIMD2(repeating: 1),
                      maskSampling: .linearClamp,
                      previous: previous,
                      target: output,
                      commandBuffer: commandBuffer
                  ) else {
                throw HarnessError.drawRefused
            }
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            guard commandBuffer.status == .completed else {
                throw HarnessError.commandFailed
            }
            return pixel(output, x: 0, y: 0)
        }
    }

    static func standardBlurOverridesLegacy() -> Bool {
        let layer = standardBlurLayer()
        let legacy = SceneEffectRuntimePlanner.plan(
            for: layer,
            hasIrisMask: false,
            hasOpacityMask: false,
            hasWaterMask: false,
            hasFoliageMask: false,
            hasWaterRippleNormal: false
        )
        let authored = SceneEffectRuntimePlanner.plan(
            for: layer,
            hasIrisMask: false,
            hasOpacityMask: false,
            hasWaterMask: false,
            hasFoliageMask: false,
            hasWaterRippleNormal: false,
            authoredEffectPlan: authoredStandardBlurPlan()
        )
        return legacy.gaussianBlur != nil
            && authored.standardBlur != nil
            && authored.gaussianBlur == nil
            && authored.offscreenPassCount == 4
    }

    static func standardBlurLayer() -> SceneRenderDescriptor.Layer {
        let empty = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            texturePaths: [], textureSlots: [], combos: [:], constantShaderValues: [:]
        )
        let scaled = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            texturePaths: [],
            textureSlots: [],
            combos: [:],
            constantShaderValues: ["scale": .init(components: [0.6, 0.6])]
        )
        return SceneRenderDescriptor.Layer(
            contentKind: "image",
            colorRGB: nil,
            colorBlendMode: nil,
            effects: [.init(
                file: "effects/blur/effect.json",
                visible: true,
                passes: [empty, scaled, scaled, empty]
            )]
        )
    }

    static func authoredStandardBlurPlan(
        layerID: Int = 530,
        effectIndex: Int = 0,
        input: Graph.TextureIdentity? = nil,
        maskTexturePath: String? = nil
    ) -> SceneAuthoredEffectExecutionPlan {
        let graph = standardBlurGraph(
            layerID: layerID,
            effectIndex: effectIndex,
            input: input
        )
        return SceneAuthoredEffectExecutionPlan(
            layerID: graph.layerID,
            renderGraph: graph,
            backend: .standardBlur(SceneStandardBlurPlan(
                horizontalStep: 0.6,
                verticalStep: 0.6,
                renderTargetScale: 4,
                effectDescriptorID: "\(layerID)#effect#\(effectIndex)",
                maskTexturePath: maskTexturePath
            )),
            materialNodeCount: 4,
            logicalRenderTargetCount: 2,
            inputRole: input == nil ? .layerSource : .priorEffectOutput
        )
    }

    static func authoredTwoStageBlurChain() -> SceneAuthoredEffectExecutionChain {
        let layerID = 840
        let first = authoredStandardBlurPlan(layerID: layerID)
        let second = authoredStandardBlurPlan(
            layerID: layerID,
            effectIndex: 1,
            input: first.renderGraph.finalOutput
        )
        let graph = Graph(
            layerID: layerID,
            effects: first.renderGraph.effects + second.renderGraph.effects,
            renderTargets: first.renderGraph.renderTargets + second.renderGraph.renderTargets,
            nodes: first.renderGraph.nodes + second.renderGraph.nodes,
            finalOutput: second.renderGraph.finalOutput,
            blockers: []
        )
        return SceneAuthoredEffectExecutionChain(
            layerID: layerID,
            renderGraph: graph,
            stages: [first, second]
        )
    }

    static func authoredWorkshopGradientChain() -> SceneAuthoredEffectExecutionChain {
        let layerID = 845
        let effectKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "\(layerID)#effect#0"
        )
        let input = graphTexture(.layerSource, layerID: layerID)
        let output = graphTexture(.effectOutput, layerID: layerID, effect: effectKey)
        let node = Graph.Node(
            nodeIndex: 0,
            effect: effectKey,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: "materials/workshop/gradient.json",
            materialPassID: "materials/workshop/gradient.json#0",
            target: output,
            bindings: [],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath: "effects/workshop/gradient/effect.json",
            input: input,
            output: output,
            nodeIndices: [0]
        )
        let graph = Graph(
            layerID: layerID,
            effects: [effect],
            renderTargets: [],
            nodes: [node],
            finalOutput: output,
            blockers: []
        )
        let stage = SceneAuthoredEffectExecutionPlan(
            layerID: layerID,
            renderGraph: graph,
            backend: .workshopGradient(.init(layerID: layerID, renderGraph: graph)),
            materialNodeCount: 1,
            logicalRenderTargetCount: 0
        )
        return SceneAuthoredEffectExecutionChain(
            layerID: layerID,
            renderGraph: graph,
            stages: [stage]
        )
    }

    static func authoredClippingMaskChain() -> SceneAuthoredEffectExecutionChain {
        let layerID = 846
        let effectKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "\(layerID)#effect#0"
        )
        let input = graphTexture(.layerSource, layerID: layerID)
        let output = graphTexture(.effectOutput, layerID: layerID, effect: effectKey)
        let node = Graph.Node(
            nodeIndex: 0,
            effect: effectKey,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: "materials/workshop/clipping_mask.json",
            materialPassID: "materials/workshop/clipping_mask.json#0",
            target: output,
            bindings: [],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath: "effects/workshop/clipping_mask/effect.json",
            input: input,
            output: output,
            nodeIndices: [0]
        )
        let graph = Graph(
            layerID: layerID,
            effects: [effect],
            renderTargets: [],
            nodes: [node],
            finalOutput: output,
            blockers: []
        )
        let clipping = SceneClippingMaskExecutionPlan(
            layerID: layerID,
            effectKey: effectKey,
            renderGraph: graph,
            providerLayerID: 1,
            blendMode: 0,
            profile: .classic
        )
        let stage = SceneAuthoredEffectExecutionPlan(
            layerID: layerID,
            renderGraph: graph,
            backend: .clippingMask(clipping),
            materialNodeCount: 1,
            logicalRenderTargetCount: 0
        )
        return SceneAuthoredEffectExecutionChain(
            layerID: layerID,
            renderGraph: graph,
            stages: [stage]
        )
    }

    static func authoredOpacityChain(
        alpha: Float = 1,
        maskTexturePath: String? = nil
    ) -> SceneAuthoredEffectExecutionChain {
        let layerID = 850
        let effectKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "\(layerID)#effect#0"
        )
        let input = graphTexture(.layerSource, layerID: layerID)
        let output = graphTexture(.effectOutput, layerID: layerID, effect: effectKey)
        let node = Graph.Node(
            nodeIndex: 0,
            effect: effectKey,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: "materials/effects/opacity.json",
            materialPassID: "materials/effects/opacity.json#0",
            target: output,
            bindings: [],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath: "effects/opacity/effect.json",
            input: input,
            output: output,
            nodeIndices: [0]
        )
        let graph = Graph(
            layerID: layerID,
            effects: [effect],
            renderTargets: [],
            nodes: [node],
            finalOutput: output,
            blockers: []
        )
        let stage = SceneAuthoredEffectExecutionPlan(
            layerID: layerID,
            renderGraph: graph,
            backend: .opacity(SceneOpacityExecutionPlan(
                staticOrFallbackAlpha: alpha,
                liveEffectIndex: 0,
                maskTexturePath: maskTexturePath,
                effectKey: effectKey
            )),
            materialNodeCount: 1,
            logicalRenderTargetCount: 0
        )
        return SceneAuthoredEffectExecutionChain(
            layerID: layerID,
            renderGraph: graph,
            stages: [stage]
        )
    }

    static func authoredBlendChain(
        multiply: Float,
        alphaMultiply: Float = 1,
        writesAlpha: Bool = false
    ) -> SceneAuthoredEffectExecutionChain {
        let layerID = authoredBlendLayerID
        let effectKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: authoredBlendEffectID
        )
        let input = graphTexture(.layerSource, layerID: layerID)
        let output = graphTexture(.effectOutput, layerID: layerID, effect: effectKey)
        let node = Graph.Node(
            nodeIndex: 0,
            effect: effectKey,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: "materials/effects/blend.json",
            materialPassID: "materials/effects/blend.json#0",
            target: output,
            bindings: [],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath: "effects/blend/effect.json",
            input: input,
            output: output,
            nodeIndices: [0]
        )
        let graph = Graph(
            layerID: layerID,
            effects: [effect],
            renderTargets: [],
            nodes: [node],
            finalOutput: output,
            blockers: []
        )
        let blend = SceneBlendExecutionPlan(
            layerID: layerID,
            effectKey: effectKey,
            renderGraph: graph,
            shaderProfile: .legacySingleTexture,
            blendMode: 0,
            multiply: multiply,
            alphaMultiply: alphaMultiply,
            writesAlpha: writesAlpha,
            assetTexturePath: authoredBlendAssetPath,
            userPropertyKey: nil
        )
        let stage = SceneAuthoredEffectExecutionPlan(
            layerID: layerID,
            renderGraph: graph,
            backend: .blend(blend),
            materialNodeCount: 1,
            logicalRenderTargetCount: 0
        )
        return SceneAuthoredEffectExecutionChain(
            layerID: layerID,
            renderGraph: graph,
            stages: [stage]
        )
    }

    static func authoredBlendRuntimeSummary() -> String? {
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            texturePaths: [authoredBlendAssetPath],
            textureSlots: [nil, authoredBlendAssetPath],
            combos: ["BLENDMODE": 0],
            constantShaderValues: ["multiply": .init(components: [0.5])]
        )
        let layer = SceneRenderDescriptor.Layer(
            contentKind: "solid",
            colorRGB: [0, 0, 0],
            colorBlendMode: nil,
            effects: [.init(
                file: "effects/blend/effect.json",
                visible: true,
                passes: [pass]
            )]
        )
        return SceneEffectRuntimePlanner.runtimeSummary(
            for: layer,
            authoredEffectPlan: authoredBlendChain(multiply: 0.5).stages[0]
        )
    }

    static func authoredTransformChain() -> SceneAuthoredEffectExecutionChain {
        let layerID = 852
        let effectKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "\(layerID)#effect#0"
        )
        let input = graphTexture(.layerSource, layerID: layerID)
        let output = graphTexture(.effectOutput, layerID: layerID, effect: effectKey)
        let node = Graph.Node(
            nodeIndex: 0,
            effect: effectKey,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: "materials/effects/transform.json",
            materialPassID: "materials/effects/transform.json#0",
            target: output,
            bindings: [],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath: "effects/transform/effect.json",
            input: input,
            output: output,
            nodeIndices: [0]
        )
        let graph = Graph(
            layerID: layerID,
            effects: [effect],
            renderTargets: [],
            nodes: [node],
            finalOutput: output,
            blockers: []
        )
        let stage = SceneAuthoredEffectExecutionPlan(
            layerID: layerID,
            renderGraph: graph,
            backend: .transform(SceneTransformExecutionPlan(renderGraph: graph)),
            materialNodeCount: 1,
            logicalRenderTargetCount: 0
        )
        return SceneAuthoredEffectExecutionChain(
            layerID: layerID,
            renderGraph: graph,
            stages: [stage]
        )
    }

    static func authoredEffectMasks(
        blendEffects: [String: SceneBlendEffectTextures] = [:],
        tintMask: MTLTexture? = nil,
        tintMaskPath: String? = nil
    ) -> SceneImageLayerMasks {
        SceneImageLayerMasks(
            iris: nil,
            opacity: nil,
            water: nil,
            waterUVScale: SIMD2(repeating: 1),
            foliage: nil,
            foliageUVScale: SIMD2(repeating: 1),
            waterRippleNormal: nil,
            foliageSwayEffects: [:],
            waterRippleEffects: [:],
            depthParallaxEffects: [:],
            blendEffects: blendEffects,
            shakeEffects: [:],
            filmGrainEffects: [:],
            standardBlurEffects: [:],
            waterFlowEffects: [:],
            waterWavesEffects: [:],
            waterCausticsEffects: [:],
            cursorRippleEffects: [:],
            opacityEffects: [:],
            pulseEffects: [:],
            tintEffects: ["851#effect#0": SceneTintEffectTextures(
                mask: tintMask,
                maskUVScale: SIMD2(repeating: 1),
                maskPath: tintMaskPath
            )],
            godraysEffects: [:],
            shineEffects: [:],
            xRay: nil
        )
    }

    static func authoredTintChain(
        blendMode: Int,
        maskPath: String? = nil
    ) -> SceneAuthoredEffectExecutionChain {
        let layerID = 851
        let effectKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "\(layerID)#effect#0"
        )
        let input = graphTexture(.layerSource, layerID: layerID)
        let output = graphTexture(.effectOutput, layerID: layerID, effect: effectKey)
        let node = Graph.Node(
            nodeIndex: 0,
            effect: effectKey,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: "materials/effects/tint.json",
            materialPassID: "materials/effects/tint.json#0",
            target: output,
            bindings: [],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath: "effects/tint/effect.json",
            input: input,
            output: output,
            nodeIndices: [0]
        )
        let graph = Graph(
            layerID: layerID,
            effects: [effect],
            renderTargets: [],
            nodes: [node],
            finalOutput: output,
            blockers: []
        )
        let stage = SceneAuthoredEffectExecutionPlan(
            layerID: layerID,
            renderGraph: graph,
            backend: .tint(SceneTintExecutionPlan(
                effectKey: effectKey,
                shaderProfile: .stock,
                blendMode: blendMode,
                staticOrFallbackColor: SIMD3<Float>(0, 0, 1),
                staticOrFallbackAlpha: 1,
                maskTexturePath: maskPath
            )),
            materialNodeCount: 1,
            logicalRenderTargetCount: 0
        )
        return SceneAuthoredEffectExecutionChain(
            layerID: layerID,
            renderGraph: graph,
            stages: [stage]
        )
    }

    static func authoredFailingSecondStageChain() -> SceneAuthoredEffectExecutionChain {
        let valid = authoredTwoStageBlurChain()
        let first = valid.stages[0]
        let second = valid.stages[1]
        let duplicateTarget = second.renderGraph.renderTargets[0].texture
        let invalidContrast = SceneLocalContrastPlan(
            firstQuarterTarget: duplicateTarget,
            secondQuarterTarget: duplicateTarget,
            renderGraph: second.renderGraph,
            staticOrFallbackStrength: 1
        )
        let failingSecond = SceneAuthoredEffectExecutionPlan(
            layerID: second.layerID,
            renderGraph: second.renderGraph,
            backend: .localContrast(invalidContrast),
            materialNodeCount: second.materialNodeCount,
            logicalRenderTargetCount: second.logicalRenderTargetCount,
            inputRole: second.inputRole
        )
        return SceneAuthoredEffectExecutionChain(
            layerID: valid.layerID,
            renderGraph: valid.renderGraph,
            stages: [first, failingSecond]
        )
    }

    static func foliageInputs(mode: Int) -> SceneLayerEffectInputs {
        let values: [String: SceneDocument.ShaderValue] = [
            "strength": .init(components: [0.4]),
            "speeduv": .init(components: [5]),
            "phase": .init(components: [0.57]),
            "power": .init(components: [1]),
            "scale": .init(components: [0.05]),
            "ratio": .init(components: [0.3]),
            "scrolldirection": .init(components: [-0.5]),
        ]
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            texturePaths: ["mask"],
            textureSlots: [nil, "mask"],
            combos: ["MODE": mode],
            constantShaderValues: values
        )
        let layer = SceneRenderDescriptor.Layer(
            contentKind: "image",
            colorRGB: nil,
            colorBlendMode: nil,
            effects: [.init(
                file: "effects/foliagesway/effect.json",
                visible: true,
                passes: [pass]
            )]
        )
        return SceneEffectRuntimePlanner.plan(
            for: layer,
            hasIrisMask: false,
            hasOpacityMask: false,
            hasWaterMask: false,
            hasFoliageMask: true,
            hasWaterRippleNormal: false
        ).inputs
    }

    static func makeTexture(
        device: MTLDevice,
        size: Int,
        usage: MTLTextureUsage,
        pixelFormat: MTLPixelFormat = .bgra8Unorm
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    static func gaussianKernelEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue
    ) throws -> [String: Any] {
        let size = 9
        guard let pipeline = SceneGaussianBlurPipeline(device: device),
              let source = makeTexture(
                  device: device,
                  size: size,
                  usage: [.shaderRead, .renderTarget]
              ) else {
            throw HarnessError.drawRefused
        }
        fillPixels(source) { x, y in
            x == size / 2 && y == size / 2
                ? [255, 255, 255, 255]
                : [0, 0, 0, 0]
        }
        func render(_ kernel: SceneGaussianBlurKernel) throws -> [UInt8] {
            guard let target = makeTexture(
                      device: device,
                      size: size,
                      usage: [.shaderRead, .renderTarget]
                  ),
                  let commandBuffer = queue.makeCommandBuffer(),
                  pipeline.encode(
                      source: source,
                      target: target,
                      step: SIMD2(1 / Float(size), 0),
                      kernel: kernel,
                      commandBuffer: commandBuffer
                  ) else {
                throw HarnessError.drawRefused
            }
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            guard commandBuffer.status == .completed else {
                throw HarnessError.commandFailed
            }
            return try textureBytes(target, queue: queue)
        }
        let large = try render(.large)
        let medium = try render(.medium)
        let small = try render(.small)
        func alphaRow(_ bytes: [UInt8]) -> [UInt8] {
            (0..<size).map { x in
                bytes[(((size / 2) * size + x) * 4) + 3]
            }
        }
        return [
            "largeAlpha": alphaRow(large),
            "mediumAlpha": alphaRow(medium),
            "smallAlpha": alphaRow(small),
            "allPremultiplied": [large, medium, small].allSatisfy(isPremultiplied),
        ]
    }

    static func fillPremultipliedImpulse(_ texture: MTLTexture) {
        fillPixels(texture) { x, y in
            switch (x, y) {
            case (1, 1): return [0, 0, 224, 255]
            case (5, 2): return [96, 0, 0, 128]
            case (2, 6): return [0, 48, 0, 64]
            case (6, 5): return [0, 180, 180, 255]
            default: return [0, 0, 0, 0]
            }
        }
    }

    static func fillPremultipliedCheckerboard(_ texture: MTLTexture) {
        let colors: [[UInt8]] = [
            [0, 0, 96, 255],
            [0, 40, 0, 128],
            [12, 0, 0, 64],
            [0, 0, 0, 0],
        ]
        fillPixels(texture) { x, y in
            let asymmetric = x > y ? 1 : 0
            return colors[((x / 2) + ((y / 3) * 2) + asymmetric) % colors.count]
        }
    }

    static func fillPixels(
        _ texture: MTLTexture,
        colorAt: (Int, Int) -> [UInt8]
    ) {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        for y in 0..<texture.height {
            for x in 0..<texture.width {
                let offset = ((y * texture.width) + x) * 4
                bytes.replaceSubrange(offset..<(offset + 4), with: colorAt(x, y))
            }
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: texture.width * 4
        )
    }

    static func textureBytes(
        _ texture: MTLTexture,
        queue: MTLCommandQueue
    ) throws -> [UInt8] {
        let byteCount = texture.width * texture.height * 4
        var bytes = [UInt8](repeating: 0, count: byteCount)
        if texture.storageMode == .shared {
            texture.getBytes(
                &bytes,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
            return bytes
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let staging = texture.device.makeTexture(descriptor: descriptor),
              let commandBuffer = queue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw HarnessError.readbackFailed
        }
        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
            to: staging,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        staging.getBytes(
            &bytes,
            bytesPerRow: staging.width * 4,
            from: MTLRegionMake2D(0, 0, staging.width, staging.height),
            mipmapLevel: 0
        )
        return bytes
    }

    static func maxDifference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        guard lhs.count == rhs.count else { return Int.max }
        return zip(lhs, rhs).reduce(0) { difference, values in
            max(difference, abs(Int(values.0) - Int(values.1)))
        }
    }

    static func hasMixedAlpha(_ bytes: [UInt8]) -> Bool {
        let alphaValues = Set(stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] })
        return [UInt8(0), 64, 128, 255].allSatisfy(alphaValues.contains)
    }

    static func isPremultiplied(_ bytes: [UInt8]) -> Bool {
        stride(from: 0, to: bytes.count, by: 4).allSatisfy { offset in
            let alpha = Int(bytes[offset + 3]) + 1
            return Int(bytes[offset]) <= alpha
                && Int(bytes[offset + 1]) <= alpha
                && Int(bytes[offset + 2]) <= alpha
        }
    }

    static func fillQuadrants(_ texture: MTLTexture) {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        for y in 0..<texture.height {
            for x in 0..<texture.width {
                let color: [UInt8]
                switch (x >= texture.width / 2, y >= texture.height / 2) {
                case (false, false): color = [0, 0, 255, 255]
                case (true, false): color = [0, 255, 0, 255]
                case (false, true): color = [255, 0, 0, 255]
                case (true, true): color = [255, 255, 255, 255]
                }
                let offset = (y * texture.width + x) * 4
                bytes.replaceSubrange(offset..<(offset + 4), with: color)
            }
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: texture.width * 4
        )
    }

    static func fill(_ texture: MTLTexture, bgra: [UInt8]) {
        var bytes = [UInt8]()
        bytes.reserveCapacity(texture.width * texture.height * 4)
        for _ in 0..<(texture.width * texture.height) {
            bytes.append(contentsOf: bgra)
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: texture.width * 4
        )
    }

    static func pixel(_ texture: MTLTexture, x: Int, y: Int) -> [UInt8] {
        var value = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &value,
            bytesPerRow: 4,
            from: MTLRegionMake2D(x, y, 1, 1),
            mipmapLevel: 0
        )
        return value
    }

    enum HarnessError: Error {
        case metalUnavailable
        case baseTextureUnavailable
        case deviceUnavailable
        case queueUnavailable
        case imagePipelineUnavailable
        case imageBlendPipelineUnavailable
        case compositorUnavailable
        case authoredBlendUnavailable
        case encoderUnavailable
        case commandFailed
        case telemetryCompletionTimedOut
        case drawRefused
        case readbackFailed
    }
}
'''


class SceneFramebufferCaptureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-framebuffer-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-framebuffer-capture"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Metal",
                "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run([str(cls.binary)], capture_output=True, text=True)
        if completed.returncode != 0:
            raise RuntimeError(
                f"framebuffer harness exited {completed.returncode}\n"
                f"stdout:\n{completed.stdout}\n"
                f"stderr:\n{completed.stderr}"
            )
        cls.result = json.loads(completed.stdout)
        cls.stderr = completed.stderr

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_current_frame_can_be_captured_without_read_write_aliasing(self) -> None:
        self.assertTrue(self.result["drew"])
        self.assertFalse(self.result["refusedWithoutPool"])
        self.assertEqual(self.result["centerBGRA"], [0, 0, 255, 255])
        self.assertEqual(self.result["bottomRightBGRA"], [255, 255, 255, 255])

    def test_film_grain_uses_noise_without_corrupting_alpha(self) -> None:
        evidence = self.result["filmGrain"]
        self.assertTrue(evidence["alphaPreserved"], evidence)
        self.assertGreater(evidence["changedRGB"], 16, evidence)
        self.assertGreater(evidence["animatedRGB"], 4, evidence)
        self.assertTrue(evidence["invalidRejected"], evidence)

    def test_static_base_color_candidate_is_atomic_at_final_gpu_split(self) -> None:
        evidence = self.result["baseColorCandidate"]
        self.assertTrue(evidence["referenceEncoded"], evidence)
        self.assertTrue(evidence["candidateEncoded"], evidence)
        self.assertTrue(evidence["matchesLegacyPixels"], evidence)
        self.assertTrue(evidence["fractionalPremultipliedPixelPreserved"], evidence)
        self.assertTrue(evidence["effectfulReferenceEncoded"], evidence)
        self.assertTrue(evidence["effectfulCandidateEncoded"], evidence)
        self.assertTrue(evidence["effectfulMatchesLegacyPixels"], evidence)
        for key in (
            "wrongPurposeRejected",
            "mismatchedTextureRejected",
            "nonIdentityRejected",
            "nearestRejected",
            "repeatRejected",
            "clampBorderRejected",
            "effectfulWrongPurposeRejected",
            "effectfulMismatchedTextureRejected",
        ):
            self.assertTrue(evidence[key], (key, evidence))

    def test_capture_telemetry_waits_for_gpu_completion(self) -> None:
        self.assertIn("phase=utility-capture layer=701 status=succeeded", self.stderr)
        self.assertIn("phase=utility-capture layer=702 status=failed", self.stderr)

        evidence = self.result["gpuCompletionTelemetry"]
        self.assertEqual(
            evidence["completionHandler"],
            {
                "encodingFailureObserved": False,
                "commandBufferSuccessObserved": True,
                "commandBufferFailureObserved": False,
                "reportedSuccess": True,
                "reportedFailure": False,
            },
        )
        self.assertEqual(
            evidence["encodingFailure"],
            {
                "encodingFailureObserved": True,
                "commandBufferSuccessObserved": False,
                "commandBufferFailureObserved": False,
                "reportedSuccess": False,
                "reportedFailure": True,
            },
        )

    def test_gpu_completion_telemetry_keeps_independent_sticky_facts(self) -> None:
        evidence = self.result["gpuCompletionTelemetry"]
        self.assertEqual(
            evidence["failureThenCompletion"],
            {
                "encodingFailureObserved": True,
                "commandBufferSuccessObserved": True,
                "commandBufferFailureObserved": False,
                "reportedSuccess": True,
                "reportedFailure": True,
            },
        )
        self.assertEqual(
            evidence["reducer"]["failureThenSuccessReports"],
            ["failed", "succeeded"],
        )
        self.assertEqual(
            evidence["reducer"]["failureThenSuccess"],
            evidence["failureThenCompletion"],
        )
        self.assertEqual(
            evidence["reducer"]["successThenFailureReports"],
            ["succeeded", "failed"],
        )
        self.assertTrue(evidence["reducer"]["observesAfterFirstSuccess"])
        self.assertFalse(
            evidence["reducer"]["observesAfterBothCommandBufferOutcomes"]
        )
        self.assertEqual(
            evidence["reducer"]["successThenFailure"],
            {
                "encodingFailureObserved": False,
                "commandBufferSuccessObserved": True,
                "commandBufferFailureObserved": True,
                "reportedSuccess": True,
                "reportedFailure": True,
            },
        )

    def test_gpu_completion_telemetry_logs_each_status_at_most_once(self) -> None:
        evidence = self.result["gpuCompletionTelemetry"]["reducer"]
        self.assertEqual(
            evidence["repeatedReports"],
            ["failed", "none", "succeeded", "none", "none"],
        )
        self.assertEqual(
            evidence["repeated"],
            {
                "encodingFailureObserved": True,
                "commandBufferSuccessObserved": True,
                "commandBufferFailureObserved": True,
                "reportedSuccess": True,
                "reportedFailure": True,
            },
        )
        for status in ("failed", "succeeded"):
            message = f"phase=utility-capture layer=703 status={status}"
            self.assertEqual(self.stderr.count(message), 1, self.stderr)

    def test_dependency_blend_modes_preserve_source_alpha(self) -> None:
        self.assert_pixel_close(self.result["noDependencyBGRA"], [32, 64, 128, 128])
        self.assert_pixel_close(self.result["normalDependencyBGRA"], [112, 48, 96, 128])
        self.assert_pixel_close(self.result["darkenDependencyBGRA"], [32, 32, 64, 128])
        self.assert_pixel_close(self.result["darkenHalfAlphaBGRA"], [16, 16, 32, 64])

    def test_authored_clipping_stage_consumes_dependency_once(self) -> None:
        self.assert_pixel_close(
            self.result["authoredClippingMaskBGRA"],
            self.result["normalDependencyBGRA"],
        )
        self.assert_pixel_close(
            self.result["authoredCompositionClippingMaskBGRA"],
            self.result["normalDependencyBGRA"],
        )

    def test_layer_tint_is_applied_to_image_and_solid_content_on_gpu(self) -> None:
        self.assert_pixel_close(self.result["solidTintBGRA"], [191, 128, 64, 255])
        self.assert_pixel_close(self.result["imageTintBGRA"], [191, 128, 64, 255])

    def test_authored_brightness_multiplies_image_layers_but_not_rasterized_text(self) -> None:
        # 白色源 × brightness 0.5：image 通道必须在 GPU 上真的变暗，alpha 不受影响。
        self.assert_pixel_close(self.result["imageBrightnessBGRA"], [128, 128, 128, 255])
        # text 通道的纹理已由 CoreText 乘过同一个 key，compositor 再乘就是二次提亮。
        self.assert_pixel_close(self.result["textBrightnessBGRA"], [255, 255, 255, 255])

    def test_layer_color_blend_reads_the_framebuffer_and_rejects_unknown_modes(self) -> None:
        self.assert_pixel_close(self.result["vividLayerBlendBGRA"], [153, 153, 153, 255], 2)
        # 0.8 image color * warm g_Color4 * 1.25 brightness enters mode 31 before
        # BGRA8Unorm clamps the red output. Green/blue remain below red instead of
        # the old all-white input clipping.
        self.assert_pixel_close(
            self.result["warmAdditiveLayerBlendBGRA"], [166, 208, 255, 255], 2
        )
        self.assertTrue(self.result["invalidLayerBlendRefused"])

    def test_blur_scales_remain_authored_pixels_until_target_normalization(self) -> None:
        for actual, expected in zip(self.result["coarseBlur"], [0.6, 0.6, 4]):
            self.assertAlmostEqual(actual, expected, places=6)
        self.assertFalse(self.result["coarseBlurIsPrecise"])
        for actual, expected in zip(self.result["preciseBlur"], [0.45, 0.45, 1]):
            self.assertAlmostEqual(actual, expected, places=6)
        self.assertTrue(self.result["preciseBlurIsPrecise"])
        self.assertTrue(self.result["blockedPreciseBlurIsNil"])
        self.assertTrue(self.result["authoredExtentMismatchRefused"])

    def test_precise_graph_blur_runs_horizontal_then_vertical_on_mixed_alpha(self) -> None:
        evidence = self.result["authoredPreciseImpulse"]
        self.assertTrue(evidence["encoded"])
        self.assertTrue(evidence["sourceHasMixedAlpha"])
        self.assertTrue(evidence["outputIsPremultiplied"])
        for key in ("inputMaxDelta", "horizontalMaxDelta", "outputMaxDelta"):
            self.assertLessEqual(evidence[key], 1, (key, evidence))
        self.assertLessEqual(evidence["mainMaxDelta"], 2, evidence)
        self.assertGreater(evidence["horizontalToOutputDelta"], 2, evidence)
        self.assertGreater(evidence["sourceToOutputDelta"], 20, evidence)

    def test_gaussian_kernel_variants_use_distinct_bounded_support(self) -> None:
        evidence = self.result["gaussianKernelPixels"]
        self.assertTrue(evidence["allPremultiplied"], evidence)
        self.assertEqual(evidence["mediumAlpha"], [0, 4, 24, 60, 80, 60, 24, 4, 0])
        self.assertEqual(evidence["smallAlpha"], [0, 0, 0, 64, 128, 64, 0, 0, 0])
        self.assertNotEqual(evidence["largeAlpha"], evidence["mediumAlpha"])
        self.assertNotEqual(evidence["largeAlpha"], evidence["smallAlpha"])

    def test_legacy_compose_precise_blur_matches_explicit_fbo_gpu_path(self) -> None:
        explicit = self.result["authoredPreciseImpulse"]
        legacy = self.result["authoredLegacyComposeImpulse"]
        for key in (
            "inputMaxDelta",
            "horizontalMaxDelta",
            "outputMaxDelta",
            "mainMaxDelta",
        ):
            self.assertLessEqual(legacy[key], 2, (key, legacy))
            self.assertLessEqual(abs(legacy[key] - explicit[key]), 1, (key, explicit, legacy))
        self.assertTrue(legacy["sourceHasMixedAlpha"])
        self.assertTrue(legacy["outputIsPremultiplied"])
        self.assertGreater(legacy["sourceToOutputDelta"], 20, legacy)

    def test_legacy_compose_preserves_authored_radius_when_pool_scales_input(self) -> None:
        evidence = self.result["authoredLegacyComposeScaled"]
        self.assertTrue(evidence["encoded"])
        self.assertEqual(evidence["sourceWidth"], 16)
        self.assertEqual(evidence["inputWidth"], 8)
        self.assertLessEqual(evidence["outputMaxDelta"], 1, evidence)
        self.assertGreater(evidence["targetNormalizedOutputDelta"], 1, evidence)
        self.assertTrue(evidence["outputIsPremultiplied"])

    def test_precise_graph_interleaves_copy_and_swap_between_material_nodes(self) -> None:
        evidence = self.result["authoredPreciseInterleave"]
        self.assertLessEqual(evidence["copyMaxDelta"], 1, evidence)
        self.assertLessEqual(evidence["swapMaxDelta"], 1, evidence)
        self.assertTrue(evidence["copyHasPixels"])
        self.assertTrue(evidence["swapHasPixels"])
        self.assertTrue(evidence["copyIsPremultiplied"])
        self.assertTrue(evidence["swapIsPremultiplied"])

    def test_standard_graph_blur_runs_full_ping_pong_chain_on_mixed_alpha(self) -> None:
        evidence = self.result["authoredStandardCheckerboard"]
        self.assertTrue(evidence["encoded"])
        self.assertTrue(evidence["sourceHasMixedAlpha"])
        self.assertTrue(evidence["outputIsPremultiplied"])
        for key in (
            "inputMaxDelta",
            "horizontalMaxDelta",
            "verticalMaxDelta",
            "outputMaxDelta",
        ):
            self.assertLessEqual(evidence[key], 1, (key, evidence))
        self.assertLessEqual(evidence["mainMaxDelta"], 2, evidence)
        self.assertGreater(evidence["horizontalToExpectedVerticalDelta"], 2, evidence)
        self.assertGreater(evidence["verticalToExpectedHorizontalDelta"], 2, evidence)
        self.assertGreater(evidence["horizontalToVerticalDelta"], 2, evidence)
        self.assertGreater(evidence["inputToOutputDelta"], 20, evidence)
        self.assertTrue(self.result["authoredStandardBlurOverridesLegacy"])

    def test_standard_blur_consumes_typed_mask_candidate_and_rejects_wrong_purpose(
        self,
    ) -> None:
        evidence = self.result["authoredStandardCandidate"]
        self.assertTrue(evidence["accepted"], evidence)
        self.assertTrue(evidence["paddedZeroMaskPreservedSource"], evidence)
        self.assertTrue(evidence["wrongPurposeRejected"], evidence)

    def test_standard_blur_combine_uses_red_mask_in_premultiplied_space(self) -> None:
        mask_zero, mask_half, mask_one = self.result["standardBlurMaskPixels"]
        self.assert_pixel_close(mask_zero, [20, 40, 80, 100], 1)
        self.assert_pixel_close(mask_one, [100, 80, 40, 200], 1)
        self.assert_pixel_close(mask_half, [60, 60, 60, 150], 2)

    def test_authored_effect_chain_runs_in_order_without_reapplying_layer_alpha(self) -> None:
        evidence = self.result["authoredTwoStageChain"]
        self.assertTrue(evidence["encoded"])
        self.assertGreater(evidence["sourceToFirstInputDelta"], 20, evidence)
        self.assertLessEqual(evidence["firstOutputToSecondInputDelta"], 1, evidence)
        self.assertGreater(evidence["firstToSecondOutputDelta"], 1, evidence)
        self.assertLessEqual(evidence["secondOutputToMainDelta"], 2, evidence)

    def test_solid_effect_chain_uses_mapped_extent_instead_of_one_pixel_provider(self) -> None:
        evidence = self.result["solidMappedEffectExtent"]
        self.assertTrue(evidence["encoded"])
        self.assertEqual(evidence["sourceSize"], [1, 1])
        self.assertEqual(evidence["offscreenSize"], [64, 36])
        self.assertGreater(evidence["uniqueColorCount"], 8, evidence)

    def test_chain_renderer_resolves_live_values_per_stage_and_neutralizes_recapture(self) -> None:
        source = (SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer.swift").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            "masks: isFirstStage ? masks : masks.authoredEffectResourcesOnly",
            source,
        )
        self.assertIn("sourceUniforms: isFirstStage ? sourceUniforms : .neutral()", source)
        self.assertIn("stage.localContrastStrength(in: dynamicValues)", source)
        opacity_source = (
            SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectChainRenderer+Opacity.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("stage.opacityAlpha(in: dynamicValues)", opacity_source)

    def test_opacity_chain_consumes_live_snapshot_on_gpu(self) -> None:
        authored, live = self.result["authoredOpacityLivePixels"]
        self.assertLessEqual(max(abs(a - b) for a, b in zip(authored, [40, 80, 160, 200])), 1)
        self.assertLessEqual(max(abs(a - b) for a, b in zip(live, [8, 16, 32, 40])), 1)

    def test_opacity_mask_alpha_is_applied_exactly_once(self) -> None:
        # 官方 opacity.frag：`albedo.a *= mask * g_UserAlpha`。源 premultiplied
        # BGRA [40,80,160,200]、mask=0.5、alpha=0.5 → 应为 ×0.25 = [10,20,40,50]。
        # 丢遮罩会得到 ×0.5 = [20,40,80,100]，遮罩或 alpha 乘两次会得到 ×0.125。
        pixel = self.result["authoredOpacityMaskPixel"]
        self.assertLessEqual(
            max(abs(a - b) for a, b in zip(pixel["legacy"], [10, 20, 40, 50])),
            1,
            f"legacy opacity mask route wrong: {pixel['legacy']}",
        )
        self.assertLessEqual(
            max(abs(a - b) for a, b in zip(pixel["authored"], [10, 20, 40, 50])),
            1,
            f"authored opacity dropped the mask: {pixel['authored']}",
        )
        # 声明了遮罩但 opacityEffects 里没有对应贴图时必须整段拒绝：静默按无遮罩渲染
        # 就是这次修的那类缺陷，会让语料里 108 个绑遮罩的 stock opacity pass 不声不响地失效。
        self.assertTrue(pixel["missingMaskRefused"], pixel)

    def test_authored_blend_chain_mixes_overlay_alpha_and_preserves_source_alpha(
        self,
    ) -> None:
        evidence = self.result["authoredBlendChainPixel"]
        source = evidence["source"]
        blend = evidence["blend"]
        weight = evidence["multiply"] * blend[3] / 255
        self.assertTrue(all(channel <= source[3] for channel in source[:3]), evidence)
        self.assertTrue(all(channel <= blend[3] for channel in blend[:3]), evidence)
        expected = [
            round(
                (
                    source[index] / source[3]
                    + (blend[index] / blend[3] - source[index] / source[3])
                    * weight
                )
                * source[3]
            )
            for index in range(3)
        ] + [source[3]]
        self.assertTrue(evidence["encoded"], evidence)
        self.assertEqual(evidence["capturedSourcePixel"], source, evidence)
        self.assertEqual(expected, [69, 68, 143, 200])
        self.assertLessEqual(
            max(
                abs(actual - wanted)
                for actual, wanted in zip(evidence["authoredPixel"], expected)
            ),
            1,
            evidence,
        )
        self.assertEqual(evidence["authoredPixel"][3], source[3])
        self.assert_pixel_close(evidence["mainPixel"], expected, 1)

    def test_authored_blend_write_alpha_uses_overlay_alpha_and_stays_premultiplied(
        self,
    ) -> None:
        evidence = self.result["authoredWriteAlphaBlendChainPixel"]
        source = evidence["source"]
        blend = evidence["blend"]
        output_alpha = round(blend[3] * evidence["alphaMultiply"])
        weight = evidence["multiply"] * blend[3] / 255
        expected = [
            round(
                (
                    source[index] / source[3]
                    + (blend[index] / blend[3] - source[index] / source[3])
                    * weight
                )
                * output_alpha
            )
            for index in range(3)
        ] + [output_alpha]
        self.assertTrue(evidence["encoded"], evidence)
        self.assertTrue(evidence["writesAlpha"], evidence)
        self.assertEqual(expected, [22, 22, 46, 64])
        self.assert_pixel_close(evidence["authoredPixel"], expected, 1)
        self.assert_pixel_close(evidence["mainPixel"], expected, 1)
        self.assertTrue(
            all(channel <= evidence["authoredPixel"][3] for channel in evidence["authoredPixel"][:3]),
            evidence,
        )

    def test_authored_blend_runtime_summary_is_not_route_only(self) -> None:
        self.assertEqual(
            self.result["authoredBlendRuntimeSummary"],
            "effect runtime blend-authored; 1 declared pass(es)",
        )

    def test_identity_transform_applies_first_stage_source_uniforms_once(self) -> None:
        evidence = self.result["authoredTransformChainPixel"]
        expected = [20, 40, 80, 100]
        self.assertTrue(evidence["encoded"], evidence)
        self.assertEqual(evidence["source"], [40, 80, 160, 200], evidence)
        self.assert_pixel_close(evidence["authoredPixel"], expected, 1)
        self.assert_pixel_close(evidence["mainPixel"], expected, 1)

    def test_tint_chain_routes_blend_mode_from_plan_on_gpu(self) -> None:
        # 源 BGRA [40,80,160,200] → A_rgb=(0.6275,0.3137,0.1569)，tint color=(0,0,1)，o=1。
        # mode 0 落到 `mix(A, B, o)` 并强制 alpha=1；mode 30 落到
        # `mix(A, max(A.r,A.g,A.b) * B, o)`（0.6275×蓝）并保留源 alpha。两条结果不同，
        # 证明 blendMode 是从 plan 走到 shader 的，不是写死一个模式。
        mode0, mode30, mode0_masked = self.result["authoredTintChainPixels"]
        self.assertLessEqual(max(abs(a - b) for a, b in zip(mode0, [255, 0, 0, 255])), 1)
        self.assertLessEqual(max(abs(a - b) for a, b in zip(mode30, [160, 0, 0, 200])), 1)
        # 半灰遮罩（0.502）必须在 straight RGB 上混合。源 premultiplied
        # BGRA=(40,80,160), alpha=200 先解预乘为约 (51,102,204)，再与
        # B=(255,0,0) 混合；mode 0 最终强制 alpha=255。
        self.assertLessEqual(
            max(abs(a - b) for a, b in zip(mode0_masked, [153, 51, 102, 255])),
            2,
        )

    def test_failed_later_stage_never_composites_an_earlier_stage(self) -> None:
        evidence = self.result["authoredFailedChain"]
        self.assertFalse(evidence["encoded"])
        self.assertTrue(evidence["firstStageProducedPixels"])
        self.assertEqual(evidence["mainPixel"], [0, 0, 0, 0])

    def test_xray_shared_three_texture_route_has_no_alias_and_propagates_output(
        self,
    ) -> None:
        evidence = self.result["xRayThreeTextureRoute"]
        self.assertTrue(evidence["encoded"], evidence)
        self.assertTrue(evidence["poolIsPairwiseDistinct"], evidence)
        self.assertTrue(evidence["resourcesDoNotAliasPool"], evidence)
        self.assertTrue(evidence["resourcesArePairwiseDistinct"], evidence)
        self.assertTrue(evidence["mainMatchesPoolOutput"], evidence)
        self.assertNotEqual(evidence["mainPixel"], evidence["sourcePixel"], evidence)
        self.assert_pixel_close(evidence["mainPixel"], evidence["blendPixel"], 2)

    def test_standard_blur_downsample_is_alpha_aware(self) -> None:
        self.assert_pixel_close(
            self.result["standardBlurAlphaAwareDownsampleBGRA"],
            [37, 73, 146, 84],
            3,
        )

    def test_single_builtin_foliage_plan_preserves_authored_parameters(self) -> None:
        self.assertNotEqual(self.result["foliageFlags"] & 1, 0)
        expected3 = [0.4, 5, 0.57, 1]
        expected4 = [0.05, 0.3, -0.5, 0]
        for actual, expected in zip(self.result["foliageParams3"], expected3):
            self.assertAlmostEqual(actual, expected, places=6)
        for actual, expected in zip(self.result["foliageParams4"], expected4):
            self.assertAlmostEqual(actual, expected, places=6)
        self.assertEqual(self.result["unsupportedFoliageFlags"] & 1, 0)

    def test_foliage_mask_uses_mapped_to_physical_uv_scale(self) -> None:
        self.assertAlmostEqual(self.result["mappedMaskScale"][0], 0.9375, places=6)
        self.assertAlmostEqual(self.result["mappedMaskScale"][1], 0.52734375, places=6)

    def test_decoded_tex_does_not_reapply_removed_physical_padding(self) -> None:
        self.assertEqual(self.result["decodedMappedScale"], [1, 1])

    def test_static_image_blend_writes_provider_color_and_alpha(self) -> None:
        self.assert_pixel_close(self.result["imageBlendBGRA"], [192, 32, 64, 255])
        self.assert_pixel_close(self.result["halfImageBlendBGRA"], [96, 16, 32, 128])
        self.assert_pixel_close(
            self.result["partialAlphaImageBlendBGRA"], [128, 0, 64, 192]
        )

    def test_gradient_color_runs_before_dependency_clipping_and_preserves_alpha(self) -> None:
        self.assert_pixel_close(self.result["gradientTopBGRA"], [16, 0, 239, 255], 2)
        self.assert_pixel_close(self.result["gradientBottomBGRA"], [239, 0, 16, 255], 2)
        self.assert_pixel_close(self.result["clippedGradientTopBGRA"], [4, 128, 60, 128], 2)

    def test_dependency_mode_reuses_uniform_padding_without_layout_growth(self) -> None:
        self.assertEqual(self.result["fragmentUniformSize"], 176)
        self.assertEqual(self.result["dependencyBlendModeOffset"], 12)

    def assert_pixel_close(
        self, actual: list[int], expected: list[int], tolerance: int = 1
    ) -> None:
        self.assertEqual(len(actual), len(expected))
        for component, wanted in zip(actual, expected):
            self.assertLessEqual(abs(component - wanted), tolerance)


if __name__ == "__main__":
    unittest.main()
