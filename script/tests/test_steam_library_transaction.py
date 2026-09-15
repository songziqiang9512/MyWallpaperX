"""Real descriptor copy and metadata publication; independent Python digest fixtures, no Steam or user library."""
import hashlib
import json
import os
import pathlib
import struct
import subprocess
import tempfile
import unicodedata
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORE = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core'
SOURCES = [ROOT / 'MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift',
           ROOT / 'MyWallpaperX/Core/DaemonKit/DaemonProcessTransport.swift',
           ROOT / 'MyWallpaperX/Core/PlaybackControl/PlaybackResourceLifetime.swift',
           *[CORE / name for name in ('SteamServiceProtocol.swift', 'SteamServiceClient.swift',
             'SteamWorkshopQueryClient.swift', 'SteamWorkshopLibraryTransaction.swift',
             'SteamWorkshopLibraryVersionLease.swift', 'SteamWorkshopJobStore.swift',
             'SteamWorkshopDownloadProgress.swift')]]
HARNESS = r'''
import Foundation
@main struct Harness {
    @MainActor static func main() async throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1])
        let mode = CommandLine.arguments[2]
        if mode == "capacity" {
            let gib = Int64(1024 * 1024 * 1024)
            let reserve = Int64(SteamWorkshopLibraryTransaction.diskSafetyReserveBytes)
            precondition(SteamWorkshopLibraryTransaction.maximumRetainedBytesBeforeAdmissions == 16 * 1024 * 1024 * 1024)
            precondition(SteamWorkshopLibraryTransaction.canReserveDiskBytes(
                required: 8 * gib, available: 16 * gib + reserve, alreadyReserved: 8 * gib))
            precondition(!SteamWorkshopLibraryTransaction.canReserveDiskBytes(
                required: 8 * gib, available: 16 * gib + reserve - 1, alreadyReserved: 8 * gib))
            precondition(!SteamWorkshopLibraryTransaction.canReserveDiskBytes(
                required: -1, available: Int64.max, alreadyReserved: 0))
            let available = try SteamWorkshopLibraryTransaction.availableDiskBytes(
                at: base.appendingPathComponent("capacity-root", isDirectory: true))
            precondition(available > 0)
            let sameFileSystem = try SteamWorkshopLibraryTransaction.areOnSameFileSystem(
                base.appendingPathComponent("capacity-root", isDirectory: true),
                base.appendingPathComponent("capacity-peer", isDirectory: true))
            precondition(sameFileSystem)
            print("CAPACITY")
            return
        }
        if mode == "cleanup" || mode == "cleanup-replaced" {
            let root = base.appendingPathComponent("staging", isDirectory: true)
            let target = root.appendingPathComponent("job-" + String(repeating: "c", count: 32), isDirectory: true)
            if mode == "cleanup" {
                try SteamWorkshopLibraryTransaction.removeStagingLease(stagingURL: target, stagingRoot: root)
                precondition(!FileManager.default.fileExists(atPath: target.path))
                try SteamWorkshopLibraryTransaction.removeStagingLease(stagingURL: target, stagingRoot: root)
                let sentinel = try String(contentsOf: base.appendingPathComponent("outside/sentinel"), encoding: .utf8)
                precondition(sentinel == "untouched")
                print("CLEANED")
            } else {
                do {
                    try SteamWorkshopLibraryTransaction.removeStagingLease(stagingURL: target, stagingRoot: root)
                    fatalError("replaced staging lease was removed")
                } catch {
                    precondition(FileManager.default.fileExists(atPath: target.path))
                    let sentinel = try String(contentsOf: base.appendingPathComponent("outside/sentinel"), encoding: .utf8)
                    precondition(sentinel == "untouched")
                    print("REJECTED REPLACEMENT")
                }
            }
            return
        }
        if mode == "reclaim" {
            let library = base.appendingPathComponent("library")
            let retained = Set(CommandLine.arguments.dropFirst(3))
            let result = try SteamWorkshopLibraryTransaction.reclaimVersions(
                libraryRoot: library,
                retaining: retained,
                minimumAge: 3_600
            )
            precondition(result.removedDirectoryNames.count == 1)
            if let protected = retained.first {
                let content = library.appendingPathComponent(".mywallpaperx-steam-versions")
                    .appendingPathComponent(protected).appendingPathComponent("content/index.html")
                precondition(SteamWorkshopLibraryTransaction.versionDirectoryName(
                    containing: content,
                    libraryRoot: library
                ) == protected)
            }
            print("RECLAIMED: \(result.removedDirectoryNames.joined(separator: ","))")
            return
        }
        let frame = try SteamServiceFrameDecoder.decode(Data(contentsOf: base.appendingPathComponent("receipt.json"))).get()
        let receipt = try SteamWorkshopStagedReceipt(frame: frame, jobId: "test-job-1", workshopId: "123456",
            accountSteamId: "76561198000000000", accountEpoch: 7, stagingRoot: base.appendingPathComponent("staging").path)
        let library = base.appendingPathComponent("library")
        do {
            let task = Task.detached { try SteamWorkshopLibraryTransaction.prepare(receipt: receipt, attempt: 1, libraryRoot: library) }
            if mode == "cancel" { task.cancel() }
            let commit = try await task.value
            if mode == "cancel" { fatalError("cancelled prepare succeeded") }
            try verifyJobRecovery(frame: frame, commit: commit, base: base)
            let leases = SteamWorkshopLibraryVersionLeaseRegistry()
            let dependencyVersion = "11111111-1111-4111-8111-111111111111"
            var lifetime: PlaybackResourceLifetime? = leases.acquire(
                directoryNames: [commit.directoryName, dependencyVersion]
            )
            precondition(leases.protectedDirectoryNames() == [commit.directoryName, dependencyVersion])
            lifetime = nil
            withExtendedLifetime(lifetime) {}
            precondition(leases.protectedDirectoryNames().isEmpty)
            try JSONEncoder().encode(commit).write(to: base.appendingPathComponent("prepared.json"))
            if mode != "prepare-only" {
                try SteamWorkshopLibraryTransaction.publish(metadata: JSONEncoder().encode(commit), itemID: "123456", libraryRoot: library)
                precondition(SteamWorkshopLibraryTransaction.isAvailable(commit, libraryRoot: library))
                let outside = base.appendingPathComponent("outside-metadata.json")
                try JSONEncoder().encode(commit).write(to: outside)
                try FileManager.default.createSymbolicLink(
                    at: library.appendingPathComponent(".mywallpaperx-steam-metadata/654321.json"),
                    withDestinationURL: outside
                )
                let index = try SteamWorkshopLibraryTransaction.publishedMetadata(libraryRoot: library)
                precondition(index.keys.sorted() == ["123456"])
                let decoded = try JSONDecoder().decode(
                    SteamWorkshopLibraryCommit.self,
                    from: index["123456"]!
                )
                precondition(decoded == commit)
            }
            print("ACCEPTED")
        } catch {
            print("REJECTED: \(error.localizedDescription)")
        }
    }

    @MainActor static func verifyJobRecovery(frame: SteamServiceFrame, commit: SteamWorkshopLibraryCommit, base: URL) throws {
        let url = base.appendingPathComponent("jobs.json")
        let store = SteamDownloadJobStore(persistenceURL: url)
        let job = store.enqueue(workshopItemId: "123456", title: "test", accountSteamId: "76561198000000000").job
        precondition(store.apply(.started, toID: job.id) != nil)
        let allocatedPath = base.appendingPathComponent("staging/job-" + String(repeating: "a", count: 32)).path
        precondition(store.apply(.stagingAllocated(path: allocatedPath, manifestId: "123"), toID: job.id)?.stagingPath == allocatedPath)
        precondition(store.apply(.stagingAllocated(
            path: base.appendingPathComponent("outside").path, manifestId: "123"), toID: job.id) == nil,
            "one attempt cannot adopt a second staging path")
        let allocated = SteamDownloadJobStore(persistenceURL: url)
        precondition(allocated.job(id: job.id)?.state == .failed
            && allocated.job(id: job.id)?.stagingPath == allocatedPath
            && allocated.job(id: job.id)?.stagingManifestId == "123"
            && allocated.job(id: job.id)?.failureMessage?.contains("校验并恢复") == true,
            "manifest-bound staging must survive a crash behind explicit retry")
        let key = job.id + "-1"
        var frame = frame
        var data = frame.root["data"]!.objectValue!
        data["jobId"] = .string(key)
        frame.root["data"] = .object(data)
        let receipt = try SteamWorkshopStagedReceipt(frame: frame, jobId: key, workshopId: job.workshopItemId,
            accountSteamId: job.accountSteamId, accountEpoch: 7, stagingRoot: base.appendingPathComponent("staging").path)
        precondition(store.apply(.staged(receipt), toID: job.id) != nil)
        let staged = SteamDownloadJobStore(persistenceURL: url)
        precondition(staged.job(id: job.id)?.state == .staged && staged.job(id: job.id)?.receipt == receipt)
        precondition(staged.enqueue(workshopItemId: "123456", title: "duplicate", accountSteamId: job.accountSteamId).isNew == false)
        let prepared = SteamWorkshopLibraryCommit(version: 1, workshopId: "123456", jobId: key, attempt: 1,
            directoryName: commit.directoryName, manifestId: commit.manifestId, contentDigest: commit.contentDigest,
            contentType: commit.contentType, entryPath: commit.entryPath, committedAt: commit.committedAt)
        precondition(staged.apply(.committing(prepared), toID: job.id) != nil)
        let persisted = try Data(contentsOf: url)
        let afterCrash = SteamDownloadJobStore(persistenceURL: url)
        afterCrash.reconcileInterruptedCommits(published: ["123456": prepared])
        precondition(afterCrash.job(id: job.id)?.state == .completed, "published record settles interrupted job")
        precondition(afterCrash.history.count == 1
            && afterCrash.history[0].outcome == .completed
            && afterCrash.history[0].recordID == "123456"
            && afterCrash.history[0].attempt == 1,
            "completed terminal must persist one library reference")
        precondition(afterCrash.apply(.completed, toID: job.id) == nil, "duplicate terminal rejected")
        let afterCompletedRestart = SteamDownloadJobStore(persistenceURL: url)
        precondition(afterCompletedRestart.history.count == 1
            && afterCompletedRestart.history[0].id == afterCrash.history[0].id,
            "completed restart must not duplicate history")
        try persisted.write(to: url)
        let beforePublishCrash = SteamDownloadJobStore(persistenceURL: url)
        beforePublishCrash.reconcileInterruptedCommits(published: [:])
        precondition(beforePublishCrash.job(id: job.id)?.state == .failed && beforePublishCrash.job(id: job.id)?.receipt != nil)
        try persisted.write(to: url)
        let unrelated = SteamDownloadJobStore(persistenceURL: url)
        unrelated.reconcileInterruptedCommits(published: ["123456": commit])
        precondition(unrelated.job(id: job.id)?.state == .failed, "different job cannot settle transaction")
        let retryURL = base.appendingPathComponent("retry.json")
        let failed = SteamDownloadJobStore(persistenceURL: retryURL)
        let failedJob = failed.enqueue(
            workshopItemId: "777777", title: "retry", accountSteamId: job.accountSteamId).job
        precondition(failed.apply(.started, toID: failedJob.id) != nil)
        precondition(failed.apply(.stagingAllocated(path: allocatedPath, manifestId: "123"), toID: failedJob.id) != nil)
        precondition(failed.apply(.failed("network"), toID: failedJob.id) != nil)
        let failedReload = SteamDownloadJobStore(persistenceURL: retryURL)
        let durableFailure = failedReload.failedJob(
            forWorkshopItemId: failedJob.workshopItemId, accountSteamId: job.accountSteamId)
        precondition(durableFailure?.id == failedJob.id && durableFailure?.stagingPath == allocatedPath,
            "pre-receipt failure and owned staging identity must persist")
        precondition(failedReload.failedJob(
            forWorkshopItemId: failedJob.workshopItemId, accountSteamId: "other") == nil,
            "another account cannot adopt a failed job")
        let retried = failedReload.apply(.resumed, toID: durableFailure!.id)
        precondition(retried?.id == failedJob.id && retried?.attempt == 2
            && retried?.stagingPath == allocatedPath && retried?.stagingManifestId == "123",
            "explicit retry keeps logical identity and its manifest-bound staging lease")
        let failureURL = base.appendingPathComponent("save-failure.json")
        let failure = SteamDownloadJobStore(persistenceURL: failureURL)
        let pending = failure.enqueue(workshopItemId: "654321", title: "test", accountSteamId: job.accountSteamId).job
        let second = failure.enqueue(workshopItemId: "654322", title: "test", accountSteamId: job.accountSteamId).job
        let other = failure.enqueue(workshopItemId: "654323", title: "other", accountSteamId: "other").job
        try FileManager.default.removeItem(at: failureURL)
        try FileManager.default.createDirectory(at: failureURL, withIntermediateDirectories: false)
        precondition(failure.apply(.started, toID: pending.id) == nil && failure.job(id: pending.id)?.state == .queued,
            "failed persistence cannot advance executable state")
        precondition(failure.cancelAll(forAccount: job.accountSteamId).isEmpty)
        precondition(failure.job(id: pending.id)?.state == .queued && failure.job(id: second.id)?.state == .queued)
        try FileManager.default.removeItem(at: failureURL)
        precondition(Set(failure.cancelAll(forAccount: job.accountSteamId)) == Set(["654321", "654322"]))
        precondition(failure.job(id: other.id)?.state == .queued)
        let reloaded = SteamDownloadJobStore(persistenceURL: failureURL)
        precondition(reloaded.activeJobs.map(\.id) == [other.id], "batch persisted without cancelled jobs")
    }
}
'''


def digest(files):
    rows = sorted(((unicodedata.normalize('NFC', path).encode(), value) for path, value in files.items()))
    h = hashlib.sha256()
    for path, value in rows:
        h.update(struct.pack('<I', len(path)) + path + struct.pack('<Q', len(value)) + hashlib.sha256(value).digest())
    return h.hexdigest()


class SteamLibraryTransactionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix='mwx-steam-transaction-build-')
        folder = pathlib.Path(cls.build.name)
        harness = folder / 'Harness.swift'
        harness.write_text(HARNESS)
        cls.binary = folder / 'transaction'
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, SOURCES), str(harness), '-o', str(cls.binary)],
                       check=True, timeout=120)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def scenario(self, files=None, mutate=None, mode='publish', accepted=True):
        files = files or {'project.json': b'{"type":"web","file":"index.html"}', 'index.html': b'<h1>safe</h1>',
                          'assets/e\u0301.txt': b'UTF8', 'empty': b''}
        with tempfile.TemporaryDirectory(prefix='mwx-steam-transaction-', dir='/private/tmp') as temporary:
            root = pathlib.Path(temporary)
            stage = root / 'staging' / ('job-' + 'a' * 32)
            stage.mkdir(parents=True)
            for name, data in files.items():
                path = stage / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            index = root / 'library' / '.mywallpaperx-steam-metadata'
            index.mkdir(parents=True)
            marker = index / '123456.json'
            marker.write_bytes(b'OLD READY POINTER')
            old = root / 'library' / 'Web' / '123456' / 'index.html'
            old.parent.mkdir(parents=True)
            old.write_bytes(b'OLD PLAYING CONTENT')
            receipt = {'v': 1, 'type': 'result', 'requestId': 'r', 'ok': True, 'accountEpoch': 7,
                       'data': {'receiptVersion': 2, 'contentDigest': digest(files), 'jobId': 'test-job-1',
                       'workshopId': '123456', 'accountSteamId': '76561198000000000', 'stagedComplete': True,
                       'projectJsonPresent': True, 'manifestId': '123', 'stagingPath': str(stage),
                       'verifiedBytes': sum(map(len, files.values())), 'totalBytes': sum(map(len, files.values()))}}
            (root / 'receipt.json').write_text(json.dumps(receipt))
            if mutate:
                mutate(root, stage)
            result = subprocess.run([str(self.binary), str(root), mode], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('ACCEPTED' if accepted else 'REJECTED', result.stdout)
            self.assertEqual(old.read_bytes(), b'OLD PLAYING CONTENT')
            if not accepted or mode == 'prepare-only':
                self.assertEqual(marker.read_bytes(), b'OLD READY POINTER')
            else:
                commit = json.loads(marker.read_bytes())
                content = root / 'library' / '.mywallpaperx-steam-versions' / commit['directoryName'] / 'content'
                for name, value in files.items():
                    self.assertEqual((content / name).read_bytes(), value)
                self.assertEqual(commit['contentDigest'], digest(files))
            return result.stdout

    def test_publish_and_preserve_old_playback(self):
        self.scenario()

    def test_crash_before_publication_keeps_old_pointer(self):
        self.scenario(mode='prepare-only')

    def test_cancel_before_copy(self):
        self.scenario(mode='cancel', accepted=False)

    def test_same_length_corruption(self):
        self.scenario(mutate=lambda r, s: (s / 'index.html').write_bytes(b'x' * len(b'<h1>safe</h1>')), accepted=False)

    def test_truncation(self):
        self.scenario(mutate=lambda r, s: (s / 'index.html').write_bytes(b''), accepted=False)

    def test_extra_file(self):
        self.scenario(mutate=lambda r, s: (s / 'extra').write_bytes(b'extra'), accepted=False)

    def test_missing_file(self):
        self.scenario(mutate=lambda r, s: (s / 'index.html').unlink(), accepted=False)

    def test_symlink_file(self):
        def mutate(root, stage):
            (root / 'outside').write_bytes(b'untouched')
            (stage / 'index.html').unlink()
            (stage / 'index.html').symlink_to(root / 'outside')
        self.scenario(mutate=mutate, accepted=False)

    def test_hardlink(self):
        self.scenario(mutate=lambda r, s: os.link(s / 'index.html', r / 'hardlink'), accepted=False)

    def test_fifo(self):
        def mutate(root, stage):
            (stage / 'index.html').unlink()
            os.mkfifo(stage / 'index.html')
        self.scenario(mutate=mutate, accepted=False)

    def test_ancestor_symlink(self):
        def mutate(root, stage):
            (root / 'staging').rename(root / 'other')
            (root / 'staging').symlink_to(root / 'other')
        self.scenario(mutate=mutate, accepted=False)

    def test_publish_parent_symlink(self):
        def mutate(root, stage):
            index = root / 'library' / '.mywallpaperx-steam-metadata'
            index.rename(root / 'outside-index')
            index.symlink_to(root / 'outside-index')
        self.scenario(mutate=mutate, accepted=False)

    def test_retained_disk_budget(self):
        def mutate(root, stage):
            versions = root / 'library' / '.mywallpaperx-steam-versions'
            versions.mkdir()
            with (versions / 'retained').open('wb') as f:
                f.truncate(17 * 1024 * 1024 * 1024)  # sparse, isolated fixture; no 17GiB payload allocation
        self.scenario(mutate=mutate, accepted=False)

    def test_concurrent_disk_reservation_boundary(self):
        with tempfile.TemporaryDirectory(prefix='mwx-steam-capacity-', dir='/private/tmp') as temporary:
            result = subprocess.run([str(self.binary), temporary, 'capacity'], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('CAPACITY', result.stdout)

    def test_retained_directory_budget(self):
        def mutate(root, stage):
            versions = root / 'library' / '.mywallpaperx-steam-versions'
            versions.mkdir()
            for i in range(64):
                (versions / str(i)).mkdir()
        self.scenario(mutate=mutate, accepted=False)

    def test_reclaim_only_old_unreferenced_uuid_version(self):
        with tempfile.TemporaryDirectory(prefix='mwx-steam-reclaim-', dir='/private/tmp') as temporary:
            root = pathlib.Path(temporary)
            versions = root / 'library' / '.mywallpaperx-steam-versions'
            versions.mkdir(parents=True)
            retained = '11111111-1111-4111-8111-111111111111'
            old = '22222222-2222-4222-8222-222222222222'
            young = '33333333-3333-4333-8333-333333333333'
            linked = '44444444-4444-4444-8444-444444444444'
            for name in (retained, old, young):
                content = versions / name / 'content'
                content.mkdir(parents=True)
                (content / 'index.html').write_text(name)
            unknown = versions / 'owned-but-unknown'
            unknown.mkdir()
            outside = root / 'outside'
            outside.mkdir()
            (outside / 'sentinel').write_text('untouched')
            (versions / linked).symlink_to(outside, target_is_directory=True)
            old_stamp = 1_600_000_000
            for name in (retained, old):
                os.utime(versions / name, (old_stamp, old_stamp))

            result = subprocess.run(
                [str(self.binary), str(root), 'reclaim', retained],
                capture_output=True,
                text=True,
                timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(old, result.stdout)
            self.assertFalse((versions / old).exists())
            self.assertTrue((versions / retained).is_dir())
            self.assertTrue((versions / young).is_dir())
            self.assertTrue(unknown.is_dir())
            self.assertTrue((versions / linked).is_symlink())
            self.assertEqual((outside / 'sentinel').read_text(), 'untouched')

    def test_remove_only_exact_owned_staging_lease(self):
        with tempfile.TemporaryDirectory(prefix='mwx-steam-staging-cleanup-', dir='/private/tmp') as temporary:
            root = pathlib.Path(temporary)
            outside = root / 'outside'
            outside.mkdir()
            (outside / 'sentinel').write_text('untouched')
            target = root / 'staging' / ('job-' + 'c' * 32)
            (target / 'nested').mkdir(parents=True)
            (target / 'nested' / 'data').write_text('partial')
            (target / 'inside-link').symlink_to(outside / 'sentinel')
            sibling = root / 'staging' / ('job-' + 'd' * 32)
            sibling.mkdir()
            (sibling / 'keep').write_text('keep')

            result = subprocess.run(
                [str(self.binary), str(root), 'cleanup'], capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('CLEANED', result.stdout)
            self.assertFalse(target.exists())
            self.assertEqual((outside / 'sentinel').read_text(), 'untouched')
            self.assertEqual((sibling / 'keep').read_text(), 'keep')

    def test_replaced_staging_lease_is_not_adopted_for_cleanup(self):
        with tempfile.TemporaryDirectory(prefix='mwx-steam-staging-replaced-', dir='/private/tmp') as temporary:
            root = pathlib.Path(temporary)
            outside = root / 'outside'
            outside.mkdir()
            (outside / 'sentinel').write_text('untouched')
            staging = root / 'staging'
            staging.mkdir()
            target = staging / ('job-' + 'c' * 32)
            target.symlink_to(outside, target_is_directory=True)

            result = subprocess.run(
                [str(self.binary), str(root), 'cleanup-replaced'], capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('REJECTED REPLACEMENT', result.stdout)
            self.assertTrue(target.is_symlink())
            self.assertEqual((outside / 'sentinel').read_text(), 'untouched')

    def test_project_rejections(self):
        for project in [b'not json', b'{}', b'{"type":"application","file":"x"}',
                        b'{"type":"web","file":"../outside"}', b'{"type":"video","file":"index.html"}',
                        b'{"type":"web","file":"missing.html"}', b'{"type":"web","dependency":"../bad"}']:
            with self.subTest(project=project):
                self.scenario(files={'project.json': project, 'index.html': b'hello'}, accepted=False)

    def test_video_scene_dependency_web(self):
        for files in [{'project.json': b'{"type":"video","file":"a.mp4"}', 'a.mp4': b'video-fixture'},
                      {'project.json': b'{"type":"scene","file":"scene.json"}', 'scene.pkg': b'package-fixture'},
                      {'project.json': b'{"type":"web","dependency":"987654"}'},
                      {'project.json': b'{"type":" web ","dependency":987654}'}]:
            with self.subTest(files=files):
                self.scenario(files=files)


if __name__ == '__main__':
    unittest.main()
