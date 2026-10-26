"""App bindings with real relationship/query/sequence values and controlled endpoints."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class WallpaperLibraryWorkspaceTests(unittest.TestCase):
    def test_app_bindings_capture_sources_and_commit_metadata_without_owning_playback(self):
        paths = ["MyWallpaperX/Models/WallpaperReference.swift", "MyWallpaperX/Models/WallpaperContent.swift",
                 "MyWallpaperX/Models/WallpaperLibraryPage.swift",
                 "MyWallpaperX/Core/LibraryCollections/UserCollectionsStore.swift",
                 "MyWallpaperX/Core/LibraryCollections/UserCollectionsController.swift",
                 "MyWallpaperX/Core/LibraryCollections/WallpaperLibraryQuery.swift",
                 "MyWallpaperX/Core/LibraryCollections/LibraryCollectionsMigration.swift",
                 "MyWallpaperX/Core/LibraryCollections/WallpaperLibraryViewPreferencesMigration.swift",
                 "MyWallpaperX/Core/PlaybackControl/WallpaperRuntimeSwitch.swift",
                 "MyWallpaperX/Core/PlaybackControl/PlaybackSwitchTransaction.swift",
                 "MyWallpaperX/Core/PlaybackControl/WallpaperPlaybackSequence.swift",
                 "MyWallpaperX/Core/PlaybackControl/WallpaperRotationDeadline.swift",
                 "MyWallpaperX/Shell/WallpaperLibraryPresentation.swift",
                 "MyWallpaperX/Core/OnlineImages/OnlineImageModels.swift",
                 "MyWallpaperX/Core/OnlineImages/OnlineImageContentProjection.swift",
                 "script/tests/fixtures/OnlineImageLibraryAppStub.swift",
                 "MyWallpaperX/App/WallpaperLibraryWorkspace.swift",
                 "script/tests/fixtures/WallpaperLibraryWorkspaceHarness.swift"]
        extra = ["MyWallpaperX/Core/LibraryCollections/LibraryCollectionsStartupAdmission.swift",
                 "MyWallpaperX/Core/LibraryCollections/LibraryCollectionsMigrationPublication.swift",
                 "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+PlaybackControl.swift",
                 "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+PlaybackSettings.swift",
                 "script/tests/fixtures/WallpaperLibraryRotationSourceChecks.swift",
                 "MyWallpaperX/Core/PlaybackControl/ImportedVideoAutoplayGate.swift"]
        hashes = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths + extra}
        fixture = (ROOT / paths[-1]).read_text().replace("// STARTUP_OUTCOME", declaration((ROOT / extra[0]).read_text(), "nonisolated enum LibraryCollectionsStartupOutcome:"))
        fixture = fixture.replace("// PUBLICATION_VALUE", declaration((ROOT / extra[1]).read_text(), "nonisolated struct LibraryCollectionsMigrationPublicationResult:"))
        navigation, settings = (ROOT / extra[2]).read_text(), (ROOT / extra[3]).read_text()
        advance_signature = '    @discardableResult\n    func advanceLibraryPlayback('
        self.assertEqual(navigation.count(advance_signature), 1)
        rotation = '\n'.join(declaration(navigation, signature) for signature in (
            '    var librarySequenceMode:', advance_signature))
        rotation += '\n' + '\n'.join(declaration(settings, signature) for signature in (
            '    var libraryRotationInterval:', '    var libraryRotationEligible:', '    func rescheduleLibraryRotationTimer(',
            '    func stopAutoSwitchTimer(', '    func refreshAutoSwitchTimerIfNeeded('))
        for marker in ('let timer = Timer(timeInterval:', 'RunLoop.main.add(timer, forMode: .common)'):
            self.assertEqual(rotation.count(marker), 1, marker)
        self.assertEqual(fixture.count('// ACTUAL_SOURCE_ROTATION'), 1)
        rotation = rotation.replace('let timer = Timer(timeInterval:', 'let timer = WorkspaceRotationTimer(timeInterval:')
        rotation = rotation.replace('RunLoop.main.add(timer, forMode: .common)', 'WorkspaceRotationTimer.add(timer)')
        rotation = rotation.replace('CACurrentMediaTime()', 'WorkspaceRotationClock.now')
        fixture = fixture.replace('// ACTUAL_SOURCE_ROTATION', rotation)
        fixture += '\n' + (ROOT / extra[4]).read_text()
        fixture = fixture.replace("// IMPORT_GATE", declaration((ROOT / extra[5]).read_text(), "final class ImportedVideoAutoplayGate:"))
        with tempfile.TemporaryDirectory(prefix="mwx-library-workspace-", dir="/private/tmp") as directory:
            work = Path(directory)
            for path in paths[:-1]:
                if path == "MyWallpaperX/App/WallpaperLibraryWorkspace.swift":
                    source = (ROOT / path).read_text()
                    marker = "        Task { @MainActor [weak self, weak collections] in"
                    self.assertEqual(source.count(marker), 1, marker)
                    source = source.replace(marker, marker + "\n            defer { WorkspaceBackingProbe.completed += 1 }", 1)
                    (work / Path(path).name).write_text(source)
                else:
                    shutil.copy2(ROOT / path, work / Path(path).name)
            (work / "Checks.swift").write_text(fixture)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *[str(work / Path(p).name) for p in paths[:-1]], str(work / "Checks.swift"),
                "-module-cache-path", str(work / "modules"), "-o", str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary), str(work / "relationships.sqlite3")], capture_output=True, text=True, timeout=45)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                self.assertIs(passed, True, name + "\n" + run.stdout + "\n" + run.stderr)
        self.assertEqual(hashes, {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths + extra})


if __name__ == "__main__":
    unittest.main()
