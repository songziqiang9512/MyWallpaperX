#if DEBUG
import AppKit
@preconcurrency import Metal

nonisolated final class SceneDebugFrameCapture {
    private struct Request {
        let reason: String
        let outputDirectory: URL
    }

    private let isEnabled = ProcessInfo.processInfo.arguments.contains(
        "--mwx-debug-scene-evidence-dir"
    )
    private var pendingRequests: [Request] = []

    func configure(_ layer: CAMetalLayer) {
        if isEnabled {
            layer.framebufferOnly = false
        }
    }

    func request(reason: String, outputDirectory: URL) {
        guard isEnabled else { return }
        pendingRequests.append(Request(reason: reason, outputDirectory: outputDirectory))
    }

    func encodeIfRequested(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard !pendingRequests.isEmpty else { return }
        let request = pendingRequests.removeFirst()

        let width = texture.width
        let height = texture.height
        let rowBytes = width * 4
        let byteCount = rowBytes * height
        guard texture.pixelFormat == .bgra8Unorm,
              let buffer = texture.device.makeBuffer(length: byteCount, options: .storageModeShared),
              let encoder = commandBuffer.makeBlitCommandEncoder() else {
            Self.reportFailure(reason: request.reason, stage: "metal-readback-setup")
            return
        }

        encoder.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: buffer,
            destinationOffset: 0,
            destinationBytesPerRow: rowBytes,
            destinationBytesPerImage: byteCount
        )
        encoder.endEncoding()
        commandBuffer.addCompletedHandler { completed in
            guard completed.status == .completed else {
                Self.reportFailure(
                    reason: request.reason,
                    stage: "metal-command-\(completed.status.rawValue)"
                )
                return
            }
            Self.persist(
                buffer: buffer,
                width: width,
                height: height,
                rowBytes: rowBytes,
                request: request
            )
        }
    }

    private static func persist(
        buffer: MTLBuffer,
        width: Int,
        height: Int,
        rowBytes: Int,
        request: Request
    ) {
        let pixels = Data(bytes: buffer.contents(), count: rowBytes * height)
        guard let provider = CGDataProvider(data: pixels as CFData),
              let source = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: rowBytes,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: [
                    .byteOrder32Little,
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                ],
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ),
              let image = resized(source, maximumDimension: 1_280),
              let png = NSBitmapImageRep(cgImage: image).representation(
                using: .png,
                properties: [:]
              ) else {
            reportFailure(reason: request.reason, stage: "png-encode")
            return
        }

        let outputURL = request.outputDirectory
            .appendingPathComponent("scene-\(request.reason)-window.png")
        do {
            try png.write(to: outputURL, options: [.atomic])
            NSLog(
                "MWX DEBUG SCENE: phase=snapshot reason=%@ source=metal path=%@",
                request.reason,
                outputURL.path
            )
        } catch {
            reportFailure(reason: request.reason, stage: "write", error: error)
        }
    }

    private static func resized(_ source: CGImage, maximumDimension: Int) -> CGImage? {
        let scale = min(
            1,
            CGFloat(maximumDimension) / CGFloat(max(source.width, source.height))
        )
        guard scale < 1 else { return source }
        let width = max(1, Int((CGFloat(source.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(source.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func reportFailure(
        reason: String,
        stage: String,
        error: Error? = nil
    ) {
        NSLog(
            "MWX DEBUG SCENE: phase=snapshot-failed reason=%@ stage=%@ error=%@",
            reason,
            stage,
            error?.localizedDescription ?? "unknown"
        )
    }
}
#endif
