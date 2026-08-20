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
    SOURCE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Clear.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Extent.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetFormat.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphExecutionState.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphExecutionState+Validation.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphExecutionState+Identity.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetTable.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetTable+Mapped.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneLayerFullFramePairPlan.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneLayerGraphTargetPlan.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetLease.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetLease+Publication.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTextureResidency.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTextureAllocationCache.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTextureAllocationCache+SharedPair.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTextureAllocationCache+Batch.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTextureFramePreflight.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTexturePool+PersistentGraphTargets.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/ScenePersistentGraphTargetAllocator.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphCommandRuntime.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphNodeScheduler.swift",
    SOURCE_ROOT / "Rendering/SceneMatrix.swift",
    SOURCE_ROOT / "Rendering/SceneMetalPipeline.swift",
    SOURCE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SOURCE_ROOT / "Rendering/SceneSpriteAnimation.swift",
    SOURCE_ROOT / "Rendering/SceneSourceUpdateTransaction.swift",
    SOURCE_ROOT / "Rendering/SceneMainPassEncoder.swift",
    SOURCE_ROOT / "Rendering/SceneFramebufferSnapshot.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenResolutionPolicy.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTexturePool.swift",
    SOURCE_ROOT / "Resources/SceneTextureSampling.swift",
    SOURCE_ROOT / "Resources/SceneTextureCandidate.swift",
    SOURCE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SOURCE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SOURCE_ROOT / "Rendering/SceneBaseImageTextureCandidateSupport.swift",
    SOURCE_ROOT / "Effects/SceneGaussianBlurPipeline.swift",
    SOURCE_ROOT / "Effects/SceneStandardBlurPipeline.swift",
    SOURCE_ROOT / "Effects/SceneStandardBlurRenderer.swift",
    SOURCE_ROOT / "Effects/SceneLocalContrastPipeline.swift",
    SOURCE_ROOT / "Effects/SceneLocalContrastRenderer.swift",
    SOURCE_ROOT / "Effects/SceneColorGradingPipeline.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopShiftHuePipeline.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopShiftHueRenderer.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopAudioBarsPipeline.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopGradientPipeline.swift",
    SOURCE_ROOT / "Effects/SceneProceduralNoisePipeline.swift",
    SOURCE_ROOT / "Effects/SceneProceduralNoisePipeline+Support.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopShadowPipeline.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopShadowRenderer.swift",
    SOURCE_ROOT / "Effects/SceneBlendPipeline.swift",
    SOURCE_ROOT / "Effects/SceneWaterRipplePipeline.swift",
    SOURCE_ROOT / "Effects/SceneXRayPipeline.swift",
    SOURCE_ROOT / "Effects/SceneBlendModeShaderSource.swift",
    SOURCE_ROOT / "Rendering/SceneLayerColorBlendPipeline.swift",
    SOURCE_ROOT / "Effects/ScenePulsePipeline.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectMaskSemantics.swift",
    SOURCE_ROOT / "Effects/SceneGaussianBlurRuntimePlan.swift",
    SOURCE_ROOT / "Rendering/SceneTextureMappedUVScale.swift",
    SOURCE_ROOT / "Effects/SceneWaterRippleRuntimePlan.swift",
    SOURCE_ROOT / "Effects/SceneEffectStageRuntimeDisposition.swift",
    SOURCE_ROOT / "Effects/SceneOffscreenEffectRenderer.swift",
    SOURCE_ROOT / "Effects/SceneOffscreenEffectRenderer+Capture.swift",
    SOURCE_ROOT / "Runtime/SceneAudioSpectrum.swift",
    SOURCE_ROOT / "Runtime/SceneAudioResponse.swift",
    SOURCE_ROOT / "RenderGraph/SceneProceduralNoiseExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer.swift",
    SOURCE_ROOT
    / "RenderGraph/EffectExecution/SceneEffectStageRenderer+SpecializedStage.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer+CursorRipple.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer+WaterRipple.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer+Rays.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer+Blend.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer+AudioBars.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer+WorkshopGradient.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer+ColorGrading.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer+Pulse.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer+ShiftHue.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer+ProceduralNoise.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer+Transform.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer+XRay.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer+Topology.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer+WorkshopStage.swift",
    SOURCE_ROOT / "Rendering/SceneImageEffectPipelineRepository.swift",
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneAuthoredEffectPipelineSet.swift",
    SOURCE_ROOT / "Rendering/SceneImageLayerDrawRequest.swift",
    SOURCE_ROOT / "Rendering/SceneLayerSourcePassthroughPlan.swift",
    SOURCE_ROOT / "Rendering/SceneResolvedMaterialGraphComposition.swift",
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

final class ExactEvidenceLogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

nonisolated enum SceneFrameTextureIdentity: Hashable {
    case layerSource(Int)
    case namedLayerTarget(SceneNamedTextureReference)
    case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
}

struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let candidate: SceneTextureCandidate
    let contentGeneration: UInt64

    var texture: MTLTexture { candidate.texture }

    var isComplete: Bool {
        guard contentGeneration > 0 else { return false }
        switch (candidate.identity, candidate.generation) {
        case let (.provider(_), .provider(generation)):
            return generation == contentGeneration
        case (.file, .file), (.builtIn, .immutable):
            return true
        default:
            return false
        }
    }
}

struct SceneFrameTextureResource {
    let publication: SceneTextureProviderPublication
    let resourceGeneration: UInt64

    static func reservedNamedLayerTarget(
        reference: SceneNamedTextureReference,
        frameEpoch: UInt64,
        texture: MTLTexture
    ) -> Self? {
        nil
    }

    var isCompleteGraphResource: Bool {
        resourceGeneration > 0
            && resourceGeneration == publication.contentGeneration
    }
}

enum SceneTextureProviderState {}
struct SceneFrameTextureRegistrySnapshot {}

enum SceneFrameTextureRegistry {
    enum ProviderStatus {}
}

enum SceneMediaThumbnailTextureStore {
    struct Snapshot {}
}

enum SceneGraphExecutionResetReason {
    case sceneSwitch, surfaceStop
}

enum SceneResolvedMaterialExecutionCapabilityCatalog {
    struct Token: Hashable { let rawValue: Int }
    struct SceneBackgroundRequirement {}
}

enum SceneResolvedMaterialDependencyOwnership: Equatable {
    case none
    case externalPrimary
}

struct SceneGraphClearFunctionRegistry: Equatable {
    typealias Graph = SceneAuthoredEffectRenderPlan

    struct ClearFunction: Equatable {
        let name: String
        let targets: [Graph.TextureIdentity]
    }

    let functions: [ClearFunction]

    func function(named name: String) -> ClearFunction? {
        functions.first { $0.name == name }
    }
}

struct SceneGraphMaterialFunctionInvocationRequest: Hashable {
    typealias Graph = SceneAuthoredEffectRenderPlan

    let effect: Graph.EffectKey
    let functionName: String
    let frameEpoch: UInt64
}

final class SceneResolvedMaterialRuntimeBridge {
    struct DedicatedFrameInputs {
        let masks: SceneImageLayerMasks
        let dynamicValues: SceneDynamicSnapshot
        let pipelines: SceneAuthoredEffectPipelineSet
        let cursorUV: SIMD2<Float>
        let previousCursorUV: SIMD2<Float>
        let pointerIsInside: Bool
        let previousPointerIsInside: Bool
        let pointerMovement: Float
        let primaryButtonIsDown: Bool
        let layerModelMatrix: simd_float4x4 = matrix_identity_float4x4
        let frameTime: Float
        let time: Float
        let audioSpectrum: SceneAudioSpectrumSnapshot
        let dependencyEffect: SceneDependencyEffectInput?
    }
    struct ExecutionTicket: Hashable {
        let identity: Int
        let consumesExternalPrimaryDependency: Bool
    }
    struct ExactEffectSubject {
        let key: SceneAuthoredEffectRenderPlan.EffectKey
        let family: String
    }
    struct ClaimedExecution {
        let token: SceneResolvedMaterialExecutionCapabilityCatalog.Token
        let layerID: Int
        let admittedGraphs: [SceneAuthoredEffectRenderPlan]
        let targetExecutionPlans: [SceneEffectStageExecutionPlan?]
        let pairPlan: SceneLayerFullFramePairPlan
        let fullFrameExtentPolicy: SceneFullFrameExtentPolicy
        let sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute
        let dependencyOwnership: SceneResolvedMaterialDependencyOwnership
        let clearFunctionsByEffect: [
            SceneAuthoredEffectRenderPlan.EffectKey: SceneGraphClearFunctionRegistry
        ] = [:]
        let sceneBackgroundRequirement:
            SceneResolvedMaterialExecutionCapabilityCatalog.SceneBackgroundRequirement? = nil
    }

    enum ClaimResult {
        case notMigrated
        case rejected(reasonCode: String)
        case claimed(ClaimedExecution)
    }

    enum ExecutionResult {
        case encoded(texture: MTLTexture, ticket: ExecutionTicket)
        case failed(reasonCode: String)
    }

    enum CompositeOutcome {
        case consumed
        case failed(reasonCode: String)
    }

    enum ExecutionEvidenceOutcome {
        case encodedOutput
        case failed(reasonCode: String)
    }

    struct FramePreparationRequest {
        let claim: ClaimedExecution
        let targetPlan: SceneResolvedMaterialFrameTargetPlan
        let sourceTexture: MTLTexture
        let sourceUniforms: SceneLayerFragmentUniforms
        let sourcePipeline: SceneImageLayerPipeline
    }

    enum FramePreparationResult {
        case ready
        case rejected(reasonCode: String)
    }

    let executionShouldSucceed: Bool
    let claimRejectionReason: String?
    let claimedExecution: ClaimedExecution?
    let compositeFailureReason: String?
    private(set) var executeCallCount = 0
    private(set) var markCompositeCallCount = 0
    private(set) var claimedFailureReasons: [String] = []
    private var preparedTexture: MTLTexture?

    init(
        executionShouldSucceed: Bool = true,
        claimRejectionReason: String? = nil,
        claimedExecution: ClaimedExecution? = nil,
        compositeFailureReason: String? = nil
    ) {
        self.executionShouldSucceed = executionShouldSucceed
        self.claimRejectionReason = claimRejectionReason
        self.claimedExecution = claimedExecution
        self.compositeFailureReason = compositeFailureReason
    }

    var assetStates: [SceneAssetTextureIdentity: SceneTextureProviderState] { [:] }
    var shouldDeferFrame: Bool { false }

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

    func deferPreparedFrame() -> Bool { true }

    func invalidate(reason: SceneGraphExecutionResetReason) {}

    func claim(layerID: Int) -> ClaimResult {
        if let claimRejectionReason {
            return .rejected(reasonCode: claimRejectionReason)
        }
        if let claimedExecution, claimedExecution.layerID == layerID {
            return .claimed(claimedExecution)
        }
        return .notMigrated
    }

    func preflightClaim(layerID: Int) -> ClaimResult {
        claim(layerID: layerID)
    }

    func recordClaimedFailure(reasonCode: String) {
        claimedFailureReasons.append(reasonCode)
    }

    func installFrameLocalFallbacks(_ fallbacks: [Int: String]) -> Bool {
        _ = fallbacks
        return true
    }

    func executeClaimed(
        claim: ClaimedExecution,
        dependencyEffect: SceneDependencyEffectInput?,
        sceneBackgroundTexture: MTLTexture? = nil,
        commandBuffer: MTLCommandBuffer
    ) -> ExecutionResult {
        _ = dependencyEffect
        _ = sceneBackgroundTexture
        _ = commandBuffer
        executeCallCount += 1
        return executionShouldSucceed && preparedTexture != nil
            ? .encoded(
                texture: preparedTexture!,
                ticket: .init(
                    identity: executeCallCount,
                    consumesExternalPrimaryDependency:
                        claim.dependencyOwnership == .externalPrimary
                )
            )
            : .failed(reasonCode: "fixture-executor-failed")
    }

    func executionEvidenceFamily(
        for key: SceneAuthoredEffectRenderPlan.EffectKey
    ) -> String? {
        "generic-framebuffer"
    }

    func executionEvidenceSubjects(
        for claim: ClaimedExecution
    ) -> [ExactEffectSubject] {
        claim.admittedGraphs.flatMap { graph in
            graph.effects.map {
                .init(key: $0.key, family: "resolved-material")
            }
        }
    }

    func executionEvidenceOutcome(
        for subject: ExactEffectSubject,
        claim: ClaimedExecution,
        ticket: ExecutionTicket
    ) -> ExecutionEvidenceOutcome {
        _ = subject
        _ = claim
        _ = ticket
        return .encodedOutput
    }

    func prepareFrame(
        _ requests: [FramePreparationRequest],
        pool: SceneOffscreenTexturePool?,
        commandBuffer: MTLCommandBuffer
    ) -> FramePreparationResult {
        _ = pool
        _ = commandBuffer
        guard requests.count == 1 else {
            return .rejected(reasonCode: "fixture-frame-preparation-invalid")
        }
        preparedTexture = requests[0].sourceTexture
        return .ready
    }

    func sealFrame(on commandBuffer: MTLCommandBuffer) -> Bool { true }

    func markComposite(
        _ ticket: ExecutionTicket,
        texture: MTLTexture,
        consumed: Bool
    ) -> CompositeOutcome {
        _ = ticket
        _ = texture
        markCompositeCallCount += 1
        if let compositeFailureReason {
            claimedFailureReasons.append(compositeFailureReason)
            return .failed(reasonCode: compositeFailureReason)
        }
        return consumed
            ? .consumed : .failed(reasonCode: "fixture-composite-not-consumed")
    }

    func auditResolvedMaterials(
        graph: SceneAuthoredEffectRenderPlan,
        targets: SceneGraphRenderTargetTable
    ) {}
}

struct SceneResolvedMaterialAdmittedLayer {
    enum SourceRoute: Equatable {
        case capturedLayerTexture
        case capturedMainTargetTexture
        case transparentDirectDraw
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
        var visible: Bool? = nil
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil
        let colorRGB: [Float]?
        let colorBlendMode: Int?
        var brightness: Double? = nil
        let effects: [EffectDescriptor]
    }
}

struct SceneLayerDisplayScriptOwnership {
    let visible: Bool
    let alpha: Bool
    var isEmpty: Bool { !visible && !alpha }
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
    enum Profile: Sendable {
        case enhancedSegmented(shape: Int)
    }

    let profile: Profile

    var shape: Int {
        switch profile {
        case .enhancedSegmented(let shape): shape
        }
    }
}

struct SceneWorkshopGradientExecutionPlan: Sendable {
    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
}

struct SceneAuthoredShaderFrameInputs: Sendable {}

enum SceneBlendShaderProfile {
    case singleTextureV1
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
    let dependencyProviderLayerID: Int?

    func resolvedMultiply(in snapshot: SceneDynamicSnapshot) -> Float {
        multiply
    }
}

struct SceneTransformExecutionPlan {
    let renderGraph: SceneAuthoredEffectRenderPlan
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

    struct SceneEffectStageExecutionPlan {
    enum Backend {
        case preciseGaussian(SceneGaussianBlurPlan)
        case standardBlur(SceneStandardBlurPlan)
        case localContrast(SceneLocalContrastPlan)
        case colorGrading(SceneColorGradingExecutionPlan)
        case workshopShiftHue(SceneWorkshopShiftHueExecutionPlan)
        case workshopAudioBars(SceneWorkshopAudioBarsExecutionPlan)
        case workshopGradient(SceneWorkshopGradientExecutionPlan)
        case workshopShadow(SceneWorkshopShadowExecutionPlan)
        case proceduralNoise(SceneProceduralNoiseExecutionPlan)
        case shake(SceneShakeExecutionPlan)
        case waterFlow(SceneWaterFlowExecutionPlan)
        case waterWaves(SceneWaterWavesExecutionPlan)
        case waterCaustics(SceneWaterCausticsExecutionPlan)
        case cursorRipple(SceneCursorRippleExecutionPlan)
        case waterRipple(SceneWaterRippleExecutionPlan)
        case depthParallax(SceneDepthParallaxExecutionPlan)
        case xRay(SceneXRayExecutionPlan)
        case blend(SceneBlendExecutionPlan)
        case transform(SceneTransformExecutionPlan)
        case pulse(ScenePulseExecutionPlan)
        case godrays(SceneGodraysPlan)
        case shine(SceneShineExecutionPlan)

        var supportsUnifiedPairLeaf: Bool {
            switch self {
            case .workshopShiftHue, .workshopAudioBars, .workshopGradient,
                 .workshopShadow,
                 .shake:
                return true
            case .proceduralNoise(let plan):
                return plan.variant == .worleyColorV1
                    && plan.dependencyProviderLayerID != nil
                    && plan.dependencySlotIndex == 3
            default:
                return false
            }
        }

        var stableName: String {
            switch self {
            case .preciseGaussian: "precise-gaussian"
            case .standardBlur: "standard-blur"
            case .localContrast: "local-contrast"
            case .colorGrading: "color-grading"
            case .workshopShiftHue: "workshop-shift-hue"
            case .workshopAudioBars: "workshop-audio-bars"
            case .workshopGradient: "workshop-gradient"
            case .workshopShadow: "workshop-shadow"
            case .proceduralNoise: "procedural-noise"
            case .shake: "shake"
            case .waterFlow: "water-flow"
            case .waterWaves: "water-waves"
            case .waterCaustics: "water-caustics"
            case .cursorRipple: "cursor-ripple"
            case .waterRipple: "water-ripple"
            case .depthParallax: "depth-parallax"
            case .xRay: "x-ray"
            case .blend: "blend"
            case .transform: "transform"
            case .pulse: "pulse"
            case .godrays: "godrays"
            case .shine: "shine"
            }
        }
    }

    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let backend: Backend
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole

    init(
        layerID: Int,
        renderGraph: SceneAuthoredEffectRenderPlan,
        backend: Backend,
        materialNodeCount: Int,
        logicalRenderTargetCount: Int,
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) {
        self.layerID = layerID
        self.renderGraph = renderGraph
        self.backend = backend
        self.materialNodeCount = materialNodeCount
        self.logicalRenderTargetCount = logicalRenderTargetCount
        self.inputRole = inputRole
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

    var godrays: SceneGodraysPlan? {
        guard case .godrays(let plan) = backend else { return nil }
        return plan
    }

    var shine: SceneShineExecutionPlan? {
        guard case .shine(let plan) = backend else { return nil }
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

    var executionFamilyStableName: String {
        backend.stableName
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
        if case .preciseGaussian = backend {
            return !supportsUnifiedFullFrameComposeStage
        }
        return false
    }

    var supportsUnifiedLogicalTargetStage: Bool {
        switch backend {
        case .preciseGaussian:
            return logicalRenderTargetCount > 0
                && !supportsUnifiedFullFrameComposeStage
        case .standardBlur:
            return true
        case .localContrast:
            return true
        case .godrays(let plan):
            return (plan.direction == nil && !plan.usesDirectionalGaussianKernel)
                || (plan.direction?.isFinite == true && plan.usesDirectionalGaussianKernel)
        case .shine:
            return true
        default:
            return false
        }
    }

    var supportsUnifiedHistoryTargetStage: Bool {
        guard case .cursorRipple = backend else { return false }
        return logicalRenderTargetCount == 2
            && renderGraph.nodes.count == 3
            && renderGraph.renderTargets.count == 2
            && renderGraph.renderTargets.allSatisfy { !$0.declaredUnique }
    }

    var supportsUnifiedFullFrameComposeStage: Bool {
        guard case .preciseGaussian = backend,
              logicalRenderTargetCount == 0,
              renderGraph.renderTargets.isEmpty,
              renderGraph.effects.count == 1,
              let effect = renderGraph.effects.first,
              renderGraph.nodes.count == 2 else { return false }
        let nodes = renderGraph.nodes
        return nodes[0].kind == .material
            && nodes[0].target == effect.output
            && nodes[0].bindings.isEmpty
            && nodes[0].compose == .bool(true)
            && nodes[1].kind == .material
            && nodes[1].target == effect.output
            && nodes[1].bindings.isEmpty
            && nodes[1].compose == nil
    }

    func localContrastStrength(in snapshot: SceneDynamicSnapshot) -> Float? {
        guard let localContrast else { return nil }
        let effectIndex = renderGraph.effects.first?.key.effectIndex ?? -1
        return snapshot.strengthsByEffectIndex[effectIndex]
            ?? localContrast.staticOrFallbackStrength
    }

}

struct SceneShakeExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    var audio: SceneAudioResponse.Parameters? = nil
}

struct SceneShakeEffectTextures {
    let maskBinding: SceneTextureSlotBinding?
}

struct SceneSpotLightPipeline {
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {}
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

struct SceneWaterFlowEffectTextures {
    func matches(_ plan: SceneWaterFlowExecutionPlan) -> Bool { false }
}

struct SceneWaterFlowPipeline {
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {}
}

enum SceneWaterFlowRenderer {
    static func render(
        plan: SceneWaterFlowExecutionPlan,
        resources: SceneWaterFlowEffectTextures,
        time: Float,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        pipeline: SceneWaterFlowPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        nil
    }

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

struct SceneWaterWavesEffectTextures {
    let mask: MTLTexture?

    func matches(_ plan: SceneWaterWavesExecutionPlan) -> Bool { true }
}

struct SceneWaterCausticsExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}

struct SceneWaterCausticsEffectTextures {
    let mask: MTLTexture?

    func matches(_ plan: SceneWaterCausticsExecutionPlan) -> Bool { true }
}

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
struct SceneCursorRippleEffectTextures {
    let mask: MTLTexture?
}

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
        pointerMovement: Float,
        primaryButtonIsDown: Bool,
        frameTime: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        nil
    }
}

struct SceneDepthParallaxExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}
struct SceneDepthParallaxEffectTextures {
    struct ResolvedArguments {}

    func resolvedArguments(
        for plan: SceneDepthParallaxExecutionPlan
    ) -> ResolvedArguments? {
        nil
    }
}
struct SceneDepthParallaxPipeline {
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {}
}

extension SceneEffectStageRenderer {
    static func renderWaterCaustics(
        _ plan: SceneWaterCausticsExecutionPlan,
        sourceTexture: MTLTexture,
        masks: SceneImageLayerMasks,
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
    let maskBinding: SceneTextureSlotBinding?

    func matches(_ plan: SceneWaterRippleExecutionPlan) -> Bool { true }
    func resolvedArguments(for plan: SceneWaterRippleExecutionPlan) -> Bool? { true }
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

struct SceneGodraysPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let firstHalfTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    let secondHalfTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    let direction: Float?
    let usesDirectionalGaussianKernel: Bool
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
        guard let resources = masks.godraysEffects[plan.effectKey.descriptorID],
              resources.matches(plan),
              targets.texture(for: plan.firstHalfTarget) != nil,
              targets.texture(for: plan.secondHalfTarget) != nil else {
            return nil
        }
        return targets.outputTexture
    }
}

struct SceneShineExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let firstHalfTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    let secondHalfTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    let maskTexturePath: String?
    let noiseTexturePath: String
}

struct SceneShineEffectTextures {
    let mask: MTLTexture?
    let maskPath: String?
    let noise: MTLTexture?
    let noisePath: String

    func matches(_ plan: SceneShineExecutionPlan) -> Bool {
        guard noise != nil, noisePath == plan.noiseTexturePath else { return false }
        return plan.maskTexturePath == nil ? maskPath == nil : mask != nil
    }
}

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
        guard let resources = masks.shineEffects[plan.effectKey.descriptorID],
              resources.matches(plan),
              targets.texture(for: plan.firstHalfTarget) != nil,
              targets.texture(for: plan.secondHalfTarget) != nil else {
            return nil
        }
        return targets.outputTexture
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

struct SceneDynamicSnapshot {
    let strengthsByEffectIndex: [Int: Float]
    let opacitiesByEffectIndex: [Int: Float]

    static func empty(frameIndex: UInt64, generation: UInt64 = 0) -> Self {
        Self(strengthsByEffectIndex: [:], opacitiesByEffectIndex: [:])
    }
}

struct SceneXRayEffectTextures {
    let effectID: String
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
        maskCandidate?.axisAlignedMappedUVScale(expectedPurpose: .mask) != nil
            && normalized(maskPath) == plan.maskTexturePath.map(normalized)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

struct SceneLocalContrastPlan {
    let firstQuarterTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    let secondQuarterTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    let renderGraph: SceneAuthoredEffectRenderPlan
    let staticOrFallbackStrength: Float
}

struct PreparedStageTargets {
    let tables: [SceneGraphRenderTargetTable]
    let commit: ScenePreparedPersistentGraphTargets.Commit
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

    static func submitFrame(
        _ commandBuffer: MTLCommandBuffer,
        transaction: SceneSourceUpdateTransaction
    ) {
        transaction.arm(on: commandBuffer)
        commandBuffer.commit()
        transaction.didSubmit()
        commandBuffer.waitUntilCompleted()
    }

    static func preciseBlurGraph(
        layerID: Int = 10,
        commandKind: Graph.NodeKind? = nil,
        fullFrameCompose: Bool = false
    ) -> Graph {
        precondition(!fullFrameCompose || commandKind == nil)
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
            target: fullFrameCompose ? output : first,
            bindings: [],
            commandSource: nil,
            commandTarget: nil,
            compose: fullFrameCompose ? .bool(true) : nil,
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
            bindings: fullFrameCompose ? [] : [
                .init(
                    slot: 0,
                    authoredName: verticalInput.name,
                    texture: verticalInput,
                    conditions: nil
                ),
            ] + [
                .init(slot: 1, authoredName: "previous", texture: input, conditions: nil),
            ],
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
        var renderTargets = fullFrameCompose ? [] : [
            Graph.RenderTarget(
                texture: first,
                extent: .init(kind: .input, first: nil, second: nil),
                format: "rgba_backbuffer",
                declaredUnique: commandKind == .swap,
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
        layerID: Int = 10,
        commandKind: Graph.NodeKind? = nil,
        fullFrameCompose: Bool = false
    ) -> SceneEffectStageExecutionPlan {
        let graph = preciseBlurGraph(
            layerID: layerID,
            commandKind: commandKind,
            fullFrameCompose: fullFrameCompose
        )
        return SceneEffectStageExecutionPlan(
            layerID: graph.layerID,
            renderGraph: graph,
            backend: .preciseGaussian(SceneGaussianBlurPlan(
                horizontalStep: 1,
                verticalStep: 1,
                sampleResolutionScale: 1,
                isPrecise: true
            )),
            materialNodeCount: 2,
            logicalRenderTargetCount: graph.renderTargets.count
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
        let resolvedLegacyProceduralPrepared =
            try resolvedLegacyProceduralPreparedEvidence(
                device: device,
                queue: queue,
                pipeline: pipeline
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
        let rejectedLayerBlend = try layerColorBlendPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            blendMode: 14
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
        let authoredFullFrameComposeImpulse = try authoredPreciseBlurImpulseEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor,
            fullFrameCompose: true
        )
        let authoredFullFrameComposeScaled = try authoredPreciseBlurImpulseEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor,
            fullFrameCompose: true,
            sourceSize: 16,
            maxDimension: 8
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
        let authoredLocalContrastPrepared = try authoredLocalContrastPreparedEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredGodraysPrepared = try authoredGodraysPreparedEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline
        )
        let authoredShinePrepared = try authoredShinePreparedEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline
        )
        let standardBlurAlphaAwareDownsample = try alphaAwareDownsamplePixel(
            device: device,
            queue: queue
        )
        let standardBlurMaskPixels = try standardBlurMaskPixels(
            device: device,
            queue: queue
        )
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
        let resolvedMaterialComposition = try resolvedMaterialCompositionEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline
        )
        let baseColorCandidate = try baseColorCandidateEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let layerSourcePassthrough = try layerSourcePassthroughEvidence(
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
            "resolvedLegacyProceduralPrepared": resolvedLegacyProceduralPrepared,
            "solidTintBGRA": solidTint,
            "imageTintBGRA": imageTint,
            "imageBrightnessBGRA": imageBrightness,
            "textBrightnessBGRA": textBrightness,
            "vividLayerBlendBGRA": vividLayerBlend as Any,
            "warmAdditiveLayerBlendBGRA": warmAdditiveLayerBlend as Any,
            "invalidLayerBlendRefused": invalidLayerBlendRefused,
            "rejectedLayerBlendBGRA": rejectedLayerBlend as Any,
            "fragmentUniformSize": MemoryLayout<SceneLayerFragmentUniforms>.size,
            "dependencyBlendModeOffset": MemoryLayout<SceneLayerFragmentUniforms>.offset(
                of: \SceneLayerFragmentUniforms.dependencyBlendMode
            ) ?? -1,
            "authoredPreciseImpulse": authoredPreciseImpulse,
            "gaussianKernelPixels": gaussianKernelPixels,
            "authoredFullFrameComposeImpulse": authoredFullFrameComposeImpulse,
            "authoredFullFrameComposeScaled": authoredFullFrameComposeScaled,
            "authoredStandardCheckerboard": authoredStandardCheckerboard,
            "authoredStandardCandidate": authoredStandardCandidate,
            "authoredLocalContrastPrepared": authoredLocalContrastPrepared,
            "authoredGodraysPrepared": authoredGodraysPrepared,
            "authoredShinePrepared": authoredShinePrepared,
            "standardBlurAlphaAwareDownsampleBGRA": standardBlurAlphaAwareDownsample,
            "standardBlurMaskPixels": standardBlurMaskPixels,
            "mappedMaskScale": [mappedMaskScale.x, mappedMaskScale.y],
            "decodedMappedScale": [decodedMappedScale.x, decodedMappedScale.y],
            "resolvedMaterialComposition": resolvedMaterialComposition,
            "baseColorCandidate": baseColorCandidate,
            "layerSourcePassthrough": layerSourcePassthrough,
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
        let referenceBytes = try textureBytes(reference, queue: queue)
        let acceptedBytes = try textureBytes(accepted, queue: queue)
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
        ]
    }

    static func drawBaseColor(
        source: MTLTexture,
        candidate: SceneTextureCandidate?,
        target: MTLTexture,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> Bool {
        guard let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let request = SceneImageLayerDrawRequest(
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
                offscreenTexturePool: nil,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
            )
        let encoded = compositor.draw(
            request,
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

    static func layerSourcePassthroughEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [String: Any] {
        let size = 16
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
              let dependency = makeTexture(
                  device: device, size: size, usage: .shaderRead
              ) else {
            throw HarnessError.metalUnavailable
        }
        // `source` is RGBA. The final BGRA target must therefore preserve this
        // premultiplied color as [16, 32, 64, 128].
        fill(source, bgra: [64, 32, 16, 128])
        fill(other, bgra: [255, 255, 255, 255])
        fill(dependency, bgra: [192, 24, 12, 255])

        let visibleUnsupportedEffect = SceneRenderDescriptor.EffectDescriptor(
            file: "effects/fixture/unclaimed/effect.json",
            visible: true,
            passes: []
        )
        func layer(
            color: [Float]? = nil,
            colorBlendMode: Int? = nil,
            brightness: Double? = nil,
            hasVisibleEffect: Bool = true
        ) -> SceneRenderDescriptor.Layer {
            SceneRenderDescriptor.Layer(
                contentKind: "image",
                colorRGB: color,
                colorBlendMode: colorBlendMode,
                brightness: brightness,
                effects: hasVisibleEffect ? [visibleUnsupportedEffect] : []
            )
        }
        func pulsePass(
            passIndex: Int = 0,
            combos: [String: Int] = [:]
        ) -> SceneRenderDescriptor.EffectDescriptor.PassDescriptor {
            SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
                passIndex: passIndex,
                texturePaths: ["util/noise", "fixture/pulse-mask"],
                textureSlots: [nil, "util/noise", "fixture/pulse-mask"],
                combos: combos,
                constantShaderValues: [:]
            )
        }
        func pulseLayer(
            file: String = "effects/pulse/effect.json",
            passIndices: [Int] = [0],
            combos: [String: Int] = [:]
        ) -> SceneRenderDescriptor.Layer {
            SceneRenderDescriptor.Layer(
                contentKind: "image",
                colorRGB: nil,
                colorBlendMode: nil,
                effects: [.init(
                    file: file,
                    visible: true,
                    passes: passIndices.map {
                        pulsePass(passIndex: $0, combos: combos)
                    }
                )]
            )
        }
        func candidate(
            identity: SceneTextureResourceIdentity,
            generation: SceneTextureResourceGeneration,
            purpose: SceneTextureLoadPurpose = .premultipliedColor,
            content: SceneTextureContent = .color(.resolved(.premultipliedAlpha)),
            texture: MTLTexture = source,
            authoredFormat: SceneShaderTextureFormat? = nil
        ) -> SceneTextureCandidate {
            let dimensions = CGSize(width: texture.width, height: texture.height)
            return SceneTextureCandidate(
                texture: texture,
                identity: identity,
                generation: generation,
                purpose: purpose,
                content: content,
                physicalSize: dimensions,
                mappedSize: dimensions,
                uvTransform: .identity,
                sampling: .linearClamp,
                authoredFormat: authoredFormat
            )
        }
        func publication(
            _ candidate: SceneTextureCandidate,
            requestLayerID: Int = 0,
            contentGeneration: UInt64 = 11
        ) -> SceneTextureProviderPublication {
            SceneTextureProviderPublication(
                requestIdentity: .layerSource(requestLayerID),
                candidate: candidate,
                contentGeneration: contentGeneration
            )
        }
        let fileGeneration = SceneTextureResourceGeneration.file(
            byteCount: UInt64(size * size * 4),
            modifiedAtBits: 1,
            revision: SceneTextureFileRevision(
                fileSystemID: 1,
                fileID: 2,
                statusChangedAtSeconds: 3,
                statusChangedAtNanoseconds: 4
            )
        )
        let staticFileCandidate = candidate(
            identity: .file(path: "materials/cards/fixture.png"),
            generation: fileGeneration,
            authoredFormat: .rgba8888
        )
        let currentMediaCandidate = candidate(
            identity: .provider(.mediaThumbnailCurrent),
            generation: .provider(contentGeneration: 11)
        )
        let builtInCandidate = candidate(
            identity: .builtIn(name: "fixture/color"),
            generation: .immutable(revision: 1)
        )
        let maskCandidate = candidate(
            identity: .builtIn(name: "fixture/mask"),
            generation: .immutable(revision: 1),
            purpose: .mask,
            content: .data,
            texture: dependency
        )
        guard let maskSlot1 = SceneTextureSlotBinding(
                  slotIndex: 1, candidate: maskCandidate
              ), let maskSlot3 = SceneTextureSlotBinding(
                  slotIndex: 3, candidate: maskCandidate
              ) else {
            throw HarnessError.drawRefused
        }
        func masks(
            waterRippleEffects: [String: SceneWaterRippleEffectTextures] = [:],
            shakeEffects: [String: SceneShakeEffectTextures] = [:],
            standardBlurEffects: [String: SceneStandardBlurEffectTextures] = [:],
            waterWavesEffects: [String: SceneWaterWavesEffectTextures] = [:],
            waterCausticsEffects: [String: SceneWaterCausticsEffectTextures] = [:],
            cursorRippleEffects: [String: SceneCursorRippleEffectTextures] = [:],
            pulseEffects: [String: ScenePulseEffectTextures] = [:],
            godraysEffects: [String: SceneGodraysEffectTextures] = [:],
            shineEffects: [String: SceneShineEffectTextures] = [:],
            xRay: SceneXRayEffectTextures? = nil
        ) -> SceneImageLayerMasks {
            SceneImageLayerMasks(
                waterRippleEffects: waterRippleEffects,
                depthParallaxEffects: [:],
                blendEffects: [:],
                shakeEffects: shakeEffects,
                standardBlurEffects: standardBlurEffects,
                waterFlowEffects: [:],
                waterWavesEffects: waterWavesEffects,
                waterCausticsEffects: waterCausticsEffects,
                cursorRippleEffects: cursorRippleEffects,
                pulseEffects: pulseEffects,
                godraysEffects: godraysEffects,
                shineEffects: shineEffects,
                xRay: xRay
            )
        }
        func draw(
            publication: SceneTextureProviderPublication?,
            layer: SceneRenderDescriptor.Layer,
            sourceTexture: MTLTexture = source,
            baseTextureCandidate: SceneTextureCandidate? = nil,
            masks: SceneImageLayerMasks = .empty,
            mvp: simd_float4x4 = SceneMatrix.scale(SIMD3<Float>(1, 1, 1)),
            alpha: Float = 1,
            tint: SIMD3<Float> = SIMD3(repeating: 1),
            dependencyEffect: SceneDependencyEffectInput? = nil,
            requiresDependencyEffect: Bool = false,
            blocksStaticLayerSourcePassthrough: Bool = false,
            using drawCompositor: SceneImageLayerCompositor? = nil,
            frameIndex: UInt64
        ) throws -> [String: Any] {
            guard let target = makeTexture(
                      device: device,
                      size: size,
                      usage: [.renderTarget, .shaderRead]
                  ), let commandBuffer = queue.makeCommandBuffer() else {
                throw HarnessError.metalUnavailable
            }
            let pass = SceneMainPassEncoder(
                commandBuffer: commandBuffer,
                target: target,
                clearColor: MTLClearColorMake(0, 0, 0, 0)
            )
            let recorder = ExactEvidenceLogRecorder()
            let trace = SceneEffectExecutionTelemetry(
                logSink: { recorder.append($0) }
            ).makeFrame(frameIndex: frameIndex)
            var request = SceneImageLayerDrawRequest(
                layer: layer,
                texture: sourceTexture,
                baseTextureCandidate: baseTextureCandidate,
                masks: masks,
                textureFrame: .identity,
                mvp: mvp,
                uniforms: SceneImageLayerUniformValues(
                    time: 0,
                    alpha: alpha,
                    cursorUV: .zero,
                    tint: tint
                ),
                offscreenTexturePool: nil,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: dependencyEffect,
                requiresDependencyEffect: requiresDependencyEffect,
            )
            request.blocksStaticLayerSourcePassthrough =
                blocksStaticLayerSourcePassthrough
            let outcome = (drawCompositor ?? compositor).drawOutcome(
                request,
                explicitLayerSourcePublication: publication,
                pipeline: pipeline,
                mainPass: pass,
                executionTrace: trace,
                executionOrigin: .image
            )
            let outcomeName: String
            switch outcome {
            case .normal: outcomeName = "normal"
            case .layerSourcePassthrough: outcomeName = "layer-source-passthrough"
            case .failed: outcomeName = "failed"
            }
            pass.finishEnsuringClear()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            guard commandBuffer.status == .completed else {
                throw HarnessError.commandFailed
            }
            return [
                "outcome": outcomeName,
                "encoded": outcome.encoded,
                "consumedDependency": outcome.consumedDependency,
                "topLeftBGRA": pixel(target, x: 0, y: 0),
                "centerBGRA": pixel(target, x: 8, y: 8),
                "leftMiddleBGRA": pixel(target, x: 2, y: 8),
                "rightMiddleBGRA": pixel(target, x: 13, y: 8),
                "bottomRightBGRA": pixel(target, x: 15, y: 15),
                "exteriorRingBGRA": [
                    pixel(target, x: 3, y: 8),
                    pixel(target, x: 12, y: 8),
                    pixel(target, x: 8, y: 3),
                    pixel(target, x: 8, y: 12),
                ],
                "trace": recorder.lines,
            ]
        }

        var nextFrame = UInt64(801)
        func run(
            publication: SceneTextureProviderPublication?,
            layer: SceneRenderDescriptor.Layer = layer(),
            sourceTexture: MTLTexture = source,
            baseTextureCandidate: SceneTextureCandidate? = nil,
            masks: SceneImageLayerMasks = .empty,
            mvp: simd_float4x4 = SceneMatrix.scale(SIMD3<Float>(1, 1, 1)),
            alpha: Float = 1,
            tint: SIMD3<Float> = SIMD3(repeating: 1),
            dependencyEffect: SceneDependencyEffectInput? = nil,
            requiresDependencyEffect: Bool = false,
            blocksStaticLayerSourcePassthrough: Bool = false,
            compositor: SceneImageLayerCompositor? = nil
        ) throws -> [String: Any] {
            defer { nextFrame += 1 }
            return try draw(
                publication: publication,
                layer: layer,
                sourceTexture: sourceTexture,
                baseTextureCandidate: baseTextureCandidate,
                masks: masks,
                mvp: mvp,
                alpha: alpha,
                tint: tint,
                dependencyEffect: dependencyEffect,
                requiresDependencyEffect: requiresDependencyEffect,
                blocksStaticLayerSourcePassthrough:
                    blocksStaticLayerSourcePassthrough,
                using: compositor,
                frameIndex: nextFrame
            )
        }

        let exactStaticFile = publication(staticFileCandidate)
        let exactCurrentMedia = publication(currentMediaCandidate)
        func pulseMasks(
            effectID: String = "effects/pulse/effect.json"
        ) -> SceneImageLayerMasks {
            masks(pulseEffects: [
                effectID: ScenePulseEffectTextures(
                    noise: nil,
                    mask: dependency,
                    maskUVScale: SIMD2(repeating: 1),
                    maskPath: "fixture/pulse-mask"
                ),
            ])
        }
        func waterWavesPass(
            passIndex: Int = 0,
            combos: [String: Int] = [:],
            maskPath: String? = "fixture/waterwaves-mask"
        ) -> SceneRenderDescriptor.EffectDescriptor.PassDescriptor {
            SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
                passIndex: passIndex,
                texturePaths: maskPath.map { [$0] } ?? [],
                textureSlots: [nil] + (maskPath.map { [$0] } ?? []),
                combos: combos,
                constantShaderValues: [:]
            )
        }
        func waterWavesLayer(
            file: String = "effects/waterwaves/effect.json",
            passIndices: [Int] = [0],
            combos: [String: Int] = [:],
            maskPath: String? = "fixture/waterwaves-mask"
        ) -> SceneRenderDescriptor.Layer {
            SceneRenderDescriptor.Layer(
                contentKind: "image",
                colorRGB: nil,
                colorBlendMode: nil,
                effects: [.init(
                    file: file,
                    visible: true,
                    passes: passIndices.map {
                        waterWavesPass(
                            passIndex: $0,
                            combos: combos,
                            maskPath: maskPath
                        )
                    }
                )]
            )
        }
        func waterWavesMasks(
            effectID: String = "effects/waterwaves/effect.json"
        ) -> SceneImageLayerMasks {
            masks(waterWavesEffects: [
                effectID: SceneWaterWavesEffectTextures(mask: dependency),
            ])
        }
        let exactPulseMasks = pulseMasks()
        let pulseAlphaZeroCombos = [
            "AUDIOPROCESSING": 0,
            "BLENDMODE": 9,
            "PULSEALPHA": 0,
            "PULSECOLOR": 1,
        ]
        let pulseMaskDefaultAlpha = try run(
            publication: exactCurrentMedia,
            layer: pulseLayer(),
            masks: exactPulseMasks
        )
        let pulseMaskAlphaZero = try run(
            publication: exactCurrentMedia,
            layer: pulseLayer(combos: pulseAlphaZeroCombos),
            masks: exactPulseMasks
        )
        let pulseMaskAlphaZeroNextFrame = try run(
            publication: exactCurrentMedia,
            layer: pulseLayer(combos: pulseAlphaZeroCombos),
            masks: exactPulseMasks
        )
        let pulseCurrentMediaWithStaticBlock = try run(
            publication: exactCurrentMedia,
            layer: pulseLayer(combos: pulseAlphaZeroCombos),
            masks: exactPulseMasks,
            blocksStaticLayerSourcePassthrough: true
        )
        let pulseStaticFileAlphaZero = try run(
            publication: exactStaticFile,
            layer: pulseLayer(combos: pulseAlphaZeroCombos),
            baseTextureCandidate: staticFileCandidate,
            masks: exactPulseMasks
        )
        let pulseStaticFileAlphaZeroNextFrame = try run(
            publication: exactStaticFile,
            layer: pulseLayer(combos: pulseAlphaZeroCombos),
            baseTextureCandidate: staticFileCandidate,
            masks: exactPulseMasks
        )
        let waterWavesMaskStaticFile = try run(
            publication: exactStaticFile,
            layer: waterWavesLayer(),
            baseTextureCandidate: staticFileCandidate,
            masks: waterWavesMasks()
        )
        let waterWavesMaskStaticFileNextFrame = try run(
            publication: exactStaticFile,
            layer: waterWavesLayer(),
            baseTextureCandidate: staticFileCandidate,
            masks: waterWavesMasks()
        )
        let accepted: [String: Any] = [
            "staticFilePartial": try run(
                publication: exactStaticFile,
                baseTextureCandidate: staticFileCandidate
            ),
            "staticFileNextFrame": try run(
                publication: exactStaticFile,
                baseTextureCandidate: staticFileCandidate
            ),
            "currentMediaPartial": try run(publication: exactCurrentMedia),
            "currentMediaNextFrame": try run(publication: exactCurrentMedia),
            "rotated": try run(
                publication: exactCurrentMedia,
                mvp: SceneMatrix.rotationZ(0.35)
                    * SceneMatrix.scale(SIMD3<Float>(0.9, 0.9, 1))
            ),
            "partiallyClipped": try run(
                publication: exactStaticFile,
                baseTextureCandidate: staticFileCandidate,
                mvp: SceneMatrix.translation(SIMD3<Float>(0.8, 0, 0))
                    * SceneMatrix.scale(SIMD3<Float>(1, 1, 1))
            ),
            "pulseMaskDefaultAlpha": pulseMaskDefaultAlpha,
            "pulseMaskAlphaZero": pulseMaskAlphaZero,
            "pulseMaskAlphaZeroNextFrame": pulseMaskAlphaZeroNextFrame,
            "pulseCurrentMediaWithStaticBlock": pulseCurrentMediaWithStaticBlock,
            "pulseStaticFileAlphaZero": pulseStaticFileAlphaZero,
            "pulseStaticFileAlphaZeroNextFrame": pulseStaticFileAlphaZeroNextFrame,
            "waterWavesMaskStaticFile": waterWavesMaskStaticFile,
            "waterWavesMaskStaticFileNextFrame":
                waterWavesMaskStaticFileNextFrame,
        ]
        let normalWithoutEffects = try run(
            publication: exactCurrentMedia,
            layer: layer(hasVisibleEffect: false)
        )
        let rejectedRouteCompositor = SceneImageLayerCompositor(
            pipelineRepository: SceneImageEffectPipelineRepository(device: device),
            resolvedMaterialRuntime: SceneResolvedMaterialRuntimeBridge(
                claimRejectionReason: "fixture-claimed-route-rejected"
            )
        )
        let claimedGraph = xRayStage(layerID: 0).renderGraph
        let claimedPairPlan: SceneLayerFullFramePairPlan
        switch SceneLayerFullFramePairPlan.make(
            conditionPrunedGraphs: [claimedGraph]
        ) {
        case let .success(value): claimedPairPlan = value
        case .failure: throw HarnessError.drawRefused
        }
        let claimedRouteCompositor = SceneImageLayerCompositor(
            pipelineRepository: SceneImageEffectPipelineRepository(device: device),
            resolvedMaterialRuntime: SceneResolvedMaterialRuntimeBridge(
                claimedExecution: .init(
                    token: .init(rawValue: 91),
                    layerID: 0,
                    admittedGraphs: [claimedGraph],
                    targetExecutionPlans: [],
                    pairPlan: claimedPairPlan,
                    fullFrameExtentPolicy: .standard,
                    sourceRoute: .capturedLayerTexture,
                    dependencyOwnership: .none
                )
            )
        )
        var nonfiniteMVP = matrix_identity_float4x4
        nonfiniteMVP.columns.0.x = .nan
        let wrongProviderCandidate = candidate(
            identity: .provider(.dynamicText(layerID: 0)),
            generation: .provider(contentGeneration: 11)
        )
        let staleCurrentMediaCandidate = candidate(
            identity: .provider(.mediaThumbnailCurrent),
            generation: .provider(contentGeneration: 10)
        )
        let mismatchedFileCandidate = candidate(
            identity: .file(path: "materials/cards/other.png"),
            generation: fileGeneration
        )
        var rejected: [String: Any] = [
            "withDependency": try run(
                publication: exactCurrentMedia,
                dependencyEffect: dependencyInput(texture: dependency)
            ),
            "requiresDependencyEffect": try run(
                publication: exactCurrentMedia,
                requiresDependencyEffect: true
            ),
            "offscreen": try run(
                publication: exactCurrentMedia,
                mvp: SceneMatrix.translation(SIMD3<Float>(3, 0, 0))
                    * SceneMatrix.scale(SIMD3<Float>(1, 1, 1))
            ),
            "degenerate": try run(
                publication: exactCurrentMedia,
                mvp: SceneMatrix.scale(SIMD3<Float>(0, 1, 1))
            ),
            "nonfinite": try run(
                publication: exactCurrentMedia,
                mvp: nonfiniteMVP
            ),
            "builtIn": try run(
                publication: publication(builtInCandidate),
                baseTextureCandidate: builtInCandidate
            ),
            "wrongProvider": try run(
                publication: publication(wrongProviderCandidate)
            ),
            "wrongLayer": try run(publication: publication(
                currentMediaCandidate, requestLayerID: 1
            )),
            "staleGeneration": try run(publication: publication(
                staleCurrentMediaCandidate, contentGeneration: 11
            )),
            "bare": try run(publication: nil),
            "unresolvedColor": try run(publication: publication(candidate(
                identity: .provider(.mediaThumbnailCurrent),
                generation: .provider(contentGeneration: 11),
                content: .color(.unresolved)
            ))),
            "straightColor": try run(publication: publication(candidate(
                identity: .provider(.mediaThumbnailCurrent),
                generation: .provider(contentGeneration: 11),
                content: .color(.resolved(.straightAlpha))
            ))),
            "data": try run(publication: publication(candidate(
                identity: .provider(.mediaThumbnailCurrent),
                generation: .provider(contentGeneration: 11),
                content: .data
            ))),
            "wrongPurpose": try run(publication: publication(candidate(
                identity: .provider(.mediaThumbnailCurrent),
                generation: .provider(contentGeneration: 11),
                purpose: .normal
            ))),
            "wrongTexture": try run(
                publication: publication(candidate(
                    identity: .provider(.mediaThumbnailCurrent),
                    generation: .provider(contentGeneration: 11),
                    texture: other
                )),
                sourceTexture: source
            ),
            "fileWithoutBaseCandidate": try run(
                publication: exactStaticFile
            ),
            "fileMismatchedBaseCandidate": try run(
                publication: exactStaticFile,
                baseTextureCandidate: mismatchedFileCandidate
            ),
            "currentMediaMismatchedBaseCandidate": try run(
                publication: exactCurrentMedia,
                baseTextureCandidate: mismatchedFileCandidate
            ),
            "partialAlpha": try run(
                publication: exactCurrentMedia, alpha: 0.75
            ),
            "partialTint": try run(
                publication: exactCurrentMedia,
                tint: SIMD3<Float>(1, 0.75, 1)
            ),
            "authoredTint": try run(
                publication: exactCurrentMedia,
                layer: layer(color: [1, 0.75, 1])
            ),
            "malformedAuthoredTint": try run(
                publication: exactCurrentMedia,
                layer: layer(color: [])
            ),
            "brightness": try run(
                publication: exactCurrentMedia,
                layer: layer(brightness: 0.75)
            ),
            "layerColorBlend": try run(
                publication: exactCurrentMedia,
                layer: layer(colorBlendMode: 1)
            ),
            "claimed": try run(
                publication: exactCurrentMedia,
                compositor: claimedRouteCompositor
            ),
            "rejected": try run(
                publication: exactCurrentMedia,
                compositor: rejectedRouteCompositor
            ),
            "pulseAlphaOneMasked": try run(
                publication: exactCurrentMedia,
                layer: pulseLayer(combos: ["PULSEALPHA": 1]),
                masks: exactPulseMasks
            ),
            "pulseAlphaOneUnmasked": try run(
                publication: exactCurrentMedia,
                layer: pulseLayer(combos: ["PULSEALPHA": 1])
            ),
            "pulseInvalidCombo": try run(
                publication: exactCurrentMedia,
                layer: pulseLayer(combos: ["PULSEALPHA": 2])
            ),
            "pulseUnknownCombo": try run(
                publication: exactCurrentMedia,
                layer: pulseLayer(combos: ["UNKNOWN": 1])
            ),
            "pulseMissingPassMasked": try run(
                publication: exactCurrentMedia,
                layer: pulseLayer(passIndices: []),
                masks: exactPulseMasks
            ),
            "pulseWrongPassMasked": try run(
                publication: exactCurrentMedia,
                layer: pulseLayer(passIndices: [1]),
                masks: exactPulseMasks
            ),
            "pulseMultiplePassesMasked": try run(
                publication: exactCurrentMedia,
                layer: pulseLayer(passIndices: [0, 1]),
                masks: exactPulseMasks
            ),
            "pulseWrongDefinitionMasked": try run(
                publication: exactCurrentMedia,
                layer: pulseLayer(file: "effects/fixture/pulse/effect.json"),
                masks: pulseMasks(effectID: "effects/fixture/pulse/effect.json")
            ),
            "pulseStaticSourceConsumer": try run(
                publication: exactStaticFile,
                layer: pulseLayer(combos: pulseAlphaZeroCombos),
                baseTextureCandidate: staticFileCandidate,
                masks: exactPulseMasks,
                blocksStaticLayerSourcePassthrough: true
            ),
            "waterWavesNonStockDefinition": try run(
                publication: exactStaticFile,
                layer: waterWavesLayer(
                    file: "effects/workshop/9/waterwaves/effect.json"
                ),
                baseTextureCandidate: staticFileCandidate,
                masks: waterWavesMasks(
                    effectID: "effects/workshop/9/waterwaves/effect.json"
                )
            ),
            "waterWavesTimeOffset": try run(
                publication: exactStaticFile,
                layer: waterWavesLayer(combos: ["TIMEOFFSET": 1]),
                baseTextureCandidate: staticFileCandidate,
                masks: waterWavesMasks()
            ),
            "waterWavesPerspective": try run(
                publication: exactStaticFile,
                layer: waterWavesLayer(combos: ["PERSPECTIVE": 1]),
                baseTextureCandidate: staticFileCandidate,
                masks: waterWavesMasks()
            ),
            "waterWavesDualWaves": try run(
                publication: exactStaticFile,
                layer: waterWavesLayer(combos: ["DUALWAVES": 1]),
                baseTextureCandidate: staticFileCandidate,
                masks: waterWavesMasks()
            ),
            "waterWavesUnknownCombo": try run(
                publication: exactStaticFile,
                layer: waterWavesLayer(combos: ["UNKNOWN": 1]),
                baseTextureCandidate: staticFileCandidate,
                masks: waterWavesMasks()
            ),
            "waterWavesMultiplePassesMasked": try run(
                publication: exactStaticFile,
                layer: waterWavesLayer(passIndices: [0, 1]),
                baseTextureCandidate: staticFileCandidate,
                masks: waterWavesMasks()
            ),
            "waterWavesWrongPassMasked": try run(
                publication: exactStaticFile,
                layer: waterWavesLayer(passIndices: [1]),
                baseTextureCandidate: staticFileCandidate,
                masks: waterWavesMasks()
            ),
            "waterWavesStaticSourceConsumer": try run(
                publication: exactStaticFile,
                layer: waterWavesLayer(),
                baseTextureCandidate: staticFileCandidate,
                masks: waterWavesMasks(),
                blocksStaticLayerSourcePassthrough: true
            ),
        ]
        let visibleEffectID = visibleUnsupportedEffect.id
        let maskedCases: [(String, SceneImageLayerMasks)] = [
            ("waterRipple", masks(waterRippleEffects: [
                visibleEffectID: SceneWaterRippleEffectTextures(
                    mask: dependency,
                    maskUVScale: SIMD2(repeating: 1),
                    normal: nil,
                    maskBinding: maskSlot1
                ),
            ])),
            ("shake", masks(shakeEffects: [
                visibleEffectID: SceneShakeEffectTextures(
                    maskBinding: maskSlot3
                ),
            ])),
            ("standardBlur", masks(standardBlurEffects: [
                visibleEffectID: SceneStandardBlurEffectTextures(
                    maskCandidate: maskCandidate,
                    maskPath: "fixture/mask"
                ),
            ])),
            ("waterWaves", masks(waterWavesEffects: [
                visibleEffectID: SceneWaterWavesEffectTextures(
                    mask: dependency
                ),
            ])),
            ("waterCaustics", masks(waterCausticsEffects: [
                visibleEffectID: SceneWaterCausticsEffectTextures(
                    mask: dependency
                ),
            ])),
            ("cursorRipple", masks(cursorRippleEffects: [
                visibleEffectID: SceneCursorRippleEffectTextures(
                    mask: dependency
                ),
            ])),
            ("godrays", masks(godraysEffects: [
                visibleEffectID: SceneGodraysEffectTextures(
                    mask: dependency,
                    maskUVScale: SIMD2(repeating: 1),
                    maskPath: "fixture/mask",
                    noise: nil
                ),
            ])),
            ("shine", masks(shineEffects: [
                visibleEffectID: SceneShineEffectTextures(
                    mask: dependency,
                    maskPath: "fixture/mask",
                    noise: nil,
                    noisePath: "fixture/noise"
                ),
            ])),
            ("xray", masks(xRay: SceneXRayEffectTextures(
                effectID: visibleEffectID,
                blend: dependency,
                halo: nil,
                opacityMask: dependency
            ))),
        ]
        for (name, maskSet) in maskedCases {
            rejected["mask-\(name)"] = try run(
                publication: exactCurrentMedia,
                masks: maskSet
            )
        }
        return [
            "accepted": accepted,
            "normalWithoutEffects": normalWithoutEffects,
            "rejected": rejected,
        ]
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
                    dependencyInput(blendMode: $0, texture: dependency)
                },
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

    static func dependencyInput(
        consumerLayerID: Int = 0,
        providerLayerID: Int = 1,
        variant: SceneNamedTextureReference.Variant = .primary,
        effectID: String = "0#effect#0",
        passIndex: Int = 0,
        slotIndex: Int = 1,
        blendMode: Int = 0,
        frameEpoch: UInt64 = 1,
        texture: MTLTexture
    ) -> SceneDependencyEffectInput {
        SceneDependencyEffectInput(
            consumerLayerID: consumerLayerID,
            providerLayerID: providerLayerID,
            variant: variant,
            slot: SceneEffectPassSlot(
                effectID: effectID,
                passIndex: passIndex,
                slotIndex: slotIndex
            ),
            blendMode: blendMode,
            frameEpoch: frameEpoch,
            texture: texture
        )
    }

    static func resolvedLegacyProceduralPreparedEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline
    ) throws -> [String: Any] {
        let size = 8
        guard let source = makeTexture(device: device, size: size, usage: .shaderRead),
              let dependency = makeTexture(
                  device: device, size: size, usage: .shaderRead
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: [32, 64, 128, 128])
        fill(dependency, bgra: [192, 32, 64, 255])

        let stage = externalProceduralNoiseStage()
        guard case let .proceduralNoise(noise) = stage.backend,
              let providerLayerID = noise.dependencyProviderLayerID else {
            throw HarnessError.drawRefused
        }
        let pool = SceneOffscreenTexturePool(device: device, maxDimension: size)
        let frameTables = try prepareStageTargets(
            plan: stage,
            pool: pool,
            width: size,
            height: size,
            commandBuffer: commandBuffer
        )
        defer { frameTables.commit.releaseAll() }
        guard let table = frameTables.tables.first else {
            throw HarnessError.drawRefused
        }
        let pipelines = SceneAuthoredEffectPipelineSet(
            repository: SceneImageEffectPipelineRepository(device: device)
        )
        func input(
            provider: Int? = nil,
            variant: SceneNamedTextureReference.Variant = .primary,
            effectID: String? = nil,
            passIndex: Int = 0,
            slotIndex: Int = 3,
            blendMode: Int = 0,
            frameEpoch: UInt64 = 1
        ) -> SceneDependencyEffectInput {
            dependencyInput(
                consumerLayerID: noise.layerID,
                providerLayerID: provider ?? providerLayerID,
                variant: variant,
                effectID: effectID ?? noise.effectKey.descriptorID,
                passIndex: passIndex,
                slotIndex: slotIndex,
                blendMode: blendMode,
                frameEpoch: frameEpoch,
                texture: dependency
            )
        }
        func preparation(
            dependencyEffect: SceneDependencyEffectInput?
        ) -> SceneEffectStageRenderer.StagePreparation {
            SceneEffectStageRenderer.prepareStage(
                stage,
                sourceTexture: table.inputTexture,
                targets: table,
                inputs: .init(
                    masks: authoredEffectMasks(),
                    dynamicValues: .empty(frameIndex: 1),
                    pipelines: pipelines,
                    cursorUV: .zero,
                    previousCursorUV: .zero,
                    pointerIsInside: false,
                    previousPointerIsInside: false,
                    pointerMovement: 0,
                    primaryButtonIsDown: false,
                    frameTime: 1 / 60,
                    time: 0,
                    audioSpectrum: .silent,
                    dependencyEffect: dependencyEffect
                ),
                sourcePipeline: pipeline,
                time: 0
            )
        }
        func rejectionReason(
            _ result: SceneEffectStageRenderer.StagePreparation
        ) -> String? {
            guard case let .rejected(reason) = result else { return nil }
            return reason
        }

        let rejections = [
            "missing": rejectionReason(preparation(dependencyEffect: nil)) ?? "accepted",
            "provider": rejectionReason(preparation(
                dependencyEffect: input(provider: providerLayerID + 1)
            )) ?? "accepted",
            "variant": rejectionReason(preparation(
                dependencyEffect: input(variant: .secondary)
            )) ?? "accepted",
            "effect": rejectionReason(preparation(
                dependencyEffect: input(effectID: "wrong-effect")
            )) ?? "accepted",
            "pass": rejectionReason(preparation(
                dependencyEffect: input(passIndex: 1)
            )) ?? "accepted",
            "slot": rejectionReason(preparation(
                dependencyEffect: input(slotIndex: 2)
            )) ?? "accepted",
            "blend": rejectionReason(preparation(
                dependencyEffect: input(blendMode: 5)
            )) ?? "accepted",
            "epoch": rejectionReason(preparation(
                dependencyEffect: input(frameEpoch: 0)
            )) ?? "accepted",
        ]
        guard case let .ready(preparedStage) = preparation(
            dependencyEffect: input()
        ), SceneOffscreenEffectRenderer.captureSource(
            sourceTexture: source,
            target: table.inputTexture,
            sourceUniforms: .neutral(),
            pipeline: pipeline,
            commandBuffer: commandBuffer
        ), SceneEffectStageRenderer.encodePreparedStage(
            preparedStage,
            commandBuffer: commandBuffer
        ) else {
            throw HarnessError.drawRefused
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed,
              commandBuffer.error == nil else { throw HarnessError.commandFailed }
        let output = try textureBytes(table.outputTexture, queue: queue)
        return [
            "preparedStageEncoded": true,
            "outputHasPixels": output.contains(where: { $0 != 0 }),
            "rejections": rejections,
        ]
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
        let request = SceneImageLayerDrawRequest(
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
        )
        let drew = compositor.draw(request, pipeline: pipeline, mainPass: mainPass)
        guard drew else { return nil }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return pixel(target, x: 0, y: 0)
    }







    static func authoredPreciseBlurImpulseEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        fullFrameCompose: Bool = false,
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
        let plan = authoredPreciseBlurPlan(fullFrameCompose: fullFrameCompose)
        let table: SceneGraphRenderTargetTable
        let intermediate: MTLTexture
        var pairComposeTransitionCount = 0
        var intermediateUsesOtherPairMember = false
        if fullFrameCompose {
            let targetSize = max(1, min(size, maxDimension))
            guard let pairZero = makeTexture(
                      device: device,
                      size: targetSize,
                      usage: [.renderTarget, .shaderRead],
                      storageMode: .private
                  ), let pairOne = makeTexture(
                      device: device,
                      size: targetSize,
                      usage: [.renderTarget, .shaderRead],
                      storageMode: .private
                  ), case let .success(targetPlan) = SceneGraphRenderTargetPlan.make(
                      graph: plan.renderGraph,
                      inputRole: plan.inputRole,
                      inputWidth: targetSize,
                      inputHeight: targetSize
                  ), case let .success(pairPlan) = SceneLayerFullFramePairPlan.make(
                      conditionPrunedGraphs: [plan.renderGraph]
                  ), let pairStep = pairPlan.effects.first,
                  pairPlan.effects.count == 1,
                  pairStep.inputMember == pairStep.outputMember,
                  pairStep.composeTransitionCount == 1,
                  pairStep.fullFrameOutputWriteCount == 2,
                  pairStep.nodes.count == 2,
                  pairStep.nodes[0].fullFrameWriteMember
                    == pairStep.inputMember.opposite,
                  pairStep.nodes[1].fullFrameWriteMember == pairStep.inputMember else {
                throw HarnessError.drawRefused
            }
            let endpoint = pairStep.inputMember == .zero ? pairZero : pairOne
            let other = pairStep.inputMember == .zero ? pairOne : pairZero
            guard case let .success(mappedTable) = SceneGraphRenderTargetTable.makeMapped(
                plan: targetPlan,
                device: device,
                texturesByIdentity: [
                    targetPlan.input: endpoint,
                    targetPlan.output: endpoint,
                ],
                fullFramePair: .init(first: pairZero, second: pairOne),
                expectsInputOutputAlias: true
            ), mappedTable.inputTexture === endpoint,
               mappedTable.outputTexture === endpoint,
               let captureBuffer = queue.makeCommandBuffer(),
               SceneOffscreenEffectRenderer.captureSource(
                   sourceTexture: source,
                   target: endpoint,
                   sourceUniforms: .neutral(),
                   pipeline: pipeline,
                   commandBuffer: captureBuffer
               ) else {
                throw HarnessError.drawRefused
            }
            captureBuffer.commit()
            captureBuffer.waitUntilCompleted()
            guard captureBuffer.status == .completed,
                  captureBuffer.error == nil else { throw HarnessError.commandFailed }
            table = mappedTable
            intermediate = other
            pairComposeTransitionCount = pairStep.composeTransitionCount
            intermediateUsesOtherPairMember = other !== endpoint
        } else {
            let pool = SceneOffscreenTexturePool(
                device: device,
                maxDimension: maxDimension
            )
            let layer = SceneRenderDescriptor.Layer(
                contentKind: "image", colorRGB: nil, colorBlendMode: nil, effects: []
            )
            let frameTables = try drawAuthoredBlur(
                source: source,
                target: target,
                layer: layer,
                plan: plan,
                pool: pool,
                queue: queue,
                pipeline: pipeline,
                compositor: compositor
            )
            guard frameTables.tables.count == 1,
                  let explicitTable = frameTables.tables.first,
                  let intermediateIdentity = explicitTable.plan.logicalTargets.first?.identity,
                  let explicitIntermediate = explicitTable.texture(
                      for: intermediateIdentity
                  ) else {
                throw HarnessError.drawRefused
            }
            table = explicitTable
            intermediate = explicitIntermediate
        }
        let sourceBytes = try textureBytes(source, queue: queue)
        let inputBytes = try textureBytes(table.inputTexture, queue: queue)
        guard let blur = plan.gaussianBlur,
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

        let preparedInputs = SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs(
            masks: authoredEffectMasks(),
            dynamicValues: .empty(frameIndex: 1),
            pipelines: .init(
                repository: SceneImageEffectPipelineRepository(device: device)
            ),
            cursorUV: .zero,
            previousCursorUV: .zero,
            pointerIsInside: false,
            previousPointerIsInside: false,
            pointerMovement: 0,
            primaryButtonIsDown: false,
            frameTime: 1 / 60,
            time: 0,
            audioSpectrum: .silent,
            dependencyEffect: nil
        )
        guard let preparedBuffer = queue.makeCommandBuffer(),
              case let .ready(preparedStage) =
                SceneEffectStageRenderer.prepareStage(
                    plan,
                    sourceTexture: table.inputTexture,
                    targets: table,
                    inputs: preparedInputs,
                    sourcePipeline: pipeline,
                    time: 0,
                    sourceSampleExtent: SIMD2(Float(size), Float(size))
                ),
              SceneEffectStageRenderer.encodePreparedStage(
                  preparedStage,
                  commandBuffer: preparedBuffer
              ) else {
            throw HarnessError.drawRefused
        }
        preparedBuffer.commit()
        preparedBuffer.waitUntilCompleted()
        guard preparedBuffer.status == .completed,
              preparedBuffer.error == nil else { throw HarnessError.commandFailed }

        if fullFrameCompose {
            guard let compositeBuffer = queue.makeCommandBuffer(),
                  SceneOffscreenEffectRenderer.captureSource(
                      sourceTexture: table.outputTexture,
                      target: target,
                      sourceUniforms: .neutral(),
                      pipeline: pipeline,
                      commandBuffer: compositeBuffer
                  ) else { throw HarnessError.drawRefused }
            compositeBuffer.commit()
            compositeBuffer.waitUntilCompleted()
            guard compositeBuffer.status == .completed,
                  compositeBuffer.error == nil else { throw HarnessError.commandFailed }
        }

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
            "preparedStageEncoded": true,
            "sourceWidth": source.width,
            "inputWidth": table.inputTexture.width,
            "logicalTargetCount": table.plan.logicalTargets.count,
            "inputOutputAliased": table.inputOutputAliased,
            "intermediateUsesOtherPairMember": intermediateUsesOtherPairMember,
            "pairComposeTransitionCount": pairComposeTransitionCount,
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
            "outputHasPixels": outputBytes.contains(where: { $0 != 0 }),
            "outputIsPremultiplied": isPremultiplied(outputBytes),
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
        let frameTables = try drawAuthoredBlur(
            source: source,
            target: target,
            layer: standardBlurLayer(),
            plan: plan,
            pool: pool,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        guard frameTables.tables.count == 1,
              let table = frameTables.tables.first else {
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

        let preparedInputs = SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs(
            masks: authoredEffectMasks(),
            dynamicValues: .empty(frameIndex: 1),
            pipelines: .init(
                repository: SceneImageEffectPipelineRepository(device: device)
            ),
            cursorUV: .zero,
            previousCursorUV: .zero,
            pointerIsInside: false,
            previousPointerIsInside: false,
            pointerMovement: 0,
            primaryButtonIsDown: false,
            frameTime: 1 / 60,
            time: 0,
            audioSpectrum: .silent,
            dependencyEffect: nil
        )
        guard let preparedBuffer = queue.makeCommandBuffer(),
              case let .ready(preparedStage) =
                SceneEffectStageRenderer.prepareStage(
                    plan,
                    sourceTexture: table.inputTexture,
                    targets: table,
                    inputs: preparedInputs,
                    sourcePipeline: pipeline,
                    time: 0
                ),
              SceneEffectStageRenderer.encodePreparedStage(
                  preparedStage,
                  commandBuffer: preparedBuffer
              ) else {
            throw HarnessError.drawRefused
        }
        preparedBuffer.commit()
        preparedBuffer.waitUntilCompleted()
        guard preparedBuffer.status == .completed,
              preparedBuffer.error == nil else { throw HarnessError.commandFailed }

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
            "preparedStageEncoded": true,
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
        let acceptedFrameTables = try drawAuthoredBlur(
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
        guard let acceptedTable = acceptedFrameTables.tables.first else {
            throw HarnessError.drawRefused
        }

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

        func preparedStageResult(
            masks: SceneImageLayerMasks
        ) -> SceneEffectStageRenderer.StagePreparation {
            let inputs = SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs(
                masks: masks,
                dynamicValues: .empty(frameIndex: 1),
                pipelines: .init(
                    repository: SceneImageEffectPipelineRepository(device: device)
                ),
                cursorUV: .zero,
                previousCursorUV: .zero,
                pointerIsInside: false,
                previousPointerIsInside: false,
                pointerMovement: 0,
                primaryButtonIsDown: false,
                frameTime: 1 / 60,
                time: 0,
                audioSpectrum: .silent,
                dependencyEffect: nil
            )
            return SceneEffectStageRenderer.prepareStage(
                plan,
                sourceTexture: acceptedTable.inputTexture,
                targets: acceptedTable,
                inputs: inputs,
                sourcePipeline: pipeline,
                time: 0
            )
        }
        let acceptedPreparation = preparedStageResult(masks: standardBlurMasks(
            candidate: acceptedCandidate,
            path: maskPath,
            descriptorID: plan.standardBlur?.effectDescriptorID ?? ""
        ))
        let wrongPurposePreparation = preparedStageResult(masks: standardBlurMasks(
            candidate: wrongPurposeCandidate,
            path: maskPath,
            descriptorID: plan.standardBlur?.effectDescriptorID ?? ""
        ))
        let missingPreparation = preparedStageResult(masks: authoredEffectMasks())
        let acceptedPrepared: Bool
        if case .ready = acceptedPreparation { acceptedPrepared = true }
        else { acceptedPrepared = false }
        let wrongPurposeReason: String?
        if case let .rejected(reason) = wrongPurposePreparation {
            wrongPurposeReason = reason
        } else {
            wrongPurposeReason = nil
        }
        let missingReason: String?
        if case let .rejected(reason) = missingPreparation {
            missingReason = reason
        } else {
            missingReason = nil
        }

        let sourceBytes = try textureBytes(source, queue: queue)
        let acceptedBytes = try textureBytes(acceptedTarget, queue: queue)
        return [
            "accepted": true,
            "preparedStageAccepted": acceptedPrepared,
            "wrongPurposePreparationReason": wrongPurposeReason as Any,
            "missingPreparationReason": missingReason as Any,
            "paddedZeroMaskPreservedSource":
                maxDifference(sourceBytes, acceptedBytes) <= 2,
            "wrongPurposeRejected": wrongPurposeRejected,
        ]
    }

    static func authoredLocalContrastPreparedEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [String: Any] {
        let size = 16
        guard let source = makeTexture(device: device, size: size, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ) else { throw HarnessError.metalUnavailable }
        fillPremultipliedCheckerboard(source)
        let plan = authoredLocalContrastPlan()
        let pool = SceneOffscreenTexturePool(device: device, maxDimension: size)
        let frameTables = try drawAuthoredBlur(
            source: source,
            target: target,
            layer: standardBlurLayer(),
            plan: plan,
            pool: pool,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        guard let table = frameTables.tables.first else {
            throw HarnessError.drawRefused
        }
        func preparation(
            snapshot: SceneDynamicSnapshot
        ) -> SceneEffectStageRenderer.StagePreparation {
            SceneEffectStageRenderer.prepareStage(
                plan,
                sourceTexture: table.inputTexture,
                targets: table,
                inputs: .init(
                    masks: authoredEffectMasks(),
                    dynamicValues: snapshot,
                    pipelines: .init(
                        repository: SceneImageEffectPipelineRepository(device: device)
                    ),
                    cursorUV: .zero,
                    previousCursorUV: .zero,
                    pointerIsInside: false,
                    previousPointerIsInside: false,
                    pointerMovement: 0,
                    primaryButtonIsDown: false,
                    frameTime: 1 / 60,
                    time: 0,
                    audioSpectrum: .silent,
                    dependencyEffect: nil
                ),
                sourcePipeline: pipeline,
                time: 0
            )
        }
        guard let commandBuffer = queue.makeCommandBuffer(),
              case let .ready(prepared) = preparation(
                  snapshot: .empty(frameIndex: 1)
              ),
              SceneEffectStageRenderer.encodePreparedStage(
                  prepared,
                  commandBuffer: commandBuffer
              ) else { throw HarnessError.drawRefused }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed,
              commandBuffer.error == nil else { throw HarnessError.commandFailed }

        let invalid = preparation(snapshot: SceneDynamicSnapshot(
            strengthsByEffectIndex: [0: 6],
            opacitiesByEffectIndex: [:]
        ))
        let invalidReason: String?
        if case let .rejected(reason) = invalid { invalidReason = reason }
        else { invalidReason = nil }
        let inputBytes = try textureBytes(table.inputTexture, queue: queue)
        let outputBytes = try textureBytes(table.outputTexture, queue: queue)
        return [
            "preparedStageEncoded": true,
            "invalidStrengthReason": invalidReason as Any,
            "inputToOutputDelta": maxDifference(inputBytes, outputBytes),
        ]
    }

    static func authoredGodraysPreparedEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline
    ) throws -> [String: Any] {
        let size = 16
        guard let noise = makeTexture(device: device, size: size, usage: .shaderRead),
              let stockCommandBuffer = queue.makeCommandBuffer(),
              let legacyCommandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(noise, bgra: [127, 127, 127, 255])
        let plan = authoredGodraysPlan()
        let legacyPlan = authoredGodraysPlan(directionalV1: true)
        let stockPool = SceneOffscreenTexturePool(device: device, maxDimension: size)
        let legacyPool = SceneOffscreenTexturePool(device: device, maxDimension: size)
        let stockFrameTables = try prepareStageTargets(
            plan: plan,
            pool: stockPool,
            width: size,
            height: size,
            commandBuffer: stockCommandBuffer
        )
        let legacyFrameTables = try prepareStageTargets(
            plan: legacyPlan,
            pool: legacyPool,
            width: size,
            height: size,
            commandBuffer: legacyCommandBuffer
        )
        defer {
            stockFrameTables.commit.releaseAll()
            legacyFrameTables.commit.releaseAll()
        }
        guard let stockTable = stockFrameTables.tables.first,
              let legacyTable = legacyFrameTables.tables.first,
              let godrays = plan.godrays,
              let legacyGodrays = legacyPlan.godrays,
              let legacyFirst = legacyTable.texture(
                  for: legacyGodrays.firstHalfTarget
              ),
              let legacySecond = legacyTable.texture(
                  for: legacyGodrays.secondHalfTarget
              ) else {
            throw HarnessError.drawRefused
        }
        let resources = SceneGodraysEffectTextures(
            mask: nil,
            maskUVScale: SIMD2(repeating: 1),
            maskPath: nil,
            noise: noise
        )
        func preparation(
            _ stage: SceneEffectStageExecutionPlan,
            table: SceneGraphRenderTargetTable,
            resources: [String: SceneGodraysEffectTextures]
        ) -> SceneEffectStageRenderer.StagePreparation {
            SceneEffectStageRenderer.prepareStage(
                stage,
                sourceTexture: table.inputTexture,
                targets: table,
                inputs: .init(
                    masks: authoredEffectMasks(godraysEffects: resources),
                    dynamicValues: .empty(frameIndex: 1),
                    pipelines: .init(
                        repository: SceneImageEffectPipelineRepository(device: device)
                    ),
                    cursorUV: .zero,
                    previousCursorUV: .zero,
                    pointerIsInside: false,
                    previousPointerIsInside: false,
                    pointerMovement: 0,
                    primaryButtonIsDown: false,
                    frameTime: 1 / 60,
                    time: 0,
                    audioSpectrum: .silent,
                    dependencyEffect: nil
                ),
                sourcePipeline: pipeline,
                time: 0
            )
        }
        let stockAccepted = preparation(
            plan,
            table: stockTable,
            resources: [godrays.effectKey.descriptorID: resources]
        )
        let stockPreparedStageEncoded: Bool
        let stockPreparationReason: String?
        switch stockAccepted {
        case .ready(let stockPrepared):
            stockPreparedStageEncoded = SceneEffectStageRenderer
                .encodePreparedStage(
                    stockPrepared,
                    commandBuffer: stockCommandBuffer
                )
            stockPreparationReason = stockPreparedStageEncoded ? nil : "encode-refused"
        case .rejected(let reason):
            stockPreparedStageEncoded = false
            stockPreparationReason = reason
        }

        let legacyAccepted = preparation(
            legacyPlan,
            table: legacyTable,
            resources: [legacyGodrays.effectKey.descriptorID: resources]
        )
        let legacyPreparedStageEncoded: Bool
        let legacyPreparationReason: String?
        switch legacyAccepted {
        case .ready(let legacyPrepared):
            legacyPreparedStageEncoded = SceneEffectStageRenderer
                .encodePreparedStage(
                    legacyPrepared,
                    commandBuffer: legacyCommandBuffer
                )
            legacyPreparationReason = legacyPreparedStageEncoded ? nil : "encode-refused"
        case .rejected(let reason):
            legacyPreparedStageEncoded = false
            legacyPreparationReason = reason
        }

        let stockMissing = preparation(plan, table: stockTable, resources: [:])
        let legacyMissing = preparation(
            legacyPlan,
            table: legacyTable,
            resources: [:]
        )
        stockCommandBuffer.commit()
        legacyCommandBuffer.commit()
        stockCommandBuffer.waitUntilCompleted()
        legacyCommandBuffer.waitUntilCompleted()
        guard stockCommandBuffer.status == .completed,
              stockCommandBuffer.error == nil,
              legacyCommandBuffer.status == .completed,
              legacyCommandBuffer.error == nil else {
            throw HarnessError.commandFailed
        }
        let stockMissingReason: String?
        if case let .rejected(reason) = stockMissing { stockMissingReason = reason }
        else { stockMissingReason = nil }
        let legacyMissingReason: String?
        if case let .rejected(reason) = legacyMissing { legacyMissingReason = reason }
        else { legacyMissingReason = nil }
        let legacyRGBAContract = legacyTable.plan.logicalTargets.count == 2
            && legacyTable.plan.logicalTargets.allSatisfy { $0.format == .rgba8888 }
            && legacyFirst.pixelFormat == .rgba8Unorm
            && legacySecond.pixelFormat == .rgba8Unorm
            && legacyFirst !== legacySecond
            && legacyTable.inputTexture.pixelFormat == .bgra8Unorm
            && legacyTable.outputTexture.pixelFormat == .bgra8Unorm
            && legacyTable.inputTexture !== legacyTable.outputTexture
        return [
            "stockPreparedStageEncoded": stockPreparedStageEncoded,
            "stockPreparationReason": stockPreparationReason as Any,
            "legacyPreparedStageEncoded": legacyPreparedStageEncoded,
            "legacyPreparationReason": legacyPreparationReason as Any,
            "legacyRGBAContract": legacyRGBAContract,
            "stockMissingResourceReason": stockMissingReason as Any,
            "legacyMissingResourceReason": legacyMissingReason as Any,
        ]
    }

    static func authoredShinePreparedEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline
    ) throws -> [String: Any] {
        let size = 16
        guard let noise = makeTexture(device: device, size: size, usage: .shaderRead),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(noise, bgra: [127, 127, 127, 255])
        let plan = authoredShinePlan()
        let pool = SceneOffscreenTexturePool(device: device, maxDimension: size)
        let frameTables = try prepareStageTargets(
            plan: plan,
            pool: pool,
            width: size,
            height: size,
            commandBuffer: commandBuffer
        )
        defer { frameTables.commit.releaseAll() }
        guard let table = frameTables.tables.first,
              let shine = plan.shine else {
            throw HarnessError.drawRefused
        }
        let resources = SceneShineEffectTextures(
            mask: nil,
            maskPath: nil,
            noise: noise,
            noisePath: shine.noiseTexturePath
        )
        func preparation(
            resources: [String: SceneShineEffectTextures]
        ) -> SceneEffectStageRenderer.StagePreparation {
            SceneEffectStageRenderer.prepareStage(
                plan,
                sourceTexture: table.inputTexture,
                targets: table,
                inputs: .init(
                    masks: authoredEffectMasks(shineEffects: resources),
                    dynamicValues: .empty(frameIndex: 1),
                    pipelines: .init(
                        repository: SceneImageEffectPipelineRepository(device: device)
                    ),
                    cursorUV: .zero,
                    previousCursorUV: .zero,
                    pointerIsInside: false,
                    previousPointerIsInside: false,
                    pointerMovement: 0,
                    primaryButtonIsDown: false,
                    frameTime: 1 / 60,
                    time: 0,
                    audioSpectrum: .silent,
                    dependencyEffect: nil
                ),
                sourcePipeline: pipeline,
                time: 0
            )
        }
        let accepted = preparation(
            resources: [shine.effectKey.descriptorID: resources]
        )
        guard case let .ready(prepared) = accepted,
              SceneEffectStageRenderer.encodePreparedStage(
                  prepared,
                  commandBuffer: commandBuffer
              ) else { throw HarnessError.drawRefused }
        let missing = preparation(resources: [:])
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed,
              commandBuffer.error == nil else { throw HarnessError.commandFailed }
        let missingReason: String?
        if case let .rejected(reason) = missing { missingReason = reason }
        else { missingReason = nil }
        return [
            "preparedStageEncoded": true,
            "missingResourceReason": missingReason as Any,
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
            waterRippleEffects: [:],
            depthParallaxEffects: [:],
            blendEffects: [:],
            shakeEffects: [:],
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
            pulseEffects: [:],
            godraysEffects: [:],
            shineEffects: [:],
            xRay: nil
        )
    }

    // Resolved material composition remains the only product owner for the
    // graph below; the runtime must execute the claim or fail closed.
    static func resolvedMaterialCompositionEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline
    ) throws -> [String: Any] {
        let size = 8
        guard let source = makeTexture(
            device: device,
            size: size,
            usage: .shaderRead
        ) else { throw HarnessError.metalUnavailable }
        let graph = xRayStage(layerID: 0).renderGraph
        let pairPlan: SceneLayerFullFramePairPlan
        switch SceneLayerFullFramePairPlan.make(conditionPrunedGraphs: [graph]) {
        case let .success(value): pairPlan = value
        case .failure: throw HarnessError.drawRefused
        }
        let claim = SceneResolvedMaterialRuntimeBridge.ClaimedExecution(
            token: .init(rawValue: 1),
            layerID: graph.layerID,
            admittedGraphs: [graph],
            targetExecutionPlans: [],
            pairPlan: pairPlan,
            fullFrameExtentPolicy: .standard,
            sourceRoute: .capturedLayerTexture,
            dependencyOwnership: .none
        )
        let layer = SceneRenderDescriptor.Layer(
            contentKind: "image",
            colorRGB: nil,
            colorBlendMode: nil,
            effects: []
        )
        let request = SceneImageLayerDrawRequest(
            layer: layer,
            texture: source,
            masks: .empty,
            textureFrame: .identity,
            mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
            uniforms: SceneImageLayerUniformValues(
                time: 0,
                alpha: 1,
                cursorUV: .zero
            ),
            offscreenTexturePool: nil,
            offscreenSize: nil,
            requiresSourceCopy: false,
            finalCompositeAlpha: nil,
            dependencyEffect: nil,
        )

        func makePass() throws -> (SceneMainPassEncoder, MTLCommandBuffer) {
            guard let target = makeTexture(
                device: device,
                size: size,
                usage: [.renderTarget, .shaderRead]
            ), let commandBuffer = queue.makeCommandBuffer() else {
                throw HarnessError.metalUnavailable
            }
            return (
                SceneMainPassEncoder(
                    commandBuffer: commandBuffer,
                    target: target,
                    clearColor: MTLClearColorMake(0, 0, 0, 0)
                ),
                commandBuffer
            )
        }

        func frameRequest(
            pool: SceneOffscreenTexturePool,
            commandBuffer: MTLCommandBuffer
        ) throws -> SceneImageLayerDrawRequest {
            let result = SceneResolvedMaterialGraphComposition.preflight(
                requests: [.init(
                    claim: claim,
                    fullFrameExtentPolicy: claim.fullFrameExtentPolicy,
                    requestedWidth: size,
                    requestedHeight: size
                )],
                pool: pool,
                commandBuffer: commandBuffer
            )
            guard case let .ready(plans, _) = result,
                  let plan = plans[claim.layerID] else {
                throw HarnessError.drawRefused
            }
            return SceneImageLayerDrawRequest(
                layer: request.layer,
                texture: request.texture,
                masks: request.masks,
                textureFrame: request.textureFrame,
                mvp: request.mvp,
                uniforms: request.uniforms,
                offscreenTexturePool: pool,
                resolvedMaterialFrameTargetPlan: plan,
                offscreenSize: request.offscreenSize,
                requiresSourceCopy: request.requiresSourceCopy,
                finalCompositeAlpha: request.finalCompositeAlpha,
                dependencyEffect: request.dependencyEffect,
            )
        }

        let successRuntime = SceneResolvedMaterialRuntimeBridge()
        let successRecorder = ExactEvidenceLogRecorder()
        let successTrace = SceneEffectExecutionTelemetry(
            logSink: { successRecorder.append($0) }
        ).makeFrame(frameIndex: 701)
        let (successPass, successBuffer) = try makePass()
        let successPool = SceneOffscreenTexturePool(
            device: device, maxDimension: size
        )
        let successRequest = try frameRequest(
            pool: successPool, commandBuffer: successBuffer
        )
        guard let successPlan = successRequest.resolvedMaterialFrameTargetPlan,
              case .ready = successRuntime.prepareFrame(
                  [.init(
                      claim: claim,
                      targetPlan: successPlan,
                      sourceTexture: source,
                      sourceUniforms: .neutral(),
                      sourcePipeline: pipeline
                  )],
                  pool: successPool,
                  commandBuffer: successBuffer
              ) else { throw HarnessError.drawRefused }
        let successResult = SceneResolvedMaterialGraphComposition.executeClaimed(
            runtime: successRuntime,
            claim: claim,
            request: successRequest,
            mainPass: successPass,
            executionTrace: successTrace,
            executionOrigin: .image
        )
        let successWasEncoded: Bool
        switch successResult {
        case let .encoded(texture, ticket):
            successWasEncoded = texture === source && ticket.identity == 1
        case .failed:
            successWasEncoded = false
        }
        successPass.finishEnsuringClear()
        successBuffer.commit()
        successBuffer.waitUntilCompleted()

        let failedRuntime = SceneResolvedMaterialRuntimeBridge(
            executionShouldSucceed: false
        )
        let failedRecorder = ExactEvidenceLogRecorder()
        let failedTrace = SceneEffectExecutionTelemetry(
            logSink: { failedRecorder.append($0) }
        ).makeFrame(frameIndex: 702)
        let (failedPass, failedBuffer) = try makePass()
        let failedPool = SceneOffscreenTexturePool(
            device: device, maxDimension: size
        )
        let failedRequest = try frameRequest(
            pool: failedPool, commandBuffer: failedBuffer
        )
        guard let failedPlan = failedRequest.resolvedMaterialFrameTargetPlan,
              case .ready = failedRuntime.prepareFrame(
                  [.init(
                      claim: claim,
                      targetPlan: failedPlan,
                      sourceTexture: source,
                      sourceUniforms: .neutral(),
                      sourcePipeline: pipeline
                  )],
                  pool: failedPool,
                  commandBuffer: failedBuffer
              ) else { throw HarnessError.drawRefused }
        let failedResult = SceneResolvedMaterialGraphComposition.executeClaimed(
            runtime: failedRuntime,
            claim: claim,
            request: failedRequest,
            mainPass: failedPass,
            executionTrace: failedTrace,
            executionOrigin: .image
        )
        let executorFailureStayedClosed: Bool
        switch failedResult {
        case .failed: executorFailureStayedClosed = true
        case .encoded: executorFailureStayedClosed = false
        }
        failedPass.finishEnsuringClear()
        failedBuffer.commit()
        failedBuffer.waitUntilCompleted()

        let allocationRuntime = SceneResolvedMaterialRuntimeBridge()
        let (allocationPass, allocationBuffer) = try makePass()
        let allocationResult = SceneResolvedMaterialGraphComposition.preflight(
            requests: [.init(
                claim: claim,
                fullFrameExtentPolicy: claim.fullFrameExtentPolicy,
                requestedWidth: size,
                requestedHeight: size
            )],
            pool: SceneOffscreenTexturePool(
                device: device, maxDimension: size, residentByteBudget: 0
            ),
            commandBuffer: allocationBuffer
        )
        let allocationFailureReason: String?
        switch allocationResult {
        case let .rejected(reasonCode): allocationFailureReason = reasonCode
        case .ready, .deferred: allocationFailureReason = nil
        }
        let allocationFailureStayedClosed =
            allocationFailureReason == "frame-target-byte-budget-exceeded"
        allocationPass.finishEnsuringClear()
        allocationBuffer.commit()
        allocationBuffer.waitUntilCompleted()

        let compositeRuntime = SceneResolvedMaterialRuntimeBridge(
            claimedExecution: claim,
            compositeFailureReason: "fixture-composite-rejected"
        )
        let composite = SceneImageLayerCompositor(
            pipelineRepository: SceneImageEffectPipelineRepository(device: device),
            resolvedMaterialRuntime: compositeRuntime
        )
        let (compositePass, compositeBuffer) = try makePass()
        let compositePool = SceneOffscreenTexturePool(
            device: device, maxDimension: size
        )
        let compositeRequest = try frameRequest(
            pool: compositePool,
            commandBuffer: compositeBuffer
        )
        guard let compositePlan = compositeRequest.resolvedMaterialFrameTargetPlan,
              case .ready = compositeRuntime.prepareFrame(
                  [.init(
                      claim: claim,
                      targetPlan: compositePlan,
                      sourceTexture: source,
                      sourceUniforms: .neutral(),
                      sourcePipeline: pipeline
                  )],
                  pool: compositePool,
                  commandBuffer: compositeBuffer
              ) else { throw HarnessError.drawRefused }
        let compositeFailureStayedClosed = !composite.draw(
            compositeRequest,
            pipeline: pipeline,
            mainPass: compositePass
        )
        compositePass.finishEnsuringClear()
        compositeBuffer.commit()
        compositeBuffer.waitUntilCompleted()

        let unavailableRuntimeCompositor = SceneImageLayerCompositor(
            pipelineRepository: SceneImageEffectPipelineRepository(device: device)
        )
        let unavailableRuntimeRecorder = ExactEvidenceLogRecorder()
        let unavailableRuntimeTrace = SceneEffectExecutionTelemetry(
            logSink: { unavailableRuntimeRecorder.append($0) }
        ).makeFrame(frameIndex: 703)
        let (unavailableRuntimePass, unavailableRuntimeBuffer) = try makePass()
        let unavailableRuntimePool = SceneOffscreenTexturePool(
            device: device, maxDimension: size
        )
        let unavailableRuntimeRequest = try frameRequest(
            pool: unavailableRuntimePool,
            commandBuffer: unavailableRuntimeBuffer
        )
        let unavailableRuntimeStayedClosed = !unavailableRuntimeCompositor.draw(
            unavailableRuntimeRequest,
            pipeline: pipeline,
            mainPass: unavailableRuntimePass,
            executionTrace: unavailableRuntimeTrace
        )
        unavailableRuntimePass.finishEnsuringClear()
        unavailableRuntimeBuffer.commit()
        unavailableRuntimeBuffer.waitUntilCompleted()

        let rejectedRuntime = SceneResolvedMaterialRuntimeBridge(
            claimRejectionReason: "fixture-route-rejected"
        )
        let rejectedCompositor = SceneImageLayerCompositor(
            pipelineRepository: SceneImageEffectPipelineRepository(device: device),
            resolvedMaterialRuntime: rejectedRuntime
        )
        let rejectedRoute = rejectedCompositor.resolvedMaterialClaim(for: request)
        let rejectedClaimStayedClosed = rejectedRoute.isRejected
            && rejectedRoute.execution == nil
            && rejectedRuntime.claimedFailureReasons == ["fixture-route-rejected"]
        let revokedAuthorityRuntime = SceneResolvedMaterialRuntimeBridge(
            claimRejectionReason: "material-generic-owner-revoked"
        )
        let revokedAuthorityCompositor = SceneImageLayerCompositor(
            pipelineRepository: SceneImageEffectPipelineRepository(device: device),
            resolvedMaterialRuntime: revokedAuthorityRuntime
        )
        let revokedAuthorityDrawRoute = revokedAuthorityCompositor
            .resolvedMaterialClaim(for: request)
        let revokedAuthorityPreflightRoute = revokedAuthorityCompositor
            .preflightResolvedMaterialClaim(layerID: request.layer.id)
        let revokedAuthorityStayedLocal =
            revokedAuthorityDrawRoute.isRejected
            && revokedAuthorityDrawRoute.rejectsUnclaimedProductAuthority
            && revokedAuthorityDrawRoute.execution == nil
            && {
                guard case .unclaimed = revokedAuthorityPreflightRoute else {
                    return false
                }
                return true
            }()
            && revokedAuthorityRuntime.claimedFailureReasons.isEmpty

        guard successBuffer.status == .completed,
              failedBuffer.status == .completed,
              allocationBuffer.status == .completed,
              compositeBuffer.status == .completed,
              unavailableRuntimeBuffer.status == .completed else {
            throw HarnessError.commandFailed
        }
        return [
            "successWasEncoded": successWasEncoded,
            "successExecuteCalls": successRuntime.executeCallCount,
            "successFailureReasons": successRuntime.claimedFailureReasons,
            "executorFailureStayedClosed": executorFailureStayedClosed,
            "executorFailureExecuteCalls": failedRuntime.executeCallCount,
            "executorFailureReasons": failedRuntime.claimedFailureReasons,
            "successExactEvidence": successRecorder.lines.filter {
                $0.contains("axis=effect-cpu-invocation")
            },
            "failedExactEvidence": failedRecorder.lines.filter {
                $0.contains("axis=effect-cpu-invocation")
            },
            "allocationFailureStayedClosed": allocationFailureStayedClosed,
            "allocationFailureReason": allocationFailureReason ?? "missing",
            "allocationFailureExecuteCalls": allocationRuntime.executeCallCount,
            "allocationFailureReasons": allocationRuntime.claimedFailureReasons,
            "compositeFailureStayedClosed": compositeFailureStayedClosed,
            "compositeFailureMarkCalls": compositeRuntime.markCompositeCallCount,
            "compositeFailureReasons": compositeRuntime.claimedFailureReasons,
            "unavailableRuntimeStayedClosed": unavailableRuntimeStayedClosed,
            "unavailableRuntimeEvidence": unavailableRuntimeRecorder.lines,
            "rejectedClaimStayedClosed": rejectedClaimStayedClosed,
            "revokedAuthorityStayedLocal": revokedAuthorityStayedLocal,
        ]
    }

    static func xRayStage(layerID: Int) -> SceneEffectStageExecutionPlan {
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
        let stage = SceneEffectStageExecutionPlan(
            layerID: layerID,
            renderGraph: graph,
            backend: .xRay(SceneXRayExecutionPlan(
                declaration: SceneXRayRuntimePlanner.Declaration()
            )),
            materialNodeCount: 1,
            logicalRenderTargetCount: 0
        )
        return stage
    }

    static func prepareStageTargets(
        plan: SceneEffectStageExecutionPlan,
        pool: SceneOffscreenTexturePool,
        width: Int,
        height: Int,
        commandBuffer: MTLCommandBuffer
    ) throws -> PreparedStageTargets {
        let orderingContext = SceneGraphCommandQueueOrderingContext(
            commandBuffer: commandBuffer
        )
        guard case let .success(pairPlan) = SceneLayerFullFramePairPlan.make(
                  conditionPrunedGraphs: [plan.renderGraph]
              ), let framePlan = pool.framePlanForPersistentGraphTargets(
            admittedGraphs: [plan.renderGraph],
            targetExecutionPlans: [plan],
            pairPlan: pairPlan,
            extentPolicy: .init(
                maximumDimensionClass: .standard,
                requiresExactInputExtent: plan.requiresExactInputExtent
            ),
            requestedWidth: width,
            requestedHeight: height,
            orderingContext: orderingContext
        ), let prepared = pool.preparePersistentGraphTargets(
            framePlan: framePlan
        ), let commit = prepared.commitAndPin(
            historyTokensByEffect: [:],
            commandBuffer: commandBuffer
        ) else {
            throw HarnessError.drawRefused
        }
        return .init(tables: commit.leases.map { $0.table }, commit: commit)
    }

    static func drawAuthoredBlur(
        source: MTLTexture,
        target: MTLTexture,
        layer: SceneRenderDescriptor.Layer,
        plan: SceneEffectStageExecutionPlan,
        pool: SceneOffscreenTexturePool,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        masks: SceneImageLayerMasks = .empty
    ) throws -> PreparedStageTargets {
        guard let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        let frameTables = try prepareStageTargets(
            plan: plan,
            pool: pool,
            width: source.width,
            height: source.height,
            commandBuffer: commandBuffer
        )
        defer { frameTables.commit.releaseAll() }
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        guard let table = frameTables.tables.first,
              SceneOffscreenEffectRenderer.captureSource(
                  sourceTexture: source,
                  target: table.inputTexture,
                  sourceUniforms: .neutral(),
                  pipeline: pipeline,
                  commandBuffer: commandBuffer
              ), let output = SceneEffectStageRenderer.renderStage(
                  plan,
                  sourceTexture: table.inputTexture,
                  masks: masks,
                  targets: table,
                  dynamicValues: .empty(frameIndex: 1),
                  sourceUniforms: .neutral(),
                  pipeline: pipeline,
                  pipelines: .init(
                      repository: SceneImageEffectPipelineRepository(device: source.device)
                  ),
                  cursorUV: .zero,
                  previousCursorUV: .zero,
                  pointerIsInside: false,
                  previousPointerIsInside: false,
                  pointerMovement: 0,
                  primaryButtonIsDown: false,
                  frameTime: 1 / 60,
                  time: 0,
                  audioSpectrum: .silent,
                  dependencyEffect: nil,
                  commandBuffer: commandBuffer
              ), SceneImageLayerMainPassRenderer.draw(
                  texture: output,
                  mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                  uniforms: compositor.makeFragmentUniforms(
                      values: SceneImageLayerUniformValues(
                          time: 0, alpha: 1, cursorUV: .zero
                      ),
                      textureFrame: .identity,
                      tint: SIMD3(repeating: 1),
                      dependencyBlendMode: nil
                  ),
                  dependencyTexture: nil,
                  layer: layer,
                  pipeline: pipeline,
                  colorBlendPipeline: nil,
                  mainPass: mainPass
              ) else {
            throw HarnessError.drawRefused
        }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return frameTables
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
    ) -> SceneEffectStageExecutionPlan {
        let graph = standardBlurGraph(
            layerID: layerID,
            effectIndex: effectIndex,
            input: input
        )
        return SceneEffectStageExecutionPlan(
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

    static func authoredLocalContrastPlan() -> SceneEffectStageExecutionPlan {
        let blurGraph = standardBlurGraph(layerID: 831)
        let graph = Graph(
            layerID: blurGraph.layerID,
            effects: blurGraph.effects,
            renderTargets: blurGraph.renderTargets.map {
                .init(
                    texture: $0.texture,
                    extent: $0.extent,
                    format: "rgba8888",
                    declaredUnique: $0.declaredUnique,
                    clear: $0.clear,
                    uvs: $0.uvs,
                    conditions: $0.conditions
                )
            },
            nodes: blurGraph.nodes,
            finalOutput: blurGraph.finalOutput,
            blockers: blurGraph.blockers
        )
        let first = graph.renderTargets.first {
            $0.texture.name?.lowercased() == "_rt_quartercompobuffer1"
        }?.texture
        let second = graph.renderTargets.first {
            $0.texture.name?.lowercased() == "_rt_quartercompobuffer2"
        }?.texture
        precondition(first != nil && second != nil)
        return SceneEffectStageExecutionPlan(
            layerID: graph.layerID,
            renderGraph: graph,
            backend: .localContrast(SceneLocalContrastPlan(
                firstQuarterTarget: first!,
                secondQuarterTarget: second!,
                renderGraph: graph,
                staticOrFallbackStrength: 0.32
            )),
            materialNodeCount: 4,
            logicalRenderTargetCount: 2
        )
    }

    static func authoredGodraysPlan(
        directionalV1: Bool = false
    ) -> SceneEffectStageExecutionPlan {
        let layerID = 832
        let effectKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "\(layerID)#effect#0"
        )
        let input = graphTexture(.layerSource, layerID: layerID)
        let output = graphTexture(.effectOutput, layerID: layerID, effect: effectKey)
        let firstHalf = graphTexture(
            .framebuffer,
            layerID: layerID,
            effect: effectKey,
            name: "_rt_HalfCompoBuffer1"
        )
        let secondHalf = graphTexture(
            .framebuffer,
            layerID: layerID,
            effect: effectKey,
            name: "_rt_HalfCompoBuffer2"
        )
        let targets = [firstHalf, secondHalf, firstHalf, secondHalf, output]
        let nodes = targets.indices.map { index in
            Graph.Node(
                nodeIndex: index,
                effect: effectKey,
                definitionPassIndex: index,
                materialOrdinal: index,
                instancePassIndex: index,
                kind: .material,
                materialPath: "materials/effects/godrays_\(index).json",
                materialPassID: "materials/effects/godrays_\(index).json#0",
                target: targets[index],
                bindings: [],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            )
        }
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath: "effects/godrays/effect.json",
            input: input,
            output: output,
            nodeIndices: nodes.map(\.nodeIndex)
        )
        let graph = Graph(
            layerID: layerID,
            effects: [effect],
            renderTargets: [firstHalf, secondHalf].map {
                .init(
                    texture: $0,
                    extent: .init(kind: .scale, first: 2, second: nil),
                    format: directionalV1 ? "rgba8888" : "rgba_backbuffer",
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
        return SceneEffectStageExecutionPlan(
            layerID: layerID,
            renderGraph: graph,
            backend: .godrays(SceneGodraysPlan(
                effectKey: effectKey,
                firstHalfTarget: firstHalf,
                secondHalfTarget: secondHalf,
                direction: directionalV1 ? 0 : nil,
                usesDirectionalGaussianKernel: directionalV1,
                maskTexturePath: nil
            )),
            materialNodeCount: 5,
            logicalRenderTargetCount: 2
        )
    }

    static func authoredShinePlan() -> SceneEffectStageExecutionPlan {
        let layerID = 833
        let effectKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "\(layerID)#effect#0"
        )
        let input = graphTexture(.layerSource, layerID: layerID)
        let output = graphTexture(.effectOutput, layerID: layerID, effect: effectKey)
        let firstHalf = graphTexture(
            .framebuffer,
            layerID: layerID,
            effect: effectKey,
            name: "_rt_HalfCompoBuffer1"
        )
        let secondHalf = graphTexture(
            .framebuffer,
            layerID: layerID,
            effect: effectKey,
            name: "_rt_HalfCompoBuffer2"
        )
        let targets = [firstHalf, secondHalf, firstHalf, secondHalf, output]
        let nodes = targets.indices.map { index in
            Graph.Node(
                nodeIndex: index,
                effect: effectKey,
                definitionPassIndex: index,
                materialOrdinal: index,
                instancePassIndex: index,
                kind: .material,
                materialPath: "materials/effects/shine_\(index).json",
                materialPassID: "materials/effects/shine_\(index).json#0",
                target: targets[index],
                bindings: [],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            )
        }
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath: "effects/shine/effect.json",
            input: input,
            output: output,
            nodeIndices: nodes.map(\.nodeIndex)
        )
        let graph = Graph(
            layerID: layerID,
            effects: [effect],
            renderTargets: [firstHalf, secondHalf].map {
                .init(
                    texture: $0,
                    extent: .init(kind: .scale, first: 2, second: nil),
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
        return SceneEffectStageExecutionPlan(
            layerID: layerID,
            renderGraph: graph,
            backend: .shine(SceneShineExecutionPlan(
                effectKey: effectKey,
                firstHalfTarget: firstHalf,
                secondHalfTarget: secondHalf,
                maskTexturePath: nil,
                noiseTexturePath: "util/clouds_256"
            )),
            materialNodeCount: 5,
            logicalRenderTargetCount: 2
        )
    }

    static func externalProceduralNoiseStage()
        -> SceneEffectStageExecutionPlan {
        let layerID = 847
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
            materialPath: "materials/workshop/procedural_noise.json",
            materialPassID: "materials/workshop/procedural_noise.json#0",
            target: output,
            bindings: [],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath:
                "effects/workshop/2924967132/procedural_noise/effect.json",
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
        let noise = SceneProceduralNoiseExecutionPlan(
            layerID: layerID,
            effectKey: effectKey,
            renderGraph: graph,
            variant: .worleyColorV1,
            scale: SIMD2(repeating: 1),
            offset: .zero,
            magnitude: SIMD2(repeating: 1),
            thresholds: SIMD2(0, 1),
            colorsMin: .zero,
            colorsMax: SIMD3(repeating: 1),
            opacity: 1,
            exponent: 1,
            fractals: 1,
            fractalScale: 2,
            fractalInfluence: 0.5,
            gradient: 0,
            seed: 0,
            animationSpeed: 0,
            scrollDirection: 0,
            scrollSpeed: 0,
            thresholdOffset: 0,
            shiftAmount: 1,
            depthFade: 1,
            perspective01: SIMD4(0, 0, 1, 0),
            perspective23: SIMD4(1, 1, 0, 1),
            dependencyProviderLayerID: 1,
            dependencySlotIndex: 3
        )
        let stage = SceneEffectStageExecutionPlan(
            layerID: layerID,
            renderGraph: graph,
            backend: .proceduralNoise(noise),
            materialNodeCount: 1,
            logicalRenderTargetCount: 0
        )
        return stage
    }



    static func authoredEffectMasks(
        blendEffects: [String: SceneBlendEffectTextures] = [:],
        godraysEffects: [String: SceneGodraysEffectTextures] = [:],
        shineEffects: [String: SceneShineEffectTextures] = [:],
    ) -> SceneImageLayerMasks {
        SceneImageLayerMasks(
            waterRippleEffects: [:],
            depthParallaxEffects: [:],
            blendEffects: blendEffects,
            shakeEffects: [:],
            standardBlurEffects: [:],
            waterFlowEffects: [:],
            waterWavesEffects: [:],
            waterCausticsEffects: [:],
            cursorRippleEffects: [:],
            pulseEffects: [:],
            godraysEffects: godraysEffects,
            shineEffects: shineEffects,
            xRay: nil
        )
    }



    static func makeTexture(
        device: MTLDevice,
        size: Int,
        usage: MTLTextureUsage,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        storageMode: MTLStorageMode = .shared
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = storageMode
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
    def test_image_blend_product_owner_and_source_preparation_are_retired(
        self,
    ) -> None:
        retired_paths = (
            SOURCE_ROOT / "Rendering/SceneImageBlendRenderPlan.swift",
            SOURCE_ROOT / "Rendering/SceneImageBlendRuntime.swift",
            SOURCE_ROOT / "Rendering/SceneImageBlendPipeline.swift",
        )
        for path in retired_paths:
            self.assertFalse(path.exists(), path)

        product_root = REPOSITORY_ROOT / "MyWallpaperX"
        product_source = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted(product_root.rglob("*.swift"))
        )
        for symbol in (
            "SceneImageBlendRenderPlan",
            "SceneImageBlendRuntime",
            "SceneImageBlendPipeline",
            "requiresSourcePreparation(",
            "preparedSourceTexture(",
        ):
            self.assertNotIn(symbol, product_source)

        dependency_runtime = (
            SOURCE_ROOT
            / "RenderGraph/LayerDependencies/SceneDependencyFrameRuntime.swift"
        ).read_text(encoding="utf-8")
        self.assertNotIn("requiresSourcePreparation", dependency_runtime)
        self.assertNotIn("preparedSourceTexture", dependency_runtime)

    def test_resolved_material_waits_for_base_source_before_runtime_begin(
        self,
    ) -> None:
        source = (
            SOURCE_ROOT / "Rendering/SceneResolvedMaterialFramePreflight.swift"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "case .capturedLayerTexture:\n"
            "                guard let texture = imageTextures[layer.id] else {\n"
            "                    return .deferred\n"
            "                }",
            source,
        )
        self.assertIn("case .transparentDirectDraw:", source)
        self.assertIn("sourceTexture = nil", source)
        self.assertIn(
            "let layerModelMatrix = worldFramesByLayerID[layerID]",
            source,
        )
        self.assertIn("layerModelMatrix: layerModelMatrix", source)
        self.assertIn(
            "var sourceUniforms: SceneLayerFragmentUniforms? = nil",
            source,
        )
        self.assertIn("case .capturedMainTargetTexture:", source)
        self.assertIn("sourceTexture = mainTarget", source)
        self.assertNotIn("frame-source-texture-unavailable", source)

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

    def test_static_base_color_candidate_is_atomic_at_final_gpu_split(self) -> None:
        evidence = self.result["baseColorCandidate"]
        self.assertTrue(evidence["referenceEncoded"], evidence)
        self.assertTrue(evidence["candidateEncoded"], evidence)
        self.assertTrue(evidence["matchesLegacyPixels"], evidence)
        self.assertTrue(evidence["fractionalPremultipliedPixelPreserved"], evidence)
        for key in (
            "wrongPurposeRejected",
            "mismatchedTextureRejected",
            "nonIdentityRejected",
            "nearestRejected",
            "repeatRejected",
            "clampBorderRejected",
        ):
            self.assertTrue(evidence[key], (key, evidence))

    def test_exact_layer_sources_passthrough_at_authored_geometry_on_next_frame(self) -> None:
        evidence = self.result["layerSourcePassthrough"]
        accepted = evidence["accepted"]
        self.assertEqual(
            set(accepted),
            {
                "staticFilePartial",
                "staticFileNextFrame",
                "currentMediaPartial",
                "currentMediaNextFrame",
                "rotated",
                "partiallyClipped",
                "pulseMaskDefaultAlpha",
                "pulseMaskAlphaZero",
                "pulseMaskAlphaZeroNextFrame",
                "pulseCurrentMediaWithStaticBlock",
                "pulseStaticFileAlphaZero",
                "pulseStaticFileAlphaZeroNextFrame",
                "waterWavesMaskStaticFile",
                "waterWavesMaskStaticFileNextFrame",
            },
        )
        for key, result in accepted.items():
            self.assertEqual(
                result["outcome"], "layer-source-passthrough", (key, result)
            )
            self.assertTrue(result["encoded"], (key, result))
            self.assertFalse(result["consumedDependency"], (key, result))
            self.assertTrue(
                any(
                    "operation=degraded-layer-source-passthrough" in line
                    and "outcome=encoded" in line
                    for line in result["trace"]
                ),
                (key, result),
            )

        for key in (
            "staticFilePartial",
            "staticFileNextFrame",
            "currentMediaPartial",
            "currentMediaNextFrame",
            "pulseMaskDefaultAlpha",
            "pulseMaskAlphaZero",
            "pulseMaskAlphaZeroNextFrame",
            "pulseCurrentMediaWithStaticBlock",
            "pulseStaticFileAlphaZero",
            "pulseStaticFileAlphaZeroNextFrame",
            "waterWavesMaskStaticFile",
            "waterWavesMaskStaticFileNextFrame",
        ):
            result = accepted[key]
            self.assert_pixel_close(result["centerBGRA"], [16, 32, 64, 128])
            self.assertEqual(result["topLeftBGRA"], [0, 0, 0, 0], result)
            self.assertEqual(result["bottomRightBGRA"], [0, 0, 0, 0], result)
            for exterior in result["exteriorRingBGRA"]:
                self.assertEqual(exterior, [0, 0, 0, 0], result)

        rotated = accepted["rotated"]
        self.assert_pixel_close(rotated["centerBGRA"], [16, 32, 64, 128])
        self.assertEqual(rotated["topLeftBGRA"], [0, 0, 0, 0], rotated)
        self.assertEqual(rotated["bottomRightBGRA"], [0, 0, 0, 0], rotated)

        clipped = accepted["partiallyClipped"]
        self.assert_pixel_close(clipped["rightMiddleBGRA"], [16, 32, 64, 128])
        self.assertEqual(clipped["centerBGRA"], [0, 0, 0, 0], clipped)
        self.assertEqual(clipped["leftMiddleBGRA"], [0, 0, 0, 0], clipped)
        self.assertEqual(clipped["topLeftBGRA"], [0, 0, 0, 0], clipped)

        ordinary = evidence["normalWithoutEffects"]
        self.assertEqual(ordinary["outcome"], "normal", ordinary)
        self.assertTrue(ordinary["encoded"], ordinary)
        self.assertFalse(ordinary["consumedDependency"], ordinary)
        self.assertFalse(
            any(
                "degraded-layer-source-passthrough" in line
                for line in ordinary["trace"]
            ),
            ordinary,
        )

    def test_layer_source_passthrough_rejects_inexact_owned_or_masked_routes(self) -> None:
        rejected = self.result["layerSourcePassthrough"]["rejected"]
        self.assertEqual(
            set(rejected),
            {
                "withDependency",
                "requiresDependencyEffect",
                "offscreen",
                "degenerate",
                "nonfinite",
                "builtIn",
                "wrongProvider",
                "wrongLayer",
                "staleGeneration",
                "bare",
                "unresolvedColor",
                "straightColor",
                "data",
                "wrongPurpose",
                "wrongTexture",
                "fileWithoutBaseCandidate",
                "fileMismatchedBaseCandidate",
                "currentMediaMismatchedBaseCandidate",
                "partialAlpha",
                "partialTint",
                "authoredTint",
                "malformedAuthoredTint",
                "brightness",
                "layerColorBlend",
                "claimed",
                "rejected",
                "pulseAlphaOneMasked",
                "pulseAlphaOneUnmasked",
                "pulseInvalidCombo",
                "pulseUnknownCombo",
                "pulseMissingPassMasked",
                "pulseWrongPassMasked",
                "pulseMultiplePassesMasked",
                "pulseWrongDefinitionMasked",
                "pulseStaticSourceConsumer",
                "waterWavesNonStockDefinition",
                "waterWavesTimeOffset",
                "waterWavesPerspective",
                "waterWavesDualWaves",
                "waterWavesUnknownCombo",
                "waterWavesMultiplePassesMasked",
                "waterWavesWrongPassMasked",
                "waterWavesStaticSourceConsumer",
                "mask-waterRipple",
                "mask-shake",
                "mask-standardBlur",
                "mask-waterWaves",
                "mask-waterCaustics",
                "mask-cursorRipple",
                "mask-godrays",
                "mask-shine",
                "mask-xray",
            },
        )
        for key, result in rejected.items():
            self.assertEqual(result["outcome"], "failed", (key, result))
            self.assertFalse(result["encoded"], (key, result))
            self.assertFalse(result["consumedDependency"], (key, result))
            self.assertEqual(result["centerBGRA"], [0, 0, 0, 0], (key, result))
            self.assertFalse(
                any(
                    "operation=degraded-layer-source-passthrough" in line
                    and "outcome=encoded" in line
                    for line in result["trace"]
                ),
                (key, result),
            )

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

    def test_legacy_procedural_stage_prepares_and_executes_with_exact_dependency(
        self,
    ) -> None:
        prepared = self.result["resolvedLegacyProceduralPrepared"]
        self.assertTrue(prepared["preparedStageEncoded"], prepared)
        self.assertTrue(prepared["outputHasPixels"], prepared)
        self.assertEqual(
            set(prepared["rejections"]),
            {"missing", "provider", "variant", "effect", "pass", "slot", "blend", "epoch"},
        )
        self.assertTrue(
            all(
                reason == "procedural-noise-dependency-missing"
                for reason in prepared["rejections"].values()
            ),
            prepared,
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
        self.assert_pixel_close(
            self.result["rejectedLayerBlendBGRA"],
            self.result["vividLayerBlendBGRA"],
            2,
        )


    def test_precise_graph_blur_runs_horizontal_then_vertical_on_mixed_alpha(self) -> None:
        evidence = self.result["authoredPreciseImpulse"]
        self.assertTrue(evidence["encoded"])
        self.assertTrue(evidence["preparedStageEncoded"])
        self.assertEqual(evidence["logicalTargetCount"], 1)
        self.assertFalse(evidence["inputOutputAliased"])
        self.assertTrue(evidence["sourceHasMixedAlpha"])
        self.assertTrue(evidence["outputHasPixels"])
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

    def test_raw_full_frame_compose_blur_uses_pair_without_a_logical_target(self) -> None:
        explicit = self.result["authoredPreciseImpulse"]
        compose = self.result["authoredFullFrameComposeImpulse"]
        self.assertTrue(compose["encoded"])
        self.assertTrue(compose["preparedStageEncoded"])
        self.assertEqual(compose["logicalTargetCount"], 0)
        self.assertTrue(compose["inputOutputAliased"])
        self.assertTrue(compose["intermediateUsesOtherPairMember"])
        self.assertEqual(compose["pairComposeTransitionCount"], 1)
        for key in (
            "inputMaxDelta",
            "horizontalMaxDelta",
            "outputMaxDelta",
            "mainMaxDelta",
        ):
            self.assertLessEqual(compose[key], 2, (key, compose))
            self.assertLessEqual(
                abs(compose[key] - explicit[key]), 1, (key, explicit, compose)
            )
        self.assertTrue(compose["sourceHasMixedAlpha"])
        self.assertTrue(compose["outputHasPixels"])
        self.assertTrue(compose["outputIsPremultiplied"])
        self.assertGreater(compose["horizontalToOutputDelta"], 2, compose)
        self.assertGreater(compose["sourceToOutputDelta"], 20, compose)

    def test_raw_full_frame_compose_preserves_source_extent_after_cap(self) -> None:
        evidence = self.result["authoredFullFrameComposeScaled"]
        self.assertTrue(evidence["encoded"])
        self.assertTrue(evidence["preparedStageEncoded"])
        self.assertEqual(evidence["sourceWidth"], 16)
        self.assertEqual(evidence["inputWidth"], 8)
        self.assertEqual(evidence["logicalTargetCount"], 0)
        self.assertTrue(evidence["inputOutputAliased"])
        self.assertTrue(evidence["intermediateUsesOtherPairMember"])
        self.assertEqual(evidence["pairComposeTransitionCount"], 1)
        self.assertLessEqual(evidence["horizontalMaxDelta"], 1, evidence)
        self.assertLessEqual(evidence["outputMaxDelta"], 1, evidence)
        self.assertGreater(evidence["targetNormalizedOutputDelta"], 1, evidence)
        self.assertTrue(evidence["outputHasPixels"])
        self.assertTrue(evidence["outputIsPremultiplied"])

    def test_standard_graph_blur_runs_full_ping_pong_chain_on_mixed_alpha(self) -> None:
        evidence = self.result["authoredStandardCheckerboard"]
        self.assertTrue(evidence["encoded"])
        self.assertTrue(evidence["preparedStageEncoded"])
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

    def test_standard_blur_consumes_typed_mask_candidate_and_rejects_wrong_purpose(
        self,
    ) -> None:
        evidence = self.result["authoredStandardCandidate"]
        self.assertTrue(evidence["accepted"], evidence)
        self.assertTrue(evidence["preparedStageAccepted"], evidence)
        self.assertEqual(
            evidence["wrongPurposePreparationReason"],
            "standard-blur-resource-missing",
            evidence,
        )
        self.assertEqual(
            evidence["missingPreparationReason"],
            "standard-blur-resource-missing",
            evidence,
        )
        self.assertTrue(evidence["paddedZeroMaskPreservedSource"], evidence)
        self.assertTrue(evidence["wrongPurposeRejected"], evidence)

    def test_local_contrast_prepared_stage_encodes_and_rejects_invalid_strength(
        self,
    ) -> None:
        evidence = self.result["authoredLocalContrastPrepared"]
        self.assertTrue(evidence["preparedStageEncoded"], evidence)
        self.assertGreater(evidence["inputToOutputDelta"], 0, evidence)
        self.assertEqual(
            evidence["invalidStrengthReason"],
            "local-contrast-strength-invalid",
            evidence,
        )

    def test_stock_and_legacy_godrays_prepare_encode_and_require_resources(
        self,
    ) -> None:
        evidence = self.result["authoredGodraysPrepared"]
        self.assertTrue(evidence["stockPreparedStageEncoded"], evidence)
        self.assertTrue(evidence["legacyPreparedStageEncoded"], evidence)
        self.assertTrue(evidence["legacyRGBAContract"], evidence)
        self.assertEqual(
            evidence["stockMissingResourceReason"],
            "godrays-resource-missing",
            evidence,
        )
        self.assertEqual(
            evidence["legacyMissingResourceReason"],
            "godrays-resource-missing",
            evidence,
        )

    def test_stock_shine_prepared_stage_requires_resources(self) -> None:
        evidence = self.result["authoredShinePrepared"]
        self.assertTrue(evidence["preparedStageEncoded"], evidence)
        self.assertEqual(
            evidence["missingResourceReason"],
            "shine-resource-missing",
            evidence,
        )

    def test_standard_blur_combine_uses_red_mask_in_premultiplied_space(self) -> None:
        mask_zero, mask_half, mask_one = self.result["standardBlurMaskPixels"]
        self.assert_pixel_close(mask_zero, [20, 40, 80, 100], 1)
        self.assert_pixel_close(mask_one, [100, 80, 40, 200], 1)
        self.assert_pixel_close(mask_half, [60, 60, 60, 150], 2)


    def test_production_resolved_material_composition_executes_and_fails_closed(
        self,
    ) -> None:
        evidence = self.result["resolvedMaterialComposition"]
        self.assertTrue(evidence["successWasEncoded"], evidence)
        self.assertEqual(evidence["successExecuteCalls"], 1, evidence)
        self.assertEqual(evidence["successFailureReasons"], [], evidence)
        self.assertTrue(evidence["executorFailureStayedClosed"], evidence)
        self.assertEqual(evidence["executorFailureExecuteCalls"], 1, evidence)
        self.assertEqual(evidence["executorFailureReasons"], [], evidence)
        self.assertEqual(len(evidence["successExactEvidence"]), 1, evidence)
        success_exact = evidence["successExactEvidence"][0]
        self.assertIn("subject=effect", success_exact)
        self.assertIn("family=generic-framebuffer", success_exact)
        self.assertIn("backend=resolved-material-graph", success_exact)
        self.assertIn("outcome=encoded-output", success_exact)
        self.assertEqual(evidence["failedExactEvidence"], [], evidence)
        self.assertTrue(evidence["allocationFailureStayedClosed"], evidence)
        self.assertEqual(
            evidence["allocationFailureReason"],
            "frame-target-byte-budget-exceeded",
            evidence,
        )
        self.assertEqual(evidence["allocationFailureExecuteCalls"], 0, evidence)
        self.assertEqual(
            evidence["allocationFailureReasons"],
            [],
            evidence,
        )
        self.assertTrue(evidence["compositeFailureStayedClosed"], evidence)
        self.assertEqual(evidence["compositeFailureMarkCalls"], 1, evidence)
        self.assertEqual(
            evidence["compositeFailureReasons"],
            ["fixture-composite-rejected"],
            evidence,
        )
        self.assertTrue(evidence["unavailableRuntimeStayedClosed"], evidence)
        self.assertEqual(len(evidence["unavailableRuntimeEvidence"]), 1, evidence)
        self.assertIn(
            "operation=resolved-material-claim",
            evidence["unavailableRuntimeEvidence"][0],
        )
        self.assertIn(
            "reason=resolved-material-runtime-unavailable",
            evidence["unavailableRuntimeEvidence"][0],
        )
        self.assertTrue(evidence["rejectedClaimStayedClosed"], evidence)
        self.assertTrue(evidence["revokedAuthorityStayedLocal"], evidence)

    def test_standard_blur_downsample_is_alpha_aware(self) -> None:
        self.assert_pixel_close(
            self.result["standardBlurAlphaAwareDownsampleBGRA"],
            [37, 73, 146, 84],
            3,
        )


    def test_foliage_mask_uses_mapped_to_physical_uv_scale(self) -> None:
        self.assertAlmostEqual(self.result["mappedMaskScale"][0], 0.9375, places=6)
        self.assertAlmostEqual(self.result["mappedMaskScale"][1], 0.52734375, places=6)

    def test_decoded_tex_does_not_reapply_removed_physical_padding(self) -> None:
        self.assertEqual(self.result["decodedMappedScale"], [1, 1])


    def test_base_layer_uniforms_exclude_effect_stage_payloads(self) -> None:
        self.assertEqual(self.result["fragmentUniformSize"], 80)
        self.assertEqual(self.result["dependencyBlendModeOffset"], 8)

    def assert_pixel_close(
        self, actual: list[int], expected: list[int], tolerance: int = 1
    ) -> None:
        self.assertEqual(len(actual), len(expected))
        for component, wanted in zip(actual, expected):
            self.assertLessEqual(abs(component - wanted), tolerance)


if __name__ == "__main__":
    unittest.main()
