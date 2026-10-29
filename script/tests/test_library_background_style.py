"""Production background preference, native popup/action and synchronous projection.

Shell outputs and unrelated settings-row layout are recording leaves. Native
material pixels remain a separate real-main-window acceptance responsibility.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "MyWallpaperX"


@unittest.skipUnless(sys.platform == "darwin", "real AppKit requires macOS")
class LibraryBackgroundStyleTests(unittest.TestCase):
    def test_native_setting_projects_published_value_without_rebuilding_content(self):
        settings_path = APP / "Shared/Settings/AppKitSettingsView.swift"
        layout_path = APP / "Shared/Settings/AppKitSettingsView+Layout.swift"
        composition_path = APP / "App/WallpaperLibraryWindowComposition.swift"
        fixture_path = ROOT / "script/tests/fixtures/LibraryBackgroundStyleHarness.swift"
        settings_window = APP / "App/SettingsWindowController.swift"
        tint_sources = [APP / "Shared/UI/ListThumbnailTintSource.swift", APP / "Shell/AppKitListBackgroundTint.swift"]
        models = [APP / "Models/WallpaperControls.swift", APP / "Models/WallpaperSettings.swift",
                  APP / "Models/ScreenSaverPreferences.swift", APP / "Models/WallpaperReference.swift"]
        inputs = [*models, *tint_sources, settings_window, settings_path, layout_path, composition_path, fixture_path, Path(__file__).resolve()]
        hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        settings, composition = settings_path.read_text(), composition_path.read_text()
        window_source = settings_window.read_text()
        tint_consumer = declaration(window_source, "private final class SettingsContentViewController:")
        binding = """        libraryBackgroundPopup.target = self
        libraryBackgroundPopup.action = #selector(handleLibraryBackgroundChange)"""
        click_binding = """        libraryCardClickPopup.target = self
        libraryCardClickPopup.action = #selector(handleLibraryCardClickChange)"""
        click_refresh = "        libraryCardClickPopup.selectItem(withTag: LibraryCardClickAction.allCases.firstIndex(of: settings.libraryCardClickAction) ?? 0)"
        refresh = "        libraryBackgroundPopup.selectItem(withTag: LibraryBackgroundStyle.allCases.firstIndex(of: settings.libraryBackgroundStyle) ?? 0)"
        subscription = """        manager.$settings.map(\\.libraryBackgroundStyle).removeDuplicates()
            .sink { [weak self] style in self?.applyBackgroundStyle(style) }
            .store(in: &subscriptions)"""
        for fragment, source in [(binding, settings), (click_binding, settings), (refresh, settings), (click_refresh, settings), (subscription, composition)]:
            self.assertEqual(source.count(fragment), 1)
        fragments = {
            "// ACTUAL_DISPLAY_SETUP": declaration(layout_path.read_text(), "    private func setupDisplaySection(").replace("private func", "func", 1),
            "// ACTUAL_STYLE_ACTION": declaration(settings, "    @objc private func handleLibraryBackgroundChange(").replace("private func", "func", 1),
            "// ACTUAL_CLICK_ACTION": declaration(settings, "    @objc private func handleLibraryCardClickChange(").replace("private func", "func", 1),
            "// ACTUAL_CLICK_BINDING": click_binding,
            "// ACTUAL_CLICK_REFRESH": click_refresh,
            "// ACTUAL_STYLE_BINDING": binding,
            "// ACTUAL_STYLE_REFRESH": refresh,
            "// ACTUAL_STYLE_SUBSCRIPTION": subscription,
            "// ACTUAL_STYLE_PROJECTION": declaration(composition, "    private func applyBackgroundStyle("),
            "// ACTUAL_SETTINGS_BACKGROUND": declaration(window_source, "private final class SettingsRootBackgroundView:").replace("private final class", "final class", 1),
            "// ACTUAL_SETTINGS_TINT_CONSUMER": declaration(tint_consumer, "    func updateMainWindowTint("),
            "// ACTUAL_SETTINGS_TINT_STORE": declaration(window_source, "    func updateMainWindowTint("),
            "// ACTUAL_SETTINGS_TINT_SHOW": declaration(window_source, "    func showWindow("),
            "// ACTUAL_SETTINGS_TINT_RESTORE": declaration(window_source, "    func windowDidDeminiaturize("),
            "// ACTUAL_SETTINGS_TINT_WILL_MINIATURIZE": declaration(window_source, "    func windowWillMiniaturize("),
            "// ACTUAL_SETTINGS_TINT_WILL_CLOSE": declaration(window_source, "    func windowWillClose("),
        }
        fixture = fixture_path.read_text()
        for marker, fragment in fragments.items():
            self.assertEqual(fixture.count(marker), 1)
            fixture = fixture.replace(marker, fragment)
        with tempfile.TemporaryDirectory(prefix="mwx-background-style-", dir="/private/tmp") as temporary:
            work = Path(temporary)
            copies = []
            for path in [*models, *tint_sources]:
                copy = work / path.name
                shutil.copy2(path, copy); copies.append(copy)
            actual = work / "Checks.swift"; actual.write_text(fixture)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "6",
                "-default-isolation", "MainActor", "-warnings-as-errors", *map(str, copies), str(actual),
                "-module-cache-path", str(work / "modules"), "-o", str(binary)], capture_output=True, text=True, timeout=90)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"; home.mkdir()
            result = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=30)
            if proof := os.environ.get("MWX_BACKGROUND_STYLE_PROOF_DIR"):
                destination = Path(proof); destination.mkdir(parents=True, exist_ok=True)
                (destination / "inputs.json").write_text(json.dumps(hashes, indent=2) + "\n")
                (destination / "compile.log").write_text(build.stdout + build.stderr)
                (destination / "runtime.log").write_text(result.stdout + result.stderr)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            checks = json.loads(result.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
        self.assertEqual(hashes, {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs})


if __name__ == "__main__":
    unittest.main()
