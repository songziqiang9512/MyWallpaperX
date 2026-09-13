import os

/// Always-on thin facade over OSSignposter for Scene runtime timing.
/// Zero abstraction layers by contract: static calls only — no protocols,
/// no registry, no gating; each call is a single signpost emit.
nonisolated enum SceneSignpost {
    private static let signposter = OSSignposter(
        subsystem: "com.songziqiang.MyWallpaperX.scene",
        category: "performance"
    )

    static func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    static func endInterval(
        _ name: StaticString, _ state: OSSignpostIntervalState
    ) {
        signposter.endInterval(name, state)
    }

    static func emitEvent(_ name: StaticString, _ message: String? = nil) {
        if let message {
            signposter.emitEvent(name, "\(message, privacy: .public)")
        } else {
            signposter.emitEvent(name)
        }
    }
}
