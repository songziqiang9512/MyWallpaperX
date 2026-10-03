import Foundation

// Only the Scene host and capture backend are substituted. Scheduling, launch
// guards, argument parsing and pointer instrumentation are compiled unchanged.
struct SceneRuntimeModel { let identity: Int }
enum SceneUserPropertyTextureLoader {
    static func supports(url: URL) -> Bool { false }
}
enum SceneDebugFrameCapture {
    enum RequestClass: String { case required, periodic }
    @MainActor static func reportRejected(reason: String, stage: String) {
        DebugScenePlaybackRunner.record("rejected:\(reason):\(stage)")
    }
}

@MainActor
final class HarnessHost {
    struct Pointer {
        var current = SIMD2<Float>.zero
        var isInside = false
        var isPrimaryButtonDown = false
    }
    struct Snapshot { var windowNumbers = [17] }
    var pointer = Pointer()
    var suspendedLaunch: CheckedContinuation<SceneRuntimeModel, Error>?
    var launchObserver: CheckedContinuation<Void, Never>?

    func setDebugPointerOverride(_ value: Pointer) {
        let pressed = value.isPrimaryButtonDown && !pointer.isPrimaryButtonDown
        pointer = value
        let state = !value.isInside ? "outside" : value.isPrimaryButtonDown ? "down" : "up"
        DebugScenePlaybackRunner.record("pointer:\(state)", point: value.current)
        if pressed {
            DispatchQueue.main.async { DebugScenePlaybackRunner.record("turn-after-press") }
        }
    }

    func launch(rootURL: URL, propertyOverrides: [String: SceneUserPropertyValue],
                userPropertyTextureURLs: [String: URL], logURL: URL?,
                recordID: String?) async throws -> SceneRuntimeModel {
        DebugScenePlaybackRunner.record("launch", point: pointer.current,
                                       inside: pointer.isInside, record: recordID)
        return try await withCheckedThrowingContinuation { continuation in
            suspendedLaunch = continuation
            launchObserver?.resume()
            launchObserver = nil
        }
    }

    func waitForLaunch() async {
        if suspendedLaunch != nil { return }
        await withCheckedContinuation { launchObserver = $0 }
    }

    func debugSnapshot() -> Snapshot { Snapshot() }
    func debugParticleLoadReportLines() -> [String] { ["fixture-report"] }
    func requestDebugSnapshot(windowNumber: Int, reason: String, outputDirectory: URL,
                              kind: SceneDebugFrameCapture.RequestClass) -> Bool {
        DebugScenePlaybackRunner.record("capture:\(reason)", point: pointer.current,
                                       inside: pointer.isInside, kind: kind.rawValue)
        return true
    }
}

@MainActor
enum DebugScenePlaybackRunner {
    static let runtimeHost = HarnessHost()
    static var isClosing = false
    static var events: [[String: Any]] = []
    static let start = ProcessInfo.processInfo.systemUptime
    static var eventObserver: (String, CheckedContinuation<Void, Never>)?

    static func record(_ name: String, point: SIMD2<Float>? = nil,
                       inside: Bool? = nil, record: String? = nil, kind: String? = nil) {
        var row: [String: Any] = ["event": name,
                                 "time": ProcessInfo.processInfo.systemUptime - start]
        if let point { row["point"] = [point.x, point.y] }
        if let inside { row["inside"] = inside }
        if let record { row["record"] = record }
        if let kind { row["kind"] = kind }
        events.append(row)
        if let observer = eventObserver, observer.0 == name {
            eventObserver = nil
            observer.1.resume()
        }
    }

    static func waitFor(_ event: String) async {
        if events.contains(where: { $0["event"] as? String == event }) { return }
        await withCheckedContinuation { eventObserver = (event, $0) }
    }
}

@main
struct SceneDebugPointerScheduleHarness {
    @MainActor static func main() async throws {
        typealias Runner = DebugScenePlaybackRunner
        let scenario = CommandLine.arguments[1]
        let output = URL(fileURLWithPath: "/private/tmp/mwx-unused-capture-output")
        var payload: [String: Any] = [
            "hover": Runner.requestedHoverPointer.map { [$0.x, $0.y] } as Any? ?? NSNull(),
            "stationary": Runner.requestedHoverPointerStationaryEntry,
            "fromLaunch": Runner.requestedHoverPointerFromLaunch,
            "click": Runner.requestedPrimaryClick,
            "subframe": Runner.requestedPrimaryClickSubframe,
            "afterDelay": Runner.requestedAfterSnapshotDelay,
            "periodicInterval": Runner.requestedPeriodicSnapshotInterval as Any? ?? NSNull(),
            "duration": Runner.requestedDuration,
        ]
        if scenario != "arguments" {
            if scenario == "already-closing" { Runner.isClosing = true }
            let task = Task { @MainActor in
                try await Runner.launchForEvidence(
                    rootURL: output, userPropertyTextureURLs: [:], previewLogURL: nil,
                    requestUptime: ProcessInfo.processInfo.systemUptime,
                    recordID: "fixture-record"
                )
            }
            if scenario != "already-closing" {
                await Runner.runtimeHost.waitForLaunch()
                // An explicitly broken caller starts the actual capture schedule
                // while host launch is suspended; the Python event oracle rejects it.
                if scenario == "fault-early-capture" {
                    Runner.scheduleInitialEvidenceSnapshots(outputDirectory: output, previewLogURL: nil)
                    await Runner.waitFor("capture:before")
                }
                payload["suspendedEvents"] = Runner.events
                if scenario == "close-during-launch" { Runner.isClosing = true }
                Runner.record("launch-complete")
                let continuation = Runner.runtimeHost.suspendedLaunch!
                Runner.runtimeHost.suspendedLaunch = nil
                if scenario == "launch-failure" {
                    continuation.resume(throwing: CocoaError(.fileReadCorruptFile))
                } else if scenario == "launch-cancelled" {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(returning: SceneRuntimeModel(identity: 91))
                }
            }
            do {
                if let model = try await task.value {
                    payload["model"] = model.identity
                    Runner.record("ready")
                    if scenario != "fault-early-capture" {
                        Runner.scheduleInitialEvidenceSnapshots(outputDirectory: output, previewLogURL: nil)
                    }
                    if scenario == "close-before-capture" {
                        Runner.isClosing = true
                        // Let the actual regular/periodic callbacks become due.
                        try await Task.sleep(for: .seconds(1.75))
                    } else {
                        await Runner.waitFor("capture:after")
                        if Runner.requestedPeriodicSnapshotInterval != nil {
                            await Runner.waitFor("capture:series-0001")
                        }
                    }
                } else {
                    payload["model"] = NSNull()
                }
            } catch {
                payload["error"] = error is CancellationError ? "cancelled" : "failed"
            }
        }
        payload["events"] = Runner.events
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
