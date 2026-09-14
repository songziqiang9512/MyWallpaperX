//
//  WallpaperEngine+SystemAudioLifecycle.swift
//  MyWallpaperX
//

import Foundation

enum PlaybackSystemInterruption: Hashable {
    case screenLock
    case systemSleep
    case displaySleep
}

extension WallpaperEngine {
    @objc func handleScreenLocked() {
        screenLocked = true
        beginSystemInterruption(.screenLock)
    }

    @objc func handleScreenUnlocked() {
        screenLocked = false
        endSystemInterruption(.screenLock, evaluationDelay: 0.5)
    }

    @objc func handleWillSleep() {
        systemSleeping = true
        beginSystemInterruption(.systemSleep)
    }

    @objc func handleDidWake() {
        systemSleeping = false
        endSystemInterruption(.systemSleep, evaluationDelay: 0.5)
    }

    @objc func handleScreensDidSleep() {
        displaysSleeping = true
        beginSystemInterruption(.displaySleep)
    }

    @objc func handleScreensDidWake() {
        displaysSleeping = false
        endSystemInterruption(.displaySleep, evaluationDelay: 0.3)
    }

    private func beginSystemInterruption(_ interruption: PlaybackSystemInterruption) {
        guard activeSystemInterruptions.insert(interruption).inserted else { return }
        applySystemPlaybackPausedState(true)
    }

    private func endSystemInterruption(
        _ interruption: PlaybackSystemInterruption,
        evaluationDelay: TimeInterval
    ) {
        guard activeSystemInterruptions.remove(interruption) != nil else { return }
        guard activeSystemInterruptions.isEmpty else {
            refreshSystemAudioSpectrumCapture()
            return
        }
        requestPlaybackStateEvaluation(delay: evaluationDelay)
    }
}
