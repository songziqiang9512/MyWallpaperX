#!/usr/bin/env python3
"""Strict texture-animation scripts must own independent, timer-free clocks."""

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
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
    SOURCE_ROOT / "Format/SceneTexDataReader.swift",
    SOURCE_ROOT / "Format/SceneTexContainer.swift",
    SOURCE_ROOT / "Runtime/SceneTextureAnimationPlaybackPlan.swift",
    SOURCE_ROOT / "Runtime/SceneTextureAnimationScriptCompiler.swift",
    SOURCE_ROOT / "Resources/SceneTextureAnimationPlaybackClock.swift",
    SOURCE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SOURCE_ROOT / "Rendering/SceneMetalPipeline.swift",
    SOURCE_ROOT / "Rendering/SceneSourceUpdateTransaction.swift",
    SOURCE_ROOT / "Rendering/SceneSpriteAnimation.swift",
]

HARNESS = r'''
import Foundation

@main
enum Harness {
    static let verifiedHash =
        "a21a7d4bf2fefdf0e8694f4c83dcf224ff6f8a95eec94136f399b6a679541a3b"
    static let timeOfDayHash =
        "152842f1740fe7672fc2275d2eda3b1039da0ab6ee3da02ffab53e4e5de17cbf"

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
        let plan = SceneTextureAnimationScriptCompiler.compileVerifiedProfile(
            layerID: 41,
            definition: parsed[0],
            sourceSHA256: verifiedHash
        )!
        let secondPlan = SceneTextureAnimationPlaybackPlan(
            layerID: 72,
            sourceSHA256: verifiedHash,
            mode: .delayedLoop(initialDelay: 1.5, minimumDelay: 0, maximumDelay: 2)
        )
        let malformedShape = SceneTextureAnimationScriptDefinition(
            host: "visible",
            source: "self-authored-fixture",
            properties: parsed[0].properties,
            user: .string("fireworks"),
            authoredValue: .bool(true),
            wrapperKeys: ["script", "scriptproperties", "user", "value", "extra"]
        )
        let wrongUser = SceneTextureAnimationScriptDefinition(
            host: "visible",
            source: "self-authored-fixture",
            properties: parsed[0].properties,
            user: .string("other-profile"),
            authoredValue: .bool(true),
            wrapperKeys: parsed[0].wrapperKeys
        )
        let timeOfDayDefinition = SceneTextureAnimationScriptDefinition(
            host: "angles",
            source: "self-authored-time-of-day-fixture",
            properties: [
                "dayStart": .number(0),
                "nightStart": .number(12),
            ],
            user: nil,
            authoredValue: .string("0.00000 -0.00000 0.00000"),
            wrapperKeys: ["script", "scriptproperties", "value"]
        )
        let timeOfDayPlan = SceneTextureAnimationScriptCompiler.compileVerifiedProfile(
            layerID: 84,
            definition: timeOfDayDefinition,
            sourceSHA256: timeOfDayHash
        )!
        guard case let .timeOfDay(schedule) = timeOfDayPlan.mode else {
            fatalError("missing time-of-day mode")
        }
        var invalidTimeProperties = timeOfDayDefinition.properties
        invalidTimeProperties["nightStart"] = .number(25)
        let invalidTimeOfDayDefinition = SceneTextureAnimationScriptDefinition(
            host: timeOfDayDefinition.host,
            source: timeOfDayDefinition.source,
            properties: invalidTimeProperties,
            user: timeOfDayDefinition.user,
            authoredValue: timeOfDayDefinition.authoredValue,
            wrapperKeys: timeOfDayDefinition.wrapperKeys
        )

        var first = SceneTextureAnimationPlaybackClock(
            plan: plan,
            frameDurations: [0.1, 0.1, 0.1, 0.1]
        )
        var second = SceneTextureAnimationPlaybackClock(
            plan: secondPlan,
            frameDurations: [0.1, 0.1, 0.1, 0.1]
        )
        let phases: [Float] = [0, 0.49, 0.5, 0.61, 0.89, 1.0, 1.5, 1.61, 2.2, 3.4, 4.9, 7.3]
        let firstFrames = phases.map { first.frameIndex(at: $0) }
        let secondFrames = phases.map { second.frameIndex(at: $0) }

        var recreated = SceneTextureAnimationPlaybackClock(
            plan: plan,
            frameDurations: [0.1, 0.1, 0.1, 0.1]
        )
        let recreatedFrames = phases.map { recreated.frameIndex(at: $0) }
        let regressedFrame = first.frameIndex(at: 0.25)
        var timeOfDayClock = SceneTextureAnimationPlaybackClock(
            plan: timeOfDayPlan,
            frameDurations: [1, 1, 1]
        )
        let utcTimeZone = TimeZone(secondsFromGMT: 0)!
        let timeOfDayFrames = [
            timeOfDayClock.frameIndex(
                at: 0,
                wallDate: utcDate(day: 28, hour: 11, minute: 59),
                timeZone: utcTimeZone
            ),
            timeOfDayClock.frameIndex(
                at: 1,
                wallDate: utcDate(day: 28, hour: 11, minute: 59),
                timeZone: utcTimeZone
            ),
            timeOfDayClock.frameIndex(
                at: 2,
                wallDate: utcDate(day: 28, hour: 12, minute: 0),
                timeZone: utcTimeZone
            ),
            timeOfDayClock.frameIndex(
                at: 3,
                wallDate: utcDate(day: 28, hour: 18, minute: 0),
                timeZone: utcTimeZone
            ),
            timeOfDayClock.frameIndex(
                at: 4,
                wallDate: utcDate(day: 29, hour: 0, minute: 0),
                timeZone: utcTimeZone
            ),
            timeOfDayClock.frameIndex(
                at: 0.5,
                wallDate: utcDate(day: 29, hour: 0, minute: 1),
                timeZone: utcTimeZone
            ),
        ]
        let atlasFrames = [
            spriteFrame(originX: 0),
            spriteFrame(originX: 0.25),
            spriteFrame(originX: 0.5),
        ]
        let atlasAnimation = SceneSpriteAnimation(
            frames: atlasFrames,
            playbackPlan: timeOfDayPlan
        )!
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
        var atlasOrigins: [Float] = []
        atlasOrigins.append(atlasAnimation.transform(
            at: 0,
            wallDate: localDate(day: 28, hour: 11, minute: 59)
        ).origin.x)
        atlasOrigins.append(atlasAnimation.transform(
            at: 1,
            wallDate: localDate(day: 28, hour: 12, minute: 0)
        ).origin.x)
        atlasOrigins.append(atlasAnimation.transform(
            at: 2,
            wallDate: localDate(day: 28, hour: 18, minute: 0)
        ).origin.x)
        atlasOrigins.append(atlasAnimation.transform(
            at: 3,
            wallDate: localDate(day: 29, hour: 0, minute: 0)
        ).origin.x)
        atlasOrigins.append(atlasAnimation.transform(
            at: 0.5,
            wallDate: localDate(day: 29, hour: 0, minute: 1)
        ).origin.x)

        guard case let .delayedLoop(initialDelay, minimumDelay, maximumDelay) = plan.mode else {
            fatalError("missing delayed-loop mode")
        }

        let payload: [String: Any] = [
            "parsedCount": parsed.count,
            "host": parsed[0].host,
            "keys": parsed[0].wrapperKeys,
            "user": parsed[0].user?.stringValue ?? "missing",
            "initialDelay": initialDelay,
            "delayBounds": [minimumDelay, maximumDelay],
            "unknownHashRejected": SceneTextureAnimationScriptCompiler.compileVerifiedProfile(
                layerID: 41,
                definition: parsed[0],
                sourceSHA256: String(repeating: "0", count: 64)
            ) == nil,
            "shapeRejected": SceneTextureAnimationScriptCompiler.compileVerifiedProfile(
                layerID: 41,
                definition: malformedShape,
                sourceSHA256: verifiedHash
            ) == nil,
            "userRejected": SceneTextureAnimationScriptCompiler.compileVerifiedProfile(
                layerID: 41,
                definition: wrongUser,
                sourceSHA256: verifiedHash
            ) == nil,
            "timeOfDayPropertiesRejected":
                SceneTextureAnimationScriptCompiler.compileVerifiedProfile(
                    layerID: 84,
                    definition: invalidTimeOfDayDefinition,
                    sourceSHA256: timeOfDayHash
                ) == nil,
            "timeOfDaySchedule": [schedule.dayStartHour, schedule.nightStartHour],
            "timeOfDayFrames": timeOfDayFrames,
            "atlasOrigins": atlasOrigins,
            "nominalAspects": atlasFrames.indices.map {
                nominalAnimation.aspectRatio(forFrameAt: $0)
            },
            "rotatedRawAspect": rawAxisAnimation.aspectRatio(forFrameAt: 0),
            "sidecarAccepted": acceptedSidecar.map { [$0.x, $0.y] } ?? [],
            "sidecarMismatchRejected": mismatchedSidecar == nil,
            "sidecarInvalidDimensionsRejected": invalidDimensionsRejected,
            "sidecarBooleanRejected": booleanRejected,
            "firstFrames": firstFrames,
            "secondFrames": secondFrames,
            "recreatedDeterministic": firstFrames == recreatedFrames,
            "instancesDiffer": firstFrames != secondFrames,
            "regressedFrame": regressedFrame,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func utcDate(day: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: .init(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    static func localDate(day: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar.date(from: .init(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    static func spriteFrame(originX: Float) -> SceneTexContainer.SpriteFrame {
        .init(
            imageIndex: 0,
            duration: 1,
            origin: SIMD2(originX, 0),
            xAxis: SIMD2(0.25, 0),
            yAxis: SIMD2(0, 1)
        )
    }
}
'''


class SceneTextureAnimationScriptTests(unittest.TestCase):
    def test_strict_profile_and_instance_local_lifecycle(self) -> None:
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
                check=True,
                cwd=REPOSITORY_ROOT,
                env=env,
                capture_output=True,
                text=True,
            )

        payload = json.loads(result.stdout)
        self.assertEqual(payload["parsedCount"], 1)
        self.assertEqual(payload["host"], "visible")
        self.assertEqual(payload["keys"], ["script", "scriptproperties", "user", "value"])
        self.assertEqual(payload["user"], "fireworks")
        self.assertEqual(payload["initialDelay"], 0.5)
        self.assertEqual(payload["delayBounds"], [0, 1.5])
        self.assertTrue(payload["unknownHashRejected"])
        self.assertTrue(payload["shapeRejected"])
        self.assertTrue(payload["userRejected"])
        self.assertTrue(payload["timeOfDayPropertiesRejected"])
        self.assertEqual(payload["timeOfDaySchedule"], [0, 12])
        self.assertEqual(payload["timeOfDayFrames"], [0, 0, 2, 2, 1, 0])
        self.assertEqual(payload["atlasOrigins"], [0, 0.5, 0.5, 0.25, 0])
        self.assertEqual(payload["nominalAspects"], [2, 2, 2])
        self.assertEqual(payload["rotatedRawAspect"], 2)
        self.assertEqual(payload["sidecarAccepted"], [100, 50])
        self.assertTrue(payload["sidecarMismatchRejected"])
        self.assertTrue(payload["sidecarInvalidDimensionsRejected"])
        self.assertTrue(payload["sidecarBooleanRejected"])
        self.assertEqual(payload["firstFrames"][:3], [0, 0, 0])
        self.assertEqual(payload["secondFrames"][:7], [0, 0, 0, 0, 0, 0, 0])
        self.assertTrue(payload["recreatedDeterministic"])
        self.assertTrue(payload["instancesDiffer"])
        self.assertEqual(payload["regressedFrame"], 0)


if __name__ == "__main__":
    unittest.main()
