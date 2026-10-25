import Foundation
import Metal
import simd

enum SceneParticleRuntimeDiagnosticKind: String, Codable, Sendable {
    case missingDefinition
    case invalidDefinition
    case cyclicChildReference
    case missingMaterial
    case unsupportedShader
    case missingTextureReference
    case missingTextureFile
    case builtInTextureUnavailable
    case unsupportedBlendMode
    case unsupportedRenderState
    case refractionUnsupported
    case missingSpriteRenderer
    case worldSpaceUnsupported
    case worldSpaceMovementUnsupported
    case layerImageEmitterUnsupported
    case trailRendererUnsupported
    case ropeRendererUnsupported
    case childSystemsUnsupported
    case textureLoadFailed
    case simulationLimitation
    case instanceBufferAllocationFailed
}

struct SceneParticleRuntimeDiagnostic: Codable, Equatable, Hashable, Sendable {
    let kind: SceneParticleRuntimeDiagnosticKind
    let layerID: Int?
    let particlePath: String
    let detail: String?
}

struct SceneParticleLayerImageEmitterCompilation {
    let mapsByLayerID: [Int: SceneParticleLayerImageEmissionMap]
    let diagnostics: [SceneParticleRuntimeDiagnostic]

    static let empty = SceneParticleLayerImageEmitterCompilation(
        mapsByLayerID: [:], diagnostics: []
    )
}

struct SceneParticleDrawBatch {
    let layerID: Int
    let particlePath: String
    let texture: MTLTexture
    let colorUVScale: SIMD2<Float>
    let colorSampling: SceneParticleTextureSampling
    let refraction: SceneParticleRefractionBinding?
    let renderState: SceneParticlePipelineRenderState
    let instanceBuffer: SceneParticleMetalInstanceBuffer
    let instances: [SceneParticleGPUInstance]
    let orientation: SceneParticleOrientation
    let orientationAxis: SIMD3<Float>?
    let usesPerspective: Bool
    /// Existing root RopeTrail admission, independent of Sprite material state.
    var inheritsNativeSceneCamera: Bool = false
    var referenceWorldFrame: simd_float4x4? = nil
    var sizeIsWorldSpace: Bool = false
}

#if DEBUG
struct SceneParticleRuntimeAudioEvaluationObservation: Hashable, Sendable {
    let layerID: Int
    let particlePath: String
    let evaluation: SceneParticleAudioEvaluationObservation
}

struct SceneParticleRuntimeAudioEvaluationIdentity: Hashable, Sendable {
    let layerID: Int
    let particlePath: String
    let componentKind: SceneParticleAudioComponentKind
    let componentIndex: Int
}
#endif

/// Immutable accounting for one live particle-runtime instance. This is an
/// observation of the existing root/child owners, not a second lifecycle state.
struct SceneParticleRuntimeLifecycleSnapshot: Equatable, Sendable {
    let activeLayerCount: Int
    let rootSystemCount: Int
    let childSystemCount: Int
    let rootParticleCount: Int
    let childParticleCount: Int

    static let empty = SceneParticleRuntimeLifecycleSnapshot(
        activeLayerCount: 0,
        rootSystemCount: 0,
        childSystemCount: 0,
        rootParticleCount: 0,
        childParticleCount: 0
    )
}

struct SceneParticlePlaybackTeardownObservation: Equatable, Sendable {
    let lifecycleIdentity: UUID
    let reason: String
    let snapshotBeforeTeardown: SceneParticleRuntimeLifecycleSnapshot
    let batchCountBeforeTeardown: Int
}

extension SceneParticleRuntime {
    struct FrameSnapshot {
        struct LayerSnapshot {
            struct RootSnapshot {
                let simulator: SceneParticleSimulator
                let simulatorFrame: SceneParticleSimulator.FrameSnapshot
                let instances: [SceneParticleGPUInstance]
                let ropeTrailHistory: SceneParticleRopeTrailHistory?
            }

            let root: RootSnapshot?
            let child: SceneParticleChildRuntime.FrameSnapshot?
            let wasVisible: Bool?
        }

        let layers: [LayerSnapshot]
#if DEBUG
        var pendingAudioEvaluationObservations:
            [SceneParticleRuntimeAudioEvaluationObservation] = []
#endif
        /// World-space freeze/adopt bookkeeping enters the same
        /// transaction as the simulation values: a discarded frame rolls
        /// the freeze back with the particles, and a replayed frame
        /// re-derives it from the same inputs.
        let frozenWorldSpaceLayerIDs: Set<Int>
        let adoptedWorldSpaceLayerIDs: Set<Int>
    }
}
