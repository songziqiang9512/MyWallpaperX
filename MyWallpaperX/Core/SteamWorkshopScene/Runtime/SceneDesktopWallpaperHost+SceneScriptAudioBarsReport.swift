import Foundation

extension SceneDesktopWallpaperHost {
    /// Appends the bounded SceneScript audio-bars admission result after the
    /// texture report, which is written by `SceneMetalView`.
    nonisolated static func appendSceneScriptAudioBarsReport(
        to logURL: URL?,
        program: SceneScriptAudioBarsProgram
    ) {
        guard let logURL,
              let existing = try? String(contentsOf: logURL, encoding: .utf8) else {
            return
        }
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        try? (existing + separator + program.reportLines.joined(separator: "\n") + "\n")
            .write(to: logURL, atomically: true, encoding: .utf8)
    }
}
