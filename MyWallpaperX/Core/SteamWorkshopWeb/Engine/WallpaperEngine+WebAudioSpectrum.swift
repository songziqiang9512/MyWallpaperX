//
//  WallpaperEngine+WebAudioSpectrum.swift
//  MyWallpaperX
//

import Foundation
import QuartzCore

extension WallpaperEngine {
    private static let webSpectrumSampleCount = 128

    func currentWebSpectrumSnapshot() -> [Float]? {
        guard currentWebAudioSpectrumRequested else { return nil }
        let latest = spectrumDelivery.currentWebLevels
        return latest.count == Self.webSpectrumSampleCount ? latest : clearedWebSpectrumLevels()
    }

    func clearedWebSpectrumLevels() -> [Float] {
        Array(repeating: 0, count: Self.webSpectrumSampleCount)
    }

}
