import Foundation

/// Session validates the captured grant and owns all irreversible action
/// budgets. The VM only relays this synchronous native result.
typealias SceneScriptUserShortcutDispatch = @Sendable (
    ScenePlaybackShortcutGesture, String
) -> Int32

nonisolated enum SceneScriptUserShortcutBridge {
    private final class Context {
        let gesture: ScenePlaybackShortcutGesture
        let dispatch: SceneScriptUserShortcutDispatch

        init(gesture: ScenePlaybackShortcutGesture,
             dispatch: @escaping SceneScriptUserShortcutDispatch) {
            self.gesture = gesture
            self.dispatch = dispatch
        }
    }

    static func withScope<Result>(
        owner: OpaquePointer,
        gesture: ScenePlaybackShortcutGesture?,
        dispatch: SceneScriptUserShortcutDispatch?,
        body: () -> Result
    ) -> Result {
        let context = gesture.flatMap { gesture in
            dispatch.map { Context(gesture: gesture, dispatch: $0) }
        }
        if let context {
            mwx_scene_quickjs_owner_set_user_shortcut_dispatch(owner, { opaque, key, length in
                guard let opaque, let key,
                      let propertyKey = String(bytes: UnsafeBufferPointer(
                        start: UnsafeRawPointer(key).assumingMemoryBound(to: UInt8.self),
                        count: length), encoding: .utf8) else { return -1 }
                let context = Unmanaged<Context>.fromOpaque(opaque).takeUnretainedValue()
                return context.dispatch(context.gesture, propertyKey)
            }, Unmanaged.passUnretained(context).toOpaque())
        }
        defer { mwx_scene_quickjs_owner_set_user_shortcut_dispatch(owner, nil, nil) }
        return withExtendedLifetime(context, body)
    }
}
