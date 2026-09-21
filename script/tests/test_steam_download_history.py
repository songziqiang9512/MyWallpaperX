"""Exercise SK5.3 JobStore history ownership, retention and migration."""
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
        precondition(store.history(forAccount: "A").count == 2)
        precondition(store.history(forAccount: "B").count == 1)
        precondition(store.history(forAccount: nil).isEmpty)

        let summaries = SteamWorkshopDownloadHistoryProjection.summaries(
            from: store.history,
            accountSteamID: "A"
        )
        precondition(summaries.count == 1)
        precondition(summaries[0].jobID == retry.id)
        precondition(summaries[0].attempts.map(\.attempt) == [2, 1])
        precondition(summaries[0].latestOutcome == .failed)
        precondition(summaries[0].attempts.first?.failureMessage == "disk")

        let reloaded = SteamDownloadJobStore(persistenceURL: url, now: { clock })
        precondition(reloaded.history == store.history, "restart must not duplicate terminal attempts")
        precondition(reloaded.clearHistory(forAccount: "A") == 2)
        precondition(reloaded.history(forAccount: "A").isEmpty)
        precondition(reloaded.failedJob(forWorkshopItemId: "100", accountSteamId: "A") != nil,
            "clearing history must not remove retryable job intent")
        precondition(reloaded.history(forAccount: "B").count == 1)
        let afterClearRestart = SteamDownloadJobStore(persistenceURL: url, now: { clock })
        precondition(afterClearRestart.history(forAccount: "A").isEmpty,
            "version 3 restart must not resurrect explicitly cleared failed history")
        precondition(afterClearRestart.failedJob(
            forWorkshopItemId: "100", accountSteamId: "A") != nil)

        // Failed persistence cannot publish an in-memory clear.
        let retained = reloaded.history
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        precondition(reloaded.clearHistory(forAccount: "B") == 0)
        precondition(reloaded.history == retained)
        try FileManager.default.removeItem(at: url)

        // Version 2 has no history key. A durable failed job migrates exactly once.
        let migrationURL = base.appendingPathComponent("migration.json")
        let migration = SteamDownloadJobStore(persistenceURL: migrationURL, now: { clock })
        let legacy = migration.enqueue(workshopItemId: "300", title: "Legacy", accountSteamId: "A").job
        precondition(migration.apply(.started, toID: legacy.id) != nil)
        precondition(migration.apply(.failed("legacy"), toID: legacy.id) != nil)
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: migrationURL)) as! [String: Any]
        precondition(object["version"] as? Int == 5, "current persisted envelope must be v5")
        let currentPersistenceText = String(decoding: try Data(contentsOf: migrationURL), as: UTF8.self).lowercased()
        precondition(!currentPersistenceText.contains("password") && !currentPersistenceText.contains("token"),
            "persisted job envelope must remain credential-free")
        object["version"] = 2
        object.removeValue(forKey: "history")
        try JSONSerialization.data(withJSONObject: object).write(to: migrationURL, options: .atomic)
        let migrated = SteamDownloadJobStore(persistenceURL: migrationURL, now: { clock })
        precondition(migrated.history.count == 1 && migrated.history[0].attempt == 1)
        let migratedAgain = SteamDownloadJobStore(persistenceURL: migrationURL, now: { clock })
        precondition(migratedAgain.history.count == 1)

        // The v5 owner imports the prior v4 sidecar copy-on-read. A baseline v4
        // reader must retain its exact rollback bytes after v5 writes/restarts,
        // while its device+inode-only partial loses resume/cleanup authority.
        let upgradeRoot = base.appendingPathComponent("upgrade", isDirectory: true)
        try FileManager.default.createDirectory(at: upgradeRoot, withIntermediateDirectories: true)
        let v4URL = upgradeRoot.appendingPathComponent("jobs-v4.json")
        let legacyWriter = SteamDownloadJobStore(persistenceURL: v4URL, now: { clock })
        let unfinished = legacyWriter.enqueue(
            workshopItemId: "400", title: "Unfinished", accountSteamId: "A").job
        precondition(legacyWriter.apply(.started, toID: unfinished.id) != nil)
        precondition(legacyWriter.apply(.stagingAllocated(
            path: upgradeRoot.appendingPathComponent(
                "staging/job-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            ).path,
            manifestId: "44",
            leaseIdentity: SteamWorkshopStagingLeaseIdentity(
                device: 1, inode: 2, birthSeconds: 3, birthNanoseconds: 4
            )
        ), toID: unfinished.id) != nil)
        var legacyObject = try JSONSerialization.jsonObject(
            with: Data(contentsOf: v4URL)) as! [String: Any]
        legacyObject["version"] = 4
        var legacyJobs = legacyObject["jobs"] as! [[String: Any]]
        var legacyIdentity = legacyJobs[0]["stagingLeaseIdentity"] as! [String: Any]
        legacyIdentity.removeValue(forKey: "birthSeconds")
        legacyIdentity.removeValue(forKey: "birthNanoseconds")
        legacyJobs[0]["stagingLeaseIdentity"] = legacyIdentity
        legacyObject["jobs"] = legacyJobs
        let legacyBytes = try JSONSerialization.data(
            withJSONObject: legacyObject, options: [.sortedKeys])
        try legacyBytes.write(to: v4URL, options: .atomic)

        let libraryFile = upgradeRoot.appendingPathComponent("library/project.json")
        let passwordFile = upgradeRoot.appendingPathComponent("credentials/legacy-password")
        let cookieFile = upgradeRoot.appendingPathComponent("cookies/legacy-cookie")
        let corruptCache = upgradeRoot.appendingPathComponent("cache/private-html.json")
        for file in [libraryFile, passwordFile, cookieFile, corruptCache] {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("sentinel-\(file.lastPathComponent)".utf8).write(to: file)
        }
        let sentinels = try Dictionary(uniqueKeysWithValues:
            [libraryFile, passwordFile, cookieFile, corruptCache].map { ($0, try Data(contentsOf: $0)) })
        let v3URL = upgradeRoot.appendingPathComponent("jobs-v3.json")
        let v3Writer = SteamDownloadJobStore(persistenceURL: v3URL, now: { clock })
        _ = v3Writer.enqueue(workshopItemId: "888", title: "Older", accountSteamId: "A")
        var v3Object = try JSONSerialization.jsonObject(
            with: Data(contentsOf: v3URL)) as! [String: Any]
        v3Object["version"] = 3
        let v3Bytes = try JSONSerialization.data(withJSONObject: v3Object, options: [.sortedKeys])
        try v3Bytes.write(to: v3URL, options: .atomic)
        let olderJobsURL = upgradeRoot.appendingPathComponent("jobs.json")
        let olderWriter = SteamDownloadJobStore(persistenceURL: olderJobsURL, now: { clock })
        _ = olderWriter.enqueue(workshopItemId: "999", title: "Stale", accountSteamId: "A")
        let olderBytes = try Data(contentsOf: olderJobsURL)
        let v5URL = upgradeRoot.appendingPathComponent("jobs-v5.json")
        let upgraded = SteamDownloadJobStore(
            persistenceURL: v5URL,
            legacyImportURL: v4URL,
            olderLegacyImportURL: v3URL,
            oldestLegacyImportURL: olderJobsURL,
            now: { clock }
        )
        precondition(upgraded.jobs.count == 1 && upgraded.jobs[0].state == .queued
            && upgraded.jobs[0].stagingPath == nil
            && upgraded.jobs[0].stagingManifestId == nil
            && upgraded.jobs[0].stagingLeaseIdentity == nil,
            "device+inode-only v4 partial must retain intent but discard lexical recovery state")
        precondition(upgraded.activeJob(forWorkshopItemId: "400") != nil,
            "unfinished legacy intent must be imported exactly once")
        precondition(upgraded.activeJob(forWorkshopItemId: "999") == nil,
            "an existing v4 owner must win over conflicting older intent")
        precondition(upgraded.activeJob(forWorkshopItemId: "888") == nil,
            "an existing v4 owner must win over the v3 predecessor")
        let preservedLegacyBytes = try Data(contentsOf: v4URL)
        precondition(preservedLegacyBytes == legacyBytes,
            "new owner must not rewrite the old-version rollback snapshot")
        precondition(FileManager.default.fileExists(atPath: v5URL.path))
        let baselineV4Object = try JSONSerialization.jsonObject(
            with: preservedLegacyBytes) as! [String: Any]
        precondition(baselineV4Object["version"] as? Int == 4,
            "the retained sidecar must remain readable by a version-4 owner")
        for (file, bytes) in sentinels {
            let preservedBytes = try Data(contentsOf: file)
            precondition(preservedBytes == bytes,
                "upgrade must not alter library, properties, credentials, cookies or HTML cache")
        }
        let upgradedAgain = SteamDownloadJobStore(
            persistenceURL: v5URL,
            legacyImportURL: v4URL,
            olderLegacyImportURL: v3URL,
            oldestLegacyImportURL: olderJobsURL,
            now: { clock }
        )
        precondition(upgradedAgain.jobs.count == 1,
            "existing v5 sidecar must win over v4 import without duplicate jobs")
        let v4BytesAfterRestart = try Data(contentsOf: v4URL)
        precondition(v4BytesAfterRestart == legacyBytes,
            "v5 restart must not rewrite the v4 rollback source")
        let v3BytesAfterRestart = try Data(contentsOf: v3URL)
        precondition(v3BytesAfterRestart == v3Bytes,
            "v5 must not rewrite an older v3 source")
        let olderBytesAfterRestart = try Data(contentsOf: olderJobsURL)
        precondition(olderBytesAfterRestart == olderBytes,
            "v5 must not rewrite the oldest fallback source")

        let v3FallbackV5 = upgradeRoot.appendingPathComponent("v3-fallback-jobs-v5.json")
        let absentV4 = upgradeRoot.appendingPathComponent("absent-jobs-v4.json")
        let v3Fallback = SteamDownloadJobStore(
            persistenceURL: v3FallbackV5,
            legacyImportURL: absentV4,
            olderLegacyImportURL: v3URL,
            oldestLegacyImportURL: olderJobsURL,
            now: { clock }
        )
        precondition(v3Fallback.activeJob(forWorkshopItemId: "888") != nil
            && v3Fallback.activeJob(forWorkshopItemId: "999") == nil
            && FileManager.default.fileExists(atPath: v3FallbackV5.path),
            "v3 is eligible only when the v4 predecessor is absent")

        let oldestFallbackV5 = upgradeRoot.appendingPathComponent("oldest-fallback-jobs-v5.json")
        let absentV3 = upgradeRoot.appendingPathComponent("absent-jobs-v3.json")
        let oldestFallback = SteamDownloadJobStore(
            persistenceURL: oldestFallbackV5,
            legacyImportURL: absentV4,
            olderLegacyImportURL: absentV3,
            oldestLegacyImportURL: olderJobsURL,
            now: { clock }
        )
        precondition(oldestFallback.activeJob(forWorkshopItemId: "999") != nil,
            "jobs.json is eligible only when both v4 and v3 predecessors are absent")

        let corruptLegacy = upgradeRoot.appendingPathComponent("corrupt-jobs-v4.json")
        let corruptV5 = upgradeRoot.appendingPathComponent("corrupt-predecessor-jobs-v5.json")
        let corruptBytes = Data("not-json".utf8)
        try corruptBytes.write(to: corruptLegacy)
        let rejected = SteamDownloadJobStore(
            persistenceURL: corruptV5,
            legacyImportURL: corruptLegacy,
            olderLegacyImportURL: v3URL,
            oldestLegacyImportURL: olderJobsURL,
            now: { clock }
        )
        precondition(rejected.jobs.isEmpty && rejected.history.isEmpty)
        let preservedCorruptBytes = try Data(contentsOf: corruptLegacy)
        precondition(preservedCorruptBytes == corruptBytes)
        precondition(!FileManager.default.fileExists(atPath: corruptV5.path),
            "an existing corrupt v4 must stop predecessor fallback instead of replaying v3/jobs.json")

        // Every v4 state loses device+inode-only cleanup/resume authority. Logical
        // intent and an already-prepared public commit survive according to their
        // own owners, while lexical staging evidence is cleared as one unit.
        let matrixRoot = base.appendingPathComponent("v4-state-matrix", isDirectory: true)
        try FileManager.default.createDirectory(at: matrixRoot, withIntermediateDirectories: true)
        let matrixV4 = matrixRoot.appendingPathComponent("jobs-v4.json")
        let matrixV5 = matrixRoot.appendingPathComponent("jobs-v5.json")
        let matrixWriter = SteamDownloadJobStore(persistenceURL: matrixV4, now: { clock })
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
                        version: 2,
                        workshopId: workshopID,
                        jobId: receipt.jobId,
                        attempt: 1,
                        directoryName: "\(workshopID)-11111111-1111-4111-8111-111111111111",
                        manifestId: "44",
                        contentDigest: receipt.contentDigest,
                        contentType: "scene",
                        entryPath: "project.json",
                        committedAt: clock
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
        var matrixObject = try JSONSerialization.jsonObject(
            with: Data(contentsOf: matrixV4)) as! [String: Any]
        matrixObject["version"] = 4
        var matrixJobs = matrixObject["jobs"] as! [[String: Any]]
        for index in matrixJobs.indices {
            let workshopID = matrixJobs[index]["workshopItemId"] as! String
            if workshopID == "410",
               var identity = matrixJobs[index]["stagingLeaseIdentity"] as? [String: Any] {
                identity.removeValue(forKey: "birthSeconds")
                identity.removeValue(forKey: "birthNanoseconds")
                matrixJobs[index]["stagingLeaseIdentity"] = identity
            } else {
                // The old v3 -> v4 bridge could retain a receipt while omitting
                // both recovery identities. This must revoke the whole tuple,
                // not merely partial identities that still have a JSON object.
                matrixJobs[index].removeValue(forKey: "stagingLeaseIdentity")
            }
            if var receipt = matrixJobs[index]["receipt"] as? [String: Any] {
                receipt.removeValue(forKey: "stagingLeaseIdentity")
                matrixJobs[index]["receipt"] = receipt
            }
        }
        matrixObject["jobs"] = matrixJobs
        let matrixV4Bytes = try JSONSerialization.data(
            withJSONObject: matrixObject, options: [.sortedKeys])
        try matrixV4Bytes.write(to: matrixV4, options: .atomic)

        let matrix = SteamDownloadJobStore(
            persistenceURL: matrixV5,
            legacyImportURL: matrixV4,
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
            "matching published metadata must still settle a v4 interrupted commit")
        let preservedMatrixV4Bytes = try Data(contentsOf: matrixV4)
        precondition(preservedMatrixV4Bytes == matrixV4Bytes,
            "state-matrix import must preserve exact v4 rollback bytes")
        let matrixRestart = SteamDownloadJobStore(
            persistenceURL: matrixV5,
            legacyImportURL: matrixV4,
            now: { clock }
        )
        precondition(matrixRestart.job(id: jobsByWorkshop["414"]!) == nil,
            "cancelled v4 staging cleanup authority must not survive the v5 restart")

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

        print("Download history: v5 birth-identity migration, v4 rollback preservation, retention, account clear and atomic failure PASS")
    }
}
'''
        with tempfile.TemporaryDirectory(prefix="mwx-steam-history-") as directory:
            root = pathlib.Path(directory)
            source = root / "Harness.swift"
            source.write_text(harness)
            binary = root / "history"
            subprocess.run(
                ["xcrun", "swiftc", "-parse-as-library", *map(str, SOURCES),
                 str(PROJECTION), str(source), "-o", str(binary)],
                check=True,
                timeout=120,
            )
            subprocess.run([str(binary), directory], check=True, timeout=30)

if __name__ == "__main__":
    unittest.main()
