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
    SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "Properties/SceneSurfaceEvaluationTransaction.swift",
]
HOST_FRAME_DRIVER = (
    SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+FrameDriver.swift"
)
HOST_FRAME_DRIVER_LIFECYCLE = (
    SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+FrameDriverLifecycle.swift"
)
TRANSACTION = SCENE_ROOT / "Properties/SceneSurfaceEvaluationTransaction.swift"

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
        var firstSurface = SceneSurfaceEvaluationTransaction()
        var secondSurface = SceneSurfaceEvaluationTransaction()
        var emptySurface = SceneSurfaceEvaluationTransaction()
        var statefulSurface = SceneSurfaceEvaluationTransaction()
        var pendingSurface = SceneSurfaceEvaluationTransaction()

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
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
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


class SceneSurfaceEvaluationTransactionTests(unittest.TestCase):
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

    def test_host_commits_surface_evaluations_after_submission_barrier(self) -> None:
        source = HOST_FRAME_DRIVER.read_text(encoding="utf-8")
        lifecycle = HOST_FRAME_DRIVER_LIFECYCLE.read_text(encoding="utf-8")
        self.assertIn("PendingEvaluation", source)
        prepare_position = source.index(
            "surface.evaluationTransaction.prepare("
        )
        outcome_position = source.index(
            "let allSurfacesSubmitted =", prepare_position
        )
        commit_call_position = source.index(
            "commitSubmittedSceneFrame(", outcome_position
        )
        self.assertLess(prepare_position, outcome_position)
        self.assertLess(outcome_position, commit_call_position)
        self.assertIn("func commitSubmittedSceneFrame(", lifecycle)
        self.assertIn("evaluationTransaction.commit", lifecycle)

    def test_host_reuses_one_typed_resolution_but_keeps_surface_prepare_owner(self) -> None:
        source = HOST_FRAME_DRIVER.read_text(encoding="utf-8")
        transaction = TRANSACTION.read_text(encoding="utf-8")
        self.assertIn(
            "let preliminarySceneScriptResolution = SceneDynamicSnapshotResolver().resolve(",
            source,
        )
        self.assertIn(
            "base: preliminarySceneScriptResolution",
            source,
        )
        self.assertIn(
            "let sharedSurfaceResolution = SceneDynamicSnapshotResolver().resolve(",
            source,
        )
        self.assertIn("resolution: sharedSurfaceResolution", source)
        self.assertNotIn("sceneScriptValues: commonSceneScriptValues", source)
        self.assertIn(
            "resolution: SceneDynamicSnapshotResolution",
            transaction,
        )
        self.assertIn(
            "generation/last-snapshot publication state",
            transaction,
        )

    def test_previous_value_projection_reads_requested_target_identity(self) -> None:
        source = (SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift").read_text(
            encoding="utf-8"
        )
        self.assertIn("for target in targets", source)
        self.assertIn("guard let resolved = values[target]", source)
        self.assertNotIn("values.reduce(into:", source)


if __name__ == "__main__":
    unittest.main()
