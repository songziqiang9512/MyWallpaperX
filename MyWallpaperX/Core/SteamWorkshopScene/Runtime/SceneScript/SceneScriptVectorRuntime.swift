import Foundation

nonisolated final class SceneScriptVectorOwner: @unchecked Sendable {
    let target: SceneDynamicTarget
    let generation: UInt64
    private let handle: OpaquePointer
    private let domain: SceneScriptQuickJSDomain
    private let budget: SceneScriptScalarBudget

    init(
        domain: SceneScriptQuickJSDomain,
        source: String,
        target: SceneDynamicTarget,
        generation: UInt64,
        budget: SceneScriptScalarBudget
    ) throws {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              generation > 0 else { throw SceneScriptScalarRuntimeFailure.invalidSource }
        self.domain = domain
        self.target = target
        self.generation = generation
        self.budget = budget
        var diagnostic = [CChar](repeating: 0, count: 512)
        let created = source.withCString {
            mwx_scene_quickjs_owner_create(
                domain.handle, $0, source.utf8.count, generation,
                &diagnostic, diagnostic.count
            )
        }
        guard let created else {
            throw Self.failure(MWX_SCENE_QUICKJS_COMPILE_ERROR, diagnostic)
        }
        handle = created
    }

    deinit { mwx_scene_quickjs_owner_destroy(handle) }

    func evaluate(
        input: SIMD3<Double>,
        frame: SceneScriptFrameInput,
        scriptPropertiesJSON: String,
        userPropertiesJSON: String,
        expectedGeneration: UInt64,
        interruptBudget: UInt64?
    ) -> Result<SceneDynamicValue, SceneScriptScalarRuntimeFailure> {
        guard input.x.isFinite, input.y.isFinite, input.z.isFinite else {
            return .failure(.invalidArgument("non-finite Vec3 input"))
        }
        guard expectedGeneration == generation else { return .failure(.staleOwner) }
        domain.resetBudget(interruptBudget ?? budget.interruptBudget)
        let source = [input.x, input.y, input.z]
        var output = [Double](repeating: 0, count: 3)
        var frameInput = MWXSceneQuickJSFrameInput(
            time_of_day: frame.timeOfDay,
            frame_time: frame.frameTime,
            runtime: frame.runtime
        )
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = source.withUnsafeBufferPointer { sourceBuffer in
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
        guard result == MWX_SCENE_QUICKJS_OK else {
            return .failure(Self.failure(result, diagnostic))
        }
        guard output.allSatisfy(\.isFinite) else {
            return .failure(.badReturn("non-finite Vec3 output"))
        }
        return .success(.vector3(output[0], output[1], output[2]))
    }

    func invalidate() { mwx_scene_quickjs_owner_invalidate(handle) }

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
