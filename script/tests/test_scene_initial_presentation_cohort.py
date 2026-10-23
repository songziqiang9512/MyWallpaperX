#!/usr/bin/env python3
"""Executable input/output checks for the real Session cohort value, without GPU/App."""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
VALUE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneInitialPresentationCohort.swift"
HARNESS = ROOT / "script/tests/fixtures/SceneInitialPresentationCohortHarness.swift"


class InitialPresentationCohortTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-initial-presentation-cohort-") as temporary:
            binary = Path(temporary) / "cohort-checks"
            subprocess.run([
                "swiftc", "-parse-as-library", "-swift-version", "6",
                "-default-isolation", "MainActor", "-strict-concurrency=complete",
                str(VALUE), str(HARNESS), "-o", str(binary),
            ], check=True, capture_output=True, text=True)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
            cls.results = json.loads(result.stdout)

    def test_exact_cohort_delivers_once_and_stays_held_for_host(self):
        self.assertEqual(self.results["sameAttempt"], {
            "held": True, "partialDelivered": False, "duplicateDelivered": False,
            "delivery": [2, 9], "redelivered": False, "heldAfterDelivery": True,
            "newAttemptBlocked": True, "heldAfterBlockedAttempt": True,
        })

    def test_partial_unqualified_empty_extra_and_replaced_submissions_do_not_hold(self):
        self.assertEqual(self.results["invalidSubmissions"], {
            "missing": False, "none": False, "replacement": False,
            "extra": False, "wrongIDs": False, "empty": False,
        })

    def test_paused_attempt_tokens_do_not_accumulate_sticky_surface_success(self):
        self.assertEqual(self.results["noCrossAttemptUnion"], {
            "oldHeld": False, "newerHeld": False, "crossedDelivered": False,
            "currentHeld": True, "staleADelivered": False, "staleBDelivered": False,
            "currentBOnlyDelivered": False, "delivery": [2, 9], "tokensIncrease": True,
        })

    def test_early_gpu_success_waits_for_actual_submission_seal(self):
        self.assertEqual(self.results["completionBeforeSeal"], {
            "earlyADelivered": False, "earlyBDelivered": False, "beforeSealDelivered": False,
            "held": True, "delivery": [2, 9], "redelivered": False, "stillHeld": True,
        })

    def test_surface_ids_do_not_substitute_for_surface_objects(self):
        self.assertEqual(self.results["surfaceReplacement"], {
            "held": True, "wrongObjectDelivered": False, "staleOldDelivered": False,
            "unknownScreenDelivered": False, "replacementOnlyDelivered": False,
            "delivery": [2, 9],
        })

    def test_invalidation_stop_and_promotion_release_without_token_reuse(self):
        self.assertEqual(self.results["releaseAndReset"], {
            "heldAfterInvalidate": False, "staleAfterInvalidateDelivered": False,
            "delivery": [2, 9], "heldAfterDelivery": True, "heldAfterReset": False,
            "staleAfterResetDelivered": False, "tokensIncrease": True, "nextDelivery": [2],
        })

    def test_stale_or_repeated_finish_does_not_revoke_current_held_output(self):
        self.assertEqual(self.results["staleAndRepeatedSeal"], {
            "staleSealHeld": False, "held": True,
            "repeatedSealPreservedHold": True, "delivery": [2, 9],
        })

    def test_delivered_phase_clears_on_invalidation_and_cannot_be_restored_by_stale_success(self):
        self.assertEqual(self.results["deliveredPhase"], {
            "phases": [False, False, False, False, True, False, False, True, False],
            "staleDelivered": False, "heldAfterReset": False,
        })


if __name__ == "__main__":
    unittest.main()
