"""System NSAlert windows, native modal sessions, hosts and responses."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class AppModalPresentationTests(unittest.TestCase):
    def test_system_alerts_keep_native_modal_and_response_contracts(self):
        sources = [ROOT / path for path in (
            'MyWallpaperX/Shared/UI/ModalPresentation.swift',
            'MyWallpaperX/Shared/UI/WallpaperLibrarySheetPresentation.swift',
            'script/tests/fixtures/AppModalPresentationHarness.swift',
            'script/tests/fixtures/NativeAppHarness.swift')]
        observed = [*sources, Path(__file__), ROOT / 'script/tests/native_app_harness.py']
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed}
        with tempfile.TemporaryDirectory(prefix='mwx-app-modal-', dir='/private/tmp') as directory:
            work = Path(directory)
            copied = []
            for path in sources:
                target = work / path.name
                shutil.copy2(path, target)
                copied.append(str(target))
            binary = prepare_native_app(work, 'AppModalPresentation')
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *copied, '-module-cache-path', str(work / 'modules'), '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, timeout=40)
            diagnostic = f'LaunchServices={run.launch_returncode}\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}'
            self.assertEqual(run.launch_returncode, 0, diagnostic)
            self.assertTrue(run.stdout.strip().startswith('{'), diagnostic)
            checks = json.loads(run.stdout)
            print(json.dumps(checks, sort_keys=True))
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True, diagnostic)
        self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed})


if __name__ == '__main__':
    unittest.main()
