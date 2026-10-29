"""Headless behavior of the actual screen-saver publication and socket owners.

The publisher, configuration codec and VideoStillFrame are compiled unchanged.
The fixture uses isolated files and a FileManager delegate to order real copies;
no engine value declarations or replacement publication owner are supplied.
Installation uses a real isolated, locally signed bundle to check code identity
changes at an unchanged version without substituting an identity provider.
The thumbnail gate executes the actual UI request/fallback/cancel methods with
controlled source and disk completion leaves; it does not render UI pixels.
The activity gate records only the policy-effect call; it compiles the actual
client/monitor, verifies readiness in an independent client process, and leaves
OR policy assertions to the existing policy gate.
It launches no product App, visible window, WebView, renderer or system saver.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "AVFoundation/AppKit require macOS")
class ScreenSaverIntegrationTests(unittest.TestCase):
    def test_configuration_thumbnail_identity_and_cancellation(self):
        sources = [ROOT / path for path in (
            "MyWallpaperX/Models/WallpaperReference.swift", "MyWallpaperX/Models/WallpaperContent.swift",
            "MyWallpaperX/Models/ScreenSaverPreferences.swift", "ScreenSaverSources/ScreenSaverConfiguration.swift",
        )]
        controller = ROOT / "MyWallpaperX/App/ScreenSaverWindowController.swift"
        artwork = ROOT / "MyWallpaperX/App/WallpaperLibraryArtworkProvider.swift"
        cache = ROOT / "MyWallpaperX/Shared/UI/ThumbnailCache.swift"
        fixture = ROOT / "script/tests/fixtures/ScreenSaverThumbnailChecks.swift"
        inputs = [*sources, controller, artwork, cache, fixture, Path(__file__).resolve()]
        identities = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        text = fixture.read_text().replace("// ACTUAL_ARTWORK_IDENTITY", declaration(artwork.read_text(), "    struct Identity:"))
        for marker, signature in (("// ACTUAL_REFRESH_ARTWORK", "    private func refreshArtwork("),
                                  ("// ACTUAL_STOP_ARTWORK", "    private func stopArtwork(")):
            text = text.replace(marker, declaration(controller.read_text(), signature).replace("private func", "func", 1))
        text = "import AppKit\n" + "\n".join(declaration(cache.read_text(), signature) for signature in (
            "nonisolated protocol ThumbnailCacheLoadCancellation:", "nonisolated final class ThumbnailCacheRequestCancellation:")) + "\n" + text
        with tempfile.TemporaryDirectory(prefix="mwx-screen-saver-thumbnails-", dir="/private/tmp") as temporary:
            work = Path(temporary)
            source = work / "Checks.swift"; source.write_text(text)
            binary = work / "checks"
            built = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-parse-as-library",
                *map(str, sources), str(source), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stderr)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(identities, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs})

    def test_real_activity_clients_monitor_restart_and_eof(self):
        sources = [ROOT / path for path in (
            "MyWallpaperX/Core/System/ScreenSaverActivityMonitor.swift",
            "ScreenSaverSources/ScreenSaverActivityClient.swift",
            "script/tests/fixtures/ScreenSaverActivityChecks.swift",
        )]
        configuration = ROOT / "ScreenSaverSources/ScreenSaverConfiguration.swift"
        inputs = [*sources, configuration, Path(__file__).resolve()]
        identities = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        paths = "import Foundation\nimport Darwin\n" + declaration(
            configuration.read_text(), "nonisolated enum ScreenSaverPaths") + "\n"
        with tempfile.TemporaryDirectory(prefix="mwx-screen-saver-activity-", dir="/private/tmp") as temporary:
            work = Path(temporary)
            values = work / "ProductionPaths.swift"
            values.write_text(paths)
            binary = work / "checks"
            built = subprocess.run([
                "xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-parse-as-library",
                *map(str, sources), str(values), "-module-cache-path", str(work / "modules"),
                "-o", str(binary),
            ], capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            home = work / "home"
            scratch = work / "tmp"
            home.mkdir(); scratch.mkdir()
            run = subprocess.run([str(binary), str(work / "cases")], cwd=work,
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(scratch) + "/"),
                capture_output=True, text=True, timeout=35)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks, "activity fixture returned no observations")
            if run.stderr.strip():
                print(run.stderr.strip())
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True, run.stderr)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(identities, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs})

    def test_real_video_publication_cancellation_leases_and_installation(self):
        sources = [ROOT / path for path in (
            "MyWallpaperX/Core/System/ScreenSaverIntegration.swift",
            "MyWallpaperX/Shared/VideoStillFrame.swift",
            "ScreenSaverSources/ScreenSaverConfiguration.swift",
            "script/tests/fixtures/ScreenSaverIntegrationChecks.swift",
        )]
        inputs = [*sources, Path(__file__).resolve()]
        identities = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        with tempfile.TemporaryDirectory(prefix="mwx-screen-saver-integration-", dir="/private/tmp") as temporary:
            work = Path(temporary)
            binary = work / "checks"
            built = subprocess.run([
                "xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-parse-as-library",
                *map(str, sources), "-module-cache-path", str(work / "modules"),
                "-o", str(binary),
            ], capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            home = work / "home"
            scratch = work / "tmp"
            home.mkdir(); scratch.mkdir()
            run = subprocess.run([str(binary), str(work / "cases")], cwd=work,
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(scratch) + "/"),
                capture_output=True, text=True, timeout=75)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks, "fixture returned no observations")
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True, run.stderr)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(identities, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs})


if __name__ == "__main__":
    unittest.main()
