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
        guard identity.layerID >= 0, let authoredIndex = identity.animationLayerIndex,
              let index = UInt32(exactly: authoredIndex) else {
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
            guard let target = identity(raw.identity), raw.callback_epoch > 0,
                  raw.value.isFinite else { return .failure(.invalidArgument("invalid Puppet animation command")) }
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
            case 7:
                guard let animationID = Int(exactly: raw.animation_id) else {
                    return .failure(.invalidArgument("invalid Single animation source ID"))
                }
                action = .createSingle(animationID: animationID)
            default: return .failure(.invalidArgument("unknown Puppet animation command"))
            }
            commands.append(.init(identity: target, action: action,
                callbackEpoch: raw.callback_epoch, ordinal: raw.ordinal))
        }
        return .success(commands)
    }

    static func wireIdentity(_ identity: ScenePuppetAnimationIdentity) -> MWXSceneQuickJSPuppetAnimationIdentity? {
        var raw = MWXSceneQuickJSPuppetAnimationIdentity()
        raw.layer_id = Int64(identity.layerID)
        switch identity.instance {
        case let .authored(index, id):
            guard let index = UInt32(exactly: index) else { return nil }
            raw.animation_layer_index = index
            raw.animation_layer_id = Int64(id ?? 0)
            raw.has_animation_layer_id = id == nil ? 0 : 1
        case let .created(epoch, ordinal):
            raw.kind = 1
            raw.creation_epoch = epoch
            raw.creation_ordinal = ordinal
        }
        return raw
    }

    static func identity(_ raw: MWXSceneQuickJSPuppetAnimationIdentity) -> ScenePuppetAnimationIdentity? {
        guard let layerID = Int(exactly: raw.layer_id) else { return nil }
        switch raw.kind {
        case 0:
            guard raw.has_animation_layer_id <= 1,
                  let index = Int(exactly: raw.animation_layer_index) else { return nil }
            return .init(layerID: layerID, animationLayerIndex: index,
                animationLayerID: raw.has_animation_layer_id == 1 ? Int(exactly: raw.animation_layer_id) : nil)
        case 1:
            guard raw.creation_epoch > 0 else { return nil }
            return .init(layerID: layerID, creationEpoch: raw.creation_epoch, creationOrdinal: raw.creation_ordinal)
        default: return nil
        }
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
    func bindPuppetAnimationSources(_ runtime: ScenePuppetAnimationPlaybackRuntime) {
        guard puppetAnimationSourceRuntime !== runtime else { return }
        puppetAnimationSourceRuntime = runtime
        mwx_scene_quickjs_domain_bind_puppet_animation_sources(handle,
            sceneScriptPuppetAnimationSourceLookup, Unmanaged.passUnretained(runtime).toOpaque())
    }

    /// Installed after owner construction and before init; ordinary frames
    /// replace only this mirror, never advance an independent native clock.
    func publishPuppetAnimationSnapshot(_ snapshots: [ScenePuppetAnimationSnapshot]) throws {
        // Optional invalid metadata makes only that target unavailable. Prepare
        // names and wire records once, including ordinary cross-layer callers.
        var names: [UnsafeMutablePointer<CChar>] = []
        defer { names.forEach { free($0) } }
        var rawSnapshots: [MWXSceneQuickJSPuppetAnimationSnapshot] = []
        rawSnapshots.reserveCapacity(snapshots.count)
        for snapshot in snapshots {
            guard let identity = SceneScriptPuppetAnimationBridge.wireIdentity(snapshot.identity),
                  snapshot.name.utf8.count <= 1024, !snapshot.name.utf8.contains(0) else { continue }
            guard let name = strdup(snapshot.name) else {
                throw SceneScriptScalarRuntimeFailure.memoryExceeded("Puppet animation snapshot names")
            }
            names.append(name)
            var raw = MWXSceneQuickJSPuppetAnimationSnapshot()
            raw.identity = identity
            raw.animation_id = Int64(snapshot.animationID)
            raw.name = UnsafePointer(name)
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

private nonisolated func sceneScriptPuppetAnimationSourceLookup(
    _ opaque: UnsafeMutableRawPointer?, _ layerID: Int64,
    _ name: UnsafePointer<CChar>?, _ nameLength: Int, _ animationID: Int64,
    _ source: UnsafeMutablePointer<MWXSceneQuickJSPuppetAnimationSource>?,
    _ sourceName: UnsafeMutablePointer<CChar>?, _ sourceNameCapacity: Int
) -> UInt32 {
    guard let opaque, let source, let sourceName else { return 0 }
    let runtime = Unmanaged<ScenePuppetAnimationPlaybackRuntime>.fromOpaque(opaque).takeUnretainedValue()
    let metadata: ScenePuppetSingleAnimationSourceMetadata?
    if let name {
        let bytes = UnsafeRawPointer(name).assumingMemoryBound(to: UInt8.self)
        metadata = runtime.singleAnimationSource(layerID: Int(layerID),
            name: String(decoding: UnsafeBufferPointer(start: bytes, count: nameLength), as: UTF8.self))
    } else {
        metadata = runtime.singleAnimationSource(layerID: Int(layerID), animationID: Int(animationID))
    }
    guard let metadata, metadata.name.utf8.count < sourceNameCapacity else { return 0 }
    source.pointee.animation_id = Int64(metadata.animationID)
    source.pointee.fps = metadata.framesPerSecond
    source.pointee.frame_count = Double(metadata.frameCount)
    source.pointee.duration = metadata.duration
    metadata.name.withCString { sourceName.update(from: $0, count: metadata.name.utf8.count + 1) }
    return 1
}
