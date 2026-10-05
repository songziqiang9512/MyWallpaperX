#!/usr/bin/env python3
"""Graph allocation recovery against the real cache and allocator owners.

Requires macOS/Metal for native texture allocation. The harness never submits a
command buffer; native quota-pressure and rendered-output evidence are separate.
"""

from __future__ import annotations

import unittest
from pathlib import Path

from script.tests import test_scene_offscreen_texture_pool as pool_support
from script.tests.test_scene_directional_shadow import run_swift


FIXTURE = Path(__file__).with_name("fixtures") / "scene_graph_allocation_recovery.swift"


class SceneGraphAllocationRecoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        support, marker, _ = pool_support.HARNESS.partition("@main")
        if not marker:
            raise AssertionError("offscreen pool harness no longer exposes pre-main support")
        cls.result = run_swift(
            pool_support.SWIFT_SOURCES,
            support + FIXTURE.read_text(encoding="utf-8"),
            label="graph-allocation-recovery",
        )

    def test_shared_pair_and_graph_have_one_recovery_for_the_whole_batch(self) -> None:
        self.assertTrue(self.result["sharedPairRecovered"])
        self.assertTrue(self.result["sharedPairPrefixAllocatedOnce"])
        self.assertTrue(self.result["graphSecondFailureNotRetried"])
        self.assertTrue(self.result["secondIdleVictimNotReclaimed"])
        self.assertTrue(self.result["failedGraphNotPublished"])

    def test_successful_prefix_survives_later_graph_factory_retry(self) -> None:
        self.assertTrue(self.result["laterGraphRecovered"])
        self.assertTrue(self.result["prefixFactoriesNotRepeated"])
        self.assertTrue(self.result["prefixTextureIdentitiesPreserved"])
        self.assertTrue(self.result["prepareDidNotPublishGraphs"])
        self.assertTrue(self.result["recoveredBatchCommittedAtomically"])

    def test_retired_reusable_generation_survives_recovery_before_commit(self) -> None:
        self.assertTrue(self.result["reservationSelectedRetiredReusable"])
        self.assertTrue(self.result["retiredGenerationSurvivedReclaim"])
        self.assertTrue(self.result["reusableTexturesNotAllocatedAgain"])
        self.assertTrue(self.result["reusablePhysicalTexturesPreserved"])
        self.assertTrue(self.result["reusableBatchCommitted"])
        self.assertTrue(self.result["retiredGenerationConsumedOnlyAtCommit"])

    def test_external_revision_change_is_not_absorbed_as_recovery(self) -> None:
        self.assertTrue(self.result["externalRevisionAbort"])
        self.assertTrue(self.result["externalRevisionNoRetry"])
        self.assertTrue(self.result["externalRevisionKeptIdleVictim"])
        self.assertTrue(self.result["externalRevisionNoGraphPublication"])

    def test_cached_targets_survive_completion_without_allocation_or_identity_drift(self) -> None:
        for row in self.result["cachedCompletion"]:
            for key, value in row.items():
                with self.subTest(key=key, row=row):
                    self.assertTrue(value)

    def test_pool_entry_recovers_under_measured_native_quota_pressure(self) -> None:
        rows = self.result["poolEntryPressure"]
        self.assertEqual([row["shared"] for row in rows], [False, True])
        for row in rows:
            with self.subTest(shared=row["shared"]):
                for key in ["prepared", "committed", "graphPublished", "sharedPairPresent",
                            "idleActuallyReleased", "idleCacheEntryRemoved", "protectedResidentSurvived"]:
                    self.assertTrue(row[key], row)
                self.assertGreater(row["coldNativeCharge"], row["idleNativeCharge"])
                self.assertGreater(row["idleNativeCharge"], 0)
                self.assertGreater(row["protectedNativeCharge"], 0)
                self.assertEqual(row["nativeQuotaRejections"], 1)
                self.assertEqual(row["warmNativeCharge"], row["coldNativeCharge"])
                self.assertEqual(row["availableBeforePrepare"],
                                 row["coldNativeCharge"] - row["idleNativeCharge"])
                self.assertEqual(row["accountAfterResetWithGuard"],
                                 row["baselineAccountBytes"] + row["reservedQuotaBytes"])
                self.assertEqual(row["accountAfterGuardRelease"], row["baselineAccountBytes"])
                self.assertEqual(row["finalAccountBytes"], row["originalAccountBytes"])


if __name__ == "__main__":
    unittest.main()
