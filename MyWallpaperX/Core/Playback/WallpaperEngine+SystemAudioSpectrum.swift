//
//  WallpaperEngine+SystemAudioSpectrum.swift
//  MyWallpaperX
//

import Foundation
import QuartzCore

extension WallpaperEngine {
    static func makeSystemAudioSpectrumService(
        barCount: Int, delivery: PlaybackSpectrumDelivery
    ) -> SystemAudioSpectrumService {
        return SystemAudioSpectrumService(
            barCount: barCount,
            onLevels: { delivery.publishOverlay($0) },
            onWebLevels: { delivery.publishWeb($0) },
            onSceneLevels: {
                left, right, left32, right32, left64, right64, token in
                delivery.publishScene(.init(left: left, right: right,
                    left32: left32, right32: right32, left64: left64, right64: right64,
                    captureToken: token))
            }
        )
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

#if DEBUG
    /// Video-overlay policy entry. The public switch owns only the video
    /// overlay; Web/Scene capture follows sample-declared demand plus the
    /// shared pause gate and must not observe this bit. Product paths only
    /// use `configureSystemAudioSpectrum`; this entry survives for the
    /// DEBUG web runners.
    public func setSystemAudioSpectrumEnabled(_ enabled: Bool) {
        currentSystemAudioSpectrumEnabled = enabled
        currentSpectrumLevels = Array(
            repeating: 0,
            count: currentSystemAudioSpectrumBarCount
        )
        refreshSystemAudioSpectrumCapture()

        if currentPlaybackContentKind == .web {
            let webLevels = currentWebAudioSpectrumRequested
                ? (currentWebSpectrumSnapshot() ?? clearedWebSpectrumLevels())
                : clearedWebSpectrumLevels()
            dispatchWebRuntimeCommand(.pushAudioSpectrum(webLevels))
        }

        // Detailed daemon configuration is sent by
        // `configureSystemAudioSpectrum`. This policy-only entry point must
        // not send a second video-daemon spectrum command for the same
        // setting change; otherwise the settings path has two command owners.
    }
#endif

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
            dispatchWebRuntimeCommand(.pushAudioSpectrum(webLevels))
        }

        for session in displaySessions.values where session.process.isRunning {
            send(
                DaemonCommand(
                    action: "setSpectrumEnabled",
                    videoPath: nil,
                    framePath: nil,
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
        refreshSystemAudioSpectrumCapture()

        if currentPlaybackContentKind == .web {
            let clearedLevels = clearedWebSpectrumLevels()
            dispatchWebRuntimeCommand(.pushAudioSpectrum(clearedLevels))
        }
    }

    func refreshSystemAudioSpectrumCapture() {
        // The public spectrum switch gates only the video overlay. Web/Scene
        // capture is demand-driven: the sample declares audio listeners and
        // the shared pause gate stays the only global cut-off.
        let captureAllowed = !PlaybackCommandMultiplexer.shared.isPlaybackPaused
        let overlayCaptureRequested = captureAllowed && currentSystemAudioSpectrumEnabled
            && displaySessions.values.contains { $0.process.isRunning }
        // The Web adapter owns live request/surface demand, including a
        // prepared successor. UI adoption must not restart the shared tap.
        let webCaptureRequested = captureAllowed && currentWebAudioSpectrumRequested
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
        sceneAudioSpectrumCaptureRouting.update(route: requestedRoute)
        let sceneCaptureRequested = requestedRoute != .none
        if !localSceneDemand.requiresSpectrum
            || !captureAllowed
            || debugSceneSilenceOwnsInbox {
            SceneAudioSpectrumInbox.shared.clearSnapshot()
        }
        spectrumDelivery.configure(
            overlay: overlayCaptureRequested,
            web: webCaptureRequested, barCount: currentSystemAudioSpectrumBarCount,
            routing: sceneAudioSpectrumCaptureRouting,
            scene: SceneDaemonClient.shared.spectrumDeliveryTarget)
        systemAudioSpectrumService.setConsumers(
            overlayEnabled: overlayCaptureRequested,
            webEnabled: webCaptureRequested,
            sceneEnabled: sceneCaptureRequested,
            includeCurrentProcessAudio:
                requestedRoute.includesCaptureProcessOutput,
            sceneCaptureScopeEpoch: sceneAudioSpectrumCaptureRouting.scopeEpoch
        )
    }

#if DEBUG
    func debugSimulateSystemAudioCaptureInvalidation() {
        systemAudioSpectrumService.debugSimulateCaptureConfigurationInvalidation()
    }
#endif

}
