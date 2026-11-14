import Foundation

/// Lowers commands from the active owner's retained `getAnimation()` handle into mutations
/// for existing authored Timeline targets. Named handles carry only an index into
/// the compiled Program; playback remains owned by SceneTimelinePlaybackRuntime.
nonisolated enum SceneScriptAnimationHandleBridge {
    /// Owner admission is settled before restoring the shared domain's actual
    /// callback order; preview and commit must consume the same command sequence.
    static func orderedMutations(in effects: [SceneScriptOwnerEffects]) -> [SceneTimelinePlaybackMutation] {
        effects.flatMap(\.animationMutations).sorted {
            if $0.callbackEpoch != $1.callbackEpoch { return $0.callbackEpoch < $1.callbackEpoch }
            return $0.ordinal < $1.ordinal
        }
    }

    static func configure(
        owner: OpaquePointer, target: SceneDynamicTarget, hasCurrentAnimation: Bool
    ) throws {
        let effectIndex: UInt32
        let passIndex: UInt32
        if case let .effectConstant(_, effect, pass, _) = target {
            effectIndex = UInt32(effect)
            passIndex = UInt32(pass)
        } else {
            guard hasCurrentAnimation else { return }
            effectIndex = .max
            passIndex = .max
        }
        var diagnostic = [CChar](repeating: 0, count: 256)
        let raw = mwx_scene_quickjs_owner_configure_animation_target(
            owner,
            hasCurrentAnimation ? 1 : 0,
            effectIndex,
            passIndex,
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
            var frame = 0.0
            var callbackEpoch: UInt64 = 0
            var ordinal: UInt32 = 0
            var diagnostic = [CChar](repeating: 0, count: 256)
            let raw = mwx_scene_quickjs_owner_animation_command_at(
                owner,
                index,
                &command,
                &targetIndex,
                &frame,
                &callbackEpoch,
                &ordinal,
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
            case MWX_SCENE_QUICKJS_ANIMATION_SET_FRAME: typed = .setFrame(frame)
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
            result.append(.init(target: resolvedTarget, command: typed,
                callbackEpoch: callbackEpoch, ordinal: ordinal))
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
    func publishAnimationEvents(
        _ puppetEvents: [ScenePuppetAnimationEventOccurrence],
        failures: [ScenePuppetAnimationIdentity: ScenePuppetAnimationEventFailure],
        timelineEvents: [SceneTimelineAnimationEventOccurrence]
    ) throws {
        guard !puppetEvents.isEmpty || !failures.isEmpty || !timelineEvents.isEmpty else { return }
        guard mwx_scene_quickjs_domain_animation_owner_count(handle) > 0 else { return }
        var names: [UnsafeMutablePointer<CChar>] = []
        defer { names.forEach { free($0) } }
        func record(_ identity: ScenePuppetAnimationIdentity) throws -> MWXSceneQuickJSAnimationEvent {
            guard identity.layerID >= 0,
                  let index = UInt32(exactly: identity.animationLayerIndex) else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument("invalid Puppet event identity")
            }
            var raw = MWXSceneQuickJSAnimationEvent()
            raw.source_kind = 1
            raw.layer_id = Int64(identity.layerID)
            raw.animation_layer_index = index
            raw.animation_layer_id = Int64(identity.animationLayerID ?? 0)
            raw.has_animation_layer_id = identity.animationLayerID == nil ? 0 : 1
            return raw
        }
        var records: [MWXSceneQuickJSAnimationEvent] = []
        for event in puppetEvents {
            var raw = try record(event.identity)
            if event.sequence == 0 || event.name.isEmpty || event.name.utf8.count > 1024
                || event.name.utf8.contains(0) || event.frame < 0
                || event.frame > 9_007_199_254_740_991 {
                raw.failure = 2
            } else {
                guard let name = strdup(event.name) else {
                    throw SceneScriptScalarRuntimeFailure.memoryExceeded("animation event payload")
                }
                names.append(name)
                raw.sequence = event.sequence
                raw.name = UnsafePointer(name)
                raw.frame = Double(event.frame)
            }
            records.append(raw)
        }
        for (identity, failure) in failures.sorted(by: {
            if $0.key.layerID != $1.key.layerID { return $0.key.layerID < $1.key.layerID }
            return $0.key.animationLayerIndex < $1.key.animationLayerIndex
        }) {
            var raw = try record(identity)
            switch failure {
            case .unsupportedMode: raw.failure = 1
            case .invalidEvent: raw.failure = 2
            case .nonFinitePhase: raw.failure = 3
            case .multipleLoopsCrossed: raw.failure = 4
            case .eventBudgetExceeded: raw.failure = 5
            case .sequenceOverflow: raw.failure = 6
            }
            records.append(raw)
        }
        for event in timelineEvents {
            guard let layerID = SceneScriptLayerMutationBridge.layerID(for: event.target) else { continue }
            guard let name = strdup(event.name) else {
                throw SceneScriptScalarRuntimeFailure.memoryExceeded("animation event payload")
            }
            names.append(name)
            var raw = MWXSceneQuickJSAnimationEvent()
            raw.layer_id = Int64(layerID)
            raw.name = UnsafePointer(name)
            raw.frame = event.frame
            records.append(raw)
        }
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = records.withUnsafeBufferPointer {
            mwx_scene_quickjs_domain_publish_animation_events(
                handle, $0.baseAddress, $0.count, &diagnostic, diagnostic.count)
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            throw SceneScriptPuppetAnimationBridge.failure(result, diagnostic)
        }
    }

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
            let sceneOnly: UInt32
            let effectIndex: UInt32
            let passIndex: UInt32
            switch binding.target {
            case let .layer(id, _), let .text(id, _):
                layerID = id
                sceneOnly = 0
                effectIndex = 0
                passIndex = 0
            case let .effectConstant(id, effect, pass, _):
                layerID = id
                sceneOnly = 1
                effectIndex = UInt32(effect)
                passIndex = UInt32(pass)
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
                name: UnsafePointer(copied), name_length: name.utf8.count,
                scene_only: sceneOnly, effect_index: effectIndex, pass_index: passIndex))
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
