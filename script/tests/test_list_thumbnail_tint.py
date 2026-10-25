"""Real tint request/controller/sampler and production first-item projections.

Media and network loaders are recording leaves; no user library or main App runs.
The opaque native system-background hosts prove projection, not product visual acceptance.
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
FIXTURES = ROOT / "script/tests/fixtures"
TINT_SOURCE = APP / "Shared/UI/ListThumbnailTintSource.swift"
TINT_CONTROLLER = APP / "Shell/AppKitListBackgroundTint.swift"
STEAM_UI = APP / "Modules/SteamWorkshop/UI"
STEAM_IMAGE_SUPPORT = APP / "Modules/SteamWorkshop/Core/SteamWorkshopPreviewImageSupport.swift"
STEAM_SOURCES = [TINT_SOURCE, STEAM_UI / "SteamWorkshopPreviewState.swift",
                 STEAM_UI / "SteamWorkshopListThumbnailTint.swift",
                 FIXTURES / "ListThumbnailTintSteamLeaves.swift"]


def steam_source_projection():
    """The source-choice algorithm stays production; only cache/decode leaves vary."""
    path = APP / "Modules/SteamWorkshop/Core/SteamWorkshopPreviewSource.swift"
    return path, "import AppKit\n" + declaration(path.read_text(), "func steamWorkshopPreviewSources(") + "\n" + declaration(
        STEAM_IMAGE_SUPPORT.read_text(), "nonisolated func steamWorkshopPreviewImageIsUsable(")


@unittest.skipUnless(sys.platform == "darwin", "real AppKit requires macOS")
class ListThumbnailTintTests(unittest.TestCase):
    def run_case(self, name, sources, fragments=None, originals=()):
        paths = [*sources, *originals, Path(__file__).resolve()]
        identities = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        with tempfile.TemporaryDirectory(prefix="mwx-list-tint-", dir="/private/tmp") as temporary:
            work = Path(temporary)
            frozen = work / "sources"; frozen.mkdir()
            copies = []
            for path in sources:
                copy = frozen / path.name
                shutil.copy2(path, copy); copies.append(copy)
            if fragments:
                actual = frozen / "ActualProjection.swift"
                actual.write_text(fragments); copies.append(actual)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "6",
                "-default-isolation", "MainActor", *map(str, copies),
                "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"; home.mkdir()
            result = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads(result.stdout)
            if destination := os.environ.get("MWX_LIST_TINT_PROOF_DIR"):
                proof = Path(destination); proof.mkdir(parents=True, exist_ok=True)
                (proof / (name + "-inputs.json")).write_text(json.dumps(identities, indent=2) + "\n")
                (proof / (name + "-report.json")).write_text(json.dumps(report, indent=2) + "\n")
                (proof / (name + "-compile.log")).write_text(build.stdout + build.stderr)
                (proof / (name + "-runtime.log")).write_text(result.stderr)
            checks = report["checks"]
            self.assertTrue(checks)
            for check, passed in checks.items():
                with self.subTest(check=check): self.assertIs(passed, True)
            self.assertEqual(identities, {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})
            return report

    def test_real_source_controller_and_sampler(self):
        self.run_case("controller", [TINT_SOURCE, TINT_CONTROLLER, FIXTURES / "ListThumbnailTintChecks.swift"])

    def test_real_window_animation_and_passive_roots(self):
        self.run_case("animation", [TINT_SOURCE, TINT_CONTROLLER, FIXTURES / "ListThumbnailTintAnimationChecks.swift"])

    def test_live_remote_first_item_projections(self):
        paths = {
            "ONLINE": APP / "Modules/OnlineLibrary/UI/AppKitOLBrowserGridView.swift",
            "STEAM": STEAM_UI / "AppKitSteamWorkshopBrowserGridView.swift",
        }
        template = (FIXTURES / "ListThumbnailTintProjectionChecks.swift").read_text()
        for key, path in paths.items():
            fragment = declaration(path.read_text(), "    private func publishListThumbnailTint(")
            marker = "// " + key + "_METHODS"
            self.assertEqual(template.count(marker), 1)
            template = template.replace(marker, fragment.replace("private func ", "func "))
        preview_path, preview = steam_source_projection()
        self.run_case("projections", [*STEAM_SOURCES, FIXTURES / "ListThumbnailTintCacheLeaves.swift"],
            fragments=template + "\n" + preview, originals=[*paths.values(), preview_path, STEAM_IMAGE_SUPPORT,
                FIXTURES / "ListThumbnailTintProjectionChecks.swift"])


if __name__ == "__main__":
    unittest.main()
