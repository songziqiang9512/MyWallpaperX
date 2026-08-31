import Foundation

nonisolated struct SceneScriptVectorEvaluation: Equatable, Sendable {
    let value: SceneDynamicValue
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
    let videoCommands: [SceneScriptVideoCommand]
}

nonisolated final class SceneScriptVectorOwner: @unchecked Sendable {
    let target: SceneDynamicTarget
    let generation: UInt64
    let hasAudioRegistration: Bool
    let handlesMediaThumbnail: Bool
    let handlesMediaPlayback: Bool
    let handlesMediaProperties: Bool
    let handlesMediaTimeline: Bool
    let exportedCursorEvents: Set<SceneScriptCursorEventKind>
    private let handle: OpaquePointer
    private let domain: SceneScriptQuickJSDomain
    private let budget: SceneScriptScalarBudget
    private let valueType: SceneDynamicValueType
    private let dynamicImagePathsByAuthoredIdentity: [String: String]

    var allowsDynamicLayerSideEffects: Bool {
        !dynamicImagePathsByAuthoredIdentity.isEmpty
    }

    init(
        domain: SceneScriptQuickJSDomain,
        source: String,
        target: SceneDynamicTarget,
        valueType: SceneDynamicValueType = .vector3,
        effectNames: [String?],
        hasCurrentAnimation: Bool = false,
        dynamicImagePathsByAuthoredIdentity: [String: String] = [:],
        generation: UInt64,
        budget: SceneScriptScalarBudget
    ) throws {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              [.bool, .vector2, .vector3].contains(valueType),
              generation > 0 else { throw SceneScriptScalarRuntimeFailure.invalidSource }
        self.domain = domain
        self.target = target
        self.generation = generation
        self.budget = budget
        self.valueType = valueType
        self.dynamicImagePathsByAuthoredIdentity =
            dynamicImagePathsByAuthoredIdentity
        try domain.checkConstructionBoundary()
        var diagnostic = [CChar](repeating: 0, count: 512)
        var creationResult = MWX_SCENE_QUICKJS_INVALID_ARGUMENT
        let created = source.withCString {
            if valueType == .bool && !dynamicImagePathsByAuthoredIdentity.isEmpty {
                mwx_scene_quickjs_owner_create_effectful_bool_with_budget(
                    domain.handle, $0, source.utf8.count, generation,
                    budget.interruptBudget, &creationResult,
                    &diagnostic, diagnostic.count
                )
            } else if valueType == .bool {
                mwx_scene_quickjs_owner_create_value_only_with_budget(
                    domain.handle, $0, source.utf8.count, generation,
                    budget.interruptBudget, &creationResult,
                    &diagnostic, diagnostic.count
                )
            } else {
                mwx_scene_quickjs_owner_create_with_budget(
                    domain.handle, $0, source.utf8.count, generation,
                    budget.interruptBudget, &creationResult,
                    &diagnostic, diagnostic.count
                )
            }
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
        var exportedCursorEvents: Set<SceneScriptCursorEventKind> = []
        var ownerHasAudioRegistration = false
        do {
            guard let layerID = SceneScriptLayerMutationBridge.layerID(for: target) else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    "SceneScript owner layer identity unavailable"
                )
            }
            let layerResult = mwx_scene_quickjs_owner_configure_layer_identity(
                created,
                Int64(layerID),
                &diagnostic,
                diagnostic.count
            )
            guard layerResult == MWX_SCENE_QUICKJS_OK else {
                throw Self.failure(layerResult, diagnostic)
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
            for event in SceneScriptCursorEventKind.allCases {
                if try SceneScriptOwnerExportBridge.contains(
                    event.callbackName, owner: created
                ) {
                    exportedCursorEvents.insert(event)
                }
            }
            ownerHasAudioRegistration = SceneScriptAudioHost.hasRegistration(
                owner: created
            )
            if valueType == .bool {
                let hasValueHook = try SceneScriptOwnerExportBridge.contains(
                    "init", owner: created
                ) || SceneScriptOwnerExportBridge.contains("update", owner: created)
                let handlesDestroy = try SceneScriptOwnerExportBridge.contains(
                    "destroy", owner: created
                )
                guard hasValueHook, !handlesDestroy,
                      !handlesMediaThumbnail, !handlesMediaPlayback,
                      !handlesMediaProperties, !handlesMediaTimeline,
                      exportedCursorEvents.isEmpty,
                      (dynamicImagePathsByAuthoredIdentity.isEmpty
                        ? !ownerHasAudioRegistration
                        : true) else {
                    throw SceneScriptScalarRuntimeFailure.invalidSource
                }
            }
        } catch {
            mwx_scene_quickjs_owner_destroy(created)
            throw error
        }
        handle = created
        hasAudioRegistration = ownerHasAudioRegistration
        self.handlesMediaThumbnail = handlesMediaThumbnail
        self.handlesMediaPlayback = handlesMediaPlayback
        self.handlesMediaProperties = handlesMediaProperties
        self.handlesMediaTimeline = handlesMediaTimeline
        self.exportedCursorEvents = exportedCursorEvents
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
        input: SceneDynamicValue,
        frame: SceneScriptFrameInput,
        scriptPropertiesJSON: String,
        userPropertiesJSON: String,
        expectedGeneration: UInt64,
        interruptBudget: UInt64?
    ) -> Result<SceneScriptVectorEvaluation, SceneScriptScalarRuntimeFailure> {
        guard input.valueType == valueType, input.isFinite else {
            return .failure(.invalidArgument("invalid typed vector input"))
        }
        guard expectedGeneration == generation else { return .failure(.staleOwner) }
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        var frameInput = frame.quickJSValue
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result: MWXSceneQuickJSResult
        let publishedValue: SceneDynamicValue
        switch input {
        case let .bool(value):
            var output: UInt32 = 0
            result = scriptPropertiesJSON.withCString { properties in
                userPropertiesJSON.withCString { userProperties in
                    if allowsDynamicLayerSideEffects {
                        mwx_scene_quickjs_owner_update_effectful_bool_with_properties(
                            handle, expectedGeneration, value ? 1 : 0, &frameInput,
                            properties, scriptPropertiesJSON.utf8.count,
                            userProperties, userPropertiesJSON.utf8.count,
                            &output, &diagnostic, diagnostic.count
                        )
                    } else {
                        mwx_scene_quickjs_owner_update_bool_with_properties(
                            handle, expectedGeneration, value ? 1 : 0, &frameInput,
                            properties, scriptPropertiesJSON.utf8.count,
                            userProperties, userPropertiesJSON.utf8.count,
                            &output, &diagnostic, diagnostic.count
                        )
                    }
                }
            }
            publishedValue = .bool(output != 0)
        case .vector2, .vector3:
            let source: [Double]
            switch input {
            case let .vector2(x, y): source = [x, y, 0]
            case let .vector3(x, y, z): source = [x, y, z]
            default: preconditionFailure("typed vector input changed")
            }
            var output = [Double](repeating: 0, count: 3)
            result = source.withUnsafeBufferPointer { sourceBuffer in
                output.withUnsafeMutableBufferPointer { outputBuffer in
                    scriptPropertiesJSON.withCString { properties in
                        userPropertiesJSON.withCString { userProperties in
                            mwx_scene_quickjs_owner_update_vec3(
                                handle, expectedGeneration, sourceBuffer.baseAddress,
                                &frameInput,
                                properties, scriptPropertiesJSON.utf8.count,
                                userProperties, userPropertiesJSON.utf8.count,
                                outputBuffer.baseAddress,
                                &diagnostic, diagnostic.count
                            )
                        }
                    }
                }
            }
            guard output.allSatisfy(\.isFinite) else {
                return .failure(.badReturn("non-finite Vec3 output"))
            }
            publishedValue = valueType == .vector2
                ? .vector2(output[0], output[1])
                : .vector3(output[0], output[1], output[2])
        default:
            return .failure(.invalidArgument("invalid typed SceneScript input"))
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            return .failure(Self.failure(result, diagnostic))
        }
        guard let layerID = SceneScriptLayerMutationBridge.layerID(for: target) else {
            return .failure(.invalidArgument("effect handle layer identity unavailable"))
        }
        let mutations: [SceneScriptMaterialFunctionMutation]
        switch SceneScriptEffectHandleBridge.mutations(
            owner: handle,
            layerID: layerID
        ) {
        case let .success(value): mutations = value
        case let .failure(failure): return .failure(failure)
        }
        let animationMutations: [SceneTimelinePlaybackMutation]
        switch SceneScriptAnimationHandleBridge.mutations(
            owner: handle,
            target: target
        ) {
        case let .success(value): animationMutations = value
        case let .failure(failure): return .failure(failure)
        }
        let layerMutations: [SceneScriptLayerMutation]
        switch SceneScriptLayerMutationBridge.mutations(owner: handle) {
        case let .success(value): layerMutations = value
        case let .failure(failure): return .failure(failure)
        }
        let videoCommands: [SceneScriptVideoCommand]
        switch SceneScriptVideoCommandBridge.commands(owner: handle) {
        case let .success(value): videoCommands = value
        case let .failure(failure): return .failure(failure)
        }
        let publishedLayerMutations: [SceneScriptLayerMutation]
        if valueType == .bool {
            guard mutations.isEmpty, animationMutations.isEmpty else {
                return .failure(.invalidArgument(
                    "Boolean value owner produced out-of-cohort mutations"
                ))
            }
            if allowsDynamicLayerSideEffects {
                var resolved: [SceneScriptLayerMutation] = []
                resolved.reserveCapacity(layerMutations.count)
                for mutation in layerMutations {
                    if !mutation.isDynamic {
                        guard mutation.kind == .upsert,
                              mutation.layerID == layerID,
                              !mutation.fields.isEmpty,
                              mutation.fields.isSubset(of: .authoredFields),
                              !mutation.fields.contains(.visibility)
                                || mutation.visible == publishedValue.boolValue else {
                            return .failure(.invalidArgument(
                                "Boolean dynamic-layer owner mutated an unowned authored field"
                            ))
                        }
                        let transformFields = mutation.fields.subtracting(.visibility)
                        if !transformFields.isEmpty {
                            resolved.append(
                                mutation.selectingAuthoredFields(transformFields)
                            )
                        }
                        continue
                    }
                    guard let assetPath = mutation.assetPath,
                          let modelPath = dynamicImagePathsByAuthoredIdentity[
                            assetPath.lowercased()
                          ] else {
                        return .failure(.invalidArgument(
                            "Boolean dynamic-layer owner requested an unprepared asset"
                        ))
                    }
                    resolved.append(mutation.resolvingAssetPath(to: modelPath))
                }
                publishedLayerMutations = resolved
            } else {
                guard layerMutations.allSatisfy({ mutation in
                    mutation.kind == .upsert && !mutation.isDynamic
                        && mutation.layerID == layerID
                        && mutation.fields == .visibility
                        && mutation.visible == publishedValue.boolValue
                }) else {
                    return .failure(.invalidArgument(
                        "Boolean value owner produced out-of-cohort mutations"
                    ))
                }
                publishedLayerMutations = []
            }
        } else {
            publishedLayerMutations = layerMutations
        }
        return .success(.init(
            value: publishedValue,
            materialFunctionMutations: mutations,
            animationMutations: animationMutations,
            layerMutations: publishedLayerMutations,
            videoCommands: videoCommands
        ))
    }

    func dispatchMediaThumbnail(
        _ event: SceneScriptMediaThumbnailEventInput,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        guard let layerID = SceneScriptLayerMutationBridge.layerID(for: target) else {
            return .failure(.invalidArgument("SceneScript owner identity unavailable"))
        }
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        return SceneScriptMediaEventBridge.dispatchThumbnail(
            owner: handle,
            target: target,
            layerID: layerID,
            ownerGeneration: generation,
            event: event,
            frame: frame,
            userPropertiesJSON: userPropertiesJSON
        )
    }

    func dispatchMediaPlayback(
        _ event: SceneScriptMediaPlaybackEventInput,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        guard let layerID = SceneScriptLayerMutationBridge.layerID(for: target) else {
            return .failure(.invalidArgument("SceneScript owner identity unavailable"))
        }
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        return SceneScriptMediaEventBridge.dispatchPlayback(
            owner: handle,
            target: target,
            layerID: layerID,
            ownerGeneration: generation,
            event: event,
            frame: frame,
            userPropertiesJSON: userPropertiesJSON
        )
    }

    func dispatchMediaProperties(
        _ event: SceneScriptMediaPropertiesEventInput,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        guard let layerID = SceneScriptLayerMutationBridge.layerID(for: target) else {
            return .failure(.invalidArgument("SceneScript owner identity unavailable"))
        }
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        return SceneScriptMediaEventBridge.dispatchProperties(
            owner: handle, target: target, layerID: layerID,
            ownerGeneration: generation, event: event, frame: frame,
            userPropertiesJSON: userPropertiesJSON
        )
    }

    func dispatchMediaTimeline(
        _ event: SceneScriptMediaTimelineEventInput,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        guard let layerID = SceneScriptLayerMutationBridge.layerID(for: target) else {
            return .failure(.invalidArgument("SceneScript owner identity unavailable"))
        }
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        return SceneScriptMediaEventBridge.dispatchTimeline(
            owner: handle, target: target, layerID: layerID,
            ownerGeneration: generation, event: event, frame: frame,
            userPropertiesJSON: userPropertiesJSON
        )
    }

    func dispatchUserProperties(
        changedPropertiesJSON: String,
        scriptPropertiesJSON: String,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        guard let layerID = SceneScriptLayerMutationBridge.layerID(for: target) else {
            return .failure(.invalidArgument("SceneScript owner identity unavailable"))
        }
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        return SceneScriptMediaEventBridge.dispatchUserProperties(
            owner: handle,
            target: target,
            layerID: layerID,
            ownerGeneration: generation,
            changedPropertiesJSON: changedPropertiesJSON,
            scriptPropertiesJSON: scriptPropertiesJSON,
            frame: frame,
            userPropertiesJSON: userPropertiesJSON
        )
    }

    func dispatchCursor(
        _ event: SceneScriptCursorEventInput,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        authoredTransformBaseline: SceneScriptLayerMutation? = nil,
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        guard case let .layer(layerID, _) = target,
              layerID == event.layerID else {
            return .failure(.invalidArgument("cursor owner identity mismatch"))
        }
        if let failure = configureCursorAuthoredTransformBaseline(
            authoredTransformBaseline,
            layerID: layerID
        ) {
            return .failure(failure)
        }
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        return SceneScriptMediaEventBridge.dispatchCursor(
            owner: handle,
            target: target,
            ownerGeneration: generation,
            event: event,
            frame: frame,
            userPropertiesJSON: userPropertiesJSON
        )
    }

    func clearCursorAuthoredTransformBaseline() {
        mwx_scene_quickjs_owner_clear_authored_layer_baseline(handle)
    }

    private func configureCursorAuthoredTransformBaseline(
        _ baseline: SceneScriptLayerMutation?,
        layerID: Int
    ) -> SceneScriptScalarRuntimeFailure? {
        guard let baseline else {
            clearCursorAuthoredTransformBaseline()
            return nil
        }
        guard baseline.kind == .upsert,
              !baseline.isDynamic,
              baseline.layerID == layerID,
              baseline.origin.x.isFinite,
              baseline.origin.y.isFinite,
              baseline.origin.z.isFinite,
              baseline.scale.x.isFinite,
              baseline.scale.y.isFinite,
              baseline.scale.z.isFinite,
              baseline.angles.x.isFinite,
              baseline.angles.y.isFinite,
              baseline.angles.z.isFinite else {
            return .invalidArgument("invalid cursor authored transform baseline")
        }
        var origin = [baseline.origin.x, baseline.origin.y, baseline.origin.z]
        var scale = [baseline.scale.x, baseline.scale.y, baseline.scale.z]
        var angles = [baseline.angles.x, baseline.angles.y, baseline.angles.z]
        var diagnostic = [CChar](repeating: 0, count: 512)
        let raw = origin.withUnsafeMutableBufferPointer { originPointer in
            scale.withUnsafeMutableBufferPointer { scalePointer in
                angles.withUnsafeMutableBufferPointer { anglesPointer in
                    mwx_scene_quickjs_owner_set_authored_layer_baseline(
                        handle,
                        generation,
                        originPointer.baseAddress,
                        scalePointer.baseAddress,
                        anglesPointer.baseAddress,
                        &diagnostic,
                        diagnostic.count
                    )
                }
            }
        }
        guard raw == MWX_SCENE_QUICKJS_OK else {
            return Self.failure(raw, diagnostic)
        }
        return nil
    }

    func invalidate() { mwx_scene_quickjs_owner_invalidate(handle) }

    func teardown(
        frame: SceneScriptFrameInput,
        scriptPropertiesJSON: String,
        userPropertiesJSON: String
    ) -> SceneScriptOwnerTeardownOutcome {
        domain.resetBudget(budget.interruptBudget)
        return SceneScriptOwnerLifecycleBridge.teardown(
            owner: handle,
            generation: generation,
            frame: frame,
            scriptPropertiesJSON: scriptPropertiesJSON,
            userPropertiesJSON: userPropertiesJSON
        )
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

private nonisolated extension SceneDynamicValue {
    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }
}
