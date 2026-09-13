import Foundation

/// Shared ownership rule for authored scalar values that combine a Timeline
/// with a SceneScript attachment. Event-only animation controls may mutate the
/// existing Timeline playback state, but they do not become a second value
/// producer for the same target.
nonisolated enum SceneScriptValueOwnership {
    nonisolated static func isEventOnlyTimelineControl(
        source: String?,
        bindingKeys: [String],
        hasTimeline: Bool
    ) -> Bool {
        guard hasTimeline,
              bindingKeys == ["animation", "script", "value"],
              let source else { return false }
        let normalized = source.replacingOccurrences(
            of: "\\s+",
            with: "",
            options: .regularExpression
        )
        guard normalized.contains("exportfunctionmediaThumbnailChanged(") else {
            return false
        }
        return !normalized.contains("exportfunctionupdate(")
            && !normalized.contains("exportfunctioninit(")
    }
}
