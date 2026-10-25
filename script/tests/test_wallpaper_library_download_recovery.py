"""Native recovery menu with real relationship/query identity and controlled source leaves.

No window, App process, browser, real download, credential or renderer is used.
This proves dispatch and rejection, not network availability of a remote work.
"""
import fcntl
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]


class WallpaperLibraryDownloadRecoveryTests(unittest.TestCase):
    def test_missing_download_relationships_recover_via_original_source_owners(self):
        paths = [
            "MyWallpaperX/Models/WallpaperReference.swift", "MyWallpaperX/Models/WallpaperContent.swift",
            "MyWallpaperX/Models/WallpaperLibraryPage.swift", "MyWallpaperX/Core/LibraryCollections/WallpaperLibraryQuery.swift",
            "MyWallpaperX/Shared/Components/ActionMenuItem.swift", "MyWallpaperX/App/WallpaperLibraryDownloadRecovery.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Downloads.swift",
            "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Integration.swift",
            "MyWallpaperX/Modules/OnlineLibrary/Core/OnlineLibraryService+SourcePage.swift",
            "MyWallpaperX/App/WallpaperLibraryCommands.swift",
            "MyWallpaperX/Core/PlaybackControl/WallpaperRuntimeSwitch.swift",
            "MyWallpaperX/Core/PlaybackControl/PlaybackSwitchTransaction.swift",
            "MyWallpaperX/Core/PlaybackControl/WallpaperPlaybackSequence.swift",
            "script/tests/fixtures/WallpaperLibraryDownloadRecoveryHarness.swift", "script/tests/test_wallpaper_library_download_recovery.py",
        ]
        before = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in paths}
        fixture = (ROOT / paths[-2]).read_text()
        fixture = fixture.replace("// ACTUAL_STEAM_ID_VALIDATION", declaration((ROOT / paths[6]).read_text(), "    func isValidWorkshopItemID("))
        fixture = fixture.replace("// ACTUAL_STEAM_RECOVERY_URL", declaration((ROOT / paths[7]).read_text(), "    func recoveryWorkshopDetailURL("))
        fixture = fixture.replace("// ACTUAL_PIXABAY_SOURCE_URL", declaration((ROOT / paths[8]).read_text(), "    static func videoSourcePageURL("))
        commands = (ROOT / paths[9]).read_text()
        fixture = fixture.replace("// ACTUAL_PRIMARY_FACTORY", "\n".join(declaration(commands, signature) for signature in (
            "    func makePrimaryAction(", "    func makeApplyAction(", "    func stop(")))
        with tempfile.TemporaryDirectory(prefix="mwx-download-recovery-", dir="/private/tmp") as directory:
            work = Path(directory)
            sources = []
            for path in paths[:6] + paths[10:13]:
                target = work / Path(path).name
                shutil.copy2(ROOT / path, target)
                sources.append(str(target))
            harness = work / "Checks.swift"
            harness.write_text(fixture)
            binary = work / "checks"
            with open("/private/tmp/mywallpaperx-checkpoint-build.flock", "a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                build = subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-default-isolation", "MainActor",
                    *sources, str(harness), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                    capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 20)
            for name, passed in checks.items():
                self.assertIs(passed, True, name)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(before, {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in paths})


if __name__ == "__main__":
    unittest.main()
