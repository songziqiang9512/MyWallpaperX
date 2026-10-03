import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'script/run_checkpoint_build.sh'


class CheckpointBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mwx-checkpoint-test-', dir='/private/tmp')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.builder = self.bin / 'xcodebuild'
        self.builder.write_text('''#!/usr/bin/env python3.12
import json, os, sys
from pathlib import Path
if '-version' in sys.argv:
    print(os.environ.get('FAKE_TOOLCHAIN', 'Xcode test-1'))
else:
    Path(os.environ['FAKE_BUILD_LOG']).write_text(json.dumps(sys.argv[1:]))
    if os.environ.get('FAKE_HOLD'):
        import time
        while Path(os.environ['FAKE_HOLD']).exists(): time.sleep(0.02)
    sys.exit(int(os.environ.get('FAKE_BUILD_EXIT', '0')))
''')
        self.builder.chmod(0o755)
        sdk = self.bin / 'xcrun'
        sdk.write_text('#!/bin/sh\necho "${FAKE_SDK:-/SDK/test-1}"\n')
        sdk.chmod(0o755)
        self.log = self.root / 'build.json'
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'], FAKE_BUILD_LOG=str(self.log))

    def run_script(self, *args, **env):
        return subprocess.run(['/bin/bash', str(SCRIPT), *args], env=dict(self.env, **env), capture_output=True, text=True)

    def derived_data(self):
        args = json.loads(self.log.read_text())
        self.assertIn('CODE_SIGNING_ALLOWED=NO', args)
        self.assertEqual(args[-1], 'build')
        return Path(args[args.index('-derivedDataPath') + 1])

    def test_default_isolated_build_cleans_success_and_failure(self):
        for code in (0, 7):
            with self.subTest(code=code):
                result = self.run_script(FAKE_BUILD_EXIT=str(code))
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertFalse(self.derived_data().exists())

    def test_cache_reuses_identity_retains_failure_and_changes_with_toolchain(self):
        cache = str(self.root / 'cache with spaces')
        self.assertEqual(self.run_script('--cache-dir', cache).returncode, 0)
        first = self.derived_data()
        self.assertTrue(first.is_dir())
        (first / 'sentinel').write_text('preserve')
        self.assertEqual(self.run_script('--cache-dir', cache, FAKE_BUILD_EXIT='5').returncode, 5)
        self.assertEqual(self.derived_data(), first)
        self.assertTrue((first / 'sentinel').is_file())
        self.assertEqual(self.run_script('--cache-dir', cache, FAKE_TOOLCHAIN='Xcode test-2').returncode, 0)
        self.assertNotEqual(self.derived_data(), first)
        self.assertEqual(self.run_script('--cache-dir', cache, FAKE_SDK='/SDK/test-2').returncode, 0)
        self.assertNotEqual(self.derived_data(), first)

    def test_keyed_directory_symlink_cannot_redirect_builder_into_sources(self):
        cache = str(self.root / 'cache')
        self.assertEqual(self.run_script('--cache-dir', cache).returncode, 0)
        keyed = self.derived_data()
        keyed.rmdir()
        keyed.symlink_to(ROOT / 'MyWallpaperX', target_is_directory=True)
        self.log.unlink()
        result = self.run_script('--cache-dir', cache)
        self.assertEqual(result.returncode, 2)
        self.assertIn('cannot be a symlink', result.stderr)
        self.assertFalse(self.log.exists())

    def test_cache_initialization_failure_preserves_existing_file_and_symlink(self):
        for kind in ('file', 'symlink'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory(
                    prefix='mywallpaperx-checkpoint-build.', dir='/private/tmp') as directory:
                cache = Path(directory)
                self.assertEqual(self.run_script('--cache-dir', str(cache)).returncode, 0)
                keyed = self.derived_data()
                keyed.rmdir()
                if kind == 'file':
                    keyed.write_bytes(b'preexisting data')
                else:
                    sentinel = cache / 'sentinel'
                    sentinel.write_bytes(b'preexisting data')
                    keyed.symlink_to(sentinel)
                self.log.unlink()
                result = self.run_script('--cache-dir', str(cache))
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.log.exists())
                self.assertEqual(keyed.is_symlink(), kind == 'symlink')
                self.assertEqual(keyed.read_bytes(), b'preexisting data')

    def test_concurrent_builder_rejected_and_os_releases_lock(self):
        marker = self.root / 'hold'
        marker.touch()
        first = subprocess.Popen(['/bin/bash', str(SCRIPT)],
            env=dict(self.env, FAKE_HOLD=str(marker)), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while not self.log.exists() and first.poll() is None and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(self.log.exists(), 'first builder never acquired lock')
            second = self.run_script()
            self.assertEqual(second.returncode, 2)
            self.assertIn('active file-lock owner', second.stderr)
        finally:
            marker.unlink(missing_ok=True)
            first.communicate(timeout=10)
        self.assertEqual(first.returncode, 0)
        self.assertEqual(self.run_script().returncode, 0)

    def test_unknown_or_missing_argument_never_builds(self):
        for args in (('--bogus',), ('--cache-dir',)):
            result = self.run_script(*args)
            self.assertEqual(result.returncode, 2)
            self.assertFalse(self.log.exists())

    def test_source_and_sample_cache_destinations_rejected_before_creation(self):
        candidates = [ROOT / 'MyWallpaperX/forbidden-cache', Path.home() / 'Movies/MyWallpaperX/创意工坊/Scene/forbidden-cache']
        for path in candidates:
            self.assertFalse(path.exists())
            result = self.run_script('--cache-dir', str(path))
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(path.exists())
            self.assertFalse(self.log.exists())


if __name__ == '__main__':
    unittest.main()
