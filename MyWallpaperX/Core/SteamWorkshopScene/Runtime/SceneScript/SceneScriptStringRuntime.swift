import Foundation

nonisolated struct SceneScriptStringEvaluation: Equatable, Sendable {
    let value: SceneDynamicValue
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
}

/// Owns one string-valued property in the shared per-scene QuickJS domain.
/// The owner publishes only its typed return value and the existing mutation
/// buffers; it does not create a second text state or compositor path.
nonisolated final class SceneScriptStringOwner: @unchecked Sendable {
    let target: SceneDynamicTarget
    let generation: UInt64
    let hasAudioRegistration: Bool
    private let handle: OpaquePointer
    private let domain: SceneScriptQuickJSDomain
    private let budget: SceneScriptScalarBudget

    init(
        domain: SceneScriptQuickJSDomain,
        source: String,
        target: SceneDynamicTarget,
        effectNames: [String?],
        hasCurrentAnimation: Bool = false,
        generation: UInt64,
        budget: SceneScriptScalarBudget = .default
    ) throws {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              generation > 0 else {
            throw SceneScriptScalarRuntimeFailure.invalidSource
        }
        self.domain = domain
        self.target = target
        self.generation = generation
        self.budget = budget
        var diagnostic = [CChar](repeating: 0, count: 512)
        let created = source.withCString {
            mwx_scene_quickjs_owner_create(
                domain.handle,
                $0,
                source.utf8.count,
                generation,
                &diagnostic,
                diagnostic.count
            )
        }
        guard let created else {
            throw Self.failure(MWX_SCENE_QUICKJS_COMPILE_ERROR, diagnostic)
        }
        do {
            try SceneScriptLayerMutationBridge.configure(owner: created, target: target)
            var updateAvailable: UInt32 = 0
            let updateResult = "update".withCString {
                mwx_scene_quickjs_owner_has_function(
                    created,
                    $0,
                    "update".utf8.count,
                    &updateAvailable,
                    &diagnostic,
                    diagnostic.count
                )
            }
            guard updateResult == MWX_SCENE_QUICKJS_OK,
                  updateAvailable == 1 else {
                throw updateResult == MWX_SCENE_QUICKJS_OK
                    ? SceneScriptScalarRuntimeFailure.invalidSource
                    : Self.failure(updateResult, diagnostic)
            }
            try SceneScriptEffectHandleBridge.configure(
                owner: created,
                effectNames: effectNames
            )
            try SceneScriptAnimationHandleBridge.configure(
                owner: created,
                hasCurrentAnimation: hasCurrentAnimation
            )
        } catch {
            mwx_scene_quickjs_owner_destroy(created)
            throw error
        }
        handle = created
        hasAudioRegistration = SceneScriptAudioHost.hasRegistration(owner: created)
    }

    deinit { mwx_scene_quickjs_owner_destroy(handle) }

    func refreshAudio(
        _ snapshot: SceneAudioSpectrumSnapshot
    ) -> Result<Void, SceneScriptScalarRuntimeFailure> {
        SceneScriptAudioHost.refresh(
            owner: handle,
            ownerGeneration: generation,
            snapshot: snapshot
        )
    }

    func evaluate(
        input: String,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        expectedGeneration: UInt64,
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptStringEvaluation, SceneScriptScalarRuntimeFailure> {
        guard input.utf8.count <= 65_536, !input.contains("\0") else {
            return .failure(.invalidArgument("invalid string input"))
        }
        guard expectedGeneration == generation else { return .failure(.staleOwner) }
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        var rawFrame = MWXSceneQuickJSFrameInput(
            time_of_day: frame.timeOfDay,
            frame_time: frame.frameTime,
            runtime: frame.runtime
        )
        var output = [CChar](repeating: 0, count: 65_537)
        var outputLength = 0
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = input.withCString { inputPointer in
            userPropertiesJSON.withCString { userProperties in
                mwx_scene_quickjs_owner_update_string(
                    handle,
                    expectedGeneration,
                    inputPointer,
                    input.utf8.count,
                    &rawFrame,
                    userProperties,
                    userPropertiesJSON.utf8.count,
                    &output,
                    output.count,
                    &outputLength,
                    &diagnostic,
                    diagnostic.count
                )
            }
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            return .failure(Self.failure(result, diagnostic))
        }
        guard outputLength <= 65_536 else {
            return .failure(.badReturn("oversized string output"))
        }
        let value = String(decoding: output.prefix(outputLength).map {
            UInt8(bitPattern: $0)
        }, as: UTF8.self)
        let layerID: Int
        switch target {
        case let .text(value, _), let .layer(value, _): layerID = value
        default:
            return .failure(.invalidArgument("SceneScript owner identity unavailable"))
        }
        let materialFunctions: [SceneScriptMaterialFunctionMutation]
        switch SceneScriptEffectHandleBridge.mutations(owner: handle, layerID: layerID) {
        case let .success(value): materialFunctions = value
        case let .failure(failure): return .failure(failure)
        }
        let animations: [SceneTimelinePlaybackMutation]
        switch SceneScriptAnimationHandleBridge.mutations(owner: handle, target: target) {
        case let .success(value): animations = value
        case let .failure(failure): return .failure(failure)
        }
        let layerMutations: [SceneScriptLayerMutation]
        switch SceneScriptLayerMutationBridge.mutations(owner: handle) {
        case let .success(value): layerMutations = value
        case let .failure(failure): return .failure(failure)
        }
        return .success(.init(
            value: .string(value),
            materialFunctionMutations: materialFunctions,
            animationMutations: animations,
            layerMutations: layerMutations
        ))
    }

    func dispatchMediaThumbnail(
        _ event: SceneScriptMediaThumbnailEventInput,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        dispatch(
            event: { owner, layerID in
                SceneScriptMediaEventBridge.dispatchThumbnail(
                    owner: owner, target: target, layerID: layerID,
                    ownerGeneration: generation, event: event, frame: frame,
                    userPropertiesJSON: userPropertiesJSON
                )
            },
            interruptBudget: interruptBudget
        )
    }

    func dispatchMediaPlayback(
        _ event: SceneScriptMediaPlaybackEventInput,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        dispatch(
            event: { owner, layerID in
                SceneScriptMediaEventBridge.dispatchPlayback(
                    owner: owner, target: target, layerID: layerID,
                    ownerGeneration: generation, event: event, frame: frame,
                    userPropertiesJSON: userPropertiesJSON
                )
            },
            interruptBudget: interruptBudget
        )
    }

    func dispatchMediaProperties(
        _ event: SceneScriptMediaPropertiesEventInput,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        dispatch(
            event: { owner, layerID in
                SceneScriptMediaEventBridge.dispatchProperties(
                    owner: owner, target: target, layerID: layerID,
                    ownerGeneration: generation, event: event, frame: frame,
                    userPropertiesJSON: userPropertiesJSON
                )
            },
            interruptBudget: interruptBudget
        )
    }

    func invalidate() { mwx_scene_quickjs_owner_invalidate(handle) }

    func teardown(
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String
    ) -> SceneScriptOwnerTeardownOutcome {
        domain.resetBudget(budget.interruptBudget)
        return SceneScriptOwnerLifecycleBridge.teardown(
            owner: handle,
            generation: generation,
            frame: frame,
            scriptPropertiesJSON: "",
            userPropertiesJSON: userPropertiesJSON
        )
    }

    private func dispatch(
        event: (OpaquePointer, Int) -> Result<
            SceneScriptMediaEventMutations,
            SceneScriptScalarRuntimeFailure
        >,
        interruptBudget: UInt64?
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        guard case let .text(layerID, _) = target else {
            return .failure(.invalidArgument("SceneScript text owner unavailable"))
        }
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        return event(handle, layerID)
    }

    private static func failure(
        _ raw: MWXSceneQuickJSResult,
        _ buffer: [CChar]
    ) -> SceneScriptScalarRuntimeFailure {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let diagnostic = String(decoding: bytes, as: UTF8.self)
        return switch raw {
        case MWX_SCENE_QUICKJS_COMPILE_ERROR: .compile(diagnostic)
        case MWX_SCENE_QUICKJS_EXCEPTION: .exception(diagnostic)
        case MWX_SCENE_QUICKJS_BUDGET_EXCEEDED: .budgetExceeded(diagnostic)
        case MWX_SCENE_QUICKJS_MEMORY_EXCEEDED: .memoryExceeded(diagnostic)
        case MWX_SCENE_QUICKJS_BAD_RETURN: .badReturn(diagnostic)
        case MWX_SCENE_QUICKJS_DISABLED: .disabled(diagnostic)
        case MWX_SCENE_QUICKJS_STALE_OWNER: .staleOwner
        case MWX_SCENE_QUICKJS_MUTATION_OVERFLOW: .mutationOverflow(diagnostic)
        default: .invalidArgument(diagnostic)
        }
    }
}
