import io
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

from script import repository_health as health


class RepositoryHealthTests(unittest.TestCase):
    def report(self):
        return health.summarize(
            {'App/a.swift': 401, 'App/b.swift': 1001, 'App/c.swift': 20},
            {'hardLineLimit': 1000},
            {'unmapped_paths': ['App/c.swift'], 'mappings': [{'path': 'App/c.swift', 'missing_modules': []}]},
            {'render_chain_authority_ratchet': {'rules': [
                {'id': 'old-owner', 'role': 'inventory', 'baseline_occurrences': 4, 'description': 'four declarations'},
                {'id': 'retired', 'role': 'retirement', 'baseline_occurrences': 0}]}},
            {'canonicalHelpers': [{'id': 'canonical'}]},
            {'entries': [{'path': 'script/tests/test_a.py', 'count': 2}]})

    def test_ranks_actual_hard_limits_before_mapping_and_review_signals(self):
        rows = self.report()
        self.assertEqual([r['kind'] for r in rows], ['hard-limit', 'selection-gap', 'test-shape', 'frozen-family', 'canonical-helper'])
        self.assertEqual(rows[3]['registeredBudget'], 4)
        self.assertNotIn('passed', rows[3])

    def test_missing_modules_are_explicit_even_when_path_has_mapping(self):
        rows = health.summarize({}, {'hardLineLimit': 1000},
            {'unmapped_paths': [], 'mappings': [{'path': 'App/a.swift', 'missing_modules': ['test_missing']}]},
            {'render_chain_authority_ratchet': {'rules': []}}, {}, {'entries': []})
        self.assertEqual(rows[0]['kind'], 'missing-test-module')
        self.assertEqual(rows[0]['modules'], ['test_missing'])

    def test_files_up_to_1000_lines_do_not_create_size_debt(self):
        rows = health.summarize({'a.swift': 600, 'b.swift': 1000},
            {'hardLineLimit': 1000}, {'unmapped_paths': [], 'mappings': []},
            {'render_chain_authority_ratchet': {'rules': []}}, {}, {'entries': []})
        self.assertEqual(rows, [])

    def test_exact_path_filters_and_limits_without_running_validation(self):
        value = {'signals': self.report(), 'signalCounts': {}, 'productFiles': 3,
                 'mappedProductFiles': 2, 'unmappedProductFiles': 1, 'evidenceLimit': 'inventory'}
        output = io.StringIO()
        with patch.object(health, 'collect', return_value=value), redirect_stdout(output):
            self.assertEqual(health.main(['--format', 'json', '--path', 'App/b.swift', '--limit', '1']), 0)
        import json
        report = json.loads(output.getvalue())
        self.assertEqual(report['matchedSignals'], 1)
        self.assertEqual(report['signals'][0]['path'], 'App/b.swift')


if __name__ == '__main__':
    unittest.main()
