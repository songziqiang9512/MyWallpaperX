"""Real remote toolbar factories and native overflow with recording service leaves."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS
from script.tests.test_steam_library_interactions import method
from script.tests.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]


class LibraryRemoteToolbarTests(unittest.TestCase):
    def test_signout_service_keeps_confirmed_account_intent(self):
        service = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService.swift'
        fixture = ROOT / 'script/tests/fixtures/LibraryToolbarSignoutHarness.swift'
        parser = ROOT / 'script/tests/test_steam_library_interactions.py'
        paths = [service, fixture, parser, Path(__file__)]
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
        actual = method(service.read_text(), '    func signOutEverywhere(')
        template = fixture.read_text()
        self.assertEqual(template.count('// PRODUCTION_SIGNOUT'), 1)
        with tempfile.TemporaryDirectory(prefix='mwx-toolbar-signout-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Signout.swift'
            source.write_text(template.replace('// PRODUCTION_SIGNOUT', actual))
            binary = work / 'checks'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                str(source), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertTrue(run.stdout.strip(), run.stderr)
            checks = json.loads(run.stdout)
            print(json.dumps(checks, sort_keys=True))
            self.assertEqual(len(checks), 11)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)
            self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths})

    def test_original_source_commands_and_native_overflow(self):
        relative = [
            'Shared/Components/ActionMenuItem.swift', 'Shared/Components/WallpaperLibraryGridMetrics.swift',
            'Shared/Components/WallpaperLibraryZoomControl.swift', 'Shared/UI/ToolbarMenuPopover.swift',
            'Modules/SteamWorkshop/Core/SteamWorkshopBrowseFilters.swift',
            'Modules/SteamWorkshop/Core/SteamWorkshopAgeRatingSupport.swift',
            'Modules/SteamWorkshop/Core/SteamWorkshopDownloadTaskProjection.swift',
            'Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarIdentifiers.swift',
            'Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarController.swift',
            'Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarController+Actions.swift',
            'Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarController+Configuration.swift',
            'Modules/SteamWorkshop/Toolbar/SteamWorkshopToolbarController+Layouts.swift',
            'Modules/OnlineLibrary/Core/OnlineLibraryModels.swift',
            'Modules/OnlineLibrary/Toolbar/OnlineLibraryToolbarController.swift',
        ]
        paths = [ROOT / 'MyWallpaperX' / path for path in relative]
        paths.append(ROOT / 'script/tests/fixtures/NativeAppHarness.swift')
        fixture = ROOT / 'script/tests/fixtures/LibraryRemoteToolbarHarness.swift'
        tasks = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopDownloadTasksPopover.swift'
        models = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopJobStore.swift'
        observed = [*paths, fixture, tasks, models, Path(__file__), ROOT / 'script/tests/native_app_harness.py',
                    ROOT / 'script/tests/test_ui_library_algorithms.py']
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed}
        template = fixture.read_text()
        for marker, content in {
            '// ACTUAL_TASK_MODELS': '\n'.join(declaration(models.read_text(), signature) for signature in [
                'enum SteamDownloadJobState:', 'struct SteamDownloadJob:',
                'enum SteamDownloadHistoryOutcome:', 'struct SteamDownloadHistoryEntry:']),
            '// ACTUAL_TASK_CONTROLLERS': '\n'.join(declaration(tasks.read_text(), signature) for signature in [
                'final class SteamWorkshopDownloadTasksPopoverController:',
                'final class SteamWorkshopDownloadTasksContentController:', 'private final class FlippedView:']),
        }.items():
            self.assertEqual(template.count(marker), 1)
            template = template.replace(marker, content)
        with tempfile.TemporaryDirectory(prefix='mwx-remote-toolbar-', dir='/private/tmp') as directory:
            work = Path(directory)
            copies = []
            for path in paths:
                copied = work / path.name
                shutil.copy2(path, copied)
                copies.append(str(copied))
            harness = work / 'Checks.swift'; harness.write_text(template); copies.append(str(harness))
            binary = prepare_native_app(work, 'LibraryRemoteToolbar')
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *copies, '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, timeout=35)
            self.assertEqual(run.launch_returncode, 0, run.stdout + run.stderr)
            self.assertTrue(run.stdout.strip(), run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            print(json.dumps(checks, sort_keys=True))
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)
            self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed})


if __name__ == '__main__':
    unittest.main()
