import Foundation

private nonisolated final class SceneScriptQuickJSCancellationCheckBox:
    @unchecked Sendable {
    let check: @Sendable () throws -> Void
    init(check: @escaping @Sendable () throws -> Void) { self.check = check }
}
private nonisolated func sceneScriptQuickJSCancellationCheck(
    _ opaque: UnsafeMutableRawPointer?
) -> CInt {
    guard let opaque else { return 0 }
    let box = Unmanaged<SceneScriptQuickJSCancellationCheckBox>
        .fromOpaque(opaque).takeUnretainedValue()
    do { try box.check(); return 0 } catch { return 1 }
}
nonisolated struct SceneScriptScalarBudget: Equatable, Sendable {
    let heapBytes: Int
    let stackBytes: Int
    let interruptBudget: UInt64
    var maximumNativeTransientBytes: Int { heapBytes }
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

nonisolated final class SceneScriptQuickJSDomain: @unchecked Sendable {
    let handle: OpaquePointer
    let budget: SceneScriptScalarBudget
    var storageSession: SceneScriptLocalStorageSession? = nil
    var particleEmissionBoundary: ((OpaquePointer, Bool) -> Void)?
    var particleEmissionHost: ((OpaquePointer, MWXSceneQuickJSParticlePlaybackCommand) throws -> SceneParticlePlaybackObservation)?

    var namedAnimationTargets: [SceneDynamicTarget]?
    var layerCatalogSignature: String?
    var layerSnapshotGeneration: UInt64 = 0
    var layerWorldTransformProjection:
        SceneScriptLayerWorldTransformProjection?
    var committedDynamicWorldTransformLayerIDs: Set<Int> = []
    var rollbackDynamicWorldTransformLayerIDs: Set<Int>?
    private var constructionBoundaryCheck: (@Sendable () throws -> Void)?
    private var constructionCancellationOpaque: UnsafeMutableRawPointer?
    init(budget: SceneScriptScalarBudget = .default) throws {
        self.budget = budget
        var diagnostic = [CChar](repeating: 0, count: 512)
        guard let handle = mwx_scene_quickjs_domain_create(
            budget.heapBytes, budget.stackBytes, budget.interruptBudget,
            &diagnostic, diagnostic.count
        ) else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                Self.diagnostic(diagnostic)
            )
        }
        self.handle = handle
    }
    deinit {
        endParticlePlaybackFrame()
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
    func adoptCurrentThread() { mwx_scene_quickjs_domain_adopt_current_thread(handle) }
    func discardCommittedLayerSnapshot() {
        guard mwx_scene_quickjs_domain_rollback_layer_snapshot(handle) else { return }
        if layerSnapshotGeneration > 0 { layerSnapshotGeneration -= 1 }
        if let rollbackDynamicWorldTransformLayerIDs {
            committedDynamicWorldTransformLayerIDs =
                rollbackDynamicWorldTransformLayerIDs
        }
        rollbackDynamicWorldTransformLayerIDs = nil
    }
    func finalizeCommittedLayerSnapshot() {
        mwx_scene_quickjs_domain_finalize_layer_snapshot(handle)
        rollbackDynamicWorldTransformLayerIDs = nil
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
            handle, sceneScriptQuickJSCancellationCheck, opaque
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
    func checkConstructionBoundary() throws { try constructionBoundaryCheck?() }
    private static func diagnostic(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
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

    /// A returned value that failed validation is data-shaped: the same script
    /// can produce a valid value on a later frame once upstream producers
    /// publish (corpus: shared-state ordering). Those failures fail the frame,
    /// keep previous-current, and retry; code-shaped failures (exceptions,
    /// budget, overflow) keep the permanent fuse.
    var permanentlyDisablesOwner: Bool {
        if case .badReturn = self { return false }
        return true
    }
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
