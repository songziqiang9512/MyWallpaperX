#!/usr/bin/env python3
"""CPU behavior of accepted property intent while actual Session resources wait.

The Session extension and property validation execute unchanged. Controlled
resource and surface seams supply readiness/adoption events without Metal.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SESSION = SCENE / "Runtime/Session/SceneDesktopWallpaperSession.swift"
LIVE_CONSUMERS = SCENE / "Runtime/Session/SceneDesktopWallpaperSession+LiveConsumers.swift"
PROPERTY_SOURCES = [
    SCENE / "Format/SceneJSONValue.swift",
    SCENE / "Systems/Properties/SceneUserProperty.swift",
    SCENE / "Systems/Properties/SceneScriptDynamicProviderHostContract.swift",
    SCENE / "Systems/Properties/SceneUserPropertyBindings.swift",
    SCENE / "Systems/Properties/SceneDynamicSnapshot.swift",
    SCENE / "Systems/Properties/ScenePuppetAnimationPropertyTarget.swift",
    SCENE / "Systems/Properties/ScenePropertyBindingProgram.swift",
    SCENE / "Systems/Properties/ScenePropertyBindingCompiler+TargetMapping.swift",
    SCENE / "Systems/Properties/ScenePropertyBindingProgramValidator.swift",
    SCENE / "Systems/Properties/ScenePropertyLiveUpdateState.swift",
]


def declaration(source: str, signature: str) -> str:
    """Extract an unchanged production declaration for a bounded CPU shell."""
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for index in range(opening, len(source)):
        depth += (source[index] == "{") - (source[index] == "}")
        if depth == 0:
            return source[start:index + 1]
    raise ValueError(f"unterminated production declaration: {signature}")


SHELL = (ROOT / "script/tests/fixtures/SceneDeferredPropertyIntentSupport.swift").read_text(encoding="utf-8")

HARNESS = (ROOT / "script/tests/fixtures/SceneDeferredPropertyIntentHarness.swift").read_text(encoding="utf-8")


class SceneDeferredPropertyIntentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-deferred-property-intent-")
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        directory = Path(cls.temporary_directory.name)
        session = SESSION.read_text(encoding="utf-8")
        owner_source = Path(os.environ.get(
            "MWX_SCENE_DEFERRED_PROPERTY_OWNER_SOURCE", str(LIVE_CONSUMERS)))
        extension = owner_source.read_text(encoding="utf-8")
        pending = declaration(session, "struct PendingDeferredLayerVisibilityUpdate {")
        shell = directory / "SessionShell.swift"
        shell.write_text(SHELL.replace("// PRODUCT_PENDING_DECLARATION", pending), encoding="utf-8")
        # The pre-fix owner may still contain apply. This assembles that exact
        # method without copying its algorithm into the test's fixture.
        if "func applyUserPropertyValues(" not in extension:
            extension += "\nextension SceneDesktopWallpaperSession {\n"
            extension += declaration(session, "func applyUserPropertyValues(")
            extension += "\n}\n"
        owner = directory / "SessionLiveConsumers.swift"
        owner.write_text(extension, encoding="utf-8")
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "deferred-property-intent"
        compilation = subprocess.run(
            ["swiftc", *(str(path) for path in PROPERTY_SOURCES),
             str(shell), str(owner), str(harness), "-module-cache-path",
             str(directory / "module-cache"), "-o", str(binary)],
            capture_output=True, text=True, timeout=120,
        )
        if compilation.returncode:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True, timeout=30,
        )
        cls.result = json.loads(completed.stdout)

    def assert_committed(self, value: dict, visible: list[bool], layers: list[int]) -> None:
        self.assertEqual(value["visible"], visible)
        self.assertIsNone(value["pending"])
        self.assertEqual(len(value["views"]), 2)
        for view in value["views"]:
            self.assertEqual(view["committed"], layers)
            self.assertEqual(view["staged"], [])

    def test_independent_accepted_commands_both_commit(self) -> None:
        result = self.result["independent"]
        self.assertEqual(result["accepted"], [True, True])
        self.assertEqual(result["waiting"]["visible"], [False, False])
        self.assertEqual(result["waiting"]["pending"]["layers"], [11, 22])
        requests = result["waiting"]["requests"]
        newest = max(generation for _, generation in requests)
        self.assertEqual(sorted(layer for layer, generation in requests if generation == newest), [11, 22])
        self.assert_committed(result["final"], [True, True], [11, 22])

    def test_partial_bulk_cancellation_keeps_the_other_accepted_key(self) -> None:
        result = self.result["partialCancellation"]
        self.assertEqual(result["accepted"], [True, True])
        self.assertEqual(result["waiting"]["visible"], [False, False])
        self.assertEqual(result["waiting"]["pending"]["layers"], [22])
        self.assert_committed(result["final"], [False, True], [22])

    def test_same_key_latest_hide_cancels_show(self) -> None:
        result = self.result["sameKeyCancellation"]
        self.assertEqual(result["accepted"], [True, True])
        self.assertEqual(result["waiting"]["revision"], 0)
        self.assertEqual(result["waiting"]["visible"], [False, False])
        self.assertIsNotNone(result["waiting"]["pending"])
        self.assertEqual(result["final"]["revision"], 0)
        self.assert_committed(result["final"], [False, False], [])
        self.assertTrue(all(view["attempts"] == 0 for view in result["final"]["views"]))

    def test_invalid_update_does_not_erase_accepted_pending_intent(self) -> None:
        result = self.result["invalidUpdate"]
        self.assertEqual(result["accepted"], [True, False])
        self.assertEqual(result["after"], result["before"])
        self.assert_committed(result["final"], [True, False], [11])

    def test_latest_removal_survives_pending_merge(self) -> None:
        result = self.result["removal"]
        self.assertEqual(result["accepted"], [True, True])
        self.assertIsNone(result["final"]["optional"])
        self.assert_committed(result["final"], [True, False], [11])

    def test_every_resource_and_a_surface_are_required_before_publication(self) -> None:
        result = self.result["readiness"]
        self.assertTrue(result["accepted"])
        self.assertEqual(result["oneReady"]["visible"], [False, False])
        self.assertIsNotNone(result["oneReady"]["pending"])
        self.assertTrue(all(view["attempts"] == 0 for view in result["oneReady"]["views"]))
        self.assertEqual(result["noSurface"]["visible"], [False, False])
        self.assertIsNotNone(result["noSurface"]["pending"])
        self.assertEqual(result["noSurface"]["views"], [])
        self.assert_committed(result["final"], [True, True], [11, 22])

    def test_partial_surface_adoption_rolls_back_and_retry_commits_all(self) -> None:
        result = self.result["adoptionRollback"]
        self.assertTrue(result["accepted"])
        before = result["rolledBack"]
        self.assertEqual(before["visible"], [False, False])
        self.assertIsNotNone(before["pending"])
        self.assertEqual(before["soundApplies"], 0)
        self.assertEqual(sum(view["attempts"] for view in before["views"]), 2)
        for view in before["views"]:
            self.assertEqual(view["staged"], [])
            self.assertEqual(view["committed"], [])
            self.assertEqual(view["discards"], 1)
        self.assert_committed(result["final"], [True, False], [11])
        self.assertEqual(result["final"]["soundApplies"], 1)

    def test_late_validation_failure_releases_adoptions_without_publication(self) -> None:
        result = self.result["validationRollback"]
        self.assertTrue(result["accepted"])
        self.assert_committed(result["final"], [False, False], [])
        self.assertEqual(result["final"]["soundApplies"], 0)
        self.assertTrue(all(view["discards"] == 1 for view in result["final"]["views"]))

    def test_failed_resource_preserves_previous_display(self) -> None:
        result = self.result["resourceFailure"]
        self.assertTrue(result["accepted"])
        self.assert_committed(result["final"], [False, False], [])
        self.assertTrue(all(view["attempts"] == 0 for view in result["final"]["views"]))

    def test_disjoint_value_update_survives_later_visibility_commit(self) -> None:
        result = self.result["disjointValue"]
        self.assertEqual(result["accepted"], [True, True])
        self.assertEqual(result["final"]["level"], 0.7)
        self.assert_committed(result["final"], [True, False], [11])

    def test_independent_ready_value_survives_other_resource_failure(self) -> None:
        result = self.result["disjointFailure"]
        self.assertEqual(result["accepted"], [True, True])
        self.assertEqual(result["waiting"]["visible"], [False, False])
        self.assertEqual(result["waiting"]["level"], 0.7)
        self.assertEqual(result["final"]["level"], 0.7)
        self.assert_committed(result["final"], [False, False], [])

    def test_prepared_particle_and_image_cohort_commit_together(self) -> None:
        result = self.result["preparedParticleCohort"]
        self.assertTrue(result["accepted"])
        self.assert_committed(result["final"], [True, False], [11])
        self.assertTrue(result["final"]["particleVisible"])
        self.assertEqual(result["final"]["revision"], 1)
        self.assertEqual(result["final"]["soundApplies"], 1)

    def test_every_current_surface_must_have_particle_resources_before_accepting_the_key(self) -> None:
        for fault in ("missing-surface-resource", "generation", "surface-set"):
            with self.subTest(fault=fault):
                result = self.result[f"particleAdmission-{fault}"]
                self.assertFalse(result["accepted"])
                self.assertEqual(result["final"], result["before"])
                self.assert_committed(result["final"], [False, False], [])
                self.assertFalse(result["final"]["particleVisible"])
                self.assertEqual(result["final"]["requests"], [])
                self.assertEqual(result["final"]["revision"], 0)
                self.assertEqual(result["final"]["soundApplies"], 0)

    def test_pending_image_particle_cohort_rechecks_resources_at_final_promotion(self) -> None:
        for fault in ("missing-surface-resource", "generation"):
            with self.subTest(fault=fault):
                result = self.result[f"particlePromotion-{fault}"]
                self.assertTrue(result["accepted"])
                self.assertEqual(result["waiting"]["pending"]["layers"], [11])
                self.assertFalse(result["waiting"]["particleVisible"])
                self.assert_committed(result["final"], [False, False], [])
                self.assertFalse(result["final"]["particleVisible"])
                self.assertEqual(result["final"]["revision"], 0)
                self.assertEqual(result["final"]["soundApplies"], 0)
                for view in result["final"]["views"]:
                    self.assertEqual(view["attempts"], 1)
                    self.assertEqual(view["discards"], 1)

    def test_parent_and_two_particle_leaves_commit_with_the_merged_image_keys(self) -> None:
        result = self.result["preparedParentParticleCohort"]
        self.assertEqual(result["accepted"], [True, True])
        self.assertEqual(result["waiting"]["pending"]["keys"], ["A", "B"])
        self.assertEqual(result["waiting"]["pending"]["layers"], [11, 22])
        self.assertFalse(result["waiting"]["particleParentVisible"])
        self.assert_committed(result["final"], [True, True], [11, 22])
        self.assertTrue(result["final"]["particleParentVisible"])
        self.assertEqual(result["final"]["revision"], 1)
        self.assertEqual(result["final"]["soundApplies"], 1)

    def test_parent_key_requires_every_particle_on_every_current_surface_even_for_false(self) -> None:
        for fault in ("missing-first-leaf", "missing-second-leaf", "generation", "surface-set", "no-surfaces"):
            for incoming in ("off", "on"):
                with self.subTest(fault=fault, incoming=incoming):
                    result = self.result[f"parentAdmission-{fault}-{incoming}"]
                    self.assertFalse(result["accepted"])
                    self.assertEqual(result["final"], result["before"])
                    self.assertFalse(result["final"]["particleParentVisible"])
                    self.assertEqual(result["final"]["visible"], [False, False])
                    self.assertIsNone(result["final"]["pending"])
                    self.assertEqual(result["final"]["requests"], [])
                    self.assertEqual(result["final"]["revision"], 0)
                    self.assertEqual(result["final"]["soundApplies"], 0)

    def test_pending_parent_key_rechecks_particle_requirements_before_merging_another_key(self) -> None:
        for fault in ("missing-second-leaf", "generation"):
            with self.subTest(fault=fault):
                result = self.result[f"parentMerge-{fault}"]
                self.assertEqual(result["accepted"], [True, False])
                self.assertEqual(result["after"], result["before"])
                self.assertEqual(result["after"]["pending"]["keys"], ["A"])
                self.assert_committed(result["final"], [False, False], [])
                self.assertFalse(result["final"]["particleParentVisible"])
                self.assertEqual(result["final"]["revision"], 0)
                self.assertEqual(result["final"]["soundApplies"], 0)

    def test_merged_parent_key_rechecks_all_particle_leaves_at_final_promotion(self) -> None:
        for fault in ("missing-second-leaf", "generation"):
            with self.subTest(fault=fault):
                result = self.result[f"parentPromotion-{fault}"]
                self.assertEqual(result["accepted"], [True, True])
                self.assertEqual(result["waiting"]["pending"]["keys"], ["A", "B"])
                self.assert_committed(result["final"], [False, False], [])
                self.assertFalse(result["final"]["particleParentVisible"])
                self.assertEqual(result["final"]["revision"], 0)
                self.assertEqual(result["final"]["soundApplies"], 0)
                for view in result["final"]["views"]:
                    self.assertEqual(view["attempts"], 2)
                    self.assertEqual(view["discards"], 1)

    def test_scalar_change_and_same_value_resend_do_not_request_visibility_resources(self) -> None:
        result = self.result["scalarWithoutVisibility"]
        self.assertEqual(result["accepted"], [True, True])
        self.assertEqual(result["final"]["level"], 0.7)
        self.assertEqual(result["final"]["revision"], 1)
        self.assertEqual(result["final"]["requests"], [])
        self.assert_committed(result["final"], [False, False], [])

    def test_sound_rejection_preserves_current_at_admission_and_promotion(self) -> None:
        admission = self.result["soundAdmission"]
        self.assertFalse(admission["accepted"])
        self.assertEqual(admission["before"], admission["final"])
        promotion = self.result["soundPromotion"]
        self.assertTrue(promotion["accepted"])
        self.assert_committed(promotion["final"], [False, False], [])
        self.assertEqual(promotion["final"]["revision"], 0)
        self.assertEqual(promotion["final"]["soundApplies"], 0)
        self.assertTrue(all(view["discards"] == 1 for view in promotion["final"]["views"]))

    def test_wrong_record_does_not_cancel_current_pending_intent(self) -> None:
        result = self.result["wrongRecord"]
        self.assertEqual(result["accepted"], [True, False])
        self.assertEqual(result["before"], result["after"])
        self.assert_committed(result["final"], [True, False], [11])

    def test_renamed_combo_cohort_selects_only_layer_resources_and_preserves_neighbor(self) -> None:
        for name in ("choice", "renamed_mode"):
            with self.subTest(name=name):
                result = self.result[f"variant-{name}"]
                self.assertEqual(result["accepted"], [True, False, False, True, True, False])
                self.assertEqual(result["neighborRequests"], 0)
                self.assertEqual(result["invalidRequests"], 0)
                self.assertEqual(result["pendingLayers"], result["expectedLayers"])
                self.assertEqual(result["requestedLayers"], result["expectedLayers"])
                self.assertEqual(result["visible"], [True, True, True])
                self.assertEqual(result["retainedVisible"], [True, True, True])
                self.assertEqual(result["revision"], 2)
                self.assertEqual(result["retainedRevision"], 2)
                self.assertTrue(result["scalar"])
                self.assertTrue(result["pendingCleared"])
                for view in result["views"]:
                    self.assertEqual(view["staged"], [])
                    self.assertEqual(view["committed"], result["expectedLayers"])


if __name__ == "__main__":
    unittest.main()
