import Foundation

/// Lowers callback-scoped `thisObject.getAnimation()` commands into mutations
/// for the existing authored Timeline target. The JS handle never carries or
/// invents a target identity.
nonisolated enum SceneScriptAnimationHandleBridge {
    static func configure(owner: OpaquePointer, hasCurrentAnimation: Bool) throws {
        guard hasCurrentAnimation else { return }
        var diagnostic = [CChar](repeating: 0, count: 256)
        let raw = mwx_scene_quickjs_owner_configure_current_animation(
            owner,
            1,
            &diagnostic,
            diagnostic.count
        )
        guard raw == MWX_SCENE_QUICKJS_OK else {
            throw failure(raw, diagnostic)
        }
    }

    static func mutations(
        owner: OpaquePointer,
        target: SceneDynamicTarget
    ) -> Result<[SceneTimelinePlaybackMutation], SceneScriptScalarRuntimeFailure> {
        var result: [SceneTimelinePlaybackMutation] = []
        let count = mwx_scene_quickjs_owner_animation_command_count(owner)
        for index in 0..<count {
            var command = MWX_SCENE_QUICKJS_ANIMATION_PLAY
            var diagnostic = [CChar](repeating: 0, count: 256)
            let raw = mwx_scene_quickjs_owner_animation_command_at(
                owner,
                index,
                &command,
                &diagnostic,
                diagnostic.count
            )
            guard raw == MWX_SCENE_QUICKJS_OK else {
                return .failure(failure(raw, diagnostic))
            }
            let typed: SceneTimelinePlaybackCommand
            switch command {
            case MWX_SCENE_QUICKJS_ANIMATION_PLAY: typed = .play
            case MWX_SCENE_QUICKJS_ANIMATION_PAUSE: typed = .pause
            case MWX_SCENE_QUICKJS_ANIMATION_STOP: typed = .stop
            default:
                return .failure(.invalidArgument("unknown animation command"))
            }
            result.append(.init(target: target, command: typed))
        }
        return .success(result)
    }

    private static func failure(
        _ raw: MWXSceneQuickJSResult,
        _ buffer: [CChar]
    ) -> SceneScriptScalarRuntimeFailure {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let diagnostic = String(decoding: bytes, as: UTF8.self)
        return switch raw {
        case MWX_SCENE_QUICKJS_MEMORY_EXCEEDED: .memoryExceeded(diagnostic)
        case MWX_SCENE_QUICKJS_MUTATION_OVERFLOW: .mutationOverflow(diagnostic)
        case MWX_SCENE_QUICKJS_STALE_OWNER: .staleOwner
        case MWX_SCENE_QUICKJS_DISABLED: .disabled(diagnostic)
        default: .invalidArgument(diagnostic)
        }
    }
}
