import AppKit
import AVFoundation
import ImageIO

@MainActor
final class SystemWallpaperVideoSurface {
    let context: NSObject
    let layer: CALayer
    let displayID: CGDirectDisplayID
    let isPreview: Bool
    let contextID: UInt32
    private let videoLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var loop: AVPlayerLooper?
    private var lease: ScreenSaverMediaLease?
    private var mediaGeneration: String?
    private var failureObservations: [NSKeyValueObservation] = []
    private var failedForActivation = false

    init(displayID: CGDirectDisplayID, size: CGSize, scale: CGFloat, isPreview: Bool) throws {
        guard let type = NSClassFromString("CAContext") as? NSObject.Type,
              type.responds(to: NSSelectorFromString("remoteContextWithOptions:")),
              let context = type.perform(NSSelectorFromString("remoteContextWithOptions:"),
                                         with: ["displayId": NSNumber(value: displayID)])?.takeUnretainedValue() as? NSObject,
              context.responds(to: NSSelectorFromString("setLayer:")),
              context.responds(to: NSSelectorFromString("contextId")),
              let identifier = (context.value(forKey: "contextId") as? NSNumber)?.uint32Value,
              identifier != 0 else {
            throw CocoaError(.featureUnsupported)
        }
        self.context = context
        self.displayID = displayID
        self.isPreview = isPreview
        contextID = identifier
        layer = CALayer()
        layer.backgroundColor = NSColor.black.cgColor
        layer.addSublayer(videoLayer)
        context.setValue(layer, forKey: "layer")
        resize(size: size, scale: scale)
    }

    func resize(size: CGSize, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = CGRect(origin: .zero, size: size)
        layer.contentsScale = scale
        videoLayer.frame = layer.bounds
        CATransaction.commit()
    }

    func apply(_ media: SystemWallpaperMedia?, animate: Bool) throws {
        guard let media else {
            suspend()
            failedForActivation = false
            mediaGeneration = nil
            layer.contents = nil
            return
        }
        if mediaGeneration != media.configuration.content?.mediaGeneration {
            suspend()
            failedForActivation = false
            layer.contents = nil
            let readLease = try ScreenSaverMediaLease(root: media.root)
            if let source = CGImageSourceCreateWithURL(media.poster as CFURL, nil) {
                layer.contents = CGImageSourceCreateImageAtIndex(source, 0,
                    [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
            }
            withExtendedLifetime(readLease) {}
            mediaGeneration = media.configuration.content?.mediaGeneration
        }
        let fit = media.configuration.fillMode == "aspectFit"
        layer.contentsGravity = fit ? .resizeAspect : .resizeAspectFill
        videoLayer.videoGravity = fit ? .resizeAspect : .resizeAspectFill
        if animate, !failedForActivation {
            if player == nil {
                lease = try ScreenSaverMediaLease(root: media.root)
                let queue = AVQueuePlayer()
                queue.isMuted = true
                queue.preventsDisplaySleepDuringVideoPlayback = false
                let looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: media.video))
                loop = looper
                player = queue
                videoLayer.player = queue
                observeFailure(player: queue, looper: looper)
            }
            videoLayer.isHidden = false
            player?.play()
        } else {
            suspend()
            if !animate { failedForActivation = false }
        }
    }

    func suspend() {
        failureObservations.removeAll()
        player?.pause()
        loop?.disableLooping()
        loop = nil
        player?.removeAllItems()
        videoLayer.player = nil
        player = nil
        videoLayer.isHidden = true
        lease = nil
    }

    private func observeFailure(player: AVQueuePlayer, looper: AVPlayerLooper) {
        let failed: @Sendable (AVQueuePlayer) -> Void = { [weak self] player in
            Task { @MainActor [weak self] in
                guard let self, self.player === player else { return }
                self.failedForActivation = true
                self.suspend()
            }
        }
        failureObservations = [
            player.observe(\.status, options: [.initial, .new]) { player, _ in
                if player.status == .failed { failed(player) }
            },
            looper.observe(\.status, options: [.initial, .new]) { looper, _ in
                if looper.status == .failed { failed(player) }
            }
        ]
    }

    func stop() {
        suspend()
        layer.contents = nil
        context.setValue(nil, forKey: "layer")
    }
}

struct SystemWallpaperMedia: Sendable {
    let configuration: ScreenSaverConfiguration
    let root: URL
    let video: URL
    let poster: URL

    static func load(from root: URL) throws -> Self? {
        let file = root.appendingPathComponent("current.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let configuration = try JSONDecoder().decode(ScreenSaverConfiguration.self, from: Data(contentsOf: file))
        guard configuration.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
        guard let content = configuration.content else { return nil }
        let mediaRoot = try ScreenSaverPaths.mediaRoot(in: root, generation: content.mediaGeneration)
        return try Self(configuration: configuration, root: mediaRoot,
                        video: ScreenSaverPaths.resource(content.entryRelativePath, in: mediaRoot),
                        poster: ScreenSaverPaths.resource(content.posterRelativePath, in: mediaRoot))
    }
}
