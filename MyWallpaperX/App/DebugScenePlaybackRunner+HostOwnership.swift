#if DEBUG
extension DebugScenePlaybackRunner {
    static let runtimeHost = SceneDesktopWallpaperHost()

    static func stop() {
        runtimeHost.stop()
    }
}
#endif
