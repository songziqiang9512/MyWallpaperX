#if DEBUG
import CoreFoundation
import Foundation

extension DebugScenePlaybackRunner {
    static func movePointer(to normalized: SIMD2<Float>) {
        runtimeHost.setDebugPointerOverride(.init(
            current: normalized,
            isInside: true,
            isPrimaryButtonDown: false
        ))
        NSLog(
            "MWX DEBUG SCENE: phase=pointer-state state=move x=%.6f y=%.6f",
            normalized.x,
            normalized.y
        )
    }

    static func holdPointer(at normalized: SIMD2<Float>) {
        setPointer(
            at: normalized,
            primaryButtonIsDown: false,
            state: "hold"
        )
    }

    static func setPointer(
        at normalized: SIMD2<Float>,
        primaryButtonIsDown: Bool,
        state: String
    ) {
        runtimeHost.setDebugPointerOverride(.init(
            current: normalized,
            isInside: true,
            isPrimaryButtonDown: primaryButtonIsDown
        ))
        NSLog(
            "MWX DEBUG SCENE: phase=pointer-state state=%@ x=%.6f y=%.6f primaryDown=%@",
            state,
            normalized.x,
            normalized.y,
            primaryButtonIsDown ? "true" : "false"
        )
    }

    static func setPointerOutside() {
        runtimeHost.setDebugPointerOverride(.init())
        NSLog("MWX DEBUG SCENE: phase=pointer-state state=outside")
    }

    static func capturePointerResult(outputDirectory: URL) {
        requestSnapshot(reason: "hover", outputDirectory: outputDirectory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            setPointerOutside()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                requestSnapshot(reason: "after", outputDirectory: outputDirectory)
            }
        }
    }

    /// Places the synthetic pointer on the requested hover point before the
    /// first frame instead of freezing it outside, so a controlled comparison
    /// can reach an authored callback that depends on first-frame state.
    /// Retire with the cursor calibration batch.
    static var requestedHoverPointerFromLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-hover-pointer-from-launch"
        )
    }

    static var requestedPointerTrajectory: [SIMD2<Float>]? {
        guard let payload = argumentValue(
            after: "--mwx-debug-scene-pointer-trajectory-json"
        ),
              let data = payload.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data)
                as? [[Any]],
              (2...8).contains(values.count) else {
            return nil
        }
        var points: [SIMD2<Float>] = []
        points.reserveCapacity(values.count)
        for value in values {
            guard value.count == 2,
                  let x = value[0] as? NSNumber,
                  let y = value[1] as? NSNumber,
                  CFGetTypeID(x) != CFBooleanGetTypeID(),
                  CFGetTypeID(y) != CFBooleanGetTypeID(),
                  x.doubleValue.isFinite,
                  y.doubleValue.isFinite,
                  (-1...1).contains(x.doubleValue),
                  (-1...1).contains(y.doubleValue) else {
                return nil
            }
            let point = SIMD2(Float(x.doubleValue), Float(y.doubleValue))
            guard points.last != point else { return nil }
            points.append(point)
        }
        return points
    }

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                requestSnapshot(reason: "drag-held", outputDirectory: outputDirectory)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                setPointer(
                    at: destination,
                    primaryButtonIsDown: false,
                    state: "release"
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                    requestSnapshot(reason: "spring-after", outputDirectory: outputDirectory)
                }
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

    static func schedulePointerTrajectory(
        outputDirectory: URL,
        points: [SIMD2<Float>]
    ) {
        guard let first = points.first else { return }
        NSLog(
            "MWX DEBUG SCENE: phase=pointer-trajectory index=0 count=%d x=%.6f y=%.6f",
            points.count,
            first.x,
            first.y
        )
        requestSnapshot(
            reason: "pointer-trajectory-00",
            outputDirectory: outputDirectory
        )
        schedulePointerTrajectoryStep(
            outputDirectory: outputDirectory,
            points: points,
            index: 1
        )
    }

    private static func schedulePointerTrajectoryStep(
        outputDirectory: URL,
        points: [SIMD2<Float>],
        index: Int
    ) {
        guard points.indices.contains(index) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                capturePointerResult(outputDirectory: outputDirectory)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let point = points[index]
            setPointer(
                at: point,
                primaryButtonIsDown: false,
                state: "trajectory"
            )
            NSLog(
                "MWX DEBUG SCENE: phase=pointer-trajectory index=%d count=%d x=%.6f y=%.6f",
                index,
                points.count,
                point.x,
                point.y
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                requestSnapshot(
                    reason: String(format: "pointer-trajectory-%02d", index),
                    outputDirectory: outputDirectory
                )
                schedulePointerTrajectoryStep(
                    outputDirectory: outputDirectory,
                    points: points,
                    index: index + 1
                )
            }
        }
    }

    static func schedulePointerSnapshots(
        outputDirectory: URL,
        hoverPointer: SIMD2<Float>,
        stationaryEntry: Bool,
        primaryClick: Bool,
        dragPointer: SIMD2<Float>?,
        pointerTrajectory: [SIMD2<Float>]?
    ) {
        var startDelay = 1.0
        if let raw = ProcessInfo.processInfo.environment["MYWALLPAPERX_SCENE_DEBUG_POINTER_SECOND"],
           let second = Double(raw), second.isFinite, (0..<60).contains(second) {
            let current = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
            startDelay = (second - current + 60).truncatingRemainder(dividingBy: 60)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
            requestSnapshot(reason: "before", outputDirectory: outputDirectory)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if stationaryEntry {
                    holdPointer(at: hoverPointer)
                    schedulePointerResultSnapshot(
                        outputDirectory: outputDirectory,
                        pointer: hoverPointer,
                        primaryClick: primaryClick,
                        dragPointer: dragPointer,
                        pointerTrajectory: pointerTrajectory,
                        after: 0.28
                    )
                } else {
                    movePointer(to: hoverPointer)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        holdPointer(at: hoverPointer)
                        schedulePointerResultSnapshot(
                            outputDirectory: outputDirectory,
                            pointer: hoverPointer,
                            primaryClick: primaryClick,
                            dragPointer: dragPointer,
                            pointerTrajectory: pointerTrajectory,
                            after: 0.2
                        )
                    }
                }
            }
        }
    }

    static func schedulePointerResultSnapshot(
        outputDirectory: URL,
        pointer: SIMD2<Float>,
        primaryClick: Bool,
        dragPointer: SIMD2<Float>?,
        pointerTrajectory: [SIMD2<Float>]?,
        after delay: TimeInterval
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let pointerTrajectory {
                schedulePointerTrajectory(
                    outputDirectory: outputDirectory,
                    points: pointerTrajectory
                )
            } else if let dragPointer {
                schedulePointerDrag(
                    outputDirectory: outputDirectory,
                    from: pointer,
                    to: dragPointer
                )
            } else if primaryClick {
                setPointer(at: pointer, primaryButtonIsDown: true, state: "press")
                if requestedPrimaryClickSubframe {
                    setPointer(at: pointer, primaryButtonIsDown: false, state: "release")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        capturePointerResult(outputDirectory: outputDirectory)
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        setPointer(at: pointer, primaryButtonIsDown: false, state: "release")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                            capturePointerResult(outputDirectory: outputDirectory)
                        }
                    }
                }
            } else {
                capturePointerResult(outputDirectory: outputDirectory)
            }
        }
    }

}
#endif
