"""Real download service methods -> real client -> fake wire -> real descriptor preparation/publication."""
import json
import pathlib
import subprocess
import tempfile
import unittest
from script.tests.test_steam_library_transaction import CORE, ROOT, SOURCES, digest


class SteamDownloadExecutionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix='mwx-steam-execution-build-')
        folder = pathlib.Path(cls.build.name)
        source = (CORE / 'SteamWorkshopService+DownloadLibrarySync.swift').read_text()
        start = source.index('    func publishDownloadedVersion(')
        end = source.index('\n    }', start) + len('\n    }')
        publisher = folder / 'Publisher.swift'
        publisher.write_text('import Foundation\nextension SteamWorkshopService {\n' + source[start:end] + '\n}')
        cls.binary = folder / 'execution'
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, SOURCES),
                        str(CORE / 'SteamWorkshopService+Downloads.swift'), str(publisher),
                        str(ROOT / 'script/tests/fixtures/SteamDownloadExecutionHarness.swift'), '-o', str(cls.binary)],
                       check=True, timeout=120)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def run_case(self, mode):
        with tempfile.TemporaryDirectory(prefix='mwx-steam-execution-', dir='/private/tmp') as directory:
            root = pathlib.Path(directory)
            stage = root / 'staging' / ('job-' + 'a' * 32)
            stage.mkdir(parents=True)
            files = {'project.json': b'{"type":"web","file":"index.html"}', 'index.html': b'hello'}
            for name, value in files.items():
                (stage / name).write_bytes(value)
            index = root / 'library' / '.mywallpaperx-steam-metadata'
            index.mkdir(parents=True)
            (index / '123456.json').write_text('OLD READY POINTER')
            if mode == 'publish-failure':
                index.rename(root / 'outside-index')
                index.symlink_to(root / 'outside-index')
            (root / 'receipt.json').write_text(json.dumps({'data': {
                'receiptVersion': 2, 'contentDigest': digest(files), 'jobId': 'replaced-by-wire-fixture',
                'workshopId': '123456', 'accountSteamId': '76561198000000000', 'stagedComplete': True,
                'projectJsonPresent': True, 'manifestId': '123', 'stagingPath': str(stage),
                'totalBytes': sum(map(len, files.values())), 'verifiedBytes': sum(map(len, files.values()))}}))
            result = subprocess.run([str(self.binary), str(root), mode], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('EXECUTION PASS: ' + mode, result.stdout)

    def test_success(self):
        self.run_case('success')

    def test_cancel_sends_exact_job_and_does_not_publish(self):
        self.run_case('cancel')

    def test_switch_rejects_old_result(self):
        self.run_case('switch')

    def test_publication_failure_preserves_old_pointer(self):
        self.run_case('publish-failure')


if __name__ == '__main__':
    unittest.main()
