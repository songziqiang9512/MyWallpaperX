//
//  WallpaperEngine+SystemAudioSpectrum.swift
//  MyWallpaperX
//

import Foundation
import QuartzCore

extension WallpaperEngine {
    func makeSystemAudioSpectrumService(barCount: Int) -> SystemAudioSpectrumService {
        let service = SystemAudioSpectrumService(barCount: barCount)
        service.onLevels = { [weak self] levels in
            DispatchQueue.main.async {
                self?.updateSystemAudioSpectrumLevels(levels)
            }
        }
        service.onWebLevels = { [weak self] levels in
            DispatchQueue.main.async {
                self?.updateWebAudioSpectrumLevels(levels)
            }
        }
        // Scene 消费者按渲染帧自行采样，这里直接发布到 inbox，不经过主队列，
        // 避免在 30 Hz 采集与 60 Hz 渲染之间多插一层调度延迟。
        service.onSceneLevels = { left, right, left32, right32, left64, right64 in
            SceneAudioSpectrumInbox.shared.publish(
                left: left,
                right: right,
                left32: left32,
                right32: right32,
                left64: left64,
                right64: right64
            )
        }
        return service
    }

    /// 由 `SceneAudioSpectrumInbox` 的需求变化驱动。Scene 没有消费者时不采集。
    func observeSceneAudioSpectrumDemand() {
        SceneAudioSpectrumInbox.shared.setDemandObserver { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshSystemAudioSpectrumCapture()
            }
        }
    }

    public func setSystemAudioSpectrumEnabled(_ enabled: Bool) {
        configureSystemAudioSpectrum(
            enabled: enabled,
            style: .balanced,
            sensitivity: .normal,
            colorHex: currentSystemAudioSpectrumColorHex,
            offsetX: currentSystemAudioSpectrumOffsetX,
            offsetY: currentSystemAudioSpectrumOffsetY,
            barCount: currentSystemAudioSpectrumBarCount,
            peakCapsEnabled: currentSystemAudioSpectrumPeakCapsEnabled
        )
    }

    public func configureSystemAudioSpectrum(
        enabled: Bool,
        style: SystemAudioSpectrumStyle,
        sensitivity: SystemAudioSpectrumSensitivity,
        colorHex: String,
        offsetX: Float,
        offsetY: Float,
        barCount: Int,
        peakCapsEnabled: Bool
    ) {
        let normalizedBarCount = max(12, min(48, barCount))
        let previousBarCount = currentSystemAudioSpectrumBarCount
        currentSystemAudioSpectrumEnabled = enabled
        currentSystemAudioSpectrumColorHex = colorHex
        currentSystemAudioSpectrumOffsetX = max(-0.35, min(0.35, offsetX))
        currentSystemAudioSpectrumOffsetY = max(-0.35, min(0.35, offsetY))
        currentSystemAudioSpectrumBarCount = normalizedBarCount
        currentSystemAudioSpectrumPeakCapsEnabled = peakCapsEnabled
        currentSpectrumLevels = Array(repeating: 0, count: normalizedBarCount)
        lastSpectrumPushAt = 0

        if normalizedBarCount != previousBarCount {
            systemAudioSpectrumService.setConsumers(overlayEnabled: false, webEnabled: false)
            systemAudioSpectrumService = makeSystemAudioSpectrumService(barCount: normalizedBarCount)
        }
        systemAudioSpectrumService.updateConfiguration(style: style, sensitivity: sensitivity)
        refreshSystemAudioSpectrumCapture()

        if currentPlaybackContentKind == .web {
            let webLevels = currentWebAudioSpectrumRequested
                ? (currentWebSpectrumSnapshot() ?? clearedWebSpectrumLevels())
                : clearedWebSpectrumLevels()
            lastWebSpectrumLevels = webLevels
            dispatchWebRuntimeCommand(.pushAudioSpectrum(webLevels))
        }

        for session in displaySessions.values where session.process.isRunning {
            send(
                DaemonCommand(
                    action: "setSpectrumEnabled",
                    videoPath: nil,
                    framePath: nil,
                    webRootPath: nil,
                    propertiesJSON: nil,
                    fillMode: nil,
                    shouldLoopCurrentItem: nil,
                    volume: nil,
                    playbackRate: nil,
                    spectrumEnabled: enabled,
                    spectrumLevels: currentSpectrumLevels,
                    spectrumBarCount: normalizedBarCount,
                    spectrumColorHex: colorHex,
                    spectrumOffsetX: currentSystemAudioSpectrumOffsetX,
                    spectrumOffsetY: currentSystemAudioSpectrumOffsetY,
                    spectrumPeakCapsEnabled: peakCapsEnabled,
                    requestID: nil
                ),
                to: session
            )
        }
    }

    func setWebAudioSpectrumRequested(_ requested: Bool) {
        guard currentWebAudioSpectrumRequested != requested else { return }
        currentWebAudioSpectrumRequested = requested
        lastWebSpectrumPushAt = 0
        lastWebSpectrumLevels = []

        if currentPlaybackContentKind == .web {
            let clearedLevels = clearedWebSpectrumLevels()
            lastWebSpectrumLevels = clearedLevels
            dispatchWebRuntimeCommand(.pushAudioSpectrum(clearedLevels))
        }
        refreshSystemAudioSpectrumCapture()
    }

    func refreshSystemAudioSpectrumCapture() {
        let captureAllowed = !playbackPaused && !screenLocked && !systemSleeping && !displaysSleeping
        let webCaptureRequested = captureAllowed
            && currentPlaybackContentKind == .web
            && currentWebAudioSpectrumRequested
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let debugScenePCMOwnsInbox = arguments.contains(
            "--mwx-debug-scene-audio-spectrum-fixture"
        )
        let debugSceneSilenceOwnsInbox = arguments.contains(
            "--mwx-debug-scene-audio-silence-fixture"
        )
        let debugSceneFixtureOwnsInbox = debugScenePCMOwnsInbox
            || debugSceneSilenceOwnsInbox
#else
        let debugScenePCMOwnsInbox = false
        let debugSceneSilenceOwnsInbox = false
        let debugSceneFixtureOwnsInbox = false
#endif
        // Scene 不走 daemon session，因此不参与 currentPlaybackContentKind 判定；
        // 需求完全由 Scene runtime 侧的消费者声明决定。
        let sceneCaptureRequested = captureAllowed
            && SceneAudioSpectrumInbox.shared.isDemanded
            && !debugSceneFixtureOwnsInbox
        if !SceneAudioSpectrumInbox.shared.isDemanded
            || debugSceneSilenceOwnsInbox {
            SceneAudioSpectrumInbox.shared.clearSnapshot()
        }
        systemAudioSpectrumService.setConsumers(
            overlayEnabled: captureAllowed && currentSystemAudioSpectrumEnabled,
            webEnabled: webCaptureRequested,
            sceneEnabled: sceneCaptureRequested
        )
    }

#if DEBUG
    func debugSimulateSystemAudioCaptureInvalidation() {
        systemAudioSpectrumService.debugSimulateCaptureConfigurationInvalidation()
    }
#endif

    public func updateSystemAudioSpectrumLevels(_ levels: [Float]) {
        guard currentSystemAudioSpectrumEnabled else { return }

        let now = CACurrentMediaTime()
        guard now - lastSpectrumPushAt >= spectrumPushMinInterval else { return }
        lastSpectrumPushAt = now

        let resizedLevels = resizedSpectrumLevels(levels, count: currentSystemAudioSpectrumBarCount)
        currentSpectrumLevels = resizedLevels
        for session in displaySessions.values where session.process.isRunning {
            send(
                DaemonCommand(
                    action: "setSpectrumLevels",
                    videoPath: nil,
                    framePath: nil,
                    webRootPath: nil,
                    propertiesJSON: nil,
                    fillMode: nil,
                    shouldLoopCurrentItem: nil,
                    volume: nil,
                    playbackRate: nil,
                    spectrumEnabled: nil,
                    spectrumLevels: resizedLevels,
                    spectrumBarCount: nil,
                    spectrumColorHex: nil,
                    spectrumOffsetX: nil,
                    spectrumOffsetY: nil,
                    spectrumPeakCapsEnabled: nil,
                    requestID: nil
                ),
                to: session
            )
        }
    }
}
