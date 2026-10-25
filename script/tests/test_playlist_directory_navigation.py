"""Actual Composition navigation methods over real page sessions and SQLite.

Steam, grid scrolling and the input predicate are recording leaves. The return
context, its invalidation and every navigation decision are extracted unchanged.
This gate does not instantiate the full AppKit window or its toolbar.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class PlaylistDirectoryNavigationTests(unittest.TestCase):
    def test_actual_return_context_restores_sessions_and_rejects_obsolete_actions(self):
        relative = [
            "MyWallpaperX/Models/WallpaperReference.swift",
            "MyWallpaperX/Models/WallpaperContent.swift",
            "MyWallpaperX/Models/WallpaperLibraryPage.swift",
            "MyWallpaperX/Core/LibraryCollections/UserCollectionsStore.swift",
            "MyWallpaperX/Core/LibraryCollections/UserCollectionsController.swift",
            "MyWallpaperX/Core/LibraryCollections/WallpaperLibraryQuery.swift",
            "MyWallpaperX/Shell/WallpaperLibraryPresentation.swift",
        ]
        composition = ROOT / "MyWallpaperX/App/WallpaperLibraryWindowComposition.swift"
        fixture = ROOT / "script/tests/fixtures/PlaylistDirectoryNavigationHarness.swift"
        paths = [ROOT / path for path in relative]
        observed = paths + [composition, fixture, Path(__file__),
                            ROOT / "script/tests/test_ui_library_algorithms.py",
                            ROOT / "script/tests/test_video_thumbnail_prefetch.py"]
        identities = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                      for path in observed}
        source = composition.read_text()
        signatures = [
            "    private struct DirectoryReturnContext:",
            "    private var directoryReturnContext:",
            "    func makeDirectoryReturnAction(",
            "    private func invalidateDirectoryReturnContext(",
            "    func navigate(to page:",
            "    private func navigatePage(",
            "    private func openPlaylist(",
        ]
        fragments = [declaration(source, signature) for signature in signatures]
        # The extracted invalidator is the one wired into the real render path.
        self.assertIn("invalidateDirectoryReturnContext()", declaration(source, "    private func render("))
        template = fixture.read_text()
        marker = "// ACTUAL_DIRECTORY_NAVIGATION"
        self.assertEqual(template.count(marker), 1)
        template = template.replace(marker, "\n".join(fragments))
        with tempfile.TemporaryDirectory(prefix="mwx-directory-navigation-", dir="/private/tmp") as directory:
            work = Path(directory)
            frozen = []
            for path in paths:
                copied = work / path.name
                shutil.copy2(path, copied)
                frozen.append(str(copied))
            checks_source = work / "DirectoryNavigationChecks.swift"
            checks_source.write_text(template)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors",
                "-parse-as-library", *frozen, str(checks_source), "-module-cache-path", str(work / "modules"),
                "-o", str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            isolated_home = work / "home"
            isolated_home.mkdir()
            run = subprocess.run([str(binary), str(work / "relationships.sqlite3")],
                env=dict(os.environ, HOME=str(isolated_home), CFFIXED_USER_HOME=str(isolated_home)),
                capture_output=True, text=True, timeout=40)
            diagnostic = build.stdout + build.stderr + run.stdout + run.stderr
            self.assertEqual(run.returncode, 0, diagnostic)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 15)
            print(json.dumps(checks, sort_keys=True))
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True, diagnostic)
            if output := os.environ.get("MWX_COLLECTIONS_PROOF_DIR"):
                proof = Path(output)
                proof.mkdir(parents=True, exist_ok=True)
                (proof / "directory-navigation-inputs.json").write_text(json.dumps(identities, indent=2) + "\n")
                (proof / "directory-navigation-report.json").write_text(json.dumps(checks, indent=2) + "\n")
                (proof / "directory-navigation-build.log").write_text(build.stdout + build.stderr)
                (proof / "directory-navigation-runtime.log").write_text(run.stderr)
        self.assertEqual(identities, {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                                     for path in observed})


if __name__ == "__main__":
    unittest.main()
