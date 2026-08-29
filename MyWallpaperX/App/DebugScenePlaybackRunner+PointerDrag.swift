#if DEBUG
import Foundation

extension DebugScenePlaybackRunner {
    static var requestedDragPointer: SIMD2<Float>? {
        guard let payload = argumentValue(
            after: "--mwx-debug-scene-cursor-drag-to-json"
        ),
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let x = (object["x"] as? NSNumber)?.doubleValue,
              let y = (object["y"] as? NSNumber)?.doubleValue,
              x.isFinite,
              y.isFinite,
              (-1...1).contains(x),
              (-1...1).contains(y) else {
            return nil
        }
        return SIMD2(Float(x), Float(y))
    }

    static func schedulePointerDrag(
        outputDirectory: URL,
        from start: SIMD2<Float>,
        to destination: SIMD2<Float>
    ) {
        setPointer(at: start, primaryButtonIsDown: true, state: "press")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            setPointer(
                at: destination,
                primaryButtonIsDown: true,
                state: "drag"
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                setPointer(
                    at: destination,
                    primaryButtonIsDown: false,
                    state: "release"
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    requestSnapshot(
                        reason: "hover",
                        outputDirectory: outputDirectory
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        setPointerOutside()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            requestSnapshot(
                                reason: "after",
                                outputDirectory: outputDirectory
                            )
                        }
                    }
                }
            }
        }
    }
}
#endif
