import Foundation

extension SceneScriptQuickJSDomain {
    func beginSharedFrameTransaction() -> SceneScriptScalarRuntimeFailure? {
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = mwx_scene_quickjs_domain_begin_shared_frame_transaction(
            handle, &diagnostic, diagnostic.count
        )
        guard result != MWX_SCENE_QUICKJS_OK else { return nil }
        return Self.failure(result, Self.sharedTransactionDiagnostic(diagnostic))
    }
    func commitSharedFrameTransaction() {
        mwx_scene_quickjs_domain_commit_shared_frame_transaction(handle)
    }
    func discardSharedFrameTransaction() -> SceneScriptScalarRuntimeFailure? {
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = mwx_scene_quickjs_domain_discard_shared_frame_transaction(
            handle, &diagnostic, diagnostic.count
        )
        guard result != MWX_SCENE_QUICKJS_OK else { return nil }
        return Self.failure(result, Self.sharedTransactionDiagnostic(diagnostic))
    }
    private static func failure(
        _ raw: MWXSceneQuickJSResult,
        _ diagnostic: String
    ) -> SceneScriptScalarRuntimeFailure {
        switch raw {
        case MWX_SCENE_QUICKJS_COMPILE_ERROR: .compile(diagnostic)
        case MWX_SCENE_QUICKJS_EXCEPTION: .exception(diagnostic)
        case MWX_SCENE_QUICKJS_BUDGET_EXCEEDED: .budgetExceeded(diagnostic)
        case MWX_SCENE_QUICKJS_MEMORY_EXCEEDED: .memoryExceeded(diagnostic)
        case MWX_SCENE_QUICKJS_BAD_RETURN: .badReturn(diagnostic)
        case MWX_SCENE_QUICKJS_DISABLED: .disabled(diagnostic)
        case MWX_SCENE_QUICKJS_STALE_OWNER: .staleOwner
        case MWX_SCENE_QUICKJS_MUTATION_OVERFLOW:
            .mutationOverflow(diagnostic)
        default: .invalidArgument(diagnostic)
        }
    }
    private static func sharedTransactionDiagnostic(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
