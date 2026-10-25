import AVFoundation
import Foundation

/// The single product owner for admitted authored Sound layer playback.
/// Visual surfaces and the compositor never depend on this registry: a decode
/// or playback failure is contained to the corresponding Sound layer.
final class SceneSoundPlaybackRegistry {
    enum CommandFailure: Error, Equatable {
        case commandBudgetExceeded
        case unavailableLayer(Int)
        case invalidCommand(Int)
    }

    private final class Source {
        let binding: SceneSoundPlaybackProgram.Binding
        private let epoch: UInt64
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private var currentItemObservation: NSKeyValueObservation?
        private var itemStatusObservation: NSKeyValueObservation?
        private var timeControlObservation: NSKeyValueObservation?
        private var endObservation: NSObjectProtocol?
        private var managedItem: AVPlayerItem?
        private var itemGeneration: UInt64 = 0
        private var currentResource: SceneSoundPlaybackProgram.Resource
        private var remainingGap: Double?
        private var gapNeedsAnchor = false
        private var lastSceneTime: Double?
        private var randomFailed = false
        private var stopped = false
        private var wantsPlayback: Bool
        private var hostPaused = true
        private var baseVolume: Double
        private var masterVolume = 1.0
        private var isMuted = false
#if DEBUG
        private static let capturesEvidence = ProcessInfo.processInfo.arguments
            .contains("--mwx-debug-scene-root")
        private var volumeEvidenceCount = 0
        private var clockEvidenceCount = 0
#endif
        init(binding: SceneSoundPlaybackProgram.Binding, epoch: UInt64) {
            self.binding = binding
            self.epoch = epoch
            wantsPlayback = !binding.startsSilent
            baseVolume = binding.authoredVolume
            currentResource = binding.resources[0] // Program admits only nonempty resources.
            player.automaticallyWaitsToMinimizeStalling = false
            player.volume = Float(binding.authoredVolume)
            if binding.playbackMode == .loop {
                if let item = makeItem() {
                    looper = AVPlayerLooper(player: player, templateItem: item)
                } else {
                    rejectUnavailableResource()
                }
                currentItemObservation = player.observe(\.currentItem, options: [.initial, .new]) {
                    [weak self] _, change in
                    let item = change.newValue ?? nil
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.stopped, self.epoch == epoch,
                              let item, self.player.currentItem === item else { return }
                        self.observeStatus(of: item)
                    }
                }
            } else {
                replaceItem()
            }
            timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) {
                [weak self] _, change in
                guard change.newValue == .playing else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.stopped, self.epoch == epoch,
                          self.player.timeControlStatus == .playing else { return }
#if DEBUG
                          NSLog(
                        "MWX Scene sound: layer=%d epoch=%llu phase=playing source=%@ volume=%.6f",
                        binding.layerID, epoch, self.currentResource.displayPath, self.player.volume
                    )
#endif
                }
            }
        }

        func start(paused: Bool) {
            guard !stopped else { return }
            hostPaused = paused
            reconcilePlayback()
        }

        func pause() {
            guard !stopped else { return }
            hostPaused = true
            player.pause()
        }

        func resume() {
            guard !stopped else { return }
            hostPaused = false
            reconcilePlayback()
        }

        var isPlaying: Bool {
            guard !stopped, wantsPlayback, !hostPaused else { return false }
            if case .random = binding.playbackMode {
                // Random's query describes the armed schedule, including its
                // quiet interval; it is not an AVPlayer rate observation.
                return !randomFailed && (player.currentItem != nil || remainingGap != nil)
            }
            return player.currentItem != nil && player.rate > 0
        }

        func play() {
            guard !stopped else { return }
            if case .random = binding.playbackMode, wantsPlayback { return }
            // Single repeats restart; author pause resumes. Host suspension
            // does not erase that author state.
            if binding.playbackMode == .single, wantsPlayback, player.currentItem != nil {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            wantsPlayback = true
            randomFailed = false
            if binding.playbackMode != .loop, player.currentItem == nil {
                replaceItem()
            }
            reconcilePlayback()
#if DEBUG
            scheduleClockObservation()
#endif
        }

        func pausePlayback() {
            guard !stopped else { return }
            wantsPlayback = false
            player.pause()
        }

        func stopPlayback() {
            pausePlayback()
            remainingGap = nil
            gapNeedsAnchor = false
            guard !stopped else { return }
            if case .random = binding.playbackMode {
                // Retire this item as well as its pending wait. A completion
                // already queued by AVFoundation cannot arm a stopped run or
                // a later explicit play of the same layer.
                itemGeneration &+= 1
                itemStatusObservation?.invalidate()
                if let endObservation { NotificationCenter.default.removeObserver(endObservation) }
                endObservation = nil
                managedItem = nil
                player.removeAllItems()
            } else if player.currentItem != nil {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }

        /// SceneClock is advanced once by the session. No media timer or
        /// per-surface clock runs here, and a delayed frame never catches up
        /// by decoding several missed sounds.
        func advance(sceneTime: Double) {
            guard !stopped, case .random = binding.playbackMode,
                  sceneTime.isFinite else { return }
            let previous = lastSceneTime
            lastSceneTime = sceneTime
            guard case .random = binding.playbackMode,
                  wantsPlayback, !hostPaused, !randomFailed,
                  let remaining = remainingGap else { return }
            guard !gapNeedsAnchor, let previous, sceneTime >= previous else {
                gapNeedsAnchor = false
                return
            }
            guard sceneTime > previous else { return }
            let next = remaining - (sceneTime - previous)
            if next > 0 {
                remainingGap = next
            } else {
                remainingGap = nil
                replaceItem()
                reconcilePlayback()
            }
        }

        private func replaceItem() {
            if case .random = binding.playbackMode {
                currentResource = binding.resources.randomElement()!
            }
            itemStatusObservation?.invalidate()
            if let endObservation { NotificationCenter.default.removeObserver(endObservation) }
            endObservation = nil
            managedItem = nil
            itemGeneration &+= 1
            player.pause()
            player.removeAllItems()
            guard let item = makeItem() else {
                rejectUnavailableResource()
                return
            }
            observeStatus(of: item)
            player.insert(item, after: nil)
            if case .random = binding.playbackMode {
                let generation = itemGeneration
                let epoch = epoch
                endObservation = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
                ) { [weak self, weak item] _ in
                    guard let self, let item, !self.stopped, self.epoch == epoch,
                          self.itemGeneration == generation, self.managedItem === item,
                          !self.randomFailed else { return }
                    // A gap retained across author pause/play is independent
                    // of the temporary resumed item. Do not overwrite it.
                    if self.remainingGap == nil,
                       case let .random(minimum, maximum) = self.binding.playbackMode {
                        self.remainingGap = Double.random(in: minimum ... maximum)
                        self.gapNeedsAnchor = true
                    }
                }
            }
        }

        /// AVPlayerLooper's items share the template asset. Pin the private
        /// file to that actual AV consumer rather than to Registry retirement.
        private func makeItem() -> AVPlayerItem? {
            guard let file = currentResource.file else { return nil }
            let asset = AVURLAsset(url: file.url)
            file.retainForLifetime(of: asset)
            return AVPlayerItem(asset: asset)
        }

        private func rejectUnavailableResource() {
            if case .random = binding.playbackMode {
                randomFailed = true
                wantsPlayback = false
                remainingGap = nil
            }
#if DEBUG
            NSLog("MWX Scene sound: layer=%d epoch=%llu phase=failed source=%@ reason=resource-unavailable",
                  binding.layerID, epoch, currentResource.displayPath)
#endif
        }

        private func reconcilePlayback() {
            if wantsPlayback, !hostPaused, player.currentItem != nil, !randomFailed {
                if player.rate != 1 { player.playImmediately(atRate: 1) }
            } else {
                player.pause()
            }
        }

        func apply(volume: Double) {
            guard !stopped, volume.isFinite, (0 ... 1).contains(volume),
                  baseVolume != volume else { return }
            baseVolume = volume
            applyEffectiveVolume()
        }

        func setMuted(_ muted: Bool) {
            guard !stopped, isMuted != muted else { return }
            isMuted = muted
            applyEffectiveVolume()
        }

        func setMasterVolume(_ volume: Double) {
            guard !stopped, volume.isFinite, (0 ... 1).contains(volume),
                  masterVolume != volume else { return }
            masterVolume = volume
            applyEffectiveVolume()
        }

        /// Master gain and mute never replace authored/user gain or intent.
        private func applyEffectiveVolume() {
            let effective = isMuted ? 0 : baseVolume * masterVolume
            let previous = player.volume
            let next = Float(effective)
            guard previous.bitPattern != next.bitPattern else { return }
            player.volume = next
#if DEBUG
            guard Self.capturesEvidence, volumeEvidenceCount < 16 else { return }
            volumeEvidenceCount += 1
            NSLog(
                "MWX Scene sound: layer=%d phase=volume source=%@ previous=%.6f current=%.6f muted=%@",
                binding.layerID, currentResource.displayPath, previous, effective,
                isMuted ? "true" : "false"
            )
#endif
        }

        func stop() {
            guard !stopped else { return }
            stopped = true
            wantsPlayback = false
            remainingGap = nil
            itemGeneration &+= 1
            itemStatusObservation?.invalidate()
            currentItemObservation?.invalidate()
            timeControlObservation?.invalidate()
            if let endObservation { NotificationCenter.default.removeObserver(endObservation) }
            endObservation = nil
            managedItem = nil
            looper?.disableLooping()
            player.pause()
            player.removeAllItems()
#if DEBUG
            NSLog("MWX Scene sound: layer=%d phase=stopped source=%@",
                  binding.layerID, currentResource.displayPath)
#endif
        }

        private func observeStatus(of item: AVPlayerItem) {
            itemStatusObservation?.invalidate()
            managedItem = item
            itemGeneration &+= 1
            let generation = itemGeneration
            let epoch = epoch
            itemStatusObservation = item.observe(\.status, options: [.initial, .new]) {
                [weak self] item, _ in
                DispatchQueue.main.async { [weak self, weak item] in
                    guard let self, let item, !self.stopped, self.epoch == epoch,
                          self.itemGeneration == generation, self.managedItem === item else { return }
                    switch item.status {
                    case .readyToPlay:
                        self.reconcilePlayback()
#if DEBUG
                        NSLog(
                            "MWX Scene sound: layer=%d epoch=%llu phase=ready source=%@ rate=%.3f",
                            self.binding.layerID, epoch, self.currentResource.displayPath, self.player.rate
                        )
                        self.scheduleClockObservation()
#endif
                    case .failed:
                        if case .random = self.binding.playbackMode {
                            self.randomFailed = true
                            self.wantsPlayback = false
                            self.remainingGap = nil
                            self.player.pause()
                            self.player.removeAllItems()
                        }
#if DEBUG
                        NSLog(
                            "MWX Scene sound: layer=%d epoch=%llu phase=failed source=%@ reason=%@",
                            self.binding.layerID, epoch, self.currentResource.displayPath,
                            item.error?.localizedDescription ?? "unknown"
                        )
#endif
                    case .unknown: break
                    @unknown default: break
                    }
                }
            }
        }
#if DEBUG
        private func scheduleClockObservation() {
            guard Self.capturesEvidence, clockEvidenceCount < 16 else { return }
            clockEvidenceCount += 1
            let initialTime = CMTimeGetSeconds(player.currentTime())
            let generation = itemGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, !self.stopped, self.itemGeneration == generation else { return }
                let currentTime = CMTimeGetSeconds(self.player.currentTime())
                let advanced = initialTime.isFinite && currentTime.isFinite
                    && currentTime > initialTime + 0.1
                NSLog(
                    "MWX Scene sound: layer=%d epoch=%llu phase=clock source=%@ initial=%.6f current=%.6f advanced=%@ rate=%.3f status=%d",
                    self.binding.layerID, self.epoch, self.currentResource.displayPath,
                    initialTime, currentTime, advanced ? "true" : "false",
                    self.player.rate, self.player.timeControlStatus.rawValue
                )
            }
        }
#endif
        deinit { stop() }
    }


    private let epoch: UInt64
    private let program: SceneSoundPlaybackProgram
    private var sources: [Int: Source] = [:]
    private var isMuted = false
    private var masterVolume: Double = 1.0
    private var stopped = false

    init(program: SceneSoundPlaybackProgram, epoch: UInt64) {
        self.program = program
        self.epoch = epoch
    }

    func start(paused: Bool, userValues: [SceneDynamicTarget: SceneDynamicValue]) {
        guard !stopped, sources.isEmpty else { return }
        for binding in program.bindings {
            let source = Source(binding: binding, epoch: epoch)
            if let volume = volume(for: binding, userValues: userValues) {
                source.apply(volume: volume)
            }
            if isMuted {
                source.setMuted(true)
            }
            source.setMasterVolume(masterVolume)
            sources[binding.layerID] = source
            source.start(paused: paused)
        }
#if DEBUG
        NSLog(
            "MWX Scene sound: epoch=%llu phase=started admitted=%d rejected=%d"
                + " skipped=%d paused=%@",
            epoch, program.bindings.count, program.layerRejectionCount,
            program.skippedSourceCount, paused ? "true" : "false"
        )
#endif
    }

    func canApply(userValues: [SceneDynamicTarget: SceneDynamicValue]) -> Bool {
        program.bindings.allSatisfy { binding in
            guard binding.volumePropertyKey != nil else { return true }
            guard case let .scalar(value)? = userValues[binding.volumeTarget] else {
                return false
            }
            return value.isFinite && (0 ... 1).contains(value)
        }
    }

    func apply(userValues: [SceneDynamicTarget: SceneDynamicValue]) {
        for binding in program.bindings where binding.volumePropertyKey != nil
            && !program.scriptVolumeTargets.contains(binding.volumeTarget) {
            guard let source = sources[binding.layerID],
                  let volume = volume(for: binding, userValues: userValues) else { continue }
            source.apply(volume: volume)
        }
    }

    /// Scalar-script outputs have a disjoint target set from the immediate
    /// property lane above. A missing snapshot entry never resets a source.
    func apply(snapshot: SceneDynamicSnapshot, excludingLayerIDs: Set<Int> = []) {
        for binding in program.bindings where binding.volumePropertyKey == nil
            || program.scriptVolumeTargets.contains(binding.volumeTarget) {
            guard !excludingLayerIDs.contains(binding.layerID),
                  let source = sources[binding.layerID],
                  case let .scalar(volume)? = snapshot[binding.volumeTarget]?.value
            else { continue }
            source.apply(volume: volume)
        }
    }

    func pause() {
        sources.values.forEach { $0.pause() }
    }

    func resume() {
        sources.values.forEach { $0.resume() }
    }

    /// The session calls this once before publishing all surfaces' VM input.
    func advance(sceneTime: Double) {
        sources.values.forEach { $0.advance(sceneTime: sceneTime) }
    }

    func sceneScriptSnapshots() -> [Int: Bool] {
        sources.mapValues(\.isPlaying)
    }

    func validate(
        _ commands: [SceneScriptMediaPlaybackCommand]
    ) -> Result<Void, CommandFailure> {
        guard commands.count <= 64 else { return .failure(.commandBudgetExceeded) }
        for (index, command) in commands.enumerated() {
            guard !stopped, sources[command.layerID] != nil else {
                return .failure(.unavailableLayer(command.layerID))
            }
            guard command.destination == .soundLayer else { return .failure(.invalidCommand(index)) }
            switch command.action {
            case .play, .pause, .stop: break
            case .setCurrentTime, .setRate, .setLoop: return .failure(.invalidCommand(index))
            }
        }
        return .success(())
    }

    func apply(
        _ commands: [SceneScriptMediaPlaybackCommand]
    ) -> Result<Void, CommandFailure> {
        switch validate(commands) {
        case let .failure(failure): return .failure(failure)
        case .success: break
        }
        for command in commands {
            guard let source = sources[command.layerID] else { continue }
            switch command.action {
            case .play: source.play()
            case .pause: source.pausePlayback()
            case .stop: source.stopPlayback()
            case .setCurrentTime, .setRate, .setLoop: break // Rejected above, before any action.
            }
        }
        return .success(())
    }

    /// 静音门（M0.2）：作用于全部已存在的 Sound 层；随后新建的
    /// 层经 start() 继承当前静音态。
    func setMuted(_ muted: Bool) {
        guard isMuted != muted else { return }
        isMuted = muted
        sources.values.forEach { $0.setMuted(muted) }
    }

    /// Applies the cross-engine master gain after authored/user layer volume.
    func setMasterVolume(_ volume: Double) {
        guard volume.isFinite, (0 ... 1).contains(volume),
              masterVolume != volume else { return }
        masterVolume = volume
        sources.values.forEach { $0.setMasterVolume(volume) }
    }

    func retire(layerIDs: Set<Int>) {
        for layerID in layerIDs {
            sources.removeValue(forKey: layerID)?.stop()
        }
    }

    func stop() {
        stopped = true
        sources.values.forEach { $0.stop() }
        sources.removeAll()
    }

    private func volume(
        for binding: SceneSoundPlaybackProgram.Binding,
        userValues: [SceneDynamicTarget: SceneDynamicValue]
    ) -> Double? {
        guard binding.volumePropertyKey != nil,
              case let .scalar(value)? = userValues[binding.volumeTarget],
              value.isFinite,
              (0 ... 1).contains(value) else {
            return binding.authoredVolume
        }
        return value
    }

    deinit {
        stop()
    }
}
