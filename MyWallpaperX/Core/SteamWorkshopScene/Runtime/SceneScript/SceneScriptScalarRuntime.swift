import Foundation

private nonisolated final class SceneScriptQuickJSCancellationCheckBox:
    @unchecked Sendable {
    let check: @Sendable () throws -> Void

    init(check: @escaping @Sendable () throws -> Void) {
        self.check = check
    }
}

private nonisolated func sceneScriptQuickJSCancellationCheck(
    _ opaque: UnsafeMutableRawPointer?
) -> CInt {
    guard let opaque else { return 0 }
    let box = Unmanaged<SceneScriptQuickJSCancellationCheckBox>
        .fromOpaque(opaque).takeUnretainedValue()
    do {
        try box.check()
        return 0
    } catch {
        return 1
    }
}

nonisolated struct SceneScriptScalarBudget: Equatable, Sendable {
    let heapBytes: Int
    let stackBytes: Int
    let interruptBudget: UInt64
    let maximumOwnerSourceBytes: Int
    let maximumCandidateSourceBytes: Int

    static let `default` = SceneScriptScalarBudget(
        heapBytes: 16 * 1024 * 1024,
        stackBytes: 512 * 1024,
        interruptBudget: 100_000,
        maximumOwnerSourceBytes: 256 * 1024,
        maximumCandidateSourceBytes: 2 * 1024 * 1024
    )

    /// UTF-8 source is charged once per projected owner. Identical source text
    /// used by distinct owners is charged repeatedly because each owner causes
    /// independent module construction; retry work has a separate candidate cap.
    func candidateSourceFailure(
        _ sources: [String]
    ) -> SceneScriptScalarRuntimeFailure? {
        guard maximumOwnerSourceBytes > 0,
              maximumCandidateSourceBytes > 0 else {
            return .budgetExceeded("SceneScript candidate source budget is invalid")
        }
        var aggregateBytes = 0
        for source in sources {
            let sourceBytes = source.utf8.count
            guard sourceBytes <= maximumOwnerSourceBytes else {
                return .budgetExceeded(
                    "SceneScript owner source exceeds UTF-8 byte budget"
                )
            }
            let (nextBytes, overflow) = aggregateBytes.addingReportingOverflow(
                sourceBytes
            )
            guard !overflow, nextBytes <= maximumCandidateSourceBytes else {
                return .budgetExceeded(
                    "SceneScript candidate aggregate source exceeds UTF-8 byte budget"
                )
            }
            aggregateBytes = nextBytes
        }
        return nil
    }
}

nonisolated enum SceneScriptScalarRuntimeFailure: Error, Equatable, Sendable {
    case invalidSource
    case compile(String)
    case exception(String)
    case budgetExceeded(String)
    case memoryExceeded(String)
    case badReturn(String)
    case disabled(String)
    case staleOwner
    case invalidArgument(String)
    case mutationOverflow(String)

    var code: String {
        switch self {
        case .invalidSource: "invalid-source"
        case .compile: "compile-error"
        case .exception: "exception"
        case .budgetExceeded: "budget-exceeded"
        case .memoryExceeded: "memory-exceeded"
        case .badReturn: "bad-return"
        case .disabled: "disabled"
        case .staleOwner: "stale-owner"
        case .invalidArgument: "invalid-argument"
        case .mutationOverflow: "mutation-overflow"
        }
    }
}

nonisolated struct SceneScriptScalarEvaluation: Equatable, Sendable {
    let value: SceneDynamicValue
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
}

nonisolated struct SceneScriptFrameInput: Equatable, Sendable {
    let timeOfDay: Double
    let frameTime: TimeInterval
    let runtime: TimeInterval
    let surface: SceneScriptSurfaceInput?

    init(
        timing: SceneFrameTiming,
        timeZone: TimeZone = .current,
        surface: SceneScriptSurfaceInput? = nil
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: timing.wallDate
        )
        let seconds = Double(components.hour ?? 0) * 3_600
            + Double(components.minute ?? 0) * 60
            + Double(components.second ?? 0)
            + Double(components.nanosecond ?? 0) / 1_000_000_000
        timeOfDay = min(max(seconds / 86_400, 0), 1)
        frameTime = max(timing.simulationFrameTime, 0)
        runtime = max(timing.sceneTime, 0)
        self.surface = surface
    }

    init(replacingSurfaceOf frame: SceneScriptFrameInput, with surface: SceneScriptSurfaceInput?) {
        timeOfDay = frame.timeOfDay
        frameTime = frame.frameTime
        runtime = frame.runtime
        self.surface = surface
    }

    var quickJSValue: MWXSceneQuickJSFrameInput {
        MWXSceneQuickJSFrameInput(
            time_of_day: timeOfDay,
            frame_time: frameTime,
            runtime: runtime,
            has_surface_input: surface == nil ? 0 : 1,
            canvas_width: surface?.canvasSize.x ?? 0,
            canvas_height: surface?.canvasSize.y ?? 0,
            screen_width: surface?.screenSize.x ?? 0,
            screen_height: surface?.screenSize.y ?? 0,
            cursor_world_x: surface?.cursorWorldPosition.x ?? 0,
            cursor_world_y: surface?.cursorWorldPosition.y ?? 0,
            cursor_world_z: surface?.cursorWorldPosition.z ?? 0,
            cursor_screen_x: surface?.cursorScreenPosition.x ?? 0,
            cursor_screen_y: surface?.cursorScreenPosition.y ?? 0,
            cursor_left_down: surface?.cursorLeftDown == true ? 1 : 0
        )
    }
}

nonisolated struct SceneScriptSurfaceInput: Equatable, Sendable {
    let canvasSize: SIMD2<Double>
    let screenSize: SIMD2<Double>
    let cursorWorldPosition: SIMD3<Double>
    let cursorScreenPosition: SIMD2<Double>
    let cursorLeftDown: Bool
}

/// Owns one scalar property binding inside a shared per-scene QuickJS domain.
/// The opaque C handles never escape this owner and are generation-checked on
/// every callback before the value enters the Swift snapshot channel.
nonisolated final class SceneScriptScalarOwner: @unchecked Sendable {
    let generation: UInt64
    let target: SceneDynamicTarget
    let authoredValue: Double
    let hasAudioRegistration: Bool
    let handlesMediaThumbnail: Bool
    let handlesMediaPlayback: Bool
    let handlesMediaProperties: Bool
    let handlesMediaTimeline: Bool
    private let initialScriptPropertiesJSON: String
    private let handle: OpaquePointer
    private let domain: SceneScriptQuickJSDomain
    private let budget: SceneScriptScalarBudget

    init(
        domain: SceneScriptQuickJSDomain,
        source: String,
        target: SceneDynamicTarget,
        authoredValue: Double,
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
        guard Self.supports(target),
              Self.accepts(authoredValue) else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                "invalid scalar owner target or authored value"
            )
        }
        self.domain = domain
        self.target = target
        self.authoredValue = authoredValue
        initialScriptPropertiesJSON = scriptPropertiesJSON
        self.generation = generation
        self.budget = budget
        try domain.checkConstructionBoundary()
        var diagnostic = [CChar](repeating: 0, count: 512)
        var creationResult = MWX_SCENE_QUICKJS_INVALID_ARGUMENT
        let created: OpaquePointer? = source.withCString {
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
            throw Self.failure(
                raw: creationResult,
                diagnostic: Self.diagnostic(diagnostic)
            )
        }
        var handlesMediaThumbnail = false
        var handlesMediaPlayback = false
        var handlesMediaProperties = false
        var handlesMediaTimeline = false
        do {
            try SceneScriptLayerMutationBridge.configure(owner: created, target: target)
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
        self.handle = created
        hasAudioRegistration = SceneScriptAudioHost.hasRegistration(owner: created)
        self.handlesMediaThumbnail = handlesMediaThumbnail
        self.handlesMediaPlayback = handlesMediaPlayback
        self.handlesMediaProperties = handlesMediaProperties
        self.handlesMediaTimeline = handlesMediaTimeline
    }

    deinit {
        mwx_scene_quickjs_owner_destroy(handle)
    }

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
        input: Double,
        frame: SceneScriptFrameInput,
        scriptPropertiesJSON: String,
        userPropertiesJSON: String,
        expectedGeneration: UInt64,
        interruptBudget: UInt64?
    ) -> Result<SceneScriptScalarEvaluation?, SceneScriptScalarRuntimeFailure> {
        guard Self.accepts(input), frame.timeOfDay.isFinite,
              (0...1).contains(frame.timeOfDay), frame.frameTime.isFinite,
              frame.frameTime >= 0, frame.runtime.isFinite,
              frame.runtime >= 0 else {
            return .failure(.invalidArgument("invalid scalar initialization input"))
        }
        guard expectedGeneration == generation else { return .failure(.staleOwner) }
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        var output = 0.0
        var didInitialize: UInt32 = 0
        var frameInput = frame.quickJSValue
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = scriptPropertiesJSON.withCString { properties in
            userPropertiesJSON.withCString { userProperties in
                mwx_scene_quickjs_owner_initialize_primitive_with_properties(
                    handle, expectedGeneration, input, 0, &frameInput,
                    properties, scriptPropertiesJSON.utf8.count,
                    userProperties, userPropertiesJSON.utf8.count,
                    &output, &didInitialize, &diagnostic, diagnostic.count
                )
            }
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            return .failure(Self.failure(
                raw: result,
                diagnostic: Self.diagnostic(diagnostic)
            ))
        }
        guard didInitialize != 0 else { return .success(nil) }
        guard Self.accepts(output),
              let layerID = SceneScriptLayerMutationBridge.layerID(for: target) else {
            return .failure(.badReturn("invalid initialized scalar output"))
        }
        let callbackMutations: SceneScriptMediaEventMutations
        switch SceneScriptMediaEventBridge.mutations(
            owner: handle,
            target: target,
            layerID: layerID
        ) {
        case let .success(value): callbackMutations = value
        case let .failure(failure): return .failure(failure)
        }
        return .success(.init(
            value: .scalar(output),
            materialFunctionMutations: callbackMutations.materialFunctions,
            animationMutations: callbackMutations.animations,
            layerMutations: callbackMutations.layers
        ))
    }

    func evaluate(
        input: Double,
        frame: SceneScriptFrameInput,
        scriptPropertiesJSON: String? = nil,
        userPropertiesJSON: String = "{}",
        expectedGeneration: UInt64,
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptScalarEvaluation, SceneScriptScalarRuntimeFailure> {
        guard Self.accepts(input) else {
            return .failure(.invalidArgument("invalid scalar input"))
        }
        guard frame.timeOfDay.isFinite,
              (0...1).contains(frame.timeOfDay),
              frame.frameTime.isFinite,
              frame.frameTime >= 0,
              frame.runtime.isFinite,
              frame.runtime >= 0 else {
            return .failure(.invalidArgument("invalid frame input"))
        }
        guard expectedGeneration == generation else {
            return .failure(.staleOwner)
        }
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        var output = 0.0
        var frameInput = frame.quickJSValue
        var diagnostic = [CChar](repeating: 0, count: 512)
        let resolvedScriptPropertiesJSON =
            scriptPropertiesJSON ?? initialScriptPropertiesJSON
        let result = resolvedScriptPropertiesJSON.withCString { scriptProperties in
            userPropertiesJSON.withCString { userProperties in
                mwx_scene_quickjs_owner_update_scalar_with_properties(
                    handle,
                    expectedGeneration,
                    input,
                    &frameInput,
                    scriptProperties,
                    resolvedScriptPropertiesJSON.utf8.count,
                    userProperties,
                    userPropertiesJSON.utf8.count,
                    &output,
                    &diagnostic,
                    diagnostic.count
                )
            }
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            return .failure(Self.failure(
                raw: result,
                diagnostic: Self.diagnostic(diagnostic)
            ))
        }
        guard Self.accepts(output) else {
            return .failure(.badReturn("invalid scalar output"))
        }
        let layerID: Int
        switch target {
        case let .effectConstant(value, _, _, _), let .layer(value, _),
             let .text(value, .pointSize), let .particle(value, _):
            layerID = value
        default:
            return .failure(.invalidArgument("SceneScript owner identity unavailable"))
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
        return .success(.init(
            value: .scalar(output),
            materialFunctionMutations: mutations,
            animationMutations: animationMutations,
            layerMutations: layerMutations
        ))
    }

    func dispatchMediaThumbnail(
        _ event: SceneScriptMediaThumbnailEventInput,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        let layerID: Int
        switch target {
        case let .effectConstant(value, _, _, _), let .layer(value, _),
             let .text(value, .pointSize), let .particle(value, _):
            layerID = value
        default:
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
        let layerID: Int
        switch target {
        case let .effectConstant(value, _, _, _), let .layer(value, _),
             let .text(value, .pointSize), let .particle(value, _):
            layerID = value
        default:
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
        let layerID: Int
        switch target {
        case let .effectConstant(value, _, _, _), let .layer(value, _),
             let .text(value, .pointSize), let .particle(value, _):
            layerID = value
        default:
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

    static func supports(_ target: SceneDynamicTarget) -> Bool {
        guard case let .text(_, field) = target else { return true }
        return field == .pointSize
    }

    static func accepts(_ value: Double) -> Bool {
        value.isFinite
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
        scriptPropertiesJSON: String? = nil,
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

    private static func diagnostic(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func failure(
        raw: MWXSceneQuickJSResult,
        diagnostic: String
    ) -> SceneScriptScalarRuntimeFailure {
        switch raw {
        case MWX_SCENE_QUICKJS_COMPILE_ERROR:
            .compile(diagnostic)
        case MWX_SCENE_QUICKJS_EXCEPTION:
            .exception(diagnostic)
        case MWX_SCENE_QUICKJS_BUDGET_EXCEEDED:
            .budgetExceeded(diagnostic)
        case MWX_SCENE_QUICKJS_MEMORY_EXCEEDED:
            .memoryExceeded(diagnostic)
        case MWX_SCENE_QUICKJS_BAD_RETURN:
            .badReturn(diagnostic)
        case MWX_SCENE_QUICKJS_DISABLED:
            .disabled(diagnostic)
        case MWX_SCENE_QUICKJS_STALE_OWNER:
            .staleOwner
        case MWX_SCENE_QUICKJS_MUTATION_OVERFLOW:
            .mutationOverflow(diagnostic)
        default:
            .invalidArgument(diagnostic)
        }
    }
}

nonisolated final class SceneScriptQuickJSDomain: @unchecked Sendable {
    let handle: OpaquePointer
    let budget: SceneScriptScalarBudget
    var storageSession: SceneScriptLocalStorageSession? = nil
    var layerCatalogSignature: String?
    var layerSnapshotGeneration: UInt64 = 0
    private var constructionBoundaryCheck: (@Sendable () throws -> Void)?
    private var constructionCancellationOpaque: UnsafeMutableRawPointer?

    init(budget: SceneScriptScalarBudget = .default) throws {
        self.budget = budget
        var diagnostic = [CChar](repeating: 0, count: 512)
        guard let handle = mwx_scene_quickjs_domain_create(
            budget.heapBytes,
            budget.stackBytes,
            budget.interruptBudget,
            &diagnostic,
            diagnostic.count
        ) else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                Self.diagnostic(diagnostic)
            )
        }
        self.handle = handle
    }

    deinit {
        clearConstructionBoundaryCheck()
        var diagnostic = [CChar](repeating: 0, count: 1)
        _ = mwx_scene_quickjs_domain_configure_storage(
            handle, nil, nil, &diagnostic, diagnostic.count
        )
        mwx_scene_quickjs_domain_destroy(handle)
    }

    func resetBudget(_ interruptBudget: UInt64) {
        mwx_scene_quickjs_domain_reset_budget(handle, interruptBudget)
    }

    func installConstructionBoundaryCheck(
        _ check: @escaping @Sendable () throws -> Void
    ) {
        clearConstructionBoundaryCheck()
        constructionBoundaryCheck = check
        let box = SceneScriptQuickJSCancellationCheckBox(check: check)
        let opaque = Unmanaged.passRetained(box).toOpaque()
        constructionCancellationOpaque = opaque
        mwx_scene_quickjs_domain_set_cancellation_check(
            handle,
            sceneScriptQuickJSCancellationCheck,
            opaque
        )
    }

    func clearConstructionBoundaryCheck() {
        mwx_scene_quickjs_domain_set_cancellation_check(handle, nil, nil)
        if let constructionCancellationOpaque {
            Unmanaged<SceneScriptQuickJSCancellationCheckBox>
                .fromOpaque(constructionCancellationOpaque).release()
        }
        constructionCancellationOpaque = nil
        constructionBoundaryCheck = nil
    }

    func checkConstructionBoundary() throws {
        try constructionBoundaryCheck?()
    }

    private static func diagnostic(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
