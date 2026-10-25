"""Actual SQLite profile transaction, expected-state organization Undo and history clearing.

No preferences/source writer is doubled into a claimed cross-owner transaction;
that separately recovered application is tested by the profile coordinator gate.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class LibraryPersonalSettingsStoreTests(unittest.TestCase):
    def test_real_profile_transaction_undo_and_recent_watermarks(self):
        sources = [ROOT / 'MyWallpaperX' / path for path in (
            'Models/WallpaperReference.swift', 'Core/LibraryCollections/UserCollectionsStore.swift',
            'Core/LibraryCollections/UserCollectionsController.swift')]
        sources.append(ROOT / 'script/tests/fixtures/LibraryPersonalSettingsStoreHarness.swift')
        inputs = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
        with tempfile.TemporaryDirectory(prefix='mwx-profile-store-', dir='/private/tmp') as directory:
            work = Path(directory); binary = work / 'checks'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors',
                '-parse-as-library', *map(str, sources), '-module-cache-path', str(work / 'modules'),
                '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / 'home'; home.mkdir()
            run = subprocess.run([str(binary), str(work / 'databases')], capture_output=True, text=True,
                timeout=40, env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 20)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
        self.assertEqual(inputs, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources})


if __name__ == '__main__':
    unittest.main()
