import AudioToolbox
import CoreAudio

/// Test input assembly through the real callback ring and worker snapshot.
/// This fixture never supplies PCM history, sanitization or FFT on its own.
final class SystemAudioSpectrumTestCapture {
    private let history = SystemAudioCaptureBuffer(maximumFrameCount: SystemAudioSceneSpectrumAnalyzer.maximumFrameCount)
    private let worker = SystemAudioCaptureBuffer(maximumFrameCount: SystemAudioSceneSpectrumAnalyzer.maximumFrameCount)

    @discardableResult
    func append(_ channels: [[Float]], sampleRate: Float) -> Bool {
        guard !channels.isEmpty, channels.allSatisfy({ !$0.isEmpty }) else { return false }
        let buffers = AudioBufferList.allocate(maximumBuffers: channels.count)
        let samples = channels.map { channel -> UnsafeMutablePointer<Float> in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: channel.count)
            channel.withUnsafeBufferPointer { pointer.initialize(from: $0.baseAddress!, count: $0.count) }
            return pointer
        }
        defer {
            buffers.unsafeMutablePointer.deallocate()
            for (pointer, channel) in zip(samples, channels) {
                pointer.deinitialize(count: channel.count)
                pointer.deallocate()
            }
        }
        buffers.count = channels.count
        for index in channels.indices {
            buffers[index] = AudioBuffer(mNumberChannels: 1,
                mDataByteSize: UInt32(channels[index].count * MemoryLayout<Float>.stride), mData: samples[index])
        }
        let format = AudioStreamBasicDescription(mSampleRate: Double(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: UInt32(channels.count), mBitsPerChannel: 32, mReserved: 0)
        return history.append(buffers.unsafePointer, streamDescription: format)
    }

    func latestFrame(sampleRate: Float) -> SystemAudioCapturedFrame? {
        let count = SystemAudioSceneSpectrumAnalyzer.analysisWindowCount(sampleRate: sampleRate)
        guard history.copyLatestFrames(count, to: worker) else { return nil }
        return worker.decodedFrame
    }

    static func frame(_ channels: [[Float]], sampleRate: Float) -> SystemAudioCapturedFrame {
        let capture = SystemAudioSpectrumTestCapture()
        precondition(capture.append(channels, sampleRate: sampleRate), "test PCM must be a real accepted buffer")
        guard let frame = capture.latestFrame(sampleRate: sampleRate) else {
            preconditionFailure("test analysis requires a complete real worker snapshot: rate=\(sampleRate), required=\(SystemAudioSceneSpectrumAnalyzer.analysisWindowCount(sampleRate: sampleRate)), counts=\(channels.map(\.count))")
        }
        return frame
    }
}
