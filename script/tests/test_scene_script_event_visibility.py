#!/usr/bin/env python3
"""Event-only Boolean setters survive VM quiescence through the layer runtime."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import SCENE, SWIFT_PREAMBLE, compile_vector_harness


HARNESS = r'''
@main enum Harness {
    static let target = SceneDynamicTarget.layer(layerID: 7, field: .visibility)
    static let origin = SceneDynamicTarget.layer(layerID: 7, field: .origin)
    static let property = SceneUserPropertyDefinition(
        key: "invert", title: "Invert", kind: .bool, runtimeType: "bool",
        order: 0, index: nil, minimumValue: nil, maximumValue: nil,
        stepValue: nil, allowsFractionalValues: false, fractionalPrecision: nil,
        displayCondition: nil, defaultValue: .bool(false), options: [])

    final class Context {
        let scene: SceneRenderDescriptor
        let program: SceneScriptVectorProgram
        let runtime: SceneScriptDynamicLayerRuntime
        let index: SceneDynamicSnapshotDefinitionIndex
        var frameIndex: UInt64 = 0

        init(_ source: String) throws {
            var layer = SceneRenderDescriptor.Layer(
                id: 7, layerIndex: 0, name: "event-leaf", visible: false,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1,
                effects: [], contentKind: "image")
            layer.displayScriptOwnership = .init(visible: true, alpha: false)
            scene = .init(layers: [layer])
            let binding = SceneScriptBindingIR(source: source,
                owner: .init(kind: .object, objectIndex: 0, objectID: 7,
                    effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
                targetPath: [.key("objects"), .index(0), .key("visible")],
                properties: [:], authoredValue: .bool(false), valueType: .boolean,
                wrapperKeys: ["script", "value"])
            program = SceneScriptVectorProgram.compile(
                domain: try SceneScriptQuickJSDomain(), descriptor: scene,
                scriptBindings: [binding], userPropertyDefinitions: [property], generation: 71)
            precondition(program.definitions.count == 1)
            runtime = .init(descriptor: scene, authoredMutationLayerIDs: [7])
            var definitions = program.definitions
            let targets = Set(definitions.map(\.target))
            definitions += runtime.authoredLayerDefinitions.filter { !targets.contains($0.target) }
            index = SceneDynamicSnapshotResolver.prepare(definitions: definitions)
        }

        func resolve(_ values: [SceneDynamicTarget: SceneDynamicValue],
                     user: [SceneDynamicTarget: SceneDynamicValue]) -> SceneDynamicSnapshotResolution {
            SceneDynamicSnapshotResolver().resolve(frameIndex: frameIndex, generation: 71,
                index: index, userValues: user, sceneScriptValues: values)
        }

        // These are the frame driver's public producers and commit order:
        // committed setters -> typed input -> real VM -> owner admission ->
        // typed output -> runtime/owner commit. No cached VM value is used to
        // hide loss of the event setter during an idle frame.
        func step(invert: Bool, revision: UInt64, time: Double,
                  userVisibility: Bool? = nil, reject: Bool = false) throws -> [String: Any] {
            frameIndex += 1
            let user: [SceneDynamicTarget: SceneDynamicValue] = userVisibility.map {
                [target: .bool($0)]
            } ?? [:]
            let committed = runtime.snapshot().authoredLayerValues
            let preliminary = resolve(committed, user: user)
            try program.domain?.publishLayerSnapshot(preliminary.snapshot, descriptor: scene)
            let before = program.frameStateSnapshot()
            let result = program.evaluate(
                inputs: preliminary.snapshot.typedValues(for: program.inputTargets,
                    valueTypes: program.inputValueTypes),
                effectivePropertyValues: ["invert": .bool(invert)],
                frame: .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
                    simulationFrameTime: 1 / 60, sceneTime: time)), propertyRevision: revision)
            let admission = runtime.preflightOwnerEffectsToFixedPoint(
                result.ownerEffects, excludingOwners: Set(result.failures.keys)) { effects in
                    reject ? Set(effects.map(\.ownerTarget)) : []
                }
            let rejected = admission.externallyRejectedOwners.union(
                admission.admission.rejectedOwners.compactMap(\.ownerTarget))
            var accepted = committed
            accepted.merge(result.values.filter { !rejected.contains($0.key) }) { _, current in current }
            let output = resolve(accepted, user: user)
            runtime.commit(admission.admission.layerPlan)
            if !rejected.isEmpty { program.restoreFrameState(before, rejectedOwnerTargets: rejected) }
            program.finalizeLayerMutations(committing: true, rejectedOwnerTargets: rejected)
            let state = runtime.snapshot().authoredLayerValues
            let visible = output.snapshot[target]?.value == .bool(true)
            var row: [String: Any] = [
                "visible": visible,
                "consumerVisible": SceneLayerVisibility.visibleLayerIDs(
                    in: scene, snapshot: output.snapshot).contains(7),
                "values": result.values.count, "effects": result.ownerEffects.count,
                "mutations": result.layerMutations.count, "failures": result.failures.count,
                "failureCode": result.failures[target]?.code ?? "none",
                "diagnostics": output.diagnostics.count, "rejected": rejected.contains(target),
                "persistentVisibility": state[target].map { $0 == .bool(true) } as Any? ?? NSNull(),
                "ownVisibilityWrites": result.layerMutations.filter {
                    $0.layerID == 7 && $0.fields.contains(.visibility)
                }.count]
            if case let .vector3(x, _, _)? = state[origin] { row["callbackCount"] = x }
            else { row["callbackCount"] = NSNull() }
            return row
        }
    }

    static let eventSource = """
        let calls = 0;
        export function applyUserProperties(properties) {
            calls += 1;
            thisLayer.origin = new Vec3(calls, 0, 0);
            if (Object.prototype.hasOwnProperty.call(properties, 'invert')) {
                thisLayer.visible = !properties.invert;
            }
        }
        """

    static func main() throws {
        let event = try Context(eventSource)
        let events = try [
            event.step(invert: false, revision: 1, time: 0, userVisibility: false),
            event.step(invert: false, revision: 1, time: 1, userVisibility: false),
            event.step(invert: false, revision: 1, time: 1.5, userVisibility: false),
            event.step(invert: true, revision: 2, time: 2, userVisibility: true),
            event.step(invert: true, revision: 2, time: 3, userVisibility: true),
            event.step(invert: false, revision: 3, time: 4, userVisibility: false),
            event.step(invert: false, revision: 3, time: 5, userVisibility: false)]

        let retry = try Context(eventSource)
        let rejected = try [
            retry.step(invert: false, revision: 1, time: 0, userVisibility: false, reject: true),
            retry.step(invert: false, revision: 1, time: 1, userVisibility: false),
            retry.step(invert: false, revision: 1, time: 2, userVisibility: false),
            retry.step(invert: true, revision: 2, time: 3, userVisibility: true, reject: true),
            retry.step(invert: true, revision: 2, time: 4, userVisibility: true),
            retry.step(invert: true, revision: 2, time: 5, userVisibility: true)]

        let throwing = try Context("""
            let calls = 0;
            export function applyUserProperties(properties) {
                calls += 1;
                thisLayer.visible = !properties.invert;
                thisLayer.origin = new Vec3(calls, 0, 0);
                if (properties.invert) {
                    throw new Error('reject after setter');
                }
            }
            """)
        let thrown = try [
            throwing.step(invert: false, revision: 1, time: 0, userVisibility: false),
            throwing.step(invert: true, revision: 2, time: 1, userVisibility: true),
            throwing.step(invert: true, revision: 2, time: 2, userVisibility: true),
            throwing.step(invert: false, revision: 3, time: 3, userVisibility: false)]

        let noWrite = try Context("""
            export function applyUserProperties(properties) {
                // Reading a Boolean is not a setter and must not pin this input.
                const observed = thisLayer.visible;
            }
            """)
        let noWrites = try [
            noWrite.step(invert: false, revision: 1, time: 0, userVisibility: true),
            noWrite.step(invert: false, revision: 1, time: 1, userVisibility: false),
            noWrite.step(invert: true, revision: 2, time: 2, userVisibility: true),
            noWrite.step(invert: true, revision: 2, time: 3, userVisibility: false)]

        let update = try Context("""
            export function applyUserProperties(properties) { thisLayer.visible = true; }
            export function update(value) { return engine.runtime < 1; }
            """)
        let updates = try [
            update.step(invert: false, revision: 1, time: 0),
            update.step(invert: false, revision: 1, time: 2),
            update.step(invert: true, revision: 2, time: 0),
            update.step(invert: true, revision: 2, time: 2)]
        print(String(data: try JSONSerialization.data(withJSONObject: [
            "events": events, "rejected": rejected, "thrown": thrown,
            "noWrites": noWrites, "updates": updates
        ], options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''


class SceneScriptEventVisibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-event-visibility-")
        cls.addClassCleanup(cls.temporary.cleanup)
        # Extend only the descriptor carrier. Visibility, VM validation,
        # admission, runtime commit and resolver are production code.
        preamble = SWIFT_PREAMBLE.replace(
            "var particleInstanceOverride:",
            "var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil\n"
            "        var particleInstanceOverride:")
        binary = compile_vector_harness(Path(cls.temporary.name), HARNESS,
            "event-visibility", preamble=preamble,
            extra_swift_sources=(SCENE / "Rendering/Geometry/SceneLayerVisibility.swift",))
        result = subprocess.run([str(binary)], capture_output=True, text=True,
                                check=True, timeout=30)
        cls.value = json.loads(result.stdout.strip().splitlines()[-1])

    def assert_valid_rows(self, rows: list[dict]) -> None:
        for row in rows:
            self.assertEqual(row["failures"], 0, row)
            self.assertEqual(row["diagnostics"], 0, row)
            self.assertEqual(row["consumerVisible"], row["visible"], row)

    def test_property_event_setter_survives_idle_and_live_toggles(self) -> None:
        rows = self.value["events"]
        self.assert_valid_rows(rows)
        self.assertEqual([r["visible"] for r in rows], [True, True, True, False, False, True, True])
        self.assertEqual([r["persistentVisibility"] for r in rows], [True, True, True, False, False, True, True])
        self.assertEqual([r["values"] for r in rows], [1, 0, 0, 1, 0, 1, 0])
        self.assertEqual([r["ownVisibilityWrites"] for r in rows], [1, 0, 0, 1, 0, 1, 0])
        self.assertEqual([r["callbackCount"] for r in rows], [1, 1, 1, 2, 2, 3, 3])

    def test_rejected_event_effects_do_not_commit_and_same_revision_retries(self) -> None:
        rows = self.value["rejected"]
        self.assert_valid_rows(rows)
        self.assertEqual([r["visible"] for r in rows], [False, True, True, True, False, False])
        self.assertEqual([r["persistentVisibility"] for r in rows], [None, True, True, True, False, False])
        self.assertEqual([r["rejected"] for r in rows], [True, False, False, True, False, False])
        self.assertEqual([r["values"] for r in rows], [1, 1, 0, 1, 1, 0])
        self.assertEqual([r["callbackCount"] for r in rows], [None, 2, 2, 2, 4, 4])

    def test_setter_then_vm_throw_keeps_previous_value_without_partial_commit(self) -> None:
        rows = self.value["thrown"]
        self.assert_valid_rows([rows[0], *rows[2:]])
        failed = rows[1]
        self.assertEqual(failed["failures"], 1, failed)
        self.assertEqual(failed["failureCode"], "exception", failed)
        self.assertEqual(failed["values"], 0, failed)
        self.assertEqual(failed["effects"], 0, failed)
        self.assertEqual(failed["mutations"], 0, failed)
        self.assertTrue(failed["rejected"], failed)
        # Exceptions retain the existing permanent owner fuse. Frame rejection
        # retries are tested separately; neither failure policy publishes the
        # setter or origin that preceded this throw.
        self.assertEqual([r["visible"] for r in rows], [True, True, True, True])
        self.assertEqual([r["persistentVisibility"] for r in rows], [True, True, True, True])
        self.assertEqual([r["callbackCount"] for r in rows], [1, 1, 1, 1])
        self.assertEqual([r["values"] for r in rows], [1, 0, 0, 0])
        self.assertTrue(all(r["effects"] == r["mutations"] == 0 for r in rows[1:]))

    def test_no_write_event_callback_does_not_pin_current_input(self) -> None:
        rows = self.value["noWrites"]
        self.assert_valid_rows(rows)
        self.assertEqual([r["visible"] for r in rows], [True, False, True, False])
        self.assertEqual([r["values"] for r in rows], [1, 0, 1, 0])
        self.assertTrue(all(r["persistentVisibility"] is None for r in rows))
        self.assertTrue(all(r["effects"] == r["mutations"] == 0 for r in rows))

    def test_update_owner_own_setter_does_not_persist_over_later_return(self) -> None:
        rows = self.value["updates"]
        self.assert_valid_rows(rows)
        self.assertEqual([r["visible"] for r in rows], [True, False, True, False])
        self.assertEqual([r["values"] for r in rows], [1, 1, 1, 1])
        self.assertTrue(all(r["persistentVisibility"] is None for r in rows))
        self.assertTrue(all(r["ownVisibilityWrites"] == 0 for r in rows))


if __name__ == "__main__":
    unittest.main()
