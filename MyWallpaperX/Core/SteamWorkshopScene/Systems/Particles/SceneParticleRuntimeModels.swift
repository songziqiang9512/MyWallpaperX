import Foundation
import simd

#if DEBUG
struct SceneParticleRuntimeComponentObservation: Sendable {
    let layerID: Int
    let particlePath: String
    let evaluation: SceneParticleComponentObservation
    var childTemplateIndex: Int? = nil
    var childSystemID: UInt64? = nil
    var childParticlePath: String? = nil
}

struct SceneParticleRuntimeComponentObservationIdentity: Hashable {
    let layerID: Int
    let particlePath: String
    let childTemplateIndex: Int?
    let fact: SceneParticleComponentObservationState.Identity

    init(_ observation: SceneParticleRuntimeComponentObservation) {
        layerID = observation.layerID
        particlePath = observation.particlePath
        childTemplateIndex = observation.childTemplateIndex
        let value = observation.evaluation
        fact = .init(category: value.category, componentIndex: value.componentIndex,
                     stage: value.stage, reason: value.reason, origin: value.origin)
    }
}

extension SceneParticleRuntime {
    func collectEvaluationObservations(layerID: Int, particlePath: String,
                                       simulator: SceneParticleSimulator) {
        pendingAudioEvaluationObservations.append(contentsOf:
            simulator.consumeAudioEvaluationObservations().map {
                .init(layerID: layerID, particlePath: particlePath, evaluation: $0)
            })
        guard pendingComponentObservations != nil else { return }
        pendingComponentObservations?.append(contentsOf:
            simulator.consumeComponentObservations().map {
                .init(layerID: layerID, particlePath: particlePath, evaluation: $0)
            })
    }

    func collectEvaluationObservations(layerID: Int, childRuntime: SceneParticleChildRuntime) {
        pendingAudioEvaluationObservations.append(contentsOf:
            childRuntime.consumeAudioEvaluationObservations().map {
                .init(layerID: layerID, particlePath: $0.particlePath, evaluation: $0.evaluation)
            })
        guard pendingComponentObservations != nil else { return }
        childRuntime.appendComponentObservations(to: &pendingComponentObservations)
    }

    func consumeComponentObservations() -> [SceneParticleRuntimeComponentObservation] {
        guard pendingComponentObservations != nil else { return [] }
        defer { pendingComponentObservations?.removeAll(keepingCapacity: true) }
        return pendingComponentObservations ?? []
    }
}

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
}

struct SceneParticleRuntimeDiagnostic: Codable, Equatable, Hashable, Sendable {
    let kind: SceneParticleRuntimeDiagnosticKind
    let layerID: Int?
    let particlePath: String
    let detail: String?
}

#endif

struct SceneParticleLayerImageEmitterCompilation {
    let mapsByLayerID: [Int: SceneParticleLayerImageEmissionMap]
#if DEBUG
    var diagnostics: [SceneParticleRuntimeDiagnostic] = []
#endif

    static let empty = SceneParticleLayerImageEmitterCompilation(
        mapsByLayerID: [:]
    )
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
        var pendingComponentObservations: [SceneParticleRuntimeComponentObservation]? = nil
#endif
        /// World-space freeze/adopt bookkeeping enters the same
        /// transaction as the simulation values: a discarded frame rolls
        /// the freeze back with the particles, and a replayed frame
        /// re-derives it from the same inputs.
        let frozenWorldSpaceLayerIDs: Set<Int>
#if DEBUG
        var adoptedWorldSpaceLayerIDs: Set<Int> = []
#endif
    }
}
