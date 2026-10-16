import AVFoundation
import Foundation

@main
enum PlaybackHarness {
    final class SharedCounter {
        private let lock = NSLock()
        private var count = 0

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        func reset() {
            lock.lock()
            count = 0
            lock.unlock()
        }
    }

    static func makeSound(mode: String, startsSilent: Bool = false,
                          volume: Double = 0, paths: [String] = ["audio/tone.wav"],
                          gap: Double? = nil, propertyKey: String? = nil)
        -> SceneDocument.SceneSoundLayerDefinition {
        SceneDocument.SceneSoundLayerDefinition(
            paths: paths,
            authoredPathCount: paths.count,
            playbackMode: mode,
            startsSilent: startsSilent,
            muteInEditor: false,
            volume: volume,
            volumePropertyKey: propertyKey,
            minimumTime: gap,
            maximumTime: gap,
            spatialization: nil,
            attenuation: nil,
            minimumDistance: nil
        )
    }

    static func writeWav(to url: URL, seconds: Double, silence: Bool = false) throws {
        let sampleRate = 8000
        let samples = Int(Double(sampleRate) * seconds)
        var pcm = Data(capacity: samples * 2)
        for index in 0..<samples {
            let value = silence ? 0 : sin(2 * Double.pi * 440 * Double(index) / Double(sampleRate))
            let sample = Int16(clamping: Int(value * 8000))
            let little = sample.littleEndian
            withUnsafeBytes(of: little) { pcm.append(contentsOf: $0) }
        }
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u32(_ value: UInt32) {
            let v = value.littleEndian
            withUnsafeBytes(of: v) { data.append(contentsOf: $0) }
        }
        func u16(_ value: UInt16) {
            let v = value.littleEndian
            withUnsafeBytes(of: v) { data.append(contentsOf: $0) }
        }
        text("RIFF"); u32(UInt32(36 + pcm.count)); text("WAVE")
        text("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        text("data"); u32(UInt32(pcm.count)); data.append(pcm)
        try data.write(to: url)
    }

    static func pump(until deadline: Date, while condition: () -> Bool) {
        while Date() < deadline && !condition() {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
    }

    // Test-side reflection exposes the existing AVQueuePlayer for real clock
    // assertions without adding a product testing accessor or another player.
    static func player(_ registry: SceneSoundPlaybackRegistry, layer: Int) -> AVQueuePlayer {
        let sources = Mirror(reflecting: registry).children.first { $0.label == "sources" }!.value
        for child in Mirror(reflecting: sources).children {
            let pair = Array(Mirror(reflecting: child.value).children)
            if pair[0].value as? Int == layer {
                return Mirror(reflecting: pair[1].value).children
                    .first { $0.value is AVQueuePlayer }!.value as! AVQueuePlayer
            }
        }
        fatalError("existing player missing for \(layer)")
    }

    static func send(_ registry: SceneSoundPlaybackRegistry,
                     _ actions: [SceneScriptMediaPlaybackCommand.Action], layer: Int) throws {
        try registry.apply(actions.map { .init(layerID: layer, action: $0, destination: .soundLayer) }).get()
    }

    static func hold(_ seconds: Double) {
        pump(until: Date().addingTimeInterval(seconds), while: { false })
    }

    final class ItemEndProbe {
        let item: AVPlayerItem
        let ends = SharedCounter()
        private var observer: NSObjectProtocol?

        init(_ item: AVPlayerItem) {
            self.item = item
            let ends = self.ends
            observer = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
            ) { _ in ends.increment() }
        }

        func waitForNaturalEnd(on player: AVQueuePlayer) {
            PlaybackHarness.pump(until: Date().addingTimeInterval(8), while: {
                self.ends.value > 0 && !player.items().contains(where: { $0 === self.item })
            })
            precondition(ends.value == 1 && item.status == .readyToPlay,
                         "expected exact ready item's real natural end; ends=\(ends.value)")
            precondition(!player.items().contains(where: { $0 === item }),
                         "ended item did not leave the actual queue")
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }

    static func currentItem(_ actual: AVQueuePlayer, allowed: Set<URL>) -> AVPlayerItem {
        guard let item = actual.currentItem, let asset = item.asset as? AVURLAsset else {
            fatalError("random source has no current AVURLAsset item")
        }
        precondition(actual.items().count == 1 && allowed.contains(asset.url),
                     "random queue must contain one admitted resource")
        return item
    }

    @discardableResult
    static func advance(_ registry: SceneSoundPlaybackRegistry, clock: inout SceneClock,
                        hostTime: Double) -> SceneFrameTiming {
        let timing = clock.advance(hostTime: hostTime, wallDate: Date(timeIntervalSince1970: 0))
        registry.advance(sceneTime: timing.sceneTime)
        return timing
    }

    static func randomProgram(layer: Int, paths: [String], gap: Double,
                              resources: SceneResourceView, propertyKey: String? = nil)
        -> SceneSoundPlaybackProgram {
        let program = SceneSoundPlaybackProgram.compile(document: .init(objects: [
            .init(id: layer, sound: makeSound(mode: "random", paths: paths,
                                             gap: gap, propertyKey: propertyKey))
        ]), resourceView: resources)
        precondition(program.bindings.count == 1,
                     "random fixture did not reach Program: \(program.diagnostics)")
        return program
    }

    static func randomNaturalContinuation(resources: SceneResourceView, allowed: Set<URL>) throws {
        let program = randomProgram(layer: 71, paths: ["audio/renamed-chime.wav", "audio/other-pulse.wav"],
                                    gap: 1.5, resources: resources)
        precondition(Set(program.bindings[0].resources.map(\.url)) == allowed)
        let registry = SceneSoundPlaybackRegistry(program: program, epoch: 41)
        defer { registry.stop() }
        registry.start(paused: false, userValues: [:])
        let actual = player(registry, layer: 71)
        let first = currentItem(actual, allowed: allowed)
        let firstEnd = ItemEndProbe(first)
        firstEnd.waitForNaturalEnd(on: actual)
        precondition(actual.items().isEmpty && registry.sceneScriptSnapshots()[71] == true,
                     "natural end must leave an armed random wait")

        // Construction precedes the new clock epoch's first cadence. Neither
        // stale host time nor wall time spent decoding may consume this gap.
        var clock = SceneClock(hostTime: 700)
        let anchor = advance(registry, clock: &clock, hostTime: 700)
        for _ in 0..<4 { registry.advance(sceneTime: anchor.sceneTime) }
        hold(0.06)
        precondition(actual.items().isEmpty)
        advance(registry, clock: &clock, hostTime: 701.49)
        try send(registry, [.play], layer: 71)
        precondition(actual.items().isEmpty && registry.sceneScriptSnapshots()[71] == true,
                     "running schedule's play must preserve its quiet gap")
        let due = advance(registry, clock: &clock, hostTime: 701.51)
        let next = currentItem(actual, allowed: allowed)
        precondition(next !== first && player(registry, layer: 71) === actual)
        for _ in 0..<4 { registry.advance(sceneTime: due.sceneTime) }
        precondition(actual.currentItem === next && actual.items().count == 1,
                     "same cadence enqueued another random item")
        let nextEnd = ItemEndProbe(next)
        nextEnd.waitForNaturalEnd(on: actual)
        precondition(actual.items().isEmpty)
        print("random-natural-end-scene-clock-single-item-pass")
        print("random-renamed-candidates-and-same-cadence-pass")
    }

    static func randomHostPauseAndGain(resources: SceneResourceView, secondURL: URL) throws {
        let program = randomProgram(layer: 72, paths: ["audio/other-pulse.wav"], gap: 2,
                                    resources: resources, propertyKey: "randomGain")
        let registry = SceneSoundPlaybackRegistry(program: program, epoch: 42)
        defer { registry.stop() }
        registry.start(paused: false, userValues: [.layer(layerID: 72, field: .volume): .scalar(0)])
        let actual = player(registry, layer: 72)
        let first = currentItem(actual, allowed: [secondURL])
        let ended = ItemEndProbe(first)
        ended.waitForNaturalEnd(on: actual)
        var clock = SceneClock(hostTime: 1_000)
        advance(registry, clock: &clock, hostTime: 1_000)
        advance(registry, clock: &clock, hostTime: 1_000.4)
        registry.pause(); clock.pause(hostTime: 1_000.4)
        let paused = advance(registry, clock: &clock, hostTime: 2_000)
        precondition(abs(paused.sceneTime - 0.4) < 0.00001 && actual.items().isEmpty)
        precondition(registry.sceneScriptSnapshots()[72] == false)
        registry.apply(userValues: [.layer(layerID: 72, field: .volume): .scalar(0.6)])
        registry.setMasterVolume(0.5); registry.setMuted(true); registry.setMuted(false)
        precondition(abs(actual.volume - 0.3) < 0.0001 && actual.items().isEmpty)
        hold(0.08)
        clock.resume(hostTime: 2_000); registry.resume()
        precondition(actual.items().isEmpty && registry.sceneScriptSnapshots()[72] == true,
                     "host resume created an item before the remaining gap")
        let resumed = advance(registry, clock: &clock, hostTime: 2_005)
        precondition(resumed.rawFrameTime == 0 && abs(resumed.sceneTime - 0.4) < 0.00001)
        let beforeDeadline = advance(registry, clock: &clock, hostTime: 2_006.59)
        precondition(beforeDeadline.simulationFrameTime < beforeDeadline.rawFrameTime)
        precondition(actual.items().isEmpty, "host pause or gain edit consumed pending time")
        advance(registry, clock: &clock, hostTime: 2_006.61)
        let next = currentItem(actual, allowed: [secondURL])
        precondition(next !== first && player(registry, layer: 72) === actual)
        print("random-real-clock-host-pause-drops-gap-pass")
        print("random-gain-does-not-reset-pending-pass")
    }

    static func randomAuthorGapResume(resources: SceneResourceView, firstURL: URL) throws {
        let registry = SceneSoundPlaybackRegistry(program: randomProgram(
            layer: 73, paths: ["audio/renamed-chime.wav"], gap: 0.6, resources: resources), epoch: 43)
        defer { registry.stop() }
        registry.start(paused: false, userValues: [:])
        let actual = player(registry, layer: 73)
        let first = currentItem(actual, allowed: [firstURL])
        let ended = ItemEndProbe(first); ended.waitForNaturalEnd(on: actual)
        var clock = SceneClock(hostTime: 3_000)
        advance(registry, clock: &clock, hostTime: 3_000)
        advance(registry, clock: &clock, hostTime: 3_000.2)
        try send(registry, [.pause], layer: 73)
        advance(registry, clock: &clock, hostTime: 3_010)
        precondition(actual.items().isEmpty && registry.sceneScriptSnapshots()[73] == false)
        try send(registry, [.play], layer: 73)
        let resumed = currentItem(actual, allowed: [firstURL])
        precondition(resumed !== first && registry.sceneScriptSnapshots()[73] == true)
        try send(registry, [.play], layer: 73)
        precondition(actual.currentItem === resumed, "running random play replaced item")
        advance(registry, clock: &clock, hostTime: 3_010.39)
        precondition(actual.currentItem === resumed)
        advance(registry, clock: &clock, hostTime: 3_010.41)
        let replacement = currentItem(actual, allowed: [firstURL])
        precondition(replacement !== resumed && player(registry, layer: 73) === actual)
        // This deliberately delivered late event is not counted as a natural
        // completion. Its old item must have lost all schedule write authority.
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: resumed)
        hold(0.01)
        advance(registry, clock: &clock, hostTime: 3_020)
        precondition(actual.currentItem === replacement && actual.items().count == 1,
                     "retired item completion rearmed a wait")
        print("random-author-gap-resume-and-running-play-pass")
        print("random-replaced-item-late-end-is-ignored-pass")
    }

    static func randomRetainedGapSurvivesTemporaryEnd(resources: SceneResourceView,
                                                     firstURL: URL) throws {
        let registry = SceneSoundPlaybackRegistry(program: randomProgram(
            layer: 74, paths: ["audio/renamed-chime.wav"], gap: 1.2, resources: resources), epoch: 44)
        defer { registry.stop() }
        registry.start(paused: false, userValues: [:])
        let actual = player(registry, layer: 74)
        let first = currentItem(actual, allowed: [firstURL])
        let firstEnd = ItemEndProbe(first); firstEnd.waitForNaturalEnd(on: actual)
        var clock = SceneClock(hostTime: 4_000)
        advance(registry, clock: &clock, hostTime: 4_000)
        advance(registry, clock: &clock, hostTime: 4_000.2)
        try send(registry, [.pause], layer: 74)
        advance(registry, clock: &clock, hostTime: 4_010)
        try send(registry, [.play], layer: 74)
        let temporary = currentItem(actual, allowed: [firstURL])
        let temporaryEnd = ItemEndProbe(temporary); temporaryEnd.waitForNaturalEnd(on: actual)
        precondition(registry.sceneScriptSnapshots()[74] == true && actual.items().isEmpty)
        advance(registry, clock: &clock, hostTime: 4_010.6)
        advance(registry, clock: &clock, hostTime: 4_010.99)
        precondition(actual.items().isEmpty)
        advance(registry, clock: &clock, hostTime: 4_011.01)
        precondition(currentItem(actual, allowed: [firstURL]) !== temporary,
                     "temporary item's end overwrote the retained remaining gap")
        print("random-temporary-end-preserves-old-gap-pass")
    }

    static func randomStopRetireAndEpoch(resources: SceneResourceView, firstURL: URL) throws {
        let program = randomProgram(layer: 75, paths: ["audio/renamed-chime.wav"],
                                    gap: 1, resources: resources)
        let registry = SceneSoundPlaybackRegistry(program: program, epoch: 45)
        registry.start(paused: false, userValues: [:])
        let actual = player(registry, layer: 75)
        let first = currentItem(actual, allowed: [firstURL])
        let firstEnd = ItemEndProbe(first); firstEnd.waitForNaturalEnd(on: actual)
        var clock = SceneClock(hostTime: 5_000)
        advance(registry, clock: &clock, hostTime: 5_000)
        advance(registry, clock: &clock, hostTime: 5_000.2)
        try send(registry, [.stop], layer: 75)
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: first)
        registry.pause(); registry.resume()
        advance(registry, clock: &clock, hostTime: 5_020)
        precondition(actual.items().isEmpty && registry.sceneScriptSnapshots()[75] == false)
        try send(registry, [.play], layer: 75)
        let replay = currentItem(actual, allowed: [firstURL])
        precondition(replay !== first && player(registry, layer: 75) === actual)
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: first)
        advance(registry, clock: &clock, hostTime: 5_030)
        precondition(actual.currentItem === replay, "author stop retained an old pending gap")
        registry.stop()
        let fresh = SceneSoundPlaybackRegistry(program: program, epoch: 46)
        defer { fresh.stop() }
        fresh.start(paused: false, userValues: [:])
        let freshPlayer = player(fresh, layer: 75)
        let freshItem = currentItem(freshPlayer, allowed: [firstURL])
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: replay)
        registry.resume(); registry.advance(sceneTime: 1_000); hold(0.03)
        precondition(actual.items().isEmpty && actual.rate == 0
                     && registry.sceneScriptSnapshots().isEmpty && freshPlayer !== actual)
        precondition(freshPlayer.currentItem === freshItem)
        fresh.retire(layerIDs: [75])
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: freshItem)
        fresh.advance(sceneTime: 10_000); fresh.resume(); hold(0.03)
        precondition(freshPlayer.items().isEmpty && freshPlayer.rate == 0
                     && fresh.sceneScriptSnapshots()[75] == nil)
        guard case .failure(.unavailableLayer(75)) = fresh.apply([
            .init(layerID: 75, action: .play, destination: .soundLayer)
        ]) else { fatalError("retired random source accepted play") }
        print("random-stop-replay-clears-wait-pass")
        print("random-retire-and-epoch-late-events-do-not-revive-pass")
    }

    static func randomDecodeFailure(resources: SceneResourceView, firstURL: URL) throws {
        let document = SceneDocument(objects: [
            .init(id: 76, sound: makeSound(mode: "random", paths: ["audio/not-a-codec.wav"], gap: 0)),
            .init(id: 77, sound: makeSound(mode: "loop", paths: ["audio/renamed-chime.wav"]))
        ])
        let program = SceneSoundPlaybackProgram.compile(document: document, resourceView: resources)
        precondition(program.bindings.count == 2, "codec failure must reach the real player")
        let registry = SceneSoundPlaybackRegistry(program: program, epoch: 47)
        defer { registry.stop() }
        registry.start(paused: false, userValues: [:])
        let failed = player(registry, layer: 76), healthy = player(registry, layer: 77)
        guard let badItem = failed.currentItem else { fatalError("bad codec was never attempted") }
        pump(until: Date().addingTimeInterval(8), while: {
            badItem.status == .failed && failed.items().isEmpty
                && CMTimeGetSeconds(healthy.currentTime()) > 0.05
        })
        precondition(badItem.status == .failed && failed.items().isEmpty)
        precondition(registry.sceneScriptSnapshots()[76] == false
                     && registry.sceneScriptSnapshots()[77] == true)
        let healthyBefore = CMTimeGetSeconds(healthy.currentTime())
        let healthyItem = healthy.currentItem
        for time in [0.0, 1.0, 10.0, 100.0] { registry.advance(sceneTime: time) }
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: badItem)
        registry.pause(); registry.resume()
        hold(0.08)
        precondition(failed.items().isEmpty && registry.sceneScriptSnapshots()[76] == false)
        precondition(healthy.rate == 1 && healthy.currentItem?.status == .readyToPlay
                     && (healthy.currentItem?.asset as? AVURLAsset)?.url == firstURL)
        pump(until: Date().addingTimeInterval(3), while: {
            healthy.currentItem !== healthyItem
                || CMTimeGetSeconds(healthy.currentTime()) > healthyBefore + 0.04
        })
        precondition(healthy.currentItem !== healthyItem
                     || CMTimeGetSeconds(healthy.currentTime()) > healthyBefore + 0.04)
        try send(registry, [.play], layer: 76)
        guard let explicitRetry = failed.currentItem else { fatalError("explicit retry did not create item") }
        precondition(explicitRetry !== badItem)
        pump(until: Date().addingTimeInterval(8), while: {
            explicitRetry.status == .failed && failed.items().isEmpty
        })
        precondition(explicitRetry.status == .failed && failed.items().isEmpty && healthy.rate == 1)
        print("random-codec-failure-local-and-explicit-retry-pass")
    }

    static func runRandomChecks(directory: URL) throws {
        let first = directory.appendingPathComponent("renamed-chime.wav")
        let second = directory.appendingPathComponent("other-pulse.wav")
        let bad = directory.appendingPathComponent("not-a-codec.wav")
        try writeWav(to: first, seconds: 0.3, silence: true)
        try writeWav(to: second, seconds: 0.42, silence: true)
        try Data("deliberately undecodable authored resource".utf8).write(to: bad)
        let resources = SceneResourceView(resourcesByReference: [
            "audio/renamed-chime.wav": first, "audio/other-pulse.wav": second,
            "audio/not-a-codec.wav": bad
        ])
        try randomNaturalContinuation(resources: resources, allowed: [first, second])
        try randomHostPauseAndGain(resources: resources, secondURL: second)
        try randomAuthorGapResume(resources: resources, firstURL: first)
        try randomRetainedGapSurvivesTemporaryEnd(resources: resources, firstURL: first)
        try randomStopRetireAndEpoch(resources: resources, firstURL: first)
        try randomDecodeFailure(resources: resources, firstURL: first)
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-scene-sound-playback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let toneURL = directory.appendingPathComponent("tone.wav")
        try writeWav(to: toneURL, seconds: 0.4)

        let endCount = SharedCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { _ in endCount.increment() }

        let resourceView = SceneResourceView(resourcesByReference: ["audio/tone.wav": toneURL])

        // single: exactly one play-through; the owner must not restart it.
        do {
            let document = SceneDocument(objects: [
                .init(id: 12, sound: makeSound(mode: "single"))
            ])
            let program = SceneSoundPlaybackProgram.compile(
                document: document,
                resourceView: resourceView
            )
            precondition(
                program.bindings.count == 1,
                "single binding missing: \(program.diagnostics)"
            )
            let registry = SceneSoundPlaybackRegistry(program: program, epoch: 7)
            registry.start(paused: false, userValues: [:])
            let originalPlayer = player(registry, layer: 12)
            guard let firstItem = originalPlayer.currentItem else {
                fatalError("single did not install its first item")
            }
            let firstEnd = ItemEndProbe(firstItem)
            firstEnd.waitForNaturalEnd(on: originalPlayer)
            precondition(endCount.value == 1, "single never finished (ends=\(endCount.value))")
            pump(until: Date().addingTimeInterval(1.5), while: { false })
            precondition(
                endCount.value == 1,
                "single restarted after end (ends=\(endCount.value))"
            )
            precondition(registry.sceneScriptSnapshots()[12] == false)
            registry.pause(); registry.resume(); hold(0.2)
            precondition(endCount.value == 1, "host resume restarted natural end")
            try send(registry, [.play], layer: 12)
            precondition(player(registry, layer: 12) === originalPlayer)
            guard let replayItem = originalPlayer.currentItem else {
                fatalError("single explicit replay did not install an item")
            }
            let replayEnd = ItemEndProbe(replayItem)
            replayEnd.waitForNaturalEnd(on: originalPlayer)
            precondition(endCount.value == 2, "single explicit replay never ended")
            precondition(originalPlayer.items().isEmpty && registry.sceneScriptSnapshots()[12] == false)
            registry.stop()
            print("single-replay-same-player-pass")
            print("single-play-to-end-pass")
        }
        // loop: keeps restarting at the item boundary — unchanged semantics.
        do {
            endCount.reset()
            let document = SceneDocument(objects: [
                .init(id: 13, sound: makeSound(mode: "loop"))
            ])
            let program = SceneSoundPlaybackProgram.compile(
                document: document,
                resourceView: resourceView
            )
            precondition(
                program.bindings.count == 1,
                "loop binding missing: \(program.diagnostics)"
            )
            let registry = SceneSoundPlaybackRegistry(program: program, epoch: 8)
            registry.start(paused: false, userValues: [:])
            pump(until: Date().addingTimeInterval(10), while: { endCount.value >= 2 })
            precondition(
                endCount.value >= 2,
                "loop never restarted (ends=\(endCount.value))"
            )
            registry.stop()
            print("loop-restart-pass")
        }

        // Long, muted WAV gives position assertions enough headroom before completion.
        try writeWav(to: toneURL, seconds: 3)
        do {
            let program = SceneSoundPlaybackProgram.compile(document: .init(objects: [
                .init(id: 31, sound: makeSound(mode: "single", startsSilent: true))
            ]), resourceView: resourceView)
            let registry = SceneSoundPlaybackRegistry(program: program, epoch: 9)
            registry.start(paused: false, userValues: [:])
            let actual = player(registry, layer: 31)
            pump(until: Date().addingTimeInterval(5), while: { actual.currentItem?.status == .readyToPlay })
            precondition(actual.currentItem?.status == .readyToPlay)
            registry.pause(); registry.resume(); hold(0.15)
            precondition(registry.sceneScriptSnapshots()[31] == false && actual.rate == 0)
            precondition(CMTimeGetSeconds(actual.currentTime()) < 0.02)
            print("startsilent-ready-host-resume-pass")

            try registry.validate([.init(layerID: 31, action: .play, destination: .soundLayer)]).get()
            precondition(actual.rate == 0, "validation mutated player")
            try send(registry, [.play], layer: 31)
            pump(until: Date().addingTimeInterval(5), while: { CMTimeGetSeconds(actual.currentTime()) > 0.4 })
            precondition(registry.sceneScriptSnapshots()[31] == true)
            let item = actual.currentItem, beforeRepeat = CMTimeGetSeconds(actual.currentTime())
            try send(registry, [.play, .play], layer: 31)
            pump(until: Date().addingTimeInterval(3), while: { CMTimeGetSeconds(actual.currentTime()) < 0.1 })
            precondition(actual.currentItem === item && CMTimeGetSeconds(actual.currentTime()) < 0.1)
            pump(until: Date().addingTimeInterval(3), while: {
                CMTimeGetSeconds(actual.currentTime()) > 0.08
            })
            let resumedTime = CMTimeGetSeconds(actual.currentTime())
            precondition(resumedTime > 0.08 && resumedTime < beforeRepeat - 0.1,
                "repeat time=\(resumedTime) before=\(beforeRepeat) rate=\(actual.rate) status=\(actual.timeControlStatus.rawValue)")
            print("repeated-play-restarts-single-pass")

            try send(registry, [.pause], layer: 31)
            let pausedAt = CMTimeGetSeconds(actual.currentTime())
            registry.pause(); registry.resume(); hold(0.2)
            precondition(registry.sceneScriptSnapshots()[31] == false && actual.rate == 0)
            precondition(abs(CMTimeGetSeconds(actual.currentTime()) - pausedAt) < 0.04)
            registry.pause()
            try send(registry, [.play], layer: 31); hold(0.1)
            precondition(registry.sceneScriptSnapshots()[31] == false && actual.rate == 0)
            precondition(abs(CMTimeGetSeconds(actual.currentTime()) - pausedAt) < 0.04)
            registry.resume()
            pump(until: Date().addingTimeInterval(3), while: { CMTimeGetSeconds(actual.currentTime()) > pausedAt + 0.1 })
            precondition(actual.currentItem === item && registry.sceneScriptSnapshots()[31] == true)
            print("author-pause-and-host-pause-independent-pass")
            registry.pause()
            try send(registry, [.play], layer: 31)
            pump(until: Date().addingTimeInterval(3), while: { CMTimeGetSeconds(actual.currentTime()) < 0.02 })
            precondition(CMTimeGetSeconds(actual.currentTime()) < 0.02 && actual.rate == 0)
            precondition(registry.sceneScriptSnapshots()[31] == false)
            registry.resume()
            pump(until: Date().addingTimeInterval(3), while: { CMTimeGetSeconds(actual.currentTime()) > 0.1 })
            precondition(registry.sceneScriptSnapshots()[31] == true)
            print("host-suspension-preserves-author-repeat-semantics-pass")

            try send(registry, [.stop], layer: 31)
            pump(until: Date().addingTimeInterval(3), while: { CMTimeGetSeconds(actual.currentTime()) < 0.02 })
            precondition(CMTimeGetSeconds(actual.currentTime()) < 0.02)
            registry.pause(); registry.resume(); hold(0.15)
            precondition(actual.rate == 0 && registry.sceneScriptSnapshots()[31] == false)
            try send(registry, [.play], layer: 31)
            pump(until: Date().addingTimeInterval(3), while: { CMTimeGetSeconds(actual.currentTime()) > 0.1 })
            precondition(registry.sceneScriptSnapshots()[31] == true)
            print("stop-rewinds-and-replays-pass")

            let stop = SceneScriptMediaPlaybackCommand(layerID: 31, action: .stop, destination: .soundLayer)
            let invalid: [(SceneScriptMediaPlaybackCommand, SceneSoundPlaybackRegistry.CommandFailure)] = [
                (.init(layerID: 31, action: .setCurrentTime(0), destination: .soundLayer), .invalidCommand(1)),
                (.init(layerID: 31, action: .setRate(1), destination: .soundLayer), .invalidCommand(1)),
                (.init(layerID: 31, action: .setLoop(true), destination: .soundLayer), .invalidCommand(1)),
                (.init(layerID: 31, action: .play), .invalidCommand(1)),
                (.init(layerID: 999, action: .play, destination: .soundLayer), .unavailableLayer(999))]
            for (command, expected) in invalid {
                guard case let .failure(failure) = registry.apply([stop, command]) else {
                    fatalError("invalid batch accepted")
                }
                precondition(failure == expected && actual.rate == 1)
            }
            guard case .failure(.commandBudgetExceeded) = registry.apply(Array(repeating: stop, count: 65))
            else { fatalError("budget accepted") }
            precondition(actual.rate == 1)
            let validAt = CMTimeGetSeconds(actual.currentTime())
            try registry.validate([stop]).get(); hold(0.1)
            precondition(actual.rate == 1 && CMTimeGetSeconds(actual.currentTime()) > validAt + 0.05)
            print("atomic-command-rejection-pass")

            try send(registry, [.play, .pause], layer: 31)
            precondition(actual.rate == 0 && registry.sceneScriptSnapshots()[31] == false)
            try send(registry, [.pause, .play], layer: 31)
            precondition(registry.sceneScriptSnapshots()[31] == true)
            try send(registry, [.play, .stop], layer: 31)
            precondition(registry.sceneScriptSnapshots()[31] == false)
            print("ordered-author-commands-pass")
            registry.stop(); hold(0.2)
            registry.resume(); registry.start(paused: false, userValues: [:])
            precondition(registry.sceneScriptSnapshots().isEmpty && actual.rate == 0 && actual.items().isEmpty)
            guard case .failure(.unavailableLayer(31)) = registry.apply([stop])
            else { fatalError("retired registry accepted command") }
            print("teardown-rejects-and-does-not-revive-pass")
        }
        do {
            let program = SceneSoundPlaybackProgram.compile(document: .init(objects: [
                .init(id: 32, sound: makeSound(mode: "single"))
            ]), resourceView: resourceView)
            let registry = SceneSoundPlaybackRegistry(program: program, epoch: 10)
            registry.start(paused: true, userValues: [:])
            let actual = player(registry, layer: 32)
            hold(0.2)
            precondition(actual.rate == 0 && registry.sceneScriptSnapshots()[32] == false)
            registry.resume()
            pump(until: Date().addingTimeInterval(3), while: { CMTimeGetSeconds(actual.currentTime()) > 0.1 })
            precondition(registry.sceneScriptSnapshots()[32] == true)
            registry.stop()
            print("initial-host-pause-retains-autoplay-intent-pass")
        }
        do {
            let program = SceneSoundPlaybackProgram.compile(document: .init(objects: [
                .init(id: 33, sound: makeSound(mode: "loop", startsSilent: true, volume: 0.8))
            ]), resourceView: resourceView)
            let registry = SceneSoundPlaybackRegistry(program: program, epoch: 11)
            registry.setMasterVolume(0.5); registry.setMuted(true)
            registry.start(paused: false, userValues: [:])
            let actual = player(registry, layer: 33)
            precondition(actual.volume == 0)
            registry.setMuted(false)
            precondition(abs(actual.volume - 0.4) < 0.001 && actual.rate == 0)
            registry.setMasterVolume(0.25)
            precondition(abs(actual.volume - 0.2) < 0.001)
            registry.setMuted(true); precondition(actual.volume == 0)
            registry.stop()
            print("gain-and-mute-contract-pass")
        }
        do {
            let program = SceneSoundPlaybackProgram.compile(document: .init(objects: [
                .init(id: 34, sound: makeSound(mode: "loop")),
                .init(id: 35, sound: makeSound(mode: "loop"))
            ]), resourceView: resourceView)
            let registry = SceneSoundPlaybackRegistry(program: program, epoch: 12)
            registry.start(paused: false, userValues: [:])
            let retired = player(registry, layer: 34), healthy = player(registry, layer: 35)
            pump(until: Date().addingTimeInterval(5), while: {
                CMTimeGetSeconds(retired.currentTime()) > 0.1
                    && CMTimeGetSeconds(healthy.currentTime()) > 0.1
            })
            precondition(registry.sceneScriptSnapshots()[34] == true
                && registry.sceneScriptSnapshots()[35] == true)
            registry.retire(layerIDs: [34, 999])
            registry.retire(layerIDs: [34])
            precondition(retired.rate == 0 && retired.items().isEmpty)
            precondition(registry.sceneScriptSnapshots()[34] == nil
                && registry.sceneScriptSnapshots()[35] == true)
            let healthyAt = CMTimeGetSeconds(healthy.currentTime())
            registry.pause(); registry.resume()
            pump(until: Date().addingTimeInterval(3), while: {
                CMTimeGetSeconds(healthy.currentTime()) > healthyAt + 0.1
            })
            precondition(CMTimeGetSeconds(healthy.currentTime()) > healthyAt + 0.1
                && healthy.rate == 1 && retired.rate == 0 && retired.items().isEmpty)
            let retiredPlay = SceneScriptMediaPlaybackCommand(
                layerID: 34, action: .play, destination: .soundLayer)
            guard case .failure(.unavailableLayer(34)) = registry.validate([retiredPlay]),
                  case .failure(.unavailableLayer(34)) = registry.apply([
                    .init(layerID: 35, action: .pause, destination: .soundLayer), retiredPlay])
            else { fatalError("retired Sound admitted") }
            precondition(healthy.rate == 1 && registry.sceneScriptSnapshots()[35] == true)
            registry.stop()
            print("layer-retirement-stops-only-its-source-pass")
        }
        NotificationCenter.default.removeObserver(observer)
        try runRandomChecks(directory: directory)
        try? FileManager.default.removeItem(at: directory)
    }
}
