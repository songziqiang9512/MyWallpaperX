import AVFoundation
import AppKit
import Foundation

/// The library and screen-saver publisher share the same AVFoundation extraction.
/// Call from a worker queue; neither decoding nor the bounded wait belongs on UI.
nonisolated enum VideoStillFrame {
    private nonisolated final class ImageResult: @unchecked Sendable {
        let lock = NSLock()
        var image: CGImage?

        func store(_ image: CGImage?) {
            lock.lock()
            self.image = image
            lock.unlock()
        }

        func load() -> CGImage? {
            lock.lock()
            defer { lock.unlock() }
            return image
        }
    }

    static func image(using generator: AVAssetImageGenerator, at time: CMTime,
                      isCancelled: () -> Bool = { false }) -> CGImage? {
        let result = ImageResult()
        let semaphore = DispatchSemaphore(value: 0)
        generator.generateCGImageAsynchronously(for: time) { image, _, _ in
            result.store(image)
            semaphore.signal()
        }
        let deadline = DispatchTime.now() + 30
        while semaphore.wait(timeout: .now() + 0.1) == .timedOut {
            if isCancelled() || DispatchTime.now() >= deadline {
                generator.cancelAllCGImageGeneration()
                return nil
            }
        }
        return isCancelled() ? nil : result.load()
    }

    static func writeJPEG(from source: URL, to destination: URL,
                          isCancelled: () -> Bool = { false }) throws {
        try autoreleasepool {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 4096, height: 4096)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            guard let frame = image(using: generator, at: .zero, isCancelled: isCancelled),
                  let data = NSBitmapImageRep(cgImage: frame).representation(
                    using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                throw CocoaError(isCancelled() ? .userCancelled : .fileReadCorruptFile)
            }
            guard !isCancelled() else { throw CocoaError(.userCancelled) }
            try data.write(to: destination)
        }
    }
}
