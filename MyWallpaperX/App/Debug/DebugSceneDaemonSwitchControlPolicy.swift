#if DEBUG
/// Keeps the daemon-switch evidence runner's control sequence explicit.  The
/// audio-continuity mode suppresses only pause/mute, because those controls
/// intentionally retire capture; requested property updates and the bounded
/// performance profile still execute in their original order.
enum DebugSceneDaemonSwitchControlPolicy {
    static func exercise(
        preservingAudioCapture: Bool,
        dispatchPropertyUpdate: () -> Void,
        dispatchPerformanceProfile: () -> Void,
        dispatchAudioLifecycleControls: () -> Void
    ) {
        dispatchPropertyUpdate()
        dispatchPerformanceProfile()
        guard !preservingAudioCapture else { return }
        dispatchAudioLifecycleControls()
    }
}
#endif
