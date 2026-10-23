"""Exercise shared UI geometry, tracking and unchanged chrome on real AppKit."""
import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.native_app_harness import prepare_native_app, run_native_app


ROOT = Path(__file__).resolve().parents[2]
PRODUCT = [
    'MyWallpaperX/Shared/UI/InspectorFooterMetrics.swift',
    'MyWallpaperX/Shared/UI/InspectorFadingScrollView.swift',
    'MyWallpaperX/Shared/Components/AppKitSettingsComponents.swift',
    'MyWallpaperX/Shared/UI/ToolbarMenuPopover.swift',
    'MyWallpaperX/Shared/Components/SidebarComponents.swift',
]


class NativeUIEquivalenceTests(unittest.TestCase):
    def test_footer_tracking_geometry_settings_and_scroll(self):
        with tempfile.TemporaryDirectory(prefix='mwx-native-ui-', dir='/private/tmp') as temporary:
            work = Path(temporary)
            binary = prepare_native_app(work, 'NativeUIEquivalence')
            override = os.environ.get('MWX_NATIVE_UI_SOURCE_DIR')
            sources = [Path(override) / Path(p).name if override else ROOT / p for p in PRODUCT]
            sources += [ROOT / 'script/tests/fixtures/NativeAppHarness.swift',
                        ROOT / 'script/tests/fixtures/NativeUIEquivalenceHarness.swift']
            identities = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
            frozen = work / 'source'
            frozen.mkdir()
            for source in sources:
                shutil.copy2(source, frozen / source.name)
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, sorted(frozen.glob('*.swift'))),
                                    '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                                   capture_output=True, text=True, timeout=60)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            proof = work / 'proof'
            result = run_native_app(binary, [str(proof)], timeout=40)
            self.assertEqual(result.launch_returncode, 0, result.stderr)
            self.assertTrue((proof / 'report.json').is_file(), result.stdout + result.stderr)
            report = json.loads((proof / 'report.json').read_text())
            checks = report['checks']
            if destination := os.environ.get('MWX_NATIVE_UI_PROOF_DIR'):
                target = Path(destination)
                target.mkdir(parents=True, exist_ok=True)
                shutil.copytree(proof, target, dirs_exist_ok=True)
                (target / 'compile.log').write_text(build.stdout + build.stderr)
                (target / 'runtime.log').write_text(result.stdout + result.stderr)
                (target / 'input-identities.json').write_text(json.dumps(identities, indent=2))
            self.assertEqual(identities, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources})
            self.assertEqual(len(checks), 163)
            self.assertTrue(report['windowVisible'])
            self.assertTrue(all(value is True for value in checks.values()), checks)

    def test_download_toast_layout_hover_and_actions(self):
        """Compile the complete toast; callbacks record effects without account/media work."""
        source = ROOT / 'MyWallpaperX/Modules/OnlineLibrary/UI/OnlineLibraryBrowserSupport.swift'
        if override := os.environ.get('MWX_NATIVE_UI_SOURCE_DIR'):
            source = Path(override) / source.name
        fixture = ROOT / 'script/tests/fixtures/OnlineDownloadToastChecks.swift'
        with tempfile.TemporaryDirectory(prefix='mwx-toast-native-', dir='/private/tmp') as temporary:
            work = Path(temporary)
            identities = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [source, fixture]}
            copies = []
            for path in [source, fixture]:
                target = work / path.name
                shutil.copy2(path, target)
                copies.append(target)
            binary = work / 'toast'
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, copies),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / 'home'; home.mkdir()
            run = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            report = json.loads(run.stdout)
            if proof := os.environ.get('MWX_NATIVE_UI_PROOF_DIR'):
                target = Path(proof); target.mkdir(parents=True, exist_ok=True)
                (target / 'toast-report.json').write_text(json.dumps(report, indent=2)+'\n')
                (target / 'toast-inputs.json').write_text(json.dumps(identities, indent=2)+'\n')
            self.assertEqual(len(report['checks']), 42)
            for name, passed in report['checks'].items():
                with self.subTest(name=name): self.assertIs(passed, True)
            self.assertEqual(identities, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [source, fixture]})

if __name__ == '__main__':
    unittest.main()
