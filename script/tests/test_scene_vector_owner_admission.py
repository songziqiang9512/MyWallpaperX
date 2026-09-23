#!/usr/bin/env python3

"""G->C vector admission and fresh-domain candidate publication."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

try:
    from .scene_vector_owner_admission_harness import HARNESS
    from .scene_vector_vm_test_support import compile_vector_harness
except ImportError:
    from scene_vector_owner_admission_harness import HARNESS
    from scene_vector_vm_test_support import compile_vector_harness


class SceneVectorOwnerAdmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-vector-owner-"
        )
        cls.binary = compile_vector_harness(
            Path(cls.temporary_directory.name),
            HARNESS,
            "vector-owner-admission",
        )
        completed = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.value = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_only_material_consumers_construct_pass_owners(self) -> None:
        value = self.value
        self.assertEqual(value["projected"], 6)
        self.assertEqual(value["consumers"], 4)
        self.assertEqual(value["definitions"], 2)
        self.assertEqual(value["claimedValue"], [2, 2])
        self.assertEqual(value["claimedFailures"], 0)
        self.assertFalse(value["unclaimedPublished"])
        self.assertFalse(value["failedPublished"])

    def test_every_failed_family_rebuilds_in_a_fresh_domain(self) -> None:
        value = self.value
        self.assertTrue(value["domainCommitted"])
        self.assertEqual(value["vectorExpected"], 5)
        self.assertEqual(value["vectorInstantiated"], 2)
        self.assertEqual(value["vectorRejected"], 3)
        self.assertEqual(
            value["vectorFailureCodes"],
            ["exception", "exception", "exception"],
        )
        self.assertEqual(value["cursorExpected"], 1)
        self.assertEqual(value["cursorRejected"], 1)
        self.assertEqual(value["scalarExpected"], 1)
        self.assertEqual(value["scalarRejected"], 1)
        self.assertEqual(value["stringExpected"], 1)
        self.assertEqual(value["stringRejected"], 1)
        self.assertEqual(value["passRequested"], 4)
        self.assertEqual(value["passInstantiated"], 2)
        self.assertEqual(value["passRejected"], 2)

    def test_engine_global_poison_is_source_local_and_peers_still_run(self) -> None:
        self.assertTrue(self.value["enginePoisonRejected"])
        self.assertFalse(self.value["enginePoisonPublished"])
        self.assertEqual(self.value["claimedValue"], [2, 2])

    def test_owner_handle_globals_are_immutable_and_peer_safe(self) -> None:
        self.assertEqual(self.value["handleGuardValue"], [2, 2])

    def test_duplicate_target_never_enters_candidate_set(self) -> None:
        self.assertEqual(self.value["duplicates"], 1)
        self.assertEqual(self.value["duplicateProjected"], 0)

    def test_aggregate_work_budget_charges_actual_candidate_attempts(
        self,
    ) -> None:
        self.assertTrue(self.value["aggregateDomainCommitted"])
        self.assertEqual(self.value["aggregateFailures"], 0)
        self.assertEqual(
            self.value["aggregateFailureCodes"],
            [],
        )
        self.assertFalse(self.value["hardAggregateDomainCommitted"])
        self.assertEqual(self.value["hardAggregateFailures"], 4_097)
        self.assertEqual(
            self.value["hardAggregateFailureCodes"],
            ["budget-exceeded"],
        )
        self.assertTrue(self.value["oversizedCancellationEscaped"])

    def test_source_budget_accepts_exact_per_owner_and_aggregate_boundaries(
        self,
    ) -> None:
        self.assertTrue(self.value["exactSourceBoundaryCommitted"])

    def test_visibility_cursor_callback_borrows_single_vector_owner(self) -> None:
        self.assertTrue(self.value["claimedCursorOverlapCommitted"])
        self.assertEqual(self.value["claimedCursorOverlapStaticProjection"], 1)
        self.assertEqual(self.value["claimedCursorOverlapVectorExpected"], 1)
        self.assertEqual(self.value["claimedCursorOverlapVectorInstantiated"], 1)
        self.assertEqual(self.value["claimedCursorOverlapCursorExpected"], 1)
        self.assertEqual(self.value["claimedCursorOverlapCursorOwnerCount"], 1)
        self.assertFalse(self.value["claimedCursorOverlapCursorOwnsOwner"])

    def test_mixed_frame_and_cursor_source_has_one_vector_owner_and_borrowed_input(
        self,
    ) -> None:
        self.assertTrue(self.value["mixedCursorCommitted"])
        self.assertEqual(self.value["mixedCursorStaticProjection"], 1)
        self.assertEqual(self.value["mixedCursorVectorExpected"], 1)
        self.assertEqual(self.value["mixedCursorVectorInstantiated"], 1)
        self.assertEqual(self.value["mixedCursorCursorExpected"], 1)
        self.assertEqual(self.value["mixedCursorOwnerCount"], 1)
        self.assertTrue(self.value["mixedCursorBorrowed"])

    def test_export_forms_dispatch_from_single_vector_owned_cursor(self) -> None:
        self.assertEqual(self.value["constCursorVectorExpected"], 1)
        self.assertEqual(self.value["constCursorExpected"], 1)
        self.assertEqual(self.value["constCursorOwnerCount"], 1)
        self.assertTrue(self.value["constCursorBorrowed"])
        self.assertEqual(self.value["constCursorMoveFailures"], 0)
        self.assertEqual(self.value["constCursorMoveX"], 47)
        self.assertEqual(self.value["asyncCursorVectorExpected"], 1)
        self.assertEqual(self.value["asyncCursorExpected"], 1)
        self.assertEqual(self.value["asyncCursorMoveFailures"], 0)
        self.assertEqual(self.value["asyncCursorMoveX"], 48)

    def test_named_export_dispatches_and_unresolved_reexport_does_not(self) -> None:
        self.assertEqual(self.value["namedCursorVectorExpected"], 1)
        self.assertEqual(self.value["namedCursorExpected"], 1)
        self.assertEqual(self.value["namedCursorMoveFailures"], 0)
        self.assertEqual(self.value["namedCursorMoveX"], 49)
        self.assertEqual(self.value["reexportCursorVectorExpected"], 1)
        self.assertEqual(self.value["reexportCursorExpected"], 0)

    def test_borrowed_cursor_receives_script_properties_before_first_event(self) -> None:
        self.assertEqual(self.value["propertyCursorVectorOwners"], 1)
        self.assertTrue(self.value["propertyCursorBorrowed"])
        self.assertEqual(self.value["propertyCursorFirstFailures"], 0)
        self.assertEqual(self.value["propertyCursorFirstX"], 3)
        self.assertEqual(self.value["propertyCursorLiveFailures"], 0)
        self.assertEqual(self.value["propertyCursorLiveX"], 5)

    def test_non_cursor_exports_and_audio_registration_are_not_dropped(self) -> None:
        self.assertEqual(self.value["mediaMixedVectorExpected"], 1)
        self.assertEqual(self.value["mediaMixedCursorExpected"], 1)
        self.assertEqual(self.value["destroyMixedVectorExpected"], 1)
        self.assertEqual(self.value["destroyMixedCursorExpected"], 0)
        self.assertEqual(self.value["audioMixedVectorExpected"], 1)
        self.assertEqual(self.value["audioMixedCursorExpected"], 1)
        self.assertEqual(self.value["nonFunctionVectorExpected"], 1)
        self.assertEqual(self.value["nonFunctionCursorExpected"], 0)
        self.assertEqual(self.value["regexLiteralVectorExpected"], 1)
        self.assertEqual(self.value["regexLiteralCursorExpected"], 0)

    def test_duplicate_standalone_candidates_preserve_vector_target(self) -> None:
        self.assertEqual(self.value["duplicateCursorStaticProjection"], 0)
        self.assertEqual(self.value["duplicateCursorDuplicates"], 1)
        self.assertEqual(self.value["duplicateCursorVectorExpected"], 0)
        self.assertEqual(self.value["duplicateCursorExpected"], 0)

    def test_mixed_wrapper_duplicate_cannot_reenter_standalone_cursor(self) -> None:
        self.assertEqual(self.value["mixedDuplicateTargets"], 1)
        self.assertEqual(self.value["mixedDuplicateVectorExpected"], 0)
        self.assertEqual(self.value["mixedDuplicateCursorExpected"], 0)
        self.assertEqual(self.value["mixedDuplicateCursorOwners"], 0)

    def test_disabled_media_visibility_cannot_reenter_standalone_cursor(self) -> None:
        self.assertEqual(self.value["routedGenericMediaTargets"], 1)
        self.assertEqual(self.value["routedGenericVectorOwners"], 1)
        self.assertEqual(self.value["routedGenericCursorOwners"], 1)
        self.assertEqual(self.value["routedDisabledMediaTargets"], 1)
        self.assertEqual(self.value["routedDisabledVectorOwners"], 0)
        self.assertEqual(self.value["routedDisabledCursorOwners"], 0)

    def test_same_layer_standalone_and_vector_cursor_targets_are_both_counted(self) -> None:
        self.assertEqual(self.value["vectorCursorCollisionVectorExpected"], 2)
        self.assertEqual(self.value["vectorCursorCollisionCursorExpected"], 2)

    def test_pass_owned_cursor_callback_never_becomes_a_cursor_owner(self) -> None:
        # Official Cursor Events contract: cursor events only work on objects
        # marked Solid; an effect or pass is not a layer object, so its cursor
        # callback stays on the pass value route and never claims a cursor owner
        # (nor fabricates a cursor failure for a route it cannot have).
        self.assertEqual(
            self.value["passCursorProjectedPassTargets"],
            ["10:mediaColor", "10:unclaimed"],
        )
        self.assertEqual(self.value["passCursorOwners"], 0)
        self.assertEqual(self.value["passCursorFailures"], 0)
        self.assertEqual(self.value["passCursorVectorOwners"], 1)
        # A pass-owned script that exports only cursor callbacks is admitted as
        # a pass value owner (measured: one definition, no failure) and still
        # never becomes a cursor owner.
        self.assertEqual(
            self.value["passCursorOnlyPassTargets"], ["10:unclaimed"]
        )
        self.assertEqual(self.value["passCursorOnlyVectorOwners"], 1)
        self.assertEqual(self.value["passCursorOnlyOwners"], 0)
        self.assertEqual(self.value["passCursorOnlyCursorFailures"], 0)
        self.assertEqual(self.value["passCursorOnlyVectorFailures"], [])

    def test_effect_visibility_cursor_without_hit_identity_fails_locally(self) -> None:
        self.assertEqual(self.value["effectCursorProjected"], 1)
        self.assertEqual(self.value["effectCursorFailureCode"], "invalid-source")
        self.assertEqual(self.value["effectCursorOwners"], 0)

    def test_text_color_cursor_dispatches_on_its_typed_layer_identity(self) -> None:
        self.assertEqual(self.value["textCursorProjected"], 1)
        self.assertEqual(self.value["textCursorOwners"], 1)
        self.assertEqual(self.value["textCursorDispatchFailures"], 0)
        self.assertEqual(self.value["textCursorMutationX"], 68)

    def test_unhittable_cursor_is_reported_without_rejecting_vector_owner(self) -> None:
        self.assertEqual(self.value["unhitVectorOwners"], 1)
        self.assertEqual(self.value["unhitCursorExpected"], 1)
        self.assertEqual(self.value["unhitCursorFailure"], "invalid-argument")
        self.assertEqual(self.value["unhitCursorOwners"], 0)
        self.assertEqual(self.value["unhitMixedCursorFailure"], "invalid-argument")
        self.assertTrue(self.value["unhitMixedVectorValue"])

    def test_borrowed_cursor_owner_initializes_before_its_first_callback(self) -> None:
        self.assertEqual(self.value["initCursorOwners"], 1)
        self.assertTrue(self.value["initCursorBorrowed"])
        self.assertEqual(self.value["initCursorFailures"], 0)
        self.assertEqual(self.value["initCursorMutationX"], 12)

    def test_initialization_value_reaches_the_first_update(self) -> None:
        self.assertEqual(self.value["initCursorUpdateFailures"], 0)
        self.assertEqual(self.value["initCursorUpdateOriginX"], 111)
        self.assertEqual(self.value["initCursorPublishedX"], 11)

    def test_init_only_borrowed_owner_still_publishes_its_value(self) -> None:
        self.assertEqual(self.value["initOnlyOwners"], 1)
        self.assertEqual(self.value["initOnlyCursorFailures"], 0)
        self.assertEqual(self.value["initOnlyUpdateFailures"], 0)
        self.assertTrue(self.value["initOnlyPublished"])
        self.assertEqual(self.value["initOnlyPublishedX"], 11)
        # The retained value is a one-shot hand-off: with no value hook of its
        # own the owner returns to quiescence instead of re-running every frame.
        self.assertFalse(self.value["initOnlyAfterPublishPublished"])

    def test_retry_budget_charges_only_started_owners_after_early_failure(self) -> None:
        self.assertTrue(self.value["retryAggregateCommitted"])
        self.assertEqual(self.value["retryAggregateVectorExpected"], 260)
        self.assertEqual(self.value["retryAggregateVectorInstantiated"], 240)
        self.assertEqual(self.value["retryAggregateVectorRejected"], 20)

    def test_local_preflight_failure_keeps_domain_and_constructs_peer(self) -> None:
        self.assertTrue(self.value["localPreflightDomainCommitted"])
        self.assertEqual(self.value["localPreflightVectorExpected"], 2)
        self.assertEqual(self.value["localPreflightVectorInstantiated"], 1)
        self.assertEqual(self.value["localPreflightVectorRejected"], 1)
        self.assertEqual(self.value["localPreflightVectorFailureCodes"], ["invalid-source"])
        self.assertEqual(self.value["localPreflightBoundaryChecks"], 9)

    def test_oversized_owner_source_rejects_whole_candidate_before_execution(
        self,
    ) -> None:
        self.assertTrue(self.value["ownerSourceRejected"])
        self.assertEqual(self.value["ownerSourceFailureCodes"], ["budget-exceeded"])
        self.assertEqual(self.value["ownerSourceBoundaryChecks"], 1)

    def test_aggregate_source_covers_all_owner_families_before_execution(
        self,
    ) -> None:
        self.assertTrue(self.value["aggregateSourceRejected"])
        self.assertEqual(
            self.value["aggregateSourceFailureCodes"], ["budget-exceeded"]
        )
        self.assertEqual(self.value["aggregateSourceBoundaryChecks"], 1)

    def test_repeated_source_is_charged_per_actual_owner_work(self) -> None:
        self.assertTrue(self.value["repeatedSourceRejected"])
        self.assertEqual(
            self.value["repeatedSourceFailureCodes"], ["budget-exceeded"]
        )
        self.assertEqual(self.value["repeatedSourceBoundaryChecks"], 1)

    def test_shared_domain_oom_rejects_every_owner_without_retrying_polluter(
        self,
    ) -> None:
        self.assertTrue(self.value["oomPolluterCommitted"])
        self.assertTrue(self.value["oomFollowerCommitted"])
        self.assertFalse(self.value["oomCombinedCommitted"])
        self.assertEqual(self.value["oomCombinedExpected"], 2)
        self.assertEqual(self.value["oomCombinedInstantiated"], 0)
        self.assertEqual(self.value["oomCombinedFailures"], 2)
        self.assertEqual(self.value["oomCombinedFailureCodes"], ["memory-exceeded"])
        self.assertEqual(self.value["oomCombinedPassInstantiated"], 0)
        self.assertEqual(self.value["oomCombinedPassFailures"], 2)

    def test_newer_launch_cancellation_escapes_from_quickjs_execution(self) -> None:
        self.assertTrue(self.value["cancellationEscaped"])
        self.assertEqual(self.value["cancellationChecks"], 4)

    def test_media_route_is_exact_launch_state_and_cannot_revive_native(self) -> None:
        self.assertEqual(self.value["routeDefault"], "generic-only")
        self.assertEqual(self.value["routeDisable"], "disable-generic")
        self.assertEqual(self.value["routeRestore"], "generic-only")
        self.assertEqual(self.value["routePrefer"], "generic-only")
        self.assertTrue(self.value["routeInvalid"])
        self.assertTrue(self.value["routeObserveRejected"])


if __name__ == "__main__":
    unittest.main()
