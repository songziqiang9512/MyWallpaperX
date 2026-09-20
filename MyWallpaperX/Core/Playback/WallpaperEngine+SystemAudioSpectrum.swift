//
//  WallpaperEngine+SystemAudioSpectrum.swift
//  MyWallpaperX
//

import Foundation
import QuartzCore

nonisolated struct SceneAudioSpectrumRoutedFrame: Sendable {
    let left: [Float]
    let right: [Float]
    let left32: [Float]
    let right32: [Float]
    let left64: [Float]
    let right64: [Float]
    let captureToken: SceneAudioSpectrumCaptureToken
}

extension WallpaperEngine {
    func makeSystemAudioSpectrumService(barCount: Int) -> SystemAudioSpectrumService {
        let service = SystemAudioSpectrumService(barCount: barCount)
        service.onLevels = { [weak self] levels in
            guard let self else { return }
            systemAudioSpectrumLevelHandoff.submit(levels) { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    self?.drainLatestSystemAudioSpectrumLevels()
                }
            }
        }
        service.onWebLevels = { [weak self] levels in
            guard let self else { return }
            webAudioSpectrumLevelHandoff.submit(levels) { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    self?.drainLatestWebAudioSpectrumLevels()
                }
            }
        }
        // Capture owns one FFT producer. Main-queue routing chooses exactly one
        // active Scene endpoint: the in-process DEBUG host or the product daemon.
        service.onSceneLevels = { [weak self]
            left, right, left32, right32, left64, right64,
            token in
            guard let self else { return }
            let frame = SceneAudioSpectrumRoutedFrame(
                left: left,
                right: right,
                left32: left32,
                right32: right32,
                left64: left64,
                right64: right64,
                captureToken: token
            )
            sceneAudioSpectrumRouteHandoff.submit(frame) { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    self?.drainLatestSceneAudioSpectrumFrame()
                }
            }
        }
        return service
    }

    private func drainLatestSystemAudioSpectrumLevels() {
        guard let levels = systemAudioSpectrumLevelHandoff.takeLatest() else {
            return
        }
        updateSystemAudioSpectrumLevels(levels)
    }

    private func drainLatestWebAudioSpectrumLevels() {
        guard let levels = webAudioSpectrumLevelHandoff.takeLatest() else {
            return
        }
        updateWebAudioSpectrumLevels(levels)
    }

    /// 由 `SceneAudioSpectrumInbox` 的需求变化驱动。Scene 没有消费者时不采集。
    func observeSceneAudioSpectrumDemand() {
        SceneAudioSpectrumInbox.shared.setDemandObserver { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshSystemAudioSpectrumCapture()
            }
        }
    }

    /// Updates the only remote Scene capture consumer. A generation-bound
    /// demand cannot survive daemon restart or publish into a replacement
    /// endpoint with a coincidentally equal local scope epoch.
    func setSceneDaemonAudioSpectrumDemand(
        _ demand: SceneAudioSpectrumCaptureDemand,
        generation: UInt64
    ) {
        if demand.requiresSpectrum {
            sceneDaemonAudioSpectrumDemand = demand
            sceneDaemonAudioSpectrumGeneration = generation
        } else if sceneDaemonAudioSpectrumGeneration == generation {
            sceneDaemonAudioSpectrumDemand = .none
            sceneDaemonAudioSpectrumGeneration = nil
        }
        refreshSystemAudioSpectrumCapture()
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
        currentSystemAudioSpectrumEnabled = enabled
        currentSystemAudioSpectrumColorHex = colorHex
        currentSystemAudioSpectrumOffsetX = max(-0.35, min(0.35, offsetX))
        currentSystemAudioSpectrumOffsetY = max(-0.35, min(0.35, offsetY))
        currentSystemAudioSpectrumBarCount = normalizedBarCount
        currentSystemAudioSpectrumPeakCapsEnabled = peakCapsEnabled
        currentSpectrumLevels = Array(repeating: 0, count: normalizedBarCount)
        lastSpectrumPushAt = 0

        systemAudioSpectrumService.updateConfiguration(
            style: style,
            sensitivity: sensitivity,
            barCount: normalizedBarCount
        )
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
        let localSceneDemand = SceneAudioSpectrumInbox.shared.captureDemand
        let remoteSceneDemand = sceneDaemonAudioSpectrumDemand
        // Product Scene executes in the daemon. Its request takes precedence
        // over the mutually exclusive direct-host DEBUG route. The tap remains
        // in the main App, so excluding the main process still naturally
        // includes sound emitted by the daemon process.
        let requestedRoute = SceneAudioSpectrumCaptureRoutingState.resolvedRoute(
            captureAllowed: captureAllowed,
            debugFixtureOwnsInbox: debugSceneFixtureOwnsInbox,
            localDemand: localSceneDemand,
            daemonDemand: remoteSceneDemand,
            daemonGeneration: sceneDaemonAudioSpectrumGeneration
        )
        if sceneAudioSpectrumCaptureRouting.update(route: requestedRoute) {
            sceneAudioSpectrumRouteHandoff.discardPendingValue()
        }
        let sceneCaptureRequested = requestedRoute != .none
        if !localSceneDemand.requiresSpectrum
            || !captureAllowed
            || debugSceneSilenceOwnsInbox {
            SceneAudioSpectrumInbox.shared.clearSnapshot()
        }
        systemAudioSpectrumService.setConsumers(
            overlayEnabled: captureAllowed && currentSystemAudioSpectrumEnabled,
            webEnabled: webCaptureRequested,
            sceneEnabled: sceneCaptureRequested,
            includeCurrentProcessAudio:
                requestedRoute.includesCaptureProcessOutput,
            sceneCaptureScopeEpoch: sceneAudioSpectrumCaptureRouting.scopeEpoch
        )
    }

    private func drainLatestSceneAudioSpectrumFrame() {
        guard let frame = sceneAudioSpectrumRouteHandoff.takeLatest(),
              sceneAudioSpectrumCaptureRouting.accepts(frame.captureToken) else {
            return
        }
        switch sceneAudioSpectrumCaptureRouting.route {
        case .none:
            return
        case let .daemon(demand, generation):
            // `captureToken` describes the main-App tap, which must exclude the
            // main process for a daemon target. The transported token instead
            // preserves the daemon-local demand identity.
            SceneDaemonClient.shared.publishAudioSpectrum(
                left: frame.left,
                right: frame.right,
                left32: frame.left32,
                right32: frame.right32,
                left64: frame.left64,
                right64: frame.right64,
                token: SceneAudioSpectrumCaptureToken(
                    scopeEpoch: demand.scopeEpoch,
                    includesCurrentProcessOutput: demand
                        .includesCurrentProcessOutput
                ),
                generation: generation
            )
        case let .local(demand):
            SceneAudioSpectrumInbox.shared.publishSystemCapture(
                left: frame.left,
                right: frame.right,
                left32: frame.left32,
                right32: frame.right32,
                left64: frame.left64,
                right64: frame.right64,
                token: SceneAudioSpectrumCaptureToken(
                    scopeEpoch: demand.scopeEpoch,
                    includesCurrentProcessOutput:
                        demand.includesCurrentProcessOutput
                )
            )
        }
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
