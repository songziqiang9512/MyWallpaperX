#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PROGRAM_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneSoundPlaybackProgram.swift"
)
REGISTRY_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneSoundPlaybackRegistry.swift"
)


def record_process(name, process):
    if destination := os.environ.get("MWX_SOUND_TEST_EVIDENCE"):
        root = Path(destination)
        root.mkdir(parents=True, exist_ok=True)
        (root / f"{name}.stdout").write_text(process.stdout)
        (root / f"{name}.stderr").write_text(process.stderr)
        (root / f"{name}.json").write_text(json.dumps({"returnCode": process.returncode}))

STUB_SOURCE = r'''
import Foundation

enum SceneDynamicField: Hashable {
    case volume
}

enum SceneDynamicTarget: Hashable {
    case layer(layerID: Int, field: SceneDynamicField)
}

enum SceneDynamicValue: Hashable {
    case scalar(Double)
}

struct SceneDynamicTargetDefinition {
    let target: SceneDynamicTarget
    let authoredValue: SceneDynamicValue
}

struct SceneDynamicResolvedValue {
    let value: SceneDynamicValue
}

struct SceneDynamicSnapshot {
    subscript(target: SceneDynamicTarget) -> SceneDynamicResolvedValue? { nil }
}

struct SceneScriptMediaPlaybackCommand {
    enum Destination { case videoTexture, soundLayer }
    enum Action { case play, pause, stop, setCurrentTime(Double), setRate(Double), setLoop(Bool) }
    let layerID: Int
    let action: Action
    let destination: Destination
    init(layerID: Int, action: Action, destination: Destination = .videoTexture) {
        self.layerID = layerID; self.action = action; self.destination = destination
    }
}

struct SceneDocument {
    struct SceneSoundLayerDefinition {
        let paths: [String]
        let authoredPathCount: Int
        let playbackMode: String?
        let startsSilent: Bool?
        let muteInEditor: Bool?
        let volume: Double?
        let volumePropertyKey: String?
        let minimumTime: Double?
        let maximumTime: Double?
        let spatialization: Bool?
        let attenuation: Double?
        let minimumDistance: Double?
    }

    struct Object {
        let id: Int
        let sound: SceneSoundLayerDefinition?
    }

    let objects: [Object]
}

struct SceneResource {
    let url: URL
}

struct SceneResourceView {
    let resourcesByReference: [String: URL]

    func resource(forReference reference: String) -> SceneResource? {
        guard let url = resourcesByReference[reference] else { return nil }
        return SceneResource(url: url)
    }

    func displayPath(for url: URL) -> String {
        url.path
    }
}
'''

PROGRAM_HARNESS_SOURCE = r'''
import Foundation

@main
enum Harness {
    static func sound(
        paths: [String],
        mode: String,
        minimumTime: Double? = nil,
        maximumTime: Double? = nil,
        spatialization: Bool? = nil,
        attenuation: Double? = nil,
        minimumDistance: Double? = nil,
        startsSilent: Bool? = false
    ) -> SceneDocument.SceneSoundLayerDefinition {
        SceneDocument.SceneSoundLayerDefinition(
            paths: paths,
            authoredPathCount: paths.count,
            playbackMode: mode,
            startsSilent: startsSilent,
            muteInEditor: false,
            volume: 0.5,
            volumePropertyKey: nil,
            minimumTime: minimumTime,
            maximumTime: maximumTime,
            spatialization: spatialization,
            attenuation: attenuation,
            minimumDistance: minimumDistance
        )
    }

    static func main() throws {
        let timedLoopLayerID = 101
        let firstAvailableSourceLayerID = 202
        let skipToNextSourceLayerID = 206
        let allSourcesUnavailableLayerID = 207
        let pathEscapeLayerID = 210
        let missingLegalSourceLayerID = 211
        let oggLayerID = 208
        let mixedCaseSingleLayerID = 209
        let nonLoopLayerID = 303
        let explicitlyNonspatialLayerID = 404
        let spatialLayerID = 505
        let document = SceneDocument(objects: [
            .init(id: 606, sound: sound(paths: ["audio/caps.mp3"], mode: "loop", startsSilent: true)),
            .init(id: 607, sound: sound(paths: ["audio/caps.mp3"], mode: "loop", startsSilent: nil)),
            .init(
                id: timedLoopLayerID,
                sound: sound(
                    paths: ["audio/timed-loop.mp3"],
                    mode: "loop",
                    minimumTime: 2.5,
                    maximumTime: 7.5
                )
            ),
            .init(
                id: firstAvailableSourceLayerID,
                sound: sound(
                    paths: ["audio/first.wav", "audio/second.flac"],
                    mode: "loop"
                )
            ),
            .init(
                id: skipToNextSourceLayerID,
                sound: sound(
                    paths: ["audio/missing.ogg", "audio/fallback.flac"],
                    mode: "single"
                )
            ),
            .init(
                id: allSourcesUnavailableLayerID,
                sound: sound(
                    paths: ["audio/gone.wav", "audio/also-gone.mp3"],
                    mode: "loop"
                )
            ),
            .init(
                id: pathEscapeLayerID,
                sound: sound(paths: ["../escape.flac"], mode: "loop")
            ),
            .init(
                id: missingLegalSourceLayerID,
                sound: sound(paths: ["audio/absent.mp3"], mode: "loop")
            ),
            .init(
                id: oggLayerID,
                sound: sound(paths: ["audio/blocked.ogg"], mode: "single")
            ),
            .init(
                id: mixedCaseSingleLayerID,
                sound: sound(paths: ["audio/caps.mp3"], mode: "Single")
            ),
            .init(
                id: nonLoopLayerID,
                sound: sound(paths: ["audio/one-shot.wav"], mode: "once")
            ),
            .init(
                id: explicitlyNonspatialLayerID,
                sound: sound(
                    paths: ["audio/nonspatial.mp3"],
                    mode: "loop",
                    spatialization: false,
                    attenuation: 1,
                    minimumDistance: 1
                )
            ),
            .init(
                id: spatialLayerID,
                sound: sound(
                    paths: ["audio/spatial.mp3"],
                    mode: "loop",
                    spatialization: true,
                    attenuation: 1,
                    minimumDistance: 1
                )
            ),
        ])
        let resourceView = SceneResourceView(resourcesByReference: [
            "audio/timed-loop.mp3": URL(fileURLWithPath: "/fixture/timed-loop.mp3"),
            "audio/first.wav": URL(fileURLWithPath: "/fixture/first.wav"),
            "audio/second.flac": URL(fileURLWithPath: "/fixture/second.flac"),
            "audio/fallback.flac": URL(fileURLWithPath: "/fixture/fallback.flac"),
            "audio/caps.mp3": URL(fileURLWithPath: "/fixture/caps.mp3"),
            "audio/one-shot.wav": URL(fileURLWithPath: "/fixture/one-shot.wav"),
            "audio/nonspatial.mp3": URL(fileURLWithPath: "/fixture/nonspatial.mp3"),
            "audio/spatial.mp3": URL(fileURLWithPath: "/fixture/spatial.mp3"),
        ])

        let program = SceneSoundPlaybackProgram.compile(
            document: document,
            resourceView: resourceView
        )
        let payload: [String: Any] = [
            "admittedLayerIDs": program.bindings.map(\.layerID),
            "bindings": program.bindings.map { binding in
                ["layerID": binding.layerID, "source": binding.displayPath, "startsSilent": binding.startsSilent]
            },
            "diagnostics": program.diagnostics.map { diagnostic in
                [
                    "layerID": diagnostic.layerID,
                    "reason": diagnostic.reason.rawValue,
                    "detail": diagnostic.detail,
                ]
            },
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''

PLAYBACK_HARNESS_SOURCE = r'''
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
                          volume: Double = 0) -> SceneDocument.SceneSoundLayerDefinition {
        SceneDocument.SceneSoundLayerDefinition(
            paths: ["audio/tone.wav"],
            authoredPathCount: 1,
            playbackMode: mode,
            startsSilent: startsSilent,
            muteInEditor: false,
            volume: volume,
            volumePropertyKey: nil,
            minimumTime: nil,
            maximumTime: nil,
            spatialization: nil,
            attenuation: nil,
            minimumDistance: nil
        )
    }

    static func writeWav(to url: URL, seconds: Double) throws {
        let sampleRate = 8000
        let samples = Int(Double(sampleRate) * seconds)
        var pcm = Data(capacity: samples * 2)
        for index in 0..<samples {
            let value = sin(2 * Double.pi * 440 * Double(index) / Double(sampleRate))
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
            pump(until: Date().addingTimeInterval(10), while: { endCount.value >= 1 })
            precondition(endCount.value == 1, "single never finished (ends=\(endCount.value))")
            pump(until: Date().addingTimeInterval(1.5), while: { false })
            precondition(
                endCount.value == 1,
                "single restarted after end (ends=\(endCount.value))"
            )
            precondition(registry.sceneScriptSnapshots()[12] == false)
            let originalPlayer = player(registry, layer: 12)
            registry.pause(); registry.resume(); hold(0.2)
            precondition(endCount.value == 1, "host resume restarted natural end")
            try send(registry, [.play], layer: 12)
            precondition(player(registry, layer: 12) === originalPlayer)
            pump(until: Date().addingTimeInterval(5), while: { endCount.value >= 2 })
            precondition(endCount.value == 2, "single explicit replay never ended")
            precondition(registry.sceneScriptSnapshots()[12] == false)
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
        try? FileManager.default.removeItem(at: directory)
    }
}
'''


def layer_diagnostics(payload, layer_id):
    return [
        (entry["reason"], entry["detail"])
        for entry in payload["diagnostics"]
        if entry["layerID"] == layer_id
    ]


def layer_binding_sources(payload, layer_id):
    return [
        entry["source"]
        for entry in payload["bindings"]
        if entry["layerID"] == layer_id
    ]


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneSoundPlaybackProgramTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-sound-program-"
        )
        root = Path(cls.temporary_directory.name)
        stub = root / "SceneSoundPlaybackProgramStubs.swift"
        harness = root / "Harness.swift"
        binary = root / "scene-sound-playback-program"
        stub.write_text(STUB_SOURCE, encoding="utf-8")
        harness.write_text(PROGRAM_HARNESS_SOURCE, encoding="utf-8")
        compilation = subprocess.run(
            [
                "swiftc",
                str(PROGRAM_SOURCE),
                str(stub),
                str(harness),
                "-o",
                str(binary),
            ],
            capture_output=True,
            text=True,
            shell=False,
        )
        record_process("program-compile", compilation)
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        # /usr/bin/env keeps a literal executable anchor; the target is the
        # harness binary this test just compiled into its own temp directory.
        completed = subprocess.run(
            ["/usr/bin/env", str(binary)],
            capture_output=True,
            text=True,
            check=True,
            shell=False,
        )
        record_process("program", completed)
        cls.payload = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_explicit_startsilent_is_preserved_and_missing_value_is_rejected(self) -> None:
        binding = next(entry for entry in self.payload["bindings"] if entry["layerID"] == 606)
        self.assertTrue(binding["startsSilent"])
        self.assertEqual(layer_diagnostics(self.payload, 606), [])
        self.assertNotIn(607, self.payload["admittedLayerIDs"])
        self.assertEqual(layer_diagnostics(self.payload, 607), [("startsSilentUnsupported", "nil")])

    def test_loop_with_minimum_and_maximum_time_remains_admitted(self) -> None:
        self.assertIn(101, self.payload["admittedLayerIDs"])
        self.assertEqual(layer_diagnostics(self.payload, 101), [])

    def test_explicitly_disabled_spatial_metadata_remains_nonspatial(self) -> None:
        diagnostic_layer_ids = [
            entry["layerID"] for entry in self.payload["diagnostics"]
        ]
        self.assertNotIn(404, diagnostic_layer_ids)

    def test_single_mode_is_admitted(self) -> None:
        self.assertIn(209, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_binding_sources(self.payload, 209), ["/fixture/caps.mp3"]
        )
        self.assertEqual(layer_diagnostics(self.payload, 209), [])

    def test_multi_source_admits_first_available_source(self) -> None:
        self.assertIn(202, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_binding_sources(self.payload, 202), ["/fixture/first.wav"]
        )
        self.assertEqual(layer_diagnostics(self.payload, 202), [])

    def test_multi_source_skips_unusable_sources_to_first_available(self) -> None:
        self.assertIn(206, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_binding_sources(self.payload, 206), ["/fixture/fallback.flac"]
        )
        self.assertEqual(
            layer_diagnostics(self.payload, 206),
            [("audioFormatUnsupported", "ogg")],
        )

    def test_all_sources_unavailable_keep_their_per_source_reasons(self) -> None:
        self.assertNotIn(207, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_diagnostics(self.payload, 207),
            [
                ("resourceUnavailable", "audio/gone.wav"),
                ("resourceUnavailable", "audio/also-gone.mp3"),
            ],
        )

    def test_path_escape_source_keeps_the_typed_path_reason(self) -> None:
        self.assertNotIn(210, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_diagnostics(self.payload, 210),
            [("malformedSourceList", "../escape.flac")],
        )

    def test_missing_source_with_legal_extension_keeps_resource_reason(self) -> None:
        self.assertNotIn(211, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_diagnostics(self.payload, 211),
            [("resourceUnavailable", "audio/absent.mp3")],
        )

    def test_ogg_source_remains_unsupported(self) -> None:
        self.assertNotIn(208, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_diagnostics(self.payload, 208),
            [("audioFormatUnsupported", "ogg")],
        )

    def test_non_loop_mode_is_rejected_with_the_typed_reason(self) -> None:
        self.assertNotIn(303, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_diagnostics(self.payload, 303),
            [("playbackModeUnsupported", "once")],
        )

    def test_enabled_spatial_playback_remains_typed_unsupported(self) -> None:
        self.assertNotIn(505, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_diagnostics(self.payload, 505),
            [("spatialPlaybackUnsupported", "spatial-fields-present")],
        )


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneSoundPlaybackRegistryPlaybackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-sound-playback-"
        )
        root = Path(cls.temporary_directory.name)
        stub = root / "SceneSoundPlaybackRegistryStubs.swift"
        harness = root / "PlaybackHarness.swift"
        binary = root / "scene-sound-playback-registry"
        stub.write_text(STUB_SOURCE, encoding="utf-8")
        harness.write_text(PLAYBACK_HARNESS_SOURCE, encoding="utf-8")
        compilation = subprocess.run(
            [
                "swiftc",
                str(PROGRAM_SOURCE),
                str(REGISTRY_SOURCE),
                str(stub),
                str(harness),
                "-o",
                str(binary),
            ],
            capture_output=True,
            text=True,
            shell=False,
        )
        record_process("playback-compile", compilation)
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        cls.result = subprocess.run(
            ["/usr/bin/env", str(binary)],
            capture_output=True,
            text=True,
            timeout=90,
            shell=False,
        )
        record_process("playback", cls.result)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_single_mode_plays_to_end_without_restart(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("single-play-to-end-pass", self.result.stdout)

    def test_loop_mode_still_restarts(self) -> None:
        self.assertIn("loop-restart-pass", self.result.stdout)


    def test_single_completion_can_replay_on_the_same_player(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("single-replay-same-player-pass", self.result.stdout)

    def test_startsilent_and_ready_do_not_autoplay(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("startsilent-ready-host-resume-pass", self.result.stdout)

    def test_repeated_play_resets_single_progress(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("repeated-play-restarts-single-pass", self.result.stdout)

    def test_host_pause_is_independent_of_author_pause(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("author-pause-and-host-pause-independent-pass", self.result.stdout)

    def test_stop_rewinds_and_can_replay(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("stop-rewinds-and-replays-pass", self.result.stdout)

    def test_invalid_batches_have_no_partial_side_effects(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("atomic-command-rejection-pass", self.result.stdout)

    def test_commands_apply_in_author_order(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("ordered-author-commands-pass", self.result.stdout)

    def test_teardown_rejects_and_cannot_restart(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("teardown-rejects-and-does-not-revive-pass", self.result.stdout)

    def test_initial_host_pause_retains_autoplay_intent(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("initial-host-pause-retains-autoplay-intent-pass", self.result.stdout)

    def test_host_suspension_keeps_author_repeat_semantics(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("host-suspension-preserves-author-repeat-semantics-pass", self.result.stdout)

    def test_master_gain_and_mute_are_preserved(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("gain-and-mute-contract-pass", self.result.stdout)

    def test_layer_retirement_stops_only_its_source(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("layer-retirement-stops-only-its-source-pass", self.result.stdout)

if __name__ == "__main__":
    unittest.main()
