import Foundation

/// Publishes the existing host-shared 16/32/64 spectrum snapshot into audio
/// registrations retained by one QuickJS owner. The JS Float32Array identities
/// stay stable; only their values are refreshed before that owner's callbacks.
nonisolated enum SceneScriptAudioHost {
    static func hasRegistration(owner: OpaquePointer) -> Bool {
        mwx_scene_quickjs_owner_audio_registration_count(owner) > 0
    }

    static func refresh(
        owner: OpaquePointer,
        ownerGeneration: UInt64,
        snapshot: SceneAudioSpectrumSnapshot
    ) -> Result<Void, SceneScriptScalarRuntimeFailure> {
        let inputs: [(UInt32, [Float], [Float])] = [
            (16, snapshot.left, snapshot.right),
            (32, snapshot.left32, snapshot.right32),
            (64, snapshot.left64, snapshot.right64),
        ]
        for (resolution, left, right) in inputs {
            var diagnostic = [CChar](repeating: 0, count: 512)
            let result = left.withUnsafeBufferPointer { leftBuffer in
                right.withUnsafeBufferPointer { rightBuffer in
                    mwx_scene_quickjs_owner_refresh_audio_resolution(
                        owner,
                        ownerGeneration,
                        resolution,
                        leftBuffer.baseAddress,
                        rightBuffer.baseAddress,
                        leftBuffer.count,
                        &diagnostic,
                        diagnostic.count
                    )
                }
            }
            guard result == MWX_SCENE_QUICKJS_OK else {
                return .failure(failure(result, diagnostic: diagnostic))
            }
        }
        return .success(())
    }

    private static func failure(
        _ raw: MWXSceneQuickJSResult,
        diagnostic: [CChar]
    ) -> SceneScriptScalarRuntimeFailure {
        let bytes = diagnostic.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let message = String(decoding: bytes, as: UTF8.self)
        return switch raw {
        case MWX_SCENE_QUICKJS_EXCEPTION: .exception(message)
        case MWX_SCENE_QUICKJS_BUDGET_EXCEEDED: .budgetExceeded(message)
        case MWX_SCENE_QUICKJS_MEMORY_EXCEEDED: .memoryExceeded(message)
        case MWX_SCENE_QUICKJS_DISABLED: .disabled(message)
        case MWX_SCENE_QUICKJS_STALE_OWNER: .staleOwner
        default: .invalidArgument(message)
        }
    }
}
