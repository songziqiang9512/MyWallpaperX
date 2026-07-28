//
//  SystemAudioSceneSpectrumAnalyzer.swift
//  MyWallpaperX
//

import Accelerate

/// Scene 侧 16/32/64 频段频谱分析。
///
/// 与 `SystemAudioWebSpectrumAnalyzer` 刻意分开实现：Web 壁纸走固定 64+64 频段并叠加
/// 为兼容 Wallpaper Engine Web 运行时而调出的增益/指数常量，Scene 的 stock shader
/// stock 合同是 16 频段，严格 Workshop consumer 另需 32/64 频段；三者都从同一次 FFT
/// 取左右分离、正值、由低到高的快照。Web 与 Scene 两套数值合同互不适用。合并成一个可参数化
/// 的分析器会让任一侧的调参隐式影响另一侧，因此这里保留独立实现而不是抽公共层。
///
/// 未知项：官方没有公开 16 频段的频率边界、幅度归一化与平滑策略。下面的频率范围与
/// dB 映射是本项目的工程选择，只保证「正值、低到高、静音为零、同输入同输出」，
/// 不构成与 Wallpaper Engine 的数值等价。
final class SystemAudioSceneSpectrumAnalyzer {
    static let bandCount = SceneAudioSpectrumSnapshot.bandCount
    static let mediumBandCount = SceneAudioSpectrumSnapshot.mediumBandCount
    static let extendedBandCount = SceneAudioSpectrumSnapshot.extendedBandCount

    struct Levels {
        let left: [Float]
        let right: [Float]
        let left32: [Float]
        let right32: [Float]
        let left64: [Float]
        let right64: [Float]
    }

    /// 频段下沿。低于此频率的分量并入首段。
    private let minimumFrequency: Float = 32
    /// 频段上沿，同时受 Nyquist 限制。
    private let maximumFrequency: Float = 16000
    /// 映射到 0 的幅度下限。
    private let minimumDecibels: Float = -80

    private let fftSize = 4096
    private let log2FFTSize: vDSP_Length
    private let fftSetup: FFTSetup
    private let hannWindow: [Float]
    private let amplitudeScale: Float

    init?() {
        let log2Size = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2Size, FFTRadix(kFFTRadix2)) else {
            return nil
        }
        log2FFTSize = log2Size
        fftSetup = setup

        var window = Array(repeating: Float(0), count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        hannWindow = window
        amplitudeScale = 2 / max(window.reduce(0, +), 1)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// 返回 (left, right)。单声道输入时右声道复制左声道，与 stock shader
    /// `AUDIOPROCESSING=3` 的左右平均语义保持一致（平均值等于该单声道）。
    func analyze(
        _ frame: SystemAudioCapturedFrame,
        sampleRate: Float
    ) -> Levels {
        analyze(signedChannels: frame.signedChannels, sampleRate: sampleRate)
    }

    func analyze(
        signedChannels: [[Float]],
        sampleRate: Float
    ) -> Levels {
        guard let leftChannel = signedChannels.first else {
            return Self.zeroLevels
        }
        let left = levels(for: leftChannel, sampleRate: sampleRate)
        guard signedChannels.count > 1 else {
            return Levels(
                left: left.base,
                right: left.base,
                left32: left.medium,
                right32: left.medium,
                left64: left.extended,
                right64: left.extended
            )
        }
        let right = levels(for: signedChannels[1], sampleRate: sampleRate)
        return Levels(
            left: left.base,
            right: right.base,
            left32: left.medium,
            right32: right.medium,
            left64: left.extended,
            right64: right.extended
        )
    }

    private func levels(
        for samples: [Float],
        sampleRate: Float
    ) -> (base: [Float], medium: [Float], extended: [Float]) {
        guard !samples.isEmpty, sampleRate.isFinite, sampleRate > 64 else {
            return (Self.zeroBands, Self.zeroMediumBands, Self.zeroExtendedBands)
        }

        let magnitudes = magnitudeSpectrum(for: samples)
        let nyquist = sampleRate * 0.5
        let upperBound = min(maximumFrequency, nyquist)
        let binWidth = sampleRate / Float(fftSize)
        guard upperBound > minimumFrequency, binWidth > 0 else {
            return (Self.zeroBands, Self.zeroMediumBands, Self.zeroExtendedBands)
        }
        return (
            bandLevels(magnitudes, upperBound: upperBound, binWidth: binWidth, count: Self.bandCount),
            bandLevels(
                magnitudes,
                upperBound: upperBound,
                binWidth: binWidth,
                count: Self.mediumBandCount
            ),
            bandLevels(
                magnitudes,
                upperBound: upperBound,
                binWidth: binWidth,
                count: Self.extendedBandCount
            )
        )
    }

    private func bandLevels(
        _ magnitudes: [Float],
        upperBound: Float,
        binWidth: Float,
        count: Int
    ) -> [Float] {
        var levels = Array(repeating: Float(0), count: count)
        let ratio = upperBound / minimumFrequency
        for band in 0 ..< count {
            let lowerProgress = Float(band) / Float(count)
            let upperProgress = Float(band + 1) / Float(count)
            let lowerFrequency = minimumFrequency * pow(ratio, lowerProgress)
            let upperFrequency = minimumFrequency * pow(ratio, upperProgress)
            // bin 0 是直流分量，恒定跳过。
            let lowerBin = max(1, Int(floor(lowerFrequency / binWidth)))
            let upperBin = min(
                magnitudes.count,
                max(lowerBin + 1, Int(ceil(upperFrequency / binWidth)))
            )
            guard lowerBin < upperBin else { continue }

            var peak: Float = 0
            for bin in lowerBin ..< upperBin where magnitudes[bin].isFinite {
                peak = max(peak, magnitudes[bin])
            }
            levels[band] = normalizedLevel(forAmplitude: peak)
        }
        return levels
    }

    private func magnitudeSpectrum(for samples: [Float]) -> [Float] {
        let sampleCount = min(samples.count, fftSize)
        let sourceStart = samples.count - sampleCount
        let tail = samples[sourceStart...].map { $0.isFinite ? $0 : 0 }
        // 去直流：麦克风/回环采集常带固定偏置，不减均值会把能量堆到最低频段。
        let mean = tail.reduce(0, +) / Float(tail.count)

        var input = Array(repeating: Float(0), count: fftSize)
        let destinationStart = fftSize - sampleCount
        for index in tail.indices {
            input[destinationStart + index] = tail[index] - mean
        }

        var windowed = Array(repeating: Float(0), count: fftSize)
        vDSP_vmul(input, 1, hannWindow, 1, &windowed, 1, vDSP_Length(fftSize))

        let halfSize = fftSize / 2
        var real = Array(repeating: Float(0), count: halfSize)
        var imaginary = Array(repeating: Float(0), count: halfSize)
        windowed.withUnsafeMutableBufferPointer { inputPointer in
            real.withUnsafeMutableBufferPointer { realPointer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                    var split = DSPSplitComplex(
                        realp: realPointer.baseAddress!,
                        imagp: imaginaryPointer.baseAddress!
                    )
                    inputPointer.baseAddress!.withMemoryRebound(
                        to: DSPComplex.self,
                        capacity: halfSize
                    ) { complexPointer in
                        vDSP_ctoz(complexPointer, 2, &split, 1, vDSP_Length(halfSize))
                    }
                    vDSP_fft_zrip(
                        fftSetup,
                        &split,
                        1,
                        log2FFTSize,
                        FFTDirection(FFT_FORWARD)
                    )
                }
            }
        }

        var magnitudes = Array(repeating: Float(0), count: halfSize)
        for bin in 0 ..< halfSize {
            magnitudes[bin] = hypot(real[bin], imaginary[bin]) * amplitudeScale
        }
        return magnitudes
    }

    private func normalizedLevel(forAmplitude amplitude: Float) -> Float {
        guard amplitude.isFinite, amplitude > 0 else { return 0 }
        let decibels = 20 * log10(amplitude)
        guard decibels.isFinite else { return 0 }
        let normalized = (decibels - minimumDecibels) / -minimumDecibels
        return min(1, max(0, normalized))
    }

    private static var zeroBands: [Float] {
        Array(repeating: 0, count: bandCount)
    }

    private static var zeroExtendedBands: [Float] {
        Array(repeating: 0, count: extendedBandCount)
    }

    private static var zeroMediumBands: [Float] {
        Array(repeating: 0, count: mediumBandCount)
    }

    private static var zeroLevels: Levels {
        Levels(
            left: zeroBands,
            right: zeroBands,
            left32: zeroMediumBands,
            right32: zeroMediumBands,
            left64: zeroExtendedBands,
            right64: zeroExtendedBands
        )
    }
}
