#!/usr/bin/env python3
"""Texture-animation wrappers stay inert while authored atlases use scene time."""

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
    SOURCE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SOURCE_ROOT / "Rendering/SceneMetalPipeline.swift",
    SOURCE_ROOT / "Rendering/SceneSourceUpdateTransaction.swift",
    SOURCE_ROOT / "Rendering/SceneSpriteAnimation.swift",
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
        let atlasSceneTimes: [Float] = [0, 0.999, 1, 1.999, 2, 2.999, 3, 4]
        let atlasOrigins = atlasSceneTimes.map {
            atlasAnimation.transform(at: $0).origin.x
        }

        let payload: [String: Any] = [
            "parsedCount": parsed.count,
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
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
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
                check=True,
                cwd=REPOSITORY_ROOT,
                env=env,
                capture_output=True,
                text=True,
            )

        payload = json.loads(result.stdout)
        self.assertEqual(payload["parsedCount"], 1)
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


if __name__ == "__main__":
    unittest.main()
