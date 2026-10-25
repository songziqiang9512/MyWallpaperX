import AVFoundation
import CoreMedia
import VideoToolbox
import UniformTypeIdentifiers

/// Media input validation and container preparation. Playback, decoding,
/// timing and publication remain in the existing video source.
nonisolated enum SceneVideoPayloadPreparation {
    private static let registeredDecoders: Void = {
        VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9)
    }()

    static func registerDecoders() { _ = registeredDecoders }

    static func supportsLocalVideo(url: URL) -> Bool {
        ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }

    enum Failure: Error {
        case format(OSStatus)
        case buffer(OSStatus)
        case writer(String)
        case invalidMedia
        case deadlineExceeded
    }

    /// Offline selection validates real AVFoundation metadata before saving
    /// intent. This neither creates a decoder nor claims a ready publication.
    static func validateLocalVideo(at url: URL) async throws {
        guard url.isFileURL, supportsLocalVideo(url: url) else { throw Failure.invalidMedia }
        let asset = AVURLAsset(url: url)
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try Task.checkCancellation()
                    let (playable, protected, duration) = try await asset.load(
                        .isPlayable, .hasProtectedContent, .duration
                    )
                    let seconds = CMTimeGetSeconds(duration)
                    guard playable, !protected, duration.isNumeric,
                          seconds.isFinite, seconds > 0 else { throw Failure.invalidMedia }
                    let tracks = try await asset.loadTracks(withMediaType: .video)
                    guard let track = tracks.first else { throw Failure.invalidMedia }
                    let size = try await track.load(.naturalSize)
                    guard size.width.isFinite, size.height.isFinite,
                          size.width > 0, size.height > 0 else { throw Failure.invalidMedia }
                    try Task.checkCancellation()
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    asset.cancelLoading()
                    throw Failure.deadlineExceeded
                }
                defer { group.cancelAll() }
                _ = try await group.next()
                // Structured scope waits for the metadata child to exit even
                // on timeout/cancellation; callers can then close file access.
            }
        } onCancel: {
            asset.cancelLoading()
        }
    }

    /// Segment delivery suppresses AVAssetWriter's URL writer. The existing
    /// owned-file sink reserves the actual output bytes before every write.
    private final class SegmentSink: NSObject, @unchecked Sendable {
        final class Cancellation: @unchecked Sendable {
            private let lock = NSLock()
            private var cancelled = false
            func cancel() { lock.lock(); cancelled = true; lock.unlock() }
            func check() throws {
                lock.lock(); defer { lock.unlock() }
                if cancelled { throw CancellationError() }
            }
        }

        let cancellation = Cancellation()
        private let output: SceneVideoOwnedFile.Writer
        private let lock = NSLock()
        private var failure: (any Error)?
        private var initializationReceived = false
        private var segments = 0
        private var closed = false

        init(output: SceneVideoOwnedFile.Writer) { self.output = output }

        // Receives a synchronous NSData byte view from the native delegate.
        func receiveSegment(_ bytes: UnsafeRawBufferPointer,
                            segmentType: AVAssetSegmentType) {
            lock.lock(); defer { lock.unlock() }
            guard !closed, failure == nil else { return }
            do {
                try cancellation.check()
                switch segmentType {
                case .initialization:
                    guard !initializationReceived, segments == 0 else {
                        throw Failure.writer("duplicate-initialization-segment")
                    }
                case .separable:
                    guard initializationReceived else { throw Failure.writer("missing-initialization-segment") }
                @unknown default: throw Failure.writer("unknown-segment-type")
                }
                try output.append(bytes, checkCancellation: cancellation.check)
                if segmentType == .initialization { initializationReceived = true }
                else { segments += 1 }
            } catch { failure = error }
        }

        func check() throws {
            try cancellation.check()
            lock.lock(); defer { lock.unlock() }
            if let failure { throw failure }
        }

        func hasSegments(_ count: Int) throws -> Bool {
            try check()
            lock.lock(); defer { lock.unlock() }
            return segments >= count
        }

        func finish(expectedSegments: Int) throws {
            lock.lock(); defer { lock.unlock() }
            try cancellation.check()
            if let failure { throw failure }
            guard initializationReceived, segments == expectedSegments else {
                throw Failure.writer("incomplete-segment-output")
            }
            _ = try output.finish(checkCancellation: cancellation.check)
            closed = true
        }

        func abort() {
            cancellation.cancel()
            lock.lock(); defer { lock.unlock() }
            closed = true
            output.abort()
        }
    }

    static func writeWebM(_ payload: Data, to output: SceneVideoOwnedFile.Writer) async throws {
        var completed = false
        defer { if !completed { output.abort() } }
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
        let writer = AVAssetWriter(contentType: .mpeg4Movie)
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = .indefinite
        let sink = SegmentSink(output: output)
        let adapter = SceneVideoSegmentDelegate(owner: sink, callback: { owner, bytes, length, segmentType in
            let originalSink = owner as! SegmentSink
            originalSink.receiveSegment(UnsafeRawBufferPointer(start: bytes, count: Int(length)),
                                        segmentType: segmentType)
        })
        // AVAssetWriter holds its delegate weakly. Keep the adapter and sink
        // through finish, or through cancelWriting and abort.
        defer { withExtendedLifetime(adapter) {} }
        writer.delegate = adapter
        defer {
            if !completed {
                writer.cancelWriting()
                sink.abort()
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
        func checkpoint() throws {
            try Task.checkCancellation()
            try sink.check()
            guard clock.now < deadline else { throw Failure.deadlineExceeded }
        }
        // Await each requested flush before appending the next sync sample.
        // Callback IO stays in the callback; no second queue stores segments.
        func waitForSegments(_ count: Int) async throws {
            while try !sink.hasSegments(count) {
                try checkpoint()
                guard writer.status == .writing || writer.status == .completed else {
                    throw writer.error ?? Failure.writer("segment-output-unavailable")
                }
                try await Task.sleep(for: .milliseconds(1))
            }
        }
        try await withTaskCancellationHandler {
            var appendedPackets = 0
            var flushedSegments = 0
            var segmentStart: Int64 = 0
            for packet in video.packets {
                try checkpoint()
                if packet.isKeyframe, appendedPackets > 0,
                   packet.presentationTimeNanoseconds - segmentStart >= 1_000_000_000 {
                    writer.flushSegment()
                    flushedSegments += 1
                    try await waitForSegments(flushedSegments)
                    segmentStart = packet.presentationTimeNanoseconds
                }
                while !input.isReadyForMoreMediaData {
                    try checkpoint()
                    guard writer.status == .writing else {
                        throw writer.error ?? Failure.writer("append-unavailable")
                    }
                    try await Task.sleep(for: .milliseconds(1))
                }
                let sample = try makeSample(packet, payload: payload, format: format)
                guard input.append(sample) else {
                    throw writer.error ?? Failure.writer("append-failed")
                }
                appendedPackets += 1
            }
            input.markAsFinished()
            beginFinishing(writer)
            while writer.status == .writing {
                try checkpoint()
                try await Task.sleep(for: .milliseconds(1))
            }
            try checkpoint()
            guard writer.status == .completed else {
                throw writer.error ?? Failure.writer("finish-failed")
            }
            try await waitForSegments(flushedSegments + 1)
            try checkpoint()
            try sink.finish(expectedSegments: flushedSegments + 1)
            completed = true
        } onCancel: {
            // Never call cancelWriting concurrently with input.append. The
            // original worker observes this flag, exits append and cancels.
            sink.cancellation.cancel()
        }
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
