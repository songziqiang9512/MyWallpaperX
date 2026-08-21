#if DEBUG
import Foundation

extension DebugScenePlaybackRunner {
    struct SceneSwitchRequest {
        let delay: TimeInterval
        let rootURL: URL
        let usesAlternateRoot: Bool
    }

    static let sceneSwitchDelayEnvironmentKey =
        "MWX_SCENE_DEBUG_SCENE_SWITCH_AFTER"
    static let sceneSwitchRootEnvironmentKey =
        "MWX_SCENE_DEBUG_SCENE_SWITCH_ROOT"

    static func containsSceneSwitchRequest(
        in environment: [String: String]
    ) -> Bool {
        environment[sceneSwitchDelayEnvironmentKey] != nil
            || environment[sceneSwitchRootEnvironmentKey] != nil
    }

    static func requestedSceneSwitchRequest(
        duration: TimeInterval,
        currentRootURL: URL
    ) -> SceneSwitchRequest? {
        let environment = ProcessInfo.processInfo.environment
        guard containsSceneSwitchRequest(in: environment),
              let rawDelay = environment[sceneSwitchDelayEnvironmentKey],
              let delay = TimeInterval(rawDelay), delay.isFinite,
              delay >= 1,
              delay < duration - 2 else { return nil }

        let rootURL: URL
        if let rawRoot = environment[sceneSwitchRootEnvironmentKey] {
            let candidate = URL(fileURLWithPath: rawRoot, isDirectory: true)
                .resolvingSymlinksInPath().standardizedFileURL
            guard isIsolatedSampleRoot(candidate) else { return nil }
            rootURL = candidate
        } else {
            rootURL = currentRootURL
        }
        return SceneSwitchRequest(
            delay: delay,
            rootURL: rootURL,
            usesAlternateRoot: rootURL != currentRootURL
        )
    }

    static func logConfiguredSceneSwitch(_ request: SceneSwitchRequest?) {
        guard let request else { return }
        NSLog(
            "MWX DEBUG SCENE: phase=scene-switch state=configured delay=%.3f mode=%@ root=%@",
            request.delay,
            request.usesAlternateRoot ? "alternate-input" : "same-input",
            request.rootURL.path
        )
    }

    static func scheduleSceneSwitch(
        request: SceneSwitchRequest?,
        recordID: String,
        propertyOverrides: [String: SceneUserPropertyValue],
        logURL: URL?,
        outputDirectory: URL
    ) {
        guard let request else { return }
        let textureURLs = requestedUserPropertyTextureURLs(
            rootURL: request.rootURL
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + request.delay) {
            let before = SceneDesktopWallpaperHost.shared.debugSnapshot()
            do {
                let model = try SceneDesktopWallpaperHost.shared.launch(
                    rootURL: request.rootURL,
                    propertyOverrides: propertyOverrides,
                    userPropertyTextureURLs: textureURLs,
                    logURL: logURL,
                    recordID: recordID
                )
                WallpaperEngine.shared.resumeAllPlayers()
                let after = SceneDesktopWallpaperHost.shared.debugSnapshot()
                let layerIDs = model.renderDescriptor.layers.map(\.id)
                    .sorted().map(String.init).joined(separator: ",")
                NSLog(
                    "MWX DEBUG SCENE: phase=scene-switch state=triggered accepted=true mode=%@ root=%@ layerIDs=%@ surfacesBefore=%d surfacesAfter=%d",
                    request.usesAlternateRoot ? "alternate-input" : "same-input",
                    request.rootURL.path,
                    layerIDs,
                    before.surfaceCount,
                    after.surfaceCount
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    requestSnapshot(
                        reason: "scene-switch-after",
                        outputDirectory: outputDirectory
                    )
                }
            } catch {
                let after = SceneDesktopWallpaperHost.shared.debugSnapshot()
                NSLog(
                    "MWX DEBUG SCENE: phase=scene-switch state=triggered accepted=false mode=%@ root=%@ surfacesBefore=%d surfacesAfter=%d error=%@",
                    request.usesAlternateRoot ? "alternate-input" : "same-input",
                    request.rootURL.path,
                    before.surfaceCount,
                    after.surfaceCount,
                    error.localizedDescription
                )
            }
        }
    }
}
#endif
