#!/usr/bin/env python3
"""Prepared hidden consumers accept typed updates without changing visibility."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_property_live_routing import method_body
from script.tests.test_scene_property_live_update_state import SWIFT_SOURCES


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
HOST_SOURCE = SCENE / "Runtime/Session/SceneDesktopWallpaperHost+LiveConsumers.swift"
LAYER_SOURCE = SCENE / "Runtime/Frame/SceneRenderDescriptor+Layer.swift"
VISIBILITY_SOURCE = SCENE / "Rendering/Geometry/SceneLayerVisibility.swift"

# Only declarations for unrelated graph, light, audio and script consumers are
# substituted. The Host function, color eligibility, visibility walk, Program
# validation/evaluation and live state are production implementations.
STUBS = r'''
import Foundation

struct SceneLayerDisplayScriptOwnership {
    var visible = false
    var alpha = false
    var isEmpty: Bool { !visible && !alpha }
    var fields: [String] { [] }
}

struct SceneRenderDescriptor {
    struct TextStyle { var limitWidth = false }
    struct AnimationLayer { var id: Int?; var visibilityBinding: Bool? }
    struct Camera { var orthoWidth: Float? = 512; var orthoHeight: Float? = 512 }
    struct Layer {
        var id: Int
        var contentKind: String
        var visible: Bool? = false
        var parentID: Int? = nil
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil
        var text: String? = nil
        var textStyle: TextStyle? = nil
        var staticModelPath: String? = nil
        var effects: [Int] = []
        var authoredDependencies: [Int] = []
        var dependencyLayerIDs: [Int] = []
        var puppetAnimationLayers: [AnimationLayer] = []
        __COLOR_ELIGIBILITY__
    }
    var layers: [Layer]
    var camera = Camera()
}

struct SceneResolvedMaterialExecutionCapabilityCatalog {
    var executionLayerIDs: Set<Int> = []
    var admittedResolvedMaterialReferences: [Int] = []
    var liveConsumerTargets: Set<SceneDynamicTarget> = []
}
enum SceneUtilityLayerRuntimePlanner {
    enum Kind { case fullscreen }
    struct Plan {
        var kind: Kind
        var requiresNamedTarget: Bool
        var shouldCapture: Bool
    }
    static func plans(in descriptor: SceneRenderDescriptor,
        resolvedMaterialLayerIDs: Set<Int>, admittedResolvedMaterialReferences: [Int])
        -> [Int: Plan] { [:] }
}
enum SceneLightSnapshot {
    static func liveConsumerTargets(descriptor: SceneRenderDescriptor)
        -> Set<SceneDynamicTarget> { [] }
}
enum SceneDependencyGraphAnalysis {
    struct Reference { var providerLayerID: Int }
    static func references(in layers: [SceneRenderDescriptor.Layer])
        -> [Reference] { [] }
}
enum SceneDynamicLayerVisibilityRouteAdmission {
    // Route shape is exercised by the visibility admission gate. Here a legal
    // candidate lets the real Host prove actual preparation is still required.
    static func targets(in descriptor: SceneRenderDescriptor,
        candidates: Set<SceneDynamicTarget>, preparedStaticModelLayerIDs: Set<Int>)
        -> Set<SceneDynamicTarget> { candidates }
}
struct SceneSoundPlaybackProgram {
    var liveConsumerTargets: Set<SceneDynamicTarget> = []
}
struct SceneScriptVectorProgram {
    var livePropertyInputTargets: Set<SceneDynamicTarget> = []
}
struct SceneScriptScalarProgram {
    var livePropertyInputTargets: Set<SceneDynamicTarget> = []
}
struct SceneScriptStringProgram {
    var livePropertyInputTargets: Set<SceneDynamicTarget> = []
}
enum SceneDesktopWallpaperHost {
    __ACTIVE_CONSUMERS__
}
'''

HARNESS = r'''
@main enum Probe {
    struct Binding {
        var key: String
        var target: SceneDynamicTarget
        var type: SceneDynamicValueType
        var seed: SceneDynamicValue
    }

    static func program(_ bindings: [Binding]) -> ScenePropertyBindingProgram {
        .init(
            definitions: bindings.map {
                .init(target: $0.target, valueType: $0.type, authoredValue: $0.seed)
            },
            instructions: bindings.map {
                .init(propertyKey: $0.key, path: .init(components: [.key($0.key)]),
                    target: $0.target, valueType: $0.type)
            }
        )
    }

    static func state(_ layers: [SceneRenderDescriptor.Layer], _ bindings: [Binding],
        values: [String: SceneUserPropertyValue], prepared: Set<Int> = [])
        -> ScenePropertyLiveUpdateState {
        let p = program(bindings)
        let targets = SceneDesktopWallpaperHost.activeLiveConsumerTargets(
            in: .init(layers: layers), propertyBindingProgram: p,
            resolvedMaterialExecutionCapabilities: .init(executionLayerIDs: prepared),
            soundPlaybackProgram: .init(), preparedStaticModelLayerIDs: [],
            preparedImageMaterialTargets: [], propertyVectorScriptProgram: .init(),
            sceneScriptScalarProgram: .init(), sceneScriptStringProgram: .init()
        )
        return .init(program: p, effectiveValues: values, activeConsumerTargets: targets)
    }

    static func unchanged(_ a: ScenePropertyLiveUpdateState,
        _ b: ScenePropertyLiveUpdateState) -> Bool {
        a.effectiveValues == b.effectiveValues && a.userValues == b.userValues
            && a.revision == b.revision
    }

    static func main() throws {
        let hiddenText = SceneRenderDescriptor.Layer(id: 1, contentKind: "text",
            text: "old", textStyle: .init(limitWidth: true))
        let visibleText = SceneRenderDescriptor.Layer(id: 2, contentKind: "text",
            visible: true, text: "old", textStyle: .init())
        let hiddenImage = SceneRenderDescriptor.Layer(id: 3, contentKind: "image")
        let effectedImage = SceneRenderDescriptor.Layer(id: 4, contentKind: "image",
            effects: [1])
        let noStyleText = SceneRenderDescriptor.Layer(id: 5, contentKind: "text", text: "old")
        let noContentText = SceneRenderDescriptor.Layer(id: 6, contentKind: "text",
            textStyle: .init())
        let unlimitedText = SceneRenderDescriptor.Layer(id: 7, contentKind: "text",
            text: "old", textStyle: .init())
        let unknown = SceneRenderDescriptor.Layer(id: 8, contentKind: "unknown")
        let allLayers = [hiddenText, visibleText, hiddenImage, effectedImage,
            noStyleText, noContentText, unlimitedText, unknown]
        var rows: [String: [String: Bool]] = [:]
        let composition = SceneRenderDescriptor.Layer(id: 9, contentKind: "composition",
            effects: [1], authoredDependencies: [10], dependencyLayerIDs: [10])
        let visibilityTarget = SceneDynamicTarget.layer(layerID: 9, field: .visibility)
        let visibilityBinding = Binding(key: "show", target: visibilityTarget,
            type: .bool, seed: .bool(false))
        for prepared in [false, true] {
            var s = state([composition], [visibilityBinding], values: ["show": .bool(false)],
                prepared: prepared ? [9, 10] : [])
            let before = s
            let accepted = s.apply(.bool(true), forPropertyKey: "show")
            rows[prepared ? "preparedComposition" : "unpreparedComposition"] = [
                "admitted": s.activeConsumerTargets.contains(visibilityTarget),
                "accepted": accepted, "unchanged": unchanged(s, before),
            ]
        }
        let cases: [(String, SceneDynamicTarget, SceneDynamicValueType,
            SceneDynamicValue, SceneUserPropertyValue, SceneUserPropertyValue,
            SceneDynamicValue)] = [
            ("content", .text(layerID: 1, field: .content), .string, .string("old"),
                .string("old"), .string("new"), .string("new")),
            ("pointSize", .text(layerID: 1, field: .pointSize), .scalar, .scalar(16),
                .number(16), .number(32), .scalar(32)),
            ("color", .text(layerID: 1, field: .color), .vector3, .vector3(1, 1, 1),
                .string("1 1 1"), .string("0.2 0.4 0.6"), .vector3(0.2, 0.4, 0.6)),
            ("maxWidth", .text(layerID: 1, field: .maxWidth), .scalar, .scalar(100),
                .number(100), .number(160), .scalar(160)),
            ("imageColor", .layer(layerID: 3, field: .color), .vector3,
                .vector3(1, 1, 1), .string("1 1 1"), .string("0 1 0"), .vector3(0, 1, 0)),
        ]
        for (name, target, type, seed, initial, replacement, expected) in cases {
            var s = state(allLayers, [.init(key: name, target: target, type: type, seed: seed)],
                values: [name: initial])
            let admitted = s.activeConsumerTargets.contains(target)
            let accepted = s.apply(replacement, forPropertyKey: name)
            let layerID = name == "imageColor" ? 3 : 1
            let snapshot = SceneDynamicSnapshotResolver().resolve(
                frameIndex: 1, generation: 1, definitions: s.program.definitions,
                userValues: s.userValues
            ).snapshot
            rows[name] = ["admitted": admitted, "accepted": accepted,
                "published": s.userValues[target] == expected,
                "revision": s.revision == 1,
                "hidden": !SceneLayerVisibility.visibleLayerIDs(
                    in: .init(layers: allLayers), snapshot: snapshot)
                    .contains(layerID)]
        }

        let sharedTargets = [SceneDynamicTarget.text(layerID: 1, field: .color),
            .text(layerID: 2, field: .color)]
        var shared = state(allLayers, sharedTargets.map {
            .init(key: "shared", target: $0, type: .vector3, seed: .vector3(1, 1, 1))
        }, values: ["shared": .string("1 1 1")])
        let sharedAccepted = shared.apply(.string("1 0 0"), forPropertyKey: "shared")
        rows["shared"] = ["accepted": sharedAccepted,
            "published": sharedTargets.allSatisfy { shared.userValues[$0] == .vector3(1, 0, 0) },
            "revision": shared.revision == 1]

        let rejected: [(String, SceneDynamicTarget, SceneDynamicValueType, SceneDynamicValue,
            SceneUserPropertyValue, SceneUserPropertyValue)] = [
            ("effectedImage", .layer(layerID: 4, field: .color), .vector3, .vector3(1, 1, 1),
                .string("1 1 1"), .string("0 1 0")),
            ("missingStyle", .text(layerID: 5, field: .content), .string, .string("old"),
                .string("old"), .string("new")),
            ("missingContent", .text(layerID: 6, field: .content), .string, .string("old"),
                .string("old"), .string("new")),
            ("unlimitedWidth", .text(layerID: 7, field: .maxWidth), .scalar, .scalar(100),
                .number(100), .number(160)),
            ("unknownLayer", .layer(layerID: 8, field: .color), .vector3, .vector3(1, 1, 1),
                .string("1 1 1"), .string("0 1 0")),
        ]
        for (name, target, type, seed, initial, replacement) in rejected {
            var s = state(allLayers, [.init(key: name, target: target, type: type, seed: seed)],
                values: [name: initial])
            let before = s
            let accepted = s.apply(replacement, forPropertyKey: name)
            rows[name] = ["rejected": !accepted, "atomic": unchanged(s, before)]
        }
        var empty = state(allLayers, [], values: ["unused": .number(1)])
        let emptyBefore = empty
        rows["noConsumer"] = ["rejected": !empty.apply(.number(2), forPropertyKey: "unused"),
            "atomic": unchanged(empty, emptyBefore)]
        var missing = state(allLayers, [], values: [:])
        let missingBefore = missing
        rows["unknownKey"] = ["rejected": !missing.apply(.number(2), forPropertyKey: "missing"),
            "atomic": unchanged(missing, missingBefore)]
        let sharedBefore = shared
        let badSharedAccepted = shared.apply(.string("0.2 junk"), forPropertyKey: "shared")
        rows["invalidShared"] = ["rejected": !badSharedAccepted,
            "atomic": unchanged(shared, sharedBefore)]
        print(String(data: try JSONSerialization.data(withJSONObject: rows,
            options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''


class SceneHiddenPropertyConsumerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-hidden-property-")
        work = Path(cls.temp.name)
        source_path = Path(os.environ.get("MWX_HIDDEN_PROPERTY_HOST_SOURCE", HOST_SOURCE))
        host = method_body(source_path.read_text(), "static func activeLiveConsumerTargets(")
        color = method_body(
            LAYER_SOURCE.read_text(), "nonisolated var supportsDirectLayerColorConsumer: Bool"
        )
        harness = work / "Probe.swift"
        harness.write_text(STUBS.replace("__ACTIVE_CONSUMERS__", host)
            .replace("__COLOR_ELIGIBILITY__", color) + HARNESS)
        binary = work / "probe"
        compiled = subprocess.run(
            ["swiftc", "-enable-upcoming-feature", "MemberImportVisibility",
             *map(str, SWIFT_SOURCES), str(VISIBILITY_SOURCE), str(harness),
             "-module-cache-path", str(work / "cache"), "-o", str(binary)],
            capture_output=True, text=True,
        )
        if compiled.returncode:
            cls.temp.cleanup()
            raise AssertionError(compiled.stderr)
        result = subprocess.run([str(binary)], capture_output=True, text=True)
        if result.returncode:
            cls.temp.cleanup()
            raise AssertionError(result.stderr)
        cls.rows = json.loads(result.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def test_hidden_text_fields_publish_and_remain_hidden(self) -> None:
        for case in ("content", "pointSize", "color", "maxWidth"):
            with self.subTest(case=case):
                self.assertEqual(self.rows[case], {
                    "admitted": True, "accepted": True, "published": True,
                    "revision": True, "hidden": True,
                })

    def test_hidden_effectless_image_color_is_live(self) -> None:
        self.assertEqual(self.rows["imageColor"], {
            "admitted": True, "accepted": True, "published": True,
            "revision": True, "hidden": True,
        })

    def test_hidden_dependency_composition_requires_actual_preparation(self) -> None:
        self.assertEqual(self.rows["preparedComposition"], {
            "admitted": True, "accepted": True, "unchanged": False,
        })
        self.assertEqual(self.rows["unpreparedComposition"], {
            "admitted": False, "accepted": False, "unchanged": True,
        })

    def test_visible_and_hidden_shared_key_updates_every_consumer(self) -> None:
        self.assertEqual(self.rows["shared"], {
            "accepted": True, "published": True, "revision": True,
        })

    def test_unsupported_and_invalid_updates_are_atomic(self) -> None:
        for case in ("effectedImage", "missingStyle", "missingContent", "unlimitedWidth",
                     "unknownLayer", "noConsumer", "unknownKey", "invalidShared"):
            with self.subTest(case=case):
                self.assertEqual(self.rows[case], {"rejected": True, "atomic": True})


if __name__ == "__main__":
    unittest.main()
