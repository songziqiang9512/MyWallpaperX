"""Owner rejection retries event acknowledgements without replaying accepted peers."""
from __future__ import annotations
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness

HARNESS = r'''
@main enum Harness {
    static let frame = SceneScriptFrameInput(timing: .init(
        wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 0.016, sceneTime: 1))
    static let events = """
        let count = 0;
        export function mediaThumbnailChanged(e) { count += 1; }
        export function mediaPlaybackChanged(e) { count += 10; }
        export function mediaPropertiesChanged(e) { count += 100; }
        export function mediaTimelineChanged(e) { count += 1000; }
        export function applyUserProperties(e) { count += 10000; }
        """
    static func descriptor() -> SceneRenderDescriptor {
        .init(layers: (1...3).map { id in .init(id: id, layerIndex: id-1,
            name: "layer\(id)", visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1],
            scaleHasScript: nil, alpha: 1, effects: [], contentKind: "text", text: "0",
            textStyle: .init(fontPath: nil, colorRGB: nil, pointSize: 20), sizeWH: [100,100]) })
    }
    static func binding(_ id: Int, _ field: String, _ source: String) -> SceneScriptBindingIR {
        .init(source: source, owner: .init(kind: .object, objectIndex: id-1, objectID: id,
            effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
            targetPath: [.key("objects"), .index(id-1), .key(field)], properties: [:],
            authoredValue: field == "alpha" ? .number(1) : .string(field == "text" ? "0" : field == "scale" ? "1 1 1" : "0 0 0"),
            valueType: field == "alpha" ? .number : .string, wrapperKeys: ["script", "value"])
    }
    static func number(_ v: SceneDynamicValue?) -> Double {
        switch v { case let .scalar(x)?: (x * 100000).rounded(); case let .vector3(x,_,_)?: x;
        case let .string(x)?: Double(x) ?? -999; default: -999 }
    }
    static func exercise(
        targets: [SceneDynamicTarget],
        capture: () -> SceneScriptProgramFrameState,
        evaluate: (UInt64, UInt64) -> [SceneDynamicTarget: SceneDynamicValue],
        restore: (SceneScriptProgramFrameState, Set<SceneDynamicTarget>?) -> Void,
        finalize: (Bool, Set<SceneDynamicTarget>) -> Void
    ) -> [[Double]] {
        var values: [[Double]] = []
        func run(_ event: UInt64, _ property: UInt64) {
            let result = evaluate(event, property)
            values.append(targets.map { number(result[$0]) })
        }
        let first = capture()
        run(1, 1)
        restore(first, [targets[0]])
        finalize(true, [targets[0]])
        run(1, 1) // first-event acknowledgement absent in snapshot must be removed
        finalize(true, [])
        run(1, 1) // accepted peer and retried owner now remain quiet
        finalize(true, [])
        let prior = capture()
        run(2, 2)
        restore(prior, [targets[0]])
        finalize(true, [targets[0]])
        run(2, 2) // preserve prior generation/revision while retrying the latest
        finalize(true, [])
        run(1, 2) // observed watermark must still reject stale media input
        finalize(true, [])
        let dropped = capture()
        run(3, 3)
        restore(dropped, [targets[0]])
        restore(dropped, nil) // whole-frame discard still restores every target
        finalize(false, [])
        run(3, 3)
        finalize(true, [])
        return values
    }
    static func main() throws {
        var out: [String: Any] = [:]
        let d = descriptor()
        for family in ["scalar", "string", "vector", "sameLayer"] {
            let field = family == "scalar" ? "alpha" : family == "string" ? "text" : "origin"
            let output = family == "scalar" ? "count / 100000" : family == "string" ? "String(count)" : "new Vec3(count,0,0)"
            let source = events + "\nexport function update(v) { return " + output + "; }"
            let ids = family == "sameLayer" ? [1,1] : [1,2]
            let bindings = ids.enumerated().map { i, id in binding(id,
                family == "sameLayer" && i == 1 ? "scale" : field, source) }
            var d = descriptor()
            if family == "string" { for i in d.layers.indices { d.layers[i].textScript = .init(source: source) } }
            let domain = try SceneScriptQuickJSDomain()
            try domain.configureLayerCatalog(d)
            let targets: [SceneDynamicTarget] = ids.enumerated().map { i, id in
                if family == "scalar" { return .layer(layerID: id, field: .alpha) }
                if family == "string" { return .text(layerID: id, field: .content) }
                return .layer(layerID: id, field: family == "sameLayer" && i == 1 ? .scale : .origin)
            }
            let properties: [SceneUserPropertyDefinition] = [
                .init(key: "mode", title: "Mode", kind: .slider, runtimeType: "slider",
                      order: 0, index: nil, minimumValue: 0, maximumValue: 10,
                      stepValue: 1, allowsFractionalValues: false, fractionalPrecision: nil,
                      displayCondition: nil, defaultValue: .number(0), options: [])]
            func thumb(_ g: UInt64) -> SceneScriptMediaThumbnailEventInput { .init(hasThumbnail: false, generation: g) }
            func playback(_ g: UInt64) -> SceneScriptMediaPlaybackEventInput { .init(state: 1, generation: g) }
            func metadata(_ g: UInt64) -> SceneScriptMediaPropertiesEventInput { .init(title: "title", artist: "artist", generation: g) }
            func timeline(_ g: UInt64) -> SceneScriptMediaTimelineEventInput { .init(position: 1, duration: 2, generation: g) }
            if family == "scalar" {
                let p = SceneScriptScalarProgram.compile(domain: domain, descriptor: d,
                    scriptBindings: bindings, userPropertyDefinitions: properties)
                out[family+"Owners"] = p.bindings.count
                out[family] = exercise(targets: targets, capture: p.frameStateSnapshot,
                    evaluate: { g, r in p.evaluate(inputs: Dictionary(uniqueKeysWithValues: targets.map { ($0, .scalar(0)) }),
                        frame: frame, effectivePropertyValues: ["mode": .number(Double(r))], propertyRevision: r,
                        mediaThumbnailEvent: thumb(g), mediaPlaybackEvent: playback(g),
                        mediaPropertiesEvent: metadata(g), mediaTimelineEvent: timeline(g)).values },
                    restore: { p.restoreFrameState($0, rejectedOwnerTargets: $1) },
                    finalize: { p.finalizeLayerMutations(committing: $0, rejectedOwnerTargets: $1) })
            } else if family == "string" {
                let p = SceneScriptStringProgram.compile(domain: domain, descriptor: d,
                    scriptBindings: bindings, userPropertyDefinitions: properties, generation: 1)
                out[family+"Owners"] = p.bindings.count
                out[family] = exercise(targets: targets, capture: p.frameStateSnapshot,
                    evaluate: { g, r in p.evaluate(inputs: Dictionary(uniqueKeysWithValues: targets.map { ($0, .string("0")) }),
                        effectivePropertyValues: ["mode": .number(Double(r))], propertyRevision: r, frame: frame,
                        mediaThumbnailEvent: thumb(g), mediaPlaybackEvent: playback(g),
                        mediaPropertiesEvent: metadata(g), mediaTimelineEvent: timeline(g)).values },
                    restore: { p.restoreFrameState($0, rejectedOwnerTargets: $1) },
                    finalize: { p.finalizeLayerMutations(committing: $0, rejectedOwnerTargets: $1) })
            } else {
                let p = SceneScriptVectorProgram.compile(domain: domain, descriptor: d,
                    scriptBindings: bindings, userPropertyDefinitions: properties, generation: 1)
                out[family+"Owners"] = p.bindings.count
                out[family] = exercise(targets: targets, capture: p.frameStateSnapshot,
                    evaluate: { g, r in p.evaluate(inputs: Dictionary(uniqueKeysWithValues: targets.map { ($0, .vector3(0,0,0)) }),
                        effectivePropertyValues: ["mode": .number(Double(r))], frame: frame, propertyRevision: r,
                        mediaThumbnailEvent: thumb(g), mediaPlaybackEvent: playback(g),
                        mediaPropertiesEvent: metadata(g), mediaTimelineEvent: timeline(g)).values },
                    restore: { p.restoreFrameState($0, rejectedOwnerTargets: $1) },
                    finalize: { p.finalizeLayerMutations(committing: $0, rejectedOwnerTargets: $1) })
            }
        }
        // Real cursor success followed by update failure on the same borrowed VM owner.
        let source = """
            export function cursorMove(e) { thisScene.getLayerByID(3).origin = new Vec3(99,0,0); }
            export function update(v) { return {}; }
            """
        let b = binding(1, "origin", source)
        let peer = binding(2, "origin", "export function update(v) { thisScene.getLayerByID(3).alpha = 0.5; return new Vec3(7,0,0); }")
        let candidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: d, runtimeDescriptor: d, scriptBindings: [b,peer],
            vectorProjection: SceneScriptVectorProgram.project(descriptor: d, scriptBindings: [b,peer]),
            userPropertyDefinitions: [], timelineTargets: [], scalarExcludedTargets: [],
            stringExcludedTargets: [], admittedVectorPassTargets: [], generation: 1)
        let hit = SceneScriptCursorHit(layerID: 1, worldPosition: .zero, localPosition: .zero)
        let cursor = candidate.cursorProgram.dispatch(batch: .init(samples: [
            .init(hits: [1:hit], pointerPosition: .zero, primaryButtonIsDown: false),
            .init(hits: [1:hit], pointerPosition: .init(1,0), primaryButtonIsDown: false)
        ], overflowed: false), frame: frame, userPropertiesJSON: "{}")
        let a: SceneDynamicTarget = .layer(layerID: 1, field: .origin)
        let p: SceneDynamicTarget = .layer(layerID: 2, field: .origin)
        let update = candidate.vectorProgram.evaluate(inputs: [a: .vector3(0,0,0), p: .vector3(0,0,0)],
            effectivePropertyValues: [:], frame: frame)
        let runtime = SceneScriptDynamicLayerRuntime(descriptor: d, authoredMutationLayerIDs: [1,2,3])
        let admission = runtime.preflightOwnerEffectsToFixedPoint(cursor.ownerEffects + update.ownerEffects,
            excludingOwners: Set(cursor.failures.keys).union(update.failures.keys)) { _ in [] }
        runtime.commit(admission.admission.layerPlan)
        out["cursorEffects"] = cursor.ownerEffects.count
        out["updateFailure"] = update.failures[a]?.code ?? "none"
        out["failedCursorExcluded"] = admission.externallyRejectedOwners.contains(a)
        out["peerAdmitted"] = admission.admission.admittedEffects.contains { $0.ownerTarget == p }
        out["rejectedCursorPublished"] = runtime.snapshot().authoredLayerValues[.layer(layerID: 3, field: .origin)] != nil
        out["peerAlpha"] = number(runtime.snapshot().authoredLayerValues[.layer(layerID: 3, field: .alpha)])
        print(String(data: try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''

class OwnerEventTransactionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-owner-event-test-")
        cls.addClassCleanup(cls.temp.cleanup)
        binary = compile_vector_harness(Path(cls.temp.name), HARNESS, "owner-event-transaction")
        run = subprocess.run([str(binary)], text=True, capture_output=True, check=True)
        cls.result = json.loads(run.stdout.strip().splitlines()[-1])

    def test_rejected_first_event_retries_without_replaying_peer(self):
        for family in ("scalar", "string", "vector", "sameLayer"):
            with self.subTest(family=family):
                self.assertEqual(self.result[family+"Owners"], 2)
                self.assertEqual(self.result[family][:3], [[11111,11111], [22222,11111], [22222,11111]])

    def test_prior_generations_and_properties_retry_only_rejected_target(self):
        for family in ("scalar", "string", "vector", "sameLayer"):
            with self.subTest(family=family):
                self.assertEqual(self.result[family][3:5], [[33333,22222], [44444,22222]])

    def test_local_rejection_keeps_observed_event_watermark_monotonic(self):
        for family in ("scalar", "string", "vector", "sameLayer"):
            with self.subTest(family=family):
                self.assertEqual(self.result[family][5], [44444,22222])

    def test_local_then_whole_frame_rejection_retries_both_owners(self):
        for family in ("scalar", "string", "vector", "sameLayer"):
            with self.subTest(family=family):
                self.assertEqual(self.result[family][6:], [[55555,33333], [66666,44444]])

    def test_late_update_failure_retracts_cursor_effects_and_preserves_peer(self):
        self.assertEqual(self.result["cursorEffects"], 1)
        self.assertEqual(self.result["updateFailure"], "bad-return")
        self.assertTrue(self.result["failedCursorExcluded"])
        self.assertTrue(self.result["peerAdmitted"])
        self.assertFalse(self.result["rejectedCursorPublished"])
        self.assertEqual(self.result["peerAlpha"], 50000)
