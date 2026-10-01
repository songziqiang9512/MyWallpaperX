#if DEBUG
import Foundation

extension SceneMetalView {
    func requestDebugSnapshot(reason: String, outputDirectory: URL,
                              kind: SceneDebugFrameCapture.RequestClass) -> SceneDebugFrameCapture.Admission {
        debugFrameCapture.request(reason: reason, outputDirectory: outputDirectory, kind: kind)
    }
}
#endif
