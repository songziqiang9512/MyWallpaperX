#!/usr/bin/env python3
"""Shared Puppet controls preserve cadence, fractional pose, alpha and owner isolation."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_scene_puppet_playback import SCENE_ROOT, SWIFT_SOURCES


FIXTURE = Path(__file__).with_name("fixtures") / "ScenePuppetAnimationPlaybackRuntimeCases.swift"
HARNESS = FIXTURE.read_text(encoding="utf-8")


class PuppetAnimationPlaybackRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not shutil.which("swiftc"):
            raise unittest.SkipTest("Swift toolchain unavailable")
        output_root = Path(__file__).resolve().parents[2] / ".artifacts/tmp/animation-rate-source-329-20261020/tests"
        output_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="mwx-puppet-playback-runtime-", dir=output_root) as directory:
            root = Path(directory)
            source, binary = root / "runtime.swift", root / "runtime"
            source.write_text(HARNESS, encoding="utf-8")
            command = ["swiftc", "-module-cache-path", str(root / "module-cache"),
                       *map(str, SWIFT_SOURCES),
                       str(SCENE_ROOT / "Systems/Puppet/ScenePuppetAnimationControl.swift"),
                       str(SCENE_ROOT / "Systems/Puppet/ScenePuppetAnimationPlaybackRuntime.swift"),
                       str(SCENE_ROOT / "Systems/Properties/ScenePuppetAnimationPropertyTarget.swift"),
                       str(source), "-o", str(binary)]
            run = subprocess.run(command, capture_output=True, text=True, timeout=120)
            if run.returncode:
                raise RuntimeError(run.stdout + run.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, check=True, timeout=30)
            cls.result = json.loads(run.stdout)

    def test_source_frame_crossings_survive_same_cadence_republication_and_late_registration(self) -> None:
        result = self.result["animationEvents"]["crossing"]
        self.assertEqual(result["initial"], [])
        self.assertEqual(result["before"], [])
        for key, name, frame, sequence in [("exact", "renamed-early", 1, 1),
                                           ("late", "late", 3, 2), ("wrapped", "renamed-early", 1, 3)]:
            self.assertEqual(result[key], [{"parent": 42, "clip": 0, "sequence": sequence,
                                            "name": name, "frame": frame}])
        self.assertTrue(result["same"])
        self.assertTrue(result["lateParentPrepared"])
        self.assertEqual(result["next"], [])
        self.assertTrue(self.result["animationEvents"]["eventDefinitionConflict"])

    def test_event_order_uses_crossing_time_then_authored_clip_and_record_order(self) -> None:
        result = self.result["animationEvents"]
        self.assertEqual([event["name"] for event in result["ordering"]],
                         ["fast-first", "authored-first", "authored-second", "fast-tie"])
        self.assertEqual([event["sequence"] for event in result["ordering"]], [1, 1, 2, 2])
        self.assertEqual([event["name"] for event in result["wrapOrder"]], ["late", "renamed-early"])

    def test_controls_hidden_and_stationary_cadences_never_synthesize_seek_events(self) -> None:
        result = self.result["animationEvents"]
        self.assertTrue(result["controls"]["quiet"])
        self.assertEqual([event["name"] for event in result["controls"]["play"]], ["renamed-early"])
        self.assertTrue(result["controls"]["frozen"])
        self.assertEqual(result["visibility"]["hidden"], [])
        self.assertEqual(result["visibility"]["stationary"], [])
        self.assertEqual([event["name"] for event in result["visibility"]["restored"]], ["renamed-early"])

    def test_parent_budget_is_atomic_and_preserves_other_parent_and_pose(self) -> None:
        result = self.result["animationEvents"]
        self.assertTrue(result["atBudget"])
        self.assertTrue(result["sourceBudget"])
        budget = result["budget"]
        self.assertEqual([event["parent"] for event in budget["events"]], [77])
        self.assertEqual(budget["failureCount"], 2)
        self.assertEqual(budget["failures"], ["eventBudgetExceeded"] * 2)
        self.assertTrue(budget["healthyPose"])
        self.assertTrue(budget["retainedFailures"])

    def test_unsupported_events_fail_locally_without_narrowing_existing_no_event_playback(self) -> None:
        result = self.result["animationEvents"]["failures"]
        self.assertEqual(result["multiple"], ["multipleLoopsCrossed"])
        self.assertEqual(result["multipleEvents"], [])
        self.assertTrue(result["multiplePose"])
        self.assertEqual(result["nonFinite"], ["nonFinitePhase"])
        self.assertEqual(result["invalid"], ["unsupportedMode", "invalidEvent"])
        self.assertTrue(result["noEventProfile"])

    def test_retire_filters_events_and_failures_without_reissuing_peer_occurrences(self) -> None:
        result = self.result["animationEvents"]["retirement"]
        self.assertEqual(result["beforeEvents"], 2)
        self.assertEqual(result["beforeFailures"], 1)
        self.assertEqual([event["parent"] for event in result["events"]], [42])
        self.assertEqual(result["failures"], 0)
        self.assertTrue(result["removedPose"])

    def test_authored_retirement_removes_pose_and_events_without_resampling_peers(self) -> None:
        self.assertTrue(all(self.result["authoredRetirement"]), self.result["authoredRetirement"])

    def test_dynamic_retirement_removes_only_the_retired_instance_and_preserves_consumed_peers(self) -> None:
        self.assertEqual(self.result["dynamicRetirement"], [True] * 9)

    def test_hidden_position_freezes_and_resumes_current_cadence_only(self) -> None:
        result = self.result["hiddenResume"]
        self.assertEqual(result["first"], [[1, 2, 0]])
        self.assertEqual(result["beforeHide"], [[2, 3, 0]])
        self.assertEqual(result["hidden"], [[]])
        self.assertEqual(result["resumed"], [[2, 3, 0.5]])

    def test_initially_hidden_clip_starts_at_zero_before_resume(self) -> None:
        self.assertEqual(self.result["initialHiddenResume"], [[0, 1, 0.5]])

    def test_same_cadence_multi_consumer_and_stale_request_reuse_snapshot(self) -> None:
        result = self.result["hiddenResume"]
        self.assertEqual(result["duplicate"], result["resumed"])
        self.assertEqual(result["stale"], result["resumed"])
        self.assertEqual(result["duplicateSceneTime"], 10.25)
        self.assertTrue(result["visibilityReadOnce"])
        self.assertTrue(result["oldSnapshotRetained"])

    def test_rebuild_registration_keeps_position_and_conflicts_preserve_definition(self) -> None:
        result = self.result["registration"]
        self.assertTrue(result["same"])
        self.assertEqual(result["afterRebuild"], [[3, 4, 0]])
        self.assertFalse(result["conflictAccepted"])
        self.assertFalse(result["alphaConflictAccepted"])
        self.assertEqual(result["afterConflict"], [[3, 4, 0.5]])

    def test_reference_state_identity_does_not_stop_clock_alpha_events_or_hidden_resume(self) -> None:
        for result, name in zip(self.result["denseState"], ("held", "renamed-σ"), strict=True):
            with self.subTest(name=name):
                self.assertTrue(result["same"])
                self.assertTrue(result["stateOnlyConflict"])
                self.assertTrue(result["defaultEquivalent"])
                self.assertEqual(result["firstSamples"], [[1, 2, 0]])
                self.assertEqual(result["firstPoseAlpha"], [0, .75])
                self.assertEqual(result["firstEvents"], [f"{name}-cue"])
                self.assertEqual(result["nextSamples"], [[2, 3, 0]])
                self.assertEqual(result["nextPoseAlpha"], [0, .5])
                self.assertEqual(result["hidden"], [[]])
                self.assertEqual(result["resumed"], [[2, 3, .5]])
                self.assertEqual(result["resumedPoseAlpha"], [0, .375])

    def test_single_loop_mirror_and_rates_preserve_natural_fractional_sampler(self) -> None:
        self.assertEqual(len(self.result["naturalSamples"]), 9)
        self.assertTrue(all(self.result["naturalSamples"].values()))

    def test_parent_layer_identity_prevents_visibility_cross_talk(self) -> None:
        self.assertEqual(self.result["parentIdentity"], {"hidden": [[]], "visible": [[0, 1, 0.5]]})

    def test_authored_position_is_part_of_immutable_registration(self) -> None:
        self.assertFalse(self.result["authoredPositionConflictAccepted"])

    def test_missing_or_wrong_visibility_stays_hidden_and_preserves_zero_position(self) -> None:
        self.assertEqual(self.result["invalidVisibility"],
                         {"missing": [[]], "wrong": [[]], "restored": [[0, 1, 0.5]]})

    def test_paused_cadence_late_registration_fills_only_missing_parent(self) -> None:
        empty = self.result["pausedEmptyRegistration"]
        self.assertTrue(empty["oldFrameStaysEmpty"])
        self.assertEqual(empty["filled"], [[1, 2, 0]])
        self.assertEqual(empty["sceneTime"], 2.5)
        result = self.result["pausedLateRegistration"]
        for name in ("oldParent", "retainedParent", "newParent", "repeatedParent"):
            with self.subTest(frame=name):
                self.assertEqual(result[name], [[1, 2, 0]])
        self.assertEqual(result["sceneTime"], 2.5)
        self.assertTrue(result["onlyNewVisibilityRead"])
        self.assertTrue(result["repeatReadsNoVisibility"])
        self.assertTrue(result["oldSnapshotMissingNewParent"])
        self.assertEqual(result["nextOldParent"], [[1, 2, 0.5]])
        self.assertEqual(result["nextNewParent"], [[1, 2, 0.5]])

    def test_ordered_init_play_seek_preserves_cadence_and_fractional_pose_alpha(self) -> None:
        self.assertTrue(self.result["controlAdmissionPure"])
        result = self.result["controlInit"]
        metadata = result["metadata"]
        self.assertEqual({key: metadata[key] for key in ("parent", "index", "id", "animationID",
                                                       "name", "fps", "count", "duration")},
                         {"parent": 42, "index": 1, "id": 10, "animationID": 1,
                          "name": "track", "fps": 2, "count": 4, "duration": 2})
        self.assertTrue(result["committed"]["playing"])
        self.assertAlmostEqual(result["committed"]["frame"], 3.72, places=6)
        self.assertEqual(result["sameCadence"], [[0, 1, 0]])
        self.assertEqual(result["oldPose"], [0, 1])
        next_frame = self.result["seekNext"]
        self.assertAlmostEqual(next_frame["frame"]["frame"], 3.74, places=6)
        self.assertAlmostEqual(next_frame["poseAlpha"][0], 3.74, places=6)
        self.assertAlmostEqual(next_frame["poseAlpha"][1], 0.065, places=6)

    def test_pause_stop_play_and_rate_changes_preserve_position(self) -> None:
        result = self.result["playbackControls"]
        self.assertAlmostEqual(result["rate"]["frame"], 0.74, places=6)
        self.assertEqual(result["rate"]["rate"], 2)
        self.assertEqual(result["paused"]["frame"], result["rate"]["frame"])
        self.assertFalse(result["paused"]["playing"])
        self.assertEqual(result["stopped"]["frame"], 0)
        self.assertFalse(result["stopped"]["playing"])
        self.assertEqual(result["restarted"]["frame"], 0.5)
        self.assertTrue(result["restarted"]["playing"])

    def test_explicit_seek_keeps_raw_value_and_clamps_only_effective_pose(self) -> None:
        for result, raw in zip(self.result["explicitSeeks"], [-1, 4, 4.5, 8.5, 0.5, 1]):
            with self.subTest(raw=raw):
                self.assertEqual(result["raw"], raw)
                bounded = max(0, min(4, raw))
                self.assertEqual(result["poseAlpha"], [bounded, 1 - bounded / 4])
                self.assertEqual(result["ended"], 1)
        self.assertEqual(self.result["explicitSeeks"][0]["samples"], [[0, 1, 0]])
        self.assertEqual(self.result["explicitSeeks"][1]["samples"], [[3, 4, 1]])

    def test_controlled_blend_updates_pose_and_alpha_at_next_cadence(self) -> None:
        result = self.result["controlledBlend"]
        self.assertEqual(result["old"], [1, 0.75])
        self.assertEqual(result["next"], [0.5, 0.875])
        self.assertEqual(result["sameCadence"], result["old"])
        self.assertEqual(result["blend"], [0.5])
        self.assertTrue(result["sameRegistration"])

    def test_script_visibility_bool_replaces_setter_mirror_and_hidden_position_freezes(self) -> None:
        result = self.result["scriptVisibility"]
        self.assertTrue(result["setterImmediate"])
        self.assertFalse(result["hidden"]["visible"])
        self.assertTrue(result["hidden"]["playing"])
        self.assertEqual(result["hidden"]["frame"], 0.5)
        self.assertEqual(result["hiddenSamples"], [[]])
        self.assertEqual(result["restored"]["frame"], 1)
        self.assertEqual(result["restoreSamples"], [[1, 2, 0]])

    def test_unadmitted_script_presence_retains_authored_visible_fallback(self) -> None:
        self.assertEqual(self.result["unadmittedScriptFallbacks"], [True, True])

    def test_zero_rate_and_static_visibility_setter_preserve_frozen_position(self) -> None:
        result = self.result["zeroRateStaticVisible"]
        self.assertEqual(result["zero"]["frame"], 1)
        self.assertTrue(result["zero"]["playing"])
        self.assertEqual(result["hidden"]["frame"], 1)
        self.assertFalse(result["hidden"]["visible"])
        self.assertEqual(result["hiddenSamples"], [[]])
        self.assertEqual(result["restored"]["frame"], 1.5)

    def test_late_registration_preserves_frozen_samples_metadata_and_pending_controls(self) -> None:
        result = self.result["controlledLateRegistration"]
        self.assertTrue(result["frozenStateRetained"])
        self.assertTrue(result["frozenPoseRetained"])
        self.assertEqual(result["frozenBlend"], [1])
        self.assertEqual(result["newParent"], [[1, 2, 0]])
        self.assertEqual(result["sceneTime"], 0.5)
        self.assertEqual(result["next"]["frame"], 3)
        self.assertFalse(result["next"]["playing"])
        self.assertEqual(result["nextPoseAlpha"], [1.5, 0.625])

    def test_invalid_control_bundle_is_atomic_local_and_cadence_bound(self) -> None:
        result = self.result["controlFailures"]
        for key in ("allRejected", "invalidCadence", "invalidBudget", "unchanged", "replayAccepted",
                    "conflictingReplay", "stale"):
            with self.subTest(check=key):
                self.assertTrue(result[key])
        self.assertEqual(result["controlled"], [[1, 2, 0.5]])
        self.assertEqual(result["other"], [[0, 1, 0.5]])

    def test_cross_parent_seek_keeps_hidden_and_exact_visibility_owner(self) -> None:
        self.assertEqual(self.result["crossParentHiddenSeek"], [True] * 5)

    def test_command_budget_aggregates_consumed_cadence_and_resets_on_next_cadence(self) -> None:
        self.assertEqual(self.result["aggregateBudget"],
                         {"overflowRejected": True, "stateRetained": True,
                          "nextCadenceAccepted": True, "frame": 3})

    def test_ended_sequence_is_natural_once_per_cadence_and_unknown_profiles_are_typed(self) -> None:
        result = self.result["ended"]
        self.assertEqual(result["crossing"]["frame"], 0.5)
        self.assertEqual(result["crossing"]["ended"], 1)
        self.assertEqual(result["repeated"], result["crossing"])
        self.assertEqual(result["pausedEndpoint"]["frame"], 4)
        self.assertEqual(result["pausedEndpoint"]["ended"], 1)
        self.assertEqual(result["second"]["frame"], 0.5)
        self.assertEqual(result["second"]["ended"], 2)
        self.assertEqual(result["multiple"]["ended"], 2)
        self.assertEqual(result["multiple"]["endedFailure"], "multipleLoopsCrossed")
        self.assertFalse(result["multiple"]["supportsEnded"])
        self.assertEqual(result["multipleSamples"], [[0, 1, 0.5]])
        self.assertTrue(all(self.result["endedUnsupportedModes"]))


    def test_created_single_uses_original_clock_controls_membership_and_retirement(self) -> None:
        for row in self.result["singleInstances"]:
            with self.subTest(source=row["sourceID"]):
                for key in ("sourceLookup", "atomicRollback", "createdIdentity", "frozenEmpty",
                            "terminalPause", "removed", "sameFrozen", "quietSingle",
                            "expiredRejected", "noRevive", "peerAlive", "retiredSource"):
                    self.assertTrue(row[key], (key, row))
                self.assertEqual(row["bornFrame"], 0)
                self.assertEqual(row["lateFrame"], 0.5)
                self.assertEqual(row["pausedFrame"], 1.5)
                self.assertEqual(row["pausedSample"], [[1, 2, 0.5]])
                self.assertEqual(row["rebuiltFrame"], 1.5)
                self.assertEqual(row["resumedFrame"], 2)
                self.assertEqual(row["stoppedFrame"], 0)
                self.assertEqual(row["retirementRevision"], 7)


if __name__ == "__main__":
    unittest.main()
