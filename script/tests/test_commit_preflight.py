import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from script import commit_preflight as gate
from script.publish_release import release_areas


class CommitPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mwx-preflight-', dir='/private/tmp')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = patch.dict(os.environ, {'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': os.devnull})
        self.env.start()
        self.addCleanup(self.env.stop)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)

    def stage(self, path, text):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text)
        subprocess.run(['git', 'add', '--', path], cwd=self.root, check=True)

    def test_reads_staged_json_not_unstaged_repair_and_does_not_change_index(self):
        self.stage('data.json', '{broken')
        before = gate.git(self.root, 'write-tree')
        (self.root / 'data.json').write_text('{}')
        report = gate.inspect(self.root, {'data.json'})
        self.assertTrue(any('Invalid staged JSON' in s for s in report['findings']))
        self.assertEqual(gate.git(self.root, 'write-tree'), before)

    def test_unowned_paths_warn_by_default_and_strict_rejects(self):
        self.stage('a.json', '{}')
        self.stage('b.json', '{}')
        self.assertEqual(gate.inspect(self.root, {'a.json'})['unownedPaths'], ['b.json'])
        with patch.object(gate, 'ROOT', self.root), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(gate.main(['--owned-path', 'a.json'], root=self.root), 0)
            self.assertEqual(gate.main(['--owned-path', 'a.json', '--strict'], root=self.root), 1)
            self.assertEqual(gate.main(['--owned-path', 'a.json', '--owned-path', 'b.json', '--strict'], root=self.root), 0)

    def test_malformed_gate_and_missing_lifecycle_rejected(self):
        for value in (None, {}, [], {'gates': {}}, {'gates': {'x': {}}}, {'gates': {}, 'method_gates': {'x': {}}}):
            self.stage('script/scene_validation_gates.json', json.dumps(value))
            self.assertTrue(gate.inspect(self.root, {'script/scene_validation_gates.json'})['findings'])

    def test_valid_gate_registry_is_accepted(self):
        value = {'gates': {'x': {'risk': 'structure', 'trigger': 'change', 'cost': 'fast',
                                 'retirement': 'after removal', 'serialized': False}},
                 'method_gates': {'x': {}}}
        self.stage('script/scene_validation_gates.json', json.dumps(value))
        self.assertEqual(gate.inspect(self.root, {'script/scene_validation_gates.json'})['findings'], [])

    def test_nul_paths_preserve_leading_whitespace_for_ownership_and_blob_read(self):
        self.stage(' a.json', '{broken')
        report = gate.inspect(self.root, {'a.json'})
        self.assertEqual(report['stagedPaths'], [' a.json'])
        self.assertEqual(report['unownedPaths'], [' a.json'])
        self.assertTrue(any('Invalid staged JSON  a.json' in x for x in report['findings']))

    def test_install_uninstall_preserves_existing_configuration(self):
        gate.git(self.root, 'config', '--local', 'core.hooksPath', 'other-hooks')
        with self.assertRaises(ValueError): gate.install(self.root)
        self.assertEqual(gate.git(self.root, 'config', '--get', 'core.hooksPath'), 'other-hooks')
        gate.git(self.root, 'config', '--unset', 'core.hooksPath')
        gate.install(self.root)
        hook = Path(gate.git(self.root, 'config', '--get', 'core.hooksPath')) / 'pre-commit'
        self.assertTrue(hook.stat().st_mode & 0o111)
        self.assertIn('commit_preflight.py', hook.read_text())
        gate.install(self.root, remove=True)
        self.assertFalse(hook.exists())

    def test_existing_global_and_worktree_hooks_configuration_is_preserved(self):
        global_config = self.root / '.git/test-global'
        with patch.dict(os.environ, {'GIT_CONFIG_GLOBAL': str(global_config)}):
            gate.git(self.root, 'config', '--global', 'core.hooksPath', 'global-hooks')
            with self.assertRaisesRegex(ValueError, 'effective'): gate.install(self.root)
            self.assertIsNone(gate.config_value(self.root, '--local'))
        gate.git(self.root, 'config', '--local', 'extensions.worktreeConfig', 'true')
        gate.git(self.root, 'config', '--worktree', 'core.hooksPath', 'worktree-hooks')
        with self.assertRaisesRegex(ValueError, 'effective'): gate.install(self.root)
        self.assertEqual(gate.config_value(self.root), 'worktree-hooks')

    def test_default_hook_chain_is_not_bypassed(self):
        hook = self.root / '.git/hooks/commit-msg'
        hook.write_text('#!/bin/sh\nexit 7\n')
        hook.chmod(0o755)
        with self.assertRaisesRegex(ValueError, 'default hooks'): gate.install(self.root)
        self.assertEqual(hook.read_text(), '#!/bin/sh\nexit 7\n')
        self.assertIsNone(gate.config_value(self.root))

    def test_modified_owned_hook_and_extra_hooks_are_never_overwritten_or_deleted(self):
        gate.install(self.root)
        directory = Path(gate.config_value(self.root))
        hook = directory / 'pre-commit'
        original = hook.read_text()
        changed = original + '# user extension\n'
        hook.write_text(changed)
        for remove in (False, True):
            with self.assertRaisesRegex(ValueError, 'exact owned'): gate.install(self.root, remove)
            self.assertEqual(hook.read_text(), changed)
            self.assertEqual(gate.config_value(self.root), str(directory))
        hook.write_text(original)
        (directory / 'post-commit').write_text('# user hook')
        for remove in (False, True):
            with self.assertRaisesRegex(ValueError, 'unowned entries'): gate.install(self.root, remove)
        self.assertEqual(gate.config_value(self.root), str(directory))

    def test_symlink_hook_is_not_claimed(self):
        gate.install(self.root)
        hook = Path(gate.config_value(self.root)) / 'pre-commit'
        target = self.root / 'user-hook'
        hook.rename(target)
        hook.symlink_to(target)
        for remove in (False, True):
            with self.assertRaisesRegex(ValueError, 'symlink'): gate.install(self.root, remove)
        self.assertEqual(target.read_text(), gate.hook_content())

    def test_shared_hook_reads_committing_worktree_index(self):
        self.stage('seed.json', '{}')
        gate.git(self.root, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                 '-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'fixture')
        peer = self.root / 'peer'
        gate.git(self.root, 'worktree', 'add', '--detach', str(peer), 'HEAD')
        gate.install(self.root)
        self.stage('only-installer.json', '{}')
        (peer / 'only-peer.json').write_text('{broken')
        gate.git(peer, 'add', '--', 'only-peer.json')
        hook = Path(gate.config_value(peer)) / 'pre-commit'
        result = subprocess.run([str(hook)], cwd=peer, capture_output=True, text=True, check=True)
        report = json.loads(result.stdout)
        self.assertEqual(report['stagedPaths'], ['only-peer.json'])
        self.assertTrue(any('Invalid staged JSON only-peer.json' in x for x in report['findings']))
        self.assertEqual(gate.inspect(self.root, {'only-installer.json'})['stagedPaths'], ['only-installer.json'])

    def test_shared_hook_survives_installer_removal_and_uninstalls_from_peer(self):
        self.stage('script/commit_preflight.py', Path(gate.__file__).read_text())
        self.stage('seed.json', '{}')
        identity = ('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                    '-c', 'commit.gpgsign=false')
        gate.git(self.root, *identity, 'commit', '-q', '-m', 'fixture')
        installer = self.root / 'installer'
        gate.git(self.root, 'worktree', 'add', '--detach', str(installer), 'HEAD')
        result = subprocess.run(
            ['python3.12', '-B', str(installer / 'script/commit_preflight.py'), '--install'],
            cwd=installer, capture_output=True, text=True, check=True)
        self.assertIn('warning-only', result.stdout)
        directory = Path(gate.config_value(self.root))
        snapshot = (directory / 'commit_preflight.py').read_bytes()
        gate.git(self.root, 'worktree', 'remove', str(installer))
        self.assertFalse(installer.exists())
        self.stage('seed.json', '{broken')
        committed = subprocess.run(
            ['git', *identity, 'commit', '-m', 'warning remains optional'],
            cwd=self.root, capture_output=True, text=True, check=True)
        self.assertIn('Invalid staged JSON seed.json', committed.stdout + committed.stderr)
        self.assertEqual((directory / 'commit_preflight.py').read_bytes(), snapshot)
        # Uninstall recognizes the installed snapshot, not the peer's checkout revision.
        source = self.root / 'script/commit_preflight.py'
        source.write_text(source.read_text() + '\n# peer revision\n')
        removed = subprocess.run(['python3.12', '-B', str(source), '--uninstall'],
                                 cwd=self.root, capture_output=True, text=True, check=True)
        self.assertIn('Removed', removed.stdout)
        self.assertIsNone(gate.config_value(self.root))
        self.assertFalse(directory.exists())

    def test_modified_snapshot_is_preserved_on_install_and_uninstall(self):
        gate.install(self.root)
        directory = Path(gate.config_value(self.root))
        payload = directory / 'commit_preflight.py'
        changed = payload.read_bytes() + b'\n# user extension\n'
        payload.write_bytes(changed)
        for remove in (False, True):
            with self.assertRaisesRegex(ValueError, 'exact owned'):
                gate.install(self.root, remove)
            self.assertEqual(payload.read_bytes(), changed)
            self.assertEqual(gate.config_value(self.root), str(directory))

    def test_release_groups_only_actual_trailers_and_rejects_unknown_areas(self):
        self.assertEqual(release_areas(['fix\n\nArea: Scene, Build\n', 'fix\n\nArea: Governance\n']), ['Build', 'Governance', 'Scene'])
        self.assertEqual(release_areas(['Area: Scene\n\nordinary body']), [])
        with self.assertRaises(ValueError): release_areas(['fix\n\nArea: Unregistered\n'])

    def test_owned_paths_cannot_escape_or_be_directory_globs(self):
        for value in ('../secret', '/root', './a.json'):
            with self.assertRaises(ValueError): gate.owned_paths([value])


if __name__ == '__main__': unittest.main()
