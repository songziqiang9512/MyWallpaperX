import Foundation

/// Lowers commands from the active owner's retained `getAnimation()` handle into mutations
/// for existing authored Timeline targets. Named handles carry only an index into
/// the compiled Program; playback remains owned by SceneTimelinePlaybackRuntime.
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
        target: SceneDynamicTarget,
        namedTargets: [SceneDynamicTarget] = []
    ) -> Result<[SceneTimelinePlaybackMutation], SceneScriptScalarRuntimeFailure> {
        var result: [SceneTimelinePlaybackMutation] = []
        let count = mwx_scene_quickjs_owner_animation_command_count(owner)
        for index in 0..<count {
            var command = MWX_SCENE_QUICKJS_ANIMATION_PLAY
            var targetIndex = UInt32.max
            var diagnostic = [CChar](repeating: 0, count: 256)
            let raw = mwx_scene_quickjs_owner_animation_command_at(
                owner,
                index,
                &command,
                &targetIndex,
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
            let resolvedTarget: SceneDynamicTarget
            if targetIndex == UInt32.max {
                resolvedTarget = target
            } else {
                guard namedTargets.indices.contains(Int(targetIndex)) else {
                    return .failure(.invalidArgument("named animation target is unavailable"))
                }
                resolvedTarget = namedTargets[Int(targetIndex)]
            }
            result.append(.init(target: resolvedTarget, command: typed))
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

nonisolated extension SceneScriptQuickJSDomain {
    /// Publishes only already-compiled targets; no second animation registry
    /// or playback state is reconstructed from the author document in a frame.
    func configureNamedAnimations(_ bindings: [(target: SceneDynamicTarget, name: String)]) throws {
        guard namedAnimationTargets == nil else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument("named animation catalog already configured")
        }
        var names: [UnsafeMutablePointer<CChar>] = []
        defer { names.forEach { free($0) } }
        var records: [MWXSceneQuickJSNamedAnimation] = []
        for (index, binding) in bindings.enumerated() {
            let layerID: Int
            switch binding.target {
            case let .layer(id, _), let .text(id, _): layerID = id
            default: continue
            }
            let name = binding.name
            guard !name.isEmpty,
                  name.utf8.count <= 256, !name.contains("\0") else { continue }
            guard let targetIndex = UInt32(exactly: index), let copied = strdup(name) else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument("named animation catalog allocation failed")
            }
            names.append(copied)
            records.append(.init(target_index: targetIndex, layer_id: Int64(layerID),
                name: UnsafePointer(copied), name_length: name.utf8.count))
        }
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = records.withUnsafeBufferPointer {
            mwx_scene_quickjs_domain_configure_named_animations(handle, $0.baseAddress,
                $0.count, &diagnostic, diagnostic.count)
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(String(cString: diagnostic))
        }
        namedAnimationTargets = bindings.map(\.target)
    }
}
