import json
import subprocess
import unittest

from script.tests.scene_harness_io import DIAGNOSTIC_PREFIXES, separate_graph_debug_output


class GraphHarnessIOTests(unittest.TestCase):
    def result(self, stdout: str, code: int = 0) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(["fixture"], code, stdout, "original stderr")

    def test_exact_json_and_process_identity_survive(self) -> None:
        original = self.result('{"results":{"actualPixel":true},"count":7}')
        result = separate_graph_debug_output(original)
        self.assertEqual(json.loads(result.stdout), json.loads(original.stdout))
        self.assertEqual((result.args, result.returncode, result.stderr),
                         (original.args, 0, "original stderr"))

    def test_all_known_diagnostics_are_retained_before_or_after_json(self) -> None:
        for prefix in DIAGNOSTIC_PREFIXES:
            for text in (f'{prefix} reason=expected\n{{"value":false}}',
                         f'{{"value":false}}{prefix} reason=expected\n'):
                with self.subTest(text=text):
                    result = separate_graph_debug_output(self.result(text))
                    self.assertEqual(json.loads(result.stdout), {"value": False})
                    self.assertEqual(result.stderr, f"original stderr\n{prefix} reason=expected")

    def test_extra_packet_unknown_output_and_incomplete_packet_fail(self) -> None:
        for text in ('{}{}', '{}unexpected failure', 'unexpected output\n{}',
                     '{"incomplete":', '[]', DIAGNOSTIC_PREFIXES[0] + ' no packet'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                separate_graph_debug_output(self.result(text))

    def test_process_failure_preserves_full_original_output(self) -> None:
        original = self.result("crash or compiler failure", code=1)
        self.assertIs(separate_graph_debug_output(original), original)
