#!/usr/bin/env python3

"""Captured primary drags keep owner-local ordered cursor transactions."""

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


HARNESS = r'''
@main
enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: [layer(id: 10, index: 0)])
        let frame = SceneScriptFrameInput(
            timing: .init(
                wallDate: Date(timeIntervalSince1970: 0),
                simulationFrameTime: 1.0 / 60.0,
                sceneTime: 2
            ),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let program = SceneScriptCursorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor,
            scriptBindings: [binding(layerID: 10, index: 0, source: dragSource)],
            generation: 41
        )
        let drag = program.dispatch(
            batch: .init(samples: [
                sample(position: .zero, localX: 0, hits: [10], down: false),
                sample(position: .zero, localX: 0, hits: [10], down: true),
                sample(position: .init(0.8, 0), localX: 0.8, hits: [], down: true),
                sample(position: .init(1.2, 0), localX: 1.2, hits: [], down: true),
                sample(position: .init(1.2, 0), localX: 1.2, hits: [], down: false),
            ], overflowed: false),
            frame: frame,
            userPropertiesJSON: "{}"
        )
        let runtime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: [10]
        )
        let dragApplied = success(runtime.apply(drag.layerMutations))
        let committed = runtime.snapshot().authoredLayerValues[
            .layer(layerID: 10, field: .origin)
        ]

        let revertProgram = SceneScriptCursorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor,
            scriptBindings: [binding(layerID: 10, index: 0, source: revertSource)],
            generation: 42
        )
        let revert = revertProgram.dispatch(
            batch: .init(samples: [
                sample(position: .zero, localX: 0, hits: [10], down: false),
                sample(position: .zero, localX: 0, hits: [10], down: true),
                sample(position: .zero, localX: 0, hits: [10], down: false),
            ], overflowed: false),
            frame: frame,
            userPropertiesJSON: "{}"
        )

        let uncaptured = program.dispatch(
            batch: .init(samples: [
                sample(position: .init(1.4, 0), localX: 1.4, hits: [], down: false),
            ], overflowed: false),
            frame: frame,
            userPropertiesJSON: "{}"
        )
        let overflowProgram = SceneScriptCursorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor,
            scriptBindings: [binding(layerID: 10, index: 0, source: dragSource)],
            generation: 43
        )
        _ = overflowProgram.dispatch(
            batch: .init(samples: [
                sample(position: .zero, localX: 0, hits: [10], down: false),
                sample(position: .zero, localX: 0, hits: [10], down: true),
            ], overflowed: false),
            frame: frame,
            userPropertiesJSON: "{}"
        )
        let overflow = overflowProgram.dispatch(
            batch: .init(samples: [
                sample(position: .init(1.2, 0), localX: 1.2, hits: [], down: true),
            ], overflowed: true),
            frame: frame,
            userPropertiesJSON: "{}"
        )
        let afterOverflowRelease = overflowProgram.dispatch(
            batch: .init(samples: [
                sample(position: .init(1.3, 0), localX: 1.3, hits: [], down: false),
            ], overflowed: false),
            frame: frame,
            userPropertiesJSON: "{}"
        )

        let peerDescriptor = SceneRenderDescriptor(layers: [
            layer(id: 10, index: 0), layer(id: 20, index: 1),
        ])
        let failureProgram = SceneScriptCursorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: peerDescriptor,
            scriptBindings: [
                binding(layerID: 10, index: 0, source: failureSource),
                binding(layerID: 20, index: 1, source: peerSource),
            ],
            generation: 44
        )
        let failure = failureProgram.dispatch(
            batch: .init(samples: [
                sample(position: .zero, localX: 0, hits: [10, 20], down: false),
                sample(position: .zero, localX: 0, hits: [10, 20], down: true),
                sample(position: .init(0.2, 0), localX: 0.2, hits: [10, 20], down: true),
                sample(position: .init(0.8, 0), localX: 0.8, hits: [], down: true),
                sample(position: .init(0.8, 0), localX: 0.8, hits: [], down: false),
            ], overflowed: false),
            frame: frame,
            userPropertiesJSON: "{}"
        )

        let conflictRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: [10]
        )
        let conflict = conflictRuntime.apply([
            authoredOrigin(x: 1), authoredOrigin(x: 2),
        ])
        let final = drag.layerMutations.first
        let reverted = revert.layerMutations.first
        let peer = failure.layerMutations.first { $0.layerID == 20 }
        let payload: [String: Any] = [
            "owners": program.ownerCount,
            "dragFailures": drag.failures.count,
            "dragMutationCount": drag.layerMutations.count,
            "dragFinalX": final?.origin.x ?? -1,
            "dragFinalY": final?.origin.y ?? -1,
            "dragApplied": dragApplied,
            "committedX": vectorX(committed),
            "capturedAfterDrag": program.capturedOwnerLayerIDs.count,
            "revertMutationCount": revert.layerMutations.count,
            "revertFinalX": reverted?.origin.x ?? -1,
            "uncapturedMutations": uncaptured.layerMutations.count,
            "overflowSignaled": overflow.inputBatchOverflowed,
            "overflowMutations": overflow.layerMutations.count,
            "afterOverflowReleaseMutations": afterOverflowRelease.layerMutations.count,
            "capturedAfterOverflow": overflowProgram.capturedOwnerLayerIDs.count,
            "failedOwners": failure.failures.keys.sorted(),
            "failedOwnerOutputLeaked": failure.layerMutations.contains {
                $0.layerID == 10
            },
            "peerMutationCount": failure.layerMutations.filter {
                $0.layerID == 20
            }.count,
            "peerFinalX": peer?.origin.x ?? -1,
            "failureMaterialMutations": failure.materialFunctionMutations.count,
            "failureAnimationMutations": failure.animationMutations.count,
            "crossOwnerConflictPreserved": conflictFailure(conflict),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    static func sample(
        position: SIMD2<Float>,
        localX: Double,
        hits hitLayerIDs: Set<Int>,
        down: Bool
    ) -> SceneScriptCursorFrameSample {
        let ownerLayerIDs: Set<Int> = [10, 20]
        let projections = Dictionary(uniqueKeysWithValues: ownerLayerIDs.map {
            layerID in
            (layerID, SceneScriptCursorHit(
                layerID: layerID,
                worldPosition: .init(localX * 100, 0, 0),
                localPosition: .init(localX, 0, 0)
            ))
        })
        return .init(
            hits: projections.filter { hitLayerIDs.contains($0.key) },
            ownerProjections: projections,
            pointerPosition: position,
            primaryButtonIsDown: down
        )
    }

    static func layer(id: Int, index: Int) -> SceneRenderDescriptor.Layer {
        .init(
            id: id, layerIndex: index, name: "owner-\(id)", visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
            scaleHasScript: false, alpha: 1, effects: [],
            contentKind: "composition", sizeWH: [100, 100],
            utilityLayer: .init(
                kind: .composition, copyBackground: false, passthrough: false
            )
        )
    }

    static func binding(
        layerID: Int,
        index: Int,
        source: String
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object, objectIndex: index, objectID: layerID,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil
            ),
            targetPath: [.key("objects"), .index(index), .key("visible")],
            properties: [:], authoredValue: .bool(true), valueType: .boolean,
            wrapperKeys: ["script", "value"]
        )
    }

    static func authoredOrigin(x: Double) -> SceneScriptLayerMutation {
        .init(
            kind: .upsert, isDynamic: false, fields: .origin,
            layerID: 10, orderIndex: 0, visible: true, alpha: 1,
            origin: .init(x, 0, 0), scale: .init(1, 1, 1), angles: .zero,
            color: .init(1, 1, 1), pointSize: 32, text: "", font: ""
        )
    }

    static func success(
        _ result: Result<Void, SceneScriptScalarRuntimeFailure>
    ) -> Bool {
        if case .success = result { return true }
        return false
    }

    static func conflictFailure(
        _ result: Result<Void, SceneScriptScalarRuntimeFailure>
    ) -> Bool {
        guard case let .failure(.invalidArgument(message)) = result else {
            return false
        }
        return message == "conflicting authored layer mutation target"
    }

    static func vectorX(_ value: SceneDynamicValue?) -> Double {
        guard case let .vector3(x, _, _)? = value else { return -1 }
        return x
    }

    static let dragSource = """
    export function cursorDown(event) {
        thisLayer.origin = new Vec3(event.localPosition.x, 1, 0);
    }
    export function cursorMove(event) {
        const previous = thisLayer.origin;
        thisLayer.origin = new Vec3(
            event.localPosition.x, previous.y + 1, previous.z
        );
    }
    export function cursorUp(event) {
        const previous = thisLayer.origin;
        thisLayer.origin = new Vec3(
            event.localPosition.x, previous.y + 10, previous.z
        );
    }
    export function cursorClick(event) {
        thisLayer.origin = new Vec3(event.localPosition.x, 99, 0);
    }
    """

    static let revertSource = """
    export function cursorDown(event) {
        thisLayer.origin = new Vec3(1, 0, 0);
    }
    export function cursorUp(event) {
        thisLayer.origin = new Vec3(0, 0, 0);
    }
    """

    static let failureSource = """
    let moveCount = { value: 0 };
    export function cursorDown(event) {
        thisLayer.origin = new Vec3(1, 0, 0);
    }
    export function cursorMove(event) {
        moveCount.value += 1;
        if (moveCount.value === 2) throw new Error('late move failure');
        thisLayer.origin = new Vec3(2, 0, 0);
    }
    """

    static let peerSource = """
    export function cursorMove(event) {
        const previous = thisLayer.origin;
        thisLayer.origin = new Vec3(previous.x + 1, 0, 0);
    }
    """
}
'''


class SceneCursorCaptureContinuityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temp_dir = tempfile.TemporaryDirectory(
            prefix="mwx-cursor-capture-continuity-"
        )
        cls.binary = compile_vector_harness(
            temporary_directory=Path(cls.temp_dir.name),
            harness_source=HARNESS,
            binary_name="scene-cursor-capture-continuity",
        )
        cls.result = json.loads(subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        ).stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp_dir.cleanup()

    def test_captured_drag_reads_staged_state_and_commits_once(self) -> None:
        self.assertEqual(self.result["owners"], 1)
        self.assertEqual(self.result["dragFailures"], 0)
        self.assertEqual(self.result["dragMutationCount"], 1)
        self.assertAlmostEqual(self.result["dragFinalX"], 1.2)
        self.assertEqual(self.result["dragFinalY"], 13)
        self.assertTrue(self.result["dragApplied"])
        self.assertAlmostEqual(self.result["committedX"], 1.2)
        self.assertEqual(self.result["capturedAfterDrag"], 0)

    def test_later_callback_can_restore_the_frame_start_value(self) -> None:
        self.assertEqual(self.result["revertMutationCount"], 1)
        self.assertEqual(self.result["revertFinalX"], 0)

    def test_late_owner_failure_rolls_back_prior_callbacks_only(self) -> None:
        self.assertEqual(self.result["failedOwners"], [10])
        self.assertFalse(self.result["failedOwnerOutputLeaked"])
        self.assertEqual(self.result["peerMutationCount"], 1)
        self.assertEqual(self.result["peerFinalX"], 2)
        self.assertEqual(self.result["failureMaterialMutations"], 0)
        self.assertEqual(self.result["failureAnimationMutations"], 0)

    def test_uncaptured_outside_move_and_overflow_publish_nothing(self) -> None:
        self.assertEqual(self.result["uncapturedMutations"], 0)
        self.assertTrue(self.result["overflowSignaled"])
        self.assertEqual(self.result["overflowMutations"], 0)
        self.assertEqual(self.result["afterOverflowReleaseMutations"], 0)
        self.assertEqual(self.result["capturedAfterOverflow"], 0)

    def test_raw_cross_owner_conflict_guard_remains_hard(self) -> None:
        self.assertTrue(self.result["crossOwnerConflictPreserved"])


if __name__ == "__main__":
    unittest.main()
