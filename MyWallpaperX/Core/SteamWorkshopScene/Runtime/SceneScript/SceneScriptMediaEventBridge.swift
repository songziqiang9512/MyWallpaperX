import Foundation

/// Launch-frozen product authority for the migrated vector media-thumbnail
/// event profile. No state can revive the removed native color owner.
nonisolated enum SceneScriptVectorMediaRouteState: String, Equatable, Sendable {
    case preferGeneric = "prefer-generic"
    case genericOnly = "generic-only"
    case disableGeneric = "disable-generic"

    static let environmentKey = "MWX_SCENE_SCRIPT_VECTOR_MEDIA_ROUTE"

    static func resolve(_ rawValue: String?) -> Self? {
        guard let rawValue else { return .genericOnly }
        guard let requested = Self(rawValue: rawValue) else { return nil }
        switch requested {
        case .preferGeneric, .genericOnly:
            // The shared VM is already the sole product owner. A migration
            // toggle cannot silently restore the deleted native path.
            return .genericOnly
        case .disableGeneric:
            return requested
        }
    }

    func admittedVectorInputs(
        _ inputs: [SceneDynamicTarget: SceneDynamicValue],
        mediaOwnerTargets: Set<SceneDynamicTarget>
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        switch self {
        case .preferGeneric, .genericOnly:
            inputs
        case .disableGeneric:
            inputs.filter { !mediaOwnerTargets.contains($0.key) }
        }
    }

    func admittedVectorPassTargets(
        _ targets: Set<SceneDynamicTarget>,
        mediaOwnerTargets: Set<SceneDynamicTarget>
    ) -> Set<SceneDynamicTarget> {
        switch self {
        case .preferGeneric, .genericOnly:
            targets
        case .disableGeneric:
            targets.subtracting(mediaOwnerTargets)
        }
    }

    func authoredFallbackDefinitions(
        _ definitions: [SceneDynamicTargetDefinition],
        mediaOwnerTargets: Set<SceneDynamicTarget>
    ) -> [SceneDynamicTargetDefinition] {
        guard self == .disableGeneric else { return [] }
        return definitions.filter { definition in
            mediaOwnerTargets.contains(definition.target)
        }
    }
}

nonisolated struct SceneScriptMediaThumbnailEventInput: Equatable, Sendable {
    let hasThumbnail: Bool
    let primaryColor: SIMD3<Double>
    let secondaryColor: SIMD3<Double>
    let tertiaryColor: SIMD3<Double>
    let textColor: SIMD3<Double>
    let highContrastColor: SIMD3<Double>
    let generation: UInt64

    init(
        hasThumbnail: Bool,
        primaryColor: SIMD3<Double> = .zero,
        secondaryColor: SIMD3<Double> = .zero,
        tertiaryColor: SIMD3<Double> = .zero,
        textColor: SIMD3<Double> = .zero,
        highContrastColor: SIMD3<Double> = .zero,
        generation: UInt64
    ) {
        self.hasThumbnail = hasThumbnail
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.tertiaryColor = tertiaryColor
        self.textColor = textColor
        self.highContrastColor = highContrastColor
        self.generation = generation
    }

    init?(snapshot: SceneMediaThumbnailInbox.Snapshot) {
        guard snapshot.generation > 0 else { return nil }
        hasThumbnail = snapshot.current != nil
        primaryColor = snapshot.primaryColor ?? .zero
        secondaryColor = snapshot.secondaryColor ?? .zero
        tertiaryColor = snapshot.tertiaryColor ?? .zero
        textColor = snapshot.textColor ?? .zero
        highContrastColor = snapshot.highContrastColor ?? .zero
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

nonisolated protocol SceneScriptGeneratedEvent: Equatable, Sendable {
    var generation: UInt64 { get }
}

extension SceneScriptMediaThumbnailEventInput: SceneScriptGeneratedEvent {}
extension SceneScriptMediaPlaybackEventInput: SceneScriptGeneratedEvent {}
extension SceneScriptMediaPropertiesEventInput: SceneScriptGeneratedEvent {}

nonisolated enum SceneScriptOwnerExportBridge {
    static func contains(_ name: String, owner: OpaquePointer) throws -> Bool {
        guard !name.isEmpty, name.utf8.count <= 128 else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                "invalid SceneScript callback export name"
            )
        }
        var available: UInt32 = 0
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = name.withCString {
            mwx_scene_quickjs_owner_has_function(
                owner, $0, name.utf8.count,
                &available, &diagnostic, diagnostic.count
            )
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            throw failure(result, diagnostic: diagnostic)
        }
        guard available <= 1 else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                "invalid SceneScript callback export availability"
            )
        }
        return available == 1
    }

    private static func failure(
        _ raw: MWXSceneQuickJSResult,
        diagnostic buffer: [CChar]
    ) -> SceneScriptScalarRuntimeFailure {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let diagnostic = String(decoding: bytes, as: UTF8.self)
        return switch raw {
        case MWX_SCENE_QUICKJS_COMPILE_ERROR: .compile(diagnostic)
        case MWX_SCENE_QUICKJS_EXCEPTION: .exception(diagnostic)
        case MWX_SCENE_QUICKJS_BUDGET_EXCEEDED: .budgetExceeded(diagnostic)
        case MWX_SCENE_QUICKJS_MEMORY_EXCEEDED: .memoryExceeded(diagnostic)
        case MWX_SCENE_QUICKJS_BAD_RETURN: .badReturn(diagnostic)
        case MWX_SCENE_QUICKJS_DISABLED: .disabled(diagnostic)
        case MWX_SCENE_QUICKJS_STALE_OWNER: .staleOwner
        case MWX_SCENE_QUICKJS_MUTATION_OVERFLOW: .mutationOverflow(diagnostic)
        default: .invalidArgument(diagnostic)
        }
    }
}

/// Program-level input watermark. Equal generation/payload remains observable
/// so an owner that was not eligible on the first frame can retry; generation
/// zero, stale input, and same-generation payload conflicts never reach JS.
nonisolated struct SceneScriptObservedEvent<Event: SceneScriptGeneratedEvent>:
    Sendable {
    private var latest: Event?

    mutating func observe(_ event: Event?) -> Event? {
        guard let event, event.generation > 0 else { return nil }
        guard let latest else {
            self.latest = event
            return event
        }
        if event.generation > latest.generation {
            self.latest = event
            return event
        }
        guard event.generation == latest.generation, event == latest else {
            return nil
        }
        return event
    }
}

nonisolated struct SceneScriptMediaEventMutations: Equatable, Sendable {
    let materialFunctions: [SceneScriptMaterialFunctionMutation]
    let animations: [SceneTimelinePlaybackMutation]
    let layers: [SceneScriptLayerMutation]
}

nonisolated enum SceneScriptCursorEventKind:
    CaseIterable, Equatable, Hashable, Sendable {
    case enter
    case leave
    case down
    case move
    case up
    case click

    var callbackName: String {
        switch self {
        case .enter: "cursorEnter"
        case .leave: "cursorLeave"
        case .down: "cursorDown"
        case .move: "cursorMove"
        case .up: "cursorUp"
        case .click: "cursorClick"
        }
    }
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
        case .down: MWX_SCENE_QUICKJS_CURSOR_DOWN
        case .move: MWX_SCENE_QUICKJS_CURSOR_MOVE
        case .up: MWX_SCENE_QUICKJS_CURSOR_UP
        case .click: MWX_SCENE_QUICKJS_CURSOR_CLICK
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
        guard event.primaryColor.isNormalizedColor,
              event.secondaryColor.isNormalizedColor,
              event.tertiaryColor.isNormalizedColor,
              event.textColor.isNormalizedColor,
              event.highContrastColor.isNormalizedColor else {
            return .failure(.invalidArgument("invalid media thumbnail colors"))
        }
        var rawEvent = MWXSceneQuickJSMediaThumbnailEvent(
            has_thumbnail: event.hasThumbnail ? 1 : 0,
            primary_red: event.primaryColor.x,
            primary_green: event.primaryColor.y,
            primary_blue: event.primaryColor.z,
            secondary_red: event.secondaryColor.x,
            secondary_green: event.secondaryColor.y,
            secondary_blue: event.secondaryColor.z,
            tertiary_red: event.tertiaryColor.x,
            tertiary_green: event.tertiaryColor.y,
            tertiary_blue: event.tertiaryColor.z,
            text_red: event.textColor.x,
            text_green: event.textColor.y,
            text_blue: event.textColor.z,
            high_contrast_red: event.highContrastColor.x,
            high_contrast_green: event.highContrastColor.y,
            high_contrast_blue: event.highContrastColor.z
        )
        var rawFrame = frame.quickJSValue
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
        var rawFrame = frame.quickJSValue
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
        var rawFrame = frame.quickJSValue
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
        let layers: [SceneScriptLayerMutation]
        switch SceneScriptLayerMutationBridge.mutations(owner: owner) {
        case let .success(value): layers = value
        case let .failure(failure): return .failure(failure)
        }
        return .success(.init(
            materialFunctions: materialFunctions,
            animations: animations,
            layers: layers
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
        frame.quickJSValue
    }
}

private nonisolated extension SIMD3 where Scalar == Double {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite }

    var isNormalizedColor: Bool {
        allFinite && (0...1).contains(x) && (0...1).contains(y)
            && (0...1).contains(z)
    }
}
