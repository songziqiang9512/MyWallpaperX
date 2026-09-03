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

    func initializeIfNeeded(
        input: SceneDynamicValue,
        frame: SceneScriptFrameInput,
        scriptPropertiesJSON: String,
        userPropertiesJSON: String,
        expectedGeneration: UInt64,
        interruptBudget: UInt64?
    ) -> Result<SceneScriptVectorEvaluation?, SceneScriptScalarRuntimeFailure> {
        guard input.valueType == valueType, input.isFinite else {
            return .failure(.invalidArgument("invalid typed initialization input"))
        }
        guard expectedGeneration == generation else { return .failure(.staleOwner) }
        let scriptInput = sceneScriptInput(input)
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        var frameInput = frame.quickJSValue
        var didInitialize: UInt32 = 0
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result: MWXSceneQuickJSResult
        let publishedValue: SceneDynamicValue
        switch scriptInput {
        case let .bool(value):
            var output = 0.0
            result = scriptPropertiesJSON.withCString { properties in
                userPropertiesJSON.withCString { userProperties in
                    mwx_scene_quickjs_owner_initialize_primitive_with_properties(
                        handle, expectedGeneration, value ? 1 : 0, 1,
                        &frameInput, properties, scriptPropertiesJSON.utf8.count,
                        userProperties, userPropertiesJSON.utf8.count,
                        &output, &didInitialize, &diagnostic, diagnostic.count
                    )
                }
            }
            publishedValue = .bool(output != 0)
        case .vector2, .vector3:
            let source: [Double]
            switch scriptInput {
            case let .vector2(x, y): source = [x, y, 0]
            case let .vector3(x, y, z): source = [x, y, z]
            default: preconditionFailure("typed initialization input changed")
            }
            var output = [Double](repeating: 0, count: 3)
            result = source.withUnsafeBufferPointer { sourceBuffer in
                output.withUnsafeMutableBufferPointer { outputBuffer in
                    scriptPropertiesJSON.withCString { properties in
                        userPropertiesJSON.withCString { userProperties in
                            mwx_scene_quickjs_owner_initialize_vec3(
                                handle, expectedGeneration, sourceBuffer.baseAddress,
                                &frameInput,
                                properties, scriptPropertiesJSON.utf8.count,
                                userProperties, userPropertiesJSON.utf8.count,
                                outputBuffer.baseAddress, &didInitialize,
                                &diagnostic, diagnostic.count
                            )
                        }
                    }
                }
            }
            guard output.allSatisfy(\.isFinite) else {
                return .failure(.badReturn("invalid initialized Vec3 output"))
            }
            publishedValue = runtimeValue(
                valueType == .vector2
                    ? .vector2(output[0], output[1])
                    : .vector3(output[0], output[1], output[2])
            )
        default:
            return .failure(.invalidArgument("invalid typed initialization input"))
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            return .failure(Self.failure(result, diagnostic))
        }
        guard didInitialize != 0 else { return .success(nil) }
        guard let layerID = SceneScriptLayerMutationBridge.layerID(for: target) else {
            return .failure(.invalidArgument("effect handle layer identity unavailable"))
        }
        let callbackMutations: SceneScriptMediaEventMutations
        switch SceneScriptMediaEventBridge.mutations(
            owner: handle, target: target, layerID: layerID
        ) {
        case let .success(value): callbackMutations = value
        case let .failure(failure): return .failure(failure)
        }
        return validatedEvaluation(
            value: publishedValue,
            mutations: callbackMutations,
            layerID: layerID
        ).map(Optional.some)
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
        let scriptInput = sceneScriptInput(input)
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        var frameInput = frame.quickJSValue
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result: MWXSceneQuickJSResult
        let publishedValue: SceneDynamicValue
        switch scriptInput {
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
            switch scriptInput {
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
            publishedValue = runtimeValue(
                valueType == .vector2
                    ? .vector2(output[0], output[1])
                    : .vector3(output[0], output[1], output[2])
            )
        default:
            return .failure(.invalidArgument("invalid typed SceneScript input"))
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            return .failure(Self.failure(result, diagnostic))
        }
        guard let layerID = SceneScriptLayerMutationBridge.layerID(for: target) else {
            return .failure(.invalidArgument("effect handle layer identity unavailable"))
        }
        let callbackMutations: SceneScriptMediaEventMutations
        switch SceneScriptMediaEventBridge.mutations(
            owner: handle, target: target, layerID: layerID
        ) {
        case let .success(value): callbackMutations = value
        case let .failure(failure): return .failure(failure)
        }
        return validatedEvaluation(
            value: publishedValue,
            mutations: callbackMutations,
            layerID: layerID
        )
    }

    private func validatedEvaluation(
        value publishedValue: SceneDynamicValue,
        mutations: SceneScriptMediaEventMutations,
        layerID: Int
    ) -> Result<SceneScriptVectorEvaluation, SceneScriptScalarRuntimeFailure> {
        let publishedLayerMutations: [SceneScriptLayerMutation]
        if valueType == .bool {
            guard mutations.materialFunctions.isEmpty,
                  mutations.animations.isEmpty else {
                return .failure(.invalidArgument(
                    "Boolean value owner produced out-of-cohort mutations"
                ))
            }
            if allowsDynamicLayerSideEffects {
                var resolved: [SceneScriptLayerMutation] = []
                resolved.reserveCapacity(mutations.layers.count)
                for mutation in mutations.layers {
                    if !mutation.isDynamic {
                        guard mutation.kind == .upsert,
                              !mutation.fields.isEmpty,
                              mutation.fields.isSubset(of: .authoredFields) else {
                            return .failure(.invalidArgument(
                                "Boolean dynamic-layer owner produced an invalid authored mutation"
                            ))
                        }
                        if mutation.layerID != layerID {
                            resolved.append(mutation)
                            continue
                        }
                        guard !mutation.fields.contains(.visibility)
                                || mutation.visible == publishedValue.boolValue else {
                            return .failure(.invalidArgument(
                                "Boolean dynamic-layer owner visibility disagrees with its value"
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
                guard mutations.layers.allSatisfy({ mutation in
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
            publishedLayerMutations = mutations.layers
        }
        return .success(.init(
            value: publishedValue,
            materialFunctionMutations: mutations.materialFunctions,
            animationMutations: mutations.animations,
            layerMutations: publishedLayerMutations,
            videoCommands: mutations.videoCommands
        ))
    }

    private func sceneScriptInput(
        _ value: SceneDynamicValue
    ) -> SceneDynamicValue {
        guard case .layer(_, .angles) = target,
              case let .vector3(x, y, z) = value else { return value }
        return .vector3(
            SceneScriptAngleUnits.degrees(fromRadians: x),
            SceneScriptAngleUnits.degrees(fromRadians: y),
            SceneScriptAngleUnits.degrees(fromRadians: z)
        )
    }

    private func runtimeValue(
        _ value: SceneDynamicValue
    ) -> SceneDynamicValue {
        guard case .layer(_, .angles) = target,
              case let .vector3(x, y, z) = value else { return value }
        return .vector3(
            SceneScriptAngleUnits.radians(fromDegrees: x),
            SceneScriptAngleUnits.radians(fromDegrees: y),
            SceneScriptAngleUnits.radians(fromDegrees: z)
        )
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
        authoredLayerBaselines: [SceneScriptLayerMutation] = [],
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        guard case let .layer(layerID, _) = target,
              layerID == event.layerID else {
            return .failure(.invalidArgument("cursor owner identity mismatch"))
        }
        if let failure = configureCursorAuthoredLayerBaselines(
            authoredLayerBaselines
        ) {
            return .failure(failure)
        }
        defer { clearCursorAuthoredLayerBaselines() }
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

    func clearCursorAuthoredLayerBaselines() {
        mwx_scene_quickjs_owner_clear_authored_layer_baseline(handle)
        mwx_scene_quickjs_owner_clear_authored_layer_mutation_baselines(handle)
    }

    private func configureCursorAuthoredLayerBaselines(
        _ baselines: [SceneScriptLayerMutation]
    ) -> SceneScriptScalarRuntimeFailure? {
        clearCursorAuthoredLayerBaselines()
        guard baselines.count <= 64 else {
            return .mutationOverflow("cursor authored baseline budget exceeded")
        }
        for baseline in baselines {
            guard baseline.kind == .upsert,
                  !baseline.isDynamic,
                  !baseline.fields.isEmpty,
                  baseline.fields.isSubset(of: .authoredFields),
                  baseline.origin.x.isFinite,
                  baseline.origin.y.isFinite,
                  baseline.origin.z.isFinite,
                  baseline.scale.x.isFinite,
                  baseline.scale.y.isFinite,
                  baseline.scale.z.isFinite,
                  baseline.angles.x.isFinite,
                  baseline.angles.y.isFinite,
                  baseline.angles.z.isFinite,
                  baseline.text.utf8.count <= 4_096,
                  !baseline.text.contains("\0"),
                  baseline.font.utf8.count <= 1_024,
                  !baseline.font.contains("\0") else {
                clearCursorAuthoredLayerBaselines()
                return .invalidArgument("invalid cursor authored layer baseline")
            }
            var origin = [
                baseline.origin.x, baseline.origin.y, baseline.origin.z,
            ]
            var scale = [
                baseline.scale.x, baseline.scale.y, baseline.scale.z,
            ]
            var angles = [
                baseline.angles.x, baseline.angles.y, baseline.angles.z,
            ]
            var diagnostic = [CChar](repeating: 0, count: 512)
            let raw = baseline.text.withCString { textPointer in
                baseline.font.withCString { fontPointer in
                    origin.withUnsafeMutableBufferPointer { originPointer in
                        scale.withUnsafeMutableBufferPointer { scalePointer in
                            angles.withUnsafeMutableBufferPointer { anglesPointer in
                                mwx_scene_quickjs_owner_add_authored_layer_mutation_baseline(
                                    handle,
                                    generation,
                                    Int64(baseline.layerID),
                                    baseline.fields.rawValue,
                                    originPointer.baseAddress,
                                    scalePointer.baseAddress,
                                    anglesPointer.baseAddress,
                                    baseline.visible ? 1 : 0,
                                    textPointer,
                                    baseline.text.utf8.count,
                                    fontPointer,
                                    baseline.font.utf8.count,
                                    &diagnostic,
                                    diagnostic.count
                                )
                            }
                        }
                    }
                }
            }
            guard raw == MWX_SCENE_QUICKJS_OK else {
                clearCursorAuthoredLayerBaselines()
                return Self.failure(raw, diagnostic)
            }
        }
        return nil
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
