import AVFoundation
import CoreVideo

@available(macOS 26.0, *)
enum VideoTrackMetadataFixtures {
    static func writeH264(_ url: URL, width: Int = 64, height: Int = 32, rotationAngle: CGFloat = .pi / 2,
                          frameDuration: CMTime = CMTime(value: 1_001, timescale: 30_000)) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.transform = CGAffineTransform(rotationAngle: rotationAngle)
        input.mediaTimeScale = frameDuration.timescale
        let attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA), size: CVImageSize(width: width, height: height))
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: attributes)
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        for index in 0..<30 {
            var buffer = try CVMutablePixelBuffer(attributes)
            buffer.accessUnsafeMutableRawPlaneBytes { planes in
                for plane in planes { _ = plane.bytes.initializeMemory(as: UInt8.self, repeating: 0x55) }
            }
            try await receiver.append(CVReadOnlyPixelBuffer(buffer), with: CMTimeMultiply(frameDuration, multiplier: Int32(index)))
        }
        writer.endSession(atSourceTime: CMTimeMultiply(frameDuration, multiplier: 30))
        receiver.finish()
        await withCheckedContinuation { done in writer.finishWriting { done.resume() } }
        precondition(writer.status == .completed, "H264 fixture writer did not finish")
    }
}
