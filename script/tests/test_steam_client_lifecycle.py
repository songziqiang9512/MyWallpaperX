"""Compile the real client with a network-free transport and exercise lifecycle boundaries."""
import pathlib
import json
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method
from script.tests.native_app_harness import prepare_native_app, run_native_app

ROOT = pathlib.Path(__file__).resolve().parents[2]


class SteamClientLifecycleTests(unittest.TestCase):
    def test_native_browser_visibility_drives_the_existing_idle_gate(self):
        view = (ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopBrowserView.swift').read_text()
        service = (ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService.swift').read_text()
        fixture = (ROOT / 'script/tests/fixtures/SteamBrowseVisibilityHarness.swift').read_text()
        fixture = fixture.replace('// ACTUAL_DEMAND_STATE', next(line for line in service.splitlines()
            if 'private(set) var browsePanelAttachmentCount =' in line))
        fixture = fixture.replace('// ACTUAL_DEMAND_METHODS', '\n'.join(method(service, signature) for signature in (
            '    var isBrowsePanelOpen:', '    func noteBrowsePanelAttached(', '    func noteBrowsePanelDetached(')))
        fixture = fixture.replace('// ACTUAL_VISIBILITY_STATE', '\n'.join(line for line in view.splitlines()
            if line.startswith('    private var isBrowsePanelActive =') or line.startswith('    private var visibilitySubscription:')))
        fixture = fixture.replace('// ACTUAL_VISIBILITY_METHODS', '\n'.join(method(view, signature) for signature in (
            '    override func viewDidMoveToWindow(', '    override func viewDidHide(',
            '    override func viewDidUnhide(', '    private func updateBrowsePanelVisibility(')))
        with tempfile.TemporaryDirectory(prefix='mwx-steam-browse-visibility-', dir='/private/tmp') as directory:
            work = pathlib.Path(directory)
            source = work / 'Checks.swift'
            source.write_text(fixture)
            executable = prepare_native_app(work, 'SteamBrowseVisibility')
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-default-isolation', 'MainActor',
                str(source), str(ROOT / 'script/tests/fixtures/NativeAppHarness.swift'),
                str(ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core/SteamHelperIdleReaper.swift'),
                '-module-cache-path', str(work / 'modules'), '-o', str(executable)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            result = run_native_app(executable, timeout=15)
            self.assertEqual(result.launch_returncode, 0, result.stdout + result.stderr)
            checks = json.loads(result.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, result.stdout + result.stderr)

    def test_real_client_with_fake_transport(self):
        sources = [
            "MyWallpaperX/Core/SteamWorkshopStorage/ScenePlaybackSource.swift",
            "MyWallpaperX/Core/SteamWorkshopStorage/SteamWorkshopStorageTree.swift",
            "MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift",
            "MyWallpaperX/Core/DaemonKit/DaemonProcessTransport.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamServiceProtocol.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamServiceClient.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamAccountSession.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopQueryClient.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamAuthRoute.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopTokenStore.swift",
            "MyWallpaperX/Core/PlaybackControl/PlaybackResourceLifetime.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopLibraryTransaction.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopLibraryTransaction+FailedVisibility.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopLibraryPublication.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopLibraryVersionLease.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopJobStore.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopDownloadProgress.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamHelperIdleReaper.swift",
            "script/tests/fixtures/SteamServiceClientLifecycleHarness.swift",
        ]
        with tempfile.TemporaryDirectory(prefix="mwx-steam-client-") as directory:
            executable = pathlib.Path(directory) / "client-tests"
            subprocess.run(["xcrun", "swiftc", "-parse-as-library", *[str(ROOT / s) for s in sources],
                            "-o", str(executable)], check=True, timeout=120)
            subprocess.run([str(executable)], check=True, timeout=15)


if __name__ == "__main__":
    unittest.main()
