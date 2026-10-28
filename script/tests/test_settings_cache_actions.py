"""Original Settings cache/profile actions and feedback, with controlled providers.

The real action factory, dependency type and four button handlers run. Cache,
profile transactions, file choosers, alerts and host visibility are controlled
leaves; no user cache, file or focus is touched.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class SettingsCacheActionsTests(unittest.TestCase):
    def test_interval_draft_uses_the_native_field_editor_across_unrelated_publications(self):
        settings = ROOT / "MyWallpaperX/Shared/Settings/AppKitSettingsView.swift"
        dependency = ROOT / "MyWallpaperX/Shared/Settings/AppSettingsPanelDependency.swift"
        fixture = ROOT / "script/tests/fixtures/SettingsIntervalEditingHarness.swift"
        paths = [settings, dependency, fixture, Path(__file__).resolve()]
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        source = settings.read_text()
        refresh = declaration(source, "    func refreshFromState()")
        # The continuous original playback-control prefix runs with native
        # NSTextField/NSWindow. Unrelated settings groups are outside this gate.
        refresh = refresh[:refresh.index("        let clampedVolume")] + "        _ = visibilityBefore\n    }"
        actual = fixture.read_text().replace("// ACTUAL_INTERVAL_REFRESH", refresh)
        for marker, signature in (
            ("// ACTUAL_SETTINGS_OBSERVER", "    private func observeManager()"),
            ("// ACTUAL_INTERVAL_COMMIT", "    func controlTextDidEndEditing("),
            ("// ACTUAL_TIME_UNIT_SELECTION", "    private func selectTimeUnit("),
        ):
            actual = actual.replace(marker, declaration(source, signature))
        with tempfile.TemporaryDirectory(prefix="mwx-settings-interval-", dir="/private/tmp") as temporary:
            work = Path(temporary)
            copied = work / "Checks.swift"; copied.write_text(actual)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *SWIFT_ISOLATION_FLAGS,
                "-warnings-as-errors", str(dependency), str(copied), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=100)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, value in checks.items():
                with self.subTest(name=name): self.assertIs(value, True, run.stdout + run.stderr)
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})

    def test_clear_once_and_report_only_after_all_providers_finish(self):
        controller = ROOT / "MyWallpaperX/App/SettingsWindowController.swift"
        settings = ROOT / "MyWallpaperX/Shared/Settings/AppKitSettingsView.swift"
        dependency = ROOT / "MyWallpaperX/Shared/Settings/AppSettingsPanelDependency.swift"
        fixture = ROOT / "script/tests/fixtures/SettingsCacheActionsHarness.swift"
        paths = [controller, settings, dependency, fixture, Path(__file__).resolve()]
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        source = fixture.read_text().replace("// ACTUAL_ACTION_FACTORY", declaration(
            controller.read_text(), "    private lazy var settingsActions:") + "()")
        source = source.replace("// ACTUAL_CLEAR_HANDLER", declaration(
            settings.read_text(), "    @objc private func handleClearCache("))
        source = source.replace("// ACTUAL_EXPORT_HANDLER", declaration(
            settings.read_text(), "    @objc func handleExportProfile("))
        source = source.replace("// ACTUAL_IMPORT_HANDLER", declaration(
            settings.read_text(), "    @objc func handleImportProfile("))
        source = source.replace("// ACTUAL_RESET_BUTTON", next(line.strip() for line in settings.read_text().splitlines()
            if line.strip().startswith("let resetSettingsButton = ")))
        source = source.replace("// ACTUAL_RESET_HANDLER", declaration(
            settings.read_text(), "    @objc private func handleResetSettings("))
        with tempfile.TemporaryDirectory(prefix="mwx-settings-cache-", dir="/private/tmp") as temporary:
            work = Path(temporary)
            actual = work / "Checks.swift"
            actual.write_text(source)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *SWIFT_ISOLATION_FLAGS, str(dependency), str(actual),
                "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=100)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for scenario in ('cancel-has-zero-provider-effects', 'cancel-keeps-button-and-has-no-success',
                             'pending-has-no-success-feedback', 'pending-button-disabled-with-progress-label',
                             'every-provider-and-steam-namespace-clears-once', 'success-follows-online-completion',
                             'completed-button-restores-original-label',
                             'closed-host-finishes-clear-without-orphan-success-sheet',
                             'next-operation-remains-usable-and-clears-once'):
                self.assertIs(checks[scenario], True, run.stdout + run.stderr)
            for operation in ('export', 'import'):
                self.assertIs(checks[operation + '-cancelled-chooser-has-no-transaction-or-terminal-alert'], True)
                for outcome in ('success', 'failure'):
                    for visibility in ('closed', 'visible'):
                        for scenario in ('pending-disables-both-buttons', 'original-transaction-finishes-once',
                                         'terminal-feedback-stays-with-the-original-host',
                                         'second-host-never-receives-terminal-feedback', 'next-operation-remains-usable'):
                            self.assertIs(checks[f'{operation}-{outcome}-{visibility}-{scenario}'], True,
                                          run.stdout + run.stderr)
            self.assertIs(checks['import-cancelled-confirmation-has-no-transaction'], True)
            for name, value in checks.items():
                with self.subTest(name=name):
                    self.assertIs(value, True, run.stdout + run.stderr)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})
