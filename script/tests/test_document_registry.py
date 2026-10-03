from __future__ import annotations

import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.document_registry import ROOT, INDEX, managed_documents, query, validate, audit, local_targets, ROLES, REQUIRED


class DocumentRegistryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mwx-doc-registry-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        (self.root / 'docs').mkdir()
        (self.root / 'docs/a.md').write_text('# A\n')
        (self.root / 'README.md').write_text('[A](docs/a.md)\n')
        (self.root / 'script').mkdir()
        (self.root / 'script/scene_validation_gates.json').write_text(json.dumps({
            'gates': {'focused-tests': {}},
            'path_groups': [{'id': 'sample-tests', 'modules': ['test_sample']}]}))
        self.index = {
            'schemaVersion': 2,
            'roleDefinitions': {r: {'requiredMetadata': fields} for r, fields in REQUIRED.items()},
            'documents': [{'path': 'docs/a.md', 'role': 'current-state',
                           'entrypoint': 'README.md', 'purpose': 'test state'}],
            'taskRoutes': [{'id': 'sample', 'title': '示例', 'keywords': ['example'],
                            'documents': ['docs/a.md'], 'verification': 'read-only',
                            'owner': 'docs/a.md', 'firstRead': 'docs/a.md',
                            'nearestTestGroups': ['sample-tests'],
                            'verificationPhases': [{'phase': 'inner', 'gateRefs': ['focused-tests'], 'requiredArguments': ['--path']}]}],
        }

    def test_unmarked_untracked_document_is_discovered_and_rejected(self):
        self.assertEqual(validate(self.root, self.index), [])
        (self.root / 'docs/unmarked.md').write_text('# Unmarked')
        self.assertIn('unregistered Markdown: docs/unmarked.md', validate(self.root, self.index))

    def test_ignored_cache_not_loaded_but_tracked_ignored_file_still_discovered(self):
        (self.root / '.gitignore').write_text('docs/evidence/\n')
        cache = self.root / 'docs/evidence'
        cache.mkdir()
        (cache / 'ignored.md').write_bytes(b'\xff')
        self.assertEqual(managed_documents(self.root), {'docs/a.md'})
        tracked = cache / 'tracked.md'
        tracked.write_text('# tracked')
        subprocess.run(['git', 'add', '-f', 'docs/evidence/tracked.md'], cwd=self.root, check=True)
        self.assertIn('docs/evidence/tracked.md', managed_documents(self.root))

    def test_deleted_tracked_document_reports_stale_index(self):
        subprocess.run(['git', 'add', 'docs/a.md'], cwd=self.root, check=True)
        (self.root / 'docs/a.md').unlink()
        self.assertIn('indexed Markdown is missing or ignored: docs/a.md', validate(self.root, self.index))

    def test_historical_policy_and_authority_cannot_pass_standalone_check(self):
        self.index['documents'][0].update(role='historical-evidence',
            commandPolicy='execute-now', currentAuthorities=['docs/missing.md'])
        errors = validate(self.root, self.index)
        self.assertTrue(any('historical-only' in e for e in errors))
        self.assertTrue(any('authority missing' in e for e in errors))
        self.assertTrue(any('historical banner' in e for e in errors))
        for history_root in ('docs/history', 'docs/scene/history'):
            path = history_root + '/current.md'
            (self.root / path).parent.mkdir(parents=True, exist_ok=True)
            (self.root / path).write_text('# Current authority cannot live in history')
            candidate = copy.deepcopy(self.index)
            candidate['documents'].append({'path': path, 'role': 'current-state',
                'entrypoint': 'README.md', 'purpose': 'invalid history authority'})
            candidate['documents'].sort(key=lambda d: d['path'])
            self.assertIn(path + ': history cannot acquire current authority',
                          validate(self.root, candidate))

    def test_contradictory_marker_and_missing_stable_authority_fail(self):
        (self.root / 'docs/a.md').write_text('<!-- document-role: active-plan -->')
        self.index['documents'][0].update(role='stable-contract', currentStateAuthority='docs/missing.md')
        errors = validate(self.root, self.index)
        self.assertTrue(any('contradicts' in e for e in errors))
        self.assertTrue(any('authority missing' in e for e in errors))

    def test_no_backlink_and_unregistered_route_fail(self):
        (self.root / 'README.md').write_text('# no link')
        self.index['taskRoutes'][0]['documents'] = ['docs/missing.md']
        errors = validate(self.root, self.index)
        self.assertTrue(any('does not link' in e for e in errors))
        self.assertTrue(any('unregistered route document' in e for e in errors))

    def test_duplicate_paths_and_unknown_role_fail(self):
        self.index['documents'].append(copy.deepcopy(self.index['documents'][0]))
        self.index['documents'][1]['role'] = 'invented'
        errors = validate(self.root, self.index)
        self.assertTrue(any('unique' in e for e in errors))
        self.assertTrue(any('unknown role' in e for e in errors))

    def test_html_entrypoint_link_and_unicode_paths(self):
        target = self.root / 'docs/状态.md'
        target.write_text('# 状态')
        (self.root / 'docs/a.md').unlink()
        self.index['documents'][0]['path'] = 'docs/状态.md'
        self.index['taskRoutes'][0]['documents'] = ['docs/状态.md']
        self.index['taskRoutes'][0]['firstRead'] = 'docs/状态.md'
        (self.root / 'README.md').write_text('<a href="docs/%E7%8A%B6%E6%80%81.md">状态</a>')
        self.assertEqual(validate(self.root, self.index), [])

    def test_query_returns_pointers_without_loading_document_body(self):
        (self.root / 'docs/a.md').write_bytes(b'\xff')
        self.assertEqual(query(self.index, 'EXAMPLE', self.root)['routes'][0]['id'], 'sample')
        self.assertEqual(query(self.index, 'missing', self.root), {'routes': [], 'documents': [], 'designAreas': [], 'terminology': []})

    def test_design_query_uses_current_authority(self):
        (self.root / 'script/design_gated_areas.json').write_text(json.dumps({'areas': [
            {'id': 'example', 'owner': 'live-owner', 'status': 'blocked-pending-design', 'designDoc': 'docs/a.md'}]}))
        result = query(self.index, 'example', self.root)
        self.assertEqual(result['designAreas'][0]['owner'], 'live-owner')
        self.assertEqual(result['designAreas'][0]['status'], 'blocked-pending-design')

    def test_repository_registry_and_required_task_routes(self):
        index = json.loads((ROOT / INDEX).read_text())
        self.assertEqual(validate(ROOT, index), [])
        for term in ('修复 Scene 视觉缺陷', '发布新版本', '设计前置判定', 'Video', 'Web', 'Steam', '暂停'):
            with self.subTest(term=term):
                self.assertTrue(query(index, term, ROOT)['routes'])

    def test_structured_gate_and_nearest_tests_resolve_existing_authority(self):
        result = query(self.index, 'example', self.root)['routes'][0]
        self.assertEqual(result['nearestTests'], ['test_sample'])
        self.assertEqual(result['gates'], {'focused-tests': {}})
        self.index['taskRoutes'][0]['nearestTestGroups'] = ['invented']
        self.index['taskRoutes'][0]['verificationPhases'][0]['gateRefs'] = ['invented']
        errors = validate(self.root, self.index)
        self.assertTrue(any('nearest test group' in e for e in errors))
        self.assertTrue(any('unknown gate reference' in e for e in errors))

    def test_first_hop_missing_anchor_and_unrouted_contract_are_rejected(self):
        self.index['taskRoutes'][0]['firstRead'] = 'docs/a.md#missing'
        self.index['documents'][0]['role'] = 'stable-contract'
        self.index['taskRoutes'][0]['documents'] = ['docs/other.md']
        errors = validate(self.root, self.index)
        self.assertTrue(any('firstRead' in e for e in errors))
        self.index['taskRoutes'][0]['documents'] = ['docs/a.md']
        self.index['taskRoutes'][0]['firstRead'] = 'docs/a.md'
        (self.root / 'docs/a.md').write_text('# A\n' + 'detail\n' * 151)
        self.assertTrue(any('snapshot exceeds 150' in e for e in audit(self.root, self.index)['errors']))
        self.assertTrue(any('no task route' in e for e in errors))

    def test_repository_machine_acceptance_and_unique_terminology(self):
        index = json.loads((ROOT / INDEX).read_text())
        result = audit(ROOT, index)
        self.assertEqual(result['errors'], [])
        self.assertEqual(result['managedDocuments'], result['registeredDocuments'])
        self.assertEqual(result['stableContracts'], result['routedContracts'])
        self.assertTrue(all(0 < count <= 150 for count in result['firstReadLines'].values()))
        for term in ('S0-S5', 'E-*', 'named source taxonomy', 'recognized/wired', 'owned paths', '家族/防御面'):
            self.assertEqual(len(query(index, term, ROOT)['terminology']), 1, term)
        sampler = 'docs/scene/capabilities/sampler-alias-precedence.md'
        self.assertIn(sampler, query(index, 'sampler', ROOT)['routes'][0]['documents'])
        for term in ('sampler', '作者采样', 'UV', 'atlas'):
            self.assertIn('docs/scene/architecture/runtime-architecture.md',
                          query(index, term, ROOT)['routes'][0]['documents'], term)
        for entry in ('docs/README.md', 'docs/scene/README.md', 'docs/scene/capabilities/README.md'):
            self.assertIn(sampler, local_targets(ROOT, entry), entry)
        index['terminology'].pop()
        self.assertTrue(any('six unique' in e for e in validate(ROOT, index)))
        del index['routingContract']
        self.assertTrue(any('routingContract' in e for e in audit(ROOT, index)['errors']))
        index['pointerEntrypoints'] = []
        self.assertTrue(any('subtree pointer' in e for e in audit(ROOT, index)['errors']))

    def test_execution_arguments_and_frequency_sample_are_not_free_text(self):
        index = json.loads((ROOT / INDEX).read_text())
        route = next(r for r in index['taskRoutes'] if r['id'] == 'scene-visual')
        route['verificationPhases'][2]['requiredArguments'].remove('--app')
        index['taskFrequencyEvidence']['sampleCount'] += 1
        errors = validate(ROOT, index)
        self.assertTrue(any('execution identity' in e for e in errors))
        self.assertTrue(any('frozen Git sample' in e for e in errors))

    def test_subtree_agents_rejects_new_rule_and_long_pointer_document(self):
        path = 'docs/AGENTS.md'
        (self.root / path).write_text('# Scene\n- [root](../AGENTS.md)\nDo a new thing.\n')
        (self.root / 'AGENTS.md').write_text('# Root')
        self.index['pointerEntrypoints'] = [{'path': path, 'authority': 'AGENTS.md', 'maxLines': 10}]
        errors = validate(self.root, self.index, discovered={'docs/a.md'})
        self.assertTrue(any('only a title and link pointers' in e for e in errors))
        (self.root / path).write_text('# Scene\n' + '- [root](../AGENTS.md)\n' * 10)
        self.assertTrue(any('10 lines' in e for e in validate(self.root, self.index, discovered={'docs/a.md'})))

    def test_navigation_anchors_are_real_and_precede_batch_logs(self):
        from script.tests.test_scene_semantics_coverage import markdown_anchors
        expected = {
            'docs/scene/capabilities/README.md': ['reading-layers'],
            'docs/scene/capabilities/coverage-ledger.md': ['current-overview', 'capability-tables', 'batch-records'],
            'docs/scene/capabilities/runtime-evidence-current.md': ['current-snapshot', 'evidence-levels', 'evidence-packages'],
        }
        for path, anchors in expected.items():
            text = (ROOT / path).read_text()
            self.assertTrue(set(anchors) <= markdown_anchors(text), path)
            offsets = [text.index(f'<a id="{anchor}"') for anchor in anchors]
            self.assertEqual(offsets, sorted(offsets))
            self.assertLess(len(text[:offsets[0]].splitlines()), 30)


if __name__ == '__main__':
    unittest.main()
