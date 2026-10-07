import Foundation

/// Native mirror and journal for the prepared animation-layer owner. Playback
/// positions and end events remain owned by the launch's Puppet runtime.
nonisolated enum SceneScriptPuppetAnimationBridge {
    static func configure(owner: OpaquePointer, identity: ScenePuppetAnimationIdentity) throws {
        guard identity.layerID >= 0, let index = UInt32(exactly: identity.animationLayerIndex) else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument("invalid Puppet animation identity")
        }
        var diagnostic = [CChar](repeating: 0, count: 512)
        let raw = mwx_scene_quickjs_owner_configure_puppet_animation(
            owner, Int64(identity.layerID), index, Int64(identity.animationLayerID ?? 0),
            identity.animationLayerID == nil ? 0 : 1, &diagnostic, diagnostic.count)
        guard raw == MWX_SCENE_QUICKJS_OK else { throw failure(raw, diagnostic) }
    }

    static func commands(owner: OpaquePointer) -> Result<[ScenePuppetAnimationCommand], SceneScriptScalarRuntimeFailure> {
        let count = mwx_scene_quickjs_owner_puppet_animation_command_count(owner)
        guard count <= 64 else { return .failure(.mutationOverflow("Puppet animation command budget exceeded")) }
        var commands: [ScenePuppetAnimationCommand] = []
        for index in 0..<count {
            var raw = MWXSceneQuickJSPuppetAnimationCommand()
            var diagnostic = [CChar](repeating: 0, count: 512)
            let result = mwx_scene_quickjs_owner_puppet_animation_command_at(owner, index, &raw, &diagnostic, diagnostic.count)
            guard result == MWX_SCENE_QUICKJS_OK else { return .failure(failure(result, diagnostic)) }
            guard let layerID = Int(exactly: raw.layer_id),
                  let authoredIndex = Int(exactly: raw.animation_layer_index),
                  raw.has_animation_layer_id <= 1, raw.callback_epoch > 0,
                  raw.value.isFinite else { return .failure(.invalidArgument("invalid Puppet animation command")) }
            let animationLayerID: Int?
            if raw.has_animation_layer_id == 1 {
                guard let id = Int(exactly: raw.animation_layer_id) else { return .failure(.invalidArgument("invalid animation layer ID")) }
                animationLayerID = id
            } else { animationLayerID = nil }
            let action: ScenePuppetAnimationCommand.Action
            switch raw.action {
            case 0: action = .play
            case 1: action = .pause
            case 2: action = .stop
            case 3: action = .setFrame(raw.value)
            case 4: action = .setRate(raw.value)
            case 5: action = .setBlend(raw.value)
            case 6:
                guard raw.value == 0 || raw.value == 1 else { return .failure(.invalidArgument("invalid animation visibility")) }
                action = .setVisible(raw.value == 1)
            default: return .failure(.invalidArgument("unknown Puppet animation command"))
            }
            commands.append(.init(identity: .init(layerID: layerID, animationLayerIndex: authoredIndex,
                animationLayerID: animationLayerID), action: action,
                callbackEpoch: raw.callback_epoch, ordinal: raw.ordinal))
        }
        return .success(commands)
    }

    static func failure(_ raw: MWXSceneQuickJSResult, _ diagnostic: [CChar]) -> SceneScriptScalarRuntimeFailure {
        let message = String(decoding: diagnostic.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return switch raw {
        case MWX_SCENE_QUICKJS_MEMORY_EXCEEDED: .memoryExceeded(message)
        case MWX_SCENE_QUICKJS_MUTATION_OVERFLOW: .mutationOverflow(message)
        case MWX_SCENE_QUICKJS_STALE_OWNER: .staleOwner
        case MWX_SCENE_QUICKJS_DISABLED: .disabled(message)
        default: .invalidArgument(message)
        }
    }
}

extension SceneScriptQuickJSDomain {
    /// Installed after owner construction and before init; ordinary frames
    /// replace only this mirror, never advance an independent native clock.
    func publishPuppetAnimationSnapshot(_ snapshots: [ScenePuppetAnimationSnapshot]) throws {
        guard mwx_scene_quickjs_domain_puppet_animation_owner_count(handle) > 0 else { return }
        // Invalid optional metadata excludes only that animation owner. The C
        // mirror marks it unavailable; unrelated script owners still publish.
        let validSnapshots = snapshots.filter {
            $0.name.utf8.count <= 1024 && !$0.name.utf8.contains(0)
                && UInt32(exactly: $0.identity.animationLayerIndex) != nil
        }
        let names: [UnsafeMutablePointer<CChar>?] = validSnapshots.map { strdup($0.name) }
        defer { names.forEach { free($0) } }
        guard names.allSatisfy({ $0 != nil }) else {
            throw SceneScriptScalarRuntimeFailure.memoryExceeded("Puppet animation snapshot names")
        }
        var rawSnapshots: [MWXSceneQuickJSPuppetAnimationSnapshot] = []
        for (index, snapshot) in validSnapshots.enumerated() {
            guard let authoredIndex = UInt32(exactly: snapshot.identity.animationLayerIndex),
                  snapshot.name.utf8.count <= 1024, !snapshot.name.utf8.contains(0) else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument("invalid Puppet animation snapshot identity")
            }
            var raw = MWXSceneQuickJSPuppetAnimationSnapshot()
            raw.layer_id = Int64(snapshot.identity.layerID)
            raw.animation_layer_index = authoredIndex
            raw.animation_layer_id = Int64(snapshot.identity.animationLayerID ?? 0)
            raw.has_animation_layer_id = snapshot.identity.animationLayerID == nil ? 0 : 1
            raw.animation_id = Int64(snapshot.animationID)
            raw.name = names[index].map { UnsafePointer($0) }
            raw.fps = snapshot.framesPerSecond
            raw.frame_count = Double(snapshot.frameCount)
            raw.duration = snapshot.duration
            raw.current_frame = snapshot.currentFrame
            raw.rate = snapshot.rate
            raw.blend = snapshot.blend
            raw.is_playing = snapshot.isPlaying ? 1 : 0
            raw.visible = snapshot.visible ? 1 : 0
            raw.ended_sequence = snapshot.endedSequence
            raw.supports_ended_callbacks = snapshot.supportsEndedCallbacks ? 1 : 0
            raw.ended_failure = snapshot.endedFailure == nil ? 0 : 1
            rawSnapshots.append(raw)
        }
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = rawSnapshots.withUnsafeBufferPointer {
            mwx_scene_quickjs_domain_publish_puppet_animations(handle, $0.baseAddress, $0.count, &diagnostic, diagnostic.count)
        }
        guard result == MWX_SCENE_QUICKJS_OK else { throw SceneScriptPuppetAnimationBridge.failure(result, diagnostic) }
    }
}
