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
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Timeline/SceneTimelineEvaluator.swift",
    SCENE_ROOT / "Format/SceneSpotLightDefinition.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/SceneSpotLightPlan.swift",
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
        let layerIndex: Int
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

enum SceneDynamicLayerField: Hashable {
    case intensity
}

enum SceneDynamicTarget: Hashable {
    case layer(layerID: Int, field: SceneDynamicLayerField)
}

enum SceneScriptBindingPathComponent: Equatable {
    case key(String)
    case index(Int)
}

struct SceneScriptBindingOwner {
    enum Kind { case object, effect }
    let kind: Kind
    let objectIndex: Int?
    let objectID: Int?
}

struct SceneScriptSourceEvidenceIR {
    let owner: SceneScriptBindingOwner
    let targetPath: [SceneScriptBindingPathComponent]
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
        visible: Bool = true,
        scriptHost: String? = nil
    ) -> SceneRenderDescriptor.Layer {
        .init(
            id: id,
            layerIndex: 0,
            contentKind: "spotLight",
            spotLight: light,
            visible: visible,
            parentID: nil,
            childLayerIDs: [],
            dependencyLayerIDs: [],
            effects: [],
            hasInlineScript: scriptHost != nil,
            anglesXYZ: [0, 0, 2.35619],
            timelines: [.init(host: .angles, animation: animation)]
        )
    }

    static func sourceEvidence(
        id: Int,
        host: String
    ) -> SceneScriptSourceEvidenceIR {
        .init(
            owner: .init(kind: .object, objectIndex: 0, objectID: id),
            targetPath: [.key("objects"), .index(0), .key(host)]
        )
    }

    static func scriptedPlan(
        id: Int,
        host: String,
        instantiatedTargets: Set<SceneDynamicTarget>? = nil,
        extraEvidence: [SceneScriptSourceEvidenceIR] = []
    ) -> SceneSpotLightPlan? {
        SceneSpotLightPlan(
            layer: layer(id: id, scriptHost: host),
            instantiatedSceneScriptTargets: instantiatedTargets ?? [
                .layer(layerID: id, field: .intensity),
            ],
            scriptSourceEvidence: [sourceEvidence(id: id, host: host)]
                + extraEvidence
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
            "supportedIntensityScriptAccepted": SceneSpotLightPlan(
                layer: layer(id: 1, scriptHost: "intensity"),
                instantiatedSceneScriptTargets: [
                    .layer(layerID: 1, field: .intensity),
                ],
                scriptSourceEvidence: [sourceEvidence(id: 1, host: "intensity")]
            ) != nil,
            "caseVariantRejected": scriptedPlan(id: 2, host: "Intensity") == nil,
            "nestedScriptRejected": scriptedPlan(
                id: 3,
                host: "intensity",
                extraEvidence: [
                    .init(
                        owner: .init(
                            kind: .object,
                            objectIndex: 0,
                            objectID: 3
                        ),
                        targetPath: [
                            .key("objects"), .index(0), .key("light"),
                            .key("nested"),
                        ]
                    ),
                ]
            ) == nil,
            "uninstantiatedIntensityRejected": scriptedPlan(
                id: 7,
                host: "intensity",
                instantiatedTargets: []
            ) == nil,
            "otherLayerTargetRejected": scriptedPlan(
                id: 8,
                host: "intensity",
                instantiatedTargets: [
                    .layer(layerID: 999, field: .intensity),
                ]
            ) == nil,
            "evidenceWithoutInlineMarkerRejected": SceneSpotLightPlan(
                layer: layer(id: 9),
                instantiatedSceneScriptTargets: [
                    .layer(layerID: 9, field: .intensity),
                ],
                scriptSourceEvidence: [
                    sourceEvidence(id: 9, host: "intensity"),
                ]
            ) == nil,
            "unwiredColorScriptRejected": scriptedPlan(
                id: 4, host: "color"
            ) == nil,
            "unwiredVisibilityScriptRejected": scriptedPlan(
                id: 5, host: "visible"
            ) == nil,
            "unsupportedScriptRejected": scriptedPlan(
                id: 6, host: "radius"
            ) == nil,
            "authoredHiddenAccepted": SceneSpotLightPlan(
                layer: layer(id: 1, visible: false)
            ) != nil,
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
        self.assertTrue(result["supportedIntensityScriptAccepted"], result)
        self.assertTrue(result["caseVariantRejected"], result)
        self.assertTrue(result["nestedScriptRejected"], result)
        self.assertTrue(result["uninstantiatedIntensityRejected"], result)
        self.assertTrue(result["otherLayerTargetRejected"], result)
        self.assertTrue(result["evidenceWithoutInlineMarkerRejected"], result)
        self.assertTrue(result["unwiredColorScriptRejected"], result)
        self.assertTrue(result["unwiredVisibilityScriptRejected"], result)
        self.assertTrue(result["unsupportedScriptRejected"], result)
        self.assertTrue(result["authoredHiddenAccepted"], result)
        angles = result["mirrorAngles"]
        self.assertEqual(len(angles), 5, result)
        self.assertAlmostEqual(angles[0], angles[4], places=4)
        self.assertAlmostEqual(angles[1], angles[3], places=4)
        self.assertLess(angles[2], angles[1])


if __name__ == "__main__":
    unittest.main()
