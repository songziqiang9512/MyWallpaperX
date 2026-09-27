import Foundation
import AppKit

extension WallpaperEngine {
    /// Runtime projection only. Manual intent and system policy live in the shared control plane.
    func applyPlaybackPaused(_ paused: Bool) {
        guard playbackPaused != paused else { return }
        playbackPaused = paused
        if currentPlaybackContentKind == .web,
           currentWebHostStrategy == .dedicatedHostPlaceholder {
            dispatchWebRuntimeCommand(paused ? .pause : .resume(playbackRate: targetPlaybackRate))
        }
        // A preparing Web surface may still retain the previous video sessions.
        // Every live surface obeys the same result throughout the transition.
        for session in displaySessions.values where session.process.isRunning {
            sendPlaybackPaused(paused, to: session)
        }
        refreshSystemAudioSpectrumCapture()
    }

    /// Also sent after every play request, so a new/restarted helper cannot miss
    /// a policy transition that happened before it existed.
    func sendPlaybackPaused(_ paused: Bool, to session: DisplayDaemonSession) {
        send(DaemonCommand(action: paused ? "pause" : "resume", videoPath: nil,
            framePath: nil, webRootPath: nil, propertiesJSON: nil, fillMode: nil,
            shouldLoopCurrentItem: nil, volume: nil, playbackRate: targetPlaybackRate,
            spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil,
            spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil,
            spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
    }

    @objc func handleScreenParametersChanged() {
        scanDisplays()
        guard let currentWallpaper else { return }
        applyWallpaper(currentWallpaper, multiDisplayEnabled: currentMultiDisplayEnabled,
            videoFillMode: currentVideoFillMode, shouldLoopCurrentItem: currentShouldLoopCurrentItem)
    }
}
