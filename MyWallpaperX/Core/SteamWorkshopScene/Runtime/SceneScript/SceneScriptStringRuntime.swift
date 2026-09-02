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
    let handlesMediaThumbnail: Bool
    let handlesMediaPlayback: Bool
    let handlesMediaProperties: Bool
    let handlesMediaTimeline: Bool
    private let handle: OpaquePointer
    private let domain: SceneScriptQuickJSDomain
    private let budget: SceneScriptScalarBudget
    private let initialScriptPropertiesJSON: String

    init(
        domain: SceneScriptQuickJSDomain,
        source: String,
        target: SceneDynamicTarget,
        scriptPropertiesJSON: String = "",
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
        initialScriptPropertiesJSON = scriptPropertiesJSON
        try domain.checkConstructionBoundary()
        var diagnostic = [CChar](repeating: 0, count: 512)
        var creationResult = MWX_SCENE_QUICKJS_INVALID_ARGUMENT
        let created = source.withCString {
            mwx_scene_quickjs_owner_create_with_budget(
                domain.handle,
                $0,
                source.utf8.count,
                generation,
                budget.interruptBudget,
                &creationResult,
                &diagnostic,
                diagnostic.count
            )
        }
        do {
            try domain.checkConstructionBoundary()
        } catch {
            if let created { mwx_scene_quickjs_owner_destroy(created) }
            throw error
        }
        guard let created else {
            throw Self.failure(creationResult, diagnostic)
        }
        var handlesMediaThumbnail = false
        var handlesMediaPlayback = false
        var handlesMediaProperties = false
        var handlesMediaTimeline = false
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
            handlesMediaThumbnail = try SceneScriptOwnerExportBridge.contains(
                "mediaThumbnailChanged", owner: created
            )
            handlesMediaPlayback = try SceneScriptOwnerExportBridge.contains(
                "mediaPlaybackChanged", owner: created
            )
            handlesMediaProperties = try SceneScriptOwnerExportBridge.contains(
                "mediaPropertiesChanged", owner: created
            )
            handlesMediaTimeline = try SceneScriptOwnerExportBridge.contains(
                "mediaTimelineChanged", owner: created
            )
        } catch {
            mwx_scene_quickjs_owner_destroy(created)
            throw error
        }
        handle = created
        hasAudioRegistration = SceneScriptAudioHost.hasRegistration(owner: created)
        self.handlesMediaThumbnail = handlesMediaThumbnail
        self.handlesMediaPlayback = handlesMediaPlayback
        self.handlesMediaProperties = handlesMediaProperties
        self.handlesMediaTimeline = handlesMediaTimeline
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

    func initializeIfNeeded(
        input: String,
        frame: SceneScriptFrameInput,
        scriptPropertiesJSON: String = "",
        userPropertiesJSON: String,
        expectedGeneration: UInt64,
        interruptBudget: UInt64?
    ) -> Result<SceneScriptStringEvaluation?, SceneScriptScalarRuntimeFailure> {
        guard input.utf8.count <= 65_536, !input.contains("\0") else {
            return .failure(.invalidArgument("invalid string initialization input"))
        }
        guard expectedGeneration == generation else { return .failure(.staleOwner) }
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        var rawFrame = frame.quickJSValue
        var output = [CChar](repeating: 0, count: 65_537)
        var outputLength = 0
        var didInitialize: UInt32 = 0
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = input.withCString { inputPointer in
            scriptPropertiesJSON.withCString { scriptProperties in
                userPropertiesJSON.withCString { userProperties in
                    mwx_scene_quickjs_owner_initialize_string(
                        handle, expectedGeneration,
                        inputPointer, input.utf8.count, &rawFrame,
                        scriptProperties, scriptPropertiesJSON.utf8.count,
                        userProperties, userPropertiesJSON.utf8.count,
                        &output, output.count, &outputLength, &didInitialize,
                        &diagnostic, diagnostic.count
                    )
                }
            }
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            return .failure(Self.failure(result, diagnostic))
        }
        guard didInitialize != 0 else { return .success(nil) }
        guard outputLength <= 65_536 else {
            return .failure(.badReturn("oversized initialized string output"))
        }
        let value = String(decoding: output.prefix(outputLength).map {
            UInt8(bitPattern: $0)
        }, as: UTF8.self)
        return callbackEvaluation(value).map(Optional.some)
    }

    func evaluate(
        input: String,
        frame: SceneScriptFrameInput,
        scriptPropertiesJSON: String = "",
        userPropertiesJSON: String,
        expectedGeneration: UInt64,
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptStringEvaluation, SceneScriptScalarRuntimeFailure> {
        guard input.utf8.count <= 65_536, !input.contains("\0") else {
            return .failure(.invalidArgument("invalid string input"))
        }
        guard expectedGeneration == generation else { return .failure(.staleOwner) }
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        var rawFrame = frame.quickJSValue
        var output = [CChar](repeating: 0, count: 65_537)
        var outputLength = 0
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = input.withCString { inputPointer in
            scriptPropertiesJSON.withCString { scriptProperties in
                userPropertiesJSON.withCString { userProperties in
                    mwx_scene_quickjs_owner_update_string(
                        handle,
                        expectedGeneration,
                        inputPointer,
                        input.utf8.count,
                        &rawFrame,
                        scriptProperties,
                        scriptPropertiesJSON.utf8.count,
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
        return callbackEvaluation(value)
    }

    private func callbackEvaluation(
        _ value: String
    ) -> Result<SceneScriptStringEvaluation, SceneScriptScalarRuntimeFailure> {
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
        switch SceneScriptLayerMutationBridge.mutations(
            owner: handle, ownerTarget: target
        ) {
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

    func dispatchMediaTimeline(
        _ event: SceneScriptMediaTimelineEventInput,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        dispatch(
            event: { owner, layerID in
                SceneScriptMediaEventBridge.dispatchTimeline(
                    owner: owner, target: target, layerID: layerID,
                    ownerGeneration: generation, event: event, frame: frame,
                    userPropertiesJSON: userPropertiesJSON
                )
            },
            interruptBudget: interruptBudget
        )
    }

    func invalidate() {
        domain.discardStorage(owner: handle)
        mwx_scene_quickjs_owner_invalidate(handle)
    }

    func commitStorage() -> Result<Void, SceneScriptScalarRuntimeFailure> {
        domain.commitStorage(owner: handle)
    }

    func discardStorage() {
        domain.discardStorage(owner: handle)
    }

    func teardown(
        frame: SceneScriptFrameInput,
        scriptPropertiesJSON: String?,
        userPropertiesJSON: String
    ) -> SceneScriptOwnerTeardownOutcome {
        domain.resetBudget(budget.interruptBudget)
        return SceneScriptOwnerLifecycleBridge.teardown(
            owner: handle,
            generation: generation,
            frame: frame,
            scriptPropertiesJSON:
                scriptPropertiesJSON ?? initialScriptPropertiesJSON,
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
