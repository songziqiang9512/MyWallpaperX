//
//  SystemAudioWebSpectrumAnalyzer.swift
//  MyWallpaperX
//

/// Web/Video runtime 的 typed projection。
///
/// PCM、FFT、频段定义和 temporal smoothing 全部由
/// `SystemAudioSceneSpectrumAnalyzer` 这个 shared producer 完成；这个类型只把
/// canonical 64-band L/R snapshot 交给 Web runtime，不再持有第二个 FFT setup。
final class SystemAudioWebSpectrumAnalyzer {
    static let channelBandCount = 64
    static let outputLevelCount = channelBandCount * 2

    func analyze(_ levels: SystemAudioSceneSpectrumAnalyzer.Levels) -> [Float] {
        let left = SystemAudioSceneSpectrumAnalyzer.resample(
            levels.left64,
            count: Self.channelBandCount
        )
        let right = SystemAudioSceneSpectrumAnalyzer.resample(
            levels.right64,
            count: Self.channelBandCount
        )
        return left + right
    }
}
