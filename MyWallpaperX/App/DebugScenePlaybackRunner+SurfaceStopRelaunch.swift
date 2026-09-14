#if DEBUG
import Foundation

extension DebugScenePlaybackRunner {
    static let surfaceStopRelaunchDelayEnvironmentKey =
        "MWX_SCENE_DEBUG_SURFACE_STOP_RELAUNCH_AFTER"

    static func requestedSurfaceStopRelaunchDelay(
        duration: TimeInterval
    ) -> TimeInterval? {
        guard let raw = ProcessInfo.processInfo.environment[
            surfaceStopRelaunchDelayEnvironmentKey
        ], let delay = TimeInterval(raw), delay.isFinite,
              delay >= 1,
              delay < duration - 2.5 else { return nil }
        return delay
    }

    static func scheduleSurfaceStopRelaunch(
        delay: TimeInterval?,
        recordID: String,
        rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue],
        userPropertyTextureURLs: [String: URL],
        logURL: URL?,
        outputDirectory: URL
    ) {
        guard let delay else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let before = runtimeHost.debugSnapshot()
            runtimeHost.stop()
            let afterStop = runtimeHost.debugSnapshot()
            NSLog(
                "MWX DEBUG SCENE: phase=surface-stop-relaunch state=stopped surfacesBefore=%d surfacesAfter=%d",
                before.surfaceCount,
                afterStop.surfaceCount
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                do {
                    _ = try runtimeHost.launch(
                        rootURL: rootURL,
                        propertyOverrides: propertyOverrides,
                        userPropertyTextureURLs: userPropertyTextureURLs,
                        logURL: logURL,
                        recordID: recordID
                    )
                    runtimeHost.setPlaybackPaused(false)
                    let afterRelaunch = runtimeHost
                        .debugSnapshot()
                    NSLog(
                        "MWX DEBUG SCENE: phase=surface-stop-relaunch state=relaunched accepted=true surfacesBefore=%d surfacesAfterStop=%d surfacesAfterRelaunch=%d",
                        before.surfaceCount,
                        afterStop.surfaceCount,
                        afterRelaunch.surfaceCount
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        requestSnapshot(
                            reason: "surface-stop-relaunch-after",
                            outputDirectory: outputDirectory
                        )
                    }
                } catch {
                    let afterRelaunch = runtimeHost
                        .debugSnapshot()
                    NSLog(
                        "MWX DEBUG SCENE: phase=surface-stop-relaunch state=relaunched accepted=false surfacesBefore=%d surfacesAfterStop=%d surfacesAfterRelaunch=%d error=%@",
                        before.surfaceCount,
                        afterStop.surfaceCount,
                        afterRelaunch.surfaceCount,
                        error.localizedDescription
                    )
                }
            }
        }
    }
}
#endif
