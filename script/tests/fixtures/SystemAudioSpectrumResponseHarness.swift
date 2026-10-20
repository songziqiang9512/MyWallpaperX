import Foundation
import CoreAudio

struct SceneAudioSpectrumSnapshot {
    static let bandCount = 16
    static let mediumBandCount = 32
    static let extendedBandCount = 64
}
struct SystemAudioCapturedFrame { let signedChannels: [[Float]] }

@main
struct SpectrumResponseHarness {
    static let rate: Float = 48_000
    static func pcm(_ frequencies: [(Float, Float)], rate: Float = rate) -> [Float] {
        (0..<SystemAudioSceneSpectrumAnalyzer.analysisWindowCount(sampleRate: rate)).map { index in
            frequencies.reduce(Float(0)) { $0 + $1.1 * sin(2 * .pi * $1.0 * Float(index) / rate) }
        }
    }
    static func settled(_ frequencies: [(Float, Float)]) -> SystemAudioSceneSpectrumAnalyzer.Levels {
        let analyzer = SystemAudioSceneSpectrumAnalyzer()!
        let input = pcm(frequencies)
        var result = analyzer.analyze(signedChannels: [input], sampleRate: rate, timestamp: 0)
        for frame in 1...90 {
            result = analyzer.analyze(signedChannels: [input], sampleRate: rate, timestamp: Double(frame) / 30)
        }
        return result
    }
    static func peakIndex(_ a: [Float]) -> Int { a.indices.max { a[$0] < a[$1] }! }
    static func envelope(fps: Int) -> [Float] {
        let analyzer = SystemAudioSceneSpectrumAnalyzer()!
        let tone = pcm([(996.09375, 0.1)])
        let zero = tone.map { _ in Float(0) }
        _ = analyzer.analyze(signedChannels: [zero], sampleRate: rate, timestamp: 0)
        var attack: Float = 0
        var release: Float = 0
        for tick in 1...fps {
            let time = Double(tick) / Double(fps)
            let output = analyzer.analyze(signedChannels: [time <= 0.5 ? tone : zero], sampleRate: rate, timestamp: time)
            if tick == fps / 2 { attack = output.left64.max()! }
            release = output.left64.max()!
        }
        return [attack, release]
    }
    static func arrays(_ levels: SystemAudioSceneSpectrumAnalyzer.Levels) -> [[Float]] {
        [levels.left, levels.right, levels.left32, levels.right32, levels.left64, levels.right64]
    }
    static func scratchReuseChecks() -> [String: Bool] {
        let reused = SystemAudioSceneSpectrumAnalyzer()!
        var matchesFresh = true
        var rightStaysSilent = true
        var publishedStaysImmutable = true
        // 96k -> fractional 48k retains an 8192-point FFT while shrinking its
        // populated window. Other cases grow/shrink storage and switch channels.
        for targetRate: Float in [48_005.99, 44_100, 192_000, 1_000, 48_000] {
            reused.reset()
            _ = reused.analyze(signedChannels: [pcm([(3000, 0.7)], rate: 96_000)], sampleRate: 96_000)
            reused.reset()
            let left = pcm([(min(600, targetRate / 4), 0.1)], rate: targetRate)
            let zero = left.map { _ in Float(0) }
            let result = reused.analyze(signedChannels: [left, zero], sampleRate: targetRate, timestamp: 1)
            let fresh = SystemAudioSceneSpectrumAnalyzer()!.analyze(
                signedChannels: [left, zero], sampleRate: targetRate, timestamp: 1)
            matchesFresh = matchesFresh && arrays(result) == arrays(fresh)
            rightStaysSilent = rightStaysSilent && result.right64.allSatisfy { $0 == 0 }
            let published = arrays(result)
            _ = reused.analyze(signedChannels: [zero, left], sampleRate: targetRate, timestamp: 2)
            publishedStaysImmutable = publishedStaysImmutable && arrays(result) == published
            reused.reset()
            let restarted = reused.analyze(signedChannels: [zero], sampleRate: targetRate, timestamp: 0)
            let silentFresh = SystemAudioSceneSpectrumAnalyzer()!.analyze(
                signedChannels: [zero], sampleRate: targetRate, timestamp: 0)
            matchesFresh = matchesFresh && arrays(restarted) == arrays(silentFresh)
        }
        return ["matchesFresh": matchesFresh, "rightStaysSilent": rightStaysSilent,
                "publishedStaysImmutable": publishedStaysImmutable]
    }
    static func main() throws {
        if CommandLine.arguments.count == 2 {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let analyzer = SystemAudioSceneSpectrumAnalyzer()!
            var rows: [[String: Any]] = []
            let count = (data.count - 44) / 4
            for start in stride(from: 0, to: count, by: 1600) {
                let channels = (0..<2).map { channel in
                    (start..<min(start + 1600, count)).map { sample in
                        data.withUnsafeBytes {
                            Float(Int16(littleEndian: $0.loadUnaligned(fromByteOffset: 44 + sample * 4 + channel * 2, as: Int16.self))) / 32768
                        }
                    }
                }
                let time = Double(start + channels[0].count) / 48000
                let levels = analyzer.analyze(signedChannels: channels, sampleRate: rate, timestamp: time)
                rows.append(["time": time, "left": levels.left64, "right": levels.right64])
            }
            print(String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self))
            return
        }
        let tone = pcm([(1000,0.1)])
        let silence = tone.map { _ in Float(0) }
        let clock = SystemAudioSceneSpectrumAnalyzer()!
        let before = clock.analyze(signedChannels: [tone], sampleRate: rate, timestamp: 1)
        let stale = clock.analyze(signedChannels: [silence], sampleRate: rate, timestamp: 0.9)
        let reference = SystemAudioSceneSpectrumAnalyzer()!
        _ = reference.analyze(signedChannels: [tone], sampleRate: rate, timestamp: 1)
        _ = clock.analyze(signedChannels: [Array(silence.prefix(1024))], sampleRate: rate, timestamp: 0.95)
        let staleFormat = clock.analyze(signedChannels: [pcm([(440,0.1)], rate: 44100)], sampleRate: 44100, timestamp: 0.97)
        let nextClock = clock.analyze(signedChannels: [Array(tone.prefix(1024))], sampleRate: rate, timestamp: 1.04)
        let nextReference = reference.analyze(signedChannels: [Array(tone.prefix(1024))], sampleRate: rate, timestamp: 1.04)
        let aRate: Float = 48_005.5
        let bRate: Float = 48_005.99
        let changed = SystemAudioSceneSpectrumAnalyzer()!
        _ = changed.analyze(signedChannels: [pcm([(440,0.1)], rate: aRate)], sampleRate: aRate)
        let after = changed.analyze(signedChannels: [pcm([(440,0.1)], rate: bRate)], sampleRate: bRate)
        let fresh = SystemAudioSceneSpectrumAnalyzer()!.analyze(signedChannels: [pcm([(440,0.1)], rate: bRate)], sampleRate: bRate)
        var finiteRates = true
        for rate: Float in [1, 63, 100, 1000, 8000, 44100, 48000, 96000, 192000, Float.greatestFiniteMagnitude] {
            let result = SystemAudioSceneSpectrumAnalyzer()!.analyze(signedChannels: [pcm([(min(440,rate/4),0.1)], rate: rate)], sampleRate: rate)
            finiteRates = finiteRates && result.left64.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 0.96 }
        }
        var releaseFractions: [Float] = []
        for amplitude: Float in [0.01,0.1] {
            let decay = SystemAudioSceneSpectrumAnalyzer()!
            let input = pcm([(996.09375,amplitude)])
            var start: Float = 0
            for i in 0...60 { start = decay.analyze(signedChannels:[input],sampleRate:rate,timestamp:Double(i)/30).left64.max()! }
            for tick in 1...12 {
                let current = decay.analyze(signedChannels:[silence],sampleRate:rate,timestamp:2+Double(tick)/30).left64.max()!
                if tick == 6 || tick == 12 { releaseFractions.append(current/start) }
            }
        }
        let probe = settled([(2400,0.04)])
        let probeIndex = peakIndex(probe.left64)
        let quietBass = settled([(120,0.015),(2400,0.04)])
        let loudBass = settled([(120,0.15),(2400,0.04)])
        let quietTreble = settled([(2400,0.04),(10000,0.01)])
        let loudTreble = settled([(2400,0.04),(10000,0.3)])
        let reset = SystemAudioSceneSpectrumAnalyzer()!
        _ = reset.analyze(signedChannels:[tone],sampleRate:rate,timestamp:0)
        var tail = before
        for i in 1...90 { tail = reset.analyze(signedChannels:[silence],sampleRate:rate,timestamp:Double(i)/30) }
        let constant = Array(repeating: Float(0.37), count: tone.count)
        let dc = settled([])
        let dcResult = SystemAudioSceneSpectrumAnalyzer()!.analyze(signedChannels:[constant],sampleRate:rate)
        let projection = SystemAudioSceneSpectrumAnalyzer.resample(Array(repeating:0.6,count:64),count:28)
        let asymmetric = (0..<64).map { Float($0) / 64 }
        let projected = SystemAudioSceneSpectrumAnalyzer.resample(asymmetric,count:28)
        let frames = [44100.0,48000,96000,192000].map {
            SystemAudioCaptureDeviceFactory.captureBufferFrameCount(sampleRate:$0,range:AudioValueRange(mMinimum:32,mMaximum:4096))!
        } + [
            SystemAudioCaptureDeviceFactory.captureBufferFrameCount(sampleRate:48000,range:AudioValueRange(mMinimum:1024,mMaximum:4096))!,
            SystemAudioCaptureDeviceFactory.captureBufferFrameCount(sampleRate:48000,range:AudioValueRange(mMinimum:32,mMaximum:256))!
        ]
        let report: [String: Any] = [
            "toneHeight":settled([(996.09375,0.2)]).left64.max()!,
            "volumeSteps":[Float(0.002),0.02,0.2,0.8].map { settled([(996.09375,$0)]).left64.max()! },
            "independentBassDelta":abs(loudBass.left64[probeIndex]-quietBass.left64[probeIndex]),
            "independentTrebleDelta":abs(loudTreble.left64[probeIndex]-quietTreble.left64[probeIndex]),
            "lowResponseDelta":zip(loudBass.left64,quietBass.left64).map { $0-$1 }.max()!,
            "displayRange":SystemAudioSceneSpectrumAnalyzer.displayLevels([0,1e-5,1e-4,1e-3,0.01,0.1,1,Float.greatestFiniteMagnitude,.nan,.infinity,-1]),
            "releaseFractions":releaseFractions,
            "envelope30":envelope(fps:30),"envelope60":envelope(fps:60),
            "projectionConstant":projection,
            "projectionMeanError":abs(projected.reduce(0,+)/28-asymmetric.reduce(0,+)/64),
            "coarseMatchesCanonical":SystemAudioSceneSpectrumAnalyzer.resample(before.left64,count:16)==before.left,
            "silenceClears":tail.left64.allSatisfy { $0 == 0 } && dc.left64.allSatisfy { $0 == 0 } && dcResult.left64.allSatisfy { $0 == 0 },
            "staleUnchanged":before.left64==stale.left64 && before.left64==staleFormat.left64,
            "staleHistoryUnchanged":nextClock.left64==nextReference.left64,
            "fractionalRateResetMatchesFresh":after.left64==fresh.left64,
            "fractionalWindowCounts":[SystemAudioSceneSpectrumAnalyzer.analysisWindowCount(sampleRate:aRate),SystemAudioSceneSpectrumAnalyzer.analysisWindowCount(sampleRate:bRate)],
            "finiteRates":finiteRates,"captureFrames":frames,
            "scratchReuse":scratchReuseChecks(),
            "observedPeakIndices":[Float(80),250,500,1000,4000,10000].map { peakIndex(settled([($0,0.02)]).left64) }
        ]
        print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self))
    }
}
