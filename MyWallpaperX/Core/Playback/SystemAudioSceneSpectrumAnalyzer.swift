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
        let rms: Float
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
    /// 使用大于 1 的对比响应压低底噪、保留真实峰值，避免把每个低能量 band
    /// 变成同样高度的“软绵绵”底。它是项目独立的显示策略，不是官方未公开常数。
    private static let visualCompressionExponent: Float = 1.60
    /// 采集以约 30 Hz 发布。攻击保持接近一个发布周期，释放约 80 ms，避免旧值
    /// 长时间拖尾成波浪；两者都只跟随真实输入，不生成无输入周期信号。
    private static let attackMix: Float = 0.82
    private static let releaseRetention: Float = 0.68
    /// 系统音频的音乐内容通常带有明显的 1/f 频谱倾斜；不补偿时，低频峰值会
    /// 把高频作者柱压到固定 -60 dB 门以下。这里使用有界的跨频率响应补偿，
    /// 让左右横轴在同一输入下有可见动态；它不改变 band identity，也不把某个
    /// 样本的频谱重排到另一组柱子。具体指数仍是项目策略，不复制第三方实现常数。
    private static let spectralTiltExponent: Float = 0.80
    private static let spectralTiltReferenceFrequency: Float = 250
    /// 低频 shelf 在 32 Hz 处只保留约 0.2 的线性幅度，向 250 Hz 平滑回到
    /// unity。它削弱系统 tap 中持续的次低音/设备底噪首档，但不会把真实 bass
    /// 变成静音；强 bass 仍由同一 band 的峰值通过后续 dB 响应显示。
    private static let spectralTiltMinimumGain: Float = 0.20
    private static let spectralTiltMaximumGain: Float = 4
    /// 项目频带轴的凹形 warp 保留既有低到高频分布；窄档通过连续插值端点
    /// 共享相邻 FFT 支撑，不再要求每档恰好包含一个离散 FFT 中心。
    private static let frequencyBandWarpExponent: Float = 0.78
    private static let settledSilenceThreshold: Float = 0.000_1

    private let log2FFTSize: vDSP_Length
    private let fftSetup: FFTSetup
    private var rollingChannels: [[Float]] = []
    private var rollingSampleRate: Float = 0
    private var cachedWindow: [Float] = []
    private var cachedAmplitudeScale: Float = 0
    private var smoothedLeft64 = Array(repeating: Float(0), count: extendedBandCount)
    private var smoothedRight64 = Array(repeating: Float(0), count: extendedBandCount)
    private var smoothedLeftEnergy: Float = 0
    private var smoothedRightEnergy: Float = 0
    private var leftOnsetPulse: Float = 0
    private var rightOnsetPulse: Float = 0

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
        let windowCount = Self.analysisWindowCount(sampleRate: sampleRate)
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
        smoothedLeft64 = visualLevels(
            rawLeft.extended,
            previous: smoothedLeft64,
            rms: rawLeft.rms,
            previousEnergy: &smoothedLeftEnergy,
            onsetPulse: &leftOnsetPulse
        )
        smoothedRight64 = visualLevels(
            rawRight.extended,
            previous: smoothedRight64,
            rms: rawRight.rms,
            previousEnergy: &smoothedRightEnergy,
            onsetPulse: &rightOnsetPulse
        )
        return Levels(
            left: Self.resample(smoothedLeft64, count: Self.bandCount),
            right: Self.resample(smoothedRight64, count: Self.bandCount),
            left32: Self.resample(smoothedLeft64, count: Self.mediumBandCount),
            right32: Self.resample(smoothedRight64, count: Self.mediumBandCount),
            left64: smoothedLeft64,
            right64: smoothedRight64
        )
    }

    static func analysisWindowCount(sampleRate: Float) -> Int {
        guard sampleRate.isFinite, sampleRate > 0 else { return 0 }
        let rateScale = max(1, sampleRate / Self.referenceSampleRate)
        return Int(min(Float(Self.fftSize), rateScale * Self.analysisWindowFrameCount))
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
            return FrequencyLevels(extended: Self.zeroExtendedBands, rms: 0)
        }
        let extended = frequencyBands(
            magnitudes,
            count: Self.extendedBandCount,
            upperFrequency: upperFrequency,
            binWidth: binWidth
        )
        let mean = samples.reduce(0, +) / Float(max(1, samples.count))
        let squaredMean = samples.reduce(0) { partial, sample in
            let centered = sample - mean
            return partial + centered * centered
        } / Float(max(1, samples.count))
        return FrequencyLevels(
            extended: extended,
            rms: squaredMean.isFinite ? sqrt(max(0, squaredMean)) : 0
        )
    }

    private func frequencyBands(
        _ magnitudes: [Float],
        count: Int,
        upperFrequency: Float,
        binWidth: Float
    ) -> [Float] {
        let ratio = upperFrequency / Self.minimumFrequency
        var levels = Array(repeating: Float(0), count: count)
        guard magnitudes.count > 1, count > 0 else { return levels }
        var weighted = magnitudes
        weighted[0] = 0 // Packed real FFT DC/Nyquist is not a positive-frequency bin.
        for bin in 1..<weighted.count {
            let frequency = Float(bin) * binWidth
            let tiltGain = min(
                Self.spectralTiltMaximumGain,
                max(Self.spectralTiltMinimumGain,
                    pow(frequency / Self.spectralTiltReferenceFrequency,
                        Self.spectralTiltExponent))
            )
            weighted[bin] = magnitudes[bin].isFinite
                ? max(0, magnitudes[bin]) * tiltGain : 0
        }
        // Peak response avoids diluting a narrow-band signal in wider treble
        // bands. Interpolated endpoints retain continuous support for bands
        // narrower than one FFT bin, without inventing a cross-band floor.
        let lastBin = Float(weighted.count - 1)
        func amplitude(at position: Float) -> Float {
            let bin = min(weighted.count - 2, Int(position))
            return weighted[bin] + (weighted[bin + 1] - weighted[bin])
                * (position - Float(bin))
        }
        for bandIndex in levels.indices {
            let lowerFrequency = Self.minimumFrequency * pow(
                ratio, pow(Float(bandIndex) / Float(count),
                           1 / Self.frequencyBandWarpExponent))
            let upperBandFrequency = Self.minimumFrequency * pow(
                ratio, pow(Float(bandIndex + 1) / Float(count),
                           1 / Self.frequencyBandWarpExponent))
            let bandLower = lowerFrequency / binWidth
            let bandUpper = upperBandFrequency / binWidth
            let lower = min(lastBin, max(1, bandLower))
            let upper = min(lastBin, max(1, bandUpper))
            var peak = max(amplitude(at: lower), amplitude(at: upper))
            let firstCenter = Int(lower.rounded(.up))
            let lastCenter = Int(upper.rounded(.down))
            if firstCenter <= lastCenter {
                for bin in firstCenter...lastCenter { peak = max(peak, weighted[bin]) }
            }
            levels[bandIndex] = peak

        }
        // Do not synthesize a cross-band floor from the loudest band. A narrow-band
        // source must leave unrelated bars quiet; otherwise the -60 dB response
        // turns the floor into a visible, wave-like copy of the peak.
        return levels.map { level in
            level.isFinite ? max(0, level) : 0
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

    private static let sharedEnergyMix: Float = 0.18
    private static let onsetPulseMix: Float = 0.10
    private static let onsetPulseRetention: Float = 0.55

    private func visualLevels(
        _ linearLevels: [Float],
        previous: [Float],
        rms: Float,
        previousEnergy: inout Float,
        onsetPulse: inout Float
    ) -> [Float] {
        guard !linearLevels.isEmpty,
              linearLevels.count == previous.count
        else {
            return Array(repeating: 0, count: previous.count)
        }
        let energyTarget = Self.visualResponse(for: rms)
        let energyBefore = previousEnergy
        let energyEnvelope: Float
        if energyTarget >= energyBefore {
            energyEnvelope = energyBefore * (1 - Self.attackMix)
                + energyTarget * Self.attackMix
        } else {
            energyEnvelope = max(
                energyTarget,
                energyBefore * Self.releaseRetention
            )
        }
        let onset = min(
            1,
            max(0, energyTarget - energyBefore)
                / max(0.08, energyBefore)
        )
        onsetPulse = max(onset, onsetPulse * Self.onsetPulseRetention)
        previousEnergy = energyEnvelope
        // Keep the frequency shape authoritative while letting a real frame-wide
        // energy rise move active bars together. This is a bounded gain, not a
        // synthesized cross-band floor: empty bands remain empty and silence stays
        // exactly zero.
        let sharedGain = min(
            1.12,
            1 - Self.sharedEnergyMix
                + Self.sharedEnergyMix * energyEnvelope
                + Self.onsetPulseMix * onsetPulse
        )
        return zip(linearLevels, previous).map { linear, prior in
            let target = Self.visualResponse(for: linear) * sharedGain
            let next: Float
            if target >= prior {
                next = prior * (1 - Self.attackMix) + target * Self.attackMix
            } else {
                next = max(target, prior * Self.releaseRetention)
            }
            guard next.isFinite, next >= Self.settledSilenceThreshold else { return 0 }
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
        smoothedLeftEnergy = 0
        smoothedRightEnergy = 0
        leftOnsetPulse = 0
        rightOnsetPulse = 0
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
