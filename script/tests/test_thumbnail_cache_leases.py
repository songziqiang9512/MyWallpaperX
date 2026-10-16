"""Shared thumbnail interest cancels only the last consumer and preserves generations."""
import json
import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class ThumbnailCacheLeaseTests(unittest.TestCase):
    def test_shared_consumer_cancellation_and_network_slots(self):
        with tempfile.TemporaryDirectory(prefix="mwx-thumbnail-leases-", dir="/private/tmp") as temporary:
            work = pathlib.Path(temporary)
            core = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Core"
            sources = [ROOT / "MyWallpaperX/Shared/UI/ThumbnailCache.swift",
                core / "SteamWorkshopPreviewRequestCoordinator.swift", core / "SteamWorkshopPreviewImageSupport.swift",
                ROOT / "script/tests/fixtures/SteamThumbnailLeaseChecks.swift"]
            binary = work / "leases"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *map(str, sources),
                "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"
            home.mkdir()
            result = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=45)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            checks = json.loads(result.stdout)
            if proof := os.environ.get("MWX_LEASE_PROOF_DIR"):
                target = pathlib.Path(proof)
                target.mkdir(parents=True, exist_ok=True)
                (target / "checks.json").write_text(json.dumps(checks, indent=2) + "\n")
                (target / "runtime.log").write_text(result.stderr)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)
            self.assertTrue(checks)


if __name__ == "__main__":
    unittest.main()
