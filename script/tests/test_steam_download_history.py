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

        // SK6.1 uses a side-by-side v3 file. Import old unfinished intent once,
        // but never mutate/quarantine the rollback snapshot or adjacent user data.
        let upgradeRoot = base.appendingPathComponent("upgrade", isDirectory: true)
        try FileManager.default.createDirectory(at: upgradeRoot, withIntermediateDirectories: true)
        let legacyJobsURL = upgradeRoot.appendingPathComponent("jobs.json")
        let legacyWriter = SteamDownloadJobStore(persistenceURL: legacyJobsURL, now: { clock })
        let unfinished = legacyWriter.enqueue(
            workshopItemId: "400", title: "Unfinished", accountSteamId: "A").job
        precondition(legacyWriter.apply(.started, toID: unfinished.id) != nil)
        var legacyObject = try JSONSerialization.jsonObject(
            with: Data(contentsOf: legacyJobsURL)) as! [String: Any]
        legacyObject["version"] = 2
        legacyObject.removeValue(forKey: "history")
        let legacyBytes = try JSONSerialization.data(
            withJSONObject: legacyObject, options: [.sortedKeys])
        try legacyBytes.write(to: legacyJobsURL, options: .atomic)

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
        let upgraded = SteamDownloadJobStore(
            persistenceURL: v3URL, legacyImportURL: legacyJobsURL, now: { clock })
        precondition(upgraded.jobs.count == 1 && upgraded.jobs[0].state == .queued)
        precondition(upgraded.activeJob(forWorkshopItemId: "400") != nil,
            "unfinished legacy intent must be imported exactly once")
        let preservedLegacyBytes = try Data(contentsOf: legacyJobsURL)
        precondition(preservedLegacyBytes == legacyBytes,
            "new owner must not rewrite the old-version rollback snapshot")
        precondition(FileManager.default.fileExists(atPath: v3URL.path))
        for (file, bytes) in sentinels {
            let preservedBytes = try Data(contentsOf: file)
            precondition(preservedBytes == bytes,
                "upgrade must not alter library, properties, credentials, cookies or HTML cache")
        }
        let upgradedAgain = SteamDownloadJobStore(
            persistenceURL: v3URL, legacyImportURL: legacyJobsURL, now: { clock })
        precondition(upgradedAgain.jobs.count == 1,
            "existing v3 sidecar must win over legacy import without duplicate jobs")

        let corruptLegacy = upgradeRoot.appendingPathComponent("corrupt-jobs.json")
        let corruptV3 = upgradeRoot.appendingPathComponent("corrupt-jobs-v3.json")
        let corruptBytes = Data("not-json".utf8)
        try corruptBytes.write(to: corruptLegacy)
        let rejected = SteamDownloadJobStore(
            persistenceURL: corruptV3, legacyImportURL: corruptLegacy, now: { clock })
        precondition(rejected.jobs.isEmpty && rejected.history.isEmpty)
        let preservedCorruptBytes = try Data(contentsOf: corruptLegacy)
        precondition(preservedCorruptBytes == corruptBytes)
        precondition(!FileManager.default.fileExists(atPath: corruptV3.path),
            "corrupt rollback data must remain inert instead of becoming new schema")

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

        print("Download history: v3 migration, attempt aggregation, retention, account clear and atomic failure PASS")
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
        self.assertIn("static let persistenceVersion = 3", source)
        self.assertIn("static let historyLimit = 100", source)
        self.assertIn("30 * 24 * 60 * 60", source)
        self.assertNotIn("password", source.lower())
        self.assertNotIn("token", source.lower())


if __name__ == "__main__":
    unittest.main()
