import Foundation

/// Native mirror and journal for the prepared animation-layer owner. Playback
/// positions and end events remain owned by the launch's Puppet runtime.
nonisolated enum SceneScriptPuppetAnimationBridge {
    /// One preparation-time identity proof for nested Bool and Number owners.
    static func preparedBindingIdentity(
        _ binding: SceneScriptBindingIR, descriptor: SceneRenderDescriptor
    ) -> ScenePuppetAnimationIdentity? {
        guard binding.owner.kind == .animationLayer,
              binding.owner.effectIndex == nil, binding.owner.effectID == nil,
              binding.owner.passIndex == nil, binding.owner.passID == nil,
              let objectIndex = binding.owner.objectIndex,
              let layerID = binding.owner.objectID,
              let animationIndex = binding.owner.animationLayerIndex,
              let animationID = binding.owner.animationLayerID,
              descriptor.layers.indices.contains(objectIndex),
              binding.userPropertyKey == nil, let keys = binding.wrapperKeys,
              keys.contains("script"), keys.contains("value"),
              Set(keys).isSubset(of: ["script", "scriptproperties", "value"]),
              binding.targetPath == [.key("objects"), .index(objectIndex),
                  .key("animationlayers"), .index(animationIndex), .key(binding.targetKey)]
        else { return nil }
        let layer = descriptor.layers[objectIndex]
        guard layer.id == layerID, layer.layerIndex == objectIndex,
              layer.puppetAnimationLayers.indices.contains(animationIndex),
              layer.puppetAnimationLayers[animationIndex].id == animationID,
              layer.puppetAnimationLayers.filter({ $0.id == animationID }).count == 1
        else { return nil }
        let animation = layer.puppetAnimationLayers[animationIndex]
        switch (binding.targetKey, binding.valueType, binding.authoredValue) {
        case let ("visible", .boolean, .bool(value)?):
            guard animation.visible == value else { return nil }
        case let ("rate", .number, .number(value)?):
            guard animation.hasRateScript == true, animation.rateBinding == nil,
                  animation.rate?.bitPattern == value.bitPattern,
                  ScenePuppetAnimationCommand.acceptsScalarControl(value) else { return nil }
        default: return nil
        }
        return .init(layerID: layerID, animationLayerIndex: animationIndex,
            animationLayerID: animationID)
    }

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
    /// One cadence's native occurrences. The existing C owner retains pending
    /// payload through rejected publications; neither side advances a clock.
    func publishPuppetAnimationEvents(
        _ events: [ScenePuppetAnimationEventOccurrence],
        failures: [ScenePuppetAnimationIdentity: ScenePuppetAnimationEventFailure]
    ) throws {
        guard !events.isEmpty || !failures.isEmpty else { return }
        guard mwx_scene_quickjs_domain_puppet_animation_owner_count(handle) > 0 else { return }
        var names: [UnsafeMutablePointer<CChar>] = []
        defer { names.forEach { free($0) } }
        func record(_ identity: ScenePuppetAnimationIdentity) throws -> MWXSceneQuickJSPuppetAnimationEvent {
            guard identity.layerID >= 0,
                  let index = UInt32(exactly: identity.animationLayerIndex) else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument("invalid Puppet event identity")
            }
            var raw = MWXSceneQuickJSPuppetAnimationEvent()
            raw.layer_id = Int64(identity.layerID)
            raw.animation_layer_index = index
            raw.animation_layer_id = Int64(identity.animationLayerID ?? 0)
            raw.has_animation_layer_id = identity.animationLayerID == nil ? 0 : 1
            return raw
        }
        var records: [MWXSceneQuickJSPuppetAnimationEvent] = []
        for event in events {
            var raw = try record(event.identity)
            if event.sequence == 0 || event.name.isEmpty || event.name.utf8.count > 1024
                || event.name.utf8.contains(0) || event.frame < 0
                || event.frame > 9_007_199_254_740_991 {
                raw.failure = 2
            } else {
                guard let name = strdup(event.name) else {
                    throw SceneScriptScalarRuntimeFailure.memoryExceeded("Puppet event payload")
                }
                names.append(name)
                raw.sequence = event.sequence
                raw.name = UnsafePointer(name)
                raw.frame = Int64(event.frame)
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
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = records.withUnsafeBufferPointer {
            mwx_scene_quickjs_domain_publish_puppet_animation_events(
                handle, $0.baseAddress, $0.count, &diagnostic, diagnostic.count)
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            throw SceneScriptPuppetAnimationBridge.failure(result, diagnostic)
        }
    }

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
