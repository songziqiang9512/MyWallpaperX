//
//  SystemAudioSpectrumService+DebugRecovery.swift
//  MyWallpaperX
//

import Foundation
import CoreAudio

#if DEBUG

/// Shared state of the DEBUG capture-recovery test seam. The service owns one
/// instance; every read and write happens on the service's `sampleQueue`. The
/// seam replaces real CoreAudio device creation, teardown and recovery
/// scheduling with deterministic, scriptable sequences so recovery paths can
/// be exercised without touching system audio devices.
final class SystemAudioDebugRecoveryState {
    private struct ScheduledRecovery {
        let kind: String
        let action: () -> Void
    }

    enum SyntheticResource {
        case ioProc
        case aggregate
        case tap
    }

    private(set) var isTestEnabled = false
    private(set) var hasSyntheticIOProc = false
    private(set) var hasSyntheticAggregate = false
    private(set) var hasSyntheticTap = false
    private(set) var captureStartTokens: [SceneAudioSpectrumCaptureToken] = []
    private(set) var captureStopCount = 0
    private(set) var callbackStateResetCount = 0
    private(set) var capturedFrameReadCount = 0
    private var scheduledRecoveries: [ScheduledRecovery] = []
    private var audioDeviceStopStatuses: [OSStatus] = []
    private var destroyIOProcStatuses: [OSStatus] = []
    private var destroyAggregateStatuses: [OSStatus] = []
    private var destroyTapStatuses: [OSStatus] = []

    var scheduledRecoveryKinds: [String] {
        scheduledRecoveries.map(\.kind)
    }

    /// Clears every recorded sequence and turns on synthetic interception.
    func enable() {
        isTestEnabled = true
        hasSyntheticIOProc = false
        hasSyntheticAggregate = false
        hasSyntheticTap = false
        audioDeviceStopStatuses.removeAll()
        destroyIOProcStatuses.removeAll()
        destroyAggregateStatuses.removeAll()
        destroyTapStatuses.removeAll()
        captureStartTokens.removeAll()
        captureStopCount = 0
        callbackStateResetCount = 0
        capturedFrameReadCount = 0
        scheduledRecoveries.removeAll()
    }

    func setSyntheticResourcesActive(_ active: Bool) {
        hasSyntheticIOProc = active
        hasSyntheticAggregate = active
        hasSyntheticTap = active
    }

    func setCaptureTeardownStatuses(
        stop: [OSStatus],
        destroyIOProc: [OSStatus],
        destroyAggregate: [OSStatus],
        destroyTap: [OSStatus]
    ) {
        audioDeviceStopStatuses = stop
        destroyIOProcStatuses = destroyIOProc
        destroyAggregateStatuses = destroyAggregate
        destroyTapStatuses = destroyTap
    }

    /// Records a capture start while the seam owns device creation. Returns
    /// `true` when recorded; the caller then skips creating real resources.
    @discardableResult
    func recordCaptureStartToken(
        epoch: UInt64,
        includesCurrentProcess: Bool
    ) -> Bool {
        guard isTestEnabled else { return false }
        captureStartTokens.append(
            SceneAudioSpectrumCaptureToken(
                scopeEpoch: epoch,
                includesCurrentProcessOutput: includesCurrentProcess
            )
        )
        return true
    }

    /// Parks a recovery action for later replay instead of real scheduling.
    /// Returns `true` when parked; the caller then skips `asyncAfter`.
    @discardableResult
    func recordScheduledRecovery(
        kind: String,
        action: @escaping () -> Void
    ) -> Bool {
        guard isTestEnabled else { return false }
        scheduledRecoveries.append(
            ScheduledRecovery(kind: kind, action: action)
        )
        return true
    }

    func recordCaptureStop() {
        guard isTestEnabled else { return }
        captureStopCount += 1
    }

    func recordCallbackStateReset() {
        guard isTestEnabled else { return }
        callbackStateResetCount += 1
    }

    func recordCapturedFrameRead() {
        guard isTestEnabled else { return }
        capturedFrameReadCount += 1
    }

    /// Clears one synthetic resource flag while the seam owns teardown.
    /// Returns `true` when handled; the caller then skips the real handle.
    @discardableResult
    func clearSyntheticResource(_ resource: SyntheticResource) -> Bool {
        guard isTestEnabled else { return false }
        switch resource {
        case .ioProc:
            hasSyntheticIOProc = false
        case .aggregate:
            hasSyntheticAggregate = false
        case .tap:
            hasSyntheticTap = false
        }
        return true
    }

    /// Pops the next scripted `AudioDeviceStop` status; `nil` when the seam
    /// is not intercepting, meaning the caller performs the real call.
    func takeAudioDeviceStopStatus() -> OSStatus? {
        guard isTestEnabled else { return nil }
        return Self.popStatus(&audioDeviceStopStatuses)
    }

    func takeDestroyIOProcStatus() -> OSStatus? {
        guard isTestEnabled else { return nil }
        return Self.popStatus(&destroyIOProcStatuses)
    }

    func takeDestroyAggregateStatus() -> OSStatus? {
        guard isTestEnabled else { return nil }
        return Self.popStatus(&destroyAggregateStatuses)
    }

    func takeDestroyTapStatus() -> OSStatus? {
        guard isTestEnabled else { return nil }
        return Self.popStatus(&destroyTapStatuses)
    }

    /// Runs one parked recovery action; returns `false` for a stale index.
    func performScheduledRecovery(at index: Int) -> Bool {
        guard scheduledRecoveries.indices.contains(index) else { return false }
        scheduledRecoveries[index].action()
        return true
    }

    private static func popStatus(_ statuses: inout [OSStatus]) -> OSStatus {
        guard !statuses.isEmpty else { return noErr }
        return statuses.removeFirst()
    }
}

extension SystemAudioSpectrumService {
    struct DebugRecoverySnapshot {
        let captureStartTokens: [SceneAudioSpectrumCaptureToken]
        let captureRetryAttempt: Int
        let hasCaptureRetryWorkItem: Bool
        let hasCaptureRestartWorkItem: Bool
        let hasCaptureTeardownRetryWorkItem: Bool
        let captureStopCount: Int
        let scheduledRecoveryKinds: [String]
        let currentToken: SceneAudioSpectrumCaptureToken
        let overlayBarCount: Int
        let hasSyntheticIOProc: Bool
        let hasSyntheticAggregate: Bool
        let hasSyntheticTap: Bool
        let callbackStateResetCount: Int
        let capturedFrameReadCount: Int
    }

    func debugSimulateCaptureConfigurationInvalidation() {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            self.scheduleCaptureRestart(reason: "debug", generation: self.captureResourceGeneration)
        }
    }

    func debugEnableRecoveryTesting() {
        sampleQueue.sync {
            debugRecovery.enable()
        }
    }

    func debugSetSyntheticCaptureResourcesActiveForTesting(_ active: Bool) {
        sampleQueue.sync {
            debugRecovery.setSyntheticResourcesActive(active)
            captureCallbackStateNeedsReset = active
        }
    }

    func debugSetCaptureTeardownStatusesForTesting(
        stop: [OSStatus] = [],
        destroyIOProc: [OSStatus] = [],
        destroyAggregate: [OSStatus] = [],
        destroyTap: [OSStatus] = []
    ) {
        sampleQueue.sync {
            debugRecovery.setCaptureTeardownStatuses(
                stop: stop,
                destroyIOProc: destroyIOProc,
                destroyAggregate: destroyAggregate,
                destroyTap: destroyTap
            )
        }
    }

    func debugScheduleCaptureRetryForTesting() {
        sampleQueue.sync {
            scheduleCaptureRetryIfNeeded()
        }
    }

    func debugScheduleCaptureRestartForTesting() {
        sampleQueue.sync {
            debugRecovery.setSyntheticResourcesActive(true)
            captureCallbackStateNeedsReset = true
            scheduleCaptureRestart(
                reason: "debug-test",
                generation: captureResourceGeneration
            )
        }
    }

    @discardableResult
    func debugPerformScheduledRecoveryForTesting(at index: Int) -> Bool {
        sampleQueue.sync {
            debugRecovery.performScheduledRecovery(at: index)
        }
    }

    func debugSimulateStaleCapturedFrameProcessingForTesting() {
        sampleQueue.sync {
            pendingCaptureResourceGeneration = captureResourceGeneration - 1
            pendingSceneCaptureToken = SceneAudioSpectrumCaptureToken(
                scopeEpoch: sceneCaptureScopeEpoch,
                includesCurrentProcessOutput:
                    processScope == .includesCurrentProcess
            )
            processCapturedAudio()
        }
    }

    func debugSimulateSceneRevokedFrameProcessingForTesting() {
        sampleQueue.sync {
            guard sceneCaptureScopeEpoch > 0 else { return }
            sceneEnabled = false
            pendingCaptureResourceGeneration = captureResourceGeneration
            pendingSceneCaptureToken = SceneAudioSpectrumCaptureToken(
                scopeEpoch: sceneCaptureScopeEpoch - 1,
                includesCurrentProcessOutput:
                    processScope == .includesCurrentProcess
            )
            processCapturedAudio()
        }
    }

    /// Runs the real capture handoff with deterministic callback time. The
    /// recovery test seam disables device creation; no system tap is opened.
    func debugProcessPCMForTesting(
        _ input: UnsafePointer<AudioBufferList>,
        format: AudioStreamBasicDescription,
        now: TimeInterval,
        workerBusy: Bool = false
    ) {
        let identity = sampleQueue.sync { () -> (Int, SceneAudioSpectrumCaptureToken) in
            precondition(debugRecovery.isTestEnabled)
            tapStreamFormat = format
            return (captureResourceGeneration, .init(
                scopeEpoch: sceneCaptureScopeEpoch,
                includesCurrentProcessOutput: processScope == .includesCurrentProcess
            ))
        }
        if workerBusy { processingGate.wait() }
        processAudioBufferList(input, resourceGeneration: identity.0,
            token: identity.1, now: now)
        if workerBusy { processingGate.signal() }
        // Wait until the single pending immutable snapshot has been consumed.
        processingGate.wait()
        processingGate.signal()
    }

    func debugRecoverySnapshot() -> DebugRecoverySnapshot {
        sampleQueue.sync {
            DebugRecoverySnapshot(
                captureStartTokens: debugRecovery.captureStartTokens,
                captureRetryAttempt: captureRetryAttempt,
                hasCaptureRetryWorkItem: captureRetryWorkItem != nil,
                hasCaptureRestartWorkItem: captureRestartWorkItem != nil,
                hasCaptureTeardownRetryWorkItem:
                    captureTeardownRetryWorkItem != nil,
                captureStopCount: debugRecovery.captureStopCount,
                scheduledRecoveryKinds: debugRecovery.scheduledRecoveryKinds,
                currentToken: SceneAudioSpectrumCaptureToken(
                    scopeEpoch: sceneCaptureScopeEpoch,
                    includesCurrentProcessOutput:
                        processScope == .includesCurrentProcess
                ),
                overlayBarCount: barCount,
                hasSyntheticIOProc: debugRecovery.hasSyntheticIOProc,
                hasSyntheticAggregate: debugRecovery.hasSyntheticAggregate,
                hasSyntheticTap: debugRecovery.hasSyntheticTap,
                callbackStateResetCount: debugRecovery.callbackStateResetCount,
                capturedFrameReadCount: debugRecovery.capturedFrameReadCount
            )
        }
    }
}

#endif
