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
CATALOG_SOURCE = SCENE / "Compilation/Material/SceneResolvedMaterialRuntimeCatalog.swift"
SOURCE_MATERIAL_SOURCE = SCENE / "Rendering/Graph/SceneResolvedMaterialRuntimeBridge+SourceMaterials.swift"
SOURCE_MATERIAL_STORAGE_SOURCE = SCENE / "Rendering/Graph/SceneResolvedMaterialRuntimeBridge.swift"
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
    struct Camera {
        struct Bloom {
            struct HDR {}
            var hdr: HDR? = nil
        }
        var orthoWidth: Float? = 512
        var orthoHeight: Float? = 512
        var bloom = Bloom()
    }
    struct Layer {
        var id: Int
        var contentKind: String
        var imagePath: String? = nil
        var visible: Bool? = false
        var parentID: Int? = nil
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil
        var text: String? = nil
        var textStyle: TextStyle? = nil
        var staticModelPath: String? = nil
        var puppetMeshPath: String? = nil
        var effects: [Int] = []
        var authoredDependencies: [Int] = []
        var dependencyLayerIDs: [Int] = []
        var puppetAnimationLayers: [AnimationLayer] = []
        __COLOR_ELIGIBILITY__
    }
    var layers: [Layer]
    var camera = Camera()
}

struct SceneResolvedMaterialRuntimeCatalog {
    struct Key { var layerID: Int }
    enum Entry { case template, failure }
    struct SourceMaterialEntry {
        var key: Key
        var entry: Entry
        var sharedModelPath: String? = nil
        __MODEL_PATH_IDENTITY__
    }
    var sourceMaterialEntries: [Int: SourceMaterialEntry]
    __SOURCE_CANDIDATES__
}

// Prepared-program dictionaries are leaves. Alias lookup is the production
// runtime method, so the candidate projection must cover the same consumers.
final class SceneResolvedMaterialRuntimeBridge {
    struct PreparedSourceMaterial { var sharedModelPath: String? }
    struct SourceMaterialConsumer { var layerID: Int; var prototypeLayerID: Int }
    __SOURCE_MATERIAL_STORAGE__
    private(set) var sourceMaterialPrototypeByModel: [String: Int] = [:]
    __SOURCE_MATERIAL_CONSUMER__
}

struct SceneResolvedMaterialExecutionCapabilityCatalog {
    enum SourceRoute { case capturedLayerTexture, capturedMainTargetTexture, transparentDirectDraw }
    enum DependencyOwnership { case none, graphInternal, externalPrimary, externalAggregate }
    struct Capability {
        var sourceRoute: SourceRoute = .capturedLayerTexture
        var dependencyOwnership: DependencyOwnership = .none
    }
    struct Token { var layerID: Int }
    struct Claim { var token: Token }
    var executionLayerIDs: Set<Int> = []
    var admittedResolvedMaterialReferences: [Int] = []
    var liveConsumerTargets: Set<SceneDynamicTarget> = []
    var capabilities: [Int: Capability] = [:]
    var unresolvedLayerIDs: Set<Int> = []
    // Capability outcomes are leaves; the production Host owns admission.
    func claim(layerID: Int) -> Claim? {
        capabilities[layerID].map { _ in .init(token: .init(layerID: layerID)) }
    }
    func resolve(_ token: Token) -> Capability? {
        unresolvedLayerIDs.contains(token.layerID) ? nil : capabilities[token.layerID]
    }
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
        values: [String: SceneUserPropertyValue], prepared: Set<Int> = [],
        colorCapabilities: [Int: SceneResolvedMaterialExecutionCapabilityCatalog.Capability] = [:],
        unresolved: Set<Int> = [], sourceCandidates: Set<Int> = [])
        -> ScenePropertyLiveUpdateState {
        let p = program(bindings)
        let targets = SceneDesktopWallpaperHost.activeLiveConsumerTargets(
            in: .init(layers: layers), propertyBindingProgram: p,
            resolvedMaterialExecutionCapabilities: .init(executionLayerIDs: prepared,
                capabilities: colorCapabilities, unresolvedLayerIDs: unresolved),
            soundPlaybackProgram: .init(), preparedStaticModelLayerIDs: [],
            preparedImageMaterialTargets: [], sourceMaterialCandidateConsumerLayerIDs: sourceCandidates,
            propertyVectorScriptProgram: .init(),
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
        let effectColor = SceneDynamicTarget.layer(layerID: 4, field: .color)
        let effectBinding = Binding(key: "renamedTint", target: effectColor,
            type: .vector3, seed: .vector3(1, 1, 1))
        typealias ColorCapability = SceneResolvedMaterialExecutionCapabilityCatalog.Capability
        for (name, capability, unresolved, completed) in [
            ("capturedImage", ColorCapability(), false, false),
            ("missingClaim", nil, false, false),
            ("unresolvedClaim", ColorCapability(), true, false),
            ("capturedMain", ColorCapability(sourceRoute: .capturedMainTargetTexture), false, false),
            ("transparentSource", ColorCapability(sourceRoute: .transparentDirectDraw), false, false),
            ("internalDependency", ColorCapability(dependencyOwnership: .graphInternal), false, false),
            ("externalProvider", ColorCapability(dependencyOwnership: .externalPrimary), false, false),
            ("aggregateProvider", ColorCapability(dependencyOwnership: .externalAggregate), false, false),
            ("sourceTemplateCandidate", ColorCapability(), false, true),
        ] as [(String, ColorCapability?, Bool, Bool)] {
            var s = state([effectedImage], [effectBinding], values: ["renamedTint": .string("1 1 1")],
                colorCapabilities: capability.map { [4: $0] } ?? [:],
                unresolved: unresolved ? [4] : [], sourceCandidates: completed ? [4] : [])
            let before = s
            let accepted = s.apply(.string("0.2 0.4 0.6"), forPropertyKey: "renamedTint")
            rows[name] = ["potential": effectedImage.supportsUserPropertyLayerColorConsumer,
                "admitted": s.activeConsumerTargets.contains(effectColor), "accepted": accepted,
                "published": s.userValues[effectColor] == .vector3(0.2, 0.4, 0.6),
                "unchanged": unchanged(s, before), "scriptUnchanged": !effectedImage.supportsDirectLayerColorConsumer]
        }
        // No runtime or PSO success is supplied: a template can warm on another
        // surface after the first one failed. Only the catalog owns this fact.
        let alias = SceneRenderDescriptor.Layer(id: 14, contentKind: "image",
            imagePath: " Models\\Shared.JSON ", effects: [1])
        let failed = SceneRenderDescriptor.Layer(id: 15, contentKind: "image",
            imagePath: "models/failed.json", effects: [1])
        let absent = SceneRenderDescriptor.Layer(id: 16, contentKind: "image",
            imagePath: "models/absent.json", effects: [1])
        let sourceCatalog = SceneResolvedMaterialRuntimeCatalog(sourceMaterialEntries: [
            4: .init(key: .init(layerID: 4), entry: .template, sharedModelPath: "models/shared.json"),
            15: .init(key: .init(layerID: 15), entry: .failure, sharedModelPath: "models/failed.json"),
        ])
        let candidates = sourceCatalog.sourceMaterialCandidateConsumerLayerIDs(
            in: .init(layers: [effectedImage, alias, failed, absent]))
        let firstSurface = SceneResolvedMaterialRuntimeBridge()
        let laterSurface = SceneResolvedMaterialRuntimeBridge()
        laterSurface.sourceMaterials = [4: .init(sharedModelPath: "models/shared.json")]
        let ambiguousSurface = SceneResolvedMaterialRuntimeBridge()
        ambiguousSurface.sourceMaterials = [4: .init(sharedModelPath: "models/shared.json"),
            18: .init(sharedModelPath: "models/shared.json")]
        rows["sourceCandidateProjection"] = ["templateWithoutRuntimeExcluded": candidates.contains(4),
            "normalizedSharedAliasExcluded": candidates.contains(14),
            "firstSurfaceHasNoPreparedSource": firstSurface.sourceMaterialConsumer(
                layerID: alias.id, modelPath: alias.imagePath) == nil,
            "laterSurfaceUsesSameAlias": laterSurface.sourceMaterialConsumer(
                layerID: alias.id, modelPath: alias.imagePath)?.prototypeLayerID == 4,
            "ambiguousRuntimeKeepsOriginalRejection": ambiguousSurface.sourceMaterialConsumer(
                layerID: alias.id, modelPath: alias.imagePath) == nil,
            "failedTemplateNotExcluded": !candidates.contains(15),
            "missingTemplateNotExcluded": !candidates.contains(16), "exactSet": candidates == [4, 14]]
        for (name, layer) in [("coldTemplate", effectedImage), ("sharedSourceAlias", alias),
                              ("failedSourceTemplate", failed), ("noSourceCandidate", absent)] {
            let target = SceneDynamicTarget.layer(layerID: layer.id, field: .color)
            var s = state([layer], [.init(key: "differentTint", target: target,
                type: .vector3, seed: .vector3(1, 1, 1))], values: ["differentTint": .string("1 1 1")],
                colorCapabilities: [layer.id: .init()], sourceCandidates: candidates)
            let before = s
            let accepted = s.apply(.string("0 1 0"), forPropertyKey: "differentTint")
            rows[name] = ["accepted": accepted, "published": s.userValues[target] == .vector3(0, 1, 0),
                "unchanged": unchanged(s, before)]
        }
        for (name, layer) in [
            ("puppetImage", SceneRenderDescriptor.Layer(id: 4, contentKind: "image",
                puppetMeshPath: "renamed.mdl", effects: [1])),
            ("modelImage", SceneRenderDescriptor.Layer(id: 4, contentKind: "image",
                staticModelPath: "renamed.model", effects: [1])),
            ("dependentImage", SceneRenderDescriptor.Layer(id: 4, contentKind: "image",
                effects: [1], authoredDependencies: [91])),
        ] {
            var s = state([layer], [effectBinding], values: ["renamedTint": .string("1 1 1")],
                colorCapabilities: [4: .init()])
            let before = s
            rows[name] = ["potentialRejected": !layer.supportsUserPropertyLayerColorConsumer,
                "rejected": !s.apply(.string("0 1 0"), forPropertyKey: "renamedTint"),
                "atomic": unchanged(s, before)]
        }
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
        color += "\n" + method_body(
            LAYER_SOURCE.read_text(), "nonisolated var supportsUserPropertyLayerColorConsumer: Bool"
        )
        harness = work / "Probe.swift"
        harness.write_text(STUBS.replace("__ACTIVE_CONSUMERS__", host)
            .replace("__COLOR_ELIGIBILITY__", color)
            .replace("__SOURCE_CANDIDATES__", method_body(CATALOG_SOURCE.read_text(),
                "func sourceMaterialCandidateConsumerLayerIDs("))
            .replace("__MODEL_PATH_IDENTITY__", method_body(CATALOG_SOURCE.read_text(),
                "static func modelPathIdentity("))
            .replace("__SOURCE_MATERIAL_STORAGE__", method_body(SOURCE_MATERIAL_STORAGE_SOURCE.read_text(),
                "var sourceMaterials:"))
            .replace("__SOURCE_MATERIAL_CONSUMER__", method_body(SOURCE_MATERIAL_SOURCE.read_text(),
                "func sourceMaterialConsumer(")) + HARNESS)
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

    def test_effectful_color_requires_a_prepared_independent_layer_capture(self) -> None:
        self.assertEqual(self.rows["capturedImage"], {
            "potential": True, "admitted": True, "accepted": True, "published": True,
            "unchanged": False, "scriptUnchanged": True,
        })
        for case in ("missingClaim", "unresolvedClaim", "capturedMain", "transparentSource",
                     "internalDependency", "externalProvider", "aggregateProvider", "sourceTemplateCandidate"):
            with self.subTest(case=case):
                self.assertEqual(self.rows[case], {
                    "potential": True, "admitted": False, "accepted": False, "published": False,
                    "unchanged": True, "scriptUnchanged": True,
                })

    def test_source_templates_exclude_every_surface_and_normalized_shared_alias(self) -> None:
        self.assertTrue(all(self.rows["sourceCandidateProjection"].values()), self.rows)
        for case in ("coldTemplate", "sharedSourceAlias"):
            with self.subTest(case=case):
                self.assertEqual(self.rows[case], {"accepted": False, "published": False, "unchanged": True})
        for case in ("failedSourceTemplate", "noSourceCandidate"):
            with self.subTest(case=case):
                self.assertEqual(self.rows[case], {"accepted": True, "published": True, "unchanged": False})

    def test_puppet_model_and_dependency_do_not_gain_the_ordinary_image_route(self) -> None:
        for case in ("puppetImage", "modelImage", "dependentImage"):
            with self.subTest(case=case):
                self.assertEqual(self.rows[case], {
                    "potentialRejected": True, "rejected": True, "atomic": True,
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
