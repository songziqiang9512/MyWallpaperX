#if DEBUG
import Foundation

extension SceneMetalView {
    func requestDebugSnapshot(reason: String, outputDirectory: URL) {
        debugFrameCapture.request(reason: reason, outputDirectory: outputDirectory)
    }
}
#endif
