//
//  SystemAudioSceneSpectrumAnalyzer.swift
//  MyWallpaperX
//

import Accelerate

/// Wallpaper Engine Scene 侧音频频谱 producer。
///
/// 官方 `AudioProcessor` 一次产生左右各 64 个 peak band：输入先经过近似 Hann
/// 窗，FFT bin 以 `pow(progress, 0.500999987) * 64` 映射到 band；16/32 档是同一份
/// 64 档快照的降采样视图。官方线性 FFT 输出与 macOS 归一化 tap 的最终视觉响度并非
/// 同一合同，因此 band identity 后仍需项目自己的有界可视响应与时间平滑。
///
/// 官方 WASAPI 的分析窗会随采样率变化（44.1 kHz 时 1920 frames，最低保持该长度），
/// 同时只消费 640 个频率 bin。macOS 的系统 tap 回调边界不同，因此这里用滚动窗口聚合
/// 相同时间跨度，再用零填充 radix-2 FFT 取得同一频率范围；FFT backend 的差异不改变
/// 官方 band identity、线性幅度或 fail-closed 边界。
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

    private static let fftSize = 4096
    private static let fftHalfSize = fftSize / 2
    private static let officialReferenceSampleRate: Float = 44_100
    private static let officialWindowFrameCount: Float = 64 * 30
    private static let officialFrequencyBinCount: Float = 64 * 10
    private static let officialCurveExponent: Float = 0.5009999871253967
    private static let officialInputScale: Float = 0.001
    /// 沿用项目既有 Scene 响应下限：低于 -60 dBFS 的 tap 底噪稳定归零，以上保留
    /// 可见动态。它是 macOS producer 的平台适配，不冒充 Windows 私有增益常量。
    private static let minimumResponseDecibels: Float = -60
    /// 复用项目频带频谱已有的 0.74 根压缩，把正常音乐的中段动态抬到作者 shader
    /// 可见区间，同时保留上述 -60 dB 硬门和 0...1 上界。这里只改变幅度响应，
    /// 不改变官方频带索引，也不使用参考项目的频带表或常数组合。
    private static let visualCompressionExponent: Float = 0.74
    /// 复用项目已有系统频谱的快起/慢落包络。采集以约 30 Hz 发布，因此这两个系数
    /// 分别让真实起音及时出现、尾音连续衰减；它们不生成任何无输入周期信号。
    private static let attackMix: Float = 0.66
    private static let releaseRetention: Float = 0.84
    private static let settledSilenceThreshold: Float = 0.000_1

    private let log2FFTSize: vDSP_Length
    private let fftSetup: FFTSetup
    private var rollingChannels: [[Float]] = []
    private var rollingSampleRate: Float = 0
    private var cachedWindow: [Float] = []
    private var smoothedLeft64 = Array(repeating: Float(0), count: extendedBandCount)
    private var smoothedRight64 = Array(repeating: Float(0), count: extendedBandCount)

    init?() {
        let log2Size = vDSP_Length(log2(Float(Self.fftSize)))
        guard let setup = vDSP_create_fftsetup(log2Size, FFTRadix(kFFTRadix2)) else {
            return nil
        }
        log2FFTSize = log2Size
        fftSetup = setup
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// capture teardown / consumer revoke 时清空未完成窗口，避免重新启用后混入旧音频。
    func reset() {
        resetRollingState()
    }

    /// 单声道输入复制到左右两侧，使官方 `AUDIOPROCESSING=3` 的左右平均仍等于
    /// 该声道。空输入、非法采样率和未填满首个官方时间窗都稳定归零。
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
        guard sampleRate.isFinite, sampleRate > 0,
              let leftInput = signedChannels.first,
              !leftInput.isEmpty
        else {
            resetRollingState()
            return Self.zeroLevels
        }

        let channelInputs = Array(signedChannels.prefix(2))
        let windowCount = officialWindowCount(sampleRate: sampleRate)
        guard windowCount > 1, windowCount <= Self.fftSize else {
            resetRollingState()
            return Self.zeroLevels
        }
        prepareRollingState(
            channelCount: channelInputs.count,
            sampleRate: sampleRate
        )
        for channelIndex in channelInputs.indices {
            appendSanitized(
                channelInputs[channelIndex],
                to: &rollingChannels[channelIndex],
                maximumCount: windowCount
            )
        }
        guard rollingChannels.allSatisfy({ $0.count == windowCount }) else {
            return Self.zeroLevels
        }

        let rawLeft64 = officialBands(
            for: rollingChannels[0],
            sampleRate: sampleRate
        )
        let rawRight64: [Float]
        if rollingChannels.count > 1 {
            rawRight64 = officialBands(
                for: rollingChannels[1],
                sampleRate: sampleRate
            )
        } else {
            rawRight64 = rawLeft64
        }
        smoothedLeft64 = Self.visualLevels(
            rawLeft64,
            previous: smoothedLeft64
        )
        smoothedRight64 = Self.visualLevels(
            rawRight64,
            previous: smoothedRight64
        )
        return Levels(
            left: Self.averageResample(smoothedLeft64, count: Self.bandCount),
            right: Self.averageResample(smoothedRight64, count: Self.bandCount),
            left32: Self.averageResample(smoothedLeft64, count: Self.mediumBandCount),
            right32: Self.averageResample(smoothedRight64, count: Self.mediumBandCount),
            left64: smoothedLeft64,
            right64: smoothedRight64
        )
    }

    private func officialWindowCount(sampleRate: Float) -> Int {
        let rateScale = max(1, sampleRate / Self.officialReferenceSampleRate)
        return Int(rateScale * Self.officialWindowFrameCount)
    }

    private func prepareRollingState(channelCount: Int, sampleRate: Float) {
        let rateChanged = abs(rollingSampleRate - sampleRate) > 0.5
        guard rateChanged || rollingChannels.count != channelCount else { return }
        rollingSampleRate = sampleRate
        rollingChannels = Array(repeating: [], count: channelCount)
    }

    private func appendSanitized(
        _ input: [Float],
        to rolling: inout [Float],
        maximumCount: Int
    ) {
        if input.count >= maximumCount {
            rolling = input.suffix(maximumCount).map { $0.isFinite ? $0 : 0 }
            return
        }
        rolling.append(contentsOf: input.map { $0.isFinite ? $0 : 0 })
        if rolling.count > maximumCount {
            rolling.removeFirst(rolling.count - maximumCount)
        }
    }

    private func officialBands(
        for samples: [Float],
        sampleRate: Float
    ) -> [Float] {
        let magnitudes = magnitudeSpectrum(for: samples)
        let sourceBinWidth = sampleRate / Float(samples.count)
        let maximumFrequency = sourceBinWidth * Self.officialFrequencyBinCount
        let fftBinWidth = sampleRate / Float(Self.fftSize)
        let maximumFFTBin = min(
            magnitudes.count - 1,
            max(1, Int(floor(maximumFrequency / fftBinWidth)))
        )
        guard maximumFFTBin > 1 else { return Self.zeroExtendedBands }

        var peaks = Self.zeroExtendedBands
        var currentBand = 0
        for fftBin in 1 ... maximumFFTBin {
            let progress = Float(fftBin - 1) / Float(maximumFFTBin - 1)
            let mappedBand = min(
                Self.extendedBandCount - 1,
                max(0, Int(pow(progress, Self.officialCurveExponent)
                    * Float(Self.extendedBandCount)))
            )
            // 官方限制 band identity 每个 FFT bin 最多前进一档，避免低频曲线跳档。
            currentBand = min(mappedBand, currentBand + 1)
            let magnitude = magnitudes[fftBin]
            if magnitude.isFinite {
                peaks[currentBand] = max(peaks[currentBand], magnitude)
            }
        }

        let linearScale = Self.officialInputScale
            * (Self.officialFrequencyBinCount / (Float(samples.count) * 0.5))
        for index in peaks.indices {
            let scaled = peaks[index] * linearScale
            peaks[index] = scaled.isFinite && scaled > 0 ? scaled : 0
        }
        return peaks
    }

    private func magnitudeSpectrum(for samples: [Float]) -> [Float] {
        let window = officialWindow(count: samples.count)
        var input = Array(repeating: Float(0), count: Self.fftSize)
        for index in samples.indices {
            input[index] = samples[index] * window[index]
        }

        var real = Array(repeating: Float(0), count: Self.fftHalfSize)
        var imaginary = Array(repeating: Float(0), count: Self.fftHalfSize)
        input.withUnsafeMutableBufferPointer { inputPointer in
            real.withUnsafeMutableBufferPointer { realPointer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                    var split = DSPSplitComplex(
                        realp: realPointer.baseAddress!,
                        imagp: imaginaryPointer.baseAddress!
                    )
                    inputPointer.baseAddress!.withMemoryRebound(
                        to: DSPComplex.self,
                        capacity: Self.fftHalfSize
                    ) { complexPointer in
                        vDSP_ctoz(
                            complexPointer,
                            2,
                            &split,
                            1,
                            vDSP_Length(Self.fftHalfSize)
                        )
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

        var magnitudes = Array(repeating: Float(0), count: Self.fftHalfSize)
        for bin in magnitudes.indices {
            magnitudes[bin] = hypot(real[bin], imaginary[bin])
        }
        return magnitudes
    }

    private func officialWindow(count: Int) -> [Float] {
        if cachedWindow.count == count { return cachedWindow }
        guard count > 1 else { return Array(repeating: 0, count: count) }
        let inverseSpan = 1 / Float(count - 1)
        let center = Self.officialCurveExponent
        let edgeAmplitude = 1 - center
        cachedWindow = (0 ..< count).map { index in
            let phase = 2 * Float.pi * Float(index) * inverseSpan
            return center - cos(phase) * edgeAmplitude
        }
        return cachedWindow
    }

    private static func averageResample(_ values: [Float], count: Int) -> [Float] {
        guard values.count == extendedBandCount,
              count > 0,
              extendedBandCount.isMultiple(of: count)
        else {
            return Array(repeating: 0, count: count)
        }
        let stride = extendedBandCount / count
        return (0 ..< count).map { outputIndex in
            let start = outputIndex * stride
            let end = start + stride
            return values[start ..< end].reduce(0, +) / Float(stride)
        }
    }

    private static func visualLevels(
        _ linearLevels: [Float],
        previous: [Float]
    ) -> [Float] {
        guard linearLevels.count == extendedBandCount,
              previous.count == extendedBandCount
        else {
            return zeroExtendedBands
        }
        return zip(linearLevels, previous).map { linear, prior in
            let target = visualResponse(for: linear)
            let next: Float
            if target >= prior {
                next = prior * (1 - attackMix) + target * attackMix
            } else {
                next = max(target, prior * releaseRetention)
            }
            guard next.isFinite, next >= settledSilenceThreshold else { return 0 }
            return min(1, max(0, next))
        }
    }

    private static func visualResponse(for linearLevel: Float) -> Float {
        guard linearLevel.isFinite, linearLevel > 0 else { return 0 }
        let decibels = 20 * log10(linearLevel)
        guard decibels.isFinite, decibels > minimumResponseDecibels else { return 0 }
        let normalized = min(
            1,
            max(0, (decibels - minimumResponseDecibels) / -minimumResponseDecibels)
        )
        return pow(normalized, visualCompressionExponent)
    }

    private func resetRollingState() {
        rollingSampleRate = 0
        rollingChannels.removeAll(keepingCapacity: true)
        smoothedLeft64 = Self.zeroExtendedBands
        smoothedRight64 = Self.zeroExtendedBands
    }

    private static var zeroBands: [Float] {
        Array(repeating: 0, count: bandCount)
    }

    private static var zeroMediumBands: [Float] {
        Array(repeating: 0, count: mediumBandCount)
    }

    private static var zeroExtendedBands: [Float] {
        Array(repeating: 0, count: extendedBandCount)
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
