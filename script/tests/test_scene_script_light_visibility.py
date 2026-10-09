#!/usr/bin/env python3
"""Real Boolean VM/property producers reach the shared effective light visibility."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.scene_vector_vm_test_support import SWIFT_PREAMBLE, compile_vector_harness
from script.tests.test_scene_property_live_routing import method_body
from script.tests.test_scene_static_model_pipeline import LIGHTING_STUB

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"

# Extend stored descriptor carriers only. The VM candidate, Host consumer
# function, leaf admission, property state, visibility and light snapshot are
# compiled from production sources. Unrelated graph/audio branches stay empty.
STUBS = r'''
struct SceneResolvedMaterialExecutionCapabilityCatalog {
    var executionLayerIDs: Set<Int> = []
    var admittedResolvedMaterialReferences: [Int] = []
    var liveConsumerTargets: Set<SceneDynamicTarget> = []
}
enum SceneUtilityLayerRuntimePlanner {
    enum Kind { case fullscreen }
    struct Plan { let kind: Kind; let requiresNamedTarget: Bool; let shouldCapture: Bool }
    static func plans(in descriptor: SceneRenderDescriptor, resolvedMaterialLayerIDs: Set<Int>,
        admittedResolvedMaterialReferences: [Int]) -> [Int: Plan] { [:] }
}
enum SceneDependencyGraphAnalysis {
    struct Reference { let providerLayerID: Int }
    static func references(in layers: [SceneRenderDescriptor.Layer]) -> [Reference] { [] }
}
struct SceneSoundPlaybackProgram { var liveConsumerTargets: Set<SceneDynamicTarget> = [] }
enum SceneDesktopWallpaperHost { __HOST_CONSUMERS__ }
'''

HARNESS = r'''
@main enum Probe {
    static func binding(id: Int, index: Int, seed: Bool, source: String) -> SceneScriptBindingIR {
        .init(source: source,
            owner: .init(kind: .object, objectIndex: index, objectID: id,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
            targetPath: [.key("objects"), .index(index), .key("visible")],
            properties: [:], authoredValue: .bool(seed), valueType: .boolean,
            wrapperKeys: ["script", "value"])
    }
    static func main() throws {
        var rows: [[String: Any]] = []
        for (ordinal, kind) in ["pointLight", "spotLight", "directionalLight"].enumerated() {
            var light = SceneRenderDescriptor.Layer(id: 7, layerIndex: 0, name: "lamp",
                visible: false, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1,
                effects: [], contentKind: kind, parentID: 90)
            if kind == "pointLight" {
                light.pointLight = .init(kind: "lpoint", colorRGB: [1, 1, 1], intensity: 1,
                    radius: 10, castsVolumetrics: false, castsShadow: true, isSolid: true)
            } else if kind == "spotLight" {
                light.spotLight = .init(kind: "lspot", colorRGB: [1, 1, 1], intensity: 1,
                    radius: 100, innerConeDegrees: 20, outerConeDegrees: 30,
                    density: nil, exponent: nil, volumetricsExponent: nil,
                    castsVolumetrics: false, castsShadow: true, isSolid: true)
            } else {
                light.directionalLight = .init(colorRGB: [1, 1, 1], intensity: 1,
                                              shadowCastIntent: .enabled)
            }
            light.displayScriptOwnership = .init(visible: true, alpha: false)
            let parent = SceneRenderDescriptor.Layer(id: 90, layerIndex: 1, name: "parent",
                visible: true, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1,
                effects: [], contentKind: "container", childLayerIDs: [7])
            var scene = SceneRenderDescriptor(layers: [light, parent])
            scene.lighting = .init(ambientColorRGB: [0, 0, 0], skylightColorRGB: [0, 0, 0])
            let lightTarget = SceneDynamicTarget.layer(layerID: 7, field: .visibility)
            let parentTarget = SceneDynamicTarget.layer(layerID: 90, field: .visibility)
            let bindings = [
                binding(id: 7, index: 0, seed: false,
                    source: "export function update(v) { return engine.runtime >= 2 && engine.runtime < 6; }"),
                binding(id: 90, index: 1, seed: true,
                    source: "export function update(v) { return engine.runtime !== 4; }"),
            ]
            let projection = SceneScriptVectorProgram.project(descriptor: scene, scriptBindings: bindings)
            let programs = try SceneScriptQuickJSProgramCandidate.compile(
                authoredDescriptor: scene, runtimeDescriptor: scene,
                scriptBindings: bindings, vectorProjection: projection,
                userPropertyDefinitions: [], timelineTargets: [], scalarExcludedTargets: [],
                stringExcludedTargets: [], admittedVectorPassTargets: [], generation: UInt64(700 + ordinal))
            let index = Dictionary(uniqueKeysWithValues: scene.layers.map { ($0.id, $0) })
            let world = SceneLayerWorldFrameResolver.compute(descriptor: scene, byID: index)
            func lightSnapshot(_ snapshot: SceneDynamicSnapshot) -> SceneLightSnapshot {
                SceneLightSnapshot.make(descriptor: scene, worldFramesByLayerID: world,
                                        dynamicSnapshot: snapshot)
            }
            func count(_ value: SceneLightSnapshot) -> Int {
                value.directional.count + value.point.count + value.spot.count
            }
            var visible: [Bool] = [], childValues: [Bool] = [], parentValues: [Bool] = []
            var counts: [Int] = [], shadows: [Int] = [], failures = 0
            for (frameIndex, time) in [0.0, 2.0, 4.0, 6.0, 2.0].enumerated() {
                let frame = programs.vectorProgram.evaluate(
                    inputs: [lightTarget: .bool(false), parentTarget: .bool(true)],
                    effectivePropertyValues: [:], frame: .init(timing: .init(
                        wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 1 / 60,
                        sceneTime: time)))
                failures += frame.failures.count
                let snapshot = SceneDynamicSnapshotResolver().resolve(
                    frameIndex: UInt64(frameIndex), generation: 1,
                    definitions: programs.vectorProgram.definitions,
                    sceneScriptValues: frame.values).snapshot
                childValues.append(snapshot[lightTarget]?.value == .bool(true))
                parentValues.append(snapshot[parentTarget]?.value == .bool(true))
                visible.append(SceneLayerVisibility.visibleLayerIDs(in: scene, snapshot: snapshot).contains(7))
                let lights = lightSnapshot(snapshot)
                counts.append(count(lights)); shadows.append(lights.shadowLights.count)
                precondition(lights.overflowCount == 0)
                programs.vectorProgram.finalizeLayerMutations(committing: true)
            }
            let propertyProgram = ScenePropertyBindingProgram(
                definitions: [.init(target: lightTarget, valueType: .bool, authoredValue: .bool(false))],
                instructions: [.init(propertyKey: "show", path: .init(components: [.key("show")]),
                    target: lightTarget, valueType: .bool)])
            let active = SceneDesktopWallpaperHost.activeLiveConsumerTargets(
                in: scene, propertyBindingProgram: propertyProgram,
                resolvedMaterialExecutionCapabilities: .init(), soundPlaybackProgram: .init(),
                preparedStaticModelLayerIDs: [], preparedImageMaterialTargets: [],
                propertyVectorScriptProgram: programs.vectorProgram,
                sceneScriptScalarProgram: programs.scalarProgram, sceneScriptStringProgram: programs.stringProgram)
            var live = ScenePropertyLiveUpdateState(program: propertyProgram,
                effectiveValues: ["show": .bool(false)], activeConsumerTargets: active)
            var propertyCounts: [Int] = [], accepted: [Bool] = []
            for show in [false, true, false] {
                accepted.append(live.apply(.bool(show), forPropertyKey: "show"))
                let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 10, generation: 1,
                    definitions: propertyProgram.definitions, userValues: live.userValues).snapshot
                propertyCounts.append(count(lightSnapshot(snapshot)))
            }
            let candidates = SceneLightSnapshot.orderedLightLayerIDs(descriptor: scene, layersByID: index)
            rows.append(["kind": kind, "projected": projection.targets.contains(lightTarget),
                "definitionCount": programs.vectorProgram.definitions.count,
                "complete": programs.constructionReport.isComplete, "failures": failures,
                "childValues": childValues, "parentValues": parentValues, "visible": visible,
                "counts": counts, "shadows": shadows,
                "hostAdmitsProperty": active.contains(lightTarget), "accepted": accepted,
                "propertyCounts": propertyCounts, "launchCandidates": candidates,
                "retainsColor": active.contains(.layer(layerID: 7, field: .color)),
                "retainsIntensity": active.contains(.layer(layerID: 7, field: .intensity))])
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneScriptLightVisibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-script-light-visible-")
        work = Path(cls.temporary.name)
        preamble = SWIFT_PREAMBLE.replace(
            "struct Camera {\n        var parallaxEnabled = false\n        var orthoHeight: Float? = nil\n    }",
            "struct Camera { struct Bloom { var hdr: Int? = nil }; var bloom = Bloom(); "
            "var parallaxEnabled = false; var orthoWidth: Float? = nil; var orthoHeight: Float? = nil }")
        lighting = LIGHTING_STUB.split("    struct LightingDescriptor {", 1)[1].split("    struct CameraDescriptor", 1)[0]
        preamble = preamble.replace("struct SceneRenderDescriptor {",
            "struct SceneRenderDescriptor {\n    struct LightingDescriptor {" + lighting
            + "    var lighting: LightingDescriptor? = nil\n")
        preamble = preamble.replace("struct TextStyle {", "struct TextStyle {\n        var limitWidth = false")
        preamble = preamble.replace("enum Kind {\n            case composition\n        }",
                                    "enum Kind: String { case composition, fullscreen }")
        preamble = preamble.replace("var spotLight: Int? = nil",
            "var pointLight: ScenePointLightDefinition? = nil\n"
            "        var spotLight: SceneSpotLightDefinition? = nil")
        preamble = preamble.replace("var directionalLight: Int? = nil",
                                    "var directionalLight: SceneDirectionalLightDefinition? = nil")
        preamble = preamble.replace("var particleInstanceOverride:",
            "var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil\n"
            "        var particlePath: String? = nil\n"
            "        var supportsDirectLayerColorConsumer: Bool { false }\n"
            "        var particleInstanceOverride:")
        admission = (SCENE / "Compilation/Material/SceneResolvedMaterialExecutionCapabilityAdmission.swift").read_text()
        start = admission.index("nonisolated enum SceneDynamicLayerVisibilityRouteAdmission {")
        end = admission.index("/// Raw-graph conservation", start)
        source = work / "VisibilityAdmission.swift"
        source.write_text("import Foundation\n" + admission[start:end])
        host = method_body((SCENE / "Runtime/Session/SceneDesktopWallpaperHost+LiveConsumers.swift").read_text(),
                           "static func activeLiveConsumerTargets(")
        preamble += STUBS.replace("__HOST_CONSUMERS__", host)
        extra = tuple(SCENE / path for path in [
            "Format/SceneDirectionalLightDefinition.swift", "Format/ScenePointLightDefinition.swift",
            "Format/SceneSpotLightDefinition.swift", "Rendering/Lighting/SceneLightSnapshot.swift",
            "Rendering/Geometry/SceneLayerVisibility.swift", "Rendering/Composition/SceneUtilityLayerSourceRoute.swift",
            "Systems/Properties/SceneDynamicLayerValues.swift", "Systems/Properties/ScenePropertyBindingProgram.swift",
            "Systems/Properties/ScenePropertyBindingCompiler+TargetMapping.swift",
            "Systems/Properties/ScenePropertyBindingProgramValidator.swift", "Systems/Properties/ScenePropertyLiveUpdateState.swift",
        ]) + (source,)
        binary = compile_vector_harness(work, HARNESS, "light-visible", extra_swift_sources=extra, preamble=preamble)
        result = subprocess.run([str(binary)], capture_output=True, text=True, check=True, timeout=30)
        cls.rows = json.loads(result.stdout)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_inline_boolean_vm_publishes_each_light_and_parent_hide_restore(self):
        for row in self.rows:
            with self.subTest(kind=row["kind"]):
                self.assertTrue(row["projected"], row)
                self.assertEqual(row["definitionCount"], 2, row)
                self.assertTrue(row["complete"], row)
                self.assertEqual(row["failures"], 0, row)
                self.assertEqual(row["childValues"], [False, True, True, False, True], row)
                self.assertEqual(row["parentValues"], [True, True, False, True, True], row)
                self.assertEqual(row["visible"], [False, True, False, False, True], row)
                self.assertEqual(row["counts"], [0, 1, 0, 0, 1], row)
                self.assertEqual(row["shadows"], [0, 1, 0, 0, 1], row)

    def test_real_host_live_property_consumer_publishes_and_preserves_launch_targets(self):
        for row in self.rows:
            with self.subTest(kind=row["kind"]):
                self.assertTrue(row["hostAdmitsProperty"], row)
                self.assertEqual(row["accepted"], [True, True, True], row)
                self.assertEqual(row["propertyCounts"], [0, 1, 0], row)
                self.assertEqual(row["launchCandidates"], [7], row)
                self.assertTrue(row["retainsColor"], row)
                self.assertTrue(row["retainsIntensity"], row)


if __name__ == "__main__":
    unittest.main()
