"""Real Metal regressions for the existing particle pipeline's upload ownership."""
from __future__ import annotations

import unittest
from pathlib import Path

from script.tests.scene_particle_render_test_support import run_particle_harness
from script.tests.test_scene_particle_rendering import HARNESS_SUPPORT_SOURCE, SWIFT_SOURCES


FIXTURE = Path(__file__).parent / "fixtures/SceneParticleUploadOwnershipHarness.swift"
SOURCES = tuple(path for path in SWIFT_SOURCES if path.name not in {
    "SceneParticleFixedGeometryHarness.swift", "SceneParticleCameraRenderingHarness.swift",
})
# Reuse the existing transport declarations; this cut executes neither the old
# @main nor its unrelated camera/geometry probes.
PREAMBLE = HARNESS_SUPPORT_SOURCE


class SceneParticleUploadOwnershipTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.result = run_particle_harness(SOURCES, PREAMBLE + FIXTURE.read_text(encoding="utf-8"))

    def test_layer_root_and_child_template_keys_preserve_separate_gpu_draws(self) -> None:
        self.assertEqual(len(self.result["keys"]), 2)
        for variant, row in enumerate(self.result["keys"]):
            with self.subTest(variant=variant):
                self.assertEqual(row["preparedCount"], 4)
                self.assertEqual(row["bufferOwnerCount"], 4)
                self.assertEqual(row["nativeBufferCount"], 4)
                self.assertEqual(row["childTemplateIndices"], [-1, 0, 1, 0])
                self.assertEqual(row["pixelsRGBA"], [
                    [255, 0, 0, 255], [0, 255, 0, 255],
                    [0, 0, 255, 255], [255, 255, 0, 255],
                ])

    def test_two_pipeline_instances_do_not_share_the_same_batch_key(self) -> None:
        row = self.result["pipelines"]
        self.assertTrue(row["differentBufferOwners"])
        self.assertTrue(row["differentNativeBuffers"])
        self.assertEqual(row["firstPixelRGBA"], [255, 0, 0, 255])
        self.assertEqual(row["secondPixelRGBA"], [0, 255, 0, 255])

    def test_absent_batch_reappears_with_the_same_completed_buffer(self) -> None:
        row = self.result["reappearance"]
        self.assertEqual(row["absentPreparedCount"], 0)
        self.assertTrue(row["sameBufferOwner"])
        self.assertTrue(row["sameNativeBuffer"])
        self.assertEqual(row["firstPixelRGBA"], [255, 0, 0, 255])
        self.assertEqual(row["nextPixelRGBA"], [0, 255, 0, 255])

    def test_enqueued_draw_survives_cancel_and_reuses_only_after_completion(self) -> None:
        row = self.result["inFlight"]
        for fact in ("sameBufferOwner", "enqueuedCancelKeepsReservation",
                     "oldUploadedValuePreserved", "firstSlotReusedAfterCompletion"):
            with self.subTest(fact=fact):
                self.assertTrue(row[fact])
        self.assertEqual(row["firstPixelRGBA"], [255, 0, 0, 255])
        self.assertEqual(row["secondPixelRGBA"], [0, 255, 0, 255])
        self.assertEqual(row["thirdPixelRGBA"], [0, 0, 255, 255])

    def test_pipeline_cancel_reclaims_only_not_enqueued_candidates(self) -> None:
        row = self.result["cancellation"]
        for fact in ("pendingCleared", "pendingSlotReused", "reservedCleared",
                     "reservedSlotReused", "cancelledCommandsRemainNotEnqueued"):
            with self.subTest(fact=fact):
                self.assertTrue(row[fact])
        self.assertEqual(row["finalPixelRGBA"], [0, 255, 0, 255])

    def test_bad_instances_are_filtered_locally_without_losing_order_or_peer(self) -> None:
        row = self.result["finiteInstances"]
        self.assertEqual(row["preparedLayerIDs"], [701, 702])
        self.assertEqual(row["uploadedCounts"], [2, 1])
        self.assertEqual(row["uploadedPositions"], [-0.5, 0.5])
        self.assertEqual(row["sourceCountsUnchanged"], [3, 1, 0, 1])
        self.assertEqual(row["pixelsRGBA"], [
            [255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255],
        ])


if __name__ == "__main__":
    unittest.main()
