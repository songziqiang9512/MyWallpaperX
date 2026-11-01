"""Actual native host models and renderer lifetimes without selecting wallpaper.

The runtime test uses temporary publication paths and an unhosted CAContext.
It proves local ownership/failure handling, not authenticated-lock visibility.
"""
from pathlib import Path
import base64
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "requires the macOS wallpaper host")
class SystemWallpaperWireTests(unittest.TestCase):
    def run_fixture(self, fixture, extra_sources=(), runtime=False, host_protocols=False):
        sources = [ROOT / name for name in (
            "ScreenSaverSources/Native/SystemWallpaperWire.swift", "ScreenSaverSources/Native/SystemWallpaperCatalog.swift",
            "ScreenSaverSources/Native/SystemWallpaperVideoSurface.swift", "ScreenSaverSources/ScreenSaverConfiguration.swift",
            *extra_sources, f"script/tests/fixtures/{fixture}.swift",
        )]
        with tempfile.TemporaryDirectory(prefix="mwx-system-wallpaper-", dir="/private/tmp") as temporary:
            directory = Path(temporary)
            executable = directory / "check"
            if host_protocols:
                from script.tests.test_ui_library_algorithms import declaration
                owner = (ROOT / "ScreenSaverSources/Native/SystemWallpaperHostProtocol.swift").read_text()
                declarations = directory / "ActualHostDeclarations.swift"
                declarations.write_text("import ExtensionFoundation\nimport Foundation\n" + "\n".join(
                    declaration(owner, signature) for signature in (
                        "@objc(MWXWallpaperExtensionProtocol)", "@objc(MWXWallpaperAgentProtocol)",
                        "struct SystemWallpaperExtensionConfiguration:",
                    )))
                sources.append(declarations)
            build = subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-warnings-as-errors",
                "-parse-as-library", "-target", "arm64-apple-macos26.0", *map(str, sources),
                "-module-cache-path", str(directory / "modules"), "-o", str(executable)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            poster = directory / "poster.png"
            if runtime:
                poster.write_bytes(base64.b64decode(
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
            arguments = [str(directory), str(poster)] if runtime else []
            run = subprocess.run([str(executable), *arguments], capture_output=True, text=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertTrue("PASS:" in run.stdout or "SKIP: no desktop display server" in run.stdout, run.stdout)
            print(run.stdout.strip())

    def test_real_system_models(self):
        self.run_fixture("SystemWallpaperWireChecks")

    def test_real_context_lifetime_and_playback_failure(self):
        self.run_fixture("SystemWallpaperRuntimeChecks", (
            "ScreenSaverSources/Native/SystemWallpaperRuntime.swift", "ScreenSaverSources/ScreenSaverActivityClient.swift",
        ), runtime=True)

    def test_actual_xpc_initial_update_clear_and_disconnect(self):
        self.run_fixture("SystemWallpaperConnectionChecks", (
            "ScreenSaverSources/Native/SystemWallpaperRuntime.swift", "ScreenSaverSources/ScreenSaverActivityClient.swift",
            "ScreenSaverSources/Native/SystemWallpaperConnection.swift",
        ), runtime=True, host_protocols=True)
