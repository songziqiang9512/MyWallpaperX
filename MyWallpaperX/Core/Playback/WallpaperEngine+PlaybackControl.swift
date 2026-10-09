import Foundation
import AppKit

extension WallpaperEngine {
    /// Runtime projection only. Manual intent and system policy live in the shared control plane.
    func applyPlaybackPaused(_ paused: Bool) {
        guard playbackPaused != paused else { return }
        playbackPaused = paused
        if currentPlaybackContentKind == .web {
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
            framePath: nil, propertiesJSON: nil, fillMode: nil,
            shouldLoopCurrentItem: nil, volume: nil, playbackRate: targetPlaybackRate,
            spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil,
            spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil,
            spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
    }

    @objc func handleScreenParametersChanged() {
        scanDisplays()
        if currentWallpaper == nil, pendingVideoRetirementOnWebReady {
            // web 准备窗内被保留的 video 会话（E2a-4）没有 currentWallpaper
            // 可供 applyWallpaper 收敛——拔掉的显示器对应的 daemon 会话在此
            // 剪枝，否则 web 失败回滚后幽灵会话对不存在的显示器持续解码
            // 且不静音（双份可听音频）。成功路径由 .ready 全量 terminate 覆盖。
            let onlineDisplays = Set(displayIDs)
            for displayID in displaySessions.keys where onlineDisplays.contains(displayID) == false {
                terminateSession(for: displayID)
            }
            return
        }
        guard let currentWallpaper else { return }
        applyWallpaper(currentWallpaper, multiDisplayEnabled: currentMultiDisplayEnabled,
            videoFillMode: currentVideoFillMode, shouldLoopCurrentItem: currentShouldLoopCurrentItem)
    }
}
