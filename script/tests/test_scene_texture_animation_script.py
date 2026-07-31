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
    SOURCE_ROOT / "Runtime/SceneTextureAnimationPlaybackPlan.swift",
    SOURCE_ROOT / "Runtime/SceneTextureAnimationScriptCompiler.swift",
    SOURCE_ROOT / "Resources/SceneTextureAnimationPlaybackClock.swift",
]

HARNESS = r'''
import Foundation

@main
enum Harness {
    static let verifiedHash =
        "a21a7d4bf2fefdf0e8694f4c83dcf224ff6f8a95eec94136f399b6a679541a3b"

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
            initialDelay: 1.5,
            minimumDelay: 0,
            maximumDelay: 2
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

        let payload: [String: Any] = [
            "parsedCount": parsed.count,
            "host": parsed[0].host,
            "keys": parsed[0].wrapperKeys,
            "user": parsed[0].user?.stringValue ?? "missing",
            "initialDelay": plan.initialDelay,
            "delayBounds": [plan.minimumDelay, plan.maximumDelay],
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
            "firstFrames": firstFrames,
            "secondFrames": secondFrames,
            "recreatedDeterministic": firstFrames == recreatedFrames,
            "instancesDiffer": firstFrames != secondFrames,
            "regressedFrame": regressedFrame,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
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
            subprocess.run(
                [
                    "swiftc",
                    *map(str, SWIFT_SOURCES),
                    str(harness_path),
                    "-o",
                    str(executable_path),
                ],
                check=True,
                cwd=REPOSITORY_ROOT,
                env=env,
                capture_output=True,
                text=True,
            )
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
        self.assertEqual(payload["firstFrames"][:3], [0, 0, 0])
        self.assertEqual(payload["secondFrames"][:7], [0, 0, 0, 0, 0, 0, 0])
        self.assertTrue(payload["recreatedDeterministic"])
        self.assertTrue(payload["instancesDiffer"])
        self.assertEqual(payload["regressedFrame"], 0)


if __name__ == "__main__":
    unittest.main()
