#!/usr/bin/env python3
"""Real property preparation and shared animation cadence; CPU only.

The descriptor is a leaf carrier. Binding parsing, compilation, live updates,
snapshot resolution, selector and playback are production sources.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_property_live_update_state import SWIFT_SOURCES as PROPERTY_SOURCES
from script.tests.test_scene_puppet_playback import SCENE_ROOT, SWIFT_SOURCES as PUPPET_SOURCES

EXTRA = [
    "Systems/Properties/SceneUserPropertyDefinitionParser.swift",
    "Systems/Properties/SceneUserPropertyResolver.swift",
    "Systems/Properties/ScenePuppetAnimationPropertyPreparation.swift",
    "Systems/Puppet/ScenePuppetAnimationPlaybackRuntime.swift",
    "Systems/Puppet/ScenePuppetAnimationControl.swift",
]
# Exclude the old unrelated retired-callback fixture, which refers to its own main.
SWIFT_SOURCES = list(dict.fromkeys([
    *(p for p in PROPERTY_SOURCES if p.name != "SceneRetiredCallbackLiveUpdateChecks.swift"),
    *PUPPET_SOURCES, *(SCENE_ROOT / p for p in EXTRA),
]))
SERVICE_SOURCE = SCENE_ROOT.parents[1] / "Modules/SteamWorkshop/Scene/SteamWorkshopSceneService+SceneProperties.swift"


def service_target_carrier() -> str:
    """Compile the complete existing eligibility methods; never copy their decisions."""
    source = SERVICE_SOURCE.read_text()
    def method(marker: str) -> str:
        start = source.index(marker)
        body = source.index("{", start)
        end, depth = body + 1, 1
        while depth:
            depth += (source[end] == "{") - (source[end] == "}")
            end += 1
        return source[start:end]
    supports = method("    private func supportsScenePropertyTarget(").replace(
        "private func supportsScenePropertyTarget", "static func supportsScenePropertyTarget", 1)
    effects = method("    private static func hasAuthoredEffect(")
    return "\nenum SceneServiceTargetCarrier {\n" + supports + "\n" + effects + "\n}\n"

HARNESS = r'''
import Foundation
import simd

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let contentKind: String
        var staticModelPath: String? = nil
        var puppetAnimationLayers: [ScenePuppetAnimationLayer]
        var supportsUserPropertyImageSourceModulationConsumer = false
        var supportsUserPropertyLayerColorConsumer = false
        var authoredLightIntensity: Double? = nil
        struct Effect { let file: String }
        var effects: [Effect] = []
    }
    var layers: [Layer]
    struct Camera {
        var default2DInputLayerID: Int? = nil
        var orthoWidth: Float? = nil
        var orthoHeight: Float? = nil
    }
    var camera = Camera()
}

@main enum Harness {
    static let ids = [56, 150, 120, 135, 153, 176, 208, 210]
    struct Fixture {
        let report: SceneUserPropertyBindingReport
        let program: ScenePropertyBindingProgram
        let descriptor: SceneRenderDescriptor
        let prepared: SceneRenderDescriptor
        let effective: [String: SceneUserPropertyValue]
    }
    static func root(key: String = "mode", hosts: Int = 1, imagePeer: Bool = false) -> [String: Any] {
        var objects: [[String: Any]] = [["id": 99, "image": "models/own/unrelated.json"]]
        for host in 0..<hosts {
            let animations: [[String: Any]] = ids.enumerated().map { index, id in
                ["id": id, "animation": 100 + index, "name": "own-\(index)",
                 "visible": ["value": index == 0,
                    "user": ["name": key, "condition": String(index + 1)]],
                 "rate": 1, "additive": false, "blend": 1]
            }
            var object: [String: Any] = ["id": 10 + host * 10, "animationlayers": animations]
            object[host == 0 || !imagePeer ? "model" : "image"] = "models/own/renamed-\(host).mdl"
            objects.append(object)
        }
        return ["objects": objects]
    }
    static func catalog(_ key: String = "mode", kind: String = "combo") -> SceneUserPropertyCatalog {
        SceneUserPropertyDefinitionParser().parse(properties: [key: [
            "type": kind, "value": "1", "options": (1...8).map {
                ["label": "Option \($0)", "value": String($0)]
            }]])
    }
    static func fixture(_ source: [String: Any], catalog: SceneUserPropertyCatalog,
                        overrides: [String: SceneUserPropertyValue] = [:]) -> Fixture {
        let resolution = SceneUserPropertyDocumentResolver().resolve(
            root: source, catalog: catalog, overrides: overrides)
        let objects = resolution.root["objects"] as! [[String: Any]]
        let layers = objects.reversed().map { object in
            SceneRenderDescriptor.Layer(id: object["id"] as! Int,
                contentKind: object["model"] != nil ? "model" : "image",
                staticModelPath: object["model"] as? String,
                puppetAnimationLayers: ScenePuppetAnimationLayer.parse(object["animationlayers"]))
        }
        let descriptor = SceneRenderDescriptor(layers: layers)
        let program = ScenePropertyBindingCompiler().compile(
            report: resolution.bindingReport, catalog: catalog).program
        return .init(report: resolution.bindingReport, program: program, descriptor: descriptor,
            prepared: ScenePuppetAnimationPropertyPreparation.applyingBindings(
                program, report: resolution.bindingReport, to: descriptor),
            effective: catalog.effectiveValues(overrides: overrides))
    }
    static func layer(_ descriptor: SceneRenderDescriptor, _ id: Int = 10)
        -> SceneRenderDescriptor.Layer { descriptor.layers.first { $0.id == id }! }
    static func markers(_ descriptor: SceneRenderDescriptor, _ id: Int = 10) -> [String] {
        layer(descriptor, id).puppetAnimationLayers.map { $0.visibilityBinding ?? "" }
    }
    static func mutate(_ source: [String: Any], index: Int = 0,
                       _ body: (inout [String: Any]) -> Void) -> [String: Any] {
        var root = source
        var objects = root["objects"] as! [[String: Any]]
        var animations = objects[1]["animationlayers"] as! [[String: Any]]
        body(&animations[index]); objects[1]["animationlayers"] = animations
        root["objects"] = objects; return root
    }
    static func clip(_ id: Int, alpha: Bool = false, aux: Bool = false) -> SceneMdlPuppetAnimation {
        .init(id: id, name: "own", mode: "loop", framesPerSecond: 2, frameCount: 8,
            transformsByBone: [(0...8).map {
                .init(translation: SIMD3(Float($0), 0, 0), rotation: .zero, scale: SIMD3(repeating: 1))
            }], alphaByBone: alpha ? [Array(repeating: 0.5, count: 9)] : nil,
            hasAuxiliaryScalarTrack: aux)
    }
    static func selection(_ descriptor: SceneRenderDescriptor, _ parent: Int = 10)
        throws -> ScenePuppetAnimationSelection {
        let set = SceneMdlPuppetAnimationSet(boneCount: 1, animations: (100..<108).map { clip($0) })
        guard let selected = try ScenePuppetAnimationSelector.select(
            layers: layer(descriptor, parent).puppetAnimationLayers, animationSet: set).get()
        else { throw Failure.noSelection }
        return selected
    }
    static func snapshot(_ f: Fixture, _ frame: UInt64,
                         values: [SceneDynamicTarget: SceneDynamicValue]) -> SceneDynamicSnapshot {
        SceneDynamicSnapshotResolver().resolve(frameIndex: frame, generation: frame,
            definitions: f.program.definitions, userValues: values).snapshot
    }
    static func active(_ frame: ScenePuppetAnimationPlaybackRuntime.FrameSnapshot,
                       parent: Int = 10) -> [Int] {
        frame[parent]!.samples.enumerated().compactMap { $0.element == nil ? nil : $0.offset }
    }
    static func phase(_ frame: ScenePuppetAnimationPlaybackRuntime.FrameSnapshot,
                      index: Int, parent: Int = 10) -> Double {
        guard let s = frame[parent]!.samples[index] else { return -1 }
        return Double(s.frameA) + Double(s.fraction) * Double(s.frameB - s.frameA)
    }
    enum Failure: Error { case noSelection }

    static func main() throws {
        var output: [String: Any] = [:]
        let f = fixture(root(), catalog: catalog())
        output["initial"] = ["markers": markers(f.prepared),
            "before": markers(f.descriptor), "descriptorOrder": f.prepared.layers.map(\.id),
            "programTargets": f.program.instructions.count]
        let renamed = fixture(root(key: "renamed-σ"), catalog: catalog("renamed-σ"))
        output["renamed"] = markers(renamed.prepared)
        let imagePeer = fixture(root(hosts: 2, imagePeer: true), catalog: catalog())
        let directTargets = ScenePuppetAnimationPropertyPreparation.visibilityTargets(
            layerID: 10, selection: try selection(imagePeer.prepared))
        var unsupportedImageLive = ScenePropertyLiveUpdateState(program: imagePeer.program,
            effectiveValues: imagePeer.effective, activeConsumerTargets: directTargets)
        let imageBefore = unsupportedImageLive.userValues
        output["imageObject"] = ["modelMarkers": markers(imagePeer.prepared),
            "imageMarkers": markers(imagePeer.prepared, 20),
            "partialApplyRejected": !unsupportedImageLive.apply(.string("2"), forPropertyKey: "mode")
                && unsupportedImageLive.userValues == imageBefore]
        let cardTarget = SceneUserPropertyBindingTarget.puppetAnimationVisibility(
            layerID: 10, animationLayerID: ids[0])
        output["propertyCard"] = ["before": SceneServiceTargetCarrier.supportsScenePropertyTarget(
            cardTarget, in: f.descriptor, materialTargets: []),
            "after": SceneServiceTargetCarrier.supportsScenePropertyTarget(
                cardTarget, in: f.prepared, materialTargets: []),
            "imageObject": SceneServiceTargetCarrier.supportsScenePropertyTarget(
                .puppetAnimationVisibility(layerID: 20, animationLayerID: ids[0]),
                in: imagePeer.prepared, materialTargets: [])]
        let equivalent = fixture(mutate(root()) {
            $0["visible"] = ["user": ["condition": "1", "name": " \tmode\n"], "value": true]
        }, catalog: catalog())
        output["equivalentReference"] = markers(equivalent.prepared)
        var rejections: [String: Any] = [:]
        let invalid: [(String, [String: Any], SceneUserPropertyCatalog)] = [
            ("missingCatalog", root(), .empty),
            ("wrongKind", root(), catalog(kind: "textinput")),
            ("malformedName", mutate(root()) {
                $0["visible"] = ["value": true, "user": ["name": 3, "condition": "1"]]
            }, catalog()),
            ("unsupportedCondition", mutate(root()) {
                $0["visible"] = ["value": true, "user": ["name": "mode", "condition": [1, 2]]]
            }, catalog()),
            ("noConditionCombo", mutate(root()) {
                $0["visible"] = ["value": true, "user": ["name": "mode"]]
            }, catalog()),
        ]
        for (name, source, catalog) in invalid {
            let value = fixture(source, catalog: catalog)
            let before = layer(value.descriptor).puppetAnimationLayers[0]
            let after = layer(value.prepared).puppetAnimationLayers[0]
            rejections[name] = ["firstMarker": after.visibilityBinding ?? "",
                "fallbackUnchanged": before.visible == after.visible,
                "firstVisible": after.visible ?? false]
        }
        output["rejections"] = rejections
        let duplicateIDs = fixture(mutate(root(), index: 1) { $0["id"] = ids[0] }, catalog: catalog())
        output["duplicateAnimationIDs"] = Array(markers(duplicateIDs.prepared).prefix(2))
        var duplicateParents = f.descriptor
        duplicateParents.layers.append(layer(f.descriptor))
        output["duplicateParents"] = ScenePuppetAnimationPropertyPreparation.applyingBindings(
            f.program, report: f.report, to: duplicateParents).layers
                .filter { $0.id == 10 }.flatMap { $0.puppetAnimationLayers }
                .compactMap(\.visibilityBinding)

        let original = f.report.bindings.first { $0.target ==
            .puppetAnimationVisibility(layerID: 10, animationLayerID: ids[0]) }!
        let wrongPath = SceneUserPropertyPath(components: [
            .key("objects"), .index(1), .key("animationlayers"), .index(1), .key("visible")])
        let badBinding = SceneUserPropertyBinding(reference: original.reference,
            fallbackValue: original.fallbackValue, path: wrongPath, target: original.target)
        let report = SceneUserPropertyBindingReport(bindings: [badBinding], diagnostics: [])
        let badProgram = ScenePropertyBindingCompiler().compile(report: report, catalog: catalog()).program
        output["wrongPathID"] = markers(ScenePuppetAnimationPropertyPreparation.applyingBindings(
            badProgram, report: report, to: f.descriptor))
        output["reportPathMismatch"] = markers(ScenePuppetAnimationPropertyPreparation.applyingBindings(
            f.program, report: report, to: f.descriptor))
        let changedReference = SceneUserPropertyBinding(reference: .init(key: "other", condition: .string("1")),
            fallbackValue: original.fallbackValue, path: original.path, target: original.target)
        output["reportProgramMismatch"] = markers(ScenePuppetAnimationPropertyPreparation.applyingBindings(
            f.program, report: .init(bindings: [changedReference], diagnostics: []), to: f.descriptor))
        let wrongCondition = SceneUserPropertyBinding(reference: .init(key: "mode", condition: .string("2")),
            fallbackValue: original.fallbackValue, path: original.path, target: original.target)
        output["reportConditionMismatch"] = markers(ScenePuppetAnimationPropertyPreparation.applyingBindings(
            f.program, report: .init(bindings: [wrongCondition], diagnostics: []), to: f.descriptor))
        let wrongTarget = SceneUserPropertyBinding(reference: original.reference,
            fallbackValue: original.fallbackValue, path: original.path,
            target: .puppetAnimationVisibility(layerID: 10, animationLayerID: ids[1]))
        output["reportTargetMismatch"] = markers(ScenePuppetAnimationPropertyPreparation.applyingBindings(
            f.program, report: .init(bindings: [wrongTarget], diagnostics: []), to: f.descriptor))
        output["duplicateReportPath"] = markers(ScenePuppetAnimationPropertyPreparation.applyingBindings(
            f.program, report: .init(bindings: [original, original], diagnostics: []), to: f.descriptor))

        var mixedRoot = root(hosts: 2)
        var mixedObjects = mixedRoot["objects"] as! [[String: Any]]
        mixedObjects[1]["unsupportedValue"] = ["value": true,
            "user": ["name": "mode", "condition": "1"]]
        var healthyAnimations = mixedObjects[2]["animationlayers"] as! [[String: Any]]
        for index in healthyAnimations.indices {
            healthyAnimations[index]["visible"] = ["value": index == 0,
                "user": ["name": "healthy", "condition": String(index + 1)]]
        }
        mixedObjects[2]["animationlayers"] = healthyAnimations
        mixedRoot["objects"] = mixedObjects
        let mixed = fixture(mixedRoot, catalog: .init(definitions:
            catalog().definitions + catalog("healthy").definitions))
        let healthyTargets = ScenePuppetAnimationPropertyPreparation.visibilityTargets(
            layerID: 20, selection: try selection(mixed.prepared, 20))
        var mixedLive = ScenePropertyLiveUpdateState(program: mixed.program,
            effectiveValues: mixed.effective, activeConsumerTargets: healthyTargets)
        let rejectedMixedKey = !mixedLive.apply(.string("2"), forPropertyKey: "mode")
        output["rebuildRequiredKey"] = ["blockedMarkers": markers(mixed.prepared),
            "healthyMarkers": markers(mixed.prepared, 20),
            "blockedInstructions": mixed.program.instructions.filter { $0.propertyKey == "mode" }.count,
            "rebuildKeys": mixed.program.rebuildRequiredPropertyKeys,
            "blockedHotRejected": rejectedMixedKey,
            "healthyHotAccepted": mixedLive.apply(.string("2"), forPropertyKey: "healthy")]

        let pair = fixture(root(hosts: 2), catalog: catalog())
        let modelSelection = try selection(pair.prepared)
        let peerSelection = try selection(pair.prepared, 20)
        let targets = ScenePuppetAnimationPropertyPreparation.visibilityTargets(layerID: 10, selection: modelSelection)
            .union(ScenePuppetAnimationPropertyPreparation.visibilityTargets(layerID: 20, selection: peerSelection))
        var live = ScenePropertyLiveUpdateState(program: pair.program, effectiveValues: pair.effective,
            activeConsumerTargets: targets)
        let runtime = ScenePuppetAnimationPlaybackRuntime()
        try runtime.register(layerID: 10, selection: modelSelection,
            authoredLayers: layer(pair.prepared).puppetAnimationLayers).get()
        try runtime.register(layerID: 20, selection: peerSelection,
            authoredLayers: layer(pair.prepared, 20).puppetAnimationLayers).get()
        let first = runtime.advance(frameIndex: 0, sceneTime: 0,
            dynamicValues: snapshot(pair, 0, values: live.userValues))
        let toTwo = live.apply(.string("2"), forPropertyKey: "mode")
        let same = runtime.advance(frameIndex: 0, sceneTime: 99,
            dynamicValues: snapshot(pair, 0, values: live.userValues))
        let second = runtime.advance(frameIndex: 1, sceneTime: 0.5,
            dynamicValues: snapshot(pair, 1, values: live.userValues))
        let toOne = live.apply(.string("1"), forPropertyKey: "mode")
        let third = runtime.advance(frameIndex: 2, sceneTime: 1,
            dynamicValues: snapshot(pair, 2, values: live.userValues))
        let beforeInvalid = live.userValues; let revision = live.revision
        let invalidAccepted = live.apply(.string("outside"), forPropertyKey: "mode")
        output["hot"] = ["accepted": [toTwo, toOne],
            "modelActive": [active(first), active(second), active(third)],
            "peerModelActive": [active(first, parent: 20), active(second, parent: 20), active(third, parent: 20)],
            "sameCadence": active(same), "phases": [phase(first, index: 0), phase(second, index: 1), phase(third, index: 0)],
            "invalidRejectedAtomically": !invalidAccepted && live.userValues == beforeInvalid && live.revision == revision,
            "targetCount": targets.count]
        var incomplete = ScenePropertyLiveUpdateState(program: pair.program, effectiveValues: pair.effective,
            activeConsumerTargets: targets.subtracting([ScenePuppetAnimationPropertyTarget.visibility(
                layerID: 20, animationLayerID: ids[7])]))
        let oldIncomplete = incomplete.userValues
        output["missingConsumerAtomic"] = !incomplete.apply(.string("2"), forPropertyKey: "mode")
            && incomplete.userValues == oldIncomplete && incomplete.revision == 0
        let pending = fixture(root(), catalog: catalog(), overrides: ["mode": .string("outside")])
        let pendingTargets = ScenePuppetAnimationPropertyPreparation.visibilityTargets(
            layerID: 10, selection: try selection(pending.prepared))
        var pendingLive = ScenePropertyLiveUpdateState(program: pending.program,
            effectiveValues: ["mode": .string("outside")], activeConsumerTargets: pendingTargets)
        let pendingInitialValues = pendingLive.userValues.count
        let fallback = snapshot(pending, 0, values: pendingLive.userValues)
        let fallbackTrueCount = ids.filter {
            fallback[ScenePuppetAnimationPropertyTarget.visibility(layerID: 10, animationLayerID: $0)]?
                .value == .bool(true)
        }.count
        let recovered = pendingLive.apply(.string("2"), forPropertyKey: "mode")
        output["pending"] = ["markers": markers(pending.prepared),
            "targets": pendingTargets.count, "initialUserValueCount": pendingInitialValues,
            "fallbackTrueCount": fallbackTrueCount, "recovered": recovered,
            "trueCount": pendingLive.userValues.values.filter { $0 == .bool(true) }.count]

        var unsafe = modelSelection
        unsafe = .init(clips: [.init(layer: modelSelection.clips[0].layer, animation: clip(100, alpha: true))]
            + Array(modelSelection.clips.dropFirst()), composition: .layered)
        let alphaTargets = ScenePuppetAnimationPropertyPreparation.visibilityTargets(layerID: 10, selection: unsafe)
        unsafe = .init(clips: [.init(layer: modelSelection.clips[0].layer, animation: clip(100, aux: true))]
            + Array(modelSelection.clips.dropFirst()), composition: .layered)
        output["unsafeChannels"] = [alphaTargets.count,
            ScenePuppetAnimationPropertyPreparation.visibilityTargets(layerID: 10, selection: unsafe).count]
        let stringLayer = ScenePuppetAnimationLayer.parse([["id": 7, "animation": 100,
            "visible": ["value": true, "user": "old-enabled"], "rate": 1,
            "additive": false, "blend": 1]])[0]
        let oldDescriptor = SceneRenderDescriptor(layers: [.init(id: 44, contentKind: "image",
            puppetAnimationLayers: [stringLayer])])
        let kept = ScenePuppetAnimationPropertyPreparation.applyingBindings(
            .init(definitions: [], instructions: []), report: .init(bindings: [], diagnostics: []),
            to: oldDescriptor).layers[0].puppetAnimationLayers[0]
        let oldSelection = ScenePuppetAnimationSelection(clips: [.init(layer: kept,
            animation: clip(100))], composition: .singleAbsolute)
        let oldRuntime = ScenePuppetAnimationPlaybackRuntime()
        try oldRuntime.register(layerID: 44, selection: oldSelection, authoredLayers: [stringLayer]).get()
        output["oldStringMissingSnapshot"] = active(oldRuntime.advance(frameIndex: 0, sceneTime: 0,
            dynamicValues: .empty(frameIndex: 0)), parent: 44)
        output["oldStringMarker"] = kept.visibilityBinding ?? ""
        let oldSource: [String: Any] = ["objects": [["id": 44, "image": "models/own/old-image.json",
            "animationlayers": [["id": 7, "animation": 100, "rate": 1, "additive": false,
                "blend": 1, "visible": ["user": "old-enabled", "value": true]]]]]]
        let oldCatalog = SceneUserPropertyDefinitionParser().parse(properties: [
            "old-enabled": ["type": "bool", "value": true]])
        let oldFixture = fixture(oldSource, catalog: oldCatalog)
        let oldOn = oldFixture.program.evaluate(effectiveValues: ["old-enabled": .bool(true)]).userValues
        let oldOff = oldFixture.program.evaluate(effectiveValues: ["old-enabled": .bool(false)]).userValues
        let resumed = oldRuntime.advance(frameIndex: 1, sceneTime: 0.5,
            dynamicValues: snapshot(oldFixture, 1, values: oldOn))
        let hidden = oldRuntime.advance(frameIndex: 2, sceneTime: 1,
            dynamicValues: snapshot(oldFixture, 2, values: oldOff))
        let again = oldRuntime.advance(frameIndex: 3, sceneTime: 1.5,
            dynamicValues: snapshot(oldFixture, 3, values: oldOn))
        output["oldImageCadence"] = ["active": [active(resumed, parent: 44), active(hidden, parent: 44),
            active(again, parent: 44)], "phases": [phase(resumed, index: 0, parent: 44),
            phase(again, index: 0, parent: 44)],
            "card": SceneServiceTargetCarrier.supportsScenePropertyTarget(
                .puppetAnimationVisibility(layerID: 44, animationLayerID: 7),
                in: oldFixture.prepared, materialTargets: [])]
        let staticFallback = fixture(root(), catalog: .empty)
        let fallbackRuntime = ScenePuppetAnimationPlaybackRuntime()
        try fallbackRuntime.register(layerID: 10, selection: try selection(staticFallback.prepared),
            authoredLayers: layer(staticFallback.prepared).puppetAnimationLayers).get()
        output["objectMissingProducerSnapshot"] = active(fallbackRuntime.advance(
            frameIndex: 0, sceneTime: 0, dynamicValues: .empty(frameIndex: 0)))
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class ScenePuppetAnimationPropertyPreparationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("swiftc"):
            raise unittest.SkipTest("swiftc is unavailable")
        cls.scratch = tempfile.TemporaryDirectory(prefix="mwx-animation-properties-")
        cls.addClassCleanup(cls.scratch.cleanup)
        directory = Path(cls.scratch.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS + service_target_carrier())
        cls.inputs = [*SWIFT_SOURCES, Path(__file__), SERVICE_SOURCE]
        cls.before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in cls.inputs}
        cls.compilation = subprocess.run(["swiftc", *map(str, SWIFT_SOURCES), str(harness),
            "-module-cache-path", str(directory / "module-cache"), "-o", str(directory / "probe")],
            capture_output=True, text=True, timeout=120)
        if cls.compilation.returncode:
            raise RuntimeError(cls.compilation.stderr)
        cls.execution = subprocess.run([str(directory / "probe")], capture_output=True,
                                       text=True, timeout=20)
        if cls.execution.returncode:
            raise RuntimeError(cls.execution.stderr)
        cls.result = json.loads(cls.execution.stdout)
        cls.after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in cls.inputs}

    def test_exact_projection_renaming_and_descriptor_reordering(self):
        row = self.result["initial"]
        self.assertEqual(row["markers"], ["mode"] * 8)
        self.assertEqual(row["before"], [""] * 8)
        self.assertEqual(row["descriptorOrder"], [10, 99])
        self.assertEqual(row["programTargets"], 8)
        self.assertEqual(self.result["renamed"], ["renamed-σ"] * 8)
        self.assertEqual(self.result["equivalentReference"], ["mode"] * 8)
        self.assertEqual(self.before, self.after)

    def test_absent_or_unsupported_producer_keeps_resolved_fallback(self):
        for name, row in self.result["rejections"].items():
            with self.subTest(name=name):
                self.assertEqual(row["firstMarker"], "")
                self.assertTrue(row["fallbackUnchanged"])
        self.assertTrue(self.result["rejections"]["missingCatalog"]["firstVisible"])

    def test_path_id_parent_and_report_identity_fail_closed(self):
        self.assertEqual(self.result["duplicateAnimationIDs"], ["", ""])
        self.assertEqual(self.result["duplicateParents"], [])
        self.assertEqual(self.result["wrongPathID"], [""] * 8)
        self.assertEqual(self.result["reportProgramMismatch"], [""] * 8)
        for key in ("reportPathMismatch", "reportConditionMismatch", "reportTargetMismatch", "duplicateReportPath"):
            with self.subTest(key=key):
                self.assertEqual(self.result[key], [""] * 8)

    def test_eight_target_groups_switch_atomically_on_one_shared_cadence(self):
        row = self.result["hot"]
        self.assertEqual(row["accepted"], [True, True])
        self.assertEqual(row["modelActive"], [[0], [1], [0]])
        self.assertEqual(row["peerModelActive"], row["modelActive"])
        self.assertEqual(row["sameCadence"], [0])
        self.assertEqual(row["phases"], [0, 1, 1])
        self.assertEqual(row["targetCount"], 16)
        self.assertTrue(row["invalidRejectedAtomically"])
        self.assertTrue(self.result["missingConsumerAtomic"])

    def test_invalid_current_value_keeps_future_producer_and_recovers(self):
        row = self.result["pending"]
        self.assertEqual(row["markers"], ["mode"] * 8)
        self.assertEqual(row["targets"], 8)
        self.assertEqual(row["initialUserValueCount"], 0)
        self.assertEqual(row["fallbackTrueCount"], 1)
        self.assertTrue(row["recovered"])
        self.assertEqual(row["trueCount"], 1)

    def test_rebuild_required_key_does_not_disable_an_independent_healthy_key(self):
        row = self.result["rebuildRequiredKey"]
        self.assertEqual(row["blockedInstructions"], 8)
        self.assertEqual(row["rebuildKeys"], ["mode"])
        self.assertEqual(row["blockedMarkers"], [""] * 8)
        self.assertEqual(row["healthyMarkers"], ["healthy"] * 8)
        self.assertTrue(row["blockedHotRejected"])
        self.assertTrue(row["healthyHotAccepted"])

    def test_direct_channel_admission_and_legacy_string_missing_snapshot(self):
        self.assertEqual(self.result["unsafeChannels"], [0, 0])
        self.assertEqual(self.result["oldStringMarker"], "old-enabled")
        self.assertEqual(self.result["oldStringMissingSnapshot"], [])
        self.assertEqual(self.result["objectMissingProducerSnapshot"], [0])
        self.assertEqual(self.result["oldImageCadence"]["active"], [[0], [], [0]])
        self.assertEqual(self.result["oldImageCadence"]["phases"], [1, 2])
        self.assertTrue(self.result["oldImageCadence"]["card"])

    def test_object_image_scope_stays_closed_and_property_card_consumes_prepared_marker(self):
        row = self.result["imageObject"]
        self.assertEqual(row["modelMarkers"], ["mode"] * 8)
        self.assertEqual(row["imageMarkers"], [""] * 8)
        self.assertTrue(row["partialApplyRejected"])
        self.assertEqual(self.result["propertyCard"], {"before": False, "after": True, "imageObject": False})


if __name__ == "__main__":
    unittest.main()
