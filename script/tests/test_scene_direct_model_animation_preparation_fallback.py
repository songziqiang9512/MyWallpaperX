#!/usr/bin/env python3
"""CPU cut of the real direct-model animation preparation and shared runtime.

Only the private resource declarations/method are extracted into their original
namespace. Readers, selector, evaluator, binding program and playback are real
sources. No device, renderer, asset filesystem loader or GPU is constructed.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_scene_prepared_script_resource_catalog import swift_declaration
from script.tests.test_scene_puppet_animation_property_preparation import SWIFT_SOURCES as BASE_SOURCES
from script.tests.test_scene_puppet_playback import SCENE_ROOT

RESOURCE = SCENE_ROOT / "Resources/Textures/ScenePreparedStaticModelResources.swift"
LAYER_LOAD = SCENE_ROOT / "Systems/Puppet/ScenePuppetLayerLoad.swift"
EXTRA = ["Format/SceneMdlStaticModel.swift", "Format/SceneMdlStaticModelReader.swift",
         "Format/SceneMdlPuppetAnimationReader.swift", "Format/SceneMdlPuppetAttachmentReader.swift",
         "Format/ScenePuppetBoneCatalog.swift", "Systems/Script/ScenePuppetBoneTransformBridge.swift"]
SWIFT_SOURCES = list(dict.fromkeys([*BASE_SOURCES, *(SCENE_ROOT / p for p in EXTRA)]))


def production_carrier() -> str:
    resource, layer_load = RESOURCE.read_text(), LAYER_LOAD.read_text()
    declarations = [swift_declaration(resource, marker) for marker in (
        "    enum FutureVisibilityFailure:", "    struct Animation {",
        "    private struct AnimationAsset {", "    private static func prepareAnimation(")]
    return "import Foundation\nimport simd\n" + "\n".join([
        "enum ScenePuppetLayerLoad {\n"
        + swift_declaration(layer_load, "    struct BoneConfiguration {") + "\n"
        + swift_declaration(layer_load, "    static func initialBoneConfiguration(") + "\n}",
        "struct ScenePreparedStaticModelResources {\n" + "\n".join(declarations) + r'''
        static func probe(model: SceneMdlStaticModel,
                          animations: Result<SceneMdlPuppetAnimationSet?, Error>,
                          attachments: Result<[SceneMdlPuppetAttachment], Error>,
                          layers: [ScenePuppetAnimationLayer]) throws -> Animation? {
            try prepareAnimation(asset: .init(model: model, animations: animations,
                                              attachments: attachments), layers: layers)
        }
        }
        ''',
    ])


HARNESS = r'''
import Foundation
import simd

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        var staticModelPath: String? = "models/own/model.mdl"
        var puppetAnimationLayers: [ScenePuppetAnimationLayer]
    }
    var layers: [Layer]
}

@main enum DirectPreparationFallbackHarness {
    static let parent = 71
    static func flatten(_ m: simd_float4x4) -> [Float] {
        [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }
    static func layer(_ id: Int, animation: Int, visible: Bool,
                      prepared: Bool? = true, additive: Bool = false) -> ScenePuppetAnimationLayer {
        var result = ScenePuppetAnimationLayer(id: id, animationID: animation, name: "own",
            additive: additive, blend: 1, blendIn: false, blendOut: false,
            blendTime: 0, rate: 1, visible: visible, visibilityBinding: "mode")
        result.hasPreparedVisibilityProperty = prepared
        return result
    }
    static func animation(_ id: Int, state: SceneMdlPuppetAnimation.TransformTrackState = .sampled,
                          referenceX: Float? = nil, count: Int = 1) -> SceneMdlPuppetAnimation {
        let track = (0...4).map { index in
            SceneMdlPuppetAnimation.Transform(translation: SIMD3(referenceX ?? (3 + Float(index)), 2, 1),
                rotation: .zero, scale: SIMD3(repeating: 1))
        }
        return .init(id: id, name: "own-motion", mode: "loop", framesPerSecond: 2, frameCount: 4,
            transformsByBone: Array(repeating: track, count: count),
            transformTrackStates: Array(repeating: state, count: count))
    }
    static func model(singular: Bool = false, noRig: Bool = false) -> SceneMdlStaticModel {
        var bind = SceneMatrix.translation(SIMD3(3, 2, 1))
        if singular { bind.columns.0.x = 0 }
        let rig = SceneMdlPuppetRig(bones: [.init(name: "own-root", parentIndex: -1,
            bindLocalMatrixColumnMajor: flatten(bind))], vertexWeights: [
                .init(boneIndices: .zero, boneWeights: SIMD4(1, 0, 0, 0))])
        return .init(version: "MDLV0023", headerFormat: 0x0180000f, vertexFormat: 0x0180000f,
            vertexStride: 80, indexElementSize: 2, materialPath: "materials/own/white.json",
            bounds: .init(minimum: [1, 2, 3], maximum: [1, 2, 3]), vertices: [
                .init(position: SIMD3(1, 2, 3), normal: SIMD3(0, 1, 0),
                      tangent: SIMD4(1, 0, 0, 1), uv: SIMD2(0.25, 0.75))],
            indices: [0, 0, 0], geometryState: .bindOnlyAnimationUnqualified,
            rig: noRig ? nil : rig)
    }
    static func program(_ layers: [ScenePuppetAnimationLayer]) -> ScenePropertyBindingProgram {
        let definitions: [SceneDynamicTargetDefinition] = layers.map { layer in
            .init(target: ScenePuppetAnimationPropertyTarget.visibility(
                layerID: parent, animationLayerID: layer.id!), valueType: .bool,
                authoredValue: .bool(layer.visible == true))
        }
        let instructions: [ScenePropertyBindingInstruction] = layers.enumerated().map { index, layer in
            .init(propertyKey: "mode", path: .init(components: [.key("own"), .index(index)]),
                target: ScenePuppetAnimationPropertyTarget.visibility(layerID: parent, animationLayerID: layer.id!),
                valueType: .bool, condition: .string(String(index + 1)))
        }
        return .init(definitions: definitions, instructions: instructions,
            conditionalValueDomainsByPropertyKey: ["mode": layers.indices.map { String($0 + 1) }])
    }
    static func snapshot(_ program: ScenePropertyBindingProgram, _ frame: UInt64,
                         values: [SceneDynamicTarget: SceneDynamicValue]) -> SceneDynamicSnapshot {
        SceneDynamicSnapshotResolver().resolve(frameIndex: frame, generation: frame,
            definitions: program.definitions, userValues: values).snapshot
    }
    static func failureCode(_ value: ScenePreparedStaticModelResources.FutureVisibilityFailure?) -> String {
        guard let value else { return "" }
        switch value {
        case .selection(.unknownAnimation(_)): return "selection.unknownAnimation"
        case .selection(.unsupportedLayer(_)): return "selection.unsupportedLayer"
        case .evaluation(.invalidReferenceTrack(_)): return "evaluation.invalidReferenceTrack"
        case .evaluation(.duplicateAdditiveAnimation(_)): return "evaluation.duplicateAdditiveAnimation"
        case .evaluation(.unsupportedReferenceComposition): return "evaluation.unsupportedReferenceComposition"
        default: return String(describing: value)
        }
    }
    static func summary(_ prepared: ScenePreparedStaticModelResources.Animation,
                        _ layers: [ScenePuppetAnimationLayer]) throws -> [String: Any] {
        let runtime = ScenePuppetAnimationPlaybackRuntime()
        try runtime.register(layerID: parent, selection: prepared.selection, authoredLayers: layers).get()
        let first = runtime.advance(frameIndex: 0, sceneTime: 0, dynamicValues: .empty(frameIndex: 0))
        let next = runtime.advance(frameIndex: 1, sceneTime: 0.5, dynamicValues: .empty(frameIndex: 1))
        let samples = next[parent]!.samples
        let pose = try prepared.evaluator.boneTransforms(selection: prepared.selection, frameSamples: samples)
        let targets = ScenePuppetAnimationPropertyPreparation.visibilityTargets(layerID: parent,
            selection: prepared.selection)
        let bindingProgram = program(layers)
        var live = ScenePropertyLiveUpdateState(program: bindingProgram,
            effectiveValues: ["mode": .string("1")], activeConsumerTargets: targets)
        let previous = live.userValues
        let changed = live.apply(.string("2"), forPropertyKey: "mode")
        let failure = failureCode(prepared.futureVisibilityFailure)
        return ["selected": prepared.selection.clips.map { $0.animation.id },
            "layerDTOUnchanged": prepared.selection.clips.allSatisfy { layers.contains($0.layer) },
            "authoredCount": layers.count, "futureFailure": failure,
            "initialBones": prepared.initialBones?.names ?? [],
            "runtimeIndices": next.animationSnapshots.map { $0.identity.animationLayerIndex },
            "firstActive": first[parent]!.samples.map { $0 != nil },
            "nextSamples": samples.map { $0.map { Double($0.frameA) + Double($0.fraction) } ?? -1 },
            "rootTranslation": [pose.local[0].columns.3.x, pose.local[0].columns.3.y, pose.local[0].columns.3.z],
            "preparedTargetCount": targets.count, "keyHotAccepted": changed,
            "keyStateAtomic": changed || (live.userValues == previous && live.revision == 0)]
    }
    static func probe(_ name: String) throws -> [String: Any] {
        let a = layer(101, animation: 10, visible: true)
        var b = layer(202, animation: 909, visible: false)
        var layers = [b, a]
        var clips = [animation(10)]
        switch name {
        case "missing": break
        case "missing-renamed":
            layers = [layer(7301, animation: 909, visible: false), layer(9702, animation: 10, visible: true)]
        case "old-string": layers[0].hasPreparedVisibilityProperty = nil
        case "explicit-false-flag": layers[0].hasPreparedVisibilityProperty = false
        case "visible-bad": layers[0] = layer(202, animation: 909, visible: true)
        case "reference-selection":
            b = layer(202, animation: 20, visible: false); layers[0] = b
            clips.append(animation(20, state: .referenceCandidate, referenceX: 3))
        case "reference-evaluation":
            b = layer(202, animation: 20, visible: false, additive: true); layers[0] = b
            clips.append(animation(20, state: .referenceCandidate, referenceX: 99))
        case "duplicate": layers[0] = layer(202, animation: 10, visible: false)
        case "bone-count":
            layers[0] = layer(202, animation: 20, visible: false); clips.append(animation(20, count: 2))
        case "singular-rig":
            layers[0] = layer(202, animation: 20, visible: false); clips.append(animation(20))
        case "reader-failure", "attachments-failure", "no-rig": break
        default: fatalError("unknown owned case")
        }
        let animations: Result<SceneMdlPuppetAnimationSet?, Error> = name == "reader-failure"
            ? Result { try SceneMdlPuppetAnimationReader.read(data: Data("OWNINPUTMDLA0006\0".utf8)) }
            : .success(.init(boneCount: 1, animations: clips))
        let attachments: Result<[SceneMdlPuppetAttachment], Error> = name == "attachments-failure"
            ? Result { try SceneMdlPuppetAttachmentReader.read(data: Data("OWNINPUTMDAT0001\0".utf8)) }
            : .success([])
        do {
            guard let prepared = try ScenePreparedStaticModelResources.probe(
                model: model(singular: name == "singular-rig", noRig: name == "no-rig"),
                animations: animations, attachments: attachments, layers: layers)
            else { return ["none": true] }
            return try summary(prepared, layers)
        } catch { return ["error": String(describing: error)] }
    }
    static func healthyEight() throws -> [String: Any] {
        let layers = (0..<8).map { layer(100 + $0, animation: 10 + $0, visible: $0 == 0) }
        let clips = (10..<18).map { animation($0) }
        let prepared = try ScenePreparedStaticModelResources.probe(model: model(),
            animations: .success(.init(boneCount: 1, animations: clips)), attachments: .success([]), layers: layers)!
        let runtime = ScenePuppetAnimationPlaybackRuntime()
        try runtime.register(layerID: parent, selection: prepared.selection, authoredLayers: layers).get()
        let bindingProgram = program(layers)
        let targets = ScenePuppetAnimationPropertyPreparation.visibilityTargets(layerID: parent, selection: prepared.selection)
        var live = ScenePropertyLiveUpdateState(program: bindingProgram,
            effectiveValues: ["mode": .string("1")], activeConsumerTargets: targets)
        var active: [[Int]] = [], accepted: [Bool] = []
        for (frame, value) in ["1", "2", "1"].enumerated() {
            accepted.append(live.apply(.string(value), forPropertyKey: "mode"))
            let frameResult = runtime.advance(frameIndex: UInt64(frame), sceneTime: Double(frame) * 0.5,
                dynamicValues: snapshot(bindingProgram, UInt64(frame), values: live.userValues))
            active.append(frameResult[parent]!.samples.enumerated().compactMap { $0.element == nil ? nil : $0.offset })
        }
        return ["selectedCount": prepared.selection.clips.count, "futureFailureAbsent": prepared.futureVisibilityFailure == nil,
            "layerDTOUnchanged": prepared.selection.clips.map(\.layer) == layers,
            "targets": targets.count, "accepted": accepted, "active": active]
    }
    static func projectionFacts() -> [String: Any] {
        let root: [String: Any] = ["objects": [["id": parent, "model": "models/own/model.mdl",
            "animationlayers": [["id": 101, "animation": 10, "visible": ["value": true,
                "user": ["name": "mode", "condition": "1"]]],
                ["id": 202, "animation": 20, "visible": ["value": false,
                "user": ["name": "mode", "condition": "2"]]],
                ["id": 303, "animation": 30, "visible": ["value": true, "user": "old"]]]]]]
        let catalog = SceneUserPropertyDefinitionParser().parse(properties: [
            "mode": ["type": "combo", "value": "1", "options": [
                ["label": "one", "value": "1"], ["label": "two", "value": "2"]]],
            "old": ["type": "bool", "value": true]])
        let resolved = SceneUserPropertyDocumentResolver().resolve(root: root, catalog: catalog, overrides: [:])
        let object = (resolved.root["objects"] as! [[String: Any]])[0]
        let rawLayers = ScenePuppetAnimationLayer.parse(object["animationlayers"])
        let descriptor = SceneRenderDescriptor(layers: [.init(id: parent, puppetAnimationLayers: rawLayers)])
        let program = ScenePropertyBindingCompiler().compile(report: resolved.bindingReport, catalog: catalog).program
        let result = ScenePuppetAnimationPropertyPreparation.applyingBindings(program,
            report: resolved.bindingReport, to: descriptor).layers[0].puppetAnimationLayers
        return ["rawProvenanceAbsent": rawLayers.allSatisfy { $0.hasPreparedVisibilityProperty == nil },
            "objectFlags": result.prefix(2).map { $0.hasPreparedVisibilityProperty == true },
            "objectKeys": result.prefix(2).map { $0.visibilityBinding ?? "" },
            "oldStringKey": result[2].visibilityBinding ?? "", "oldStringFlagAbsent": result[2].hasPreparedVisibilityProperty == nil]
    }
    static func missingBool(prepared: Bool?, visible: Bool) throws -> [Bool] {
        let value = layer(333, animation: 10, visible: visible, prepared: prepared)
        let selected = try ScenePuppetAnimationSelector.select(layers: [value],
            animationSet: .init(boneCount: 1, animations: [animation(10)])).get()!
        let runtime = ScenePuppetAnimationPlaybackRuntime()
        try runtime.register(layerID: parent, selection: selected, authoredLayers: [value]).get()
        return runtime.advance(frameIndex: 0, sceneTime: 0,
            dynamicValues: .empty(frameIndex: 0))[parent]!.samples.map { $0 != nil }
    }
    static func main() throws {
        var output: [String: Any] = [:]
        for name in ["missing", "missing-renamed", "old-string", "explicit-false-flag", "visible-bad",
                     "reference-selection", "reference-evaluation", "duplicate", "bone-count", "singular-rig",
                     "reader-failure", "attachments-failure", "no-rig"] { output[name] = try probe(name) }
        output["healthy-eight"] = try healthyEight()
        output["projection"] = projectionFacts()
        output["missing-bool"] = ["newVisible": try missingBool(prepared: true, visible: true),
            "newHidden": try missingBool(prepared: true, visible: false),
            "oldString": try missingBool(prepared: nil, visible: true)]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class DirectModelAnimationPreparationFallbackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        retained = os.environ.get("MWX_DIRECT_ANIMATION_FALLBACK_OUTPUT")
        cls.temporary = None if retained else tempfile.TemporaryDirectory(prefix="mwx-animation-fallback-")
        cls.directory = Path(retained or cls.temporary.name)
        cls.directory.mkdir(parents=True, exist_ok=True)
        carrier = cls.directory / "ProductionPreparation.swift"
        carrier.write_text(production_carrier())
        harness = cls.directory / "Harness.swift"
        harness.write_text(HARNESS)
        paths = list(dict.fromkeys([Path(__file__), RESOURCE, LAYER_LOAD, *SWIFT_SOURCES, carrier, harness]))
        identities = lambda: {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        before = identities()
        (cls.directory / "inputs-before.json").write_text(json.dumps(before, indent=2))
        binary = cls.directory / "preparation-fallback"
        command = ["swiftc", *map(str, SWIFT_SOURCES), str(carrier), str(harness),
                   "-module-cache-path", str(cls.directory / "module-cache"), "-o", str(binary)]
        (cls.directory / "compile-command.json").write_text(json.dumps(command, indent=2))
        compiled = subprocess.run(command, capture_output=True, text=True, timeout=90)
        (cls.directory / "compile.stdout").write_text(compiled.stdout)
        (cls.directory / "compile.stderr").write_text(compiled.stderr)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        completed = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
        (cls.directory / "raw.stdout").write_text(completed.stdout)
        (cls.directory / "raw.stderr").write_text(completed.stderr)
        if completed.returncode:
            raise RuntimeError(completed.stderr)
        cls.rows = json.loads(completed.stdout)
        after = identities()
        (cls.directory / "inputs-after.json").write_text(json.dumps(after, indent=2))
        cls.source_drift = {p: [sha, after[p]] for p, sha in before.items() if after[p] != sha}

    @classmethod
    def tearDownClass(cls):
        if cls.temporary:
            cls.temporary.cleanup()

    def test_hidden_new_future_failure_preserves_healthy_pose_and_authored_registration(self):
        for name in ("missing", "missing-renamed", "reference-selection", "reference-evaluation", "duplicate"):
            row = self.rows[name]
            with self.subTest(name=name):
                self.assertNotIn("error", row, row)
                self.assertEqual(row["selected"], [10])
                self.assertTrue(row["futureFailure"])
                self.assertTrue(row["layerDTOUnchanged"])
                self.assertEqual(row["authoredCount"], 2)
                self.assertEqual(row["runtimeIndices"], [1])
                self.assertEqual(row["firstActive"], [True])
                self.assertEqual(row["nextSamples"], [1])
                self.assertEqual(row["rootTranslation"], [4, 2, 1])
                self.assertEqual(row["initialBones"], ["own-root"])

    def test_first_typed_reason_is_retained_and_incomplete_key_cannot_apply_partially(self):
        expected = {"missing": "unknownAnimation", "reference-selection": "unsupportedLayer",
                    "reference-evaluation": "invalidReferenceTrack", "duplicate": "duplicateAdditiveAnimation"}
        for name, reason in expected.items():
            row = self.rows[name]
            self.assertIn(reason, row["futureFailure"])
            self.assertEqual(row["preparedTargetCount"], 1)
            self.assertFalse(row["keyHotAccepted"])
            self.assertTrue(row["keyStateAtomic"])

    def test_legacy_required_or_currently_visible_failure_does_not_retry(self):
        for name in ("old-string", "explicit-false-flag", "visible-bad"):
            self.assertIn("animation id 909 is absent", self.rows[name]["error"])
            self.assertNotIn("selected", self.rows[name])

    def test_structural_errors_are_not_reclassified_as_optional_future_failures(self):
        expected = {"reader-failure": "unsupported animation mdl magic OWNINPUT",
                    "attachments-failure": "unsupported attachment mdl magic OWNINPUT",
                    "singular-rig": "singular", "bone-count": "bone counts do not match"}
        for name, reason in expected.items():
            self.assertIn(reason, self.rows[name]["error"])
            self.assertNotIn("selected", self.rows[name])
        self.assertEqual(self.rows["no-rig"], {"none": True})

    def test_healthy_eight_conditions_prepare_once_and_switch_as_a_complete_group(self):
        row = self.rows["healthy-eight"]
        self.assertEqual(row["selectedCount"], 8)
        self.assertTrue(row["futureFailureAbsent"])
        self.assertTrue(row["layerDTOUnchanged"])
        self.assertEqual(row["targets"], 8)
        self.assertEqual(row["accepted"], [True, True, True])
        self.assertEqual(row["active"], [[0], [1], [0]])

    def test_missing_bool_fallback_is_provenance_specific(self):
        self.assertEqual(self.rows["missing-bool"],
                         {"newVisible": [True], "newHidden": [False], "oldString": [False]})

    def test_provenance_is_only_projected_for_validated_new_object_markers(self):
        row = self.rows["projection"]
        self.assertTrue(row["rawProvenanceAbsent"])
        self.assertEqual(row["objectFlags"], [True, True])
        self.assertEqual(row["objectKeys"], ["mode", "mode"])
        self.assertEqual(row["oldStringKey"], "old")
        self.assertTrue(row["oldStringFlagAbsent"])

    def test_frozen_production_inputs_have_no_drift(self):
        self.assertEqual(self.source_drift, {})


if __name__ == "__main__":
    unittest.main()
