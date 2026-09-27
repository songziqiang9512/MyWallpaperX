//
//  SystemAudioCaptureBuffer.swift
//  MyWallpaperX
//

import AudioToolbox
import CoreAudio

struct SystemAudioCapturedFrame {
    let rectifiedMono: [Float]
    let signedChannels: [[Float]]
}

final class SystemAudioCaptureBuffer {
    private enum SampleFormat {
        case float32
        case int16
        case int32

        var byteCount: Int {
            switch self {
            case .float32, .int32:
                return 4
            case .int16:
                return 2
            }
        }
    }

    private let maximumFrameCount: Int
    private let maximumBufferCount: Int
    private let maximumBytesPerBuffer: Int
    private let storage: [UnsafeMutableRawPointer]
    private var byteCounts: [Int]
    private var channelCounts: [Int]
    private var frameStrides: [Int]
    private var capturedBufferCount = 0
    private var capturedFrameCount = 0
    private var writeFrameIndex = 0
    private var streamDescription = AudioStreamBasicDescription()

    init(
        maximumFrameCount: Int = 4096,
        maximumBufferCount: Int = 8,
        maximumBytesPerFrame: Int = 32
    ) {
        precondition(maximumFrameCount > 0)
        precondition(maximumBufferCount > 0)
        precondition(maximumBytesPerFrame > 0)

        self.maximumFrameCount = maximumFrameCount
        self.maximumBufferCount = maximumBufferCount
        self.maximumBytesPerBuffer = maximumFrameCount * maximumBytesPerFrame
        self.storage = (0..<maximumBufferCount).map { _ in
            UnsafeMutableRawPointer.allocate(
                byteCount: maximumFrameCount * maximumBytesPerFrame,
                alignment: 16
            )
        }
        self.byteCounts = Array(repeating: 0, count: maximumBufferCount)
        self.channelCounts = Array(repeating: 0, count: maximumBufferCount)
        self.frameStrides = Array(repeating: 0, count: maximumBufferCount)
    }

    deinit {
        storage.forEach { $0.deallocate() }
    }

    /// Callback-owned bounded PCM history. All input blocks enter this ring;
    /// throttling analysis must never splice non-adjacent blocks together.
    func append(
        _ bufferListPointer: UnsafePointer<AudioBufferList>,
        streamDescription: AudioStreamBasicDescription
    ) -> Bool {
        guard let sampleFormat = Self.sampleFormat(for: streamDescription) else {
            invalidate()
            return false
        }
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferListPointer)
        )
        guard !buffers.isEmpty, buffers.count <= maximumBufferCount else {
            invalidate()
            return false
        }
        var inputFrameCount = Int.max
        var sameLayout = capturedBufferCount == buffers.count
            && self.streamDescription.mSampleRate == streamDescription.mSampleRate
            && self.streamDescription.mFormatFlags == streamDescription.mFormatFlags
            && self.streamDescription.mBitsPerChannel == streamDescription.mBitsPerChannel
        for index in buffers.indices {
            let buffer = buffers[index]
            let channelCount = max(1, Int(buffer.mNumberChannels))
            let stride = max(channelCount * sampleFormat.byteCount,
                             Int(streamDescription.mBytesPerFrame))
            guard buffer.mData != nil,
                  stride <= maximumBytesPerBuffer / maximumFrameCount,
                  Int(buffer.mDataByteSize) / stride > 0 else {
                invalidate()
                return false
            }
            inputFrameCount = min(inputFrameCount, Int(buffer.mDataByteSize) / stride)
            sameLayout = sameLayout && frameStrides[index] == stride
                && channelCounts[index] == channelCount
        }
        if !sameLayout { invalidate() }
        let count = min(maximumFrameCount, inputFrameCount)
        let firstCount = min(count, maximumFrameCount - writeFrameIndex)
        for index in buffers.indices {
            let buffer = buffers[index]
            let channels = max(1, Int(buffer.mNumberChannels))
            let stride = max(channels * sampleFormat.byteCount,
                             Int(streamDescription.mBytesPerFrame))
            // A large callback retains its newest complete, channel-aligned tail.
            let source = buffer.mData!.advanced(by: (inputFrameCount - count) * stride)
            storage[index].advanced(by: writeFrameIndex * stride).copyMemory(
                from: source, byteCount: firstCount * stride
            )
            if firstCount < count {
                storage[index].copyMemory(from: source.advanced(by: firstCount * stride),
                    byteCount: (count - firstCount) * stride)
            }
            frameStrides[index] = stride
            channelCounts[index] = channels
            byteCounts[index] = maximumFrameCount * stride
        }
        writeFrameIndex = (writeFrameIndex + count) % maximumFrameCount
        capturedFrameCount = min(maximumFrameCount, capturedFrameCount + count)
        capturedBufferCount = buffers.count
        self.streamDescription = streamDescription
        return true
    }

    /// Copy a complete analysis window into the existing worker-owned snapshot.
    /// Caller holds the handoff gate for destination; source remains callback-owned.
    func copyLatestFrames(_ count: Int, to destination: SystemAudioCaptureBuffer) -> Bool {
        guard destination !== self, count > 0, capturedFrameCount >= count,
              count <= destination.maximumFrameCount,
              capturedBufferCount <= destination.maximumBufferCount else { return false }
        for index in 0..<capturedBufferCount {
            guard frameStrides[index] * count <= destination.maximumBytesPerBuffer else { return false }
        }
        let start = (writeFrameIndex - count + maximumFrameCount) % maximumFrameCount
        let firstCount = min(count, maximumFrameCount - start)
        for index in 0..<capturedBufferCount {
            let stride = frameStrides[index]
            destination.storage[index].copyMemory(
                from: storage[index].advanced(by: start * stride), byteCount: firstCount * stride
            )
            if firstCount < count {
                destination.storage[index].advanced(by: firstCount * stride).copyMemory(
                    from: storage[index], byteCount: (count - firstCount) * stride
                )
            }
            destination.frameStrides[index] = stride
            destination.channelCounts[index] = channelCounts[index]
            destination.byteCounts[index] = count * stride
        }
        destination.capturedBufferCount = capturedBufferCount
        destination.capturedFrameCount = count
        destination.writeFrameIndex = count % destination.maximumFrameCount
        destination.streamDescription = streamDescription
        return true
    }

    var decodedFrame: SystemAudioCapturedFrame? {
        guard
            capturedBufferCount > 0,
            capturedFrameCount > 0,
            let sampleFormat = Self.sampleFormat(for: streamDescription)
        else {
            return nil
        }

        var channels: [[Float]] = []
        channels.reserveCapacity(
            channelCounts.prefix(capturedBufferCount).reduce(0, +)
        )

        for bufferIndex in 0..<capturedBufferCount {
            for channelIndex in 0..<channelCounts[bufferIndex] {
                var channel = Array(repeating: Float(0), count: capturedFrameCount)
                for frameIndex in 0..<capturedFrameCount {
                    channel[frameIndex] = decodedSample(
                        format: sampleFormat,
                        bufferIndex: bufferIndex,
                        frameIndex: frameIndex,
                        channelIndex: channelIndex
                    )
                }
                channels.append(channel)
            }
        }
        guard !channels.isEmpty else { return nil }

        var rectifiedMono = Array(repeating: Float(0), count: capturedFrameCount)
        for frameIndex in 0..<capturedFrameCount {
            var magnitude: Float = 0
            for channel in channels {
                magnitude += abs(channel[frameIndex])
            }
            rectifiedMono[frameIndex] = magnitude / Float(channels.count)
        }
        return SystemAudioCapturedFrame(
            rectifiedMono: rectifiedMono,
            signedChannels: channels
        )
    }

    func reset() {
        invalidate()
    }

    private func decodedSample(
        format: SampleFormat,
        bufferIndex: Int,
        frameIndex: Int,
        channelIndex: Int
    ) -> Float {
        let physicalFrame = (writeFrameIndex - capturedFrameCount + maximumFrameCount + frameIndex)
            % maximumFrameCount
        let offset = physicalFrame * frameStrides[bufferIndex] + channelIndex * format.byteCount
        guard offset + format.byteCount <= byteCounts[bufferIndex] else { return 0 }

        let value: Float
        switch format {
        case .float32:
            value = storage[bufferIndex].load(fromByteOffset: offset, as: Float.self)
        case .int16:
            let sample = storage[bufferIndex].load(fromByteOffset: offset, as: Int16.self)
            value = Float(sample) / 32_768
        case .int32:
            let sample = storage[bufferIndex].load(fromByteOffset: offset, as: Int32.self)
            value = Float(sample) / 2_147_483_648
        }
        return value.isFinite ? value : 0
    }

    private func invalidate() {
        capturedBufferCount = 0
        capturedFrameCount = 0
        writeFrameIndex = 0
    }

    private static func sampleFormat(
        for streamDescription: AudioStreamBasicDescription
    ) -> SampleFormat? {
        guard streamDescription.mFormatID == kAudioFormatLinearPCM else { return nil }
        guard (streamDescription.mFormatFlags & kAudioFormatFlagIsBigEndian) == 0 else {
            return nil
        }

        let flags = streamDescription.mFormatFlags
        let bitsPerChannel = Int(streamDescription.mBitsPerChannel)
        if (flags & kAudioFormatFlagIsFloat) != 0, bitsPerChannel == 32 {
            return .float32
        }
        if (flags & kAudioFormatFlagIsSignedInteger) != 0, bitsPerChannel == 16 {
            return .int16
        }
        if (flags & kAudioFormatFlagIsSignedInteger) != 0, bitsPerChannel == 32 {
            return .int32
        }
        return nil
    }
}
