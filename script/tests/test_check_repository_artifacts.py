from pathlib import Path
import json
import subprocess
import tempfile
import unittest

from script.check_repository_artifacts import inspect, historical_errors, MAX_BYTES


class RepositoryArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mwx-artifact-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)

    def file(self, path, size):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('wb') as stream:
            stream.truncate(size)
        return target

    def test_limit_untracked_spaces_and_product_media_scope(self):
        self.file('script/allowed.json', MAX_BYTES)
        self.file('docs/large report.json', MAX_BYTES + 1)
        self.file('MyWallpaperX/Resources/movie.mp4', MAX_BYTES + 1)
        self.assertEqual(inspect(self.root), [{'path': 'docs/large report.json',
            'bytes': MAX_BYTES + 1, 'maximumBytes': MAX_BYTES}])

    def test_ignored_cache_excluded_but_tracked_ignored_file_checked(self):
        (self.root / '.gitignore').write_text('docs/evidence/\n')
        self.file('docs/evidence/cache.json', MAX_BYTES + 1)
        self.assertEqual(inspect(self.root), [])
        subprocess.run(['git', 'add', '-f', 'docs/evidence/cache.json'], cwd=self.root, check=True)
        self.assertEqual(len(inspect(self.root)), 1)

    def test_deleted_tracked_artifact_is_not_failure(self):
        target = self.file('script/report.json', MAX_BYTES + 1)
        subprocess.run(['git', 'add', 'script/report.json'], cwd=self.root, check=True)
        target.unlink()
        self.assertEqual(inspect(self.root), [])

    def test_exception_is_exact_bounded_owned_and_retired(self):
        target = self.file('docs/large.json', MAX_BYTES + 1)
        policy = self.root / 'script/repository_artifact_baseline.json'
        policy.parent.mkdir(exist_ok=True)
        entry = {'path': 'docs/large.json', 'maximumBytes': MAX_BYTES + 2,
                 'owner': 'test owner', 'reason': 'reviewed input', 'retirement': 'replace with cache'}
        def save():
            policy.write_text(json.dumps({'schemaVersion': 1, 'exceptions': [entry]}))
        save()
        self.assertEqual(inspect(self.root), [])
        self.file('docs/another.json', MAX_BYTES + 1)
        self.assertEqual(len(inspect(self.root)), 1)
        self.file('docs/large.json', MAX_BYTES + 3)
        self.assertEqual(len(inspect(self.root)), 2)
        entry['reason'] = ''; save()
        with self.assertRaises(ValueError): inspect(self.root)
        entry['reason'] = 'reviewed'; entry['path'] = 'docs/*.json'; save()
        with self.assertRaises(ValueError): inspect(self.root)
        entry['path'] = 'docs/large.json'; save(); target.unlink()
        with self.assertRaises(ValueError): inspect(self.root)

    def test_new_exception_cannot_bypass_committed_empty_budget(self):
        policy = self.root / 'script/repository_artifact_baseline.json'
        policy.parent.mkdir()
        policy.write_text(json.dumps({'schemaVersion': 1, 'exceptions': []}))
        subprocess.run(['git', 'add', 'script/repository_artifact_baseline.json'], cwd=self.root, check=True)
        subprocess.run(['git', '-c', 'user.name=Fixture', '-c', 'user.email=f@example.test',
                        'commit', '-qm', 'baseline'], cwd=self.root, check=True)
        self.file('docs/new.json', MAX_BYTES + 1)
        policy.write_text(json.dumps({'schemaVersion': 1, 'exceptions': [
            {'path': 'docs/new.json', 'maximumBytes': MAX_BYTES + 1,
             'owner': 'owner', 'reason': 'reason', 'retirement': 'retire'}]}))
        self.assertEqual(inspect(self.root), [])
        self.assertTrue(historical_errors(self.root, 'HEAD'))


if __name__ == '__main__':
    unittest.main()
