import AVFoundation
import CoreVideo
import Metal

final class SceneVideoTextureSource {
    struct Frame {
        let texture: MTLTexture
        let content: SceneTextureContent
        let contentGeneration: UInt64
        let itemTime: TimeInterval
        let epoch: UInt64
        let layerID: Int

        var publication: SceneTextureProviderPublication {
            let size = CGSize(width: texture.width, height: texture.height)
            return SceneTextureProviderPublication(
                requestIdentity: .layerSource(layerID),
                candidate: SceneTextureCandidate(
                    texture: texture,
                    identity: .provider(.video(
                        layerID: layerID,
                        lifecycleEpoch: epoch
                    )),
                    generation: .provider(contentGeneration: contentGeneration),
                    purpose: .premultipliedColor,
                    content: content,
                    physicalSize: size,
                    mappedSize: size,
                    uvTransform: .identity,
                    sampling: .linearClamp
                ),
                contentGeneration: contentGeneration
            )
        }
    }

    private let player: AVPlayer
    private let item: AVPlayerItem
    private let videoOutput: AVPlayerItemVideoOutput
    private let textureCache: CVMetalTextureCache
    private let temporaryFileURL: URL
    private let layerID: Int
    private var endObserver: NSObjectProtocol?
    private var lifecycle = SceneVideoProviderLifecycleState(epoch: 0)
    private var currentCVMetalTexture: CVMetalTexture?
    private var lastFrame: Frame?
    private var hasStarted = false
    private var needsPlayerAnchor = true
    private var playbackBarrier: UInt64 = 0
    private var endedGeneration: UInt64 = 0

    init?(
        layerID: Int,
        mp4PayloadData: Data,
        cacheDirectory: URL,
        device: MTLDevice
    ) {
        self.layerID = layerID
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
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        self.textureCache = textureCache

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
        self.item = item
        player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .pause
        player.isMuted = true
        player.volume = 0

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            endedGeneration &+= 1
            lifecycle.didReachEnd(duration: duration)
            markPlayerAnchorRequired()
        }
    }

    deinit {
        stop()
    }

    func adoptLifecycleEpoch(_ epoch: UInt64) {
        guard !hasStarted, lifecycle.contentGeneration == 0 else { return }
        lifecycle = SceneVideoProviderLifecycleState(epoch: epoch)
    }

    func currentFrame(for timing: SceneFrameTiming) -> Frame? {
        guard player.currentItem != nil else { return nil }
        if !hasStarted {
            lifecycle.start(
                sceneTime: timing.sceneTime,
                hostTime: timing.hostTime
            )
            hasStarted = true
            markPlayerAnchorRequired()
        }
        let plan = lifecycle.planFrame(
            frameIndex: timing.frameIndex,
            sceneTime: timing.sceneTime,
            hostTime: timing.hostTime
        )
        guard plan.shouldDecode else { return lastFrame }
        guard item.status == .readyToPlay else {
            markPlayerAnchorRequired()
            return lastFrame
        }

        let itemTime = boundedItemTime(plan.itemTime)
        if lifecycle.isPlaying && (needsPlayerAnchor || player.rate == 0) {
            player.setRate(
                Float(lifecycle.rate),
                time: itemTime,
                atHostTime: hostTime(plan.hostTime)
            )
            needsPlayerAnchor = player.rate == 0
        } else if !lifecycle.isPlaying && needsPlayerAnchor {
            player.pause()
            player.seek(
                to: itemTime,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
        if lifecycle.isPlaying && player.rate == 0 {
            needsPlayerAnchor = true
            return lastFrame
        }
        let expectedBarrier = playbackBarrier
        guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime) else {
            if player.rate == 0 {
                needsPlayerAnchor = true
            }
            return lastFrame
        }
        var itemTimeForDisplay = CMTime.invalid
        guard let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: itemTime,
            itemTimeForDisplay: &itemTimeForDisplay
        ),
        expectedBarrier == playbackBarrier,
        let texture = makeTexture(from: pixelBuffer),
        let contentGeneration = lifecycle.didPublish(
            frameIndex: timing.frameIndex
        ) else {
            return lastFrame
        }

        let frame = Frame(
            texture: texture,
            content: resolvedColorContent(for: pixelBuffer),
            contentGeneration: contentGeneration,
            itemTime: plan.itemTime,
            epoch: plan.epoch,
            layerID: layerID
        )
        needsPlayerAnchor = false
        if !lifecycle.isPlaying { player.pause() }
        lastFrame = frame
        return frame
    }

    func playbackSnapshot(
        sceneTime: TimeInterval
    ) -> SceneScriptVideoPlaybackSnapshot {
        let duration = self.duration
        let current = boundedCurrentTime(
            lifecycle.currentTime(at: sceneTime),
            duration: duration
        )
        return .init(
            layerID: layerID,
            duration: duration,
            rate: lifecycle.rate,
            loop: lifecycle.loop,
            currentTime: current,
            isPlaying: lifecycle.isPlaying,
            endedGeneration: endedGeneration
        )
    }

    func canApply(_ command: SceneScriptVideoCommand) -> Bool {
        guard command.layerID == layerID else { return false }
        switch command.action {
        case .play, .pause, .stop, .setLoop:
            return true
        case let .setCurrentTime(value):
            return value.isFinite && value >= 0
                && (duration == 0 || value <= duration)
        case let .setRate(value):
            return value.isFinite && value > 0 && value <= 16
        }
    }

    func apply(
        _ command: SceneScriptVideoCommand,
        timing: SceneFrameTiming
    ) {
        guard canApply(command) else { return }
        if !hasStarted {
            lifecycle.start(
                sceneTime: timing.sceneTime,
                hostTime: timing.hostTime
            )
            hasStarted = true
        }
        switch command.action {
        case .play:
            lifecycle.resume(
                sceneTime: timing.sceneTime,
                hostTime: timing.hostTime
            )
            markPlayerAnchorRequired()
        case .pause:
            lifecycle.pause(
                sceneTime: timing.sceneTime,
                hostTime: timing.hostTime
            )
            markPlayerAnchorRequired()
        case .stop:
            lifecycle.seek(
                to: 0,
                sceneTime: timing.sceneTime,
                hostTime: timing.hostTime
            )
            lifecycle.pause(
                sceneTime: timing.sceneTime,
                hostTime: timing.hostTime
            )
            markPlayerAnchorRequired()
        case let .setCurrentTime(value):
            lifecycle.seek(
                to: value,
                sceneTime: timing.sceneTime,
                hostTime: timing.hostTime
            )
            markPlayerAnchorRequired()
        case let .setRate(value):
            lifecycle.setRate(
                value,
                sceneTime: timing.sceneTime,
                hostTime: timing.hostTime
            )
            markPlayerAnchorRequired()
        case let .setLoop(value):
            lifecycle.setLoop(value)
        }
    }

    /// AVPlayer's BGRA output is a typed color source only when CoreVideo
    /// explicitly describes its alpha representation. Unknown or straight
    /// alpha stays unresolved so it cannot enter a premultiplied Program slot.
    private func resolvedColorContent(
        for pixelBuffer: CVPixelBuffer
    ) -> SceneTextureContent {
        if let opaque = CVBufferCopyAttachment(
            pixelBuffer,
            kCVImageBufferAlphaChannelIsOpaque,
            nil
        ) as? Bool, opaque {
            return .color(.resolved(.opaque))
        }
        if let mode = CVBufferCopyAttachment(
            pixelBuffer,
            kCVImageBufferAlphaChannelModeKey,
            nil
        ) as? String,
           mode == kCVImageBufferAlphaChannelMode_PremultipliedAlpha
                as String {
            return .color(.resolved(.premultipliedAlpha))
        }
        return .color(.unresolved)
    }

    func pause(sceneTime: TimeInterval, hostTime: TimeInterval) {
        player.pause()
        guard hasStarted else { return }
        lifecycle.suspend(sceneTime: sceneTime, hostTime: hostTime)
        markPlayerAnchorRequired()
    }

    func resume(sceneTime: TimeInterval, hostTime: TimeInterval) {
        guard hasStarted else { return }
        lifecycle.resumeSuspension(sceneTime: sceneTime, hostTime: hostTime)
        markPlayerAnchorRequired()
    }

    func rebuild(sceneTime: TimeInterval, hostTime: TimeInterval) {
        player.pause()
        guard hasStarted else { return }
        lifecycle.rebuild(sceneTime: sceneTime, hostTime: hostTime)
        markPlayerAnchorRequired()
    }

    func stop() {
        guard lifecycle.stop() else { return }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentCVMetalTexture = nil
        lastFrame = nil
        CVMetalTextureCacheFlush(textureCache, 0)
        try? FileManager.default.removeItem(at: temporaryFileURL)
    }

    private func markPlayerAnchorRequired() {
        player.pause()
        needsPlayerAnchor = true
        playbackBarrier &+= 1
    }

    private func boundedItemTime(_ itemTime: TimeInterval) -> CMTime {
        let duration = self.duration
        let seconds: TimeInterval
        if duration.isFinite, duration > 0 {
            seconds = lifecycle.loop
                ? max(0, itemTime).truncatingRemainder(dividingBy: duration)
                : min(max(0, itemTime), duration)
        } else {
            seconds = max(0, itemTime)
        }
        let timescale = item.duration.timescale > 0
            ? item.duration.timescale
            : CMTimeScale(600)
        return CMTime(seconds: seconds, preferredTimescale: timescale)
    }

    private var duration: TimeInterval {
        let value = CMTimeGetSeconds(item.duration)
        return value.isFinite && value > 0 ? value : 0
    }

    private func boundedCurrentTime(
        _ value: TimeInterval,
        duration: TimeInterval
    ) -> TimeInterval {
        guard duration > 0 else { return max(0, value) }
        return lifecycle.loop
            ? max(0, value).truncatingRemainder(dividingBy: duration)
            : min(max(0, value), duration)
    }

    private func hostTime(_ hostTime: TimeInterval) -> CMTime {
        CMTime(seconds: hostTime, preferredTimescale: 1_000_000)
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
