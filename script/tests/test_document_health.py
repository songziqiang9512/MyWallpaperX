from __future__ import annotations

import copy
from datetime import date
import hashlib
import io
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch
import json
from pathlib import Path
import tempfile
import subprocess
import unittest

from script.document_health import ROOT, BASELINE, anchors, body_size, load_json, main, schema_errors, ratchet_errors, required_adjustments, review_errors, validate


class DocumentHealthTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mwx-document-health-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'docs/history').mkdir(parents=True)
        self.path = 'docs/current.md'
        self.body = '# Authority\n\n<a id="snapshot"></a>\nShort overview.\n<a id="contract"></a>\nContract.\n'
        (self.root / self.path).write_text(self.body)
        self.index = {'documents': [{'path': self.path, 'role': 'current-state'}]}
        self.baseline = {'schemaVersion': 1, 'maxReviewAgeDays': 60,
                         'bodies': {self.path: body_size(self.body)}, 'archives': [],
                         'snapshots': [{'path': self.path, 'start': 'snapshot', 'end': 'contract'}]}

    def test_new_authority_and_body_growth_fail_without_budget(self):
        self.assertEqual(validate(self.root, self.index, self.baseline), [])
        (self.root / self.path).write_text(self.body + 'New unsupported narrative.\n')
        self.assertTrue(any('exceeds baseline' in e for e in validate(self.root, self.index, self.baseline)))
        self.baseline['bodies'] = {}
        self.assertTrue(any('unbudgeted' in e for e in validate(self.root, self.index, self.baseline)))

    def test_ratchet_rejects_budget_growth_removal_archive_rewrite_and_age_extension(self):
        old = copy.deepcopy(self.baseline)
        old['maxReviewAgeDays'] = 59
        old['archives'] = [{'source': self.path, 'archive': 'docs/history/one.md', 'anchors': ['one'], 'preservedBodySHA256': 'a' * 64}]
        new = copy.deepcopy(old)
        new['bodies'][self.path]['bytes'] += 1
        new['archives'][0]['preservedBodySHA256'] = 'b' * 64
        new['maxReviewAgeDays'] += 1
        self.assertEqual(len(ratchet_errors(old, new)), 3)
        del new['bodies'][self.path]
        self.assertTrue(any('removed' in e for e in ratchet_errors(old, new)))

    def record_adjustments(self, old, new, decision=None):
        new['adjustments'] = [dict(change, owner='documentation', reason='Reviewed capability or lifecycle change',
                                   decision=decision or self.path + '#contract')
                              for change in required_adjustments(old, new)]

    def test_documented_growth_is_exact_and_does_not_allow_following_growth(self):
        old = copy.deepcopy(self.baseline)
        text = self.body + 'New capability and its acceptance contract.\n'
        (self.root / self.path).write_text(text)
        self.baseline['bodies'][self.path] = body_size(text)
        self.assertTrue(ratchet_errors(old, self.baseline))
        self.record_adjustments(old, self.baseline)
        self.assertEqual(ratchet_errors(old, self.baseline), [])
        self.assertEqual(validate(self.root, self.index, self.baseline), [])
        committed = copy.deepcopy(self.baseline)
        self.baseline['bodies'][self.path]['bytes'] += 1
        self.assertTrue(ratchet_errors(old, self.baseline))
        self.assertTrue(ratchet_errors(committed, self.baseline))

    def test_authority_can_move_or_retire_with_bound_decision(self):
        for role, destination in (('current-state', 'docs/renamed.md'),
                                  ('historical-evidence', 'docs/history/completed.md')):
            with self.subTest(role=role):
                old = copy.deepcopy(self.baseline)
                new = copy.deepcopy(old)
                (self.root / destination).write_text(self.body)
                new['bodies'] = {destination: body_size(self.body)} if role == 'current-state' else {}
                new['snapshots'] = [dict(old['snapshots'][0], path=destination)] if role == 'current-state' else []
                index = {'documents': [{'path': destination, 'role': role}]}
                self.assertTrue(ratchet_errors(old, new))
                self.record_adjustments(old, new, destination + '#contract')
                self.assertEqual(ratchet_errors(old, new), [])
                self.assertEqual(validate(self.root, index, new), [])
                if role == 'current-state':
                    new['bodies'][destination]['bytes'] += 1
                    self.assertTrue(ratchet_errors(old, new))
                    new['bodies'][destination]['bytes'] -= 1
                    new['snapshots'][0]['end'] = 'another-boundary'
                    self.assertTrue(ratchet_errors(old, new))

    def test_archive_merge_still_requires_real_payload_and_permanent_redirects(self):
        payload = '<a id="legacy"></a>\nHistorical result.\n'
        old = copy.deepcopy(self.baseline)
        old['archives'] = [{'source': self.path, 'archive': 'docs/history/one.md', 'anchors': ['legacy'],
                            'preservedBodySHA256': hashlib.sha256(payload.encode()).hexdigest()}]
        new = copy.deepcopy(old)
        new['archives'][0]['archive'] = 'docs/history/merged.md'
        archive = self.root / new['archives'][0]['archive']
        archive.write_text('<!-- preserved-body:start -->\n' + payload + '<!-- preserved-body:end -->\n')
        (self.root / self.path).write_text(self.body + '<a id="legacy"></a> [归档记录](history/merged.md#legacy) <!-- archive-redirect -->\n')
        self.record_adjustments(old, new)
        self.assertEqual(ratchet_errors(old, new), [])
        self.assertEqual(validate(self.root, self.index, new), [])
        changed_destination = copy.deepcopy(new)
        changed_destination['archives'][0]['preservedBodySHA256'] = 'f' * 64
        self.assertTrue(ratchet_errors(old, changed_destination))
        archive.write_text('<!-- preserved-body:start -->\nAltered evidence.\n<!-- preserved-body:end -->\n')
        self.assertTrue(any('payload changed' in e for e in validate(self.root, self.index, new)))

    def test_adjustments_do_not_bypass_hard_limits_or_missing_decision(self):
        old = copy.deepcopy(self.baseline)
        text = self.body + 'Line\n' * 601
        (self.root / self.path).write_text(text)
        self.baseline['bodies'][self.path] = body_size(text)
        self.record_adjustments(old, self.baseline)
        self.assertEqual(ratchet_errors(old, self.baseline), [])
        self.assertTrue(any('600 lines' in e for e in validate(self.root, self.index, self.baseline)))
        for decision, expected in (('docs/missing.md', 'missing'), (self.path + '#missing', 'anchor missing')):
            self.baseline['adjustments'][0]['decision'] = decision
            self.assertTrue(any(expected in e for e in validate(self.root, self.index, self.baseline)))

    def test_malformed_and_duplicate_adjustments_are_rejected(self):
        old = copy.deepcopy(self.baseline)
        self.baseline['bodies'][self.path]['bytes'] += 1
        self.record_adjustments(old, self.baseline)
        for field, value in (('section', []), ('path', '../outside.md'), ('before', 'invalid'),
                             ('reason', ''), ('owner', None), ('decision', 'docs/../outside.md')):
            invalid = copy.deepcopy(self.baseline)
            invalid['adjustments'][0][field] = value
            self.assertTrue(schema_errors(invalid), field)
        invalid = copy.deepcopy(self.baseline)
        invalid['adjustments'] *= 2
        self.assertTrue(schema_errors(invalid))

    def test_cli_compares_committed_baseline_and_reports_required_adjustments(self):
        (self.root / 'script').mkdir()
        (self.root / 'docs/document-role-index.json').write_text(json.dumps(self.index))
        baseline_file = self.root / BASELINE
        baseline_file.write_text(json.dumps(self.baseline))
        def git(*args):
            return subprocess.run(['git', '-c', 'user.name=Document Test', '-c', 'user.email=test@example.invalid',
                                   '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', *args],
                                  cwd=self.root, capture_output=True, text=True, check=True)
        git('init', '-q')
        git('add', str(BASELINE))
        git('commit', '-qm', 'Initial document baseline')
        old = copy.deepcopy(self.baseline)
        text = self.body + 'Expanded contract.\n'
        (self.root / self.path).write_text(text)
        self.baseline['bodies'][self.path] = body_size(text)
        for documented in (False, True):
            if documented:
                self.record_adjustments(old, self.baseline)
            baseline_file.write_text(json.dumps(self.baseline))
            output = io.StringIO()
            with patch('script.document_health.ROOT', self.root), redirect_stdout(output):
                code = main(['--check'])
            result = json.loads(output.getvalue())
            self.assertEqual(code, 0 if documented else 1)
            self.assertFalse(result['baselineBootstrap'])
            self.assertEqual(len(result['requiredAdjustments']), 1)

    def test_archive_payload_and_original_anchor_must_survive(self):
        payload = '<a id="legacy"></a>\nOriginal bounded evidence.\n'
        for archive in ('docs/history/one.md', 'docs/scene/history/one.md'):
            (self.root / archive).parent.mkdir(parents=True, exist_ok=True)
            (self.root / archive).write_text('<!-- preserved-body:start -->\n' + payload + '<!-- preserved-body:end -->\n')
            text = self.body + f'<a id="legacy"></a> [归档记录]({archive.removeprefix("docs/")}#legacy) <!-- archive-redirect -->\n'
            (self.root / self.path).write_text(text)
            self.baseline['archives'] = [{'source': self.path, 'archive': archive, 'anchors': ['legacy'],
                                         'preservedBodySHA256': hashlib.sha256(payload.encode()).hexdigest()}]
            self.assertEqual(validate(self.root, self.index, self.baseline), [])
            (self.root / archive).write_text('<!-- preserved-body:start -->\nChanged.\n<!-- preserved-body:end -->\n')
            errors = validate(self.root, self.index, self.baseline)
            self.assertTrue(any('payload changed' in e for e in errors))
            self.assertTrue(any('anchor' in e for e in errors))

    def test_fake_redirect_cannot_hide_new_prose_or_target_other_authority(self):
        for line in ('new prose <!-- archive-redirect -->', '<a id="contract"></a> [归档记录](current.md#contract) <!-- archive-redirect -->'):
            with self.subTest(line=line):
                (self.root / self.path).write_text(self.body + line + '\n')
                self.assertTrue(validate(self.root, self.index, self.baseline))

    def test_snapshot_is_bounded_and_ordered(self):
        text = self.body.replace('Short overview.', '\n'.join(['Detail'] * 151))
        (self.root / self.path).write_text(text)
        self.baseline['bodies'][self.path] = body_size(text)
        self.assertTrue(any('150 lines' in e for e in validate(self.root, self.index, self.baseline)))
        (self.root / self.path).write_text(self.body.replace('id="contract"', 'id="lost"'))
        self.assertTrue(any('snapshot anchors' in e for e in validate(self.root, self.index, self.baseline)))

    def test_stale_future_and_unbound_review_receipts_are_rejected(self):
        document = {'path': self.path, 'lastReviewed': '2026-08-01', 'reviewBasis': {
            'kind': 'navigation-audit', 'sourceSHA256': hashlib.sha256(self.body.encode()).hexdigest(),
            'method': 'document_registry --audit + document_health --check',
            'scope': 'navigation only', 'limitations': 'not runtime validation'}}
        self.assertEqual(review_errors(self.root, document, date(2026, 9, 1), 60), [])
        self.assertTrue(any('stale' in e for e in review_errors(self.root, document, date(2026, 10, 3), 60)))
        self.assertTrue(any('future' in e for e in review_errors(self.root, document, date(2026, 7, 1), 60)))
        document['reviewBasis']['sourceSHA256'] = 'invented'
        self.assertTrue(any('receipt' in e for e in review_errors(self.root, document, date(2026, 9, 1), 60)))

    def test_nonfinite_boolean_and_malformed_budgets_cannot_bypass_comparisons(self):
        for number in (float('nan'), float('inf'), -1, True, False, 3.5, '4', None):
            for field in ('lines', 'bytes'):
                with self.subTest(number=number, field=field):
                    invalid = copy.deepcopy(self.baseline)
                    invalid['bodies'][self.path][field] = number
                    self.assertTrue(schema_errors(invalid))
                    self.assertTrue(validate(self.root, self.index, invalid))
                    self.assertTrue(ratchet_errors(self.baseline, invalid))
                    self.assertTrue(ratchet_errors(invalid, self.baseline))
        for field, value in (('archives', {}), ('snapshots', [None]), ('bodies', []),
                             ('maxReviewAgeDays', True), ('schemaVersion', True)):
            invalid = copy.deepcopy(self.baseline)
            invalid[field] = value
            self.assertTrue(validate(self.root, self.index, invalid), field)
        for token in ('NaN', 'Infinity', '-Infinity', '1e999'):
            with self.assertRaisesRegex(ValueError, 'non-finite'):
                load_json('{"budget": ' + token + '}')

    def test_paths_cannot_escape_docs_lexically_or_through_symlinks(self):
        for path in ('/tmp/out.md', 'docs/../out.md', 'docs//current.md', 'docs/./current.md',
                     'other/current.md', 'docs/current.txt', 'docs/evil\\name.md'):
            invalid = copy.deepcopy(self.baseline)
            invalid['bodies'] = {path: {'lines': 1, 'bytes': 1}}
            self.assertTrue(validate(self.root, self.index, invalid), path)
        outside = self.root / 'outside.md'
        outside.write_text('outside')
        (self.root / self.path).unlink()
        (self.root / self.path).symlink_to(outside)
        self.assertTrue(any('escapes docs' in e for e in validate(self.root, self.index, self.baseline)))

    def test_cli_invalid_json_and_schema_report_errors_without_traceback(self):
        (self.root / 'script').mkdir()
        (self.root / 'docs/document-role-index.json').write_text(json.dumps(self.index))
        for text in ('{"schemaVersion": NaN}', '[]', '{"bodies": false}'):
            (self.root / BASELINE).write_text(text)
            output, error = io.StringIO(), io.StringIO()
            with patch('script.document_health.ROOT', self.root), redirect_stdout(output), redirect_stderr(error):
                try:
                    code = main(['--check'])
                except SystemExit as failure:
                    code = failure.code
            self.assertIn(code, (1, 2))
            self.assertNotIn('Traceback', output.getvalue() + error.getvalue())
            self.assertTrue(output.getvalue() or error.getvalue())

    def test_heading_anchors_match_original_link_checker(self):
        from script.tests.test_scene_semantics_coverage import markdown_anchors
        text = '# E-2026 — Test  Name\n## 中文 **标题** &amp; value\n```\n## Not an anchor\n```\n<a id="explicit"></a>\n<A class="x" ID="attribute-order"></A>\n'
        self.assertEqual(anchors(text), markdown_anchors(text))
        self.assertIn('e-2026-test-name', anchors(text))
        self.assertNotIn('not-an-anchor', anchors(text))

    def test_snapshot_contract_and_shrinking_body_cannot_leave_loose_budget(self):
        new = copy.deepcopy(self.baseline)
        new['snapshots'] = []
        self.assertTrue(any('snapshot boundaries' in e for e in ratchet_errors(self.baseline, new)))
        (self.root / self.path).write_text(self.body.replace('Contract.', 'C.'))
        self.assertTrue(any('ratchet baseline down' in e for e in validate(self.root, self.index, self.baseline)))

    def test_repository_current_authorities_archives_and_review_evidence(self):
        index = json.loads((ROOT / 'docs/document-role-index.json').read_text())
        baseline = json.loads((ROOT / BASELINE).read_text())
        self.assertEqual(validate(ROOT, index, baseline), [])
        for path in ('docs/scene/capabilities/coverage-ledger.md', 'docs/scene/capabilities/runtime-evidence-current.md'):
            self.assertLessEqual(body_size((ROOT / path).read_text())['lines'], 600)


if __name__ == '__main__':
    unittest.main()
