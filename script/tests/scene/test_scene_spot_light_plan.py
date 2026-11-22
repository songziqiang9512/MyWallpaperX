#!/usr/bin/env python3

from __future__ import annotations

import json
import math
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCENE_ROOT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [SCENE_ROOT / path for path in [
    "Format/SceneTimelineAnimation.swift",
    "Systems/Timeline/SceneTimelineEvaluator.swift",
    "Systems/Timeline/SceneTimelineRuntime.swift",
    "Systems/Timeline/SceneTimelinePlaybackRuntime.swift",
    "Systems/Properties/SceneDynamicSnapshot.swift",
    "Systems/Properties/SceneDynamicLayerValues.swift",
    "Systems/Puppet/ScenePuppetAttachmentFrameSnapshot.swift",
    "Rendering/Geometry/SceneMatrix.swift",
    "Rendering/Geometry/SceneLayerWorldFrameResolver.swift",
    "Rendering/Geometry/SceneLayerDynamicWorldFrameResolver.swift",
    "Format/SceneSpotLightDefinition.swift",
    "Format/SceneDirectionalLightDefinition.swift",
    "Rendering/Lighting/SceneSpotLightPlan.swift",
]]

# Plain prepared/document carriers. Admission, Timeline, readers and world-frame
# computations below compile their actual production owners.
CARRIERS = r'''
import Foundation
import simd

enum SceneDocument {
    struct SceneObjectTimeline {
        enum Host { case angles, alpha }
        let host: Host
        let animation: SceneTimelineAnimation
    }
}
struct SceneRenderDescriptor {
    struct Camera {
        var orthoHeight: Float? = nil
        var default2DOriginInputLayerID: Int? = nil
    }
    var camera = Camera()
    let layers: [Layer]
    struct Layer {
        let id: Int
        var layerIndex = 0
        var name = "Cone"
        var contentKind = "spotLight"
        var spotLight: SceneSpotLightDefinition? = nil
        var visible: Bool? = true
        var alpha: Double? = nil
        var parentID: Int? = nil
        var childLayerIDs: [Int] = []
        var dependencyLayerIDs: [Int] = []
        var effects: [Int] = []
        var hasInlineScript = false
        var originXYZ: [Float]? = nil
        var anglesXYZ: [Float]? = nil
        var scaleXYZ: [Float]? = nil
        var attachmentName: String? = nil
        var parentAttachmentBindFrame: [Float]? = nil
        var timelines: [SceneDocument.SceneObjectTimeline] = []
    }
}
// PRODUCTION_TIMELINE_CARRIERS
enum SceneScriptBindingPathComponent: Equatable, Sendable {
    case key(String)
    case index(Int)
}
struct SceneScriptBindingOwner: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case object, effect }
    let kind: Kind
    let objectIndex: Int?
    let objectID: Int?
}
// PRODUCTION_SOURCE_EVIDENCE
extension SceneScriptSourceEvidenceIR {
    init(owner: SceneScriptBindingOwner, targetPath: [SceneScriptBindingPathComponent]) {
        self.init(source: "export function update(value) { return value; }", owner: owner,
            targetPath: targetPath, wrapperKeys: ["script", "value"])
    }
}

enum SpotLightInputs {
    static func light(
        color: [Float]? = [0.34118, 0.36078, 0.49804],
        intensity: Float = 80, radius: Float = 3_000,
        inner: Float = 1.87, outer: Float = 5.72,
        density: Float = 3.93, exponent: Float = 2.68,
        volumetrics: Float = 2.82, volumetric: Bool = true, solid: Bool = true
    ) -> SceneSpotLightDefinition {
        .init(kind: "lspot", colorRGB: color, intensity: intensity, radius: radius,
            innerConeDegrees: inner, outerConeDegrees: outer, density: density,
            exponent: exponent, volumetricsExponent: volumetrics,
            castsVolumetrics: volumetric, castsShadow: true, isSolid: solid)
    }
    static func layer(_ id: Int = 253, light: SceneSpotLightDefinition = light()) -> SceneRenderDescriptor.Layer {
        var layer = SceneRenderDescriptor.Layer(id: id)
        layer.spotLight = light
        return layer
    }
    static func evidence(_ id: Int, host: String, index: Int = 0) -> SceneScriptSourceEvidenceIR {
        .init(owner: .init(kind: .object, objectIndex: index, objectID: id),
            targetPath: [.key("objects"), .index(index), .key(host)])
    }
}
'''


def _declaration(source: str, marker: str) -> str:
    start = source.index(marker)
    body = source.index("{", start)
    depth, end = 1, body + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


_timeline_source = (SCENE_ROOT / "Systems/Timeline/SceneTimelineTargetCompiler.swift").read_text()
CARRIERS = CARRIERS.replace("// PRODUCTION_TIMELINE_CARRIERS", "\n".join(
    _declaration(_timeline_source, "nonisolated struct " + name)
    for name in ("SceneTimelineBinding:", "SceneTimelineProgram:", "SceneTimelineAnimationEventOccurrence:")
)).replace("// PRODUCTION_SOURCE_EVIDENCE", _declaration(
    (SCENE_ROOT / "Format/SceneScriptSourceEvidence.swift").read_text(),
    "nonisolated struct SceneScriptSourceEvidenceIR:",
))

HARNESS = CARRIERS + r'''
@main enum Harness {
    static func animation(mode: SceneTimelineMode = .mirror, relative: Bool = true) -> SceneTimelineAnimation {
        func frame(_ time: Double, _ value: Double) -> SceneTimelineKeyframe {
            .init(frame: time, value: value, back: nil, front: nil, locksAngle: true, locksLength: true)
        }
        return .init(lanes: [[frame(0, 0), frame(210, 0)], [frame(0, 0), frame(210, 0)],
                            [frame(0, 0), frame(210, -1.3089924)]],
            options: .init(fps: 30, length: 210, mode: mode, startsPaused: false, wrapsLoop: false,
                smoothing: nil, stiffness: nil, parent: nil, children: []),
            isRelative: relative, previewValue: nil)
    }

    static func preparedCases() -> [String: Bool] {
        func accepts(_ light: SceneSpotLightDefinition) -> Bool {
            SceneSpotLightPlan(layer: SpotLightInputs.layer(light: light)) != nil
        }
        var hierarchy = SpotLightInputs.layer()
        hierarchy.parentID = 17
        hierarchy.childLayerIDs = [23]
        hierarchy.dependencyLayerIDs = [42]
        hierarchy.alpha = 0.375
        let prepared = SceneSpotLightPlan(layer: hierarchy)
        var effected = hierarchy
        effected.effects = [0]
        var loop = hierarchy
        loop.timelines = [.init(host: .angles, animation: animation(mode: .loop, relative: false))]
        let rightAngle = SceneSpotLightPlan(layer: SpotLightInputs.layer(
            light: SpotLightInputs.light(radius: 2, inner: 0, outer: 90)))
        let ratio = SceneSpotLightPlan(layer: SpotLightInputs.layer(
            light: SpotLightInputs.light(radius: 2, inner: 45, outer: 90)))
        let zero = SceneSpotLightPlan(layer: SpotLightInputs.layer(
            light: SpotLightInputs.light(intensity: 0, radius: 0, inner: 0, density: 0, exponent: 0, volumetrics: 0)))
        return [
            "staticAccepted": SceneSpotLightPlan(layer: SpotLightInputs.layer()) != nil,
            "renamedAccepted": SceneSpotLightPlan(layer: SpotLightInputs.layer(991)) != nil,
            "hierarchyAccepted": prepared != nil,
            "authoredAlphaPreserved": prepared?.alpha == 0.375,
            "loopAbsoluteAccepted": SceneSpotLightPlan(layer: loop) != nil,
            "effectRejected": SceneSpotLightPlan(layer: effected) == nil,
            "wideAndHighValuesAccepted": accepts(SpotLightInputs.light(
                intensity: 101, radius: 5_001, inner: 20, outer: 75, density: 11, exponent: 11, volumetrics: 11)),
            "smallValuesAccepted": accepts(SpotLightInputs.light(radius: 0.1, inner: 0, exponent: 0, volumetrics: 0)),
            "zeroAccepted": zero != nil && zero?.supportHalfWidth == 0,
            "preparedHalfWidth": abs((rightAngle?.supportHalfWidth ?? -1) - 3.2) < 0.00001,
            "zeroInnerRatio": rightAngle?.innerRatio == 0,
            "preparedInnerRatio": abs((ratio?.innerRatio ?? -1) - 0.25888348) < 0.00001,
            "derivedOverflowRejected": !accepts(SpotLightInputs.light(radius: .greatestFiniteMagnitude, inner: 0, outer: 90)),
            "badColorRejected": [SpotLightInputs.light(color: nil), SpotLightInputs.light(color: [0, 1]),
                SpotLightInputs.light(color: [-0.1, 0, 0]), SpotLightInputs.light(color: [0, 0, 1.1]),
                SpotLightInputs.light(color: [.nan, 0, 0])].allSatisfy { !accepts($0) },
            "badConeRejected": [SpotLightInputs.light(inner: -1), SpotLightInputs.light(inner: 6, outer: 5),
                SpotLightInputs.light(inner: 0, outer: 0), SpotLightInputs.light(outer: 180),
                SpotLightInputs.light(outer: .infinity)].allSatisfy { !accepts($0) },
            "badParametersRejected": [SpotLightInputs.light(intensity: -1), SpotLightInputs.light(intensity: .nan),
                SpotLightInputs.light(radius: -1), SpotLightInputs.light(radius: .infinity),
                SpotLightInputs.light(density: -1), SpotLightInputs.light(exponent: -1),
                SpotLightInputs.light(volumetrics: -.infinity), SpotLightInputs.light(volumetric: false),
                SpotLightInputs.light(solid: false)].allSatisfy { !accepts($0) },
        ]
    }

    static func writerCases() -> [String: Bool] {
        let id = 63
        var input = SpotLightInputs.layer(id)
        input.hasInlineScript = true
        let writers: [(String, SceneDynamicLayerField)] = [
            ("origin", .origin), ("angles", .angles), ("scale", .scale), ("color", .color),
            ("intensity", .intensity), ("alpha", .alpha), ("visible", .visibility),
        ]
        let targets = Set(writers.map { SceneDynamicTarget.layer(layerID: id, field: $0.1) })
        let evidence = writers.map { SpotLightInputs.evidence(id, host: $0.0) }
        func accepts(_ source: [SceneScriptSourceEvidenceIR], _ instantiated: Set<SceneDynamicTarget>? = nil,
                     layer: SceneRenderDescriptor.Layer? = nil) -> Bool {
            SceneSpotLightPlan(layer: layer ?? input, instantiatedSceneScriptTargets: instantiated ?? targets,
                scriptSourceEvidence: source) != nil
        }
        var cases = Dictionary(uniqueKeysWithValues: writers.map { host, field in
            (host, accepts([SpotLightInputs.evidence(id, host: host)], [.layer(layerID: id, field: field)]))
        })
        cases["scalarVectorWritersTogether"] = accepts(evidence)
        cases["duplicateWriterAccepted"] = accepts(evidence + [evidence[0]])
        cases["uninstantiatedRejected"] = !accepts(evidence, [])
        cases["wrongTargetIdentityRejected"] = !accepts([evidence[4]], [.layer(layerID: 999, field: .intensity)])
        cases["wrongObjectIdentityRejected"] = !accepts([SpotLightInputs.evidence(999, host: "intensity")])
        cases["wrongObjectIndexRejected"] = !accepts([SpotLightInputs.evidence(id, host: "intensity", index: 1)])
        cases["wrongOwnerKindRejected"] = !accepts([.init(
            owner: .init(kind: .effect, objectIndex: 0, objectID: id), targetPath: evidence[4].targetPath)])
        cases["wrongPathIndexRejected"] = !accepts([.init(owner: evidence[4].owner,
            targetPath: [.key("objects"), .index(1), .key("intensity")])])
        cases["wrongPathRootRejected"] = !accepts([.init(owner: evidence[4].owner,
            targetPath: [.key("layers"), .index(0), .key("intensity")])])
        cases["nestedRejected"] = !accepts([.init(owner: evidence[4].owner,
            targetPath: evidence[4].targetPath + [.key("nested")])])
        for host in ["Intensity", "visibility", "radius", "density", "size", "future"] {
            cases["unsupported-" + host] = !accepts(evidence + [SpotLightInputs.evidence(id, host: host)])
        }
        var noMarker = input
        noMarker.hasInlineScript = false
        cases["unmarkedEvidenceRejected"] = !accepts(evidence, layer: noMarker)
        cases["foreignPeerDoesNotPoisonOwner"] = accepts(evidence + [SpotLightInputs.evidence(999, host: "radius")])
        return cases
    }

    static func playbackCase(id: Int, relative: Bool) throws -> [String: Any] {
        var input = SpotLightInputs.layer(id)
        input.originXYZ = [3, 4, 0]
        input.anglesXYZ = [0, 0, 2.35619]
        input.parentID = id + 1
        var parent = SceneRenderDescriptor.Layer(id: id + 1)
        parent.contentKind = "container"
        parent.anglesXYZ = [0, 0, .pi / 2]
        parent.scaleXYZ = [2, 2, 1]
        parent.childLayerIDs = [id]
        var peer = SpotLightInputs.layer(id + 9_000)
        peer.anglesXYZ = input.anglesXYZ
        let animation = animation(mode: relative ? .mirror : .loop, relative: relative)
        func binding(_ layerID: Int) -> SceneTimelineBinding {
            .init(definition: .init(target: .layer(layerID: layerID, field: .angles), valueType: .vector3,
                authoredValue: .vector3(0, 0, 2.35619)), animation: animation,
                composition: relative ? .additive : .absolute)
        }
        let target = SceneDynamicTarget.layer(layerID: id, field: .angles)
        let program = SceneTimelineProgram(bindings: [binding(id), binding(peer.id)], diagnostics: [])
        let runtime = SceneTimelinePlaybackRuntime(program: program)
        let definitions = SceneTimelineRuntime.mergedDefinitions(propertyDefinitions: [], timelineProgram: program)
        let descriptor = SceneRenderDescriptor(layers: [input, parent, peer])
        let byID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        let staticFrames = SceneLayerWorldFrameResolver.compute(descriptor: descriptor, byID: byID)
        var validChain = true
        var frame: UInt64 = 0
        func sample(_ time: Double) -> (direction: [Float], peer: Float) {
            let resolution = SceneDynamicSnapshotResolver().resolve(frameIndex: frame, generation: 11,
                definitions: definitions, timelineValues: runtime.values(sceneTime: time))
            frame += 1
            let snapshot = resolution.snapshot
            let worlds = SceneLayerDynamicWorldFrameResolver.resolve(descriptor: descriptor, byID: byID,
                snapshot: snapshot, staticFrames: staticFrames)
            let world = worlds[id]!
            validChain = validChain && snapshot[target]?.source == .timeline && resolution.diagnostics.isEmpty
                && abs(world.columns.3.x + 8) < 0.00001 && abs(world.columns.3.y - 6) < 0.00001
            return ([world.columns.0.x, world.columns.0.y], worlds[peer.id]!.columns.0.x)
        }
        let start = sample(0), playing = sample(2)
        try runtime.apply([.init(target: target, command: .pause)], sceneTime: 2).get()
        let paused8 = sample(8), paused13 = sample(13)
        try runtime.apply([.init(target: target, command: .play)], sceneTime: 13).get()
        let resumed = sample(13), resumed14 = sample(14)
        try runtime.apply([.init(target: target, command: .stop)], sceneTime: 14).get()
        let stopped = sample(14), stopped20 = sample(20)
        try runtime.apply([.init(target: target, command: .play)], sceneTime: 20).get()
        let restarted = sample(20), restarted21 = sample(21)
        return ["id": id, "relative": relative, "worldFrameChain": validChain,
            "planAccepted": SceneSpotLightPlan(layer: input) != nil,
            "peerContinuesWhileTargetPaused": paused8.peer != paused13.peer,
            "directions": [start.direction, playing.direction, paused8.direction, paused13.direction,
                resumed.direction, resumed14.direction, stopped.direction, stopped20.direction,
                restarted.direction, restarted21.direction]]
    }

    static func dynamicReaders() -> [String: Bool] {
        let id = 53
        var layer = SpotLightInputs.layer(id)
        layer.alpha = 0.5
        let plan = SceneSpotLightPlan(layer: layer)!
        let alpha = SceneDynamicTarget.layer(layerID: id, field: .alpha)
        let color = SceneDynamicTarget.layer(layerID: id, field: .color)
        let intensity = SceneDynamicTarget.layer(layerID: id, field: .intensity)
        let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 2, generation: 4,
            definitions: [.init(target: alpha, valueType: .scalar, authoredValue: .scalar(0.5)),
                .init(target: color, valueType: .vector3, authoredValue: .vector3(0.1, 0.2, 0.3)),
                .init(target: intensity, valueType: .scalar, authoredValue: .scalar(80))],
            timelineValues: [alpha: .scalar(0.7)],
            sceneScriptValues: [alpha: .scalar(0.25), color: .vector3(1, 0.5, 0), intensity: .scalar(120)]).snapshot
        return [
            "authoredAlpha": SceneDynamicLayerValues.alpha(layerID: id, authoredValue: plan.alpha,
                snapshot: .empty(frameIndex: 0)) == 0.5,
            "scriptAlphaPrecedence": SceneDynamicLayerValues.alpha(layerID: id,
                authoredValue: plan.alpha, snapshot: snapshot) == 0.25,
            "scriptColor": SceneDynamicLayerValues.color(layerID: id, authoredValue: nil,
                snapshot: snapshot) == SIMD3(1, 0.5, 0),
            "highIntensity": SceneDynamicLayerValues.lightIntensity(layerID: id,
                authoredValue: plan.intensity, snapshot: snapshot) == 120,
        ]
    }

    static func main() throws {
        let parsed = SceneSpotLightDefinition.parse(["light": "lspot",
            "color": ["script": "color.js", "value": "0.1 0.2 0.3"],
            "intensity": ["user": "strength", "value": 80], "radius": 1437.12,
            "innercone": 1.87, "outercone": 2.91, "density": 3.93, "exponent": 2.68,
            "volumetricsexponent": 2.82, "castvolumetrics": true,
            "castshadow": ["user": "shadow", "value": true], "solid": true])
        let result: [String: Any] = [
            "parsed": parsed?.colorRGB == [0.1, 0.2, 0.3] && parsed?.intensity == 80
                && parsed?.outerConeDegrees == 2.91 && parsed?.castsShadow == true,
            "prepared": preparedCases(), "writers": writerCases(), "readers": dynamicReaders(),
            "playback": try [playbackCase(id: 253, relative: true), playbackCase(id: 991, relative: false)],
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneSpotLightPlanTests(unittest.TestCase):
    def test_prepared_geometry_and_shared_timeline_world_frame(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="scene-spot-light-plan-") as directory:
            temporary = Path(directory)
            harness = temporary / "Harness.swift"
            binary = temporary / "scene-spot-light-plan"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                ["swiftc", "-parse-as-library", "-module-cache-path", str(temporary / "module-cache"),
                 *(str(path) for path in SOURCES), str(harness), "-o", str(binary)],
                capture_output=True, text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
        result = json.loads(completed.stdout)
        self.assertTrue(result["parsed"], result)
        for category in ("prepared", "writers", "readers"):
            for case, accepted in result[category].items():
                with self.subTest(category=category, case=case):
                    self.assertTrue(accepted, result[category])
        base, sweep = 2.35619, 1.3089924
        phases = [0, 2 / 7, 2 / 7, 2 / 7, 2 / 7, 3 / 7, 0, 0, 0, 1 / 7]
        for case in result["playback"]:
            with self.subTest(layer=case["id"], relative=case["relative"]):
                self.assertTrue(case["worldFrameChain"], case)
                self.assertTrue(case["planAccepted"], case)
                self.assertTrue(case["peerContinuesWhileTargetPaused"], case)
                self.assertEqual(len(case["directions"]), len(phases))
                for actual, phase in zip(case["directions"], phases):
                    angle = math.pi / 2 + (base if case["relative"] else 0) - sweep * phase
                    self.assertAlmostEqual(actual[0], 2 * math.cos(angle), places=5)
                    self.assertAlmostEqual(actual[1], 2 * math.sin(angle), places=5)


if __name__ == "__main__":
    unittest.main()
