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
        def extract_function(signature):
            start = source.index(signature)
            opening = source.index('{', start)
            depth = 0
            for index in range(opening, len(source)):
                if source[index] == '{':
                    depth += 1
                elif source[index] == '}':
                    depth -= 1
                    if depth == 0:
                        return source[start:index + 1]
            raise AssertionError('unterminated Swift function: ' + signature)
        methods = []
        for name in ('publishDownloadedVersion', 'managedDownloadSnapshots', 'loadManagedDownloadSnapshots'):
            methods.append(extract_function('    func ' + name + '('))
        migration = extract_function('    private func scheduleLegacyLibraryPublicationMigration(')
        methods.append(migration.replace('    private func ', '    func ', 1))
        publisher = folder / 'Publisher.swift'
        publisher.write_text('import Foundation\nextension SteamWorkshopService {\n' + '\n'.join(methods) + '\n}')
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
            second_stage = root / 'staging' / ('job-' + 'b' * 32)
            if mode in ('concurrent-cancel', 'concurrent-success'):
                second_stage.mkdir(parents=True)
                for name, value in files.items():
                    (second_stage / name).write_bytes(value)
            index = root / 'library' / '.mywallpaperx-steam-metadata'
            index.mkdir(parents=True)
            (index / '123456.json').write_text('OLD READY POINTER')
            if mode in ('concurrent-cancel', 'concurrent-success'):
                (index / '654321.json').write_text('OLD SECOND READY POINTER')
            if mode == 'publish-failure':
                index.rename(root / 'outside-index')
                index.symlink_to(root / 'outside-index')
            (root / 'receipt.json').write_text(json.dumps({'data': {
                'receiptVersion': 2, 'contentDigest': digest(files), 'jobId': 'replaced-by-wire-fixture',
                'workshopId': '123456', 'accountSteamId': '76561198000000000', 'stagedComplete': True,
                'projectJsonPresent': True, 'manifestId': '123', 'stagingPath': str(stage),
                'stagingDevice': str(stage.stat().st_dev), 'stagingInode': str(stage.stat().st_ino),
                'secondStagingPath': str(second_stage),
                'secondStagingDevice': str(second_stage.stat().st_dev) if second_stage.exists() else None,
                'secondStagingInode': str(second_stage.stat().st_ino) if second_stage.exists() else None,
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

    def test_busy_retry_reuses_queued_identity_and_staging(self):
        self.run_case('busy-retry')

    def test_abandon_removes_failed_intent_and_only_owned_staging(self):
        self.run_case('abandon')

    def test_network_failure_persists_and_explicit_retry_reuses_job(self):
        self.run_case('network-failure')

    def test_manifest_mismatch_invalidates_and_cleans_recovery_identity(self):
        self.run_case('manifest-mismatch')

    def test_first_progress_rejects_same_name_replacement_before_binding(self):
        self.run_case('prebind-replacement')

    def test_v3_identityless_partial_does_not_resume_or_adopt_replacement(self):
        self.run_case('legacy-partial-retry')

    def test_cancel_one_of_two_active_jobs_does_not_retire_the_other(self):
        self.run_case('concurrent-cancel')

    def test_disk_full_retains_recoverable_staging_and_surfaces_action(self):
        self.run_case('disk-full')

    def test_two_successes_serialize_library_copy_and_publish_both(self):
        self.run_case('concurrent-success')

    def test_legacy_publication_migration_runs_through_service_owner(self):
        self.run_case('migration-success')

    def test_legacy_publication_waits_for_shared_copy_capacity(self):
        self.run_case('migration-capacity')

    def test_legacy_publication_cas_preserves_newer_pointer(self):
        self.run_case('migration-cas')

    def test_legacy_publication_retries_transient_type_root_failure(self):
        self.run_case('migration-retry')


if __name__ == '__main__':
    unittest.main()
