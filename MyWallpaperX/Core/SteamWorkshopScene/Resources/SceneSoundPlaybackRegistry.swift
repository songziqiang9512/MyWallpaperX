import AVFoundation
import Foundation

/// The single product owner for admitted authored Sound layer playback.
/// Visual surfaces and the compositor never depend on this registry: a decode
/// or playback failure is contained to the corresponding Sound layer.
final class SceneSoundPlaybackRegistry {
    private final class Source {
        let binding: SceneSoundPlaybackProgram.Binding
        private let player = AVQueuePlayer()
        private let looper: AVPlayerLooper
        private var currentItemObservation: NSKeyValueObservation?
        private var itemStatusObservation: NSKeyValueObservation?
        private var timeControlObservation: NSKeyValueObservation?
        private var stopped = false
        private var wantsPlayback = false

        init(binding: SceneSoundPlaybackProgram.Binding, epoch: UInt64) {
            self.binding = binding
            let item = AVPlayerItem(url: binding.resourceURL)
            looper = AVPlayerLooper(player: player, templateItem: item)
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
            wantsPlayback = !paused
            guard wantsPlayback else { return }
            player.playImmediately(atRate: 1)
        }

        func pause() {
            guard !stopped else { return }
            wantsPlayback = false
            player.pause()
        }

        func resume() {
            guard !stopped else { return }
            wantsPlayback = true
            player.playImmediately(atRate: 1)
        }

        func apply(volume: Double) {
            guard !stopped, volume.isFinite, (0 ... 1).contains(volume) else { return }
            let previous = player.volume
            player.volume = Float(volume)
            guard previous.bitPattern != player.volume.bitPattern else { return }
            NSLog(
                "MWX Scene sound: layer=%d phase=volume source=%@ previous=%.6f current=%.6f",
                binding.layerID, binding.displayPath, previous, player.volume
            )
        }

        func stop() {
            guard !stopped else { return }
            stopped = true
            wantsPlayback = false
            itemStatusObservation?.invalidate()
            currentItemObservation?.invalidate()
            timeControlObservation?.invalidate()
            looper.disableLooping()
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
                    if self.wantsPlayback {
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

    init(program: SceneSoundPlaybackProgram, epoch: UInt64) {
        self.program = program
        self.epoch = epoch
    }

    func start(paused: Bool, userValues: [SceneDynamicTarget: SceneDynamicValue]) {
        guard sources.isEmpty else { return }
        for binding in program.bindings {
            let source = Source(binding: binding, epoch: epoch)
            if let volume = volume(for: binding, userValues: userValues) {
                source.apply(volume: volume)
            }
            sources[binding.layerID] = source
            source.start(paused: paused)
        }
        NSLog(
            "MWX Scene sound: epoch=%llu phase=started admitted=%d rejected=%d paused=%@",
            epoch, program.bindings.count, program.diagnostics.count,
            paused ? "true" : "false"
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
        for binding in program.bindings {
            guard let source = sources[binding.layerID],
                  let volume = volume(for: binding, userValues: userValues) else { continue }
            source.apply(volume: volume)
        }
    }

    func pause() {
        sources.values.forEach { $0.pause() }
    }

    func resume() {
        sources.values.forEach { $0.resume() }
    }

    func stop() {
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
