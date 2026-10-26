//
//  SystemAudioSceneSpectrumAnalyzer.swift
//  MyWallpaperX
//

import Accelerate
import Foundation

/// The only PCM producer for Video, Web and Scene. Frequency identities, the fixed
/// decibel response and final-height envelopes belong here; consumers only
/// average/project the resulting heights. Author shaders/scripts keep their own styling.
nonisolated final class SystemAudioSceneSpectrumAnalyzer {
    static let bandCount = SceneAudioSpectrumSnapshot.bandCount
    static let mediumBandCount = SceneAudioSpectrumSnapshot.mediumBandCount
    static let extendedBandCount = SceneAudioSpectrumSnapshot.extendedBandCount
    static let maximumFrameCount = 16_384

    struct Levels {
        let left64: [Float]
        let right64: [Float]
        var left: [Float] { SystemAudioSceneSpectrumAnalyzer.resample(left64, count: SystemAudioSceneSpectrumAnalyzer.bandCount) }
        var right: [Float] { SystemAudioSceneSpectrumAnalyzer.resample(right64, count: SystemAudioSceneSpectrumAnalyzer.bandCount) }
        var left32: [Float] { SystemAudioSceneSpectrumAnalyzer.resample(left64, count: SystemAudioSceneSpectrumAnalyzer.mediumBandCount) }
        var right32: [Float] { SystemAudioSceneSpectrumAnalyzer.resample(right64, count: SystemAudioSceneSpectrumAnalyzer.mediumBandCount) }
    }

    /// Fractional area mean: both coarse resolutions and Video retain the same
    /// display scale. Adding more source bands must not multiply a bar's height.
    /// Inputs are completed finite display heights from this analyzer.
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
    /// detail visible travel without a moving strongest-band denominator. The
    /// smoothstep shoulder avoids a hard bright ceiling in author visuals.
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

    init?() {
        guard let setup = vDSP_create_fftsetup(14, FFTRadix(kFFTRadix2)) else { return nil }
        fftSetup = setup
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    func reset() {
        analysisSampleRate = 0
        analysisChannelCount = 0
        leftEnvelope = Self.zeroBands
        rightEnvelope = Self.zeroBands
        lastTimestamp = nil
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
            reset()
            return Self.zeroLevels
        }
        // CaptureBuffer owns raw validation and the complete worker snapshot.
        // The serial service hands this analyzer the current whole window.
        let inputs = frame.signedChannels.prefix(2)
        let windowCount = Self.analysisWindowCount(sampleRate: sampleRate)
        if analysisSampleRate != sampleRate || analysisChannelCount != inputs.count {
            reset()
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
