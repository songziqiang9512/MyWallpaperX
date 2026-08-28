import Foundation

nonisolated struct SceneScriptScalarBudget: Equatable, Sendable {
    let heapBytes: Int
    let stackBytes: Int
    let interruptBudget: UInt64

    static let `default` = SceneScriptScalarBudget(
        heapBytes: 2 * 1024 * 1024,
        stackBytes: 512 * 1024,
        interruptBudget: 100_000
    )
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
}

nonisolated struct SceneScriptFrameInput: Equatable, Sendable {
    let timeOfDay: Double
    let frameTime: TimeInterval
    let runtime: TimeInterval

    init(timing: SceneFrameTiming, timeZone: TimeZone = .current) {
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
    }
}

/// Owns one scalar property binding inside a shared per-scene QuickJS domain.
/// The opaque C handles never escape this owner and are generation-checked on
/// every callback before the value enters the Swift snapshot channel.
nonisolated final class SceneScriptScalarOwner: @unchecked Sendable {
    let generation: UInt64
    let target: SceneDynamicTarget
    let authoredValue: Double
    private let handle: OpaquePointer
    private let domain: SceneScriptQuickJSDomain
    private let budget: SceneScriptScalarBudget

    init(
        domain: SceneScriptQuickJSDomain,
        source: String,
        target: SceneDynamicTarget,
        authoredValue: Double,
        generation: UInt64,
        budget: SceneScriptScalarBudget = .default
    ) throws {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              generation > 0 else {
            throw SceneScriptScalarRuntimeFailure.invalidSource
        }
        self.domain = domain
        self.target = target
        self.authoredValue = authoredValue
        self.generation = generation
        self.budget = budget
        var diagnostic = [CChar](repeating: 0, count: 512)
        let created: OpaquePointer? = source.withCString {
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
            throw Self.failure(
                raw: MWX_SCENE_QUICKJS_COMPILE_ERROR,
                diagnostic: Self.diagnostic(diagnostic)
            )
        }
        self.handle = created
    }

    deinit {
        mwx_scene_quickjs_owner_destroy(handle)
    }

    func evaluate(
        input: Double,
        frame: SceneScriptFrameInput,
        expectedGeneration: UInt64,
        interruptBudget: UInt64? = nil
    ) -> Result<SceneScriptScalarEvaluation, SceneScriptScalarRuntimeFailure> {
        guard input.isFinite else {
            return .failure(.invalidArgument("non-finite input"))
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
        var frameInput = MWXSceneQuickJSFrameInput(
            time_of_day: frame.timeOfDay,
            frame_time: frame.frameTime,
            runtime: frame.runtime
        )
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = mwx_scene_quickjs_owner_update_scalar(
            handle,
            expectedGeneration,
            input,
            &frameInput,
            &output,
            &diagnostic,
            diagnostic.count
        )
        guard result == MWX_SCENE_QUICKJS_OK else {
            return .failure(Self.failure(
                raw: result,
                diagnostic: Self.diagnostic(diagnostic)
            ))
        }
        guard output.isFinite else {
            return .failure(.badReturn("non-finite output"))
        }
        var mutations: [SceneScriptMaterialFunctionMutation] = []
        let count = mwx_scene_quickjs_owner_material_function_count(handle)
        for index in 0..<count {
            var effectIndex: UInt32 = 0
            var name = [CChar](repeating: 0, count: 128)
            var mutationDiagnostic = [CChar](repeating: 0, count: 256)
            let mutationResult = mwx_scene_quickjs_owner_material_function_at(
                handle,
                index,
                &effectIndex,
                &name,
                name.count,
                &mutationDiagnostic,
                mutationDiagnostic.count
            )
            guard mutationResult == MWX_SCENE_QUICKJS_OK else {
                return .failure(Self.failure(
                    raw: mutationResult,
                    diagnostic: Self.diagnostic(mutationDiagnostic)
                ))
            }
            let nameBytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let functionName = String(decoding: nameBytes, as: UTF8.self)
            guard !functionName.isEmpty,
                  case let .effectConstant(layerID, _, _, _) = target else {
                return .failure(.invalidArgument("material function owner identity unavailable"))
            }
            mutations.append(.init(
                layerID: layerID,
                effectIndex: Int(effectIndex),
                functionName: functionName
            ))
        }
        return .success(.init(
            value: .scalar(output),
            materialFunctionMutations: mutations
        ))
    }

    func invalidate() {
        mwx_scene_quickjs_owner_invalidate(handle)
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
    fileprivate let handle: OpaquePointer
    let budget: SceneScriptScalarBudget

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
        mwx_scene_quickjs_domain_destroy(handle)
    }

    fileprivate func resetBudget(_ interruptBudget: UInt64) {
        mwx_scene_quickjs_domain_reset_budget(handle, interruptBudget)
    }

    private static func diagnostic(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
