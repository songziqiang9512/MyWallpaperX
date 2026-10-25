"""Real NSWindow events drive the shared local grid and live remote browser leases."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]


class GridWindowThumbnailLifecycleTests(unittest.TestCase):
    def test_shared_local_grid_viewport_geometry_and_native_window_leases(self):
        from script.tests.native_app_harness import prepare_native_app, run_native_app
        from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS
        paths = ["Models/WallpaperReference.swift", "Models/WallpaperContent.swift", "Models/WallpaperLibraryPage.swift",
            "Shared/Components/WallpaperLibraryGridMetrics.swift", "Shared/Components/WallpaperCardInteractionView.swift",
            "Shared/UI/WallpaperGridScrollView.swift", "Shared/UI/BoxSelectionState.swift",
            "Shared/UI/GridThumbnailPrefetchDemand.swift", "Shell/WallpaperLibraryGridController.swift"]
        sources = [ROOT / "MyWallpaperX" / path for path in paths]
        sources += [ROOT / "script/tests/fixtures" / name for name in
            ["NativeAppHarness.swift", "WallpaperLibraryGridViewportHarness.swift"]]
        with tempfile.TemporaryDirectory(prefix="mwx-local-viewport-", dir="/private/tmp") as directory:
            work = Path(directory)
            binary = prepare_native_app(work, "WallpaperLibraryGridViewport")
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *map(str, sources), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, timeout=35)
            self.assertEqual(run.launch_returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 16)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)

    def test_actual_order_out_in_mini_and_hidden_ancestor(self):
        steam = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI'
        classes = []
        for index, source in [(1, (steam / 'AppKitSteamWorkshopBrowserGridView.swift').read_text())]:
            signatures = ['    override func viewDidMoveToWindow(', '    override func viewDidHide(',
                          '    override func viewDidUnhide(']
            pieces = [method(source, signature) for signature in signatures]
            demand = source
            signatures = ['    private var thumbnailDemandIsVisible:', '    private func cancelPreviewPrefetch(',
                          '    private func prioritizeVisibleItemsForHydration(' if index == 1 else '    private func schedulePreviewPrefetch(',
                          '    private func syncVisiblePreviewAnimationStates(']
            pieces += [method(demand, signature) for signature in signatures]
            if index > 0:
                pieces.append('override func installNotifications() {\n' + method(source,
                    '        for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification]') + '\n}')
            classes.append(f'final class P{index}: WindowProbe {{\n'  + '\n'.join(pieces).replace('private ', '') + '\n}')
        with tempfile.TemporaryDirectory(prefix='mwx-grid-window-demand-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Window.swift'
            template = (ROOT / 'script/tests/fixtures/GridWindowThumbnailLifecycleHarness.swift').read_text()
            source.write_text(template.replace('// PRODUCTION_CLASSES', '\n'.join(classes)))
            binary = work / 'window'
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(source),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            if proof := os.environ.get('MWX_GRID_WINDOW_PROOF_DIR'):
                target = Path(proof); target.mkdir(parents=True, exist_ok=True)
                (target / 'checks.json').write_text(json.dumps(checks, indent=2) + '\n')
                (target / 'build.log').write_text(build.stdout + build.stderr)
                (target / 'runtime.log').write_text(run.stderr)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertTrue(passed)

            # Restore the reviewed Steam behavior in the isolated copy: both
            # the caller and callee ignore the hidden ancestor. Altering only
            # one is harmless because the other still enforces visibility.
            # This must fail both independent-lease negative controls.
            old = 'self.syncVisiblePreviewAnimationStates(isVisible: self.thumbnailDemandIsVisible)'
            bad = 'self.syncVisiblePreviewAnimationStates(isVisible: !window.isMiniaturized)'
            mutant_classes = []
            for index, body in [(1, classes[0])]:
                if index > 0:
                    guard = 'item.setPreviewVisible(isVisible && thumbnailDemandIsVisible)'
                    self.assertEqual(body.count(guard), 1)
                    body = body.replace(guard, 'item.setPreviewVisible(isVisible)')
                    start = body.index('override func installNotifications()')
                    callback = body[start:]
                    self.assertEqual(callback.count(old), 1, "mini callback injection must remain exact")
                    body = body[:start] + callback.replace(old, bad)
                mutant_classes.append(body)
            mutant = work / 'Mutant.swift'
            mutant.write_text(template.replace('// PRODUCTION_CLASSES', '\n'.join(mutant_classes)))
            mutant_binary = work / 'mutant'
            mutant_build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(mutant),
                '-module-cache-path', str(work / 'modules'), '-o', str(mutant_binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(mutant_build.returncode, 0, mutant_build.stdout + mutant_build.stderr)
            mutant_run = subprocess.run([str(mutant_binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(mutant_run.returncode, 0, mutant_run.stdout + mutant_run.stderr)
            mutant_checks = json.loads(mutant_run.stdout)
            self.assertEqual({name for name, passed in mutant_checks.items() if not passed}, {
                '1-hiddenAncestorCannotResumeAfterDemini',
            })
            if proof := os.environ.get('MWX_GRID_WINDOW_PROOF_DIR'):
                target = Path(proof)
                (target / 'mutant-checks.json').write_text(json.dumps(mutant_checks, indent=2) + '\n')
                (target / 'mutant-build.log').write_text(mutant_build.stdout + mutant_build.stderr)


if __name__ == '__main__':
    unittest.main()
