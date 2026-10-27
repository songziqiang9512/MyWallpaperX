"""Original Steam login controller and native input/modal lifetime.

Only authentication, token storage and account status are controlled leaves;
the controller, glass view, QR child and local event delivery are unchanged.
"""
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


class SteamLoginModalTests(unittest.TestCase):
    def test_original_login_controller_owns_native_modal_input_and_nested_lifetime(self):
        paths = [ROOT / path for path in (
            'MyWallpaperX/Shared/UI/WallpaperLibrarySheetPresentation.swift',
            'MyWallpaperX/Shared/Components/WallpaperFormFieldStyle.swift',
            'MyWallpaperX/Shared/UI/ModalPresentation.swift',
            'MyWallpaperX/Modules/SteamWorkshop/UI/SteamLoginPanelController.swift',
            'MyWallpaperX/Modules/SteamWorkshop/UI/SteamLoginPanelView.swift',
            'script/tests/fixtures/SteamLoginModalHarness.swift',
            'script/tests/fixtures/WallpaperLibraryModalInputChecks.swift',
            'script/tests/fixtures/NativeAppHarness.swift')]
        observed = [*paths, Path(__file__), ROOT / 'script/tests/native_app_harness.py',
                    ROOT / 'script/tests/test_video_thumbnail_prefetch.py']
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed}
        with tempfile.TemporaryDirectory(prefix='mwx-login-modal-', dir='/private/tmp') as directory:
            work = Path(directory)
            copies = []
            for path in paths:
                target = work / path.name
                shutil.copy2(path, target)
                copies.append(str(target))
            binary = prepare_native_app(work, 'SteamLoginModal')
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *copies, '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, timeout=45)
            diagnostic = f'LaunchServices={run.launch_returncode}\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}'
            self.assertEqual(run.launch_returncode, 0, diagnostic)
            self.assertTrue(run.stdout.strip().startswith('{'), diagnostic)
            checks = json.loads(run.stdout)
            print(json.dumps(checks, sort_keys=True))
            required = {
                'missing-main-host-never-starts-auth-or-opens-a-nonmodal-login',
                'original-login-controller-owns-one-key-child-with-shared-clear-glass',
                'steam-login-blocks-native-queue-main-click-drag-and-key-without-a-gray-sheet',
                'repeated-login-presentation-keeps-the-same-panel-and-authentication-attempt',
                'enlarged-qr-is-a-legal-top-child-and-revokes-held-login-controls',
                'closing-enlarged-qr-keeps-the-original-auth-attempt-and-releases-only-its-child',
                'nested-login-alert-stays-above-the-child-and-blocks-held-auth-controls',
                'nested-login-confirmation-keeps-the-original-response-once',
                'ordinary-focus-change-does-not-cancel-the-admitted-login-or-disable-unrelated-window-input',
                'login-cancel-clears-secrets-cancels-once-and-rejects-held-closed-controls',
                'login-close-removes-the-local-monitor-and-restores-native-queue-main-click-drag-and-key',
                'late-auth-publication-cannot-reopen-the-closed-login',
                'already-online-switch-account-keeps-the-password-page-without-replaying-old-success',
                'switch-account-new-guard-transition-and-submission-remain-live',
                'switch-account-new-authentication-success-still-closes-the-panel',
                'already-online-previous-token-save-failure-does-not-replace-the-new-password-page',
                'new-authentication-token-save-failure-still-requires-explicit-completion',
                'silent-restore-success-retains-original-completion-and-status-feedback',
                'silent-restore-new-guard-transition-remains-visible',
                'silent-restore-new-network-failure-keeps-panel-and-reports-retained-session',
                'silent-restore-new-credential-failure-keeps-panel-and-requires-new-login',
                'main-close-retires-the-owned-login-and-authentication-once',
            }
            missing = required.difference(checks)
            self.assertFalse(missing, f'Missing named checks: {sorted(missing)}\n{diagnostic}')
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True, diagnostic)
        self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed})


if __name__ == '__main__':
    unittest.main()
