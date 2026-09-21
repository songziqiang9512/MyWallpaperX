//
//  SystemAudioOverlaySpectrumAnalyzer.swift
//  MyWallpaperX
//

import Foundation

/// Video/overlay 的 typed projection。
///
/// 该类型不再接收 PCM，也不再拥有 FFT/window。所有引擎共用 Scene analyzer 产出的
/// canonical L/R bands；这里仅负责 stereo 合并、有限投影、显示风格和本地快起慢落。
final class SystemAudioOverlaySpectrumAnalyzer {
    private let barCount: Int
    private var smoothedLevels: [Float]
    private var adaptiveCeiling: Float = 0.12
    private var style: SystemAudioSpectrumStyle = .balanced
    private var sensitivity: SystemAudioSpectrumSensitivity = .normal

    init(barCount: Int) {
        precondition(barCount > 0)
        self.barCount = barCount
        self.smoothedLevels = Array(repeating: 0, count: barCount)
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
        smoothedLevels = Array(repeating: 0, count: barCount)
        adaptiveCeiling = 0.12
        return smoothedLevels
    }

    func analyze(leftLevels: [Float], rightLevels: [Float]) -> [Float] {
        let count = min(leftLevels.count, rightLevels.count)
        guard count > 0 else { return smoothedLevels }
        let stereoLevels = (0..<count).map { index in
            let left = leftLevels[index].isFinite ? max(0, leftLevels[index]) : 0
            let right = rightLevels[index].isFinite ? max(0, rightLevels[index]) : 0
            return min(1, sqrt((left * left + right * right) * 0.5))
        }
        let projected = SystemAudioSceneSpectrumAnalyzer.resample(
            stereoLevels,
            count: barCount
        )
        let rawLevels = styledLevels(projected)
        var nextLevels = Array(repeating: Float(0), count: barCount)
        for index in nextLevels.indices {
            let incoming = rawLevels[index]
            let previous = smoothedLevels[index]
            if incoming >= previous {
                nextLevels[index] = previous * 0.34 + incoming * 0.66
            } else {
                nextLevels[index] = max(incoming, previous * 0.84)
            }
        }
        smoothedLevels = nextLevels
        return nextLevels
    }

    private func styledLevels(_ levels: [Float]) -> [Float] {
        guard !levels.isEmpty else { return levels }
        let peakLevel = levels.max() ?? 0
        if peakLevel > adaptiveCeiling {
            // A lagging ceiling clips every stronger band to one on a loud
            // frame, erasing the shape before the local envelope sees it.
            // Follow new peaks immediately; only the release is adaptive.
            adaptiveCeiling = peakLevel
        } else {
            adaptiveCeiling = max(0.02, adaptiveCeiling * 0.972)
        }
        let noiseFloor = adaptiveCeiling * (style == .balanced ? 0.07 : 0.04)
        let normalizationRange = max(0.001, adaptiveCeiling - noiseFloor)
        let normalized = levels.map { level in
            let value = max(0, level - noiseFloor) / normalizationRange
            return min(1, pow(value, style == .balanced ? 0.82 : 0.76))
        }
        let globalAverage = normalized.reduce(0, +) / Float(normalized.count)
        let sensitivityGain: Float
        switch sensitivity {
        case .soft: sensitivityGain = style == .balanced ? 0.86 : 0.88
        case .normal: sensitivityGain = 1
        case .lively: sensitivityGain = style == .balanced ? 1.16 : 1.18
        }
        return normalized.enumerated().map { index, level in
            let lower = max(0, index - 1)
            let upper = min(normalized.count - 1, index + 1)
            let neighborhood = normalized[lower...upper]
            let neighborAverage = neighborhood.reduce(0, +) / Float(neighborhood.count)
            let mixed = style == .balanced
                ? level * 0.52 + neighborAverage * 0.28 + globalAverage * 0.20
                : level * 0.70 + neighborAverage * 0.18 + globalAverage * 0.12
            let floorLift = globalAverage * (style == .balanced ? 0.14 : 0.04)
            return min(1, max(floorLift, pow(min(1, mixed * sensitivityGain), 0.92)))
        }
    }
}
