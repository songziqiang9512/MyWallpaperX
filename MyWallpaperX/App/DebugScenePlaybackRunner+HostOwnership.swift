#if DEBUG
import Foundation

extension DebugScenePlaybackRunner {
    static let runtimeHost = SceneDesktopWallpaperHost()
    private(set) static var isClosing = false
    private static var finishResult: Bool?
    static var isFinished: Bool { finishResult != nil }
    private static var finishCallbacks: [@MainActor (Bool) -> Void] = []

    static func finish(completion: @escaping @MainActor (Bool) -> Void) {
        if let finishResult { completion(finishResult); return }
        finishCallbacks.append(completion)
        guard !isClosing else { return }
        isClosing = true
        let before = runtimeHost.debugSnapshot()
        runtimeHost.stopAndDrainGPU { succeeded in
            finishResult = succeeded
            NSLog("MWX DEBUG SCENE: phase=stopped surfacesBefore=%d surfacesAfter=%d gpuDrained=%@",
                  before.surfaceCount, runtimeHost.debugSnapshot().surfaceCount,
                  succeeded ? "true" : "false")
            let callbacks = finishCallbacks
            finishCallbacks.removeAll()
            callbacks.forEach { $0(succeeded) }
        }
    }

    static func stop() {
        // applicationWillTerminate arrives after finish; keep cleanup idempotent.
        runtimeHost.stop()
    }
}
#endif
