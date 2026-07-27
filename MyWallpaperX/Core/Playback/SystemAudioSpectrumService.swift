//
//  SystemAudioSpectrumService.swift
//  MyWallpaperX
//

import Foundation
import AudioToolbox
import CoreAudio

final class SystemAudioSpectrumService: NSObject {
    private let barCount: Int
    private let sampleQueue = DispatchQueue(
        label: "com.songziqiang.MyWallpaperX.system-audio-spectrum",
        qos: .utility
    )
    private let processingMinInterval: TimeInterval = 1.0 / 30.0
    private let processingGate = DispatchSemaphore(value: 1)
    private let captureBuffer = SystemAudioCaptureBuffer(maximumFrameCount: 4096)
    private let overlayAnalyzer: SystemAudioOverlaySpectrumAnalyzer
    private let webAnalyzer = SystemAudioWebSpectrumAnalyzer()
    private let sceneAnalyzer = SystemAudioSceneSpectrumAnalyzer()
    private lazy var configurationMonitor = SystemAudioCaptureConfigurationMonitor(queue: sampleQueue)

    private var processingSource: DispatchSourceUserDataAdd!
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var tapStreamFormat = AudioStreamBasicDescription()
    private var overlayEnabled = false
    private var webEnabled = false
    private var sceneEnabled = false
    private var lastProcessedAt: TimeInterval = 0
    private var captureRetryAttempt = 0
    private var captureRetryWorkItem: DispatchWorkItem?
    private var captureGeneration = 0
    private var hasLoggedCapturedData = false
    private var captureResourceGeneration = 0
    private var captureRestartSequence = 0
    private var captureRestartWorkItem: DispatchWorkItem?

    var onLevels: (([Float]) -> Void)?
    var onWebLevels: (([Float]) -> Void)?
    var onSceneLevels: ((
        _ left: [Float], _ right: [Float], _ left64: [Float], _ right64: [Float]
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
        processingSource?.cancel()
        stopCapture()
    }

    func setConsumers(overlayEnabled: Bool, webEnabled: Bool, sceneEnabled: Bool = false) {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            if self.overlayEnabled != overlayEnabled {
                self.onLevels?(self.overlayAnalyzer.reset())
            }
            if self.webEnabled != webEnabled {
                self.onWebLevels?(Self.clearedWebLevels)
            }
            if self.sceneEnabled != sceneEnabled {
                self.clearSceneLevels()
            }
            self.overlayEnabled = overlayEnabled
            self.webEnabled = webEnabled
            self.sceneEnabled = sceneEnabled
            self.reconcileCaptureState()
        }
    }

    func updateConfiguration(
        style: SystemAudioSpectrumStyle,
        sensitivity: SystemAudioSpectrumSensitivity
    ) {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            self.overlayAnalyzer.updateConfiguration(style: style, sensitivity: sensitivity)
            self.onLevels?(Array(repeating: 0, count: self.barCount))
        }
    }

    /// 任一消费者存在才采集；全部撤销时释放 tap 与聚合设备。
    private var hasActiveConsumer: Bool {
        overlayEnabled || webEnabled || sceneEnabled
    }

    private func startCaptureIfNeeded() {
        guard hasActiveConsumer else { return }
        guard tapID == kAudioObjectUnknown, aggregateDeviceID == kAudioObjectUnknown else { return }
        guard #available(macOS 14.2, *) else {
            NSLog("MWX AUDIO CAPTURE: unavailable before macOS 14.2")
            resetConsumersAfterCaptureFailure()
            return
        }

        do {
            captureRetryWorkItem?.cancel()
            captureRetryWorkItem = nil
            let excludedProcessIDs = SystemAudioCaptureDeviceFactory.currentProcessObjectID().map { [$0] } ?? []
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

            let aggregateID = try SystemAudioCaptureDeviceFactory.createAggregateDevice(tapUID: tapUID)
            aggregateDeviceID = aggregateID
            SystemAudioCaptureDeviceFactory.configureCaptureBufferFrameSize(for: aggregateID)
            captureResourceGeneration += 1
            let resourceGeneration = captureResourceGeneration
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
                self?.processAudioBufferList(inInputData)
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
                "MWX AUDIO CAPTURE: started generation=%d sampleRate=%.0f channels=%u",
                captureGeneration,
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
        let hasCaptureResources = tapID != kAudioObjectUnknown
            || aggregateDeviceID != kAudioObjectUnknown
            || ioProcID != nil
        if shouldCapture {
            if !hasCaptureResources,
               captureRetryWorkItem == nil,
               captureRestartWorkItem == nil {
                startCaptureIfNeeded()
            }
            return
        }

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
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.captureRetryWorkItem = nil
            self.startCaptureIfNeeded()
        }
        captureRetryWorkItem?.cancel()
        captureRetryWorkItem = workItem
        NSLog("MWX AUDIO CAPTURE: retry scheduled attempt=%d delay=%.1f", captureRetryAttempt, delay)
        sampleQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleCaptureRestart(reason: String, generation: Int) {
        guard generation == captureResourceGeneration,
              hasActiveConsumer,
              tapID != kAudioObjectUnknown,
              aggregateDeviceID != kAudioObjectUnknown else { return }
        captureRestartSequence += 1
        let sequence = captureRestartSequence
        captureRestartWorkItem?.cancel()
        NSLog("MWX AUDIO CAPTURE: invalidated reason=%@ generation=%d", reason, generation)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.captureRestartSequence == sequence,
                  self.captureResourceGeneration == generation,
                  self.hasActiveConsumer else { return }
            self.captureRestartWorkItem = nil
            NSLog("MWX AUDIO CAPTURE: restarting reason=%@ generation=%d", reason, generation)
            self.stopCapture()
            self.scheduleCaptureStartAfterRestart()
        }
        captureRestartWorkItem = workItem
        sampleQueue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func scheduleCaptureStartAfterRestart() {
        guard hasActiveConsumer else { return }
        captureRestartSequence += 1
        let sequence = captureRestartSequence
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.captureRestartSequence == sequence,
                  self.hasActiveConsumer else { return }
            self.captureRestartWorkItem = nil
            self.startCaptureIfNeeded()
        }
        captureRestartWorkItem = workItem
        NSLog("MWX AUDIO CAPTURE: restart waiting delay=1.0")
        sampleQueue.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func cancelCaptureRestart() {
        captureRestartSequence += 1
        captureRestartWorkItem?.cancel()
        captureRestartWorkItem = nil
    }

    private func stopCapture() {
        let hadCapture = aggregateDeviceID != kAudioObjectUnknown || tapID != kAudioObjectUnknown
        cancelCaptureRestart()
        captureResourceGeneration += 1
        configurationMonitor.remove()
        if aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }

        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = kAudioObjectUnknown
        }

        tapStreamFormat = AudioStreamBasicDescription()
        captureBuffer.reset()
        lastProcessedAt = 0
        onLevels?(overlayAnalyzer.reset())
        onWebLevels?(Self.clearedWebLevels)
        clearSceneLevels()
        if hadCapture {
            NSLog("MWX AUDIO CAPTURE: stopped")
        }
    }

#if DEBUG
    func debugSimulateCaptureConfigurationInvalidation() {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            self.scheduleCaptureRestart(reason: "debug", generation: self.captureResourceGeneration)
        }
    }
#endif

    private func resetConsumersAfterCaptureFailure() {
        overlayEnabled = false
        webEnabled = false
        sceneEnabled = false
        onLevels?(overlayAnalyzer.reset())
        onWebLevels?(Self.clearedWebLevels)
        clearSceneLevels()
    }

    private func processAudioBufferList(_ inputData: UnsafePointer<AudioBufferList>) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastProcessedAt >= processingMinInterval else { return }
        lastProcessedAt = now
        guard processingGate.wait(timeout: .now()) == .success else { return }
        guard captureBuffer.capture(inputData, streamDescription: tapStreamFormat) else {
            processingGate.signal()
            return
        }
        processingSource.add(data: 1)
    }

    private func processCapturedAudio() {
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
        if overlayEnabled {
            onLevels?(
                overlayAnalyzer.analyze(
                    rectifiedMono: frame.rectifiedMono,
                    sampleRate: sampleRate
                )
            )
        }
        if webEnabled {
            onWebLevels?(webAnalyzer.analyze(frame, sampleRate: sampleRate))
        }
        if sceneEnabled {
            guard let sceneAnalyzer else {
                // FFT setup 不可用时保持稳定零输入，不产生假波形。
                clearSceneLevels()
                return
            }
            let bands = sceneAnalyzer.analyze(frame, sampleRate: sampleRate)
            onSceneLevels?(bands.left, bands.right, bands.left64, bands.right64)
        }
    }

    private func clearSceneLevels() {
        onSceneLevels?(
            Self.clearedSceneLevels,
            Self.clearedSceneLevels,
            Self.clearedExtendedSceneLevels,
            Self.clearedExtendedSceneLevels
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
}
