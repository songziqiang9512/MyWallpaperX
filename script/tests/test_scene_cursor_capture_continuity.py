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
        let dragOutcome = runtime.applyIsolatingOwners(drag.layerMutations)
        let dragApplied = success(dragOutcome, expectedCount: 1)
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
        let crossDescriptor = SceneRenderDescriptor(layers: [
            layer(id: 10, index: 0), textLayer(id: 20, index: 1),
        ])
        let peerDomain = try SceneScriptQuickJSDomain()
        let peerProgram = SceneScriptCursorProgram.compile(
            domain: peerDomain,
            descriptor: crossDescriptor,
            scriptBindings: [
                binding(layerID: 10, index: 0, source: peerMutationSource),
            ],
            generation: 50
        )
        let peerResult = peerProgram.dispatch(
            batch: .init(samples: [
                sample(position: .zero, localX: 0, hits: [10], down: false),
                sample(position: .zero, localX: 0, hits: [10], down: true),
                sample(position: .init(0.5, 0), localX: 0.5, hits: [10], down: true),
                sample(position: .init(0.5, 0), localX: 0.5, hits: [10], down: false),
            ], overflowed: false),
            frame: frame,
            userPropertiesJSON: "{}"
        )
        let peerRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: crossDescriptor,
            authoredMutationLayerIDs: [10]
        )
        let peerOutcome = peerRuntime.applyIsolatingOwners(
            peerResult.layerMutations
        )
        let peerApplied = success(peerOutcome, expectedCount: 1)
        let peerTopology = peerRuntime.snapshot()
        let peerSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 1,
            definitions: peerRuntime.authoredLayerDefinitions,
            sceneScriptValues: peerTopology.authoredLayerValues
        ).snapshot
        try peerDomain.publishLayerSnapshot(peerSnapshot, descriptor: crossDescriptor)
        let verificationProgram = SceneScriptCursorProgram.compile(
            domain: peerDomain,
            descriptor: crossDescriptor,
            scriptBindings: [
                binding(layerID: 10, index: 0, source: peerVerificationSource),
            ],
            generation: 51
        )
        let verification = verificationProgram.dispatch(
            batch: .init(samples: [
                sample(position: .zero, localX: 0, hits: [10], down: false),
                sample(position: .zero, localX: 0, hits: [10], down: true),
            ], overflowed: false),
            frame: frame,
            userPropertiesJSON: "{}"
        )
        let rollbackProgram = SceneScriptCursorProgram.compile(
            domain: try SceneScriptQuickJSDomain(),
            descriptor: crossDescriptor,
            scriptBindings: [
                binding(layerID: 10, index: 0, source: peerRollbackSource),
            ],
            generation: 52
        )
        let rollback = rollbackProgram.dispatch(
            batch: .init(samples: [
                sample(position: .zero, localX: 0, hits: [10], down: false),
                sample(position: .zero, localX: 0, hits: [10], down: true),
                sample(position: .init(0.5, 0), localX: 0.5, hits: [10], down: true),
            ], overflowed: false),
            frame: frame,
            userPropertiesJSON: "{}"
        )
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
            "failurePeerMutationCount": failure.layerMutations.filter {
                $0.layerID == 20
            }.count,
            "peerFinalX": peer?.origin.x ?? -1,
            "failureMaterialMutations": failure.materialFunctionMutations.count,
            "failureAnimationMutations": failure.animationMutations.count,
            "crossOwnerConflictPreserved": conflictFailure(conflict),
            "peerFailures": peerResult.failures.count,
            "peerFailureCode": peerResult.failures[10]?.code ?? "",
            "peerFailure": peerResult.failures[10].map(String.init(describing:)) ?? "",
            "crossPeerMutationCount": peerResult.layerMutations.count,
            "peerOwnerEffectsCount": peerResult.ownerEffects.count,
            "peerOwnerEffectsLayerCount": peerResult.ownerEffects.first?
                .layerMutations.count ?? -1,
            "peerOwnerTargetPreserved": peerResult.layerMutations.first?
                .ownerTarget == .layer(layerID: 10, field: .visibility),
            "peerTextRestoredAcrossCallbacks": peerResult.layerMutations.first?.text == "authored",
            "peerScaleAccumulatedAcrossCallbacks": peerResult.layerMutations.first?.scale == .init(3, 3, 4),
            "peerVisibilityRetainedAcrossCallbacks": peerResult.layerMutations.first?.visible == false,
            "peerFieldsRetainedAcrossCallbacks": peerResult.layerMutations.first?.fields == [.scale, .visibility, .text],
            "peerApplied": peerApplied,
            "peerTextPublished": peerTopology.authoredLayerValues[
                .text(layerID: 20, field: .content)
            ] == .string("authored"),
            "peerScalePublished": peerTopology.authoredLayerValues[
                .layer(layerID: 20, field: .scale)
            ] == .vector3(3, 3, 4),
            "peerVisibilityPublished": peerTopology.authoredLayerValues[
                .layer(layerID: 20, field: .visibility)
            ] == .bool(false),
            "nextFrameProjectionFailures": verification.failures.count,
            "nextFrameProjectionFailureCode": verification.failures[10]?.code ?? "",
            "nextFrameProjectionFailure": verification.failures[10].map(
                String.init(describing:)
            ) ?? "",
            "nextFrameProjectionMutationCount": verification.layerMutations.count,
            "rollbackFailedOwners": rollback.failures.keys.sorted(),
            "rollbackLeakedMutations": rollback.layerMutations.count,
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

    static func textLayer(id: Int, index: Int) -> SceneRenderDescriptor.Layer {
        var result = layer(id: id, index: index)
        result.contentKind = "text"
        result.text = "authored"
        result.textStyle = .init(
            fontPath: nil, colorRGB: [1, 1, 1], pointSize: 32
        )
        return result
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
            color: .init(1, 1, 1), pointSize: 32, text: "", font: "",
            assetPath: nil
        )
    }

    static func success(
        _ outcome: SceneScriptLayerMutationApplyOutcome,
        expectedCount: Int
    ) -> Bool {
        outcome.failures.isEmpty
            && outcome.committedMutationCount == expectedCount
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

    static let peerMutationSource = """
    export function cursorDown(event) {
        const peer = thisScene.getLayer("owner-20");
        peer.text = "~";
        peer.visible = false;
        peer.scale = peer.scale.add(new Vec3(1, 0, 0));
        if (peer.text !== "~") throw new Error("staged text unavailable");
    }
    export function cursorMove(event) {
        const peer = thisScene.getLayer("owner-20");
        peer.scale = peer.scale.add(new Vec3(1, 2, 3));
        if (peer.scale.y !== 3) throw new Error("staged scale unavailable");
        if (peer.visible !== false) throw new Error("staged visibility unavailable");
    }
    export function cursorUp(event) {
        const peer = thisScene.getLayer("owner-20");
        if (peer.text !== "~" || peer.scale.x !== 3 || peer.visible !== false) {
            throw new Error("cross-callback peer baseline unavailable");
        }
        peer.text = "authored";
    }
    """

    static let peerVerificationSource = """
    export function cursorDown(event) {
        const peer = thisScene.getLayer("owner-20");
        if (peer.text !== "authored") throw new Error("committed text unavailable");
        if (peer.scale.x !== 3 || peer.scale.y !== 3 || peer.scale.z !== 4) {
            throw new Error("committed scale unavailable");
        }
        if (peer.visible !== false) throw new Error("committed visibility unavailable");
        thisLayer.origin = new Vec3(5, 0, 0);
    }
    """

    static let peerRollbackSource = """
    export function cursorDown(event) {
        thisScene.getLayer("owner-20").text = "must-not-publish";
    }
    export function cursorMove(event) {
        thisScene.getLayer("missing-layer").scale = new Vec3(9, 9, 9);
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
        self.assertEqual(self.result["failurePeerMutationCount"], 1)
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

    def test_exact_peer_writes_commit_together_and_project_next_frame(self) -> None:
        self.assertEqual(self.result["peerFailures"], 0)
        self.assertEqual(self.result["crossPeerMutationCount"], 1)
        self.assertEqual(self.result["peerOwnerEffectsCount"], 1)
        self.assertEqual(self.result["peerOwnerEffectsLayerCount"], 1)
        self.assertTrue(self.result["peerOwnerTargetPreserved"])
        self.assertTrue(self.result["peerTextRestoredAcrossCallbacks"])
        self.assertTrue(self.result["peerScaleAccumulatedAcrossCallbacks"])
        self.assertTrue(self.result["peerVisibilityRetainedAcrossCallbacks"])
        self.assertTrue(self.result["peerFieldsRetainedAcrossCallbacks"])
        self.assertTrue(self.result["peerApplied"])
        self.assertTrue(self.result["peerTextPublished"])
        self.assertTrue(self.result["peerScalePublished"])
        self.assertTrue(self.result["peerVisibilityPublished"])
        self.assertEqual(self.result["nextFrameProjectionFailures"], 0)
        self.assertEqual(self.result["nextFrameProjectionMutationCount"], 1)

    def test_missing_peer_rolls_back_prior_peer_write(self) -> None:
        self.assertEqual(self.result["rollbackFailedOwners"], [10])
        self.assertEqual(self.result["rollbackLeakedMutations"], 0)


if __name__ == "__main__":
    unittest.main()
