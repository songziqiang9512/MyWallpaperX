import AppKit
import AVFoundation
import Foundation

private enum Failure: Error { case assertion(String) }
private func expect(_ value: Bool, _ label: String) throws {
    if !value { throw Failure.assertion(label) }
}
enum PixabayDownloadedAssetMetadata {
    static func nativeSize(for asset: AVAsset) async -> CGSize? { nil }
}

@main private struct PixabayDownloadedThumbnailHarness {
    static func main() async throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let image = await PixabayThumbnailVideoGeneration(url: url, request: nil).image()
        try expect(image != nil, "async 0.5s video frame failed")
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 520, height: 300)
        let reference = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        let referenceImage = NSImage(cgImage: reference, size: .zero)
        guard let image, case .image(let nsImage, _) = image else {
            throw Failure.assertion("expected an NSImage ThumbnailInput")
        }
        let representation = nsImage.representations.first!, referenceRep = referenceImage.representations.first!
        try expect(reference.width <= 520 && reference.height <= 300
            && representation.pixelsWide == referenceRep.pixelsWide
            && representation.pixelsHigh == referenceRep.pixelsHigh
            && nsImage.size == referenceImage.size,
            "the bridge changed the original 520x300 extraction or NSImage sizing")
        let failure = await PixabayThumbnailVideoGeneration(url: url.appendingPathExtension("missing"), request: nil).image()
        try expect(failure == nil, "missing local media must terminate as failure")
        for _ in 0..<20 {
            let task = Task { await PixabayThumbnailVideoGeneration(url: url, request: nil).image() }
            task.cancel()
            try expect(await task.value == nil, "cancelled generation published image")
        }
        try expect(await PixabayThumbnailVideoGeneration(url: url, request: nil).image() != nil,
            "cancellation poisoned a later independent generation")
        print("{\"realFrameAndDimensions\":true,\"missingMediaCompletes\":true,\"cancelledGenerationsDrain\":true,\"retryAfterCancellation\":true}")
    }
}
