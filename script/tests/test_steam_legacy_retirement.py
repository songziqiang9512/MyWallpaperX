"""Execute SK6.2 retirement against injected boundaries and verify Debug isolation wiring."""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Core"


class SteamLegacyRetirementTests(unittest.TestCase):
    def test_exact_cleanup_is_idempotent_and_retries_failed_components(self):
        sources = [
            CORE / "SteamWorkshopLegacyAcquisitionRetirement.swift",
            ROOT / "script/tests/fixtures/SteamLegacyRetirementHarness.swift",
        ]
        with tempfile.TemporaryDirectory(prefix="mwx-steam-retirement-") as directory:
            executable = Path(directory) / "retirement-tests"
            subprocess.run(
                [
                    "xcrun", "swiftc", "-parse-as-library",
                    *map(str, sources),
                    "-framework", "Security",
                    "-framework", "WebKit",
                    "-o", str(executable),
                ],
                check=True,
                timeout=120,
            )
            subprocess.run([str(executable), directory], check=True, timeout=15)

    def test_isolated_debug_defaults_skip_live_retirement(self):
        service = (CORE / "SteamWorkshopService.swift").read_text()
        initializer = service[service.index("    private init()"):]
        self.assertIn("Self.isolatedDebugDefaultsSuiteName() == nil", initializer)
        self.assertIn("SteamWorkshopLegacyAcquisitionRetirement.run(defaults: defaults)", initializer)
        self.assertIn("MWX DEBUG RETIREMENT: skipped for isolated defaults suite", initializer)
        helper = service[service.index("    private static func isolatedDebugDefaultsSuiteName") :]
        self.assertIn("#if DEBUG", helper)
        self.assertIn('"--mwx-debug-user-defaults-suite"', helper)
        self.assertIn('"com.songziqiang.MyWallpaperX.Debug."', helper)


if __name__ == "__main__":
    unittest.main()
