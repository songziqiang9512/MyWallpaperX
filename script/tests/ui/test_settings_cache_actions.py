"""Original Settings cache/profile actions and feedback, with controlled providers.

The real action factory, dependency type and four button handlers run. Cache,
profile transactions, file choosers, alerts and host visibility are controlled
leaves; no user cache, file or focus is touched.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.ui.test_ui_library_algorithms import declaration
from script.tests.ui.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[3]


class SettingsCacheActionsTests(unittest.TestCase):
    def test_interval_draft_uses_the_native_field_editor_across_unrelated_publications(self):
        settings = ROOT / "MyWallpaperX/Shared/Settings/AppKitSettingsView.swift"
        layout = ROOT / "MyWallpaperX/Shared/Settings/AppKitSettingsView+Layout.swift"
        dependency = ROOT / "MyWallpaperX/Shared/Settings/AppSettingsPanelDependency.swift"
        quality = ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackPerformanceProfile.swift"
        settings_components = ROOT / "MyWallpaperX/Shared/Components/AppKitSettingsComponents.swift"
        fixture = ROOT / "script/tests/fixtures/SettingsIntervalEditingHarness.swift"
        display_configuration = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonClient+DisplayConfiguration.swift"
        paths = [settings, layout, dependency, quality, settings_components, fixture, display_configuration, Path(__file__).resolve()]
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        source = settings.read_text()
        refresh = declaration(source, "    func refreshFromState()")
        # The continuous original playback-control prefix runs with native
        # NSTextField/NSWindow. Unrelated settings groups are outside this gate.
        refresh = refresh[:refresh.index("        // 登录项开关")] + "        _ = visibilityBefore\n    }"
        actual = fixture.read_text().replace("// ACTUAL_INTERVAL_REFRESH", refresh)
        actual = actual.replace("// ACTUAL_CONFIGURED_WALLPAPER_SCREENS", declaration(
            display_configuration.read_text(), "    var configuredWallpaperScreens:"))
        actual += "\n" + declaration(settings_components.read_text(), "final class SettingsGroupView:") + "\n"
        layout_source = layout.read_text()
        for marker, signature in (
            ("// ACTUAL_SCENE_POST_PROCESSING_MENU", "    func refreshScenePostProcessingMenu("),
            ("// ACTUAL_SCENE_REAPPLY_TITLE", "    func refreshSceneQualityReapplyTitle("),
            ("// ACTUAL_RASTER_SAMPLE_READOUT", "    func refreshSceneRasterSampleReadout("),
            ("// ACTUAL_RESTORE_QUALITY_CONTROLS", "    func refreshQualityControls("),
            ("// ACTUAL_REFRESH_SCENE_QUALITY_PRESET", "    private func refreshSceneQualityPreset("),
            ("// ACTUAL_QUALITY_ACTION", "    @objc private func handleQualityChange("),
            ("// ACTUAL_RESTORE_DEFAULT_QUALITY_ACTION", "    @objc private func restoreDefaultQuality("),
            ("// ACTUAL_SAVE_EDITED_QUALITY", "    private func saveEditedQuality("),
            ("// ACTUAL_FRAME_RATE_LABELS", "    private func updateSceneFrameRateLabels("),
            ("// ACTUAL_REFRESH_FRAME_RATE_READOUT", "    func refreshSceneFrameRateReadout("),
            ("// ACTUAL_FRAME_RATE_READOUT", "    private func updateSceneFrameRateReadout("),
            ("// ACTUAL_FRAME_RATE_COMMIT", "    func commitSceneFrameRate("),
            ("// ACTUAL_FRAME_RATE_ACTION", "    @objc private func handleSceneFrameRateSlider("),
            ("// ACTUAL_FRAME_RATE_SLIDER", "final class SceneFrameRateSlider:"),
        ):
            actual = actual.replace(marker, declaration(layout_source, signature))
        for marker, signature in (
            ("// ACTUAL_SETTINGS_OBSERVER", "    private func observeManager()"),
            ("// ACTUAL_INTERVAL_COMMIT", "    func controlTextDidEndEditing("),
            ("// ACTUAL_TIME_UNIT_SELECTION", "    private func selectTimeUnit("),
            ("// ACTUAL_PLAYBACK_RATE_ACTION", "    @objc private func handlePlaybackRateChange("),
            ("// ACTUAL_PLAYBACK_RATE_LABEL", "    private func playbackRateLabel("),
            ("// ACTUAL_PLAYBACK_RATE_SWITCH", "    @objc private func handlePlaybackRateSwitchToggle("),
        ):
            actual = actual.replace(marker, declaration(source, signature))
        with tempfile.TemporaryDirectory(prefix="mwx-settings-interval-", dir="/private/tmp") as temporary:
            work = Path(temporary)
            copied = work / "Checks.swift"; copied.write_text(actual)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *SWIFT_ISOLATION_FLAGS,
                "-warnings-as-errors", str(dependency), str(quality), str(copied), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=100)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            for region in ("en_US", "de_DE"):
                run = subprocess.run([str(binary), "-AppleLocale", region],
                    env={**os.environ, "CFFIXED_USER_HOME": temporary, "HOME": temporary},
                    capture_output=True, text=True, timeout=30)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                checks = json.loads(run.stdout)
                self.assertTrue(checks)
                for name, value in checks.items():
                    with self.subTest(region=region, name=name): self.assertIs(value, True)
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})

    def test_clear_once_and_report_only_after_all_providers_finish(self):
        controller = ROOT / "MyWallpaperX/App/SettingsWindowController.swift"
        settings = ROOT / "MyWallpaperX/Shared/Settings/AppKitSettingsView.swift"
        dependency = ROOT / "MyWallpaperX/Shared/Settings/AppSettingsPanelDependency.swift"
        fixture = ROOT / "script/tests/fixtures/SettingsCacheActionsHarness.swift"
        manager = ROOT / "MyWallpaperX/Modules/VideoLibrary/Core"
        playback = manager / "WallpaperManager+PlaybackSettings.swift"
        persistence = manager / "WallpaperManager+Persistence.swift"
        paths = [controller, settings, dependency, fixture, playback, persistence, Path(__file__).resolve()]
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
        source = source.replace("// ACTUAL_LOGIN_ITEM_SYNC", declaration(
            playback.read_text(), "    func updateLoginItemStatus("))
        reset = declaration(persistence.read_text(), "    func resetToFreshInstallState(")
        default = next(line for line in reset.splitlines() if line.strip() == "settings = defaultSettings")
        settlement = reset[reset.index("        applyEngineSettings(reloadWallpaper: false)"):]
        source = source.replace("// ACTUAL_RESET_LOGIN_SETTLEMENT",
            "func finishFreshInstallReset() {\n" + default + "\n" + settlement)
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
