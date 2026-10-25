"""Inject real SQLite C API failures into the unmodified relationship owner."""
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
           ROOT / 'script/tests/fixtures/UserCollectionsSQLiteFaultHarness.swift']
SHIM = ROOT / 'script/tests/fixtures/UserCollectionsSQLiteFault.c'
CHECKS = {'database_error_reported', 'original_full_error_retained',
          'rollback_io_error_retained', 'first_create_injected_once',
          'rollback_injected_once', 'failed_open_closes_exactly_once',
          'failed_open_uses_close_v2', 'same_owner_reopens_cleanly',
          'reopened_owner_commits_real_write', 'independent_owner_reads_committed_data',
          'faults_do_not_repeat_during_reopen'}


class UserCollectionsSQLiteFaultTests(unittest.TestCase):
    def test_create_full_and_rollback_ioerr_close_once_then_reopen(self):
        identities = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                      for path in SOURCES + [SHIM]}
        with tempfile.TemporaryDirectory(prefix='mwx-collections-fault-', dir='/private/tmp') as temporary:
            work = Path(temporary)
            for source in SOURCES + [SHIM]:
                shutil.copy2(source, work / source.name)
            library = work / 'libUserCollectionsSQLiteFault.dylib'
            shim_build = subprocess.run(['xcrun', 'clang', '-dynamiclib', '-Wall', '-Wextra', '-Werror',
                str(work / SHIM.name), '-lsqlite3', '-o', str(library)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(shim_build.returncode, 0, shim_build.stdout + shim_build.stderr)
            binary = work / 'checks'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS,
                '-warnings-as-errors', '-parse-as-library', *[str(work / path.name) for path in SOURCES],
                '-module-cache-path', str(work / 'modules'), '-L', str(work),
                '-lUserCollectionsSQLiteFault', '-Xlinker', '-rpath', '-Xlinker', str(work),
                '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            data = work / 'profile'; data.mkdir()
            run = subprocess.run([str(binary), str(data)], capture_output=True, text=True, timeout=30,
                                 env=dict(os.environ, HOME=str(data), CFFIXED_USER_HOME=str(data)))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            report = json.loads(run.stdout)
            self.assertEqual(set(report), CHECKS)
            for name, passed in report.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True)
            self.assertEqual(identities, {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                                          for path in SOURCES + [SHIM]})
            if output := os.environ.get('MWX_COLLECTIONS_PROOF_DIR'):
                proof = Path(output); proof.mkdir(parents=True, exist_ok=True)
                (proof / 'sqlite-fault-report.json').write_text(json.dumps(report, indent=2) + '\n')
                (proof / 'sqlite-fault-inputs.json').write_text(json.dumps(identities, indent=2) + '\n')
                (proof / 'sqlite-fault-build.log').write_text(shim_build.stdout + shim_build.stderr
                                                           + build.stdout + build.stderr)


if __name__ == '__main__':
    unittest.main()
