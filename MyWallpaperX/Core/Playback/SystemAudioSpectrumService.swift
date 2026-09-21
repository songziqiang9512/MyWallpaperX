//
//  SystemAudioSpectrumService.swift
//  MyWallpaperX
//

import Foundation
import AudioToolbox
import CoreAudio

final class SystemAudioSpectrumService: NSObject {
    private enum ProcessScope: String {
        case excludesCurrentProcess = "exclude-current-process"
        case includesCurrentProcess = "include-current-process"
    }

    private var barCount: Int
    private let sampleQueue = DispatchQueue(
        label: "com.songziqiang.MyWallpaperX.system-audio-spectrum",
        qos: .utility
    )
    private let processingMinInterval: TimeInterval = 1.0 / 30.0
    private static let captureResourceRetirementDelay: TimeInterval = 1.0
    private static let captureResourceTeardownRetryDelay: TimeInterval = 0.25
    private let processingGate = DispatchSemaphore(value: 1)
    private let captureBuffer = SystemAudioCaptureBuffer(maximumFrameCount: 4096)
    private var overlayAnalyzer: SystemAudioOverlaySpectrumAnalyzer
    private let webAnalyzer = SystemAudioWebSpectrumAnalyzer()
    private let sceneAnalyzer = SystemAudioSceneSpectrumAnalyzer()
    private lazy var configurationMonitor = SystemAudioCaptureConfigurationMonitor(queue: sampleQueue)

    private var processingSource: DispatchSourceUserDataAdd!
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var tapStreamFormat = AudioStreamBasicDescription()
    private var captureCallbackStateNeedsReset = false
    private var overlayEnabled = false
    private var webEnabled = false
    private var sceneEnabled = false
    private var processScope = ProcessScope.excludesCurrentProcess
    private var sceneCaptureScopeEpoch: UInt64 = 0
    private var lastProcessedAt: TimeInterval = 0
    private var captureRetryAttempt = 0
    private var captureRetryWorkItem: DispatchWorkItem?
    private var captureRetrySequence = 0
    private var captureGeneration = 0
    private var hasLoggedCapturedData = false
    private var captureResourceGeneration = 0
    private var pendingCaptureResourceGeneration = 0
    private var pendingSceneCaptureToken = SceneAudioSpectrumCaptureToken(
        scopeEpoch: 0,
        includesCurrentProcessOutput: false
    )
    private var captureRestartSequence = 0
    private var captureRestartWorkItem: DispatchWorkItem?
    private var captureResourceRetirementUntil: TimeInterval = 0
    private var captureTeardownRetrySequence = 0
    private var captureTeardownRetryWorkItem: DispatchWorkItem?

#if DEBUG
    private struct DebugScheduledRecovery {
        let kind: String
        let action: () -> Void
    }

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

    private var debugRecoveryTestingEnabled = false
    private var debugHasSyntheticIOProc = false
    private var debugHasSyntheticAggregate = false
    private var debugHasSyntheticTap = false
    private var debugAudioDeviceStopStatuses: [OSStatus] = []
    private var debugDestroyIOProcStatuses: [OSStatus] = []
    private var debugDestroyAggregateStatuses: [OSStatus] = []
    private var debugDestroyTapStatuses: [OSStatus] = []
    private var debugCaptureStartTokens: [SceneAudioSpectrumCaptureToken] = []
    private var debugCaptureStopCount = 0
    private var debugCallbackStateResetCount = 0
    private var debugCapturedFrameReadCount = 0
    private var debugScheduledRecoveries: [DebugScheduledRecovery] = []
#endif

    var onLevels: (([Float]) -> Void)?
    var onWebLevels: (([Float]) -> Void)?
    var onSceneLevels: ((
        _ left: [Float], _ right: [Float], _ left32: [Float], _ right32: [Float],
        _ left64: [Float], _ right64: [Float],
        _ token: SceneAudioSpectrumCaptureToken
    ) -> Void)?

    init(barCount: Int) {
        self.barCount = barCount
        self.overlayAnalyzer = SystemAudioOverlaySpectrumAnalyzer(barCount: barCount)
        super.init()

        let processingSource = DispatchSource.makeUserDataAddSource(queue: sampleQueue)
        processingSource.setEventHandler { [weak self] in
            guard let self else { return }
            defer { self.processingGate.signal() }
            self.processCapturedAudio()
        }
        processingSource.resume()
        self.processingSource = processingSource
    }

    deinit {
        captureRetryWorkItem?.cancel()
        captureRestartWorkItem?.cancel()
        captureTeardownRetryWorkItem?.cancel()
        processingSource?.cancel()
        stopCapture(allowRetry: false)
    }

    func setConsumers(
        overlayEnabled: Bool,
        webEnabled: Bool,
        sceneEnabled: Bool = false,
        includeCurrentProcessAudio: Bool = false,
        sceneCaptureScopeEpoch: UInt64 = 0
    ) {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            let requestedProcessScope: ProcessScope = sceneEnabled
                && includeCurrentProcessAudio
                ? .includesCurrentProcess
                : .excludesCurrentProcess
            let processScopeChanged = self.processScope != requestedProcessScope
            let activeSceneEpochChanged = sceneEnabled
                && (!self.sceneEnabled
                    || self.sceneCaptureScopeEpoch != sceneCaptureScopeEpoch)
            if self.overlayEnabled != overlayEnabled {
                self.onLevels?(self.overlayAnalyzer.reset())
            }
            if self.webEnabled != webEnabled {
                self.onWebLevels?(Self.clearedWebLevels)
            }
            if self.sceneEnabled != sceneEnabled {
                // A Scene endpoint can be revoked while Web/Video is still using
                // the same canonical rolling producer. Clear only the endpoint;
                // do not discard the shared capture window for another consumer.
                self.clearSceneLevels(resetAnalyzer: false)
            }
            self.overlayEnabled = overlayEnabled
            self.webEnabled = webEnabled
            self.sceneEnabled = sceneEnabled
            self.processScope = requestedProcessScope
            self.sceneCaptureScopeEpoch = sceneCaptureScopeEpoch
            if processScopeChanged || activeSceneEpochChanged {
                self.captureRetrySequence += 1
                self.captureRetryWorkItem?.cancel()
                self.captureRetryWorkItem = nil
                self.captureRetryAttempt = 0
                self.cancelCaptureRestart()
                // A source-set transition is an epoch boundary. Stop IO and
                // reset every rolling analyzer before reconciliation. The
                // shared start gate owns any required retirement delay.
                if self.hasCaptureResources {
                    self.stopCapture()
                }
            }
            self.reconcileCaptureState()
        }
    }

    func updateConfiguration(
        style: SystemAudioSpectrumStyle,
        sensitivity: SystemAudioSpectrumSensitivity,
        barCount: Int
    ) {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            let normalizedBarCount = max(1, barCount)
            if self.barCount != normalizedBarCount {
                self.barCount = normalizedBarCount
                self.overlayAnalyzer = SystemAudioOverlaySpectrumAnalyzer(
                    barCount: normalizedBarCount
                )
            }
            self.overlayAnalyzer.updateConfiguration(style: style, sensitivity: sensitivity)
            self.onLevels?(Array(repeating: 0, count: self.barCount))
        }
    }

    /// 任一消费者存在才采集；全部撤销时释放 tap 与聚合设备。
    private var hasActiveConsumer: Bool {
        overlayEnabled || webEnabled || sceneEnabled
    }

    private var hasCaptureResources: Bool {
        hasTapResource || hasAggregateResource || hasIOProcResource
    }

    private var hasTapResource: Bool {
#if DEBUG
        if debugRecoveryTestingEnabled { return debugHasSyntheticTap }
#endif
        return tapID != kAudioObjectUnknown
    }

    private var hasAggregateResource: Bool {
#if DEBUG
        if debugRecoveryTestingEnabled { return debugHasSyntheticAggregate }
#endif
        return aggregateDeviceID != kAudioObjectUnknown
    }

    private var hasIOProcResource: Bool {
#if DEBUG
        if debugRecoveryTestingEnabled { return debugHasSyntheticIOProc }
#endif
        return ioProcID != nil
    }

    private func startCaptureIfNeeded(
        resourceRetirementElapsed: Bool = false
    ) {
        guard hasActiveConsumer else { return }
        guard !hasCaptureResources,
              captureTeardownRetryWorkItem == nil else { return }
        if !resourceRetirementElapsed {
            let remainingRetirementDelay = captureResourceRetirementUntil
                - ProcessInfo.processInfo.systemUptime
            if remainingRetirementDelay > 0 {
                scheduleCaptureStartAfterResourceRetirement(
                    delay: remainingRetirementDelay
                )
                return
            }
        }
#if DEBUG
        if debugRecoveryTestingEnabled {
            debugCaptureStartTokens.append(
                SceneAudioSpectrumCaptureToken(
                    scopeEpoch: sceneCaptureScopeEpoch,
                    includesCurrentProcessOutput:
                        processScope == .includesCurrentProcess
                )
            )
            return
        }
#endif
        guard #available(macOS 14.2, *) else {
            NSLog("MWX AUDIO CAPTURE: unavailable before macOS 14.2")
            resetConsumersAfterCaptureFailure()
            return
        }

        do {
            captureRetryWorkItem?.cancel()
            captureRetryWorkItem = nil
            let excludedProcessIDs: [AudioObjectID]
            switch processScope {
            case .includesCurrentProcess:
                excludedProcessIDs = []
            case .excludesCurrentProcess:
                guard let currentProcessObjectID =
                        SystemAudioCaptureDeviceFactory.currentProcessObjectID() else {
                    throw SystemAudioCaptureDeviceFactory.CaptureError
                        .currentProcessUnavailable
                }
                excludedProcessIDs = [currentProcessObjectID]
            }
            let tapDescription = CATapDescription(
                stereoGlobalTapButExcludeProcesses: excludedProcessIDs
            )
            tapDescription.name = "MyWallpaperX System Audio Spectrum"
            tapDescription.uuid = UUID()
            tapDescription.isPrivate = true
            tapDescription.muteBehavior = .unmuted
            tapDescription.isProcessRestoreEnabled = false

            let createdTapID = try SystemAudioCaptureDeviceFactory.createProcessTap(description: tapDescription)
            tapID = createdTapID
            let tapUID = try SystemAudioCaptureDeviceFactory.fetchTapUID(for: createdTapID)
            tapStreamFormat = try SystemAudioCaptureDeviceFactory.fetchTapFormat(for: createdTapID)
            captureCallbackStateNeedsReset = true

            let aggregateID = try SystemAudioCaptureDeviceFactory.createAggregateDevice(tapUID: tapUID)
            aggregateDeviceID = aggregateID
            SystemAudioCaptureDeviceFactory.configureCaptureBufferFrameSize(for: aggregateID)
            captureResourceGeneration += 1
            let resourceGeneration = captureResourceGeneration
            let captureProcessScope = processScope
            let captureToken = SceneAudioSpectrumCaptureToken(
                scopeEpoch: sceneCaptureScopeEpoch,
                includesCurrentProcessOutput:
                    captureProcessScope == .includesCurrentProcess
            )
            try configurationMonitor.install(tapID: createdTapID, aggregateDeviceID: aggregateID) {
                [weak self] reason in
                self?.scheduleCaptureRestart(reason: reason, generation: resourceGeneration)
            }

            var createdIOProcID: AudioDeviceIOProcID?
            let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
                &createdIOProcID,
                aggregateID,
                nil
            ) { [weak self] _, inInputData, _, _, _ in
                self?.processAudioBufferList(
                    inInputData,
                    resourceGeneration: resourceGeneration,
                    token: captureToken
                )
            }
            guard ioStatus == noErr, let createdIOProcID else {
                throw SystemAudioCaptureDeviceFactory.CaptureError.osStatus(ioStatus)
            }
            ioProcID = createdIOProcID

            let startStatus = AudioDeviceStart(aggregateID, createdIOProcID)
            guard startStatus == noErr else {
                throw SystemAudioCaptureDeviceFactory.CaptureError.osStatus(startStatus)
            }
            captureRetryAttempt = 0
            captureGeneration += 1
            hasLoggedCapturedData = false
            NSLog(
                "MWX AUDIO CAPTURE: started generation=%d scope=%@ sampleRate=%.0f channels=%u",
                captureGeneration,
                processScope.rawValue,
                tapStreamFormat.mSampleRate,
                tapStreamFormat.mChannelsPerFrame
            )
        } catch {
            NSLog("MWX AUDIO CAPTURE: failed %@", error.localizedDescription)
            stopCapture()
            scheduleCaptureRetryIfNeeded()
        }
    }

    private func reconcileCaptureState() {
        let shouldCapture = hasActiveConsumer
        if shouldCapture {
            if !hasCaptureResources,
               captureRetryWorkItem == nil,
               captureRestartWorkItem == nil {
                startCaptureIfNeeded()
            }
            return
        }

        captureRetrySequence += 1
        captureRetryWorkItem?.cancel()
        captureRetryWorkItem = nil
        captureRetryAttempt = 0
        cancelCaptureRestart()
        if hasCaptureResources {
            stopCapture()
        }
    }

    private func scheduleCaptureRetryIfNeeded() {
        guard hasActiveConsumer else { return }
        captureRetryAttempt += 1
        let delay = min(pow(2, Double(captureRetryAttempt - 1)), 30)
        captureRetrySequence += 1
        let sequence = captureRetrySequence
        let scopeEpoch = sceneCaptureScopeEpoch
        let retryProcessScope = processScope
        let action = { [weak self] in
            guard let self,
                  self.captureRetrySequence == sequence,
                  self.sceneCaptureScopeEpoch == scopeEpoch,
                  self.processScope == retryProcessScope else { return }
            self.captureRetryWorkItem = nil
            self.startCaptureIfNeeded()
        }
        let workItem = DispatchWorkItem(block: action)
        captureRetryWorkItem?.cancel()
        captureRetryWorkItem = workItem
        NSLog("MWX AUDIO CAPTURE: retry scheduled attempt=%d delay=%.1f", captureRetryAttempt, delay)
#if DEBUG
        if debugRecoveryTestingEnabled {
            debugScheduledRecoveries.append(
                DebugScheduledRecovery(kind: "retry", action: action)
            )
            return
        }
#endif
        sampleQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleCaptureRestart(reason: String, generation: Int) {
        guard generation == captureResourceGeneration,
              hasActiveConsumer,
              hasTapResource,
              hasAggregateResource else { return }
        captureRestartSequence += 1
        let sequence = captureRestartSequence
        captureRestartWorkItem?.cancel()
        NSLog("MWX AUDIO CAPTURE: invalidated reason=%@ generation=%d", reason, generation)
        let action = { [weak self] in
            guard let self,
                  self.captureRestartSequence == sequence,
                  self.captureResourceGeneration == generation,
                  self.hasActiveConsumer else { return }
            self.captureRestartWorkItem = nil
            NSLog("MWX AUDIO CAPTURE: restarting reason=%@ generation=%d", reason, generation)
            self.stopCapture()
            self.reconcileCaptureState()
        }
        let workItem = DispatchWorkItem(block: action)
        captureRestartWorkItem = workItem
#if DEBUG
        if debugRecoveryTestingEnabled {
            debugScheduledRecoveries.append(
                DebugScheduledRecovery(kind: "restart", action: action)
            )
            return
        }
#endif
        sampleQueue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    /// CoreAudio can keep a just-destroyed tap/aggregate identity retiring for
    /// a short interval. Recreating the new source scope synchronously after
    /// `stopCapture()` can therefore fail with `kAudioHardwareBadObjectError`
    /// even though the next retry succeeds. Initial capture and scope changes
    /// without live resources still start immediately; only an actual resource
    /// retirement crosses this delayed identity boundary.
    private func scheduleCaptureStartAfterResourceRetirement(
        delay: TimeInterval
    ) {
        guard hasActiveConsumer else { return }
        captureRestartSequence += 1
        let sequence = captureRestartSequence
        let scopeEpoch = sceneCaptureScopeEpoch
        let restartProcessScope = processScope
        let action = { [weak self] in
            guard let self,
                  self.captureRestartSequence == sequence,
                  self.sceneCaptureScopeEpoch == scopeEpoch,
                  self.processScope == restartProcessScope,
                  self.hasActiveConsumer else { return }
            self.captureRestartWorkItem = nil
            self.startCaptureIfNeeded(resourceRetirementElapsed: true)
        }
        let workItem = DispatchWorkItem(block: action)
        captureRestartWorkItem = workItem
        NSLog(
            "MWX AUDIO CAPTURE: resource-retirement waiting delay=%.1f scope=%@ epoch=%llu",
            delay,
            restartProcessScope.rawValue,
            scopeEpoch
        )
#if DEBUG
        if debugRecoveryTestingEnabled {
            debugScheduledRecoveries.append(
                DebugScheduledRecovery(kind: "resource-retirement-start", action: action)
            )
            return
        }
#endif
        sampleQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelCaptureRestart() {
        captureRestartSequence += 1
        captureRestartWorkItem?.cancel()
        captureRestartWorkItem = nil
    }

    /// Tear down the current CoreAudio owner in dependency order. A failed
    /// operation keeps its identity live and blocks replacement capture until
    /// the same service has completed a retry; generation checks alone cannot
    /// make an undestroyed tap or aggregate safe to replace.
    private func stopCapture(allowRetry: Bool = true) {
        let hadCapture = hasCaptureResources
        guard hadCapture else { return }
#if DEBUG
        if debugRecoveryTestingEnabled {
            debugCaptureStopCount += 1
        }
#endif
        cancelCaptureRestart()
        captureResourceGeneration += 1
        configurationMonitor.remove()

        if hasAggregateResource, hasIOProcResource {
            let stopStatus = stopAudioDeviceResource()
            if stopStatus == kAudioHardwareBadObjectError {
                clearIOProcResource()
            } else if stopStatus == noErr
                        || stopStatus == kAudioHardwareNotRunningError {
                let destroyStatus = destroyIOProcResource()
                if destroyStatus == kAudioHardwareBadObjectError {
                    clearIOProcResource()
                } else if destroyStatus == noErr {
                    clearIOProcResource()
                } else {
                    logCaptureTeardownFailure(
                        operation: "destroy-ioproc",
                        status: destroyStatus
                    )
                }
            } else {
                logCaptureTeardownFailure(
                    operation: "stop-device",
                    status: stopStatus
                )
            }
        }

        if !hasIOProcResource, hasAggregateResource {
            let status = destroyAggregateResource()
            if status == noErr || status == kAudioHardwareBadObjectError {
                clearAggregateResource()
            } else {
                logCaptureTeardownFailure(
                    operation: "destroy-aggregate",
                    status: status
                )
            }
        }

        if !hasIOProcResource, !hasAggregateResource, hasTapResource {
            let status = destroyTapResource()
            if status == noErr || status == kAudioHardwareBadObjectError {
                clearTapResource()
            } else {
                logCaptureTeardownFailure(
                    operation: "destroy-tap",
                    status: status
                )
            }
        }

        if !hasIOProcResource, captureCallbackStateNeedsReset {
            resetCaptureCallbackState()
        }
        onLevels?(overlayAnalyzer.reset())
        onWebLevels?(Self.clearedWebLevels)
        clearSceneLevels(resetAnalyzer: true)
        if hasCaptureResources {
            if allowRetry {
                scheduleCaptureTeardownRetryIfNeeded()
            } else {
                NSLog("MWX AUDIO CAPTURE: teardown incomplete during service deinit")
            }
            return
        }

        captureTeardownRetrySequence += 1
        captureTeardownRetryWorkItem?.cancel()
        captureTeardownRetryWorkItem = nil
        captureResourceRetirementUntil = ProcessInfo.processInfo.systemUptime
            + Self.captureResourceRetirementDelay
        NSLog("MWX AUDIO CAPTURE: stopped")
    }

    private func scheduleCaptureTeardownRetryIfNeeded() {
        guard hasCaptureResources,
              captureTeardownRetryWorkItem == nil else { return }
        captureTeardownRetrySequence += 1
        let sequence = captureTeardownRetrySequence
        let action = { [weak self] in
            guard let self,
                  self.captureTeardownRetrySequence == sequence,
                  self.hasCaptureResources else { return }
            self.captureTeardownRetryWorkItem = nil
            self.stopCapture()
            if !self.hasCaptureResources {
                self.reconcileCaptureState()
            }
        }
        let workItem = DispatchWorkItem(block: action)
        captureTeardownRetryWorkItem = workItem
        NSLog(
            "MWX AUDIO CAPTURE: teardown retry waiting delay=%.2f",
            Self.captureResourceTeardownRetryDelay
        )
#if DEBUG
        if debugRecoveryTestingEnabled {
            debugScheduledRecoveries.append(
                DebugScheduledRecovery(kind: "resource-teardown-retry", action: action)
            )
            return
        }
#endif
        sampleQueue.asyncAfter(
            deadline: .now() + Self.captureResourceTeardownRetryDelay,
            execute: workItem
        )
    }

    private func stopAudioDeviceResource() -> OSStatus {
#if DEBUG
        if debugRecoveryTestingEnabled {
            return Self.nextDebugStatus(&debugAudioDeviceStopStatuses)
        }
#endif
        guard aggregateDeviceID != kAudioObjectUnknown,
              let ioProcID else { return kAudioHardwareBadObjectError }
        return AudioDeviceStop(aggregateDeviceID, ioProcID)
    }

    private func destroyIOProcResource() -> OSStatus {
#if DEBUG
        if debugRecoveryTestingEnabled {
            return Self.nextDebugStatus(&debugDestroyIOProcStatuses)
        }
#endif
        guard aggregateDeviceID != kAudioObjectUnknown,
              let ioProcID else { return kAudioHardwareBadObjectError }
        return AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
    }

    private func destroyAggregateResource() -> OSStatus {
#if DEBUG
        if debugRecoveryTestingEnabled {
            return Self.nextDebugStatus(&debugDestroyAggregateStatuses)
        }
#endif
        guard aggregateDeviceID != kAudioObjectUnknown else {
            return kAudioHardwareBadObjectError
        }
        return AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
    }

    private func destroyTapResource() -> OSStatus {
#if DEBUG
        if debugRecoveryTestingEnabled {
            return Self.nextDebugStatus(&debugDestroyTapStatuses)
        }
#endif
        guard tapID != kAudioObjectUnknown else {
            return kAudioHardwareBadObjectError
        }
        guard #available(macOS 14.2, *) else {
            return kAudioHardwareUnsupportedOperationError
        }
        return AudioHardwareDestroyProcessTap(tapID)
    }

    private func clearIOProcResource() {
#if DEBUG
        if debugRecoveryTestingEnabled {
            debugHasSyntheticIOProc = false
            return
        }
#endif
        ioProcID = nil
    }

    private func clearAggregateResource() {
#if DEBUG
        if debugRecoveryTestingEnabled {
            debugHasSyntheticAggregate = false
            return
        }
#endif
        aggregateDeviceID = kAudioObjectUnknown
    }

    private func clearTapResource() {
#if DEBUG
        if debugRecoveryTestingEnabled {
            debugHasSyntheticTap = false
            return
        }
#endif
        tapID = kAudioObjectUnknown
    }

    private func logCaptureTeardownFailure(
        operation: String,
        status: OSStatus
    ) {
        NSLog(
            "MWX AUDIO CAPTURE: teardown failed operation=%@ status=%d",
            operation,
            status
        )
    }

    private func resetCaptureCallbackState() {
        tapStreamFormat = AudioStreamBasicDescription()
        captureBuffer.reset()
        lastProcessedAt = 0
        captureCallbackStateNeedsReset = false
#if DEBUG
        if debugRecoveryTestingEnabled {
            debugCallbackStateResetCount += 1
        }
#endif
    }

#if DEBUG
    private static func nextDebugStatus(_ statuses: inout [OSStatus]) -> OSStatus {
        guard !statuses.isEmpty else { return noErr }
        return statuses.removeFirst()
    }

    func debugSimulateCaptureConfigurationInvalidation() {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            self.scheduleCaptureRestart(reason: "debug", generation: self.captureResourceGeneration)
        }
    }

    func debugEnableRecoveryTesting() {
        sampleQueue.sync {
            debugRecoveryTestingEnabled = true
            debugHasSyntheticIOProc = false
            debugHasSyntheticAggregate = false
            debugHasSyntheticTap = false
            debugAudioDeviceStopStatuses.removeAll()
            debugDestroyIOProcStatuses.removeAll()
            debugDestroyAggregateStatuses.removeAll()
            debugDestroyTapStatuses.removeAll()
            debugCaptureStartTokens.removeAll()
            debugCaptureStopCount = 0
            debugCallbackStateResetCount = 0
            debugCapturedFrameReadCount = 0
            debugScheduledRecoveries.removeAll()
        }
    }

    func debugSetSyntheticCaptureResourcesActiveForTesting(_ active: Bool) {
        sampleQueue.sync {
            debugHasSyntheticIOProc = active
            debugHasSyntheticAggregate = active
            debugHasSyntheticTap = active
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
            debugAudioDeviceStopStatuses = stop
            debugDestroyIOProcStatuses = destroyIOProc
            debugDestroyAggregateStatuses = destroyAggregate
            debugDestroyTapStatuses = destroyTap
        }
    }

    func debugScheduleCaptureRetryForTesting() {
        sampleQueue.sync {
            scheduleCaptureRetryIfNeeded()
        }
    }

    func debugScheduleCaptureRestartForTesting() {
        sampleQueue.sync {
            debugHasSyntheticIOProc = true
            debugHasSyntheticAggregate = true
            debugHasSyntheticTap = true
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
            guard debugScheduledRecoveries.indices.contains(index) else { return false }
            debugScheduledRecoveries[index].action()
            return true
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

    func debugRecoverySnapshot() -> DebugRecoverySnapshot {
        sampleQueue.sync {
            DebugRecoverySnapshot(
                captureStartTokens: debugCaptureStartTokens,
                captureRetryAttempt: captureRetryAttempt,
                hasCaptureRetryWorkItem: captureRetryWorkItem != nil,
                hasCaptureRestartWorkItem: captureRestartWorkItem != nil,
                hasCaptureTeardownRetryWorkItem:
                    captureTeardownRetryWorkItem != nil,
                captureStopCount: debugCaptureStopCount,
                scheduledRecoveryKinds: debugScheduledRecoveries.map(\.kind),
                currentToken: SceneAudioSpectrumCaptureToken(
                    scopeEpoch: sceneCaptureScopeEpoch,
                    includesCurrentProcessOutput:
                        processScope == .includesCurrentProcess
                ),
                overlayBarCount: barCount,
                hasSyntheticIOProc: debugHasSyntheticIOProc,
                hasSyntheticAggregate: debugHasSyntheticAggregate,
                hasSyntheticTap: debugHasSyntheticTap,
                callbackStateResetCount: debugCallbackStateResetCount,
                capturedFrameReadCount: debugCapturedFrameReadCount
            )
        }
    }
#endif

    private func resetConsumersAfterCaptureFailure() {
        overlayEnabled = false
        webEnabled = false
        sceneEnabled = false
        processScope = .excludesCurrentProcess
        onLevels?(overlayAnalyzer.reset())
        onWebLevels?(Self.clearedWebLevels)
        clearSceneLevels(resetAnalyzer: true)
    }

    private func processAudioBufferList(
        _ inputData: UnsafePointer<AudioBufferList>,
        resourceGeneration: Int,
        token: SceneAudioSpectrumCaptureToken
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastProcessedAt >= processingMinInterval else { return }
        lastProcessedAt = now
        guard processingGate.wait(timeout: .now()) == .success else { return }
        guard captureBuffer.capture(inputData, streamDescription: tapStreamFormat) else {
            processingGate.signal()
            return
        }
        pendingCaptureResourceGeneration = resourceGeneration
        pendingSceneCaptureToken = token
        processingSource.add(data: 1)
    }

    private func processCapturedAudio() {
        guard pendingCaptureResourceGeneration == captureResourceGeneration,
              (!sceneEnabled
                || pendingSceneCaptureToken.scopeEpoch == sceneCaptureScopeEpoch),
              pendingSceneCaptureToken.includesCurrentProcessOutput
                == (processScope == .includesCurrentProcess) else { return }
#if DEBUG
        if debugRecoveryTestingEnabled {
            debugCapturedFrameReadCount += 1
        }
#endif
        guard let frame = captureBuffer.decodedFrame else { return }
        let sampleRate = Float(max(1, tapStreamFormat.mSampleRate))
        if !hasLoggedCapturedData {
            let peak = frame.rectifiedMono.max() ?? 0
            if peak >= 0.0001 {
                hasLoggedCapturedData = true
                NSLog(
                    "MWX AUDIO CAPTURE: data generation=%d peak=%.4f",
                    captureGeneration,
                    peak
                )
            }
        }
        guard let sceneAnalyzer else {
            if overlayEnabled { onLevels?(overlayAnalyzer.reset()) }
            if webEnabled { onWebLevels?(Self.clearedWebLevels) }
            if sceneEnabled { clearSceneLevels(resetAnalyzer: true) }
            return
        }
        let bands = sceneAnalyzer.analyze(frame, sampleRate: sampleRate)
        if overlayEnabled {
            onLevels?(
                overlayAnalyzer.analyze(
                    leftLevels: bands.left64,
                    rightLevels: bands.right64
                )
            )
        }
        if webEnabled {
            onWebLevels?(webAnalyzer.analyze(bands))
        }
        if sceneEnabled {
            onSceneLevels?(
                bands.left,
                bands.right,
                bands.left32,
                bands.right32,
                bands.left64,
                bands.right64,
                pendingSceneCaptureToken
            )
        }
    }

    private func clearSceneLevels(resetAnalyzer: Bool = false) {
        if resetAnalyzer {
            sceneAnalyzer?.reset()
        }
        onSceneLevels?(
            Self.clearedSceneLevels,
            Self.clearedSceneLevels,
            Self.clearedMediumSceneLevels,
            Self.clearedMediumSceneLevels,
            Self.clearedExtendedSceneLevels,
            Self.clearedExtendedSceneLevels,
            SceneAudioSpectrumCaptureToken(
                scopeEpoch: sceneCaptureScopeEpoch,
                includesCurrentProcessOutput:
                    processScope == .includesCurrentProcess
            )
        )
    }

}

private extension SystemAudioSpectrumService {
    static let clearedWebLevels = Array(
        repeating: Float(0),
        count: SystemAudioWebSpectrumAnalyzer.outputLevelCount
    )
    static let clearedSceneLevels = Array(
        repeating: Float(0),
        count: SystemAudioSceneSpectrumAnalyzer.bandCount
    )
    static let clearedExtendedSceneLevels = Array(
        repeating: Float(0),
        count: SystemAudioSceneSpectrumAnalyzer.extendedBandCount
    )
    static let clearedMediumSceneLevels = Array(
        repeating: Float(0),
        count: SystemAudioSceneSpectrumAnalyzer.mediumBandCount
    )
}
