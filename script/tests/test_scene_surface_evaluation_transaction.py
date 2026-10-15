#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneEvaluationTransaction.swift",
]
HOST_FRAME_DRIVER = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift"
)
HOST_FRAME_DRIVER_LIFECYCLE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriverLifecycle.swift"
)
TRANSACTION = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneEvaluationTransaction.swift"

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let target = SceneDynamicTarget.layer(layerID: 7, field: .alpha)
        let definition = SceneDynamicTargetDefinition(
            target: target,
            valueType: .scalar,
            authoredValue: .scalar(0.25)
        )
        var firstSurface = SceneEvaluationTransaction()
        var secondSurface = SceneEvaluationTransaction()
        var emptySurface = SceneEvaluationTransaction()
        var statefulSurface = SceneEvaluationTransaction()
        var pendingSurface = SceneEvaluationTransaction()

        let emptyFirst = emptySurface.evaluate(frameIndex: 40, definitions: [])
        let emptySecond = emptySurface.evaluate(frameIndex: 41, definitions: [])

        let first = firstSurface.evaluate(frameIndex: 100, definitions: [definition])
        let firstPublished = firstSurface.previousValues(for: [target])
        let same = firstSurface.evaluate(frameIndex: 101, definitions: [definition])
        let changed = firstSurface.evaluate(
            frameIndex: 102,
            definitions: [definition],
            userValues: [target: .scalar(0.5)]
        )
        let changedPublished = firstSurface.previousValues(for: [target])
        let isolated = secondSurface.evaluate(frameIndex: 200, definitions: [definition])
        let isolatedPublished = secondSurface.previousValues(for: [target])
        let sourceOnly = firstSurface.evaluate(
            frameIndex: 103,
            definitions: [definition],
            timelineValues: [target: .scalar(0.5)]
        )
        let invalidHigherPriority = firstSurface.evaluate(
            frameIndex: 104,
            definitions: [definition],
            timelineValues: [target: .scalar(0.5)],
            sceneScriptValues: [target: .scalar(.nan)]
        )
        let secondChanged = secondSurface.evaluate(
            frameIndex: 201,
            definitions: [definition],
            sceneScriptValues: [target: .scalar(0.75)]
        )
        _ = statefulSurface.evaluate(
            frameIndex: 300,
            definitions: [definition],
            sceneScriptValues: [target: .scalar(0.75)]
        )
        let statefulPublished = statefulSurface.previousValues(for: [target])
        _ = statefulSurface.evaluate(
            frameIndex: 301,
            definitions: [definition],
            userValues: [target: .scalar(0.5)]
        )
        let userOverridePublished = statefulSurface.previousValues(for: [target])

        _ = pendingSurface.evaluate(
            frameIndex: 400,
            definitions: [definition],
            sceneScriptValues: [target: .scalar(0.25)]
        )
        let pending = pendingSurface.prepare(
            frameIndex: 401,
            index: SceneDynamicSnapshotResolver.prepare(definitions: [definition]),
            sceneScriptValues: [target: .scalar(0.75)]
        )
        let pendingPreview = pending.resolution.snapshot
        let pendingBeforeCommit = pendingSurface.previousValues(for: [target])
        pendingSurface.commit(pending)
        let pendingAfterCommit = pendingSurface.previousValues(for: [target])
        let discarded = pendingSurface.prepare(
            frameIndex: 402,
            index: SceneDynamicSnapshotResolver.prepare(definitions: [definition]),
            sceneScriptValues: [target: .scalar(0.9)]
        )
        let discardedPreview = discarded.resolution.snapshot
        let pendingAfterDiscard = pendingSurface.previousValues(for: [target])

        let payload: [String: Any] = [
            "empty": [identity(emptyFirst), identity(emptySecond)],
            "firstSurface": [
                state(first, target),
                state(same, target),
                state(changed, target),
                state(sourceOnly, target),
                state(invalidHigherPriority, target),
            ],
            "published": [
                scalar(firstPublished[target]),
                scalar(changedPublished[target]),
                scalar(isolatedPublished[target]),
                scalar(statefulPublished[target]),
                scalar(userOverridePublished[target]),
            ],
            "secondSurface": [
                state(isolated, target),
                state(secondChanged, target),
            ],
            "pending": [
                scalar(pendingPreview[target]?.value),
                scalar(pendingBeforeCommit[target]),
                scalar(pendingAfterCommit[target]),
                scalar(discardedPreview[target]?.value),
                scalar(pendingAfterDiscard[target]),
            ],
            "invalidDiagnostics": invalidHigherPriority.diagnostics.map {
                [$0.source.rawValue, $0.code.rawValue]
            },
            "scoped": scopedSnapshots(),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func scopedSnapshots() -> [String: Any] {
        let volume = SceneDynamicTarget.layer(layerID: 45, field: .volume)
        let peer = SceneDynamicTarget.layer(layerID: 9, field: .alpha)
        let timeline = SceneDynamicTarget.layer(layerID: 10, field: .brightness)
        let origin = SceneDynamicTarget.layer(layerID: 11, field: .origin)
        let scale = SceneDynamicTarget.layer(layerID: 11, field: .scale)
        let fov = SceneDynamicTarget.layer(layerID: 12, field: .fov)
        let unknown = SceneDynamicTarget.layer(layerID: 999, field: .volume)
        let definitions: [SceneDynamicTargetDefinition] = [
            .init(target: volume, valueType: .scalar, authoredValue: .scalar(0.2),
                  userPropertyNumericRange: 0 ... 1),
            .init(target: peer, valueType: .scalar, authoredValue: .scalar(0.1),
                  userPropertyNumericRange: 0 ... 2),
            .init(target: timeline, valueType: .scalar, authoredValue: .scalar(0.3)),
            .init(target: origin, valueType: .vector3, authoredValue: .vector3(0, 0, 0)),
            .init(target: scale, valueType: .vector3, authoredValue: .vector3(1, 1, 1)),
            .init(target: fov, valueType: .scalar, authoredValue: .scalar(60)),
        ]
        let index = SceneDynamicSnapshotResolver.prepare(definitions: definitions)
        var transaction = SceneEvaluationTransaction()
        _ = transaction.evaluate(
            frameIndex: 900, index: index,
            userValues: [volume: .scalar(0.25), scale: .vector3(2, 2, 2)],
            timelineValues: [volume: .scalar(0.4), timeline: .scalar(0.8)],
            sceneScriptValues: [volume: .scalar(0.6), peer: .scalar(0.75),
                                origin: .vector3(4, 5, 6)]
        )
        let base = transaction.committedSnapshot!
        let pending = transaction.prepareScoped(
            replacing: [volume], index: index,
            userValues: [volume: .scalar(0.3)],
            timelineValues: [volume: .scalar(0.45)],
            sceneScriptValues: [volume: .scalar(0.9)]
        )!
        let unselected: Set<SceneDynamicTarget> = [peer, timeline, origin, scale, fov]
        let preservesPeers = unselected.allSatisfy {
            pending.snapshot[$0] == base[$0]
                && pending.snapshot.authoredValue(for: $0) == base.authoredValue(for: $0)
                && pending.snapshot.userPropertyNumericRange(for: $0)
                    == base.userPropertyNumericRange(for: $0)
        }
        let unpublished = transaction.committedSnapshot == base
        transaction.commit(pending)
        let published = transaction.committedSnapshot == pending.snapshot
        let sameValueNewSource = transaction.prepareScoped(
            replacing: [volume], index: index, userValues: [volume: .scalar(0.9)]
        )!
        let invalidScript = transaction.prepareScoped(
            replacing: [volume], index: index,
            userValues: [volume: .scalar(0.3)],
            timelineValues: [volume: .scalar(0.45)],
            sceneScriptValues: [volume: .scalar(.nan)]
        )!
        let invalidUserAndType = transaction.prepareScoped(
            replacing: [volume], index: index,
            userValues: [volume: .scalar(2)],
            sceneScriptValues: [volume: .string("invalid")]
        )!
        let nonFiniteUser = transaction.prepareScoped(
            replacing: [volume], index: index, userValues: [volume: .scalar(.infinity)]
        )!
        let invalidFOV = transaction.prepareScoped(
            replacing: [fov], index: index,
            userValues: [fov: .scalar(90)], sceneScriptValues: [fov: .scalar(180)]
        )!
        let omittedLowerLane = transaction.prepareScoped(
            replacing: [volume], index: index,
            userValues: [volume: .scalar(0.3)]
        )!
        let resetOrigin = transaction.prepareScoped(replacing: [origin], index: index)!
        let resetTransform = transaction.prepareScoped(
            replacing: [origin, scale], index: index
        )!
        var empty = SceneEvaluationTransaction()
        let noBase = empty.prepareScoped(replacing: [volume], index: index) == nil
        let rejectedUnknown = transaction.prepareScoped(
            replacing: [unknown], index: index
        ) == nil
        let rejectedOutsideInputs = transaction.prepareScoped(
            replacing: [volume], index: index, userValues: [peer: .scalar(0.5)]
        ) == nil && transaction.prepareScoped(
            replacing: [volume], index: index, timelineValues: [peer: .scalar(0.5)]
        ) == nil && transaction.prepareScoped(
            replacing: [volume], index: index, sceneScriptValues: [peer: .scalar(0.5)]
        ) == nil
        let changedFirst: [SceneDynamicTargetDefinition] = [
            .init(target: volume, valueType: .scalar, authoredValue: .scalar(0.21),
                  userPropertyNumericRange: 0 ... 1),
            .init(target: volume, valueType: .scalar, authoredValue: .scalar(0.2),
                  userPropertyNumericRange: 0 ... 2),
            .init(target: volume, valueType: .string, authoredValue: .string("seed")),
            .init(target: volume, valueType: .scalar, authoredValue: .scalar(.nan)),
            .init(target: volume, valueType: .scalar, authoredValue: .string("bad type")),
        ]
        let rejectedChangedSchema = changedFirst.allSatisfy { replacement in
            transaction.prepareScoped(
                replacing: [volume],
                index: SceneDynamicSnapshotResolver.prepare(
                    definitions: [replacement] + Array(definitions.dropFirst())
                )
            ) == nil
        }
        let topologyVariants: [[SceneDynamicTargetDefinition]] = [
            Array(definitions.dropLast()),
            definitions + [.init(target: unknown, valueType: .scalar, authoredValue: .scalar(0))],
            definitions + [definitions[0]],
        ]
        let rejectedTopology = topologyVariants.allSatisfy { variant in
            transaction.prepareScoped(
                replacing: [volume],
                index: SceneDynamicSnapshotResolver.prepare(definitions: variant)
            ) == nil
        }
        var changedPeerSchema = definitions
        changedPeerSchema[1] = .init(
            target: peer, valueType: .scalar, authoredValue: .scalar(0.1),
            userPropertyNumericRange: 0 ... 3
        )
        let rejectedUnselectedSchemaChange = transaction.prepareScoped(
            replacing: [volume],
            index: SceneDynamicSnapshotResolver.prepare(definitions: changedPeerSchema)
        ) == nil
        return [
            "prepared": state(pending.resolution, volume),
            "sameValueNewSource": state(sameValueNewSource.resolution, volume),
            "invalidScriptFallback": state(invalidScript.resolution, volume),
            "invalidScriptDiagnostics": invalidScript.diagnostics.map { $0.code.rawValue },
            "invalidUserAndTypeFallback": state(invalidUserAndType.resolution, volume),
            "invalidUserAndTypeDiagnostics": invalidUserAndType.diagnostics.map { $0.code.rawValue },
            "nonFiniteUserFallback": state(nonFiniteUser.resolution, volume),
            "nonFiniteUserDiagnostics": nonFiniteUser.diagnostics.map { $0.code.rawValue },
            "invalidFOVFallback": state(invalidFOV.resolution, fov),
            "invalidFOVDiagnostics": invalidFOV.diagnostics.map { $0.code.rawValue },
            "omittedLowerLane": state(omittedLowerLane.resolution, volume),
            "preservesPeers": preservesPeers,
            "preservesTransformMetadata": pending.snapshot.dynamicTransformLayerIDsForFrame == [11],
            "preservesSelectedMetadata": pending.snapshot.authoredValue(for: volume) == .scalar(0.2)
                && pending.snapshot.userPropertyNumericRange(for: volume) == (0 ... 1),
            "resetOriginKeepsUntouchedScale": resetOrigin.snapshot.dynamicTransformLayerIDsForFrame == [11]
                && resetOrigin.snapshot[scale] == base[scale],
            "resetTransformRemovesDynamicMetadata": resetTransform.snapshot.dynamicTransformLayerIDsForFrame.isEmpty,
            "unpublished": unpublished,
            "published": published,
            "discardedCandidatesKeepPublication": transaction.committedSnapshot == pending.snapshot,
            "noBase": noBase,
            "rejectedUnknown": rejectedUnknown,
            "rejectedOutsideInputs": rejectedOutsideInputs,
            "rejectedChangedSchema": rejectedChangedSchema,
            "rejectedTopology": rejectedTopology,
            "rejectedUnselectedSchemaChange": rejectedUnselectedSchemaChange,
        ]
    }

    static func identity(_ resolution: SceneDynamicSnapshotResolution) -> [UInt64] {
        [resolution.snapshot.frameIndex, resolution.snapshot.generation]
    }

    static func state(
        _ resolution: SceneDynamicSnapshotResolution,
        _ target: SceneDynamicTarget
    ) -> [String] {
        let value = resolution.snapshot[target]
        return [
            String(resolution.snapshot.frameIndex),
            String(resolution.snapshot.generation),
            scalar(value?.value),
            value?.source.rawValue ?? "missing",
        ]
    }

    static func scalar(_ value: SceneDynamicValue?) -> String {
        guard case let .scalar(number) = value else { return "missing" }
        return String(number)
    }
}
'''


# Host all-surface rollback source checks retired with D10.
# Actual presentation/VM behavior: test_scene_frame_presentation_integration.
# GPU source ownership: test_scene_surface_submission and the FIFO harness below.
class SceneEvaluationTransactionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-surface-transaction-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-surface-transaction"
        compilation = subprocess.run(
            ["swiftc", *map(str, SOURCES), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_first_empty_payload_stays_at_generation_zero(self) -> None:
        self.assertEqual(self.result["empty"], [[40, 0], [41, 0]])

    def test_same_payload_keeps_generation_but_frame_identity_advances(self) -> None:
        first, same = self.result["firstSurface"][:2]
        self.assertEqual(first[:2], ["100", "1"])
        self.assertEqual(same[:2], ["101", "1"])

    def test_value_change_increments_generation_once(self) -> None:
        changed = self.result["firstSurface"][2]
        self.assertEqual(changed[:3], ["102", "2", "0.5"])

    def test_previous_values_follow_the_published_snapshot(self) -> None:
        self.assertEqual(
            self.result["published"],
            ["missing", "missing", "missing", "0.75", "missing"],
        )

    def test_transactions_keep_generation_state_isolated(self) -> None:
        isolated, changed = self.result["secondSurface"]
        self.assertEqual(isolated[:2], ["200", "1"])
        self.assertEqual(changed[:2], ["201", "2"])

    def test_source_only_change_does_not_increment_generation(self) -> None:
        source_only = self.result["firstSurface"][3]
        self.assertEqual(source_only[:2], ["103", "2"])
        self.assertEqual(source_only[3], "timeline")

    def test_invalid_higher_priority_value_does_not_change_payload(self) -> None:
        invalid = self.result["firstSurface"][4]
        self.assertEqual(invalid[:2], ["104", "2"])
        self.assertEqual(invalid[3], "timeline")
        self.assertEqual(
            self.result["invalidDiagnostics"],
            [["sceneScript", "nonFiniteValue"]],
        )

    def test_pending_evaluation_is_not_published_until_commit(self) -> None:
        self.assertEqual(
            self.result["pending"],
            ["0.75", "0.25", "0.75", "0.9", "0.75"],
        )

    def test_scoped_refresh_freezes_frame_and_preserves_unselected_publication(self) -> None:
        scoped = self.result["scoped"]
        self.assertEqual(scoped["prepared"], ["900", "2", "0.9", "sceneScript"])
        self.assertEqual(scoped["sameValueNewSource"], ["900", "2", "0.9", "userProperty"])
        for key in ["preservesPeers", "preservesTransformMetadata", "preservesSelectedMetadata",
                    "resetOriginKeepsUntouchedScale", "resetTransformRemovesDynamicMetadata"]:
            self.assertTrue(scoped[key], key)

    def test_scoped_candidates_publish_only_on_commit(self) -> None:
        for key in ["unpublished", "published", "discardedCandidatesKeepPublication"]:
            self.assertTrue(self.result["scoped"][key], key)

    def test_scoped_inputs_reuse_validation_and_explicit_lower_priority_lanes(self) -> None:
        scoped = self.result["scoped"]
        self.assertEqual(scoped["invalidScriptFallback"][2:], ["0.45", "timeline"])
        self.assertEqual(scoped["invalidScriptDiagnostics"], ["nonFiniteValue"])
        self.assertEqual(scoped["invalidUserAndTypeFallback"][2:], ["0.2", "authored"])
        self.assertEqual(scoped["invalidUserAndTypeDiagnostics"],
                         ["userPropertyValueOutOfRange", "valueTypeMismatch"])
        self.assertEqual(scoped["nonFiniteUserFallback"][2:], ["0.2", "authored"])
        self.assertEqual(scoped["nonFiniteUserDiagnostics"], ["nonFiniteValue"])
        self.assertEqual(scoped["invalidFOVFallback"][2:], ["90.0", "userProperty"])
        self.assertEqual(scoped["invalidFOVDiagnostics"], ["valueOutOfRange"])
        self.assertEqual(scoped["omittedLowerLane"][2:], ["0.3", "userProperty"])

    def test_scoped_refresh_rejects_missing_base_wrong_scope_and_schema_drift(self) -> None:
        for key in ["noBase", "rejectedUnknown", "rejectedOutsideInputs",
                    "rejectedChangedSchema", "rejectedTopology", "rejectedUnselectedSchemaChange"]:
            self.assertTrue(self.result["scoped"][key], key)



    def test_previous_value_projection_reads_requested_target_identity(self) -> None:
        source = (REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift").read_text(
            encoding="utf-8"
        )
        self.assertIn("for target in targets", source)
        self.assertIn("guard let resolved = values[target]", source)
        self.assertNotIn("values.reduce(into:", source)


if __name__ == "__main__":
    unittest.main()
