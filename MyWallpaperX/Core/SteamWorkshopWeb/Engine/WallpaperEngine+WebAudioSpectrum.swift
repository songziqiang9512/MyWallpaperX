//
//  WallpaperEngine+WebAudioSpectrum.swift
//  MyWallpaperX
//

import Foundation
import QuartzCore

extension WallpaperEngine {
    private static let webSpectrumSampleCount = 128

    func updateWebAudioSpectrumLevels(_ levels: [Float]) {
        _ = dispatchWebAudioSpectrumIfNeeded(levels)
    }

    @discardableResult
    func dispatchWebAudioSpectrumIfNeeded(_ levels: [Float]) -> Bool {
        guard levels.count == Self.webSpectrumSampleCount,
              levels.allSatisfy(\.isFinite) else {
            // A malformed capture must not leave either a pending value or the
            // previously published snapshot visible to the next Web consumer.
            lastWebSpectrumLevels = []
            let activeWeb = currentPlaybackContentKind == .web
                && currentSystemAudioSpectrumEnabled
                && currentWebAudioSpectrumRequested
            if activeWeb {
                // Input rejection is reported with false, but an active Web
                // consumer still needs an immediate typed silence publication
                // so a prior non-zero frame cannot remain frozen on screen.
                lastWebSpectrumPushAt = CACurrentMediaTime()
                dispatchWebRuntimeCommand(
                    .pushAudioSpectrum(clearedWebSpectrumLevels())
                )
            }
            return false
        }
        guard currentPlaybackContentKind == .web,
              currentSystemAudioSpectrumEnabled,
              currentWebAudioSpectrumRequested else {
            return false
        }

        let now = CACurrentMediaTime()
        // The shared producer already performed the only nonlinear visual
        // response and fast-attack/slow-release envelope. Web dispatch is a
        // typed handoff, so it must not compress or smooth the same snapshot a
        // second time and turn sharp transients into a long tail.
        let outputLevels = levels.map { level -> Float in
            return min(max(level, 0), 1)
        }
        // Keep the latest valid snapshot in the same slot while throttled. The
        // published command is intentionally separate in time, but readers must
        // still observe the newest pending value rather than an older command.
        lastWebSpectrumLevels = outputLevels
        // Silence is a revocation boundary: clear a running Web animation
        // immediately instead of allowing the throttle window to hold it.
        if outputLevels.allSatisfy({ $0 == 0 }) {
            lastWebSpectrumPushAt = now
            dispatchWebRuntimeCommand(.pushAudioSpectrum(outputLevels))
            return true
        }
        guard now - lastWebSpectrumPushAt >= webSpectrumPushMinInterval else {
            return true
        }
        lastWebSpectrumPushAt = now
        dispatchWebRuntimeCommand(.pushAudioSpectrum(outputLevels))
        return true
    }

    func currentWebSpectrumSnapshot() -> [Float]? {
        guard currentWebAudioSpectrumRequested else { return nil }
        guard lastWebSpectrumLevels.count == Self.webSpectrumSampleCount else {
            return clearedWebSpectrumLevels()
        }
        return lastWebSpectrumLevels
    }

    func clearedWebSpectrumLevels() -> [Float] {
        Array(repeating: 0, count: Self.webSpectrumSampleCount)
    }

}
