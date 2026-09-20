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
        object["version"] = 2
        object.removeValue(forKey: "history")
        try JSONSerialization.data(withJSONObject: object).write(to: migrationURL, options: .atomic)
        let migrated = SteamDownloadJobStore(persistenceURL: migrationURL, now: { clock })
        precondition(migrated.history.count == 1 && migrated.history[0].attempt == 1)
        let migratedAgain = SteamDownloadJobStore(persistenceURL: migrationURL, now: { clock })
        precondition(migratedAgain.history.count == 1)

        // The v4 owner imports the prior v3 sidecar copy-on-read. A baseline v3
        // reader must retain its exact rollback bytes after v4 writes/restarts.
        let upgradeRoot = base.appendingPathComponent("upgrade", isDirectory: true)
        try FileManager.default.createDirectory(at: upgradeRoot, withIntermediateDirectories: true)
        let v3URL = upgradeRoot.appendingPathComponent("jobs-v3.json")
        let legacyWriter = SteamDownloadJobStore(persistenceURL: v3URL, now: { clock })
        let unfinished = legacyWriter.enqueue(
            workshopItemId: "400", title: "Unfinished", accountSteamId: "A").job
        precondition(legacyWriter.apply(.started, toID: unfinished.id) != nil)
        precondition(legacyWriter.apply(.stagingAllocated(
            path: upgradeRoot.appendingPathComponent(
                "staging/job-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            ).path,
            manifestId: "44",
            leaseIdentity: SteamWorkshopStagingLeaseIdentity(device: 1, inode: 2)
        ), toID: unfinished.id) != nil)
        var legacyObject = try JSONSerialization.jsonObject(
            with: Data(contentsOf: v3URL)) as! [String: Any]
        legacyObject["version"] = 3
        var legacyJobs = legacyObject["jobs"] as! [[String: Any]]
        legacyJobs[0].removeValue(forKey: "stagingLeaseIdentity")
        legacyObject["jobs"] = legacyJobs
        let legacyBytes = try JSONSerialization.data(
            withJSONObject: legacyObject, options: [.sortedKeys])
        try legacyBytes.write(to: v3URL, options: .atomic)

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
        let olderJobsURL = upgradeRoot.appendingPathComponent("jobs.json")
        let olderWriter = SteamDownloadJobStore(persistenceURL: olderJobsURL, now: { clock })
        _ = olderWriter.enqueue(workshopItemId: "999", title: "Stale", accountSteamId: "A")
        let olderBytes = try Data(contentsOf: olderJobsURL)
        let v4URL = upgradeRoot.appendingPathComponent("jobs-v4.json")
        let upgraded = SteamDownloadJobStore(
            persistenceURL: v4URL,
            legacyImportURL: v3URL,
            olderLegacyImportURL: olderJobsURL,
            now: { clock }
        )
        precondition(upgraded.jobs.count == 1 && upgraded.jobs[0].state == .queued
            && upgraded.jobs[0].stagingPath == nil
            && upgraded.jobs[0].stagingManifestId == nil
            && upgraded.jobs[0].stagingLeaseIdentity == nil,
            "identityless v3 partial must retain intent but discard lexical recovery state")
        precondition(upgraded.activeJob(forWorkshopItemId: "400") != nil,
            "unfinished legacy intent must be imported exactly once")
        precondition(upgraded.activeJob(forWorkshopItemId: "999") == nil,
            "an existing v3 owner must win over conflicting older intent")
        let preservedLegacyBytes = try Data(contentsOf: v3URL)
        precondition(preservedLegacyBytes == legacyBytes,
            "new owner must not rewrite the old-version rollback snapshot")
        precondition(FileManager.default.fileExists(atPath: v4URL.path))
        let baselineV3Object = try JSONSerialization.jsonObject(
            with: preservedLegacyBytes) as! [String: Any]
        precondition(baselineV3Object["version"] as? Int == 3,
            "the retained sidecar must remain readable by a version-3 owner")
        for (file, bytes) in sentinels {
            let preservedBytes = try Data(contentsOf: file)
            precondition(preservedBytes == bytes,
                "upgrade must not alter library, properties, credentials, cookies or HTML cache")
        }
        let upgradedAgain = SteamDownloadJobStore(
            persistenceURL: v4URL,
            legacyImportURL: v3URL,
            olderLegacyImportURL: olderJobsURL,
            now: { clock }
        )
        precondition(upgradedAgain.jobs.count == 1,
            "existing v4 sidecar must win over v3 import without duplicate jobs")
        let v3BytesAfterRestart = try Data(contentsOf: v3URL)
        precondition(v3BytesAfterRestart == legacyBytes,
            "v4 restart must not rewrite the v3 rollback source")
        let olderBytesAfterRestart = try Data(contentsOf: olderJobsURL)
        precondition(olderBytesAfterRestart == olderBytes,
            "v4 must not rewrite the older fallback source")

        let absentV4 = upgradeRoot.appendingPathComponent("absent-v3-jobs-v4.json")
        let absentV3 = upgradeRoot.appendingPathComponent("absent-v3-jobs-v3.json")
        let fallback = SteamDownloadJobStore(
            persistenceURL: absentV4,
            legacyImportURL: absentV3,
            olderLegacyImportURL: olderJobsURL,
            now: { clock }
        )
        precondition(fallback.activeJob(forWorkshopItemId: "999") != nil
            && FileManager.default.fileExists(atPath: absentV4.path),
            "jobs.json is eligible only when the v3 predecessor is absent")

        let corruptLegacy = upgradeRoot.appendingPathComponent("corrupt-jobs-v3.json")
        let corruptV4 = upgradeRoot.appendingPathComponent("corrupt-jobs-v4.json")
        let corruptBytes = Data("not-json".utf8)
        try corruptBytes.write(to: corruptLegacy)
        let rejected = SteamDownloadJobStore(
            persistenceURL: corruptV4,
            legacyImportURL: corruptLegacy,
            olderLegacyImportURL: olderJobsURL,
            now: { clock }
        )
        precondition(rejected.jobs.isEmpty && rejected.history.isEmpty)
        let preservedCorruptBytes = try Data(contentsOf: corruptLegacy)
        precondition(preservedCorruptBytes == corruptBytes)
        precondition(!FileManager.default.fileExists(atPath: corruptV4.path),
            "an existing corrupt v3 must fail closed instead of replaying stale jobs.json")

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

        print("Download history: v4 sidecar migration, rollback preservation, retention, account clear and atomic failure PASS")
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

    def test_persistence_schema_is_credential_free(self):
        source = (CORE / "SteamWorkshopJobStore.swift").read_text()
        self.assertIn("static let persistenceVersion = 4", source)
        self.assertIn("static let historyLimit = 100", source)
        self.assertIn("30 * 24 * 60 * 60", source)
        self.assertNotIn("password", source.lower())
        self.assertNotIn("token", source.lower())


if __name__ == "__main__":
    unittest.main()
