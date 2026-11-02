#!/usr/bin/env python3

"""Cursor QuickJS owners consume the current shared audio snapshot."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

try:
    from .scene_vector_vm_test_support import compile_vector_harness
except ImportError:
    from scene_vector_vm_test_support import compile_vector_harness


CURSOR_HARNESS = r'''
@main
enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: [
            layer(id: 10, index: 0), layer(id: 20, index: 1),
            layer(id: 30, index: 2),
        ])
        let bindings = [
            eventOnlyBinding(layerID: 10, index: 0),
            borrowedBinding(layerID: 20, index: 1),
            siblingBinding(layerID: 20, index: 1),
            eventOnlyBinding(layerID: 30, index: 2),
        ]
        let projection = SceneScriptVectorProgram.project(
            descriptor: descriptor, scriptBindings: bindings
        )
        let candidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: descriptor,
            runtimeDescriptor: descriptor,
            scriptBindings: bindings,
            vectorProjection: projection,
            userPropertyDefinitions: [], timelineTargets: [],
            scalarExcludedTargets: [], stringExcludedTargets: [],
            admittedVectorPassTargets: [], generation: 41
        )
        let isolatedProjection = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: [eventOnlyBinding(layerID: 30, index: 2)]
        )
        let isolatedCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: descriptor,
            runtimeDescriptor: descriptor,
            scriptBindings: [eventOnlyBinding(layerID: 30, index: 2)],
            vectorProjection: isolatedProjection,
            userPropertyDefinitions: [], timelineTargets: [],
            scalarExcludedTargets: [], stringExcludedTargets: [],
            admittedVectorPassTargets: [], generation: 42
        )
        let controlTarget = SceneDynamicTarget.layer(layerID: 30, field: .visibility)
        let controlValues = candidate.vectorProgram.bindings.filter { $0.definition.target == controlTarget }
        let controlCursors = candidate.cursorProgram.bindings.filter { $0.ownerTarget == controlTarget }
        let controlRegistrations = candidate.vectorProgram.cursorOwnerRegistrations.filter { $0.target == controlTarget }
        let isolatedValues = isolatedCandidate.vectorProgram.bindings
        let isolatedCursors = isolatedCandidate.cursorProgram.bindings
        let preparedOwners = candidate.vectorProgram.bindings.map(\.owner) + candidate.cursorProgram.bindings.map(\.owner)
        let dependentControlSharesOwner = controlValues.count == 1 && controlCursors.count == 1
            && controlRegistrations.count == 1 && !controlCursors[0].ownsOwner
            && controlCursors[0].owner === controlValues[0].owner
            && controlRegistrations[0].owner === controlValues[0].owner
        let isolatedSharesOwner = isolatedValues.count == 1 && isolatedCursors.count == 1
            && !isolatedCursors[0].ownsOwner && isolatedCursors[0].owner === isolatedValues[0].owner
        let frame = SceneScriptFrameInput(
            timing: .init(
                wallDate: Date(timeIntervalSince1970: 0),
                simulationFrameTime: 1.0 / 60.0, sceneTime: 2
            ),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        _ = candidate.vectorProgram.evaluate(
            inputs: [.layer(layerID: 10, field: .visibility): .bool(true)],
            effectivePropertyValues: [:], frame: frame
        )
        candidate.vectorProgram.finalizeLayerMutations(committing: true)
        let firstAudio = audio(left: 0.25, right: 0.5, generation: 1)
        let first = candidate.cursorProgram.dispatch(
            batch: batch(down: true), frame: frame,
            userPropertiesJSON: "{}", audioSpectrum: firstAudio
        )
        candidate.cursorProgram.finalizeLayerMutations(committing: true)
        candidate.vectorProgram.finalizeLayerMutations(committing: true)
        let secondAudio = audio(left: 0.75, right: 0.8, generation: 2)
        let second = candidate.cursorProgram.dispatch(
            batch: batch(down: false), frame: frame,
            userPropertiesJSON: "{}", audioSpectrum: secondAudio
        )
        candidate.cursorProgram.finalizeLayerMutations(committing: true)
        candidate.vectorProgram.finalizeLayerMutations(committing: true)
        let migratedTarget = SceneDynamicTarget.layer(layerID: 10, field: .visibility)
        let quietFrame = candidate.vectorProgram.evaluate(
            inputs: [migratedTarget: .bool(true)], effectivePropertyValues: [:], frame: frame,
            audioSpectrum: secondAudio
        )
        let borrowedTarget = SceneDynamicTarget.layer(
            layerID: 20, field: .origin
        )
        let sameGenerationDifferentPayload = audio(
            left: 0.05, right: 0.1, generation: 2
        )
        let borrowedFrame = candidate.vectorProgram.evaluate(
            inputs: [borrowedTarget: .vector3(1, 1, 1)],
            effectivePropertyValues: [:], frame: frame,
            audioSpectrum: sameGenerationDifferentPayload
        )
        let borrowedFrameXYZ: [Double]
        if case let .vector3(x, y, z)? = borrowedFrame.values[borrowedTarget] {
            borrowedFrameXYZ = [x, y, z]
        } else {
            borrowedFrameXYZ = [-1, -1, -1]
        }
        let firstByLayer = Dictionary(uniqueKeysWithValues:
            first.layerMutations.map { ($0.layerID, $0.origin) }
        )
        let secondByLayer = Dictionary(uniqueKeysWithValues:
            second.layerMutations.map { ($0.layerID, $0.origin) }
        )
        candidate.vectorProgram.finalizeLayerMutations(committing: true)
        let cursorOwnersBeforeFailure = candidate.cursorProgram.ownerCount
        candidate.cursorProgram.systemInputConsumersChanged = false
        let failed = candidate.cursorProgram.dispatch(
            batch: batch(down: true), frame: frame,
            userPropertiesJSON: "{}", audioSpectrum: audio(left: 1, right: 1, generation: 3)
        )
        let afterFailure = candidate.cursorProgram.dispatch(
            batch: batch(down: false), frame: frame,
            userPropertiesJSON: "{}", audioSpectrum: audio(left: 0.5, right: 0.6, generation: 4)
        )
        let propertyOnly = try propertyAudio(initializes: false, frame: frame)
        let initializing = try propertyAudio(initializes: true, frame: frame)
        var payload: [String: Any] = [
            "propertyOnly": propertyOnly,
            "initializing": initializing,
            "migratedIsBorrowed": candidate.cursorProgram.bindings
                .first { $0.layerID == 10 }?.ownsOwner == false,
            "dependentControlSharesOwner": dependentControlSharesOwner,
            "preparedValueOwnerCount": candidate.vectorProgram.bindings.count,
            "distinctPreparedOwnerCount": Set(preparedOwners.map { ObjectIdentifier($0) }).count,
            "isolatedSharesOwner": isolatedSharesOwner,
            "isolatedHasOneValueAndCursorTarget":
                isolatedCandidate.constructionReport.instantiatedVectorTargets == [controlTarget]
                    && isolatedCandidate.constructionReport.instantiatedCursorTargets == [controlTarget],
            "migratedConstructionFailure": candidate.constructionReport.vectorFailures[migratedTarget]?.code ?? "",
            "quietPublished": quietFrame.values[migratedTarget] != nil,
            "quietFailures": quietFrame.failures.count,
            "firstControlX": firstByLayer[30]?.x ?? -1,
            "secondControlX": secondByLayer[30]?.x ?? -1,
            "failedOwnerCount": failed.failures.count,
            "failedPublishedLayerIDs": failed.layerMutations.map(\.layerID).sorted(),
            "afterFailureLayerIDs": afterFailure.layerMutations.map(\.layerID).sorted(),
            "cursorOwners": cursorOwnersBeforeFailure,
            "activeCursorOwnersAfterFailure": candidate.cursorProgram.ownerCount,
            "cursorChangeObserved": candidate.cursorProgram.systemInputConsumersChanged,
            "liveConsumerChanges": try liveConsumerChanges(frame: frame),
            "cursorOwnerIDs": candidate.cursorProgram.ownerLayerIDs.sorted(),
            "cursorConstructionComplete":
                candidate.constructionReport.isComplete,
            "cursorFailures":
                candidate.constructionReport.cursorFailures.keys
                    .map { String(describing: $0) }.sorted(),
            "borrowedRegistrationIDs": candidate.vectorProgram
                .cursorOwnerRegistrations.map(\.layerID).sorted(),
            "cursorHasAudio": candidate.cursorProgram.hasAudioConsumers,
            "vectorHasAudio": candidate.vectorProgram.hasAudioConsumers,
            "isolatedCursorHasAudio":
                isolatedCandidate.cursorProgram.hasAudioConsumers,
            "isolatedValueHasAudio":
                isolatedCandidate.vectorProgram.hasAudioConsumers,
            "firstFailures": first.failures.count,
            "firstEventOnlyX": firstByLayer[10]?.x ?? -1,
            "firstBorrowedX": firstByLayer[20]?.x ?? -1,
            "firstBorrowedY": firstByLayer[20]?.y ?? -1,
            "secondFailures": second.failures.count,
            "secondEventOnlyX": secondByLayer[10]?.x ?? -1,
            "secondBorrowedX": secondByLayer[20]?.x ?? -1,
            "borrowedFrameFailures": borrowedFrame.failures.count,
            "borrowedFramePublished": borrowedFrame.values[borrowedTarget] != nil,
            "borrowedFrameXYZ": borrowedFrameXYZ,
        ]
        _ = isolatedCandidate.cursorProgram.retire(layerIDs: [30], frame: frame, userPropertiesJSON: "{}")
        payload["lastCursorRetired"] = isolatedCandidate.cursorProgram.ownerCount == 0
            && !isolatedCandidate.cursorProgram.hasActiveOwners(excludingTargets: [])
            && !isolatedCandidate.cursorProgram.hasAudioConsumers
            && isolatedCandidate.cursorProgram.systemInputConsumersChanged
        let data = try JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    static func propertyAudio(initializes: Bool, frame: SceneScriptFrameInput) throws -> [String: Any] {
        let source = """
        const audio = engine.registerAudioBuffers(16);
        let initial = -1;
        \(initializes ? "export function init(v) { initial = audio.left[0]; return v; }" : "")
        export function applyUserProperties(props) {
            thisLayer.origin = new Vec3(audio.left[0], initial, 0);
        }
        """
        let descriptor = SceneRenderDescriptor(layers: [layer(id: 10, index: 0)])
        let bindings = [eventOnlyBinding(layerID: 10, index: 0, source: source)]
        let candidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: descriptor, runtimeDescriptor: descriptor,
            scriptBindings: bindings,
            vectorProjection: SceneScriptVectorProgram.project(descriptor: descriptor, scriptBindings: bindings),
            userPropertyDefinitions: [], timelineTargets: [], scalarExcludedTargets: [],
            stringExcludedTargets: [], admittedVectorPassTargets: [], generation: 53
        )
        let target = SceneDynamicTarget.layer(layerID: 10, field: .visibility)
        func evaluate(_ enabled: Bool, _ snapshot: SceneAudioSpectrumSnapshot) -> SceneScriptVectorFrameResult {
            let value = candidate.vectorProgram.evaluate(
                inputs: [target: .bool(true)], effectivePropertyValues: ["enabled": .bool(enabled)],
                frame: frame, audioSpectrum: snapshot
            )
            candidate.vectorProgram.finalizeLayerMutations(committing: true)
            return value
        }
        let first = evaluate(false, audio(left: 0.25, right: 0.5, generation: 1))
        let second = evaluate(true, audio(left: 0.75, right: 0.8, generation: 2))
        let silent = evaluate(false, audio(left: 0, right: 0, generation: 3))
        let quiet = evaluate(false, audio(left: 1, right: 1, generation: 4))
        return [
            "ownerCount": candidate.vectorProgram.bindings.count,
            "firstX": first.layerMutations.first?.origin.x ?? -2,
            "firstY": first.layerMutations.first?.origin.y ?? -2,
            "secondX": second.layerMutations.first?.origin.x ?? -2,
            "secondY": second.layerMutations.first?.origin.y ?? -2,
            "silentX": silent.layerMutations.first?.origin.x ?? -2,
            "quietPublished": !quiet.values.isEmpty || !quiet.layerMutations.isEmpty,
            "failures": first.failures.count + second.failures.count + silent.failures.count + quiet.failures.count,
        ]
    }

    static func audio(
        left: Float, right: Float, generation: UInt64
    ) -> SceneAudioSpectrumSnapshot {
        SceneAudioSpectrumSnapshot(
            left: [left] + Array(repeating: 0, count: 15),
            right: [right] + Array(repeating: 0, count: 15),
            generation: generation
        )
    }

    static func liveConsumerChanges(frame: SceneScriptFrameInput) throws -> [String: Bool] {
        let descriptor = SceneRenderDescriptor(layers: [layer(id: 20, index: 0)])
        let source = """
        const audio = engine.registerAudioBuffers(16);
        export function mediaPropertiesChanged(e) {}
        export function applyUserProperties(e) { if (engine.userProperties.enabled === false) throw Error('disabled'); }
        export function update(v) { return v; }
        """
        func candidate(_ source: String) throws -> SceneScriptQuickJSProgramCandidate {
            let bindings = [borrowedBinding(layerID: 20, index: 0, source: source)]
            return try SceneScriptQuickJSProgramCandidate.compile(authoredDescriptor: descriptor,
                runtimeDescriptor: descriptor, scriptBindings: bindings,
                vectorProjection: SceneScriptVectorProgram.project(descriptor: descriptor, scriptBindings: bindings),
                userPropertyDefinitions: [], timelineTargets: [], scalarExcludedTargets: [],
                stringExcludedTargets: [], admittedVectorPassTargets: [], generation: 71)
        }
        let target = SceneDynamicTarget.layer(layerID: 20, field: .origin)
        let prepared = try candidate(source)
        let program = prepared.vectorProgram
        func evaluate(_ enabled: Bool, revision: UInt64) -> SceneScriptVectorFrameResult {
            let result = program.evaluate(inputs: [target: .vector3(1, 2, 3)],
                effectivePropertyValues: ["enabled": .bool(enabled)], frame: frame, propertyRevision: revision,
                audioSpectrum: audio(left: 0.2, right: 0.3, generation: revision))
            program.finalizeLayerMutations(committing: true)
            return result
        }
        var checks: [String: Bool] = [:]
        prepared.domain?.systemInputConsumersChanged = false
        let failed = evaluate(false, revision: 1)
        checks["permanent-failure-signals-and-revokes-audio-media"] = failed.failures[target] != nil
            && prepared.domain?.systemInputConsumersChanged == true && !program.hasAudioConsumers
            && program.mediaOwnerRegistrations.isEmpty
        prepared.domain?.systemInputConsumersChanged = false
        _ = evaluate(false, revision: 1)
        checks["stable-disabled-owner-does-not-repeat-change"] = prepared.domain?.systemInputConsumersChanged == false
        let recovered = evaluate(true, revision: 2)
        checks["property-recovery-signals-and-restores-audio-media"] = recovered.failures.isEmpty
            && prepared.domain?.systemInputConsumersChanged == true && program.hasAudioConsumers
            && !program.mediaOwnerRegistrations.isEmpty
        prepared.domain?.systemInputConsumersChanged = false
        _ = evaluate(true, revision: 2)
        checks["stable-active-owner-does-not-repeat-change"] = prepared.domain?.systemInputConsumersChanged == false
        _ = program.retire(layerIDs: [20], frame: frame, userPropertiesJSON: "{}")
        checks["authored-retirement-signals-and-revokes-last-owner"] = prepared.domain?.systemInputConsumersChanged == true
            && !program.hasAudioConsumers && program.mediaOwnerRegistrations.isEmpty
        let badValue = try candidate("""
        const audio = engine.registerAudioBuffers(16);
        export function update(v) { return 'wrong value'; }
        """)
        badValue.domain?.systemInputConsumersChanged = false
        let invalid = badValue.vectorProgram.evaluate(inputs: [target: .vector3(1, 2, 3)],
            effectivePropertyValues: [:], frame: frame)
        checks["bad-return-keeps-consumer-without-membership-change"] = invalid.failures[target]?.code == "bad-return"
            && badValue.domain?.systemInputConsumersChanged == false && badValue.vectorProgram.hasAudioConsumers
        return checks
    }

    static func batch(down: Bool) -> SceneScriptCursorFrameBatch {
        let hits = Dictionary(uniqueKeysWithValues: [10, 20, 30].map { id in
            (id, SceneScriptCursorHit(
                layerID: id, worldPosition: .zero, localPosition: .zero
            ))
        })
        return .init(samples: [.init(
            hits: hits, pointerPosition: .zero,
            primaryButtonIsDown: down
        )], overflowed: false)
    }

    static func layer(id: Int, index: Int) -> SceneRenderDescriptor.Layer {
        .init(
            id: id, layerIndex: index, name: "owner-\(id)", visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
            scaleHasScript: false, alpha: 1, effects: [],
            contentKind: id == 20 ? "image" : "composition",
            sizeWH: [100, 100],
            utilityLayer: id == 20 ? nil : .init(
                kind: .composition, copyBackground: false, passthrough: false
            ),
            // Dependencies retain the visibility value owner; cursor callbacks
            // must borrow it instead of constructing a second event owner.
            dependencyLayerIDs: id == 30 ? [20] : [],
            authoredDependencies: id == 30 ? [20] : []
        )
    }

    static func eventOnlyBinding(
        layerID: Int, index: Int, source: String = eventOnlySource
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: owner(layerID: layerID, index: index),
            targetPath: [.key("objects"), .index(index), .key("visible")],
            properties: [:], authoredValue: .bool(true), valueType: .boolean,
            wrapperKeys: ["script", "value"]
        )
    }

    static func borrowedBinding(
        layerID: Int, index: Int, source: String = borrowedSource
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: owner(layerID: layerID, index: index),
            targetPath: [.key("objects"), .index(index), .key("origin")],
            properties: [:], authoredValue: .string("0 0 0"),
            valueType: .string, wrapperKeys: ["script", "value"]
        )
    }

    static func siblingBinding(
        layerID: Int, index: Int
    ) -> SceneScriptBindingIR {
        .init(
            source: siblingSource,
            owner: owner(layerID: layerID, index: index),
            targetPath: [.key("objects"), .index(index), .key("visible")],
            properties: [:], authoredValue: .bool(true),
            valueType: .boolean, wrapperKeys: ["script", "value"]
        )
    }

    static func owner(
        layerID: Int, index: Int
    ) -> SceneScriptBindingOwner {
        .init(
            kind: .object, objectIndex: index, objectID: layerID,
            effectIndex: nil, effectID: nil, passIndex: nil, passID: nil
        )
    }

    static let eventOnlySource = """
    const audio = engine.registerAudioBuffers(16);
    export function cursorDown() {
        thisLayer.origin = new Vec3(audio.left[0], audio.right[0], 0);
        if (audio.left[0] > 0.9) throw new Error("discard this owner only");
    }
    export function cursorUp() {
        thisLayer.origin = new Vec3(audio.left[0], audio.right[0], 0);
    }
    """

    static let borrowedSource = """
    const audio = engine.registerAudioBuffers(16);
    export function update(value) {
        return new Vec3(audio.left[0], audio.right[0], value.z);
    }
    export function cursorDown() {
        thisLayer.origin = new Vec3(audio.left[0], audio.right[0], 0);
    }
    export function cursorUp() {
        thisLayer.origin = new Vec3(audio.left[0], audio.right[0], 0);
    }
    """

    static let siblingSource = """
    export function update(value) { return value; }
    export function mediaPlaybackChanged() { shared.media = true; }
    """
}
'''


class SceneCursorAudioConsumerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temp_dir = tempfile.TemporaryDirectory(
            prefix="mwx-cursor-audio-consumer-"
        )
        temporary = Path(cls.temp_dir.name)
        cls.cursor_binary = compile_vector_harness(
            temporary_directory=temporary,
            harness_source=CURSOR_HARNESS,
            binary_name="scene-cursor-audio-consumer",
        )
        cls.cursor_result = json.loads(subprocess.run(
            [str(cls.cursor_binary)], check=True, capture_output=True, text=True
        ).stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp_dir.cleanup()

    def test_event_only_value_owner_and_cursor_share_audio_registration(self) -> None:
        self.assertTrue(self.cursor_result["isolatedCursorHasAudio"])
        self.assertTrue(self.cursor_result["isolatedValueHasAudio"])
        self.assertTrue(self.cursor_result["isolatedSharesOwner"])
        self.assertTrue(self.cursor_result["isolatedHasOneValueAndCursorTarget"])

    def test_event_only_and_update_callbacks_read_current_snapshot(self) -> None:
        self.assertEqual(self.cursor_result["cursorOwners"], 3)
        self.assertTrue(self.cursor_result["cursorConstructionComplete"])
        self.assertTrue(self.cursor_result["cursorHasAudio"])
        self.assertTrue(self.cursor_result["vectorHasAudio"])
        self.assertEqual(self.cursor_result["firstFailures"], 0)
        self.assertAlmostEqual(self.cursor_result["firstEventOnlyX"], 0.25)
        self.assertAlmostEqual(self.cursor_result["firstBorrowedX"], 0.25)
        self.assertAlmostEqual(self.cursor_result["firstBorrowedY"], 0.5)
        self.assertEqual(self.cursor_result["secondFailures"], 0)
        self.assertAlmostEqual(self.cursor_result["secondEventOnlyX"], 0.75)
        self.assertAlmostEqual(self.cursor_result["secondBorrowedX"], 0.75)

    def test_composition_event_audio_uses_one_borrowed_owner_and_stays_quiet(self) -> None:
        self.assertTrue(self.cursor_result["migratedIsBorrowed"])
        self.assertTrue(self.cursor_result["dependentControlSharesOwner"])
        self.assertEqual(self.cursor_result["preparedValueOwnerCount"], 4)
        self.assertEqual(self.cursor_result["distinctPreparedOwnerCount"], 4)
        self.assertEqual(self.cursor_result["migratedConstructionFailure"], "")
        self.assertFalse(self.cursor_result["quietPublished"])
        self.assertEqual(self.cursor_result["quietFailures"], 0)
        self.assertAlmostEqual(self.cursor_result["firstControlX"], 0.25)
        self.assertAlmostEqual(self.cursor_result["secondControlX"], 0.75)

    def test_failed_event_audio_owner_discards_mutations_and_preserves_peer(self) -> None:
        self.assertEqual(self.cursor_result["failedOwnerCount"], 2)
        self.assertEqual(self.cursor_result["failedPublishedLayerIDs"], [20])
        self.assertEqual(self.cursor_result["afterFailureLayerIDs"], [20])
        self.assertEqual(self.cursor_result["activeCursorOwnersAfterFailure"], 1)
        self.assertTrue(self.cursor_result["cursorChangeObserved"])
        self.assertTrue(self.cursor_result["lastCursorRetired"])

    def test_real_owner_failure_recovery_retirement_and_bad_return_demand(self) -> None:
        for name, passed in self.cursor_result["liveConsumerChanges"].items():
            with self.subTest(behavior=name):
                self.assertTrue(passed)

    def test_property_events_and_init_read_current_audio_before_any_callback(self) -> None:
        for key in ("propertyOnly", "initializing"):
            with self.subTest(key=key):
                value = self.cursor_result[key]
                self.assertEqual(value["ownerCount"], 1)
                self.assertEqual(value["failures"], 0)
                self.assertAlmostEqual(value["firstX"], 0.25)
                self.assertAlmostEqual(value["secondX"], 0.75)
                self.assertEqual(value["silentX"], 0)
                self.assertFalse(value["quietPublished"])
        self.assertEqual(self.cursor_result["initializing"]["firstY"], 0.25)
        self.assertEqual(self.cursor_result["initializing"]["secondY"], 0.25)

    def test_borrowed_owner_reuses_generation_in_later_vector_pass(self) -> None:
        self.assertEqual(self.cursor_result["borrowedFrameFailures"], 0)
        self.assertTrue(self.cursor_result["borrowedFramePublished"])
        self.assertAlmostEqual(self.cursor_result["borrowedFrameXYZ"][0], 0.75)
        self.assertAlmostEqual(self.cursor_result["borrowedFrameXYZ"][1], 0.8)
        self.assertEqual(self.cursor_result["borrowedFrameXYZ"][2], 1)


if __name__ == "__main__":
    unittest.main()
