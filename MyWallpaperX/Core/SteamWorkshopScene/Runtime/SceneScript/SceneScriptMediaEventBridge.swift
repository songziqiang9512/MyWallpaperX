import Foundation

nonisolated struct SceneScriptMediaThumbnailEventInput: Equatable, Sendable {
    let hasThumbnail: Bool
    let generation: UInt64

    init(hasThumbnail: Bool, generation: UInt64) {
        self.hasThumbnail = hasThumbnail
        self.generation = generation
    }

    init?(snapshot: SceneMediaThumbnailInbox.Snapshot) {
        guard snapshot.generation > 0 else { return nil }
        hasThumbnail = snapshot.current != nil
        generation = snapshot.generation
    }
}

nonisolated struct SceneScriptMediaPlaybackEventInput: Equatable, Sendable {
    let state: Int
    let generation: UInt64

    init(state: Int, generation: UInt64) {
        self.state = state
        self.generation = generation
    }

    init?(snapshot: SceneMediaThumbnailInbox.Snapshot) {
        guard snapshot.playbackGeneration > 0,
              let state = snapshot.playbackState,
              (0...2).contains(state) else { return nil }
        self.state = state
        generation = snapshot.playbackGeneration
    }
}

nonisolated struct SceneScriptMediaPropertiesEventInput: Equatable, Sendable {
    let title: String
    let artist: String
    let generation: UInt64

    init(title: String, artist: String, generation: UInt64) {
        self.title = title
        self.artist = artist
        self.generation = generation
    }

    init?(snapshot: SceneMediaThumbnailInbox.Snapshot) {
        guard snapshot.propertiesGeneration > 0,
              let properties = snapshot.properties else { return nil }
        title = properties.title
        artist = properties.artist
        generation = snapshot.propertiesGeneration
    }
}

nonisolated struct SceneScriptMediaEventMutations: Equatable, Sendable {
    let materialFunctions: [SceneScriptMaterialFunctionMutation]
    let animations: [SceneTimelinePlaybackMutation]
}

nonisolated enum SceneScriptCursorEventKind: Equatable, Sendable {
    case enter
    case leave
}

nonisolated struct SceneScriptCursorEventInput: Equatable, Sendable {
    let kind: SceneScriptCursorEventKind
    let layerID: Int
    let worldPosition: SIMD3<Double>
    let localPosition: SIMD3<Double>
}

nonisolated enum SceneScriptMediaEventBridge {
    static func dispatchUserProperties(
        owner: OpaquePointer,
        target: SceneDynamicTarget,
        layerID: Int,
        ownerGeneration: UInt64,
        changedPropertiesJSON: String,
        scriptPropertiesJSON: String,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        guard !changedPropertiesJSON.isEmpty,
              changedPropertiesJSON.utf8.count <= 65_536 else {
            return .failure(.invalidArgument("invalid user properties payload"))
        }
        var rawFrame = rawFrame(frame)
        var diagnostic = [CChar](repeating: 0, count: 512)
        let raw = changedPropertiesJSON.withCString { changed in
            scriptPropertiesJSON.withCString { scriptProperties in
                userPropertiesJSON.withCString { userProperties in
                    mwx_scene_quickjs_owner_dispatch_user_properties(
                        owner,
                        ownerGeneration,
                        changed,
                        changedPropertiesJSON.utf8.count,
                        scriptProperties,
                        scriptPropertiesJSON.utf8.count,
                        &rawFrame,
                        userProperties,
                        userPropertiesJSON.utf8.count,
                        &diagnostic,
                        diagnostic.count
                    )
                }
            }
        }
        guard raw == MWX_SCENE_QUICKJS_OK else {
            return .failure(failure(raw, diagnostic))
        }
        return mutations(owner: owner, target: target, layerID: layerID)
    }

    static func dispatchCursor(
        owner: OpaquePointer,
        target: SceneDynamicTarget,
        ownerGeneration: UInt64,
        event: SceneScriptCursorEventInput,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        guard event.layerID >= 0,
              event.worldPosition.allFinite,
              event.localPosition.allFinite else {
            return .failure(.invalidArgument("invalid cursor event payload"))
        }
        var rawEvent = MWXSceneQuickJSCursorEvent(
            world_x: event.worldPosition.x,
            world_y: event.worldPosition.y,
            world_z: event.worldPosition.z,
            local_x: event.localPosition.x,
            local_y: event.localPosition.y,
            local_z: event.localPosition.z
        )
        var rawFrame = rawFrame(frame)
        var diagnostic = [CChar](repeating: 0, count: 512)
        let kind = switch event.kind {
        case .enter: MWX_SCENE_QUICKJS_CURSOR_ENTER
        case .leave: MWX_SCENE_QUICKJS_CURSOR_LEAVE
        }
        let raw = userPropertiesJSON.withCString { userProperties in
            mwx_scene_quickjs_owner_dispatch_cursor(
                owner,
                ownerGeneration,
                kind,
                &rawEvent,
                &rawFrame,
                userProperties,
                userPropertiesJSON.utf8.count,
                &diagnostic,
                diagnostic.count
            )
        }
        guard raw == MWX_SCENE_QUICKJS_OK else {
            return .failure(failure(raw, diagnostic))
        }
        return mutations(
            owner: owner,
            target: target,
            layerID: event.layerID
        )
    }

    static func dispatchThumbnail(
        owner: OpaquePointer,
        target: SceneDynamicTarget,
        layerID: Int,
        ownerGeneration: UInt64,
        event: SceneScriptMediaThumbnailEventInput,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        var rawEvent = MWXSceneQuickJSMediaThumbnailEvent(
            has_thumbnail: event.hasThumbnail ? 1 : 0
        )
        var rawFrame = MWXSceneQuickJSFrameInput(
            time_of_day: frame.timeOfDay,
            frame_time: frame.frameTime,
            runtime: frame.runtime
        )
        var diagnostic = [CChar](repeating: 0, count: 512)
        let raw = userPropertiesJSON.withCString { userProperties in
            mwx_scene_quickjs_owner_dispatch_media_thumbnail(
                owner,
                ownerGeneration,
                &rawEvent,
                &rawFrame,
                userProperties,
                userPropertiesJSON.utf8.count,
                &diagnostic,
                diagnostic.count
            )
        }
        guard raw == MWX_SCENE_QUICKJS_OK else {
            return .failure(failure(raw, diagnostic))
        }
        return mutations(owner: owner, target: target, layerID: layerID)
    }

    static func dispatchPlayback(
        owner: OpaquePointer,
        target: SceneDynamicTarget,
        layerID: Int,
        ownerGeneration: UInt64,
        event: SceneScriptMediaPlaybackEventInput,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        guard (0...2).contains(event.state) else {
            return .failure(.invalidArgument("invalid media playback state"))
        }
        var rawEvent = MWXSceneQuickJSMediaPlaybackEvent(
            state: UInt32(event.state)
        )
        var rawFrame = MWXSceneQuickJSFrameInput(
            time_of_day: frame.timeOfDay,
            frame_time: frame.frameTime,
            runtime: frame.runtime
        )
        var diagnostic = [CChar](repeating: 0, count: 512)
        let raw = userPropertiesJSON.withCString { userProperties in
            mwx_scene_quickjs_owner_dispatch_media_playback(
                owner,
                ownerGeneration,
                &rawEvent,
                &rawFrame,
                userProperties,
                userPropertiesJSON.utf8.count,
                &diagnostic,
                diagnostic.count
            )
        }
        guard raw == MWX_SCENE_QUICKJS_OK else {
            return .failure(failure(raw, diagnostic))
        }
        return mutations(owner: owner, target: target, layerID: layerID)
    }

    static func dispatchProperties(
        owner: OpaquePointer,
        target: SceneDynamicTarget,
        layerID: Int,
        ownerGeneration: UInt64,
        event: SceneScriptMediaPropertiesEventInput,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        guard event.title.utf8.count <= 65_536,
              event.artist.utf8.count <= 65_536,
              !event.title.contains("\0"),
              !event.artist.contains("\0") else {
            return .failure(.invalidArgument("invalid media properties payload"))
        }
        var rawFrame = MWXSceneQuickJSFrameInput(
            time_of_day: frame.timeOfDay,
            frame_time: frame.frameTime,
            runtime: frame.runtime
        )
        var diagnostic = [CChar](repeating: 0, count: 512)
        let raw = event.title.withCString { title in
            event.artist.withCString { artist in
                var rawEvent = MWXSceneQuickJSMediaPropertiesEvent(
                    title: title,
                    title_length: event.title.utf8.count,
                    artist: artist,
                    artist_length: event.artist.utf8.count
                )
                return userPropertiesJSON.withCString { userProperties in
                    mwx_scene_quickjs_owner_dispatch_media_properties(
                        owner,
                        ownerGeneration,
                        &rawEvent,
                        &rawFrame,
                        userProperties,
                        userPropertiesJSON.utf8.count,
                        &diagnostic,
                        diagnostic.count
                    )
                }
            }
        }
        guard raw == MWX_SCENE_QUICKJS_OK else {
            return .failure(failure(raw, diagnostic))
        }
        return mutations(owner: owner, target: target, layerID: layerID)
    }

    private static func mutations(
        owner: OpaquePointer,
        target: SceneDynamicTarget,
        layerID: Int
    ) -> Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure> {
        let materialFunctions: [SceneScriptMaterialFunctionMutation]
        switch SceneScriptEffectHandleBridge.mutations(
            owner: owner,
            layerID: layerID
        ) {
        case let .success(value): materialFunctions = value
        case let .failure(failure): return .failure(failure)
        }
        let animations: [SceneTimelinePlaybackMutation]
        switch SceneScriptAnimationHandleBridge.mutations(
            owner: owner,
            target: target
        ) {
        case let .success(value): animations = value
        case let .failure(failure): return .failure(failure)
        }
        return .success(.init(
            materialFunctions: materialFunctions,
            animations: animations
        ))
    }

    private static func failure(
        _ raw: MWXSceneQuickJSResult,
        _ buffer: [CChar]
    ) -> SceneScriptScalarRuntimeFailure {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let diagnostic = String(decoding: bytes, as: UTF8.self)
        return switch raw {
        case MWX_SCENE_QUICKJS_EXCEPTION: .exception(diagnostic)
        case MWX_SCENE_QUICKJS_BUDGET_EXCEEDED: .budgetExceeded(diagnostic)
        case MWX_SCENE_QUICKJS_MEMORY_EXCEEDED: .memoryExceeded(diagnostic)
        case MWX_SCENE_QUICKJS_DISABLED: .disabled(diagnostic)
        case MWX_SCENE_QUICKJS_STALE_OWNER: .staleOwner
        case MWX_SCENE_QUICKJS_MUTATION_OVERFLOW: .mutationOverflow(diagnostic)
        default: .invalidArgument(diagnostic)
        }
    }

    private static func rawFrame(
        _ frame: SceneScriptFrameInput
    ) -> MWXSceneQuickJSFrameInput {
        MWXSceneQuickJSFrameInput(
            time_of_day: frame.timeOfDay,
            frame_time: frame.frameTime,
            runtime: frame.runtime
        )
    }
}

private nonisolated extension SIMD3 where Scalar == Double {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}
