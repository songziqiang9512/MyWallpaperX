//
//  SystemAudioOverlaySpectrumAnalyzer.swift
//  MyWallpaperX
//

import Foundation

/// Video/overlay 的 typed projection。
///
/// 该类型不再接收 PCM，也不再拥有 FFT/window。所有引擎共用 Scene analyzer 产出的
/// canonical L/R bands；这里仅负责 stereo 合并、有限投影、显示风格和静态噪声门。
final class SystemAudioOverlaySpectrumAnalyzer {
    private let barCount: Int
    private var style: SystemAudioSpectrumStyle = .balanced
    private var sensitivity: SystemAudioSpectrumSensitivity = .normal

    init(barCount: Int) {
        precondition(barCount > 0)
        self.barCount = barCount
    }

    func updateConfiguration(
        style: SystemAudioSpectrumStyle,
        sensitivity: SystemAudioSpectrumSensitivity
    ) {
        self.style = style
        self.sensitivity = sensitivity
        reset()
    }

    @discardableResult
    func reset() -> [Float] {
        // Kept as an endpoint reset for the shared capture service. The overlay
        // projection is stateless, so no previous frame can leak into the next
        // typed snapshot.
        return Array(repeating: 0, count: barCount)
    }

    func analyze(leftLevels: [Float], rightLevels: [Float]) -> [Float] {
        let count = min(leftLevels.count, rightLevels.count)
        guard count > 0 else { return reset() }
        let stereoLevels = (0..<count).map { index in
            let left = leftLevels[index].isFinite ? max(0, leftLevels[index]) : 0
            let right = rightLevels[index].isFinite ? max(0, rightLevels[index]) : 0
            return min(1, sqrt((left * left + right * right) * 0.5))
        }
        let projected = SystemAudioSceneSpectrumAnalyzer.resample(
            stereoLevels,
            count: barCount
        )
        return styledLevels(projected)
    }

    private func styledLevels(_ levels: [Float]) -> [Float] {
        guard !levels.isEmpty else { return levels }
        let sensitivityGain: Float
        switch sensitivity {
        case .soft: sensitivityGain = style == .balanced ? 0.86 : 0.88
        case .normal: sensitivityGain = 1
        case .lively: sensitivityGain = style == .balanced ? 1.16 : 1.18
        }
        // Style and sensitivity are intentionally static per-band transforms.
        // Do not normalize against a frame-wide peak or blend neighboring/global
        // bands: those operations erase the authored frequency shape before it
        // reaches the overlay.
        let styleGain: Float = style == .balanced ? 1 : 1.05
        let noiseGate: Float = style == .balanced ? 0.002 : 0.001
        return levels.map { level in
            let finiteLevel = level.isFinite ? max(0, level) : 0
            guard finiteLevel > noiseGate else { return 0 }
            return min(1, finiteLevel * styleGain * sensitivityGain)
        }
    }
}
