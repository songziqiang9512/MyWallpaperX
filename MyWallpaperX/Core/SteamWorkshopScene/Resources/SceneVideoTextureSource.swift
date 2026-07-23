import AVFoundation
import CoreVideo
import Metal
import QuartzCore

final class SceneVideoTextureSource {
    private let player: AVPlayer
    private let videoOutput: AVPlayerItemVideoOutput
    private let textureCache: CVMetalTextureCache
    private let temporaryFileURL: URL
    private let endObserver: NSObjectProtocol
    private var currentCVMetalTexture: CVMetalTexture?
    private var lastTexture: MTLTexture?

    init?(
        layerID: Int,
        mp4PayloadData: Data,
        cacheDirectory: URL,
        device: MTLDevice
    ) {
        let outputDirectory = cacheDirectory
            .appendingPathComponent(".mywallpaperx-scene-video-payloads", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            return nil
        }

        let filename = "layer-\(layerID)-\(UUID().uuidString).mp4"
        let fileURL = outputDirectory.appendingPathComponent(filename)
        do {
            try mp4PayloadData.write(to: fileURL, options: [.atomic])
        } catch {
            return nil
        }
        temporaryFileURL = fileURL

        let output = AVPlayerItemVideoOutput(
            pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )
        output.suppressesPlayerRendering = true
        videoOutput = output

        let item = AVPlayerItem(url: fileURL)
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        player.isMuted = true
        player.volume = 0

        var maybeTextureCache: CVMetalTextureCache?
        let cacheStatus = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &maybeTextureCache
        )
        guard cacheStatus == kCVReturnSuccess,
              let textureCache = maybeTextureCache else {
            return nil
        }
        self.textureCache = textureCache

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        player.play()
    }

    deinit {
        NotificationCenter.default.removeObserver(endObserver)
        player.pause()
        try? FileManager.default.removeItem(at: temporaryFileURL)
    }

    func currentTexture(forHostTime hostTime: CFTimeInterval) -> MTLTexture? {
        let itemTime = videoOutput.itemTime(forHostTime: hostTime)

        if videoOutput.hasNewPixelBuffer(forItemTime: itemTime),
           let pixelBuffer = videoOutput.copyPixelBuffer(
               forItemTime: itemTime,
               itemTimeForDisplay: nil
           ),
           let texture = makeTexture(from: pixelBuffer) {
            lastTexture = texture
        }

        return lastTexture
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }

        var cvMetalTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvMetalTexture
        )
        guard status == kCVReturnSuccess,
              let cvMetalTexture,
              let texture = CVMetalTextureGetTexture(cvMetalTexture) else {
            return nil
        }

        currentCVMetalTexture = cvMetalTexture
        return texture
    }
}
