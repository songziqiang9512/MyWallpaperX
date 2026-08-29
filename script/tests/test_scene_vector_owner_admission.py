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

    def test_source_budget_accepts_exact_per_owner_and_aggregate_boundaries(
        self,
    ) -> None:
        self.assertTrue(self.value["exactSourceBoundaryCommitted"])

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
