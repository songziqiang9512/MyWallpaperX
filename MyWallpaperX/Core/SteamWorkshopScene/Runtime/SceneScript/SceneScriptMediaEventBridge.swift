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

nonisolated struct SceneScriptMediaEventMutations: Equatable, Sendable {
    let materialFunctions: [SceneScriptMaterialFunctionMutation]
    let animations: [SceneTimelinePlaybackMutation]
}

nonisolated enum SceneScriptMediaEventBridge {
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
}
