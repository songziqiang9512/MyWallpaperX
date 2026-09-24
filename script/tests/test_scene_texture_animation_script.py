#!/usr/bin/env python3
"""Shared SceneScript TextureAnimation control over authored TEX playback."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift",
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
    SOURCE_ROOT / "Format/SceneTexDataReader.swift",
    SOURCE_ROOT / "Format/SceneTexContainer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneMetalPipeline.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneSourceUpdateTransaction.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Animation/SceneSpriteAnimation.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Animation/SceneTextureAnimationControl.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Animation/SceneTextureAnimationPlaybackRuntime.swift",
]

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let root: [String: Any] = [
            "visible": [
                "script": "self-authored-fixture",
                "scriptproperties": [
                    "initialDelay": 0.5,
                    "maxDelay": 0.0,
                    "minDelay": 1.5,
                ],
                "user": "fireworks",
                "value": true,
            ],
        ]
        let parsed = SceneTextureAnimationScriptDefinition.parseLayerProperties(in: root)
        let atlasFrames = [
            spriteFrame(originX: 0),
            spriteFrame(originX: 0.25),
            spriteFrame(originX: 0.5),
        ]
        let atlasAnimation = SceneSpriteAnimation(frames: atlasFrames)!
        let invalidTimelines: [[Float]] = [
            [.greatestFiniteMagnitude, .greatestFiniteMagnitude],
            [16_777_216, 1],
        ]
        let invalidTimelinesRejected = invalidTimelines.map { durations in
            SceneSpriteAnimation(frames: durations.map {
                spriteFrame(originX: 0, duration: $0)
            }) == nil
        }
        let defaultDurationAnimation = SceneSpriteAnimation(frames: [
            spriteFrame(originX: 0, duration: 0),
            spriteFrame(originX: 0.25, duration: 0),
        ])!
        let nominalAnimation = SceneSpriteAnimation(
            frames: atlasFrames,
            textureSize: SIMD2(400, 200),
            nominalFrameSize: SIMD2(100, 50)
        )!
        let rotatedFrame = SceneTexContainer.SpriteFrame(
            imageIndex: 0,
            duration: 1,
            origin: .zero,
            xAxis: SIMD2(0, 0.5),
            yAxis: SIMD2(0.125, 0)
        )
        let rawAxisAnimation = SceneSpriteAnimation(
            frames: [rotatedFrame],
            textureSize: SIMD2(400, 200)
        )!
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "scene-sprite-aspect-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(
            at: temporary,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporary) }
        let textureURL = temporary.appendingPathComponent("atlas.tex")
        let sidecarURL = URL(fileURLWithPath: textureURL.path + "-json")
        var invalidFrameCountsRejected: [Bool] = []
        var invalidSidecarPlaybackPreserved: [Bool] = []
        let atlasContainer = SceneTexContainer(
            format: 0, flags: 4, textureWidth: 400, textureHeight: 200,
            imageWidth: 400, imageHeight: 200, containerVersion: .texb0002,
            freeImageFormat: -1, isVideoMp4: false,
            images: [.init(mips: [.init(width: 400, height: 200, data: Data())])],
            spriteFrames: atlasFrames
        )
        for count in [Double.greatestFiniteMagnitude, Double(Int.max), -1, 0, 3.5] {
            let invalid: [String: Any] = [
                "spritesheetsequences": [["frames": count, "width": 100, "height": 50]],
            ]
            try JSONSerialization.data(withJSONObject: invalid).write(to: sidecarURL)
            invalidFrameCountsRejected.append(SceneSpriteAnimation.nominalFrameSize(
                from: textureURL, expectedFrameCount: 3
            ) == nil)
            let fallback = SceneSpriteAnimation(container: atlasContainer, sourceURL: textureURL)
            invalidSidecarPlaybackPreserved.append(
                fallback?.aspectRatio(forFrameAt: 0) == 0.5
                    && fallback?.transform(at: 1).origin.x == 0.25
                    && fallback?.duration == 3
            )
        }
        let sidecar: [String: Any] = [
            "spritesheetsequences": [["frames": 3, "width": 100, "height": 50]],
        ]
        try JSONSerialization.data(withJSONObject: sidecar).write(to: sidecarURL)
        let acceptedSidecar = SceneSpriteAnimation.nominalFrameSize(
            from: textureURL,
            expectedFrameCount: 3
        )
        let mismatchedSidecar = SceneSpriteAnimation.nominalFrameSize(
            from: textureURL,
            expectedFrameCount: 2
        )
        let invalidURL = temporary.appendingPathComponent("invalid.tex")
        let invalidSidecar: [String: Any] = [
            "spritesheetsequences": [["frames": 3, "width": -100, "height": -50]],
        ]
        try JSONSerialization.data(withJSONObject: invalidSidecar).write(
            to: URL(fileURLWithPath: invalidURL.path + "-json")
        )
        let invalidDimensionsRejected = SceneSpriteAnimation.nominalFrameSize(
            from: invalidURL,
            expectedFrameCount: 3
        ) == nil
        let booleanURL = temporary.appendingPathComponent("boolean.tex")
        let booleanSidecar: [String: Any] = [
            "spritesheetsequences": [["frames": true, "width": 100, "height": 50]],
        ]
        try JSONSerialization.data(withJSONObject: booleanSidecar).write(
            to: URL(fileURLWithPath: booleanURL.path + "-json")
        )
        let booleanRejected = SceneSpriteAnimation.nominalFrameSize(
            from: booleanURL,
            expectedFrameCount: 1
        ) == nil
        let atlasSceneTimes: [Float] = [0, 0.999, 1, 1.999, 2, 2.999, 3, 4]
        let atlasOrigins = atlasSceneTimes.map {
            atlasAnimation.transform(at: $0).origin.x
        }
        let runtime = SceneTextureAnimationPlaybackRuntime()
        let secondAnimation = SceneSpriteAnimation(frames: atlasFrames)!
        let conflictingAnimation = SceneSpriteAnimation(
            frames: [spriteFrame(originX: 0), spriteFrame(originX: 0.25)]
        )!
        let firstRegistration = runtime.register(
            layerID: 10, sourceIdentity: "models/shared.tex",
            animation: atlasAnimation
        )
        let secondRegistration = runtime.register(
            layerID: 11, sourceIdentity: "models/shared.tex",
            animation: secondAnimation
        )
        let repeatedRegistration = runtime.register(
            layerID: 10, sourceIdentity: "models/shared.tex",
            animation: atlasAnimation
        )
        let conflict = runtime.register(
            layerID: 10, sourceIdentity: "models/other.tex",
            animation: conflictingAnimation
        )
        let sharedSourceConflict = runtime.register(
            layerID: 12, sourceIdentity: "models/shared.tex",
            animation: conflictingAnimation
        )
        let variableAnimation = SceneSpriteAnimation(frames: [
            spriteFrame(originX: 0, duration: 0.5),
            spriteFrame(originX: 0.25, duration: 1.5),
            spriteFrame(originX: 0.5, duration: 2),
        ])!
        let variableRegistration = runtime.register(
            layerID: 13, sourceIdentity: "models/variable.tex",
            animation: variableAnimation
        )
        let variableSetFrame = runtime.apply([
            .init(layerID: 13, action: .setFrame(1)),
        ], sceneTime: 0)
        let variableAtOne = runtime.snapshots(sceneTime: 1)
        let sharedAtHalf = runtime.snapshots(sceneTime: 0.5)
        let boundaryTimes = [Double(1).nextDown, 1, Double(1).nextUp,
                             Double(3).nextDown, 3, Double(3).nextUp, -Double.ulpOfOne]
        let boundaryAgreement = boundaryTimes.map { time in
            let snapshot = runtime.snapshots(sceneTime: time)[11]!
            let playback = runtime.playbackTimes(layerIDs: [11], sceneTime: time)[11]!
            let sampled = SceneSpriteAnimation.frameIndex(
                at: playback, duration: atlasAnimation.duration,
                frameEndTimes: atlasAnimation.frameEndTimes
            )
            return snapshot.currentFrame == Double(sampled)
                && snapshot.sharedCurrentFrame == Double(sampled)
        }
        var localBoundaryAgreement: [Bool] = []
        for rate: Double in [-1, 1] {
            let local = SceneTextureAnimationPlaybackRuntime()
            _ = local.register(layerID: 1, sourceIdentity: "local", animation: atlasAnimation)
            _ = local.apply([
                .init(layerID: 1, action: .setFrame(0)),
                .init(layerID: 1, action: .setRate(rate)),
            ], sceneTime: 0)
            for time in boundaryTimes {
                let playback = local.playbackTimes(layerIDs: [1], sceneTime: time)[1]!
                let rendered = SceneSpriteAnimation.frameIndex(
                    at: playback, duration: atlasAnimation.duration,
                    frameEndTimes: atlasAnimation.frameEndTimes
                )
                localBoundaryAgreement.append(
                    local.snapshots(sceneTime: time)[1]!.currentFrame == Double(rendered)
                )
            }
            _ = local.apply([.init(layerID: 1, action: .pause)], sceneTime: Double(1).nextDown)
            let pausedPlayback = local.playbackTimes(layerIDs: [1], sceneTime: 20)[1]!
            localBoundaryAgreement.append(
                local.snapshots(sceneTime: 20)[1]!.currentFrame == Double(
                    SceneSpriteAnimation.frameIndex(
                        at: pausedPlayback, duration: atlasAnimation.duration,
                        frameEndTimes: atlasAnimation.frameEndTimes
                    )
                )
            )
        }
        let setFrame = runtime.apply([
            .init(layerID: 10, action: .setFrame(1)),
        ], sceneTime: 0.5)
        let detachedAtOne = runtime.snapshots(sceneTime: 1)
        let pause = runtime.apply([
            .init(layerID: 10, action: .pause),
        ], sceneTime: 1)
        let pausedAtThree = runtime.snapshots(sceneTime: 3)
        let reverse = runtime.apply([
            .init(layerID: 10, action: .setRate(-2)),
            .init(layerID: 10, action: .play),
        ], sceneTime: 3)
        let reversedAtQuarter = runtime.snapshots(sceneTime: 3.25)
        let beforeAtomicFailure = runtime.snapshots(sceneTime: 3.25)
        let atomicFailure = runtime.apply([
            .init(layerID: 10, action: .setFrame(0)),
            .init(layerID: 999, action: .play),
        ], sceneTime: 3.25)
        let fractionalFrame = runtime.apply([
            .init(layerID: 10, action: .setFrame(0.25)),
        ], sceneTime: 3.25)
        let afterAtomicFailure = runtime.snapshots(sceneTime: 3.25)
        let stop = runtime.apply([
            .init(layerID: 10, action: .stop),
        ], sceneTime: 3.25)
        let stopped = runtime.snapshots(sceneTime: 8)
        let join = runtime.apply([
            .init(layerID: 10, action: .join),
        ], sceneTime: 8)
        let joined = runtime.snapshots(sceneTime: 8)
        let playbackTimes = runtime.playbackTimes(
            layerIDs: [10, 11],
            sceneTime: 8
        )

        let payload: [String: Any] = [
            "parsedCount": parsed.count,
            "invalidTimelinesRejected": invalidTimelinesRejected,
            "zeroDurationPreserved": defaultDurationAnimation.duration.isFinite
                && defaultDurationAnimation.frameEndTimes[1] > defaultDurationAnimation.frameEndTimes[0],
            "boundaryAgreement": boundaryAgreement,
            "localBoundaryAgreement": localBoundaryAgreement,
            "boundaryFrames": boundaryTimes.map {
                runtime.snapshots(sceneTime: $0)[11]!.currentFrame
            },
            "host": parsed[0].host,
            "source": parsed[0].source,
            "keys": parsed[0].wrapperKeys,
            "user": parsed[0].user?.stringValue ?? "missing",
            "authoredValue": parsed[0].authoredValue?.boolValue ?? false,
            "initialDelay": parsed[0].properties["initialDelay"]?.numberValue ?? -1,
            "delayBounds": [
                parsed[0].properties["maxDelay"]?.numberValue ?? -1,
                parsed[0].properties["minDelay"]?.numberValue ?? -1,
            ],
            "atlasSceneTimes": atlasSceneTimes,
            "atlasOrigins": atlasOrigins,
            "nominalAspects": atlasFrames.indices.map {
                nominalAnimation.aspectRatio(forFrameAt: $0)
            },
            "rotatedRawAspect": rawAxisAnimation.aspectRatio(forFrameAt: 0),
            "sidecarAccepted": acceptedSidecar.map { [$0.x, $0.y] } ?? [],
            "sidecarMismatchRejected": mismatchedSidecar == nil,
            "sidecarInvalidDimensionsRejected": invalidDimensionsRejected,
            "sidecarBooleanRejected": booleanRejected,
            "sidecarInvalidFrameCountsRejected": invalidFrameCountsRejected,
            "invalidSidecarPlaybackPreserved": invalidSidecarPlaybackPreserved,
            "registrationsAccepted": isSuccess(firstRegistration)
                && isSuccess(secondRegistration)
                && isSuccess(repeatedRegistration),
            "conflictRejected": isFailure(conflict)
                && isFailure(sharedSourceConflict),
            "variableAccepted": isSuccess(variableRegistration)
                && isSuccess(variableSetFrame),
            "variableAtOne": variableAtOne[13]?.currentFrame ?? -1,
            "sharedAtHalf": [
                sharedAtHalf[10]?.currentFrame ?? -1,
                sharedAtHalf[11]?.currentFrame ?? -1,
            ],
            "setFrameAccepted": isSuccess(setFrame),
            "detachedAtOne": [
                detachedAtOne[10]?.currentFrame ?? -1,
                detachedAtOne[11]?.currentFrame ?? -1,
            ],
            "pauseAccepted": isSuccess(pause),
            "pausedAtThree": pausedAtThree[10]?.currentFrame ?? -1,
            "reverseAccepted": isSuccess(reverse),
            "reversedAtQuarter": reversedAtQuarter[10]?.currentFrame ?? -1,
            "atomicFailureRejected": isFailure(atomicFailure)
                && beforeAtomicFailure == afterAtomicFailure,
            "fractionalFrameRejected": isFailure(fractionalFrame),
            "stopAccepted": isSuccess(stop),
            "stopped": [
                stopped[10]?.currentFrame ?? -1,
                stopped[10]?.isPlaying == true ? 1 : 0,
            ],
            "joinAccepted": isSuccess(join),
            "joined": [
                joined[10]?.currentFrame ?? -1,
                joined[11]?.currentFrame ?? -1,
                joined[10]?.isPlaying == true ? 1 : 0,
            ],
            "playbackTimes": [
                playbackTimes[10] ?? -1,
                playbackTimes[11] ?? -1,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func spriteFrame(
        originX: Float,
        duration: Float = 1
    ) -> SceneTexContainer.SpriteFrame {
        .init(
            imageIndex: 0,
            duration: duration,
            origin: SIMD2(originX, 0),
            xAxis: SIMD2(0.25, 0),
            yAxis: SIMD2(0, 1)
        )
    }

    static func isSuccess<T, E>(_ result: Result<T, E>) -> Bool {
        if case .success = result { return true }
        return false
    }

    static func isFailure<T, E>(_ result: Result<T, E>) -> Bool {
        if case .failure = result { return true }
        return false
    }
}
'''


class SceneTextureAnimationScriptTests(unittest.TestCase):
    def test_atlas_transform_reuses_prepared_frame_end_times(self) -> None:
        source = (
            REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Animation/SceneSpriteAnimation.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("var upper = frameEndTimes.count", source)
        self.assertIn("if remaining < frameEndTimes[middle]", source)
        self.assertNotIn("for frame in frames", source)

    def test_wrapper_parsing_and_scene_time_atlas_playback(self) -> None:
        with tempfile.TemporaryDirectory(prefix="scene-texture-animation-") as temp_dir:
            temp_path = Path(temp_dir)
            harness_path = temp_path / "Harness.swift"
            executable_path = temp_path / "harness"
            harness_path.write_text(HARNESS, encoding="utf-8")
            env = os.environ.copy()
            env["CLANG_MODULE_CACHE_PATH"] = str(temp_path / "clang-cache")
            env["SWIFT_MODULECACHE_PATH"] = str(temp_path / "swift-cache")
            compilation = subprocess.run(
                [
                    "swiftc",
                    *map(str, SWIFT_SOURCES),
                    str(harness_path),
                    "-o",
                    str(executable_path),
                ],
                cwd=REPOSITORY_ROOT,
                env=env,
                capture_output=True,
                text=True,
            )
            if compilation.returncode != 0:
                raise AssertionError(compilation.stderr)
            result = subprocess.run(
                [str(executable_path)],
                cwd=REPOSITORY_ROOT,
                env=env,
                capture_output=True,
                text=True,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["parsedCount"], 1)
        self.assertEqual(payload["invalidTimelinesRejected"], [True, True])
        self.assertTrue(payload["zeroDurationPreserved"])
        self.assertEqual(payload["boundaryAgreement"], [True] * 7)
        self.assertEqual(payload["localBoundaryAgreement"], [True] * 16)
        self.assertEqual(payload["boundaryFrames"], [1, 1, 1, 0, 0, 0, 0])
        self.assertEqual(payload["host"], "visible")
        self.assertEqual(payload["source"], "self-authored-fixture")
        self.assertEqual(payload["keys"], ["script", "scriptproperties", "user", "value"])
        self.assertEqual(payload["user"], "fireworks")
        self.assertTrue(payload["authoredValue"])
        self.assertEqual(payload["initialDelay"], 0.5)
        self.assertEqual(payload["delayBounds"], [0, 1.5])
        self.assertEqual(
            [round(value, 3) for value in payload["atlasSceneTimes"]],
            [0, 0.999, 1, 1.999, 2, 2.999, 3, 4],
        )
        self.assertEqual(payload["atlasOrigins"], [0, 0, 0.25, 0.25, 0.5, 0.5, 0, 0.25])
        self.assertEqual(payload["nominalAspects"], [2, 2, 2])
        self.assertEqual(payload["rotatedRawAspect"], 2)
        self.assertEqual(payload["sidecarAccepted"], [100, 50])
        self.assertTrue(payload["sidecarMismatchRejected"])
        self.assertTrue(payload["sidecarInvalidDimensionsRejected"])
        self.assertTrue(payload["sidecarBooleanRejected"])
        self.assertEqual(payload["sidecarInvalidFrameCountsRejected"], [True] * 5)
        self.assertEqual(payload["invalidSidecarPlaybackPreserved"], [True] * 5)
        self.assertTrue(payload["registrationsAccepted"])
        self.assertTrue(payload["conflictRejected"])
        self.assertTrue(payload["variableAccepted"])
        self.assertEqual(payload["variableAtOne"], 1)
        self.assertEqual(payload["sharedAtHalf"], [0, 0])
        self.assertTrue(payload["setFrameAccepted"])
        self.assertEqual(payload["detachedAtOne"], [1, 1])
        self.assertTrue(payload["pauseAccepted"])
        self.assertEqual(payload["pausedAtThree"], 1)
        self.assertTrue(payload["reverseAccepted"])
        self.assertEqual(payload["reversedAtQuarter"], 1)
        self.assertTrue(payload["atomicFailureRejected"])
        self.assertTrue(payload["fractionalFrameRejected"])
        self.assertTrue(payload["stopAccepted"])
        self.assertEqual(payload["stopped"], [0, 0])
        self.assertTrue(payload["joinAccepted"])
        self.assertEqual(payload["joined"], [2, 2, 1])
        self.assertEqual(payload["playbackTimes"], [2, 2])

    def test_single_clock_transaction_and_renderer_wiring(self) -> None:
        runtime = (
            REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Animation/SceneTextureAnimationPlaybackRuntime.swift"
        ).read_text(encoding="utf-8")
        host = (
            REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+FrameDriver.swift"
        ).read_text(encoding="utf-8")
        lifecycle = (
            REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+FrameDriverLifecycle.swift"
        ).read_text(encoding="utf-8")
        view = (REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift").read_text(
            encoding="utf-8"
        )
        renderer = (REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift").read_text(
            encoding="utf-8"
        )
        preflight = (
            REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneResolvedMaterialFramePreflight.swift"
        ).read_text(encoding="utf-8")

        self.assertNotIn("Timer(", runtime)
        self.assertNotIn("CADisplayLink", runtime)
        publication = host.index("sceneScriptTextureAnimationSnapshots")
        script_evaluation = host.index("let coordinatedSceneScript")
        submission_barrier = host.index("guard allSurfacesSubmitted")
        commit = host.index("commitSubmittedSceneFrame(", submission_barrier)
        self.assertLess(publication, script_evaluation)
        self.assertLess(submission_barrier, commit)
        self.assertIn("textureAnimationCommands: textureAnimationCommands", host)
        lifecycle_apply = lifecycle.index(
            "context.textureAnimationPlaybackRuntime.apply("
        )
        lifecycle_commit = lifecycle.index(
            "commitSceneScriptLayerPlan(", lifecycle_apply
        )
        self.assertLess(lifecycle_apply, lifecycle_commit)
        self.assertIn("spriteAnimationPlaybackTimes", view)
        self.assertNotIn(
            "layer.puppetMeshPath == nil, let animation = baseLoad.animation",
            view,
        )
        self.assertIn("if let animation = baseLoad.animation", view)
        self.assertIn("textureAnimationPlaybackRuntime.playbackTimes(", view)
        self.assertIn("spriteAnimationPlaybackTimes[layerID] else { continue }", view)
        self.assertIn("playbackTime: playbackTime", view)
        self.assertNotIn("Float(frameContext.sceneTime)", view)
        self.assertIn("spriteAnimationPlaybackTimes[layer.id] ?? 0", renderer)
        self.assertIn("spriteAnimationPlaybackTimes[layerID] ?? 0", preflight)


if __name__ == "__main__":
    unittest.main()
