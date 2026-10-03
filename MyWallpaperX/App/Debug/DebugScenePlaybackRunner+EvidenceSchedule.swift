#if DEBUG
import Foundation

// The evidence runner's launch and capture ordering stays in the existing
// owner; this extension is also compiled by the standalone scheduling harness.
extension DebugScenePlaybackRunner {
    static func launchForEvidence(
        rootURL: URL,
        userPropertyTextureURLs: [String: URL],
        previewLogURL: URL?,
        requestUptime: TimeInterval,
        recordID: String
    ) async throws -> SceneRuntimeModel? {
        if let hoverPointer = requestedHoverPointer {
            // Freeze the synthetic pointer outside before surface creation so
            // the first authored edge belongs to the declared benchmark step,
            // not to the operator's current mouse location. The explicit
            // from-launch opt-in keeps that edge but declares it as the
            // requested point, which is the only way to reach an authored
            // callback that depends on first-frame state.
            runtimeHost.setDebugPointerOverride(
                requestedHoverPointerFromLaunch
                    ? .init(
                        current: hoverPointer,
                        isInside: true,
                        isPrimaryButtonDown: false
                    )
                    : .init()
            )
        }
        NSLog(
            "MWX LAUNCH-STAGE: stage=runner-pre-launch elapsedMs=%.0f",
            (ProcessInfo.processInfo.systemUptime - requestUptime) * 1_000
        )
        guard !isClosing else { return nil }
        let model = try await runtimeHost.launch(
            rootURL: rootURL,
            propertyOverrides: requestedPropertyOverrides,
            userPropertyTextureURLs: userPropertyTextureURLs,
            logURL: previewLogURL,
            recordID: recordID
        )
        guard !isClosing else { return nil }
        return model
    }

    static func scheduleInitialEvidenceSnapshots(
        outputDirectory: URL,
        previewLogURL: URL?
    ) {
        if let hoverPointer = requestedHoverPointer {
            setPointerOutside()
            schedulePointerSnapshots(
                outputDirectory: outputDirectory,
                hoverPointer: hoverPointer,
                stationaryEntry: requestedHoverPointerStationaryEntry,
                primaryClick: requestedPrimaryClick,
                dragPointer: requestedDragPointer,
                pointerTrajectory: requestedPointerTrajectory
            )
            schedulePeriodicSnapshots(outputDirectory: outputDirectory)
        } else {
            scheduleSnapshots(outputDirectory: outputDirectory, previewLogURL: previewLogURL)
        }
    }

    static func scheduleSnapshots(
        outputDirectory: URL,
        previewLogURL: URL?
    ) {
        for (reason, delay) in [("ready", 1.0), ("after", requestedAfterSnapshotDelay)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !isClosing else { return }
                requestSnapshot(reason: reason, outputDirectory: outputDirectory)
                // The launch-time particle summary undercounts child-only
                // containers (their particles spawn after advance-by-0); the
                // after point captures the settled state for the evidence.
                if reason == "after", let previewLogURL {
                    // Append: the launch-time evidence lines above must
                    // survive for the benchmark's validation gates.
                    let lines = runtimeHost.debugParticleLoadReportLines()
                    let report = lines.joined(separator: "\n") + "\n"
                    if let handle = try? FileHandle(forWritingTo: previewLogURL) {
                        defer { try? handle.close() }
                        try? handle.seekToEnd()
                        try? handle.write(contentsOf: Data(report.utf8))
                    }
                }
            }
        }
        schedulePeriodicSnapshots(outputDirectory: outputDirectory)
    }

    private static func schedulePeriodicSnapshots(outputDirectory: URL) {
        guard let interval = requestedPeriodicSnapshotInterval else { return }
        schedulePeriodicSnapshot(outputDirectory: outputDirectory, interval: interval,
                                 elapsed: max(1.5, interval), index: 0)
    }

    private static func schedulePeriodicSnapshot(outputDirectory: URL, interval: TimeInterval,
                                                 elapsed: TimeInterval, index: Int) {
        guard !isClosing, elapsed < requestedDuration - 0.5 else { return }
        let delay = index == 0 ? elapsed : interval
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard !isClosing else { return }
            requestSnapshot(reason: String(format: "series-%04d", index),
                            outputDirectory: outputDirectory, kind: .periodic)
            schedulePeriodicSnapshot(outputDirectory: outputDirectory, interval: interval,
                                     elapsed: elapsed + interval, index: index + 1)
        }
    }

    static func requestSnapshot(reason: String, outputDirectory: URL,
                                kind: SceneDebugFrameCapture.RequestClass = .required) {
        guard !isClosing else { return }
        guard let windowNumber = runtimeHost.debugSnapshot().windowNumbers.first else {
            SceneDebugFrameCapture.reportRejected(reason: reason, stage: "surface-lookup")
            return
        }
        _ = runtimeHost.requestDebugSnapshot(windowNumber: windowNumber, reason: reason,
                                            outputDirectory: outputDirectory, kind: kind)
    }
}
#endif
