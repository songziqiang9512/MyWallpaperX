"""Execute the real actor/SQLite owner; no database or mutation method doubles."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [ROOT / 'MyWallpaperX/Models/WallpaperReference.swift',
           ROOT / 'MyWallpaperX/Core/LibraryCollections/UserCollectionsStore.swift',
           ROOT / 'script/tests/fixtures/UserCollectionsStoreHarness.swift']


class UserCollectionsStoreTests(unittest.TestCase):
    def test_real_database_identity_commands_alias_history_reset_and_failure(self):
        identities = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCES}
        with tempfile.TemporaryDirectory(prefix='mwx-collections-store-', dir='/private/tmp') as temporary:
            work = Path(temporary)
            for source in SOURCES:
                shutil.copy2(source, work / source.name)
            binary = work / 'checks'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS,
                '-warnings-as-errors', '-parse-as-library', *[str(work / p.name) for p in SOURCES],
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            data = work / 'profile'; data.mkdir()
            run = subprocess.run([str(binary), str(data)], capture_output=True, text=True, timeout=30,
                                 env=dict(os.environ, HOME=str(data), CFFIXED_USER_HOME=str(data)))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            report = json.loads(run.stdout)
            self.assertGreaterEqual(len(report), 25)
            for name, passed in report.items():
                with self.subTest(name=name): self.assertIs(passed, True)
            self.assertEqual(identities, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCES})
            if output := os.environ.get('MWX_COLLECTIONS_PROOF_DIR'):
                proof = Path(output); proof.mkdir(parents=True, exist_ok=True)
                (proof / 'store-report.json').write_text(json.dumps(report, indent=2)+'\n')
                (proof / 'store-inputs.json').write_text(json.dumps(identities, indent=2)+'\n')
                (proof / 'store-build.log').write_text(build.stdout+build.stderr)


if __name__ == '__main__':
    unittest.main()
