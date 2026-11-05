"""Exercise SK5.3 JobStore history ownership, retention and current-format recovery."""
import os
import pathlib
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_transaction import CORE, SOURCES

PROJECTION = CORE / "SteamWorkshopDownloadTaskProjection.swift"


class SteamDownloadHistoryTests(unittest.TestCase):
    def test_history_is_atomic_account_scoped_bounded_and_attempt_aggregated(self):
        harness = r'''
import Foundation

@main struct Harness {
    @MainActor static func stagedReceipt(
        job: SteamDownloadJob,
        stagingRoot: URL,
        stagingPath: String,
        manifestID: String,
        identity: SteamWorkshopStagingLeaseIdentity
    ) throws -> SteamWorkshopStagedReceipt {
        let requestID = "\(job.id)-\(job.attempt)"
        let digest = String(repeating: "a", count: 64)
        let data: [String: SteamServiceJSON] = [
            "receiptVersion": .int(2),
            "contentDigest": .string(digest),
            "stagedComplete": .bool(true),
            "jobId": .string(requestID),
            "workshopId": .string(job.workshopItemId),
            "accountSteamId": .string(job.accountSteamId),
            "manifestId": .string(manifestID),
            "projectJsonPresent": .bool(true),
            "stagingDevice": .string(String(identity.device)),
            "stagingInode": .string(String(identity.inode)),
            "stagingBirthSeconds": .string(String(identity.birthSeconds!)),
            "stagingBirthNanoseconds": .string(String(identity.birthNanoseconds!)),
            "totalBytes": .int(1),
            "verifiedBytes": .int(1),
            "stagingPath": .string(stagingPath),
        ]
        var frame = SteamServiceFrame(root: [
            "v": .int(1),
            "type": .string("result"),
            "requestId": .string(requestID),
            "accountEpoch": .int(1),
            "ok": .bool(true),
            "data": .object(data),
        ], frameType: "result")
        frame.requestId = requestID
        frame.accountEpoch = 1
        frame.ok = true
        return try SteamWorkshopStagedReceipt(
            frame: frame,
            jobId: requestID,
            workshopId: job.workshopItemId,
            accountSteamId: job.accountSteamId,
            accountEpoch: 1,
            stagingRoot: stagingRoot.path
        )
    }

    @MainActor static func main() throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1])
        let url = base.appendingPathComponent("jobs.json")
        var clock = Date(timeIntervalSince1970: 2_000_000_000)
        let store = SteamDownloadJobStore(persistenceURL: url, now: { clock })

        let retry = store.enqueue(workshopItemId: "100", title: "Retry", accountSteamId: "A").job
        clock.addTimeInterval(1)
        precondition(store.apply(.started, toID: retry.id)?.attempt == 1)
        clock.addTimeInterval(1)
        precondition(store.apply(.failed("network"), toID: retry.id) != nil)
        clock.addTimeInterval(1)
        precondition(store.apply(.started, toID: retry.id)?.attempt == 2)
        clock.addTimeInterval(1)
        precondition(store.apply(.failed("disk"), toID: retry.id) != nil)

        let other = store.enqueue(workshopItemId: "200", title: "Other", accountSteamId: "B").job
        clock.addTimeInterval(1)
        precondition(store.cancel(id: other.id) != nil)
        precondition(store.history.filter { $0.accountSteamId == "A" }.count == 2)
        precondition(store.history.filter { $0.accountSteamId == "B" }.count == 1)
        precondition(store.history.count == 3, "local terminal history does not require a current login identity")

        let latestEntries = SteamWorkshopDownloadHistoryProjection.latestEntries(
            from: store.history
        )
        precondition(latestEntries.count == 2 && Set(latestEntries.map(\.accountSteamId)) == ["A", "B"],
                     "local terminal history must remain readable without a current account")
        let latestRetry = latestEntries.first { $0.jobID == retry.id }!
        precondition(latestRetry.accountSteamId == "A" && latestRetry.attempt == 2)
        precondition(store.history.filter { $0.jobID == retry.id }.map(\.attempt) == [2, 1])
        precondition(latestRetry.outcome == .failed)
        precondition(latestRetry.failureMessage == "disk")

        let reloaded = SteamDownloadJobStore(persistenceURL: url, now: { clock })
        precondition(reloaded.history == store.history, "restart must not duplicate terminal attempts")
        precondition(reloaded.clearHistory(forAccount: "A") == 2)
        precondition(reloaded.history.filter { $0.accountSteamId == "A" }.isEmpty)
        precondition(reloaded.failedJob(forWorkshopItemId: "100", accountSteamId: "A") != nil,
            "clearing history must not remove retryable job intent")
        precondition(reloaded.history.filter { $0.accountSteamId == "B" }.count == 1)
        let afterClearRestart = SteamDownloadJobStore(persistenceURL: url, now: { clock })
        precondition(afterClearRestart.history.filter { $0.accountSteamId == "A" }.isEmpty,
            "current restart must not resurrect explicitly cleared failed history")
        precondition(afterClearRestart.failedJob(
            forWorkshopItemId: "100", accountSteamId: "A") != nil)

        // Failed persistence cannot publish an in-memory clear.
        let retained = reloaded.history
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        precondition(reloaded.clearHistory(forAccount: "B") == 0)
        precondition(reloaded.history == retained)
        try FileManager.default.removeItem(at: url)

        let seedURL = base.appendingPathComponent("seed-current.json")
        let seed = SteamDownloadJobStore(persistenceURL: seedURL, now: { clock })
        let seededJob = seed.enqueue(workshopItemId: "300", title: "Current", accountSteamId: "A").job
        precondition(seed.apply(.started, toID: seededJob.id) != nil)
        precondition(seed.apply(.failed("network"), toID: seededJob.id) != nil)
        let seedBytes = try Data(contentsOf: seedURL)
        let seedObject = try JSONSerialization.jsonObject(with: seedBytes) as! [String: Any]
        precondition(seedObject["version"] as? Int == 5)
        let currentPersistenceText = String(decoding: seedBytes, as: UTF8.self).lowercased()
        precondition(!currentPersistenceText.contains("password") && !currentPersistenceText.contains("token"),
            "persisted job envelope must remain credential-free")
        for version in 1...4 {
            var old = seedObject; old["version"] = version
            let bytes = try JSONSerialization.data(withJSONObject: old)
            let oldURL = base.appendingPathComponent("unsupported-\(version).json")
            try bytes.write(to: oldURL)
            let rejected = SteamDownloadJobStore(persistenceURL: oldURL, now: { clock })
            precondition(rejected.jobs.isEmpty && rejected.history.isEmpty && !rejected.lastSaveSucceeded)
            precondition(!rejected.enqueue(workshopItemId: "301", title: "Rejected", accountSteamId: "A").isNew)
            let retainedBytes = try Data(contentsOf: oldURL)
            precondition(retainedBytes == bytes, "unsupported current path stays byte-for-byte intact")
        }
        var missingHistory = seedObject; missingHistory.removeValue(forKey: "history")
        let missingHistoryURL = base.appendingPathComponent("missing-history.json")
        let missingHistoryBytes = try JSONSerialization.data(withJSONObject: missingHistory)
        try missingHistoryBytes.write(to: missingHistoryURL)
        let missingHistoryStore = SteamDownloadJobStore(persistenceURL: missingHistoryURL, now: { clock })
        precondition(!missingHistoryStore.lastSaveSucceeded && missingHistoryStore.history.isEmpty)
        precondition(!missingHistoryStore.enqueue(workshopItemId: "302", title: "Missing field", accountSteamId: "A").isNew)
        let retainedMissingHistory = try Data(contentsOf: missingHistoryURL)
        precondition(retainedMissingHistory == missingHistoryBytes)

        let home = base.appendingPathComponent("home", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        precondition(FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().standardizedFileURL.path == home.path)
        let currentURL = SteamDownloadJobStore.defaultPersistenceURL().resolvingSymlinksInPath().standardizedFileURL
        precondition(currentURL.path.hasPrefix(home.path + "/"), "default JobStore must be isolated")
        let oldRoot = currentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: oldRoot, withIntermediateDirectories: true)
        var oldObject = seedObject; oldObject["version"] = 4
        let legacyBytes = try JSONSerialization.data(withJSONObject: oldObject)
        let oldNames = ["jobs-v4.json", "jobs-v3.json", "jobs.json"]
        for name in oldNames { try legacyBytes.write(to: oldRoot.appendingPathComponent(name)) }
        let currentOnly = SteamDownloadJobStore(now: { clock })
        precondition(currentOnly.jobs.isEmpty && currentOnly.history.isEmpty && currentOnly.lastSaveSucceeded,
            "default owner must not discover old filenames")
        precondition(!FileManager.default.fileExists(atPath: currentURL.path))
        let freshJob = currentOnly.enqueue(workshopItemId: "400", title: "Fresh", accountSteamId: "A").job
        let restartedCurrent = SteamDownloadJobStore(now: { clock })
        precondition(restartedCurrent.jobs == [freshJob], "current queue survives restart without old intent")
        for name in oldNames {
            let bytes = try Data(contentsOf: oldRoot.appendingPathComponent(name))
            precondition(bytes == legacyBytes, "old files are neither read into state nor rewritten")
        }
        let corruptBytes = Data("not-json".utf8)

        let corruptCurrentRoot = base.appendingPathComponent(
            "corrupt-current", isDirectory: true)
        try FileManager.default.createDirectory(
            at: corruptCurrentRoot, withIntermediateDirectories: true)
        let corruptCurrent = corruptCurrentRoot.appendingPathComponent("jobs-v5.json")
        let validPredecessor = corruptCurrentRoot.appendingPathComponent("jobs-v4.json")
        try corruptBytes.write(to: corruptCurrent)
        try legacyBytes.write(to: validPredecessor)
        let currentRejected = SteamDownloadJobStore(
            persistenceURL: corruptCurrent,
            now: { clock }
        )
        precondition(currentRejected.jobs.isEmpty && currentRejected.history.isEmpty
            && !currentRejected.lastSaveSucceeded,
            "an unreadable current v5 must remain authoritative instead of importing v4")
        let currentDirectoryBefore = try FileManager.default.contentsOfDirectory(
            atPath: corruptCurrentRoot.path).sorted()
        let currentRejectedEnqueue = currentRejected.enqueue(
            workshopItemId: "402", title: "Must not overwrite", accountSteamId: "A")
        precondition(!currentRejectedEnqueue.isNew && currentRejected.jobs.isEmpty)
        let corruptCurrentBytesAfterMutation = try Data(contentsOf: corruptCurrent)
        precondition(corruptCurrentBytesAfterMutation == corruptBytes,
            "a rejected mutation must preserve the exact corrupt current bytes")
        let currentDirectoryAfter = try FileManager.default.contentsOfDirectory(
            atPath: corruptCurrentRoot.path).sorted()
        precondition(currentDirectoryAfter == currentDirectoryBefore,
            "fail-closed loading must not quarantine or create sidecar files")

        let futureCurrent = corruptCurrentRoot.appendingPathComponent("future-jobs-v5.json")
        let futureBytes = Data("{\"version\":6,\"jobs\":[],\"history\":[]}".utf8)
        try futureBytes.write(to: futureCurrent)
        let futureRejected = SteamDownloadJobStore(
            persistenceURL: futureCurrent,
            now: { clock }
        )
        precondition(!futureRejected.lastSaveSucceeded)
        let futureRejectedEnqueue = futureRejected.enqueue(
            workshopItemId: "403", title: "Future schema", accountSteamId: "A")
        precondition(!futureRejectedEnqueue.isNew && futureRejected.jobs.isEmpty)
        let futureBytesAfterMutation = try Data(contentsOf: futureCurrent)
        precondition(futureBytesAfterMutation == futureBytes,
            "a future schema must not be downgraded or overwritten")

        let symlinkCurrentRoot = base.appendingPathComponent(
            "symlink-current", isDirectory: true)
        try FileManager.default.createDirectory(
            at: symlinkCurrentRoot, withIntermediateDirectories: true)
        let symlinkCurrent = symlinkCurrentRoot.appendingPathComponent("jobs-v5.json")
        let danglingCurrentTarget = symlinkCurrentRoot.appendingPathComponent("missing-target.json")
        let symlinkCurrentV4 = symlinkCurrentRoot.appendingPathComponent("jobs-v4.json")
        try FileManager.default.createSymbolicLink(
            at: symlinkCurrent, withDestinationURL: danglingCurrentTarget)
        try legacyBytes.write(to: symlinkCurrentV4)
        let symlinkCurrentRejected = SteamDownloadJobStore(
            persistenceURL: symlinkCurrent,
            now: { clock }
        )
        precondition(symlinkCurrentRejected.jobs.isEmpty
            && !symlinkCurrentRejected.lastSaveSucceeded,
            "a dangling current entry must reject instead of replaying valid v4 intent")
        let symlinkCurrentEnqueue = symlinkCurrentRejected.enqueue(
            workshopItemId: "404", title: "Dangling current", accountSteamId: "A")
        precondition(!symlinkCurrentEnqueue.isNew && symlinkCurrentRejected.jobs.isEmpty)
        precondition(!FileManager.default.fileExists(atPath: danglingCurrentTarget.path))
        let preservedCurrentLink = try FileManager.default.destinationOfSymbolicLink(
            atPath: symlinkCurrent.path)
        precondition(preservedCurrentLink == danglingCurrentTarget.path,
            "the current symlink entry must remain unchanged")
        let symlinkCurrentV4Bytes = try Data(contentsOf: symlinkCurrentV4)
        precondition(symlinkCurrentV4Bytes == legacyBytes,
            "a current symlink must not consume or rewrite the v4 predecessor")

        // Current interrupted jobs retain complete recovery tuples. Malformed
        // tuples lose pathname authority without discarding the published commit.
        let matrixRoot = base.appendingPathComponent("current-state-matrix", isDirectory: true)
        try FileManager.default.createDirectory(at: matrixRoot, withIntermediateDirectories: true)
        let matrixV5 = matrixRoot.appendingPathComponent("jobs-v5.json")
        let matrixWriter = SteamDownloadJobStore(persistenceURL: matrixV5, now: { clock })
        let matrixAccount = "76561198000000000"
        var preparedByWorkshop: [String: SteamWorkshopLibraryCommit] = [:]
        var jobsByWorkshop: [String: String] = [:]
        for (offset, workshopID) in ["410", "411", "412", "413", "414", "415"].enumerated() {
            let enqueued = matrixWriter.enqueue(
                workshopItemId: workshopID,
                title: "State \(workshopID)",
                accountSteamId: matrixAccount
            ).job
            let running = matrixWriter.apply(.started, toID: enqueued.id)!
            jobsByWorkshop[workshopID] = running.id
            let path = matrixRoot.appendingPathComponent(
                "staging/job-" + String(repeating: String(format: "%x", offset + 1), count: 32)
            ).path
            let identity = SteamWorkshopStagingLeaseIdentity(
                device: 7,
                inode: UInt64(100 + offset),
                birthSeconds: 2_000_000_000 + Int64(offset),
                birthNanoseconds: Int64(offset)
            )
            precondition(matrixWriter.apply(.stagingAllocated(
                path: path,
                manifestId: "44",
                leaseIdentity: identity
            ), toID: running.id) != nil)
            if ["411", "412", "413", "414", "415"].contains(workshopID) {
                let current = matrixWriter.job(id: running.id)!
                let receipt = try stagedReceipt(
                    job: current,
                    stagingRoot: matrixRoot.appendingPathComponent("staging", isDirectory: true),
                    stagingPath: path,
                    manifestID: "44",
                    identity: identity
                )
                precondition(matrixWriter.apply(.staged(receipt), toID: running.id) != nil)
                if ["412", "415"].contains(workshopID) {
                    let commit = SteamWorkshopLibraryCommit(
                        version: 3,
                        workshopId: workshopID,
                        jobId: receipt.jobId,
                        attempt: 1,
                        directoryName: workshopID,
                        manifestId: "44",
                        contentDigest: receipt.contentDigest,
                        contentType: "scene",
                        entryPath: "project.json",
                        committedAt: clock,
                        generation: "11111111-1111-4111-8111-111111111111"
                    )
                    preparedByWorkshop[workshopID] = commit
                    precondition(matrixWriter.apply(.committing(commit), toID: running.id) != nil)
                    if workshopID == "415" {
                        precondition(matrixWriter.apply(.completed, toID: running.id) != nil)
                    }
                } else if workshopID == "413" {
                    precondition(matrixWriter.apply(.failed("network"), toID: running.id) != nil)
                } else if workshopID == "414" {
                    precondition(matrixWriter.cancel(id: running.id) != nil)
                }
            }
        }
        let completeBytes = try Data(contentsOf: matrixV5)
        let completeURL = matrixRoot.appendingPathComponent("complete-current.json")
        try completeBytes.write(to: completeURL)
        let completeRestart = SteamDownloadJobStore(persistenceURL: completeURL, now: { clock })
        let interrupted = completeRestart.job(id: jobsByWorkshop["410"]!)!
        precondition(interrupted.state == .failed && interrupted.stagingLeaseIdentity?.isComplete == true
            && interrupted.stagingPath != nil && interrupted.stagingManifestId == "44")
        precondition(completeRestart.history.filter { $0.jobID == interrupted.id }.count == 1)
        completeRestart.reconcileInterruptedCommits(published: ["412": preparedByWorkshop["412"]!])
        precondition(completeRestart.job(id: jobsByWorkshop["412"]!)?.state == .completed,
            "matching current ready pointer settles an interrupted current commit")
        let completeAgain = SteamDownloadJobStore(persistenceURL: completeURL, now: { clock })
        precondition(completeAgain.history.filter { $0.jobID == interrupted.id }.count == 1)
        var matrixObject = try JSONSerialization.jsonObject(with: completeBytes) as! [String: Any]
        var matrixJobs = matrixObject["jobs"] as! [[String: Any]]
        for index in matrixJobs.indices {
            let workshopID = matrixJobs[index]["workshopItemId"] as! String
            if workshopID == "410",
               var identity = matrixJobs[index]["stagingLeaseIdentity"] as? [String: Any] {
                identity.removeValue(forKey: "birthSeconds")
                identity.removeValue(forKey: "birthNanoseconds")
                matrixJobs[index]["stagingLeaseIdentity"] = identity
            } else {
                // A partial current snapshot must revoke the whole tuple,
                // including receipts whose matching recovery fields are missing.
                matrixJobs[index].removeValue(forKey: "stagingLeaseIdentity")
            }
            if var receipt = matrixJobs[index]["receipt"] as? [String: Any] {
                receipt.removeValue(forKey: "stagingLeaseIdentity")
                matrixJobs[index]["receipt"] = receipt
            }
        }
        matrixObject["jobs"] = matrixJobs
        let matrixBytes = try JSONSerialization.data(
            withJSONObject: matrixObject, options: [.sortedKeys])
        try matrixBytes.write(to: matrixV5, options: .atomic)

        let matrix = SteamDownloadJobStore(
            persistenceURL: matrixV5,
            now: { clock }
        )
        let runningImport = matrix.job(id: jobsByWorkshop["410"]!)!
        precondition(runningImport.state == .queued
            && runningImport.stagingPath == nil
            && runningImport.stagingManifestId == nil
            && runningImport.stagingLeaseIdentity == nil)
        let stagedImport = matrix.job(id: jobsByWorkshop["411"]!)!
        precondition(stagedImport.state == .failed
            && stagedImport.receipt == nil
            && stagedImport.failureMessage?.contains("缺少创建时间") == true)
        let failedImport = matrix.job(id: jobsByWorkshop["413"]!)!
        precondition(failedImport.state == .failed
            && failedImport.failureMessage == "network"
            && failedImport.stagingPath == nil
            && failedImport.stagingLeaseIdentity == nil
            && failedImport.receipt == nil)
        let cancelledImport = matrix.job(id: jobsByWorkshop["414"]!)!
        precondition(cancelledImport.state == .cancelled
            && cancelledImport.stagingPath == nil
            && cancelledImport.stagingLeaseIdentity == nil
            && cancelledImport.receipt == nil)
        let completedImport = matrix.job(id: jobsByWorkshop["415"]!)!
        precondition(completedImport.state == .completed
            && completedImport.stagingPath == nil
            && completedImport.stagingLeaseIdentity == nil
            && completedImport.receipt == nil
            && completedImport.preparedCommit == preparedByWorkshop["415"])
        let committingID = jobsByWorkshop["412"]!
        let committingImport = matrix.job(id: committingID)!
        precondition(committingImport.state == .committing
            && committingImport.receipt == nil
            && committingImport.preparedCommit == preparedByWorkshop["412"],
            "published commit authority must survive removal of obsolete staging authority")
        matrix.reconcileInterruptedCommits(published: ["412": preparedByWorkshop["412"]!])
        precondition(matrix.job(id: committingID)?.state == .completed,
            "matching published metadata still settles a current interrupted commit")
        let matrixRestart = SteamDownloadJobStore(
            persistenceURL: matrixV5,
            now: { clock }
        )
        precondition(matrixRestart.job(id: jobsByWorkshop["414"]!) == nil,
            "cancelled staging cleanup authority must not survive the current restart")

        // Retention is frozen at the newest 100 terminal attempts and 30 days.
        let boundedURL = base.appendingPathComponent("bounded.json")
        let bounded = SteamDownloadJobStore(persistenceURL: boundedURL, now: { clock })
        for index in 0...100 {
            let job = bounded.enqueue(
                workshopItemId: "bounded-\(index)",
                title: "Bounded \(index)",
                accountSteamId: "A"
            ).job
            clock.addTimeInterval(1)
            precondition(bounded.cancel(id: job.id) != nil)
        }
        precondition(bounded.history.count == SteamDownloadJobStore.historyLimit)
        precondition(!bounded.history.contains { $0.workshopItemId == "bounded-0" })

        let expiringURL = base.appendingPathComponent("expiring.json")
        let expiringStore = SteamDownloadJobStore(persistenceURL: expiringURL, now: { clock })
        let expiring = expiringStore.enqueue(
            workshopItemId: "old", title: "Old", accountSteamId: "A").job
        precondition(expiringStore.cancel(id: expiring.id) != nil)
        clock.addTimeInterval(SteamDownloadJobStore.historyRetentionInterval + 1)
        precondition(expiringStore.pruneExpiredHistory() == 1)
        precondition(expiringStore.history.isEmpty)

        print("Download history: current v5 recovery, old-format rejection, retention, account clear and atomic failure PASS")
    }
}
'''
        with tempfile.TemporaryDirectory(prefix="mwx-steam-history-") as directory:
            root = pathlib.Path(directory).resolve()
            home, temporary = root / "home", root / "tmp"
            home.mkdir(); temporary.mkdir()
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(temporary) + "/")
            source = root / "Harness.swift"
            source.write_text(harness)
            binary = root / "history"
            subprocess.run(
                ["xcrun", "swiftc", "-parse-as-library", *map(str, SOURCES),
                 str(PROJECTION), str(source), "-o", str(binary)],
                check=True,
                timeout=120,
            )
            subprocess.run([str(binary), str(root)], env=environment, check=True, timeout=30)

if __name__ == "__main__":
    unittest.main()
