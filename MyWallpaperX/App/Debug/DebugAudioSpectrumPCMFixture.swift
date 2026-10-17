#if DEBUG
import Foundation
import AudioToolbox

/// Deterministic input shared by visual evidence runners. No FFT, band values,
/// real-device capture or product output authority is introduced here.
nonisolated enum DebugAudioSpectrumPCMFixture {
    static let sampleRate: Float = 48_000
    static let publicationRate: Float = 30
    static let samplesPerFrame = 1_600

    /// Optional isolated visual-test recording. A rejected explicit recording
    /// produces silence rather than silently substituting synthetic tones.
    private static let recordedPCM: [[Float]]? = {
        guard let path = ProcessInfo.processInfo.environment["MWX_DEBUG_AUDIO_PCM_FILE"] else { return nil }
        let empty: [[Float]] = [[], []]
        guard let size = try? FileManager.default.attributesOfItem(atPath:path)[.size] as? NSNumber,
              size.intValue <= 16 * 1024 * 1024,
              let data = try? Data(contentsOf:URL(fileURLWithPath:path)), data.count >= 44 else {
            NSLog("MWX DEBUG AUDIO: rejected recording"); return empty
        }
        func u16(_ offset: Int) -> UInt16 { data.withUnsafeBytes { UInt16(littleEndian:$0.loadUnaligned(fromByteOffset:offset,as:UInt16.self)) } }
        func u32(_ offset: Int) -> UInt32 { data.withUnsafeBytes { UInt32(littleEndian:$0.loadUnaligned(fromByteOffset:offset,as:UInt32.self)) } }
        guard String(decoding:data[0..<4],as:UTF8.self) == "RIFF",
              String(decoding:data[8..<16],as:UTF8.self) == "WAVEfmt ",
              u32(16) == 16, u16(20) == 1, u16(22) == 2,
              u32(24) == 48000, u16(32) == 4, u16(34) == 16,
              String(decoding:data[36..<40],as:UTF8.self) == "data",
              Int(u32(40)) == data.count - 44, (data.count - 44).isMultiple(of:4) else {
            NSLog("MWX DEBUG AUDIO: rejected recording format"); return empty
        }
        let count = (data.count - 44) / 4
        let channels = (0..<2).map { channel in
            (0..<count).map { sample -> Float in
                Float(Int16(bitPattern:u16(44 + sample * 4 + channel * 2))) / 32768
            }
        }
        NSLog("MWX DEBUG AUDIO: source=recordedPCM frames=%d sampleRate=48000 channels=2",count)
        return channels
    }()

    static func feed(_ service: SystemAudioSpectrumService, frame: Int,
                     toneFrequency: Float? = nil, silence: Bool = false) {
        let left = samples(frame: frame, channelPhase: 0, toneFrequency: toneFrequency, silence: silence)
        let right = samples(frame: frame, channelPhase: 0.19, toneFrequency: toneFrequency, silence: silence)
        let format = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        let buffers = AudioBufferList.allocate(maximumBuffers: 2)
        defer { buffers.unsafeMutablePointer.deallocate() }
        buffers.count = 2
        left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                for offset in stride(from: 0, to: samplesPerFrame, by: 128) {
                    let count = min(128, samplesPerFrame - offset)
                    buffers[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(count * 4),
                        mData: UnsafeMutableRawPointer(mutating: l.baseAddress! + offset))
                    buffers[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(count * 4),
                        mData: UnsafeMutableRawPointer(mutating: r.baseAddress! + offset))
                    service.debugProcessPCMForTesting(buffers.unsafePointer, format: format,
                        now: 1 + Double(frame * samplesPerFrame + offset + count) / Double(sampleRate))
                }
            }
        }
    }

    static func samples(
        frame: Int,
        channelPhase: Float,
        toneFrequency: Float? = nil,
        silence: Bool = false
    ) -> [Float] {
        if silence { return Array(repeating: 0, count: samplesPerFrame) }
        let startSample = frame * samplesPerFrame
        if toneFrequency == nil, let recordedPCM {
            let channel = recordedPCM[channelPhase == 0 ? 0 : 1]
            return (0..<samplesPerFrame).map { index in
                let sample = startSample + index
                return sample < channel.count ? channel[sample] : 0
            }
        }
        if let toneFrequency {
            // The diagnostic tone still enters the shared PCM/FFT path. It
            // never constructs bins or changes the author's frequency range.
            return (0 ..< samplesPerFrame).map { localSample in
                let time = Double(startSample + localSample) / Double(sampleRate)
                return Float(0.5 * sin(2 * .pi * (Double(toneFrequency) * time
                    + Double(channelPhase))))
            }
        }
        let elapsed = Float(frame) / publicationRate
        let overallEnvelope = 0.68
            + 0.12 * sin((elapsed * 0.27 + channelPhase * 0.07) * 2 * .pi)
            + 0.06 * sin((elapsed * 0.61 + channelPhase * 0.13) * 2 * .pi)
        let toneCount = 24
        return (0 ..< samplesPerFrame).map { localSample in
            let sample = startSample + localSample
            let time = Float(sample) / sampleRate
            var mixed: Float = 0
            for index in 0 ..< toneCount {
                let position = (Float(index) + 0.5) / Float(toneCount)
                // 对数分布让固定输入覆盖整个低频到高频横轴；这里只
                // 生成测试 PCM，不参与产品频带映射。
                let frequency = 55 * pow(14_500 / 55, position)
                let firstCenter = 0.23
                    + 0.14 * sin((elapsed * 0.19 + channelPhase * 0.09) * 2 * .pi)
                let secondCenter = 0.71
                    + 0.18 * sin((elapsed * 0.13 + 0.31
                        - channelPhase * 0.06) * 2 * .pi)
                let firstDistance = (position - firstCenter) / 0.14
                let secondDistance = (position - secondCenter) / 0.18
                let firstCluster = exp(-firstDistance * firstDistance)
                let secondCluster = exp(-secondDistance * secondDistance)
                let firstPulse = 0.5 + 0.5 * sin(
                    (elapsed * 0.43 + position * 0.72 + channelPhase * 0.16) * 2 * .pi
                )
                let secondPulse = 0.5 + 0.5 * sin(
                    (elapsed * 0.31 - position * 0.54 + 0.27
                        + channelPhase * 0.21) * 2 * .pi
                )
                let spectralEnvelope = min(0.95, max(0.002,
                    firstCluster * (0.12 + 0.78 * firstPulse * firstPulse)
                        + secondCluster * (0.09 + 0.64 * secondPulse * secondPulse)
                ))
                let phase = Float(index) * 0.371 + channelPhase * 2 * .pi
                mixed += sin(2 * .pi * frequency * time + phase) * spectralEnvelope
            }
            return max(-0.95, min(0.95, mixed * overallEnvelope * 0.062))
        }
    }
}
#endif
