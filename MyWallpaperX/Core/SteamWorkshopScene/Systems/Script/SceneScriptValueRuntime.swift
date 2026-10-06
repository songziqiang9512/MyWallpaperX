import Foundation

nonisolated final class SceneScriptValueOwner: @unchecked Sendable {
    let target: SceneDynamicTarget
    /// Pure projection of the immutable target, resolved once at construction.
    let layerID: Int
    let generation: UInt64
    let hasAudioRegistration: Bool
    let handlesMediaThumbnail: Bool
    let handlesMediaPlayback: Bool
    let handlesMediaProperties: Bool
    let handlesMediaTimeline: Bool
    let handlesUserProperties: Bool
    let exportedCursorEvents: Set<SceneScriptCursorEventKind>
    let handle: OpaquePointer
    private let domain: SceneScriptQuickJSDomain
    private let budget: SceneScriptScalarBudget
    private let valueType: SceneDynamicValueType
    private let dynamicImagePathsByAuthoredIdentity: [String: String]
    private let allowsStatefulLayerSideEffects: Bool
    private let handlesInit: Bool
    private let handlesUpdate: Bool
    private var pendingInitializationValue: SceneDynamicValue?
    private var initializationValueConsumed = false
    private var lastAudioGeneration: UInt64?
    private var pendingCursorEvaluation = false

    var allowsDynamicLayerSideEffects: Bool {
        allowsStatefulLayerSideEffects
            || !dynamicImagePathsByAuthoredIdentity.isEmpty
    }

    /// Event-only owners sleep until a callback stages their own value.
    /// Publish it through the ordinary typed evaluation; initialization and
    /// timers keep their existing scheduling and shared commit boundary.
    var requiresFrameEvaluation: Bool {
        handlesUpdate || needsInitialization || pendingCursorEvaluation
            || (pendingInitializationValue != nil && !initializationValueConsumed)
            || mwx_scene_quickjs_owner_has_staged_effect_visibility(handle)
            || mwx_scene_quickjs_owner_active_timer_count(handle) > 0
    }

    /// Authored `init` runs once, before any other authored callback. A route
    /// that dispatches events ahead of the frame evaluation has to complete it
    /// first, or the callback would read pre-`init` state.
    var needsInitialization: Bool { handlesInit && !mwx_scene_quickjs_owner_is_initialized(handle) }

    /// Takes the value an out-of-band `init` published, for the next `update`.
    private func consumePendingInitializationValue() -> SceneDynamicValue? {
        guard !initializationValueConsumed, let pendingInitializationValue else { return nil }
        initializationValueConsumed = true
        return pendingInitializationValue
    }

    init(
        domain: SceneScriptQuickJSDomain,
        source: String,
        target: SceneDynamicTarget,
        valueType: SceneDynamicValueType = .vector3,
        effectNames: [String?],
        hasCurrentAnimation: Bool = false,
        dynamicImagePathsByAuthoredIdentity: [String: String] = [:],
        allowsStatefulLayerSideEffects: Bool = false,
        effectVisibilityGetterSeed: Bool? = nil,
        generation: UInt64,
        budget: SceneScriptScalarBudget,
        constructionWork: SceneScriptConstructionWorkBudget? = nil
    ) throws {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              [.scalar, .bool, .vector2, .vector3, .string].contains(valueType),
              generation > 0 else { throw SceneScriptScalarRuntimeFailure.invalidSource }
        if valueType == .scalar, case let .text(_, field) = target, field != .pointSize {
            throw SceneScriptScalarRuntimeFailure.invalidArgument("invalid scalar text target")
        }
        self.domain = domain
        self.target = target
        self.generation = generation
        self.budget = budget
        self.valueType = valueType
        self.dynamicImagePathsByAuthoredIdentity =
            dynamicImagePathsByAuthoredIdentity
        self.allowsStatefulLayerSideEffects = allowsStatefulLayerSideEffects
        if let constructionWork, !constructionWork.consume() {
            throw constructionWork.failure
        }
        try domain.checkConstructionBoundary()
        var diagnostic = [CChar](repeating: 0, count: 512)
        var creationResult = MWX_SCENE_QUICKJS_INVALID_ARGUMENT
        let created = source.withCString {
            if valueType == .bool && (allowsStatefulLayerSideEffects
                || !dynamicImagePathsByAuthoredIdentity.isEmpty) {
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
        var handlesUserProperties = false
        var handlesInit = false
        var handlesUpdate = false
        var exportedCursorEvents: Set<SceneScriptCursorEventKind> = []
        var ownerHasAudioRegistration = false
        do {
            guard let layerID = SceneScriptLayerMutationBridge.layerID(for: target) else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    "SceneScript owner layer identity unavailable"
                )
            }
            self.layerID = layerID
            let layerResult = mwx_scene_quickjs_owner_configure_layer_identity(
                created,
                Int64(layerID),
                &diagnostic,
                diagnostic.count
            )
            guard layerResult == MWX_SCENE_QUICKJS_OK else {
                throw Self.failure(layerResult, diagnostic)
            }
            let scopeResult = mwx_scene_quickjs_owner_set_property_object_scope(
                created,
                SceneScriptLayerMutationBridge.propertyObjectIsLayer(target) ? 1 : 0,
                &diagnostic,
                diagnostic.count
            )
            guard scopeResult == MWX_SCENE_QUICKJS_OK else {
                throw Self.failure(scopeResult, diagnostic)
            }
            try SceneScriptLayerMutationBridge.configureEffectVisibilityTarget(
                owner: created, target: target,
                // The getter's read default is the binding's authored seed,
                // not the definition's prepared snapshot seed.
                seedVisible: effectVisibilityGetterSeed ?? true
            )
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
            handlesUserProperties = try SceneScriptOwnerExportBridge.contains(
                "applyUserProperties", owner: created
            )
            handlesInit = try SceneScriptOwnerExportBridge.contains(
                "init", owner: created
            )
            handlesUpdate = try SceneScriptOwnerExportBridge.contains(
                "update", owner: created
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
                let handlesDestroy = try SceneScriptOwnerExportBridge.contains(
                    "destroy", owner: created
                )
                let hasMediaHook = handlesMediaThumbnail || handlesMediaPlayback
                    || handlesMediaProperties || handlesMediaTimeline
                let hasCursorHook = !exportedCursorEvents.isEmpty
                let hasEventHook = hasMediaHook || handlesUserProperties
                    || hasCursorHook
                if handlesInit || handlesUpdate {
                    // A stateful owner's destroy hook joins the existing
                    // exactly-once teardown dispatch (fail-soft, journal
                    // discarded); value-less lanes keep the stricter shape.
                    guard allowsStatefulLayerSideEffects || !handlesDestroy,
                          (allowsStatefulLayerSideEffects || !hasMediaHook),
                          (allowsStatefulLayerSideEffects
                            || exportedCursorEvents.isEmpty),
                          (dynamicImagePathsByAuthoredIdentity.isEmpty
                            && !allowsStatefulLayerSideEffects
                            ? !ownerHasAudioRegistration
                            : true) else {
                        throw SceneScriptScalarRuntimeFailure.invalidSource
                    }
                } else {
                    // Event callbacks share the stateful mutation journal and
                    // current audio snapshot. Registration does not require a
                    // per-frame update; idle owners keep the existing event/
                    // timer scheduling and borrowed cursor ownership.
                    guard hasEventHook,
                          !handlesDestroy,
                          allowsStatefulLayerSideEffects else {
                        throw SceneScriptScalarRuntimeFailure.invalidSource
                    }
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
        self.handlesUserProperties = handlesUserProperties
        self.handlesInit = handlesInit
        self.handlesUpdate = handlesUpdate
        self.exportedCursorEvents = exportedCursorEvents
    }

    deinit { mwx_scene_quickjs_owner_destroy(handle) }

    func refreshAudio(
        _ snapshot: SceneAudioSpectrumSnapshot
    ) -> Result<Void, SceneScriptScalarRuntimeFailure> {
        guard lastAudioGeneration != snapshot.generation else {
            return .success(())
        }
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = SceneScriptAudioHost.refresh(
            owner: handle,
            ownerGeneration: generation,
            snapshot: snapshot,
            diagnostic: &diagnostic
        )
        if case .success = result {
            lastAudioGeneration = snapshot.generation
        }
        return result
    }

    func initializeIfNeeded(
        input: SceneDynamicValue,
        frame: SceneScriptFrameInput,
        scriptPropertiesJSON: String,
        userPropertiesJSON: String,
        expectedGeneration: UInt64,
        interruptBudget: UInt64?,
        retainsValueForNextUpdate: Bool = false
    ) -> Result<SceneScriptValueEvaluation?, SceneScriptScalarRuntimeFailure> {
        guard input.valueType == valueType, input.isFinite,
              Self.acceptsScalarValue(input, for: target),
              frame.timeOfDay.isFinite, (0...1).contains(frame.timeOfDay),
              frame.frameTime.isFinite, frame.frameTime >= 0,
              frame.runtime.isFinite, frame.runtime >= 0 else {
            return .failure(.invalidArgument("invalid typed initialization input"))
        }
        guard expectedGeneration == generation else { return .failure(.staleOwner) }
        let scriptInput = sceneScriptInput(input)
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        var frameInput = frame.quickJSValue
        var didInitialize: UInt32 = 0
        var diagnostic = [CChar](repeating: 0, count: 512)
        var result: MWXSceneQuickJSResult
        let publishedValue: SceneDynamicValue
        switch scriptInput {
        case .scalar, .bool:
            let inputValue: Double
            if case let .scalar(value) = scriptInput { inputValue = value }
            else if case let .bool(value) = scriptInput { inputValue = value ? 1 : 0 }
            else { preconditionFailure("primitive initialization input changed") }
            var output = 0.0
            result = scriptPropertiesJSON.withCString { properties in
                userPropertiesJSON.withCString { userProperties in
                    mwx_scene_quickjs_owner_initialize_primitive_with_properties(
                        handle, expectedGeneration, inputValue, valueType == .bool ? 1 : 0,
                        &frameInput, properties, scriptPropertiesJSON.utf8.count,
                        userProperties, userPropertiesJSON.utf8.count,
                        &output, &didInitialize, &diagnostic, diagnostic.count
                    )
                }
            }
            publishedValue = valueType == .bool ? .bool(output != 0) : .scalar(output)
        case let .string(value):
            (result, publishedValue) = callString(
                value, initializing: true, expectedGeneration: expectedGeneration,
                frame: &frameInput, scriptPropertiesJSON: scriptPropertiesJSON,
                userPropertiesJSON: userPropertiesJSON,
                didInitialize: &didInitialize, diagnostic: &diagnostic
            )
        case .vector2, .vector3:
            let source: [Double]
            switch scriptInput {
            case let .vector2(x, y): source = [x, y]
            case let .vector3(x, y, z): source = [x, y, z]
            default: preconditionFailure("typed initialization input changed")
            }
            var output = [Double](repeating: 0, count: source.count)
            result = source.withUnsafeBufferPointer { sourceBuffer in
                output.withUnsafeMutableBufferPointer { outputBuffer in
                    scriptPropertiesJSON.withCString { properties in
                        userPropertiesJSON.withCString { userProperties in
                            mwx_scene_quickjs_owner_initialize_vector(
                                handle, expectedGeneration, sourceBuffer.baseAddress,
                                UInt32(source.count), &frameInput,
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
                discardLayerMutations()
                return .failure(.badReturn("invalid initialized vector output"))
            }
            publishedValue = runtimeValue(
                valueType == .vector2
                    ? .vector2(output[0], output[1])
                    : .vector3(output[0], output[1], output[2])
            )
        default:
            return .failure(.invalidArgument("invalid typed initialization input"))
        }
        if result != MWX_SCENE_QUICKJS_OK,
           case .layer(_, .angles) = target,
           String(cString: diagnostic).contains("invalid Vec3") {
            // Some authored update callbacks return their text payload while
            // publishing the angle through thisLayer.angles mutation.
            result = MWX_SCENE_QUICKJS_OK
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            discardLayerMutations()
            return .failure(Self.failure(result, diagnostic))
        }
        guard didInitialize != 0 else { return .success(nil) }
        let callbackMutations: SceneScriptMediaEventMutations
        switch SceneScriptMediaEventBridge.mutations(
            owner: handle, target: target, layerID: layerID
        ) {
        case let .success(value): callbackMutations = value
        case let .failure(failure):
            discardLayerMutations()
            return .failure(failure)
        }
        let evaluation = validatedEvaluation(
            value: publishedValue,
            mutations: callbackMutations,
            layerID: layerID
        )
        // A route that ran this `init` ahead of the frame evaluation (cursor)
        // carries its value across, so the first `update` still receives it.
        if retainsValueForNextUpdate, case let .success(value) = evaluation {
            pendingInitializationValue = value.value
        }
        return evaluation.map(Optional.some)
    }

    func evaluate(
        input: SceneDynamicValue,
        frame: SceneScriptFrameInput,
        scriptPropertiesJSON: String,
        userPropertiesJSON: String,
        expectedGeneration: UInt64,
        interruptBudget: UInt64?
    ) -> Result<SceneScriptValueEvaluation, SceneScriptScalarRuntimeFailure> {
        guard input.valueType == valueType, input.isFinite,
              Self.acceptsScalarValue(input, for: target),
              frame.timeOfDay.isFinite, (0...1).contains(frame.timeOfDay),
              frame.frameTime.isFinite, frame.frameTime >= 0,
              frame.runtime.isFinite, frame.runtime >= 0 else {
            return .failure(.invalidArgument("invalid typed vector input"))
        }
        guard expectedGeneration == generation else { return .failure(.staleOwner) }
        let scriptInput = sceneScriptInput(
            consumePendingInitializationValue() ?? input
        )
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        var frameInput = frame.quickJSValue
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result: MWXSceneQuickJSResult
        let publishedValue: SceneDynamicValue
        switch scriptInput {
        case let .scalar(value):
            var output = 0.0
            result = scriptPropertiesJSON.withCString { properties in
                userPropertiesJSON.withCString { userProperties in
                    mwx_scene_quickjs_owner_update_scalar_with_properties(
                        handle, expectedGeneration, value, &frameInput,
                        properties, scriptPropertiesJSON.utf8.count,
                        userProperties, userPropertiesJSON.utf8.count,
                        &output, &diagnostic, diagnostic.count
                    )
                }
            }
            if result == MWX_SCENE_QUICKJS_OK, !handlesUpdate {
                switch boundScalarValue() {
                case let .success(value): if let value { output = value }
                case let .failure(failure):
                    discardLayerMutations()
                    return .failure(failure)
                }
            }
            publishedValue = .scalar(output)
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
        case let .string(value):
            var didInitialize: UInt32 = 0
            (result, publishedValue) = callString(
                value, initializing: false, expectedGeneration: expectedGeneration,
                frame: &frameInput, scriptPropertiesJSON: scriptPropertiesJSON,
                userPropertiesJSON: userPropertiesJSON,
                didInitialize: &didInitialize, diagnostic: &diagnostic
            )
        case .vector2, .vector3:
            let source: [Double]
            switch scriptInput {
            case let .vector2(x, y): source = [x, y]
            case let .vector3(x, y, z): source = [x, y, z]
            default: preconditionFailure("typed vector input changed")
            }
            var output = [Double](repeating: 0, count: source.count)
            result = source.withUnsafeBufferPointer { sourceBuffer in
                output.withUnsafeMutableBufferPointer { outputBuffer in
                    scriptPropertiesJSON.withCString { properties in
                        userPropertiesJSON.withCString { userProperties in
                            mwx_scene_quickjs_owner_update_vector(
                                handle, expectedGeneration, sourceBuffer.baseAddress,
                                UInt32(source.count), &frameInput,
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
                discardLayerMutations()
                return .failure(.badReturn("non-finite vector output"))
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
            discardLayerMutations()
            return .failure(Self.failure(result, diagnostic))
        }
        let callbackMutations: SceneScriptMediaEventMutations
        switch SceneScriptMediaEventBridge.mutations(
            owner: handle, target: target, layerID: layerID
        ) {
        case let .success(value): callbackMutations = value
        case let .failure(failure):
            discardLayerMutations()
            return .failure(failure)
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
    ) -> Result<SceneScriptValueEvaluation, SceneScriptScalarRuntimeFailure> {
        guard Self.acceptsScalarValue(publishedValue, for: target) else {
            discardLayerMutations()
            return .failure(.badReturn("invalid scalar output"))
        }
        let publishedLayerMutations: [SceneScriptLayerMutation]
        let resolvedValue: SceneDynamicValue
        if valueType == .bool {
            guard mutations.materialFunctions.isEmpty,
                  mutations.animations.isEmpty else {
                discardLayerMutations()
                return .failure(.invalidArgument(
                    "Boolean value owner produced out-of-cohort mutations"
                ))
            }
            switch validateBooleanFrame(
                value: publishedValue,
                mutations: mutations.layers
            ) {
            case let .success(resolved):
                resolvedValue = resolved.value
                publishedLayerMutations = resolved.mutations
            case let .failure(failure):
                discardLayerMutations()
                return .failure(failure)
            }
        } else {
            resolvedValue = publishedValue
            publishedLayerMutations = mutations.layers
        }
        return .success(.init(
            value: resolvedValue,
            materialFunctionMutations: mutations.materialFunctions,
            animationMutations: mutations.animations,
            layerMutations: publishedLayerMutations,
            puppetBoneMutations: mutations.puppetBones,
            videoCommands: mutations.videoCommands,
            textureAnimationCommands: mutations.textureAnimationCommands,
            particlePlaybackCommands: mutations.particlePlaybackCommands
        ))
    }

    func validateBooleanFrame(
        value publishedValue: SceneDynamicValue,
        mutations: [SceneScriptLayerMutation]
    ) -> Result<
        (value: SceneDynamicValue, mutations: [SceneScriptLayerMutation]),
        SceneScriptScalarRuntimeFailure
    > {
        if case .effectVisibility = target {
            // The staged effect-visibility write publishes straight into the
            // typed effect-activation channel; layer mutations have no cohort
            // here and would signal a routing bug.
            guard mutations.isEmpty else {
                return .failure(.invalidArgument(
                    "Effect visibility owner produced out-of-cohort mutations"
                ))
            }
            return .success((publishedValue, []))
        }
        return SceneScriptBooleanVisibilityValidation.validate(
            valueType: valueType,
            target: target,
            allowsLayerSideEffects: allowsDynamicLayerSideEffects,
            dynamicImagePathsByAuthoredIdentity:
                dynamicImagePathsByAuthoredIdentity,
            value: publishedValue,
            mutations: mutations
        )
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
        scriptPropertiesJSON: String,
        userPropertiesJSON: String,
        authoredLayerBaselines: [SceneScriptLayerMutation] = [],
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        guard layerID == event.layerID else {
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
            scriptPropertiesJSON: scriptPropertiesJSON,
            userPropertiesJSON: userPropertiesJSON
        ).flatMap { mutations in
            if valueType == .scalar { pendingCursorEvaluation = true }
            guard case .effectVisibility = target else {
                return .success(mutations)
            }
            // Validate the same effect-owner cohort as init/update. This
            // event has no return value; its staged Bool is consumed by the
            // ordinary value evaluation before the shared frame commit.
            return validatedEvaluation(
                value: .bool(false), mutations: mutations, layerID: event.layerID
            ).map { _ in mutations }
        }
    }

    func invalidate() {
        domain.discardStorage(owner: handle)
        mwx_scene_quickjs_owner_invalidate(handle)
    }

    func commitLayerMutations() {
        pendingCursorEvaluation = false
        SceneScriptLayerMutationBridge.commit(owner: handle)
        if initializationValueConsumed { pendingInitializationValue = nil }
        initializationValueConsumed = false
    }

    func discardLayerMutations() {
        pendingCursorEvaluation = false
        SceneScriptLayerMutationBridge.discard(owner: handle)
        // Keep a previously committed cursor value until its consumption is
        // accepted. A rejected first init has no committed value to retain.
        if !mwx_scene_quickjs_owner_is_initialized(handle) {
            pendingInitializationValue = nil
        }
        initializationValueConsumed = false
    }

    func commitStorage() -> Result<Void, SceneScriptScalarRuntimeFailure> {
        let result = domain.commitStorage(owner: handle, target: target)
        if case .failure = result {
            discardLayerMutations()
        }
        return result
    }

    func discardStorage() {
        domain.discardStorage(owner: handle)
    }

    func timerFrameSnapshot() -> OpaquePointer? {
        mwx_scene_quickjs_owner_timer_snapshot(handle)
    }

    func restoreTimerFrame(_ snapshot: OpaquePointer?) {
        guard let snapshot else { return }
        _ = mwx_scene_quickjs_owner_timer_restore(handle, snapshot)
    }

    func discardTimerFrame(_ snapshot: OpaquePointer?) {
        guard let snapshot else { return }
        mwx_scene_quickjs_owner_timer_snapshot_destroy(snapshot, handle)
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

    static func acceptsScalar(_ value: Double, for target: SceneDynamicTarget) -> Bool {
        guard value.isFinite else { return false }
        if case .layer(_, .intensity) = target {
            return value >= 0 && value <= Double(Float.greatestFiniteMagnitude)
        }
        if case .materialConstant = target {
            return Float(value).isFinite
        }
        return true
    }

    private static func acceptsScalarValue(_ value: SceneDynamicValue, for target: SceneDynamicTarget) -> Bool {
        guard case let .scalar(number) = value else { return true }
        return acceptsScalar(number, for: target)
    }

    private func boundScalarValue() -> Result<Double?, SceneScriptScalarRuntimeFailure> {
        guard case let .effectConstant(_, _, _, name) = target,
              !name.isEmpty, name.utf8.count <= 256, !name.contains("\0") else {
            return .success(nil)
        }
        var value = 0.0
        var present: UInt32 = 0
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = name.withCString {
            mwx_scene_quickjs_owner_read_bound_scalar(
                handle, generation, $0, name.utf8.count,
                &value, &present, &diagnostic, diagnostic.count
            )
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            return .failure(Self.failure(result, diagnostic))
        }
        return .success(present == 0 ? nil : value)
    }

    static func failure(
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
