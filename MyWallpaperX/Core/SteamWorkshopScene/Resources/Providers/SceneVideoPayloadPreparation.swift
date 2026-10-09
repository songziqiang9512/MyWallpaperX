import AVFoundation
import CoreMedia
import VideoToolbox

/// Container preparation only. Playback, timing and publication remain in the
/// existing video source. Compressed packets are copied without decoding.
nonisolated enum SceneVideoPayloadPreparation {
    private static let registeredDecoders: Void = {
        VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9)
    }()

    static func registerDecoders() { _ = registeredDecoders }

    enum Failure: Error {
        case format(OSStatus)
        case buffer(OSStatus)
        case writer(String)
        case deadlineExceeded
    }

    static func writeWebM(_ payload: Data, to url: URL) async throws {
        registerDecoders()
        let video = try SceneWebMContainer.parse(payload, cancellationCheck: {
            try Task.checkCancellation()
        })
        let track = video.track
        var format: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_VP9,
            width: Int32(track.width), height: Int32(track.height),
            extensions: [kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String:
                ["vpcC": track.vpCodecConfiguration]] as CFDictionary,
            formatDescriptionOut: &format)
        guard status == noErr, let format else { throw Failure.format(status) }
        try Task.checkCancellation()
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        var completed = false
        defer {
            if !completed {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: url)
            }
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil,
                                      sourceFormatHint: format)
        input.expectsMediaDataInRealTime = false
        // WebM timestamps and DefaultDuration are nanoseconds. The writer's
        // default 600 Hz would quantize e.g. 17 ms to 16.667 ms.
        input.mediaTimeScale = 1_000_000_000
        guard writer.canAdd(input) else { throw Failure.writer("track-unsupported") }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? Failure.writer("start-failed")
        }
        writer.startSession(atSourceTime: .zero)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        for packet in video.packets {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else {
                    throw writer.error ?? Failure.writer("append-unavailable")
                }
                guard clock.now < deadline else { throw Failure.deadlineExceeded }
                try await Task.sleep(for: .milliseconds(1))
            }
            guard clock.now < deadline else { throw Failure.deadlineExceeded }
            let sample = try makeSample(packet, payload: payload, format: format)
            guard input.append(sample) else {
                throw writer.error ?? Failure.writer("append-failed")
            }
        }
        input.markAsFinished()
        beginFinishing(writer)
        while writer.status == .writing {
            try Task.checkCancellation()
            guard clock.now < deadline else { throw Failure.deadlineExceeded }
            try await Task.sleep(for: .milliseconds(1))
        }
        try Task.checkCancellation()
        guard clock.now < deadline else { throw Failure.deadlineExceeded }
        guard writer.status == .completed else {
            throw writer.error ?? Failure.writer("finish-failed")
        }
        completed = true
    }

    // Use the nonblocking completion API, polling its thread-safe status on
    // this same preparation task so cancellation also bounds finalization.
    private static func beginFinishing(_ writer: AVAssetWriter) {
        writer.finishWriting(completionHandler: {})
    }

    private static func makeSample(
        _ packet: SceneWebMContainer.Packet, payload: Data,
        format: CMVideoFormatDescription
    ) throws -> CMSampleBuffer {
        let range = packet.dataRange
        var buffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: range.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: range.count, flags: 0, blockBufferOut: &buffer)
        guard status == noErr, let buffer else { throw Failure.buffer(status) }
        status = payload.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!.advanced(by: range.lowerBound),
                blockBuffer: buffer, offsetIntoDestination: 0, dataLength: range.count)
        }
        guard status == noErr else { throw Failure.buffer(status) }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: packet.durationNanoseconds, timescale: 1_000_000_000),
            presentationTimeStamp: CMTime(value: packet.presentationTimeNanoseconds,
                                          timescale: 1_000_000_000),
            decodeTimeStamp: .invalid)
        var size = range.count
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault,
            dataBuffer: buffer, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw Failure.buffer(status) }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample,
                createIfNecessary: true) as? [NSMutableDictionary],
              let first = attachments.first else { throw Failure.writer("sample-attachments") }
        first[kCMSampleAttachmentKey_NotSync] = !packet.isKeyframe
        return sample
    }
}
