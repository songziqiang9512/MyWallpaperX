import AVFoundation
import CoreVideo
import Metal

final class SceneVideoTextureSource {
    struct Frame {
        let texture: MTLTexture
        let content: SceneTextureContent
        let contentGeneration: UInt64
        let requestedItemTime: TimeInterval
        let decodedItemTime: TimeInterval?
        let epoch: UInt64
        let owner: SceneVideoTexturePlaybackOwner
        let sourceIncarnation: UUID

        var publication: SceneTextureProviderPublication? {
            guard let layerID = owner.layerID else { return nil }
            return publication(request: .layerSource(layerID), provider: .video(
                layerID: layerID, lifecycleEpoch: epoch
            ), authoredFormat: nil)
        }

        func assetPublication(
            for asset: SceneAssetTextureIdentity
        ) -> SceneTextureProviderPublication? {
            guard owner == .asset, asset.purpose == .premultipliedColor else { return nil }
            return publication(request: .asset(asset), provider: .videoAsset(
                asset: asset, sourceIncarnation: sourceIncarnation,
                lifecycleEpoch: epoch
            ), authoredFormat: .rgba8888)
        }

        func userPropertyPublication(
            for property: SceneUserPropertyTextureIdentity
        ) -> SceneTextureProviderPublication? {
            guard owner == .userProperty(property),
                  property.purpose == .premultipliedColor else { return nil }
            return publication(request: .materialUserProperty(property), provider: .videoUserProperty(
                property: property, sourceIncarnation: sourceIncarnation,
                lifecycleEpoch: epoch
            ), authoredFormat: nil)
        }

        private func publication(
            request: SceneFrameTextureIdentity,
            provider: SceneTextureProviderIdentity,
            authoredFormat: SceneShaderTextureFormat?
        ) -> SceneTextureProviderPublication {
            let size = CGSize(width: texture.width, height: texture.height)
            return SceneTextureProviderPublication(
                requestIdentity: request,
                candidate: SceneTextureCandidate(
                    texture: texture,
                    identity: .provider(provider),
                    generation: .provider(contentGeneration: contentGeneration),
                    purpose: .premultipliedColor,
                    content: content,
                    physicalSize: size,
                    mappedSize: size,
                    uvTransform: .identity,
                    sampling: .linearClamp,
                    authoredFormat: authoredFormat
                ),
                contentGeneration: contentGeneration
            )
        }
    }

    private let player: AVPlayer
    private var item: AVPlayerItem?
    private let videoOutput: AVPlayerItemVideoOutput
    private let textureCache: CVMetalTextureCache
    private var ownedFile: SceneVideoOwnedFile?
    let owner: SceneVideoTexturePlaybackOwner
    private let sourceIncarnation = UUID()
    private let capturesLifecycleObservations: Bool
    private var endObserver: NSObjectProtocol?
    private var payloadPreparation: Task<Void, Error>?
    private var payloadPreparationID: UUID?
    private var payloadPreparationFailed = false
    private var lifecycle = SceneVideoProviderLifecycleState(epoch: 0)
    private var lastFrame: Frame?
    private var pendingFrame: Frame?
    private var pendingFrameIndex: UInt64?
    private struct DecodedFrame {
        let texture: MTLTexture
        let content: SceneTextureContent
        let requestedItemTime: TimeInterval
        let decodedItemTime: TimeInterval?
    }
    private var primedFrame: DecodedFrame?
    private var decodedFrameCandidate: DecodedFrame?
    private var primeOperationID: UUID?
    private var primeSeekResult: Bool?
    private var primePrerollResult: Bool?
    private struct InitialPreparationSnapshot {
        let lifecycle: SceneVideoProviderLifecycleState
        let endedGeneration: UInt64
        let itemTime: TimeInterval
    }
    private var pendingInitialPreparation: InitialPreparationSnapshot?
    private var hasStarted = false
    private var needsPlayerAnchor = true
    // Backend positioning outlives a rejected frame. The Scene clock and
    // publication still belong to lifecycle and the host commit barrier.
    private enum PlayerPositionState {
        case unchanged
        case required(TimeInterval?)
        case pending(UUID, AVPlayerItem, CMTime, TimeInterval?)
        case ready(AVPlayerItem, CMTime)
    }
    private var playerPositionState: PlayerPositionState = .unchanged
    private var playerEventState = SceneVideoPlayerEventState()
    private var endedGeneration: UInt64 = 0

    convenience init?(
        layerID: Int,
        mp4PayloadData: Data,
        isWebM: Bool = false,
        cacheDirectory: URL,
        device: MTLDevice,
        capturesLifecycleObservations: Bool = false
    ) {
        self.init(owner: .layer(layerID), mp4PayloadData: mp4PayloadData,
            isWebM: isWebM, cacheDirectory: cacheDirectory, device: device,
            capturesLifecycleObservations: capturesLifecycleObservations)
    }

    convenience init?(
        owner: SceneVideoTexturePlaybackOwner,
        mp4PayloadData: Data,
        isWebM: Bool = false,
        cacheDirectory: URL,
        device: MTLDevice,
        capturesLifecycleObservations: Bool = false,
        onWebMPrepared: (@Sendable (SceneVideoOwnedFile.Writer) throws -> Void)? = nil
    ) {
        let file: SceneVideoOwnedFile
        let writer: SceneVideoOwnedFile.Writer?
        do {
            if isWebM {
                let output = try SceneVideoOwnedFile.makeWriter(cacheDirectory: cacheDirectory)
                file = output.file
                writer = output
            } else {
                file = try SceneVideoOwnedFile.snapshot(payload: mp4PayloadData,
                    cacheDirectory: cacheDirectory)
                writer = nil
            }
        } catch {
            return nil
        }
        self.init(owner: owner, fileLease: file, installPreparedItem: !isWebM,
            device: device, capturesLifecycleObservations: capturesLifecycleObservations)
        if let writer {
            prepareWebMPayload(mp4PayloadData, output: writer, onPrepared: onWebMPrepared)
        }
    }

    convenience init?(
        owner: SceneVideoTexturePlaybackOwner,
        preparedFile: SceneVideoOwnedFile,
        device: MTLDevice,
        capturesLifecycleObservations: Bool = false
    ) {
        self.init(owner: owner, fileLease: preparedFile, installPreparedItem: true,
            device: device, capturesLifecycleObservations: capturesLifecycleObservations)
    }

    private init?(
        owner: SceneVideoTexturePlaybackOwner,
        fileLease: SceneVideoOwnedFile,
        installPreparedItem: Bool,
        device: MTLDevice,
        capturesLifecycleObservations: Bool
    ) {
        self.owner = owner
        self.ownedFile = fileLease
        self.capturesLifecycleObservations = capturesLifecycleObservations
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

        let output = AVPlayerItemVideoOutput(
            pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )
        output.suppressesPlayerRendering = true
        videoOutput = output

        SceneVideoPayloadPreparation.registerDecoders()
        player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .pause
        player.isMuted = true
        player.volume = 0

        if installPreparedItem { installItem(at: fileLease.url) }
    }

    private func prepareWebMPayload(
        _ data: Data, output: SceneVideoOwnedFile.Writer,
        onPrepared: (@Sendable (SceneVideoOwnedFile.Writer) throws -> Void)?
    ) {
        let file = output.file
        let preparationID = UUID()
        payloadPreparationID = preparationID
        let worker = Task.detached(priority: .utility) {
            // Cancellation is cooperative. Keep the destination lease until
            // the actual writer exits, even after Source.stop releases it.
            defer { withExtendedLifetime(file) {} }
            try await SceneVideoPayloadPreparation.writeWebM(data, to: output)
            try Task.checkCancellation()
            try onPrepared?(output)
        }
        payloadPreparation = worker
        Task { [weak self] in
            defer { withExtendedLifetime(file) {} }
            let result = await worker.result
            guard let self, self.payloadPreparationID == preparationID else { return }
            self.payloadPreparation = nil
            self.payloadPreparationID = nil
            switch result {
            case .success:
                self.installItem(at: file.url)
            case let .failure(error):
                self.payloadPreparationFailed = true
#if DEBUG
                NSLog("MWX video preparation failed: owner=%@ error=%@",
                    String(describing: self.owner), String(describing: error))
#endif
            }
        }
    }

    private func installItem(at fileURL: URL) {
        payloadPreparationFailed = false
        let item = AVPlayerItem(url: fileURL)
        item.add(videoOutput)
        self.item = item
        player.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let observedItemTime = CMTimeGetSeconds(player.currentTime())
            let itemDuration = duration
            guard lifecycle.isAdvancingPlayback,
                  playerEventState.acceptsEndEvent(
                      observedItemTime: observedItemTime,
                      duration: itemDuration,
                      tolerance: endEventTolerance
                  ) else {
                logEndEvent(
                    disposition: "ignored-stale",
                    observedItemTime: observedItemTime,
                    duration: itemDuration
                )
                return
            }
            logEndEvent(
                disposition: "accepted",
                observedItemTime: observedItemTime,
                duration: itemDuration
            )
            endedGeneration &+= 1
            lifecycle.didReachEnd(duration: itemDuration)
            requestPlayerPosition()
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

    /// Qualifies an unregistered property source with the same decoder used
    /// after adoption. The imported seed is not a lifecycle publication.
    func primeInitialFrame(isCancelled: @escaping () -> Bool = { false }) async -> Bool {
        guard !hasStarted, ownedFile != nil, primeOperationID == nil,
              case let .userProperty(property) = owner,
              property.purpose == .premultipliedColor,
              !isCancelled(), !Task.isCancelled else { return false }
        if primedFrame != nil { return hasCompletePrimedPublication(for: property) }
        let operationID = UUID()
        primeOperationID = operationID
        primeSeekResult = nil
        primePrerollResult = nil
        let deadline = ContinuousClock().now.advanced(by: .seconds(10))
        defer {
            if primeOperationID == operationID {
                primeOperationID = nil
                primeSeekResult = nil
                primePrerollResult = nil
                player.pause()
                player.cancelPendingPrerolls()
                item?.cancelPendingSeeks()
            }
        }
        guard await waitForPrime(operationID, until: deadline, isCancelled: isCancelled, condition: {
            self.item?.status == .readyToPlay || self.item?.status == .failed
        }), let expectedItem = item, expectedItem.status == .readyToPlay else { return false }
        player.pause()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, self.primeOperationID == operationID,
                      self.item === expectedItem else { return }
                self.primeSeekResult = finished
            }
        }
        guard await waitForPrime(operationID, until: deadline, isCancelled: isCancelled,
            condition: { self.primeSeekResult != nil }), primeSeekResult == true else { return false }
        player.preroll(atRate: 1) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, self.primeOperationID == operationID,
                      self.item === expectedItem else { return }
                self.primePrerollResult = finished
            }
        }
        guard await waitForPrime(operationID, until: deadline, isCancelled: isCancelled,
            condition: { self.primePrerollResult != nil }), primePrerollResult == true,
              await waitForPrime(operationID, until: deadline, isCancelled: isCancelled,
                condition: { self.videoOutput.hasNewPixelBuffer(forItemTime: .zero) }) else { return false }
        var displayTime = CMTime.invalid
        guard let buffer = videoOutput.copyPixelBuffer(forItemTime: .zero, itemTimeForDisplay: &displayTime),
              let texture = makeTexture(from: buffer),
              primeOperationID == operationID, !isCancelled(), !Task.isCancelled else { return false }
        primedFrame = DecodedFrame(texture: texture, content: resolvedColorContent(for: buffer),
            requestedItemTime: 0,
            decodedItemTime: displayTime.isNumeric ? CMTimeGetSeconds(displayTime) : nil)
        guard hasCompletePrimedPublication(for: property) else {
            primedFrame = nil
            return false
        }
        return true
    }

    private func waitForPrime(
        _ operationID: UUID, until deadline: ContinuousClock.Instant,
        isCancelled: () -> Bool, condition: () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        while clock.now < deadline {
            guard primeOperationID == operationID, ownedFile != nil,
                  !hasStarted, !isCancelled(), !Task.isCancelled else { return false }
            if condition() { return true }
            do { try await Task.sleep(for: .milliseconds(5)) }
            catch { return false }
        }
        return false
    }

    func hasCompletePrimedPublication(for property: SceneUserPropertyTextureIdentity) -> Bool {
        guard lifecycle.contentGeneration == 0, let primedFrame,
              let publication = makeFrame(from: primedFrame, epoch: lifecycle.epoch)
                .userPropertyPublication(for: property) else { return false }
        return publication.isComplete && publication.generationIsCurrent
    }

    /// Registry calls this once in its synchronous adoption transaction.
    /// Only the SceneClock anchor and pause policy change; the seed stays
    /// uncommitted until the first ordinary prepare/commit pair.
    func activatePrimed(
        sceneTime: TimeInterval, hostTime: TimeInterval, isPaused: Bool
    ) -> Bool {
        guard !hasStarted, primeOperationID == nil,
              case let .userProperty(property) = owner,
              hasCompletePrimedPublication(for: property) else { return false }
        lifecycle.start(sceneTime: sceneTime, hostTime: hostTime)
        if isPaused {
            lifecycle.suspend(sceneTime: sceneTime, hostTime: hostTime)
        } else {
            lifecycle.resumeSuspension(sceneTime: sceneTime, hostTime: hostTime)
        }
        hasStarted = true
        markPlayerAnchorRequired()
        return true
    }

    private func makeFrame(from decoded: DecodedFrame, epoch: UInt64) -> Frame {
        Frame(texture: decoded.texture, content: decoded.content,
            contentGeneration: lifecycle.contentGeneration &+ 1,
            requestedItemTime: decoded.requestedItemTime,
            decodedItemTime: decoded.decodedItemTime, epoch: epoch,
            owner: owner, sourceIncarnation: sourceIncarnation)
    }

    func currentFrame(for timing: SceneFrameTiming) -> Frame? {
        guard let frame = prepareFrame(for: timing) else { return lastFrame }
        commitPreparedFrame()
        return frame
    }

    /// Observes the frame already prepared by the original transaction. An
    /// unknown item, positioning wait or absent copied buffer remains pending.
    /// A usable last-ready frame still satisfies this ordinary consumer.
    func initialFrameReadiness(preparedFrame: Frame?) -> SceneOrdinaryVideoFrameReadiness {
        if preparedFrame?.publication != nil { return .ready }
        return payloadPreparationFailed || item?.status == .failed ? .unavailable : .pending
    }

    /// Builds a frame candidate without advancing the provider publication.
    /// The host commits it only after the surface submission barrier accepts
    /// the frame, so a drawable miss or graph rejection cannot consume video
    /// content generation or replace the last-ready frame.
    func prepareFrame(for timing: SceneFrameTiming) -> Frame? {
        if pendingFrameIndex == timing.frameIndex,
           lifecycle.hasPlannedFrame(frameIndex: timing.frameIndex) {
            return pendingFrame ?? lastFrame
        }
        pendingFrame = nil
        pendingFrameIndex = nil
        pendingInitialPreparation = nil
        if !hasStarted {
            pendingInitialPreparation = .init(lifecycle: lifecycle,
                endedGeneration: endedGeneration,
                itemTime: lifecycle.currentTime(at: timing.sceneTime))
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
        // Keep even a last-ready fallback behind the host's submission
        // barrier. If another surface rejects this frame, the lifecycle plan
        // must be discarded so the same frame index can retry decoding after
        // AVPlayer publishes a buffer.
        pendingFrameIndex = timing.frameIndex
        guard plan.shouldDecode else {
            decodedFrameCandidate = nil
            return lastFrame
        }
        if let primedFrame, lifecycle.contentGeneration == 0 {
            let frame = makeFrame(from: primedFrame, epoch: plan.epoch)
            pendingFrame = frame
            return frame
        }
        // An EOF may arrive after preparation but before a rejected frame is
        // retried. Its old Scene time can precede the new loop's zero point.
        // Keep the previous texture until that point instead of scheduling
        // item zero against an earlier host time and shifting playback ahead.
        guard plan.itemTime >= 0 else { return lastFrame }
        guard item?.status == .readyToPlay else {
            markPlayerAnchorRequired()
            return lastFrame
        }

        let itemTime = boundedItemTime(plan.itemTime)
        guard preparePlayerPosition(for: itemTime) else { return lastFrame }
        if lifecycle.isAdvancingPlayback && (needsPlayerAnchor || player.rate == 0) {
            player.setRate(
                Float(lifecycle.rate),
                time: itemTime,
                atHostTime: hostTime(plan.hostTime)
            )
            needsPlayerAnchor = player.rate == 0
            if !needsPlayerAnchor {
                playerEventState.didAnchorPlayback()
                // Once playback leaves the positioned target, a later same-
                // value seek must qualify again, even if this frame is rejected.
                if case .ready = playerPositionState { playerPositionState = .unchanged }
            }
        }
        if lifecycle.isAdvancingPlayback && player.rate == 0 {
            needsPlayerAnchor = true
            return lastFrame
        }
        // Acquisition cannot be rolled back with a surface. Reuse this one
        // unpublished payload for the exact target, rebuilding only its typed
        // publication under the current lifecycle epoch/generation.
        if let decodedFrameCandidate,
           decodedFrameCandidate.requestedItemTime == CMTimeGetSeconds(itemTime) {
            let frame = makeFrame(from: decodedFrameCandidate, epoch: plan.epoch)
            pendingFrame = frame
            return frame
        }
        decodedFrameCandidate = nil
        let expectedCommandGeneration = playerEventState.commandGeneration
        guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime) else {
            return lastFrame
        }
        var itemTimeForDisplay = CMTime.invalid
        guard let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: itemTime,
            itemTimeForDisplay: &itemTimeForDisplay
        ),
        expectedCommandGeneration == playerEventState.commandGeneration,
        let texture = makeTexture(from: pixelBuffer) else {
            return lastFrame
        }
        let decoded = DecodedFrame(
            texture: texture,
            content: resolvedColorContent(for: pixelBuffer),
            requestedItemTime: CMTimeGetSeconds(itemTime),
            decodedItemTime: itemTimeForDisplay.isNumeric
                ? CMTimeGetSeconds(itemTimeForDisplay) : nil
        )
        decodedFrameCandidate = decoded
        let frame = makeFrame(from: decoded, epoch: plan.epoch)
        needsPlayerAnchor = false
        if !lifecycle.isAdvancingPlayback { player.pause() }
        pendingFrame = frame
        return frame
    }

    func commitPreparedFrame() {
        guard let frameIndex = pendingFrameIndex else { return }
        defer {
            pendingFrame = nil
            pendingFrameIndex = nil
            pendingInitialPreparation = nil
        }
        guard let pendingFrame else {
            // A successful host submission may have used the previous frame
            // while this provider had no new buffer. The plan was consumed;
            // do not leave same-index deduplication armed for later retries.
            lifecycle.discardPlannedFrame(frameIndex: frameIndex)
            return
        }
        guard lifecycle.didPublish(frameIndex: frameIndex) != nil else {
            lifecycle.discardPlannedFrame(frameIndex: frameIndex)
            return
        }
        lastFrame = pendingFrame
        decodedFrameCandidate = nil
        // Paused positioning stays reusable until its first publication;
        // advancing playback already consumed it when the backend restarted.
        if case .ready = playerPositionState { playerPositionState = .unchanged }
        if primedFrame?.texture === pendingFrame.texture { primedFrame = nil }
        if capturesLifecycleObservations, let layerID = owner.layerID {
#if DEBUG
        NSLog(
                "MWX video frame: schema=video-frame-v1 layer=%d epoch=%llu frame=%llu generation=%llu requested=%.9f decoded=%@",
                layerID, pendingFrame.epoch, frameIndex, pendingFrame.contentGeneration,
                pendingFrame.requestedItemTime,
                pendingFrame.decodedItemTime.map { String(format: "%.9f", $0) } ?? "unavailable"
            )
#endif
        }
#if DEBUG
        if capturesLifecycleObservations, owner == .asset {
            NSLog(
                "MWX video frame: schema=video-frame-v1 owner=asset source=%@ epoch=%llu frame=%llu generation=%llu requested=%.9f decoded=%@ content=%@",
                sourceIncarnation.uuidString, pendingFrame.epoch, frameIndex,
                pendingFrame.contentGeneration, pendingFrame.requestedItemTime,
                pendingFrame.decodedItemTime.map { String(format: "%.9f", $0) } ?? "unavailable",
                String(describing: pendingFrame.content)
            )
        }
#endif
    }


    func discardPreparedFrame() {
        guard let frameIndex = pendingFrameIndex else { return }
        let initial = pendingInitialPreparation
        pendingFrame = nil
        pendingFrameIndex = nil
        pendingInitialPreparation = nil
        lifecycle.discardPlannedFrame(frameIndex: frameIndex)
        // Ordinary presentation failure does not rewind SceneClock or undo
        // a real backend anchor/EOF. Only the first, unsubmitted start has an
        // origin to restore; a confirmed EOF already superseded that origin.
        if let initial, endedGeneration == initial.endedGeneration {
            lifecycle = initial.lifecycle
            hasStarted = false
            requestPlayerPosition(to: initial.itemTime)
            markPlayerAnchorRequired()
        }
    }

    func playbackSnapshot(
        sceneTime: TimeInterval
    ) -> SceneScriptVideoPlaybackSnapshot? {
        guard let layerID = owner.layerID else { return nil }
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

    func canApply(_ command: SceneScriptMediaPlaybackCommand) -> Bool {
        guard command.destination == .videoTexture,
              command.layerID == owner.layerID else { return false }
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
        _ command: SceneScriptMediaPlaybackCommand,
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
            guard !lifecycle.isPlaying else { return }
            lifecycle.resume(
                sceneTime: timing.sceneTime,
                hostTime: timing.hostTime
            )
            markPlayerAnchorRequired()
        case .pause:
            guard lifecycle.isPlaying else { return }
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
            requestPlayerPosition(to: 0)
            markPlayerAnchorRequired()
        case let .setCurrentTime(value):
            lifecycle.seek(
                to: value,
                sceneTime: timing.sceneTime,
                hostTime: timing.hostTime
            )
            requestPlayerPosition(to: value)
            markPlayerAnchorRequired()
        case let .setRate(value):
            guard value != lifecycle.rate else { return }
            lifecycle.setRate(
                value,
                sceneTime: timing.sceneTime,
                hostTime: timing.hostTime
            )
            markPlayerAnchorRequired()
        case let .setLoop(value):
            guard value != lifecycle.loop else { return }
            let currentTime = lifecycle.currentTime(at: timing.sceneTime)
            let previousPosition = boundedItemTime(currentTime)
            lifecycle.setLoop(value)
            if CMTimeCompare(previousPosition, boundedItemTime(currentTime)) != 0 {
                lifecycle.requestFrameRefresh()
                requestPlayerPosition()
            }
            markPlayerAnchorRequired()
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
        lifecycle.suspend(sceneTime: sceneTime, hostTime: hostTime)
        if hasStarted { markPlayerAnchorRequired() }
    }

    func resume(sceneTime: TimeInterval, hostTime: TimeInterval) {
        lifecycle.resumeSuspension(sceneTime: sceneTime, hostTime: hostTime)
        if hasStarted { markPlayerAnchorRequired() }
    }

    func rebuild(sceneTime: TimeInterval, hostTime: TimeInterval) {
        player.pause()
        guard hasStarted else { return }
        lifecycle.rebuild(sceneTime: sceneTime, hostTime: hostTime)
        markPlayerAnchorRequired()
    }

    func stop() {
        guard lifecycle.stop() else { return }
        // Active playback owns the file here. Transfer it to the actual asset
        // before retiring the item, so AV borrowers can outlive this Source.
        if let ownedFile, let item {
            ownedFile.retainForLifetime(of: item.asset)
        }
        primeOperationID = nil
        primeSeekResult = nil
        primePrerollResult = nil
        payloadPreparationID = nil
        payloadPreparation?.cancel()
        payloadPreparation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player.pause()
        playerPositionState = .unchanged
        player.cancelPendingPrerolls()
        item?.cancelPendingSeeks()
        player.replaceCurrentItem(with: nil)
        item = nil
        lastFrame = nil
        pendingFrame = nil
        pendingFrameIndex = nil
        pendingInitialPreparation = nil
        primedFrame = nil
        decodedFrameCandidate = nil
        playerEventState.invalidateAnchor()
        CVMetalTextureCacheFlush(textureCache, 0)
        ownedFile = nil
    }

    private func markPlayerAnchorRequired() {
        player.pause()
        needsPlayerAnchor = true
        playerEventState.invalidateAnchor()
    }

    private func requestPlayerPosition(to target: TimeInterval? = nil) {
        if let target {
            switch playerPositionState {
            case let .pending(_, expectedItem, pendingTarget, _), let .ready(expectedItem, pendingTarget):
                if expectedItem === item, expectedItem === player.currentItem,
                   CMTimeCompare(pendingTarget, boundedItemTime(target)) == 0 { return }
            case .unchanged, .required:
                break
            }
        }
        let wasPending: Bool
        if case .pending = playerPositionState { wasPending = true } else { wasPending = false }
        // Revoke the old operation before cancellation can deliver its callback.
        playerPositionState = .required(target)
        decodedFrameCandidate = nil
        if wasPending { item?.cancelPendingSeeks() }
    }

    /// A timebase anchor does not wait for media at the new position. Hold
    /// last-ready until the one accepted seek completes, then use the latest
    /// Scene plan to anchor playback; callbacks never publish or start it.
    private func preparePlayerPosition(for itemTime: CMTime) -> Bool {
        guard let expectedItem = item, player.currentItem === expectedItem else { return false }
        if !lifecycle.isAdvancingPlayback && needsPlayerAnchor {
            switch playerPositionState {
            case let .pending(_, positionedItem, target, _), let .ready(positionedItem, target):
                if positionedItem !== expectedItem || CMTimeCompare(target, itemTime) != 0 {
                    requestPlayerPosition()
                }
            case .unchanged:
                requestPlayerPosition()
            case .required:
                break
            }
        }
        switch playerPositionState {
        case .unchanged:
            return true
        case let .ready(positionedItem, _):
            guard positionedItem === expectedItem else {
                requestPlayerPosition()
                return false
            }
            if !lifecycle.isAdvancingPlayback { needsPlayerAnchor = false }
            return true
        case .pending:
            return false
        case let .required(rawTarget):
            let target = lifecycle.isAdvancingPlayback
                ? (rawTarget.map(boundedItemTime) ?? itemTime) : itemTime
            let operationID = UUID()
            playerPositionState = .pending(operationID, expectedItem, target, rawTarget)
            player.pause()
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                DispatchQueue.main.async {
                    guard let self,
                          case let .pending(currentID, positionedItem, _, _) = self.playerPositionState,
                          currentID == operationID, positionedItem === expectedItem,
                          self.item === expectedItem, self.player.currentItem === expectedItem else { return }
                    self.playerPositionState = finished
                        ? .ready(expectedItem, target) : .required(rawTarget)
                    // Pause or suspension can have changed the held Scene
                    // position during the seek. The next prepare verifies it.
                    self.needsPlayerAnchor = true
                }
            }
            return false
        }
    }

    private var endEventTolerance: TimeInterval {
        let timescale = item?.duration.timescale ?? 0
        return timescale > 0 ? 1 / Double(timescale) : 1 / 600
    }

    private func logEndEvent(
        disposition: String,
        observedItemTime: TimeInterval,
        duration: TimeInterval
    ) {
        guard capturesLifecycleObservations else { return }
        guard let layerID = owner.layerID else { return }
#if DEBUG
        NSLog(
            "MWX video provider event: schema=video-provider-event-v1 layer=%d event=end disposition=%@ commandGeneration=%llu anchoredGeneration=%@ itemTime=%.6f duration=%.6f",
            layerID,
            disposition,
            playerEventState.commandGeneration,
            playerEventState.anchoredGeneration.map(String.init) ?? "-",
            observedItemTime,
            duration
        )
#endif
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
        let itemTimescale = item?.duration.timescale ?? 0
        let timescale = itemTimescale > 0 ? itemTimescale : CMTimeScale(600)
        return CMTime(seconds: seconds, preferredTimescale: timescale)
    }

    private var duration: TimeInterval {
        let value = CMTimeGetSeconds(item?.duration ?? .invalid)
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

        return SceneResourceAllocation.importVideo(pixelBuffer, cache: textureCache)
    }
}
