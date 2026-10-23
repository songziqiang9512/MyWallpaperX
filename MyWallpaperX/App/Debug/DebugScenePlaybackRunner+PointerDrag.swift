#if DEBUG
import CoreFoundation
import Foundation

extension DebugScenePlaybackRunner {
    static func movePointer(to normalized: SIMD2<Float>) {
        guard !isClosing else { return }
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
        guard !isClosing else { return }
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
        guard !isClosing else { return }
        runtimeHost.setDebugPointerOverride(.init())
        NSLog("MWX DEBUG SCENE: phase=pointer-state state=outside")
    }

    static func capturePointerResult(outputDirectory: URL) {
        requestSnapshot(reason: "hover", outputDirectory: outputDirectory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            setPointerOutside()
            schedulePointerAfterSnapshot(outputDirectory: outputDirectory)
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
        strictPointerPoint(after: "--mwx-debug-scene-cursor-drag-to-json")
    }

    private static func strictPointerPoint(after flag: String) -> SIMD2<Float>? {
        guard let payload = argumentValue(after: flag),
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let rawX = object["x"] as? NSNumber,
              let rawY = object["y"] as? NSNumber,
              CFGetTypeID(rawX) != CFBooleanGetTypeID(),
              CFGetTypeID(rawY) != CFBooleanGetTypeID() else { return nil }
        let x = rawX.doubleValue, y = rawY.doubleValue
        guard
              x.isFinite,
              y.isFinite,
              (-1...1).contains(x),
              (-1...1).contains(y) else {
            return nil
        }
        return SIMD2(Float(x), Float(y))
    }

    struct PointerDragTiming {
        let count: Int
        let pressSeconds: TimeInterval
        let heldSeconds: TimeInterval
        let betweenSeconds: TimeInterval
    }

    private static let pointerDragTimingFlag = "--mwx-debug-scene-cursor-drag-timing-json"

    static var requestedPointerDragTiming: PointerDragTiming? {
        guard let payload = argumentValue(after: pointerDragTimingFlag),
              let data = payload.data(using: .utf8), data.count <= 1_024,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["count", "pressSeconds", "heldSeconds", "betweenSeconds"] else { return nil }
        func number(_ key: String) -> Double? {
            guard let value = object[key] as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
            return value.doubleValue
        }
        guard let count = number("count"), (1...8).contains(count), count.rounded() == count,
              let press = number("pressSeconds"), (0.28...5).contains(press),
              let held = number("heldSeconds"), (0.28...5).contains(held),
              let between = number("betweenSeconds"), (0.28...10).contains(between) else { return nil }
        return .init(count: Int(count), pressSeconds: press, heldSeconds: held, betweenSeconds: between)
    }

    /// Validate the complete bounded plan before launching a Scene. A wall-clock
    /// alignment can wait up to one minute, so reserve that worst case here.
    static var pointerDragTimingPreconditionFailure: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(pointerDragTimingFlag) else { return nil }
        guard arguments.filter({ $0 == pointerDragTimingFlag }).count == 1,
              let timing = requestedPointerDragTiming else { return "invalid-pointer-drag-timing" }
        guard strictPointerPoint(after: "--mwx-debug-scene-hover-pointer-json") != nil,
              requestedDragPointer != nil, !requestedPrimaryClick, !requestedPrimaryClickSubframe,
              !arguments.contains("--mwx-debug-scene-pointer-trajectory-json") else {
            return "ambiguous-pointer-drag-timing"
        }
        var maximumStartDelay = 1.0
        if let raw = ProcessInfo.processInfo.environment["MYWALLPAPERX_SCENE_DEBUG_POINTER_SECOND"],
           let second = Double(raw), second.isFinite, (0..<60).contains(second) {
            maximumStartDelay = 60
        }
        // Existing hover entry: 0.35 + 0.28 seconds. Each explicit round
        // captures released after 0.28 seconds; the next round waits from there.
        let plan = maximumStartDelay + 0.35 + 0.28
            + Double(timing.count) * (timing.pressSeconds + timing.heldSeconds + 0.28)
            + Double(timing.count - 1) * timing.betweenSeconds + 0.2
        return plan < requestedDuration - 0.5 ? nil : "pointer-drag-timing-exceeds-duration"
    }

    static func schedulePointerDrag(
        outputDirectory: URL,
        from start: SIMD2<Float>,
        to destination: SIMD2<Float>
    ) {
        guard !isClosing else { return }
        if let timing = requestedPointerDragTiming {
            schedulePointerDragRound(outputDirectory: outputDirectory, from: start,
                to: destination, timing: timing, ordinal: 1)
            return
        }
        setPointer(at: start, primaryButtonIsDown: true, state: "press")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            guard !isClosing else { return }
            setPointer(
                at: destination,
                primaryButtonIsDown: true,
                state: "drag"
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                requestSnapshot(reason: "drag-held", outputDirectory: outputDirectory)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                guard !isClosing else { return }
                setPointer(
                    at: destination,
                    primaryButtonIsDown: false,
                    state: "release"
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                    requestSnapshot(reason: "spring-after", outputDirectory: outputDirectory)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    guard !isClosing else { return }
                    capturePointerResult(outputDirectory: outputDirectory)
                }
            }
        }
    }

    private static func schedulePointerDragRound(
        outputDirectory: URL, from start: SIMD2<Float>, to destination: SIMD2<Float>,
        timing: PointerDragTiming, ordinal: Int
    ) {
        guard !isClosing else { return }
        setPointer(at: start, primaryButtonIsDown: true, state: "press")
        DispatchQueue.main.asyncAfter(deadline: .now() + timing.pressSeconds) {
            guard !isClosing else { return }
            setPointer(at: destination, primaryButtonIsDown: true, state: "drag")
            DispatchQueue.main.asyncAfter(deadline: .now() + timing.heldSeconds / 2) {
                guard !isClosing else { return }
                requestSnapshot(reason: String(format: "drag-%02d-held", ordinal), outputDirectory: outputDirectory)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timing.heldSeconds) {
                guard !isClosing else { return }
                setPointer(at: destination, primaryButtonIsDown: false, state: "release")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    guard !isClosing else { return }
                    requestSnapshot(reason: String(format: "drag-%02d-released", ordinal), outputDirectory: outputDirectory)
                    if ordinal < timing.count {
                        DispatchQueue.main.asyncAfter(deadline: .now() + timing.betweenSeconds) {
                            guard !isClosing else { return }
                            schedulePointerDragRound(outputDirectory: outputDirectory, from: start,
                                to: destination, timing: timing, ordinal: ordinal + 1)
                        }
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            guard !isClosing else { return }
                            setPointerOutside()
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
                let count = ProcessInfo.processInfo.arguments.contains(
                    "--mwx-debug-scene-primary-double-click") ? 2 : 1
                schedulePrimaryClicks(outputDirectory: outputDirectory, pointer: pointer, remaining: count)
            } else {
                capturePointerResult(outputDirectory: outputDirectory)
            }
        }
    }

    private static func schedulePrimaryClicks(
        outputDirectory: URL, pointer: SIMD2<Float>, remaining: Int
    ) {
        setPointer(at: pointer, primaryButtonIsDown: true, state: "press")
        let release: @MainActor @Sendable () -> Void = {
            setPointer(at: pointer, primaryButtonIsDown: false, state: "release")
            DispatchQueue.main.asyncAfter(deadline: .now() + (remaining > 1 ? 0.07 : 0.28)) {
                if remaining > 1 {
                    schedulePrimaryClicks(outputDirectory: outputDirectory, pointer: pointer, remaining: remaining - 1)
                } else {
                    capturePointerResult(outputDirectory: outputDirectory)
                }
            }
        }
        if requestedPrimaryClickSubframe { release() }
        else {
            DispatchQueue.main.asyncAfter(deadline: .now() + (remaining > 1 ? 0.07 : 0.28), execute: release)
        }
    }

}
#endif
