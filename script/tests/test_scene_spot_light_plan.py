#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SCENE_ROOT / "Format/SceneTimelineAnimation.swift",
    SCENE_ROOT / "Format/SceneTimelineEvaluator.swift",
    SCENE_ROOT / "Format/SceneSpotLightDefinition.swift",
    SCENE_ROOT / "Rendering/SceneSpotLightPlan.swift",
]


HARNESS = r'''
import Foundation

enum SceneDocument {
    struct SceneObjectTimeline {
        enum Host { case angles, alpha }
        let host: Host
        let animation: SceneTimelineAnimation
    }
}

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let contentKind: String
        let spotLight: SceneSpotLightDefinition?
        let visible: Bool?
        let parentID: Int?
        let childLayerIDs: [Int]
        let dependencyLayerIDs: [Int]
        let effects: [Int]
        let hasInlineScript: Bool
        let anglesXYZ: [Float]?
        let timelines: [SceneDocument.SceneObjectTimeline]
    }
}

@main
enum Harness {
    static func frame(_ index: Double, _ value: Double) -> SceneTimelineKeyframe {
        .init(
            frame: index,
            value: value,
            back: nil,
            front: nil,
            locksAngle: true,
            locksLength: true
        )
    }

    static func animation(
        mode: SceneTimelineMode = .mirror,
        relative: Bool = true
    ) -> SceneTimelineAnimation {
        .init(
            lanes: [
                [frame(0, 0), frame(210, 0)],
                [frame(0, 0), frame(210, 0)],
                [frame(0, 0), frame(210, -1.3089924)],
            ],
            options: .init(
                fps: 30,
                length: 210,
                mode: mode,
                startsPaused: false,
                wrapsLoop: false,
                smoothing: nil,
                stiffness: nil,
                parent: nil,
                children: []
            ),
            isRelative: relative,
            previewValue: nil
        )
    }

    static func definition(
        kind: String = "lspot",
        outerCone: Float = 5.72
    ) -> SceneSpotLightDefinition {
        .init(
            kind: kind,
            colorRGB: [0.34118, 0.36078, 0.49804],
            intensity: 80,
            radius: 3_000,
            innerConeDegrees: 1.87,
            outerConeDegrees: outerCone,
            density: 3.93,
            exponent: 2.68,
            volumetricsExponent: 2.82,
            castsVolumetrics: true,
            castsShadow: true,
            isSolid: true
        )
    }

    static func layer(
        id: Int,
        light: SceneSpotLightDefinition? = definition(),
        animation: SceneTimelineAnimation = animation(),
        hasInlineScript: Bool = false
    ) -> SceneRenderDescriptor.Layer {
        .init(
            id: id,
            contentKind: "spotLight",
            spotLight: light,
            visible: true,
            parentID: nil,
            childLayerIDs: [],
            dependencyLayerIDs: [],
            effects: [],
            hasInlineScript: hasInlineScript,
            anglesXYZ: [0, 0, 2.35619],
            timelines: [.init(host: .angles, animation: animation)]
        )
    }

    static func main() throws {
        let first = SceneSpotLightPlan(layer: layer(id: 253))
        let second = SceneSpotLightPlan(layer: layer(id: 999))
        let parsed = SceneSpotLightDefinition.parse([
            "light": "lspot",
            "color": ["script": "color.js", "value": "0.1 0.2 0.3"],
            "intensity": ["user": "strength", "value": 80],
            "radius": 1437.12,
            "innercone": 1.87,
            "outercone": 2.91,
            "density": 3.93,
            "exponent": 2.68,
            "volumetricsexponent": 2.82,
            "castvolumetrics": true,
            "castshadow": ["user": "shadow", "value": true],
            "solid": true,
        ])
        let angles = [0.0, 3.5, 7.0, 10.5, 14.0].compactMap {
            first?.authoredAngle(at: $0)
        }
        let result: [String: Any] = [
            "parsed": parsed?.kind == "lspot"
                && parsed?.colorRGB == [0.1, 0.2, 0.3]
                && parsed?.intensity == 80
                && parsed?.outerConeDegrees == 2.91
                && parsed?.castsShadow == true,
            "sharedIDsAccepted": first != nil && second != nil,
            "mirrorAngles": angles,
            "loopRejected": SceneSpotLightPlan(
                layer: layer(id: 1, animation: animation(mode: .loop))
            ) == nil,
            "absoluteRejected": SceneSpotLightPlan(
                layer: layer(id: 1, animation: animation(relative: false))
            ) == nil,
            "wideConeRejected": SceneSpotLightPlan(
                layer: layer(id: 1, light: definition(outerCone: 20))
            ) == nil,
            "scriptRejected": SceneSpotLightPlan(
                layer: layer(id: 1, hasInlineScript: true)
            ) == nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneSpotLightPlanTests(unittest.TestCase):
    def test_strict_profile_and_relative_mirror_clock(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="scene-spot-light-plan-") as directory:
            temporary = Path(directory)
            harness = temporary / "Harness.swift"
            binary = temporary / "scene-spot-light-plan"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                ["swiftc", "-parse-as-library", *(str(path) for path in SOURCES), str(harness), "-o", str(binary)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
        result = json.loads(completed.stdout)
        self.assertTrue(result["parsed"], result)
        self.assertTrue(result["sharedIDsAccepted"], result)
        self.assertTrue(result["loopRejected"], result)
        self.assertTrue(result["absoluteRejected"], result)
        self.assertTrue(result["wideConeRejected"], result)
        self.assertTrue(result["scriptRejected"], result)
        angles = result["mirrorAngles"]
        self.assertEqual(len(angles), 5, result)
        self.assertAlmostEqual(angles[0], angles[4], places=4)
        self.assertAlmostEqual(angles[1], angles[3], places=4)
        self.assertLess(angles[2], angles[1])


if __name__ == "__main__":
    unittest.main()
