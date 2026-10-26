//
//  SystemAudioOverlaySpectrumAnalyzer.swift
//  MyWallpaperX
//

import Foundation

/// Video/overlay 的 typed projection。
///
/// 只投影共享分析器已完成分贝响应与平滑的最终高度；不持有FFT、自动增益
/// 或第二套包络。默认风格与Web/Scene同尺度，灵敏度是原生绘制的静态风格。
nonisolated final class SystemAudioOverlaySpectrumAnalyzer {
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
    }

    @discardableResult
    func reset() -> [Float] {
        // Kept as an endpoint reset for the shared capture service. The overlay
        // projection is stateless, so no previous frame can leak into the next
        // typed snapshot.
        return Array(repeating: 0, count: barCount)
    }

    func analyze(_ levels: SystemAudioSceneSpectrumAnalyzer.Levels) -> [Float] {
        let left = levels.left64, right = levels.right64
        let count = left.count
        guard count > 0 else { return reset() }
        let stereo = (0..<count).map { index -> Float in
            (left[index] + right[index]) * 0.5
        }
        let projected = SystemAudioSceneSpectrumAnalyzer.resample(stereo, count: barCount)
        let sensitivityGain: Float
        switch sensitivity {
        case .soft: sensitivityGain = style == .balanced ? 0.86 : 0.88
        case .normal: sensitivityGain = 1
        case .lively: sensitivityGain = style == .balanced ? 1.16 : 1.18
        }
        let gain = sensitivityGain * (style == .balanced ? 1 : 1.05)
        if gain == 1 { return projected }
        // A static bounded contrast adjustment preserves zero/one endpoints,
        // avoids clipping loud bars and adds no second temporal state.
        return projected.map { gain * $0 / (1 + (gain - 1) * $0) }
    }
}
