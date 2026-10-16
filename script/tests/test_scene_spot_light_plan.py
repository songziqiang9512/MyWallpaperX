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
    SCENE_ROOT / "Systems/Timeline/SceneTimelineEvaluator.swift",
    SCENE_ROOT / "Systems/Timeline/SceneTimelineRuntime.swift",
    SCENE_ROOT / "Systems/Timeline/SceneTimelinePlaybackRuntime.swift",
    SCENE_ROOT / "Systems/Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "Format/SceneSpotLightDefinition.swift",
    SCENE_ROOT / "Format/SceneDirectionalLightDefinition.swift",
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
        let name: String
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

// Prepared binding carriers only. Playback, additive evaluation and snapshot
// validation below compile their production owners, not harness algorithms.
struct SceneTimelineBinding {
    enum Composition { case absolute, additive }
    let definition: SceneDynamicTargetDefinition
    let animation: SceneTimelineAnimation
    let composition: Composition
    var target: SceneDynamicTarget { definition.target }
}

struct SceneTimelineProgram {
    let bindings: [SceneTimelineBinding]
    let diagnostics: [String]
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
        scriptHost: String? = nil,
        name: String = "Cone"
    ) -> SceneRenderDescriptor.Layer {
        .init(
            id: id,
            layerIndex: 0,
            name: name,
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

    static func binding(
        for layer: SceneRenderDescriptor.Layer
    ) -> SceneTimelineBinding {
        let angles = layer.anglesXYZ!
        return .init(
            definition: .init(
                target: .layer(layerID: layer.id, field: .angles),
                valueType: .vector3,
                authoredValue: .vector3(
                    Double(angles[0]), Double(angles[1]), Double(angles[2])
                )
            ),
            animation: layer.timelines[0].animation,
            composition: .additive
        )
    }

    static func mirrorAngles() -> [Float] {
        let input = layer(id: 253)
        let plan = SceneSpotLightPlan(layer: input)!
        let program = SceneTimelineProgram(
            bindings: [binding(for: input)], diagnostics: []
        )
        let runtime = SceneTimelinePlaybackRuntime(program: program)
        let definitions = SceneTimelineRuntime.mergedDefinitions(
            propertyDefinitions: [], timelineProgram: program
        )
        return [0.0, 3.5, 7.0, 10.5, 14.0].enumerated().map { index, time in
            let resolved = SceneDynamicSnapshotResolver().resolve(
                frameIndex: UInt64(index), generation: 1,
                definitions: definitions,
                timelineValues: runtime.values(sceneTime: time)
            )
            return plan.currentAngle(in: resolved.snapshot)
        }
    }

    static func playbackCase(id: Int, name: String) throws -> [String: Any] {
        let input = layer(id: id, name: name)
        let peer = layer(id: id + 9_000, name: name + " peer")
        let plan = SceneSpotLightPlan(layer: input)!
        let peerPlan = SceneSpotLightPlan(layer: peer)!
        let target = SceneDynamicTarget.layer(layerID: id, field: .angles)
        let program = SceneTimelineProgram(
            bindings: [binding(for: input), binding(for: peer)], diagnostics: []
        )
        let runtime = SceneTimelinePlaybackRuntime(program: program)
        let definitions = SceneTimelineRuntime.mergedDefinitions(
            propertyDefinitions: [], timelineProgram: program
        )
        let index = SceneDynamicSnapshotResolver.prepare(definitions: definitions)
        var validChain = true
        var frame: UInt64 = 0
        func sample(_ time: Double) -> (angle: Float, peer: Float) {
            let resolution = SceneDynamicSnapshotResolver().resolve(
                frameIndex: frame, generation: 11, index: index,
                timelineValues: runtime.values(sceneTime: time)
            )
            frame += 1
            let snapshot = resolution.snapshot
            let angle = plan.currentAngle(in: snapshot)
            if let resolved = snapshot[target],
               resolved.source == .timeline,
               case let .vector3(_, _, z) = resolved.value {
                validChain = validChain && resolution.diagnostics.isEmpty
                    && angle == Float(z)
            } else {
                validChain = false
            }
            return (angle, peerPlan.currentAngle(in: snapshot))
        }
        let start = sample(0)
        let playing = sample(2)
        try runtime.apply([.init(target: target, command: .pause)], sceneTime: 2).get()
        let paused8 = sample(8)
        let paused13 = sample(13)
        try runtime.apply([.init(target: target, command: .play)], sceneTime: 13).get()
        let resumed = sample(13)
        let resumed14 = sample(14)
        try runtime.apply([.init(target: target, command: .stop)], sceneTime: 14).get()
        let stopped = sample(14)
        let stopped20 = sample(20)
        try runtime.apply([.init(target: target, command: .play)], sceneTime: 20).get()
        let restarted = sample(20)
        let restarted21 = sample(21)
        return [
            "id": id, "name": name,
            "angles": [
                start.angle, playing.angle, paused8.angle, paused13.angle,
                resumed.angle, resumed14.angle, stopped.angle, stopped20.angle,
                restarted.angle, restarted21.angle,
            ],
            "productionTimelineLaneReachedAngle": validChain,
            "peerContinuesWhileTargetPaused": paused8.peer != paused13.peer,
            "targetDefinitionCount": definitions.filter { $0.target == target }.count,
        ]
    }

    static func snapshot(
        target: SceneDynamicTarget,
        value: SceneDynamicValue?,
        source: SceneDynamicSource = .timeline,
        authored: SceneDynamicValue = .vector3(0, 0, 2.35619)
    ) -> SceneDynamicSnapshotResolution {
        let definition = SceneDynamicTargetDefinition(
            target: target,
            valueType: authored.valueType,
            authoredValue: authored
        )
        let values = value.map { [target: $0] } ?? [:]
        return SceneDynamicSnapshotResolver().resolve(
            frameIndex: 0, generation: 4, definitions: [definition],
            userValues: source == .userProperty ? values : [:],
            timelineValues: source == .timeline ? values : [:],
            sceneScriptValues: source == .sceneScript ? values : [:]
        )
    }

    static func fallbackCases() -> [String: Any] {
        let plan = SceneSpotLightPlan(layer: layer(id: 63))!
        let target = SceneDynamicTarget.layer(layerID: 63, field: .angles)
        let base = plan.baseAngles.z
        var fallback: [String: Bool] = [
            "missing": plan.currentAngle(in: .empty(frameIndex: 0)) == base,
            "authoredOnly": plan.currentAngle(in: snapshot(
                target: target, value: nil, authored: .vector3(0, 0, 1.1)
            ).snapshot) == base,
            "wrongLayer": plan.currentAngle(in: snapshot(
                target: .layer(layerID: 64, field: .angles),
                value: .vector3(0, 0, 0.4)
            ).snapshot) == base,
            "wrongField": plan.currentAngle(in: snapshot(
                target: .layer(layerID: 63, field: .origin),
                value: .vector3(0, 0, 0.4)
            ).snapshot) == base,
        ]
        let wrongTypes: [SceneDynamicValue] = [
            .scalar(0.4), .bool(true), .vector2(0.2, 0.4),
            .vector4(0, 0, 0.4, 1), .string("0.4"),
        ]
        for (index, value) in wrongTypes.enumerated() {
            let resolved = snapshot(
                target: target, value: value, authored: value
            )
            fallback["wrongType\(index)"] = resolved.snapshot[target]?.source == .timeline
                && plan.currentAngle(in: resolved.snapshot) == base
        }
        let overflow = Double(Float.greatestFiniteMagnitude) * 2
        let oversized: [SceneDynamicValue] = [
            .vector3(overflow, 0, 0.4),
            .vector3(0, -overflow, 0.4),
            .vector3(0, 0, overflow),
        ]
        for (index, value) in oversized.enumerated() {
            let resolved = snapshot(target: target, value: value)
            fallback["floatOverflow\(index)"] =
                resolved.snapshot[target]?.source == .timeline
                && plan.currentAngle(in: resolved.snapshot) == base
        }
        for (index, value) in [
            SceneDynamicValue.vector3(.nan, 0, 0.4),
            .vector3(0, .infinity, 0.4), .vector3(0, 0, -.infinity),
        ].enumerated() {
            let resolved = snapshot(target: target, value: value)
            fallback["nonFinite\(index)"] = !resolved.diagnostics.isEmpty
                && plan.currentAngle(in: resolved.snapshot) == base
        }
        let live = snapshot(target: target, value: .vector3(0.2, -0.6, 1.25))
        let user = snapshot(
            target: target, value: .vector3(0, 0, 0.75), source: .userProperty
        )
        let overlay = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1, generation: 4,
            definitions: [binding(for: layer(id: 63)).definition],
            timelineValues: [target: .vector3(0, 0, 0.8)],
            sceneScriptValues: [target: .vector3(0.1, 0.2, 0.45)]
        )
        return [
            "fallbacks": fallback,
            "resolvedZNotAddedTwice": plan.currentAngle(in: live.snapshot) == 1.25,
            "userPropertyLaneAccepted": plan.currentAngle(in: user.snapshot) == 0.75,
            "sceneScriptPrecedence": overlay.snapshot[target]?.source == .sceneScript
                && plan.currentAngle(in: overlay.snapshot) == Float(0.45),
        ]
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
        let angles = mirrorAngles()
        let result: [String: Any] = [
            "parsed": parsed?.kind == "lspot"
                && parsed?.colorRGB == [0.1, 0.2, 0.3]
                && parsed?.intensity == 80
                && parsed?.outerConeDegrees == 2.91
                && parsed?.castsShadow == true,
            "sharedIDsAccepted": first != nil && second != nil,
            "mirrorAngles": angles,
            "playbackCases": try [
                playbackCase(id: 253, name: "Upper Lantern"),
                playbackCase(id: 991, name: "Renamed Azure Cone"),
            ],
            "snapshotConsumption": fallbackCases(),
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
    def test_strict_profile_and_shared_timeline_playback(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="scene-spot-light-plan-") as directory:
            temporary = Path(directory)
            harness = temporary / "Harness.swift"
            binary = temporary / "scene-spot-light-plan"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                ["swiftc", "-parse-as-library", "-module-cache-path", str(temporary / "module-cache"), *(str(path) for path in SOURCES), str(harness), "-o", str(binary)],
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
        base = 2.35619
        sweep = 1.3089924
        for actual, expected in zip(
            angles, [base, base - sweep / 2, base - sweep, base - sweep / 2, base]
        ):
            self.assertAlmostEqual(actual, expected, places=5)
        expected_playback = [
            base, base - sweep * 2 / 7,
            base - sweep * 2 / 7, base - sweep * 2 / 7,
            base - sweep * 2 / 7, base - sweep * 3 / 7,
            base, base, base, base - sweep / 7,
        ]
        self.assertEqual(len(result["playbackCases"]), 2, result)
        for case in result["playbackCases"]:
            with self.subTest(layer=case["id"], name=case["name"]):
                self.assertTrue(case["productionTimelineLaneReachedAngle"], case)
                self.assertTrue(case["peerContinuesWhileTargetPaused"], case)
                self.assertEqual(case["targetDefinitionCount"], 1, case)
                self.assertEqual(len(case["angles"]), len(expected_playback), case)
                for actual, expected in zip(case["angles"], expected_playback):
                    self.assertAlmostEqual(actual, expected, places=5, msg=str(case))
        consumption = result["snapshotConsumption"]
        self.assertEqual(len(consumption["fallbacks"]), 15, consumption)
        for name, held_authored in consumption["fallbacks"].items():
            with self.subTest(fallback=name):
                self.assertTrue(held_authored, consumption)
        self.assertTrue(consumption["resolvedZNotAddedTwice"], consumption)
        self.assertTrue(consumption["userPropertyLaneAccepted"], consumption)
        self.assertTrue(consumption["sceneScriptPrecedence"], consumption)


if __name__ == "__main__":
    unittest.main()
