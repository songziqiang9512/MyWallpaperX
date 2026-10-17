"""Real local statistics and metadata date persistence, without the user's library."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core'


class SteamDownloadSortingTests(unittest.TestCase):
    def test_first_download_date_and_exact_local_bytes(self):
        records = (CORE / 'SteamWorkshopService+LibraryRecords.swift').read_text()
        sync = (CORE / 'SteamWorkshopService+DownloadLibrarySync.swift').read_text()
        parsing = (CORE / 'SteamWorkshopService+ParsingUtilities.swift').read_text()
        metadata = method((CORE / 'SteamWorkshopAPIModels.swift').read_text(), 'struct SteamWorkshopDownloadMetadataSnapshot')
        commit = method((CORE / 'SteamWorkshopLibraryTransaction.swift').read_text(), 'nonisolated struct SteamWorkshopLibraryCommit')
        methods = '\n'.join(method(records, signature) for signature in [
            '    nonisolated static func localDownloadStatistics(', '    nonisolated static func localCreationDate(',
            '    nonisolated static func localFileSizeBytes(', '    nonisolated static func directoryTotalBytes('])
        methods += '\n' + method(parsing, '    nonisolated static func fileSizeText(forBytes')
        methods += '\n' + method(sync, '    private func writeDownloadMetadataSnapshot(')
        template = (ROOT / 'script/tests/fixtures/SteamDownloadSortingHarness.swift').read_text()
        with tempfile.TemporaryDirectory(prefix='mwx-steam-sort-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Harness.swift'
            source.write_text(template.replace('// MODELS', commit + '\n' + metadata).replace('// METHODS', methods))
            binary = work / 'sorting'
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(source),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary), str(work / 'library')], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)


if __name__ == '__main__':
    unittest.main()
