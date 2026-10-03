#!/usr/bin/env python3
"""Real native quota recovery and existing pool transaction boundaries."""
from pathlib import Path
import unittest

from script.tests import test_scene_offscreen_texture_pool as pool_fixture
from script.tests.test_scene_directional_shadow import run_swift

FIXTURE = Path(__file__).with_name('fixtures') / 'SceneAllocationRecoveryHarness.swift'


class SceneAllocationRecoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = run_swift(pool_fixture.SWIFT_SOURCES,
            pool_fixture.HARNESS.split('@main', 1)[0] + FIXTURE.read_text(),
            label='allocation-recovery')

    def test_real_native_quota_recovers_all_non_graph_callers(self):
        self.assertEqual(len(self.report['pressure']), 28)
        for row in self.report['pressure']:
            with self.subTest(row=row):
                self.assertTrue(row['success'])
                self.assertTrue(row['oldReleased'])
                self.assertGreater(row['oldCharge'], 0)
                self.assertEqual(row['calls'], row['expectedCalls'])
                self.assertEqual(row['rejections'], 1)
                self.assertEqual(row['resident'], row['nativeCharge'])
                self.assertEqual(row['finalBytes'], 0)

    def test_external_reference_retains_real_quota_after_cache_reclamation(self):
        row = self.report['external']
        for key in ['failed', 'cacheEmpty', 'retained', 'released', 'retry']:
            self.assertTrue(row[key], row)
        self.assertEqual(row['calls'], 2)
        self.assertEqual(row['finalBytes'], 0)

    def test_failed_later_member_does_not_restart_prefix_or_recover_twice(self):
        row = self.report['failure']
        for key in ['failed', 'empty', 'prefixReleased', 'retryReleased', 'victimReleased']:
            self.assertTrue(row[key], row)
        self.assertEqual(row['calls'], 4)
        self.assertEqual(row['quotaRejections'], 0)
        self.assertEqual(row['finalBytes'], 0)

    def test_external_reset_is_not_adopted_as_the_batch_revision(self):
        for row in self.report['races']:
            with self.subTest(row=row):
                self.assertTrue(row['failed'])
                self.assertTrue(row['empty'])
                self.assertEqual(row['calls'], row['expectedCalls'])
                self.assertEqual(row['finalBytes'], 0)

    def test_no_victim_does_not_retry(self):
        row = self.report['noVictim']
        self.assertTrue(row['failed'])
        self.assertTrue(row['empty'])
        self.assertEqual(row['calls'], 1)

    def test_scene_color_retention_is_not_rebuildable_idle_storage(self):
        row = self.report['retention']
        for key in ['failed', 'retained', 'retry']:
            self.assertTrue(row[key], row)
        self.assertEqual(row['calls'], 1)
        self.assertEqual(row['finalBytes'], 0)

    def test_actual_blocked_gpu_submission_is_protected_until_completion(self):
        row = self.report['inFlight']
        for key in ['failed', 'blocked', 'completed', 'retry']:
            self.assertTrue(row[key], row)
        self.assertEqual(row['calls'], 1)
        self.assertEqual(row['finalBytes'], 0)


if __name__ == '__main__':
    unittest.main()
