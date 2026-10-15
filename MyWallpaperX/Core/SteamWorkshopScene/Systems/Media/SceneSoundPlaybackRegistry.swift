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
        private let looper: AVPlayerLooper?
        private var currentItemObservation: NSKeyValueObservation?
        private var itemStatusObservation: NSKeyValueObservation?
        private var timeControlObservation: NSKeyValueObservation?
        private var stopped = false
        private var wantsPlayback: Bool
        private var hostPaused = true
        private var baseVolume: Double
        private var masterVolume = 1.0
        private var isMuted = false
#if DEBUG
        private static let capturesVolumeEvidence = ProcessInfo.processInfo.arguments
            .contains("--mwx-debug-scene-root")
        private var volumeEvidenceCount = 0
#endif

        init(binding: SceneSoundPlaybackProgram.Binding, epoch: UInt64) {
            self.binding = binding
            self.epoch = epoch
            wantsPlayback = !binding.startsSilent
            baseVolume = binding.authoredVolume
            let item = AVPlayerItem(url: binding.resourceURL)
            // The loop/restart boundary is the only mode branch: `loop`
            // attaches a looper, `single` plays the queued item once to the
            // end and the empty queue stops without any restart.
            if binding.loops {
                looper = AVPlayerLooper(player: player, templateItem: item)
            } else {
                looper = nil
                player.insert(item, after: nil)
            }
            player.automaticallyWaitsToMinimizeStalling = false
            player.volume = Float(binding.authoredVolume)
            currentItemObservation = player.observe(
                \.currentItem,
                options: [.initial, .new]
            ) { [weak self] _, change in
                self?.observeStatus(of: change.newValue ?? nil, epoch: epoch)
            }
            timeControlObservation = player.observe(
                \.timeControlStatus,
                options: [.new]
            ) { [weak self] _, change in
                guard let self,
                      change.newValue == .playing else { return }
                NSLog(
                    "MWX Scene sound: layer=%d epoch=%llu phase=playing source=%@ volume=%.6f",
                    binding.layerID, epoch, binding.displayPath, self.player.volume
                )
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
            !stopped && wantsPlayback && !hostPaused
                && player.currentItem != nil && player.rate > 0
        }

        func play() {
            guard !stopped else { return }
            // Repeating author play on an active single restarts it. Host
            // suspension does not erase that author state; author pause does.
            if !binding.loops, wantsPlayback, player.currentItem != nil {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            wantsPlayback = true
            // Natural single completion empties the queue. Only an explicit
            // author play rebuilds its item; host resume never restarts it.
            if !binding.loops, player.currentItem == nil {
                player.insert(AVPlayerItem(url: binding.resourceURL), after: nil)
            }
            reconcilePlayback()
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--mwx-debug-scene-root") {
                scheduleClockObservation(epoch: epoch)
            }
#endif
        }

        func pausePlayback() {
            guard !stopped else { return }
            wantsPlayback = false
            player.pause()
        }

        func stopPlayback() {
            pausePlayback()
            guard !stopped, player.currentItem != nil else { return }
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        private func reconcilePlayback() {
            if wantsPlayback, !hostPaused, player.currentItem != nil {
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

        /// 静音门作用于最终增益：muted → 0，否则回到基础音量
        /// （作者音量或用户属性覆盖值）。
        private func applyEffectiveVolume() {
            let effective = isMuted ? 0 : baseVolume * masterVolume
            let previous = player.volume
            let next = Float(effective)
            guard previous.bitPattern != next.bitPattern else { return }
            player.volume = next
#if DEBUG
            // Animated gain is ordinary frame work. Export only a bounded
            // diagnostic prefix, with configuration resolved once per process.
            guard Self.capturesVolumeEvidence, volumeEvidenceCount < 16 else { return }
            volumeEvidenceCount += 1
            NSLog(
                "MWX Scene sound: layer=%d phase=volume source=%@ previous=%.6f current=%.6f muted=%@",
                binding.layerID, binding.displayPath, previous, effective,
                isMuted ? "true" : "false"
            )
#endif
        }

        func stop() {
            guard !stopped else { return }
            stopped = true
            wantsPlayback = false
            itemStatusObservation?.invalidate()
            currentItemObservation?.invalidate()
            timeControlObservation?.invalidate()
            looper?.disableLooping()
            player.pause()
            player.removeAllItems()
            NSLog(
                "MWX Scene sound: layer=%d phase=stopped source=%@",
                binding.layerID, binding.displayPath
            )
        }

        private func observeStatus(of item: AVPlayerItem?, epoch: UInt64) {
            itemStatusObservation?.invalidate()
            guard let item else { return }
            itemStatusObservation = item.observe(\.status, options: [.initial, .new]) {
                [weak self] item, _ in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    if !self.stopped, self.wantsPlayback, !self.hostPaused {
                        self.player.playImmediately(atRate: 1)
                    }
                    NSLog(
                        "MWX Scene sound: layer=%d epoch=%llu phase=ready source=%@ rate=%.3f",
                        binding.layerID, epoch, binding.displayPath, self.player.rate
                    )
                    self.scheduleClockObservation(epoch: epoch)
                case .failed:
                    NSLog(
                        "MWX Scene sound: layer=%d epoch=%llu phase=failed source=%@ reason=%@",
                        binding.layerID, epoch, binding.displayPath,
                        item.error?.localizedDescription ?? "unknown"
                    )
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        private func scheduleClockObservation(epoch: UInt64) {
            let initialTime = CMTimeGetSeconds(player.currentTime())
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, !self.stopped else { return }
                let currentTime = CMTimeGetSeconds(self.player.currentTime())
                let advanced = initialTime.isFinite && currentTime.isFinite
                    && currentTime > initialTime + 0.1
                NSLog(
                    "MWX Scene sound: layer=%d epoch=%llu phase=clock source=%@ initial=%.6f current=%.6f advanced=%@ rate=%.3f status=%d",
                    self.binding.layerID, epoch, self.binding.displayPath,
                    initialTime, currentTime, advanced ? "true" : "false",
                    self.player.rate, self.player.timeControlStatus.rawValue
                )
            }
        }

        deinit {
            stop()
        }
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
        NSLog(
            "MWX Scene sound: epoch=%llu phase=started admitted=%d rejected=%d"
                + " skipped=%d paused=%@",
            epoch, program.bindings.count, program.layerRejectionCount,
            program.skippedSourceCount, paused ? "true" : "false"
        )
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
        for binding in program.bindings where binding.volumePropertyKey != nil {
            guard let source = sources[binding.layerID],
                  let volume = volume(for: binding, userValues: userValues) else { continue }
            source.apply(volume: volume)
        }
    }

    /// Scalar-script outputs have a disjoint target set from the immediate
    /// property lane above. A missing snapshot entry never resets a source.
    func apply(snapshot: SceneDynamicSnapshot, excludingLayerIDs: Set<Int> = []) {
        for binding in program.bindings where binding.volumePropertyKey == nil {
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
