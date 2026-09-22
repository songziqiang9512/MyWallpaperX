//
//  SystemAudioSceneSpectrumAnalyzer.swift
//  MyWallpaperX
//

import Accelerate

/// Video/Web/Scene 共用的唯一 PCM -> 16/32/64×L/R 频谱 producer。
///
/// 公开作者合同只保证每个分辨率都从低频排到高频，数值为正且通常落在
/// 0...1；它没有公开频段边界、窗函数或平滑算法。因此这里用项目自有的
/// 32 Hz...16 kHz 对数频段、Hann 窗、幅度响应和快起慢落包络，不把未公开的
/// Windows 内部实现写成产品合同。
///
/// 64 档是唯一的 canonical producer 输出；16/32 档只从这组已包络的 canonical
/// bands 做确定性的连续块投影，不再各自维护一套时间 envelope。这样三种分辨率
/// 共用同一个 canonical 频带身份和时间状态，不会因消费端邻域/全局混合而改变形状。
/// macOS 系统 tap 的回调块长不稳定，所以 producer 先聚合约 43.5 ms 滚动窗，再做一次补零 FFT；
/// 采样率超出 FFT 容量时有界截断而不让整条音频链归零。
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

    /// 将 canonical 频段投影到消费端需要的柱数。投影只做连续区间的有界平均，
    /// 不重新采集、窗化或运行第二套 FFT；64 档 identity 保持每个真实 band，
    /// 下采样时平均每个目标区间内的 canonical bands，上采样时重复其有界区间值。
    static func resample(_ levels: [Float], count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard !levels.isEmpty else { return Array(repeating: 0, count: count) }
        if levels.count == count {
            return levels.map { $0.isFinite ? min(1, max(0, $0)) : 0 }
        }

        var projected = Array(repeating: Float(0), count: count)
        for index in projected.indices {
            let lower = (index * levels.count) / count
            let upper = max(lower + 1, ((index + 1) * levels.count) / count)
            let boundedLower = min(levels.count - 1, max(0, lower))
            let boundedUpper = min(levels.count, upper)
            guard boundedLower < boundedUpper else { continue }
            var total: Float = 0
            var finiteCount = 0
            for level in levels[boundedLower..<boundedUpper] where level.isFinite {
                total += min(1, max(0, level))
                finiteCount += 1
            }
            guard finiteCount > 0 else { continue }
            projected[index] = min(1, max(0, total / Float(finiteCount)))
        }
        return projected
    }

    private struct FrequencyLevels {
        let extended: [Float]
    }

    private static let fftSize = 4096
    private static let fftHalfSize = fftSize / 2
    private static let referenceSampleRate: Float = 44_100
    private static let analysisWindowFrameCount: Float = 64 * 30
    private static let minimumFrequency: Float = 32
    private static let maximumFrequency: Float = 16_000
    /// 沿用项目既有 Scene 响应下限：低于 -60 dBFS 的 tap 底噪稳定归零，以上保留
    /// 可见动态。它是 macOS producer 的平台适配，不冒充 Windows 私有增益常量。
    private static let minimumResponseDecibels: Float = -60
    /// 复用项目频带频谱已有的 0.74 根压缩，把正常音乐的中段动态抬到作者 shader
    /// 可见区间，同时保留上述 -60 dB 硬门和 0...1 上界。这里只改变幅度响应，
    /// 不改变低频到高频的索引顺序，也不使用参考项目的频带表或常数组合。
    private static let visualCompressionExponent: Float = 0.74
    /// 复用项目已有系统频谱的快起/慢落包络。采集以约 30 Hz 发布，因此这两个系数
    /// 分别让真实起音及时出现、尾音连续衰减；它们不生成任何无输入周期信号。
    private static let attackMix: Float = 0.66
    private static let releaseRetention: Float = 0.84
    /// 系统音频的音乐内容通常带有明显的 1/f 频谱倾斜；不补偿时，低频峰值会
    /// 把高频作者柱压到固定 -60 dB 门以下。该指数只做有界的跨频率响应补偿，
    /// 不改变 band identity，也不把某个样本的频谱重排到另一组柱子。
    private static let spectralTiltExponent: Float = 0.05
    private static let spectralTiltReferenceFrequency: Float = 250
    private static let spectralTiltMinimumGain: Float = 0.55
    private static let spectralTiltMaximumGain: Float = 4
    /// 低频主导的真实输入仍应让整条作者频谱有可见、可更新的活动底。底值由
    /// 同一帧的最高真实 band 推导，静音仍严格为零，不制造随机或周期信号。
    private static let broadbandActivityFloorRatio: Float = 0.01
    private static let broadbandActivityFloorMaximum: Float = 0.004
    private static let settledSilenceThreshold: Float = 0.000_1

    private let log2FFTSize: vDSP_Length
    private let fftSetup: FFTSetup
    private var rollingChannels: [[Float]] = []
    private var rollingSampleRate: Float = 0
    private var cachedWindow: [Float] = []
    private var cachedAmplitudeScale: Float = 0
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
    /// 该声道。空输入、非法采样率和未填满首个分析窗都稳定归零。
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
        let windowCount = analysisWindowCount(sampleRate: sampleRate)
        guard windowCount > 1 else {
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

        let rawLeft = frequencyLevels(
            for: rollingChannels[0],
            sampleRate: sampleRate
        )
        let rawRight: FrequencyLevels
        if rollingChannels.count > 1 {
            rawRight = frequencyLevels(
                for: rollingChannels[1],
                sampleRate: sampleRate
            )
        } else {
            rawRight = rawLeft
        }
        // Apply the fast-attack/slow-release envelope exactly once to the 64-band
        // canonical producer. Lower resolutions are projections of that same
        // identity-preserving result, so they cannot acquire a second temporal tail.
        smoothedLeft64 = Self.visualLevels(rawLeft.extended, previous: smoothedLeft64)
        smoothedRight64 = Self.visualLevels(rawRight.extended, previous: smoothedRight64)
        return Levels(
            left: Self.resample(smoothedLeft64, count: Self.bandCount),
            right: Self.resample(smoothedRight64, count: Self.bandCount),
            left32: Self.resample(smoothedLeft64, count: Self.mediumBandCount),
            right32: Self.resample(smoothedRight64, count: Self.mediumBandCount),
            left64: smoothedLeft64,
            right64: smoothedRight64
        )
    }

    private func analysisWindowCount(sampleRate: Float) -> Int {
        let rateScale = max(1, sampleRate / Self.referenceSampleRate)
        return min(Self.fftSize, Int(rateScale * Self.analysisWindowFrameCount))
    }

    private func prepareRollingState(channelCount: Int, sampleRate: Float) {
        let rateChanged = abs(rollingSampleRate - sampleRate) > 0.5
        guard rateChanged || rollingChannels.count != channelCount else { return }
        // 采样率会改变 FFT bin identity，声道数会改变 L/R identity；两者都必须
        // 与滚动窗一起撤销旧包络，不能把上一格式的 previous-current 泄漏给新格式。
        resetRollingState()
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

    private func frequencyLevels(
        for samples: [Float],
        sampleRate: Float
    ) -> FrequencyLevels {
        let magnitudes = magnitudeSpectrum(for: samples)
        let binWidth = sampleRate / Float(Self.fftSize)
        let upperFrequency = min(Self.maximumFrequency, sampleRate * 0.5)
        guard binWidth.isFinite, binWidth > 0,
              upperFrequency > Self.minimumFrequency
        else {
            return FrequencyLevels(
                extended: Self.zeroExtendedBands
            )
        }
        let extended = frequencyBands(
            magnitudes,
            count: Self.extendedBandCount,
            upperFrequency: upperFrequency,
            binWidth: binWidth
        )
        return FrequencyLevels(extended: extended)
    }

    private func frequencyBands(
        _ magnitudes: [Float],
        count: Int,
        upperFrequency: Float,
        binWidth: Float
    ) -> [Float] {
        let ratio = upperFrequency / Self.minimumFrequency
        var levels = Array(repeating: Float(0), count: count)
        for bandIndex in levels.indices {
            let lowerProgress = Float(bandIndex) / Float(count)
            let upperProgress = Float(bandIndex + 1) / Float(count)
            let lowerFrequency = Self.minimumFrequency * pow(ratio, lowerProgress)
            let upperBandFrequency = Self.minimumFrequency * pow(ratio, upperProgress)
            let lowerBin = max(1, Int(floor(lowerFrequency / binWidth)))
            let upperBin = min(
                magnitudes.count,
                max(lowerBin + 1, Int(ceil(upperBandFrequency / binWidth)))
            )
            guard lowerBin < upperBin else { continue }
            let centerFrequency = sqrt(lowerFrequency * upperBandFrequency)
            let tiltGain = min(
                Self.spectralTiltMaximumGain,
                max(
                    Self.spectralTiltMinimumGain,
                    pow(
                        centerFrequency / Self.spectralTiltReferenceFrequency,
                        Self.spectralTiltExponent
                    )
                )
            )
            for bin in lowerBin ..< upperBin where magnitudes[bin].isFinite {
                levels[bandIndex] = max(
                    levels[bandIndex],
                    magnitudes[bin] * tiltGain
                )
            }
        }
        guard let broadbandPeak = levels.max(),
              broadbandPeak.isFinite,
              broadbandPeak > 0
        else {
            return levels
        }
        let activityFloor = min(
            Self.broadbandActivityFloorMaximum,
            broadbandPeak * Self.broadbandActivityFloorRatio
        )
        return levels.map { level in
            guard level.isFinite else { return activityFloor }
            return max(level, activityFloor)
        }
    }

    private func magnitudeSpectrum(for samples: [Float]) -> [Float] {
        let window = analysisWindow(count: samples.count)
        let mean = samples.reduce(0, +) / Float(samples.count)
        var input = Array(repeating: Float(0), count: Self.fftSize)
        for index in samples.indices {
            input[index] = (samples[index] - mean) * window[index]
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
                * cachedAmplitudeScale
        }
        return magnitudes
    }

    private func analysisWindow(count: Int) -> [Float] {
        if cachedWindow.count == count { return cachedWindow }
        guard count > 1 else { return Array(repeating: 0, count: count) }
        let inverseSpan = 1 / Float(count - 1)
        cachedWindow = (0 ..< count).map { index in
            let phase = 2 * Float.pi * Float(index) * inverseSpan
            return 0.5 - 0.5 * cos(phase)
        }
        cachedAmplitudeScale = 2 / max(cachedWindow.reduce(0, +), 1)
        return cachedWindow
    }

    private static func visualLevels(
        _ linearLevels: [Float],
        previous: [Float]
    ) -> [Float] {
        guard !linearLevels.isEmpty,
              linearLevels.count == previous.count
        else {
            return Array(repeating: 0, count: previous.count)
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
