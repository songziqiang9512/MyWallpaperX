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
                && currentWebAudioSpectrumRequested
            if activeWeb {
                // Input rejection is reported with false, but an active Web
                // consumer still needs an immediate typed silence publication
                // so a prior non-zero frame cannot remain frozen on screen.
                dispatchWebRuntimeCommand(
                    .pushAudioSpectrum(clearedWebSpectrumLevels())
                )
            }
            return false
        }
        guard currentPlaybackContentKind == .web,
              currentWebAudioSpectrumRequested else {
            return false
        }

        // The shared producer already performed the only nonlinear visual
        // response and fast-attack/slow-release envelope. Web dispatch is a
        // typed handoff, so it must not compress or smooth the same snapshot a
        // second time and turn sharp transients into a long tail.
        let outputLevels = levels.map { level -> Float in
            return max(level, 0)
        }
        // Service is the sole cadence owner. Forward every complete snapshot,
        // including silence, so callback quantization cannot halve Web updates.
        lastWebSpectrumLevels = outputLevels
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
