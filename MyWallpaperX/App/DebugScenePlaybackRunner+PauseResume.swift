#if DEBUG
import Foundation

extension DebugScenePlaybackRunner {
    struct PauseResumeRequest {
        let delay: TimeInterval
        let dwell: TimeInterval
    }

    static let pauseResumeRequestEnvironmentKey =
        "MWX_SCENE_DEBUG_PAUSE_RESUME_AFTER"

    static func requestedPauseResumeRequest(
        duration: TimeInterval
    ) -> PauseResumeRequest? {
        guard let raw = ProcessInfo.processInfo.environment[
            pauseResumeRequestEnvironmentKey
        ] else { return nil }
        let values = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard values.count == 2,
              let delay = TimeInterval(values[0]), delay.isFinite,
              let dwell = TimeInterval(values[1]), dwell.isFinite,
              delay >= 1,
              dwell >= 1,
              delay + dwell < duration - 2 else { return nil }
        return PauseResumeRequest(delay: delay, dwell: dwell)
    }

    static func schedulePauseResume(
        request: PauseResumeRequest?,
        outputDirectory: URL
    ) {
        guard let request else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + request.delay) {
            let before = SceneDesktopWallpaperHost.shared.debugSnapshot()
            WallpaperEngine.shared.pauseAllPlayers()
            let paused = SceneDesktopWallpaperHost.shared.debugSnapshot()
            let pauseAccepted = before.surfaceCount > 0
                && before.surfaceCount == paused.surfaceCount
                && !before.isPlaybackPaused
                && before.isFrameDriverActive
                && paused.isPlaybackPaused
                && !paused.isFrameDriverActive
            NSLog(
                "MWX DEBUG SCENE: phase=pause-resume state=paused accepted=%@ surfacesBefore=%d surfacesAfter=%d pausedBefore=%@ pausedAfter=%@ timerBefore=%@ timerAfter=%@",
                pauseAccepted ? "true" : "false",
                before.surfaceCount,
                paused.surfaceCount,
                before.isPlaybackPaused ? "true" : "false",
                paused.isPlaybackPaused ? "true" : "false",
                before.isFrameDriverActive ? "active" : "inactive",
                paused.isFrameDriverActive ? "active" : "inactive"
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + request.dwell) {
                let beforeResume = SceneDesktopWallpaperHost.shared.debugSnapshot()
                WallpaperEngine.shared.resumeAllPlayers()
                let resumed = SceneDesktopWallpaperHost.shared.debugSnapshot()
                let resumeAccepted = pauseAccepted
                    && beforeResume.surfaceCount == paused.surfaceCount
                    && beforeResume.isPlaybackPaused
                    && !beforeResume.isFrameDriverActive
                    && resumed.surfaceCount == paused.surfaceCount
                    && !resumed.isPlaybackPaused
                    && resumed.isFrameDriverActive
                NSLog(
                    "MWX DEBUG SCENE: phase=pause-resume state=resumed accepted=%@ surfacesPaused=%d surfacesBeforeResume=%d surfacesAfterResume=%d pausedBeforeResume=%@ pausedAfterResume=%@ timerBeforeResume=%@ timerAfterResume=%@",
                    resumeAccepted ? "true" : "false",
                    paused.surfaceCount,
                    beforeResume.surfaceCount,
                    resumed.surfaceCount,
                    beforeResume.isPlaybackPaused ? "true" : "false",
                    resumed.isPlaybackPaused ? "true" : "false",
                    beforeResume.isFrameDriverActive ? "active" : "inactive",
                    resumed.isFrameDriverActive ? "active" : "inactive"
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    requestSnapshot(
                        reason: "pause-resume-after",
                        outputDirectory: outputDirectory
                    )
                }
            }
        }
    }
}
#endif
