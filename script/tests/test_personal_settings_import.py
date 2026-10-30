"""Real schema codec, SQLite owners and recovered source/preferences import.

Only application-support URLs, preference domain and unrelated playback leaves
are replaced. Source patch/save bodies and SQLite transactions are production.
No App window, media decode, product launch or user data is used.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid

from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class PersonalSettingsImportTests(unittest.TestCase):
    def test_schema_six_and_recovered_cross_owner_import(self):
        self.run_profile_harness()

    def test_video_sort_profile_bridges_live_view_and_recovers_without_overwriting_later_edits(self):
        self.run_profile_harness("video-sort")

    def test_repeated_paths_and_alias_retarget_use_each_import_snapshot(self):
        self.run_profile_harness("path-reuse")

    def test_only_declared_source_owners_write_and_equal_patches_still_acknowledge(self):
        self.run_profile_harness("source-persistence")

    def run_profile_harness(self, *arguments):
        sources = [ROOT / 'MyWallpaperX' / path for path in (
            'Models/WallpaperControls.swift', 'Models/WallpaperSettings.swift',
            'Models/ScreenSaverPreferences.swift',
            'Models/WallpaperReference.swift', 'Models/WallpaperContent.swift', 'Models/WallpaperLibraryPage.swift',
            'Models/PersonalSettingsPayload.swift', 'Models/VideoWallpaper.swift',
            'Core/LibraryCollections/WallpaperLibraryQuery.swift', 'Shell/WallpaperLibraryPresentation.swift',
            'Core/LibraryCollections/LibraryPersonalSettings.swift',
            'Core/LibraryCollections/UserCollectionsStore.swift', 'Core/LibraryCollections/UserCollectionsController.swift',
            'Modules/VideoLibrary/Core/WallpaperManager+ProfileSettings.swift',
            'Modules/StaticImageLibrary/Core/SILService+PersonalSettings.swift',
            'Shared/Settings/SceneHDRDisplayPreference.swift', 'Shared/Settings/SceneMediaSourcePreference.swift',
            'Core/PlaybackControl/PlaybackPerformanceProfile.swift',
            'App/PersonalSettingsImportCoordinator.swift')]
        persistence_path = ROOT / 'MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Persistence.swift'
        images_path = ROOT / 'MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift'
        index_path = ROOT / 'MyWallpaperX/Modules/VideoLibrary/Core/WallpaperIndexStore.swift'
        manager_path = ROOT / 'MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager.swift'
        removal_path = ROOT / 'MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Removal.swift'
        fixture_path = ROOT / 'script/tests/fixtures/PersonalSettingsImportHarness.swift'
        sort_fixture_path = ROOT / 'script/tests/fixtures/PersonalSettingsVideoSortHarness.swift'
        screen_saver_fixture_path = ROOT / 'script/tests/fixtures/ScreenSaverPreferencesChecks.swift'
        source_fixture_path = ROOT / 'script/tests/fixtures/PersonalSettingsSourcePersistenceChecks.swift'
        inputs = sources + [persistence_path, images_path, index_path, manager_path, removal_path, fixture_path,
                            sort_fixture_path, screen_saver_fixture_path, source_fixture_path]
        identities = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        persistence, images, manager = (p.read_text() for p in (persistence_path, images_path, manager_path))
        fixture = fixture_path.read_text()
        fixture = fixture.replace('// PRODUCTION_IMAGE_MODEL', declaration(images, 'struct SILWallpaper:'))
        fixture = fixture.replace('// PRODUCTION_IMAGE_SAVE', '\n'.join(declaration(images, marker) for marker in (
            '    func save()', '    func persistWallpaperMetadata(', '    private func reconcileMissingFilesOnLaunch(',
            '    func resumeMissingFileCleanupAfterSettingsRecovery(')))
        image_write = '        let data = try JSONEncoder().encode(values)'
        self.assertEqual(fixture.count(image_write), 1)
        fixture = fixture.replace(image_write, '        PersonalSettingsSourceWrites.shared.record("images")\n' + image_write)
        fixture = fixture.replace('// PRODUCTION_VIDEO_STATE', declaration(manager, '    struct WallpaperIndexSaveSnapshot'))
        fixture = fixture.replace('// PRODUCTION_VIDEO_SAVE', '\n'.join(declaration(persistence, marker) for marker in (
            '    private var wallpaperIndexStore:', '    func scheduleWallpapersAutoPersist(',
            '    func scheduleMissingIndexedSourceFilesScan(',
            '    func saveWallpapers(', '    private func submitPendingWallpaperIndexSave(',
            '    private func applyWallpaperIndexSaveResult(', '    func persistWallpaperIndexNow(',
            '    func persistSettingsNow(')))
        removal = removal_path.read_text()
        fixture = fixture.replace('// PRODUCTION_VIDEO_REMOVAL', '\n'.join(declaration(removal, marker) for marker in (
            '    struct RemovalRecord', '    func purgeMissingIndexedWallpapersFromLibrary(',
            '    func applyLibraryRemoval(', '    func removalRecord(')))
        index = index_path.read_text()
        index = index.replace(declaration(index, '    private init('), '''
    private init() {
        migrationReadOnly = false
        dbURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MWX_PROFILE_TEST_ROOT"]!).appendingPathComponent("video.sqlite3")
    }
''')
        video_write = '    private func saveWallpapersInternal(_ wallpapers: [VideoWallpaper]) throws {'
        self.assertEqual(index.count(video_write), 1)
        index = index.replace(video_write, video_write + '\n        PersonalSettingsSourceWrites.shared.record("video")')
        index += '''
extension WallpaperIndexStore {
    func profileQueryOnly(_ enabled: Bool) throws {
        try queue.sync { try openIfNeeded(); try exec("PRAGMA query_only=" + (enabled ? "ON" : "OFF")) }
    }
    func profileHold(entered: DispatchSemaphore, release: DispatchSemaphore) {
        queue.async { entered.signal(); release.wait() }
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='mwx-personal-settings-', dir='/private/tmp') as directory:
            work = Path(directory)
            actual = work / 'Checks.swift'; actual.write_text(fixture)
            store = work / 'WallpaperIndexStore.swift'; store.write_text(index)
            binary = work / 'checks'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *map(str, sources), str(store), str(actual), str(sort_fixture_path), str(screen_saver_fixture_path),
                str(source_fixture_path), '-module-cache-path', str(work / 'modules'),
                '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / 'home'; home.mkdir()
            run = subprocess.run([str(binary), str(work), *arguments], capture_output=True, text=True, timeout=50,
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home),
                         MWX_PROFILE_TEST_ROOT=str(work), MWX_PROFILE_TEST_DOMAIN='MWX.Profile.' + uuid.uuid4().hex))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            if arguments == ("path-reuse",):
                checks = checks["checks"]
                self.assertGreaterEqual(len(checks), 10)
            elif arguments == ("source-persistence",):
                self.assertGreaterEqual(len(checks), 12)
            else:
                self.assertGreaterEqual(len(checks), 25)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(identities, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs})


if __name__ == '__main__':
    unittest.main()
