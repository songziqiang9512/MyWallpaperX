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

    init(
        hits: [Int: SceneScriptCursorHit],
        ownerProjections: [Int: SceneScriptCursorHit]? = nil,
        pointerPosition: SIMD2<Float>? = nil,
        primaryButtonIsDown: Bool,
        surface: SceneScriptSurfaceInput? = nil
    ) {
        self.hits = hits
        self.ownerProjections = ownerProjections ?? hits
        self.pointerPosition = pointerPosition
        self.primaryButtonIsDown = primaryButtonIsDown
        self.surface = surface
    }
}

nonisolated struct SceneScriptCursorFrameBatch: Equatable, Sendable {
    let samples: [SceneScriptCursorFrameSample]
    let overflowed: Bool
}

nonisolated struct SceneScriptCursorFrameResult: Equatable, Sendable {
    let failures: [Int: SceneScriptScalarRuntimeFailure]
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
    let inputBatchOverflowed: Bool
    let ownerEffects: [SceneScriptOwnerEffects]

    init(
        failures: [Int: SceneScriptScalarRuntimeFailure],
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
    let requestedLayerIDs: Set<Int>
    let instantiatedLayerIDs: Set<Int>
    let failures: [Int: SceneScriptScalarRuntimeFailure]
    // Identity preflight rejection executes no failed JavaScript. Only an
    // attempted owner failure can contaminate the shared construction domain.
    var requiresDomainReconstruction: Bool = false

    var deferredLayerIDs: Set<Int> {
        requestedLayerIDs.subtracting(instantiatedLayerIDs).subtracting(failures.keys)
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

    static let empty = SceneScriptCursorEdgeState(
        previousHits: [:],
        capturedHits: [:],
        previousPointerPosition: nil,
        previousPrimaryButtonIsDown: false
    )
}

nonisolated struct SceneScriptCursorBinding: @unchecked Sendable {
    let layerID: Int
    let authoredOrder: Int
    let owner: SceneScriptVectorOwner
    let events: Set<SceneScriptCursorEventKind>
    let ownsOwner: Bool
    let scriptProperties: [String: SceneScriptPropertyInput]
}

nonisolated struct SceneScriptCursorAuthoredMutationKey: Hashable {
    let ownerLayerID: Int
    let targetLayerID: Int
}
