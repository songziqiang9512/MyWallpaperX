import Foundation

nonisolated struct SceneScriptCursorHit: Equatable, Sendable {
    let layerID: Int
    let worldPosition: SIMD3<Double>
    let localPosition: SIMD3<Double>
}

nonisolated struct SceneScriptCursorFrameSample: Equatable, Sendable {
    let hits: [Int: SceneScriptCursorHit]
    let ownerProjections: [Int: SceneScriptCursorHit]
    let pointerPosition: SIMD2<Float>?
    let primaryButtonIsDown: Bool
    let surface: SceneScriptSurfaceInput?
    let surfaceID: UInt32?
    let leavingSurface: SceneScriptSurfaceInput?

    init(
        hits: [Int: SceneScriptCursorHit],
        ownerProjections: [Int: SceneScriptCursorHit]? = nil,
        pointerPosition: SIMD2<Float>? = nil,
        primaryButtonIsDown: Bool,
        surface: SceneScriptSurfaceInput? = nil,
        surfaceID: UInt32? = nil,
        leavingSurface: SceneScriptSurfaceInput? = nil
    ) {
        self.hits = hits
        self.ownerProjections = ownerProjections ?? hits
        self.pointerPosition = pointerPosition
        self.primaryButtonIsDown = primaryButtonIsDown
        self.surface = surface
        self.surfaceID = surfaceID
        self.leavingSurface = leavingSurface
    }
}

nonisolated struct SceneScriptCursorFrameBatch: Equatable, Sendable {
    let samples: [SceneScriptCursorFrameSample]
    let overflowed: Bool
}

nonisolated struct SceneScriptCursorFrameResult: Equatable, Sendable {
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
    let inputBatchOverflowed: Bool
    let ownerEffects: [SceneScriptOwnerEffects]

    init(
        failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure],
        materialFunctionMutations: [SceneScriptMaterialFunctionMutation],
        animationMutations: [SceneTimelinePlaybackMutation],
        layerMutations: [SceneScriptLayerMutation],
        inputBatchOverflowed: Bool,
        ownerEffects: [SceneScriptOwnerEffects] = []
    ) {
        self.failures = failures
        self.materialFunctionMutations = materialFunctionMutations
        self.animationMutations = animationMutations
        self.layerMutations = layerMutations
        self.inputBatchOverflowed = inputBatchOverflowed
        self.ownerEffects = ownerEffects
    }
}

nonisolated struct SceneScriptCursorProgramConstruction: @unchecked Sendable {
    let program: SceneScriptCursorProgram
    let requestedTargets: Set<SceneDynamicTarget>
    let instantiatedTargets: Set<SceneDynamicTarget>
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    // Identity preflight rejection executes no failed JavaScript. Only an
    // attempted owner failure can contaminate the shared construction domain.
    var requiresDomainReconstruction: Bool = false

    var deferredTargets: Set<SceneDynamicTarget> {
        requestedTargets.subtracting(instantiatedTargets).subtracting(failures.keys)
    }
}

/// Frame-visible cursor edge state. Dispatch advances this state before the
/// surface outcome is known; a deferred/dropped frame must restore it so the
/// next successful frame still sees enter/leave, press/release and click
/// edges for every event it re-dispatches.
nonisolated struct SceneScriptCursorEdgeState: Sendable {
    var previousHits: [Int: SceneScriptCursorHit]
    var capturedHits: [Int: SceneScriptCursorHit]
    var previousPointerPosition: SIMD2<Float>?
    var previousPrimaryButtonIsDown: Bool
    var pendingEvents: [SceneScriptCursorPendingEvent]
    var capturedSurfaceID: UInt32? = nil
    var previousSurfaceID: UInt32? = nil
    var previousSurface: SceneScriptSurfaceInput? = nil

    static let empty = SceneScriptCursorEdgeState(
        previousHits: [:],
        capturedHits: [:],
        previousPointerPosition: nil,
        previousPrimaryButtonIsDown: false,
        pendingEvents: []
    )
}

/// Resolved physical input awaiting this target's publication. Retaining the
/// event preserves a down/up pair even when the latest pointer is stationary.
nonisolated struct SceneScriptCursorPendingEvent: Sendable {
    let ownerTarget: SceneDynamicTarget
    let kind: SceneScriptCursorEventKind
    let hit: SceneScriptCursorHit
    let surface: SceneScriptSurfaceInput?
    let captureActive: Bool
    let currentHit: Bool
}

nonisolated struct SceneScriptCursorBinding: @unchecked Sendable {
    let layerID: Int
    let authoredOrdinal: Int
    let owner: SceneScriptVectorOwner
    let events: Set<SceneScriptCursorEventKind>
    let ownsOwner: Bool
    let scriptProperties: [String: SceneScriptPropertyInput]
    /// Authored initial value of the owner's own target. A borrowed owner is
    /// initialized from here when a cursor callback reaches it before the
    /// frame evaluation did. A standalone cursor-only owner has no value
    /// route, so it carries no seed and is constructed fail-closed when it
    /// would need one.
    let ownerSeedValue: SceneDynamicValue?

    var ownerTarget: SceneDynamicTarget { owner.target }
}

nonisolated struct SceneScriptCursorAuthoredMutationKey: Hashable {
    let ownerTarget: SceneDynamicTarget
    let targetLayerID: Int
}
