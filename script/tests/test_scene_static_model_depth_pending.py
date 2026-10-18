"""Actual model frame-depth/pool/draw pending pressure and typed failure facts.

The prepared-input shell is the nearest frame-owner gate. This is not App
admission: the fixture cancels after observing the real frame-owner decision.
Root's frozen App gate owns final FrameOutcome/host propagation validation.
"""
from pathlib import Path
import unittest

from script.tests import test_scene_directional_shadow_frame_owner as frame

MAIN = (Path(__file__).with_name('fixtures') / 'SceneStaticModelDepthPendingChecks.swift').read_text()


class SceneStaticModelDepthPendingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # These inputs declare no named/graph provider. The real ordered
        # model-depth walk may inspect those facts before its capacity exit.
        ordered_support = frame.UNUSED_ORDERED_SUPPORT.replace(
            '->Bool { fatalError("unused RF13 ordered preparation shell") }',
            '->Bool { false }')
        report = frame.shadow_fixture.run_swift(
            frame.SOURCES,
            frame.pool_fixture.HARNESS.split('@main', 1)[0]
            + frame.SHELL + ordered_support + MAIN,
            label='model-depth-pending',
            metal_sources=[frame.SCENE / 'Rendering/Composition/SceneStaticModel.metal'])
        cls.cases = {row['prepared']: row for row in report['cases']}

    def test_pending_model_depth_defers_and_recovers_without_partial_submission(self):
        report = self.cases[False]
        self.assertTrue(report['passed'], report)
        self.assertEqual(report['rows'][1]['deferral'], 'static-model-depth-in-flight')
        self.assertEqual(report['rows'][1]['centerRGBA'], [17, 17, 17, 17])
        self.assertTrue(all(report['checks'].values()), report)

    def test_mandatory_preparation_preserves_same_busy_decision(self):
        report = self.cases[True]
        self.assertTrue(report['passed'], report)
        self.assertEqual(report['rows'][1]['encodedLayerIDs'], [])
        self.assertEqual(report['rows'][1]['centerRGBA'], [17, 17, 17, 17])

    def test_terminal_shared_depth_binding_has_one_frame_lifetime(self):
        for report in self.cases.values():
            checks = {key: value for key, value in report['checks'].items()
                      if key.startswith('terminal-')}
            self.assertGreaterEqual(len(checks), 9)
            self.assertTrue(all(checks.values()), checks)

    def test_optional_source_depth_failure_is_qualified_before_graph_candidate(self):
        for report in self.cases.values():
            checks = {key: value for key, value in report['checks'].items()
                      if key.startswith('source-')}
            self.assertGreaterEqual(len(checks), 8)
            self.assertTrue(all(checks.values()), checks)


if __name__ == '__main__':
    unittest.main()
