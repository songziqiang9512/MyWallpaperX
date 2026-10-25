"""Real pre-service startup, saved-input recovery and AppKit main-queue delivery."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import uuid

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class LibraryCollectionsStartupTests(unittest.TestCase):
    def test_pre_service_admission_restart_and_recovery(self):
        paths = ["MyWallpaperX/Models/VideoWallpaper.swift", "MyWallpaperX/Models/WallpaperIndexStartupChanges.swift",
                 "MyWallpaperX/Models/WallpaperReference.swift", "MyWallpaperX/Core/LibraryCollections/LegacyLibrarySnapshot.swift",
                 "MyWallpaperX/Core/LibraryCollections/LibraryCollectionsMigration.swift",
                 "MyWallpaperX/Core/LibraryCollections/UserCollectionsStore.swift",
                 "MyWallpaperX/Core/LibraryCollections/LibraryCollectionsMigrationPublication.swift",
                 "MyWallpaperX/Core/LibraryCollections/LibraryCollectionsStartupAdmission.swift",
                 "script/tests/fixtures/LibraryCollectionsStartupHarness.swift"]
        hashes = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}
        with tempfile.TemporaryDirectory(prefix="mwx-collections-startup-", dir="/private/tmp") as directory:
            work = Path(directory)
            for path in paths:
                shutil.copy2(ROOT / path, work / Path(path).name)
            for filename, marker, point in [
                ("LegacyLibrarySnapshot.swift", '        try writeDurable(encoder.encode(manifest), to:', "after-input"),
                ("LibraryCollectionsMigrationPublication.swift", '        let migration = try LibraryCollectionsMigration.build(input, manifest: manifest)', "after-map"),
            ]:
                path = work / filename
                source = path.read_text()
                self.assertEqual(source.count(marker), 1)
                source = source.replace(marker, '        if ProcessInfo.processInfo.environment["MWX_STARTUP_TEST_FAULT"] == "' + point + '" { throw CocoaError(.fileWriteUnknown) }\n' + marker)
                path.write_text(source)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *[str(work / Path(p).name) for p in paths], "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            for mode in ["fresh", "restart", "reset", "capture-gap", "saved-map", "wrong-defaults",
                         "missing-stage", "missing-map", "missing-backup", "timeout", "appkit"]:
                with self.subTest(mode=mode):
                    case = work / mode
                    case.mkdir()
                    result = subprocess.run([str(binary), str(case), mode], env=dict(os.environ,
                        HOME=str(case), CFFIXED_USER_HOME=str(case), MWX_STARTUP_TEST_DOMAIN="MWX.Startup.Test." + uuid.uuid4().hex),
                        capture_output=True, text=True, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    checks = json.loads(result.stdout)
                    self.assertTrue(checks)
                    for name, passed in checks.items():
                        self.assertIs(passed, True, mode + ": " + name + "\n" + result.stdout)
                    print(json.dumps({"mode": mode, "checks": checks}, sort_keys=True))
            self.assertEqual(hashes, {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths})


if __name__ == "__main__":
    unittest.main()
