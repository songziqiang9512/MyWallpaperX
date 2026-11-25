//
//  SystemAudioSceneSpectrumAnalyzer.swift
//  MyWallpaperX
//

import Accelerate
import Foundation

/// Serial analysis of shared capture snapshots. Video and Web consume display
/// heights; Scene consumes author bands before shader or script styling.
nonisolated final class SystemAudioSceneSpectrumAnalyzer {
    static let bandCount = SceneAudioSpectrumSnapshot.bandCount
    static let mediumBandCount = SceneAudioSpectrumSnapshot.mediumBandCount
    static let extendedBandCount = SceneAudioSpectrumSnapshot.extendedBandCount
    static let maximumFrameCount = 16_384

    struct Levels {
        let left64: [Float]
        let right64: [Float]
    }

    struct AuthorLevels {
        let left64: [Float]
        let right64: [Float]
        let left32: [Float]
        let right32: [Float]
        let left: [Float]
        let right: [Float]

        init(left64: [Float], right64: [Float]? = nil) {
            self.left64 = left64
            self.right64 = right64 ?? left64
            left32 = Self.pairPeaks(left64)
            right32 = right64.map(Self.pairPeaks) ?? left32
            left = Self.pairPeaks(left32)
            right = right64 == nil ? left : Self.pairPeaks(right32)
        }

        static let silence = AuthorLevels(left64: zeroBands)

        private static func pairPeaks(_ bands: [Float]) -> [Float] {
            stride(from: 0, to: bands.count, by: 2).map { max(bands[$0], bands[$0 + 1]) }
        }
    }

    /// Fractional area mean for projecting finished display heights to Video bars.
    static func resample(_ levels: [Float], count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard !levels.isEmpty else { return Array(repeating: 0, count: count) }
        if count == levels.count { return levels }
        if count > levels.count {
            return (0..<count).map { levels[min(levels.count - 1, $0 * levels.count / count)] }
        }
        let width = Double(levels.count) / Double(count)
        return (0..<count).map { index in
            let lower = Double(index) * width
            let upper = Double(index + 1) * width
            var total: Double = 0
            for source in Int(lower)..<min(levels.count, Int(upper.rounded(.up))) {
                let overlap = max(0, min(upper, Double(source + 1)) - max(lower, Double(source)))
                total += Double(levels[source]) * overlap
            }
            return Float(total / width)
        }
    }

    /// Fixed acoustic dynamic range. Standard dB compression gives weak musical
    /// detail visible travel without a moving strongest-band denominator.
    static func displayLevels(_ amplitudes: [Float]) -> [Float] {
        amplitudes.map { amplitude in
            guard amplitude > 0 else { return 0 }
            let decibels = 20 * log10(Double(amplitude))
            let unit = min(1, max(0, (decibels + 100) / 90))
            return Float(0.96 * unit * unit * (3 - 2 * unit))
        }
    }

    private static let minimumFrequency: Float = 32
    private static let maximumFrequency: Float = 16_000
    private static let attackSeconds: Float = 0.030
    private static let releaseSeconds: Float = 0.140
    private let fftSetup: FFTSetup
    private var analysisSampleRate: Float = 0
    private var analysisChannelCount = 0
    private var window: [Float] = []
    private var fftSize = 0
    // The capture worker serializes this analyzer. Scratch never escapes into
    // published Levels, and each transform overwrites both split-complex arrays.
    private var fftInput: [Float] = []
    private var fftReal: [Float] = []
    private var fftImaginary: [Float] = []
    private var amplitudeScale: Float = 0
    private var bandWeights: [[(bin: Int, coverage: Float)]] = []
    private var bandGains: [Float] = []
    private var leftEnvelope = Array(repeating: Float(0), count: extendedBandCount)
    private var rightEnvelope = Array(repeating: Float(0), count: extendedBandCount)
    private var lastTimestamp: TimeInterval?
    private var author = AuthorAnalysis()

    init?() {
        guard let setup = vDSP_create_fftsetup(14, FFTRadix(kFFTRadix2)) else { return nil }
        fftSetup = setup
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    func reset() {
        resetDisplay()
        resetAuthor()
    }

    func resetDisplay() {
        analysisSampleRate = 0
        analysisChannelCount = 0
        leftEnvelope = Self.zeroBands
        rightEnvelope = Self.zeroBands
        lastTimestamp = nil
    }

    func resetAuthor() {
        author.reset()
    }

    func analyzeAuthor(
        _ frame: SystemAudioCapturedFrame,
        sampleRate: Float,
        timestamp: TimeInterval? = nil
    ) -> AuthorLevels {
        author.analyze(frame, sampleRate: sampleRate, timestamp: timestamp, fftSetup: fftSetup)
    }

    func analyze(
        _ frame: SystemAudioCapturedFrame,
        sampleRate: Float,
        timestamp: TimeInterval? = nil
    ) -> Levels {
        // Reject late captures before a different format can reset the clock,
        // FFT preparation or height envelopes of the current stream.
        if let timestamp, timestamp.isFinite, let lastTimestamp, timestamp <= lastTimestamp {
            return levelsFromEnvelopes()
        }
        guard sampleRate.isFinite, sampleRate > 0,
              let first = frame.signedChannels.first, !first.isEmpty else {
            resetDisplay()
            return Self.zeroLevels
        }
        // CaptureBuffer owns raw validation and the complete worker snapshot.
        // The serial service hands this analyzer the current whole window.
        let inputs = frame.signedChannels.prefix(2)
        let windowCount = Self.analysisWindowCount(sampleRate: sampleRate)
        if analysisSampleRate != sampleRate || analysisChannelCount != inputs.count {
            resetDisplay()
            analysisSampleRate = sampleRate
            analysisChannelCount = inputs.count
            prepareAnalysis(windowCount: windowCount, sampleRate: sampleRate)
        }
        guard bandWeights.count == Self.extendedBandCount else { return Self.zeroLevels }
        // Capture time, rather than worker scheduling, owns envelope advancement.
        // Callers without a clock are deterministic offline 30 Hz analyses.
        let elapsed: Float
        if let timestamp, timestamp.isFinite {
            elapsed = Float(min(1, max(0, timestamp - (lastTimestamp ?? (timestamp - 1 / 30)))))
            lastTimestamp = timestamp
        } else {
            elapsed = 1 / 30
        }
        let left = Self.displayLevels(frequencyAmplitudes(inputs[0]))
        updateEnvelope(&leftEnvelope, heights: left, elapsed: elapsed)
        if inputs.count == 1 {
            rightEnvelope = leftEnvelope
        } else {
            let right = Self.displayLevels(frequencyAmplitudes(inputs[1]))
            updateEnvelope(&rightEnvelope, heights: right, elapsed: elapsed)
        }
        return levelsFromEnvelopes()
    }

    static func analysisWindowCount(sampleRate: Float) -> Int {
        guard sampleRate.isFinite, sampleRate > 0 else { return 0 }
        return Int(min(Float(maximumFrameCount), max(2, (sampleRate * (4096 / 48_000)).rounded())))
    }

    private func prepareAnalysis(windowCount: Int, sampleRate: Float) {
        fftSize = 2
        while fftSize < windowCount { fftSize *= 2 }
        if fftInput.count != fftSize {
            fftInput = Array(repeating: 0, count: fftSize)
            fftReal = Array(repeating: 0, count: fftSize / 2)
            fftImaginary = Array(repeating: 0, count: fftSize / 2)
        }
        window = (0..<windowCount).map { index in
            let phase = 2 * Double.pi * Double(index) / Double(windowCount - 1)
            return Float(0.5 - 0.5 * cos(phase))
        }
        // vDSP real forward FFT is 2*DFT. Dividing magnitudes by the
        // unpadded sample count gives the conventional 2/N spectrum, retaining
        // the Hann attenuation consistently at every capture sample rate.
        amplitudeScale = 1 / Float(windowCount)
        let binWidth = sampleRate / Float(fftSize)
        let upper = min(Self.maximumFrequency / binWidth, Float(fftSize / 2 - 1))
        let lower = max(1, Self.minimumFrequency / binWidth)
        bandWeights = []
        bandGains = []
        guard upper > lower else { return }
        func perceptual(_ hz: Float) -> Float { log(1 + hz / Self.minimumFrequency) }
        let start = perceptual(lower * binWidth)
        let span = perceptual(upper * binWidth) - start
        // Limit dense low-frequency FFT-grid coverage. This does not create
        // resolution beyond the finite window or guarantee disjoint main lobes.
        // Very low sample rates remain bounded.
        let minimumWidth = min(2, (upper - lower) / Float(Self.extendedBandCount))
        var edge = lower
        for band in 0..<Self.extendedBandCount {
            let desired = Self.minimumFrequency * (exp(start + span * Float(band + 1) / Float(Self.extendedBandCount)) - 1) / binWidth
            let remaining = Float(Self.extendedBandCount - band - 1)
            let next = min(upper - remaining * minimumWidth, max(edge + minimumWidth, desired))
            var weights: [(Int, Float)] = []
            let firstBin = max(1, Int((edge - 0.5).rounded(.up)))
            let lastBin = min(fftSize / 2 - 1, Int((next + 0.5).rounded(.down)))
            if firstBin <= lastBin {
                for bin in firstBin...lastBin {
                    let coverage = max(0, min(next, Float(bin) + 0.5) - max(edge, Float(bin) - 0.5))
                    if coverage > 0 { weights.append((bin, coverage)) }
                }
            }
            bandWeights.append(weights)
            let center = sqrt(edge * next) * binWidth
            // A fixed 6 dB/octave tilt balances common music spectral rolloff.
            // It never follows a band's current peak or amplifies silence.
            bandGains.append(min(16, max(0.06, center / 1000)))
            edge = next
        }
    }

    private func frequencyAmplitudes(_ samples: [Float]) -> [Float] {
        // Accumulate DC in Double: a repeated finite Float must subtract to
        // exact zero, rather than leak a Float summation residual into low bars.
        let mean = Float(samples.reduce(0.0) { $0 + Double($1) } / Double(samples.count))
        let count = fftSize
        fftInput.withUnsafeMutableBufferPointer { source in
            for index in samples.indices { source[index] = (samples[index] - mean) * window[index] }
            // A new rate can shrink the unpadded window without changing count.
            // Clear padding on every channel so old samples cannot enter its FFT.
            for index in samples.count..<count { source[index] = 0 }
            fftReal.withUnsafeMutableBufferPointer { r in
                fftImaginary.withUnsafeMutableBufferPointer { i in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                    source.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: count / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(count / 2))
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(log2(Float(count))), FFTDirection(FFT_FORWARD))
                }
            }
        }
        return bandWeights.enumerated().map { band, weights -> Float in
            var magnitude: Double = 0
            var width: Double = 0
            for (bin, coverage) in weights {
                magnitude += hypot(Double(fftReal[bin]), Double(fftImaginary[bin])) * Double(coverage)
                width += Double(coverage)
            }
            let amplitude = magnitude * Double(amplitudeScale) * Double(bandGains[band]) / max(1, width)
            return amplitude.isFinite ? Float(min(Double(Float.greatestFiniteMagnitude), amplitude)) : 0
        }
    }

    private func updateEnvelope(_ state: inout [Float], heights: [Float], elapsed: Float) {
        for index in state.indices {
            let target = heights[index]
            let time = target > state[index] ? Self.attackSeconds : Self.releaseSeconds
            state[index] += (target - state[index]) * (1 - exp(-elapsed / time))
            if state[index] < 1e-7 { state[index] = 0 }
        }
    }

    private func levelsFromEnvelopes() -> Levels {
        Levels(left64: leftEnvelope, right64: rightEnvelope)
    }

    private static var zeroBands: [Float] { Array(repeating: 0, count: extendedBandCount) }
    private static var zeroLevels: Levels {
        Levels(left64: zeroBands, right64: zeroBands)
    }
}

private extension SystemAudioSceneSpectrumAnalyzer {
    struct AuthorAnalysis {
        private static let onsetPeak: Float = 0.3432
        private static let quietPeak: Float = 0.00002
        private static let minimumDenominator: Float = 0.000113
        private static let reentryDelay = 0.5
        private static let groupCount = extendedBandCount / 8

        private var window: AuthorWindow?
        private var channelCount = 0
        private var lastTimestamp: TimeInterval?
        private var quietDuration: TimeInterval = 0
        private var sharedPeak = onsetPeak
        private var denominators = Array(repeating: Float(0), count: 2 * groupCount)
        private var lastLevels = AuthorLevels.silence

        mutating func reset() {
            lastTimestamp = nil
            quietDuration = 0
            seedOnset()
            lastLevels = .silence
        }

        mutating func analyze(
            _ frame: SystemAudioCapturedFrame,
            sampleRate: Float,
            timestamp: TimeInterval?,
            fftSetup: FFTSetup
        ) -> AuthorLevels {
            let time = timestamp.flatMap { $0.isFinite ? $0 : nil }
            if let time, let lastTimestamp, time <= lastTimestamp {
                return lastLevels
            }
            guard let first = frame.signedChannels.first, sampleRate.isFinite, sampleRate > 0 else {
                reset()
                return .silence
            }
            let formatChanged = window?.sampleRate != sampleRate
            if formatChanged {
                window = AuthorWindow(sampleRate: sampleRate, fftSetup: fftSetup)
            }
            let channels = min(2, frame.signedChannels.count)
            if formatChanged || channels != channelCount {
                channelCount = channels
                reset()
            }
            guard let window, first.count >= window.sampleCount else { return .silence }

            let elapsed = time.flatMap { time in lastTimestamp.map { min(1, time - $0) } } ?? 1 / 30
            lastTimestamp = time
            var left = window.bands(first, fftSetup: fftSetup)
            var right = channels == 2 ? window.bands(frame.signedChannels[1], fftSetup: fftSetup) : nil
            let peak = max(left.max() ?? 0, right?.max() ?? 0)
            guard peak.isFinite else {
                lastLevels = .silence
                return lastLevels
            }
            let dt = Float(elapsed)
            let localFall = 0.05634 * dt
            if peak < Self.quietPeak {
                if quietDuration < Self.reentryDelay {
                    quietDuration += elapsed
                    if quietDuration >= Self.reentryDelay {
                        seedOnset()
                    } else {
                        sharedPeak = max(0, sharedPeak - 0.17 * dt)
                        for index in denominators.indices {
                            denominators[index] = max(0, denominators[index] - localFall)
                        }
                    }
                }
                lastLevels = .silence
                return lastLevels
            }

            quietDuration = 0
            sharedPeak += min(0.36 * dt, max(-0.17 * dt, peak - sharedPeak))
            let floor = max(sharedPeak / 3, Self.minimumDenominator)
            normalize(&left, channelOffset: 0, floor: floor, rise: 0.12 * dt, fall: localFall)
            if right != nil {
                normalize(&right!, channelOffset: Self.groupCount, floor: floor, rise: 0.12 * dt, fall: localFall)
            }
            lastLevels = AuthorLevels(left64: left, right64: right)
            return lastLevels
        }

        private mutating func seedOnset() {
            sharedPeak = Self.onsetPeak
            for index in denominators.indices { denominators[index] = 0 }
        }

        private mutating func normalize(
            _ bands: inout [Float],
            channelOffset: Int,
            floor: Float,
            rise: Float,
            fall: Float
        ) {
            for group in 0..<Self.groupCount {
                let samples = (group * 8)..<((group + 1) * 8)
                let peak = bands[samples].max()!
                let index = channelOffset + group
                let previous = denominators[index]
                let next = max(floor, previous + min(rise, max(-fall, peak - previous)))
                denominators[index] = next
                for band in samples { bands[band] /= next }
            }
        }
    }

    final class AuthorWindow {
        let sampleRate: Float
        let sampleCount: Int
        private let fftExponent: vDSP_Length
        private let chirpReal: [Float]
        private let chirpImaginary: [Float]
        private let kernelReal: [Float]
        private let kernelImaginary: [Float]
        private let binGains: [Float]
        private let bandEnds: [Int]
        private var real: [Float]
        private var imaginary: [Float]

        init?(sampleRate: Float, fftSetup: FFTSetup) {
            let highestBin = 639
            let gridPeriod = Double(sampleRate) * (2089 / 48_000.0)
            let binCount = Int(min(Double(highestBin), gridPeriod / 2))
            guard binCount > 0 else { return nil }
            self.sampleRate = sampleRate
            sampleCount = Int(min(Float(maximumFrameCount - highestBin), max(2, (sampleRate * 0.029).rounded())))
            // Only lags from -(sampleCount - 1) through binCount affect the output.
            let exponent = Int.bitWidth - (sampleCount + binCount - 1).leadingZeroBitCount
            fftExponent = vDSP_Length(exponent)
            let fftCount = 1 << exponent
            func angle(_ index: Int) -> Double { .pi * Double(index * index) / gridPeriod }
            let phases = (0..<sampleCount).map(angle)
            chirpReal = phases.map { Float(cos($0)) }
            chirpImaginary = phases.map { -Float(sin($0)) }

            var kernelReal = Array(repeating: Float(0), count: fftCount)
            var kernelImaginary = kernelReal
            for lag in (1 - sampleCount)...binCount {
                let index = lag < 0 ? fftCount + lag : lag
                let phase = angle(lag)
                kernelReal[index] = Float(cos(phase))
                kernelImaginary[index] = Float(sin(phase))
            }
            kernelReal.withUnsafeMutableBufferPointer { real in
                kernelImaginary.withUnsafeMutableBufferPointer { imaginary in
                    var kernel = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginary.baseAddress!)
                    vDSP_fft_zip(fftSetup, &kernel, 1, vDSP_Length(exponent), FFTDirection(FFT_FORWARD))
                }
            }
            self.kernelReal = kernelReal
            self.kernelImaginary = kernelImaginary

            func weight(_ bin: Int) -> Double {
                let curve = sin(.pi * Double(bin - 1) / 1278)
                return sqrt(1 + 500 * curve * curve)
            }
            let scale = 2 / (Double(sampleCount) * Double(fftCount) * weight(65))
            binGains = [0] + (1...binCount).map { Float(weight($0) * scale) }
            bandEnds = (1...extendedBandCount).map { band in
                let fraction = Double(band) / Double(extendedBandCount)
                let edge = Int((Double(highestBin) * pow(fraction, 4)).rounded(.up))
                return min(binCount, max(band, edge))
            }
            real = Array(repeating: 0, count: fftCount)
            imaginary = real
        }

        func bands(_ samples: [Float], fftSetup: FFTSetup) -> [Float] {
            real.withUnsafeMutableBufferPointer { real in
                imaginary.withUnsafeMutableBufferPointer { imaginary in
                    let offset = samples.count - sampleCount
                    for index in 0..<sampleCount {
                        let value = samples[offset + index]
                        real[index] = value * chirpReal[index]
                        imaginary[index] = value * chirpImaginary[index]
                    }
                    let padding = vDSP_Length(real.count - sampleCount)
                    vDSP_vclr(real.baseAddress! + sampleCount, 1, padding)
                    vDSP_vclr(imaginary.baseAddress! + sampleCount, 1, padding)
                    var signal = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginary.baseAddress!)
                    vDSP_fft_zip(fftSetup, &signal, 1, fftExponent, FFTDirection(FFT_FORWARD))
                    for index in real.indices {
                        let r = real[index]
                        let i = imaginary[index]
                        real[index] = r * kernelReal[index] - i * kernelImaginary[index]
                        imaginary[index] = r * kernelImaginary[index] + i * kernelReal[index]
                    }
                    vDSP_fft_zip(fftSetup, &signal, 1, fftExponent, FFTDirection(FFT_INVERSE))
                }
            }
            var lower = 1
            return bandEnds.map { upper in
                var peak: Float = 0
                while lower <= upper {
                    // The final output chirp is unit magnitude; only its norm is consumed.
                    let r = real[lower]
                    let i = imaginary[lower]
                    peak = max(peak, (r * r + i * i).squareRoot() * binGains[lower])
                    lower += 1
                }
                return peak
            }
        }
    }
}
