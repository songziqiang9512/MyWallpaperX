import Foundation

@_silgen_name("mwx_sqlite_fault_full_count")
nonisolated private func fullCount() -> Int32
@_silgen_name("mwx_sqlite_fault_rollback_count")
nonisolated private func rollbackCount() -> Int32
@_silgen_name("mwx_sqlite_fault_close_count")
nonisolated private func closeCount() -> Int32
@_silgen_name("mwx_sqlite_fault_close_v2_count")
nonisolated private func closeV2Count() -> Int32

@main enum UserCollectionsSQLiteFaultHarness {
    static func main() async throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let store = UserCollectionsStore(url: folder.appendingPathComponent("collections.sqlite3"))
        var checks: [String: Bool] = [:]
        do {
            _ = try await store.snapshot()
            checks["database_error_reported"] = false
            checks["original_full_error_retained"] = false
            checks["rollback_io_error_retained"] = false
        } catch let UserCollectionsError.database(message) {
            checks["database_error_reported"] = true
            checks["original_full_error_retained"] = message.contains("SQLITE_FULL")
            checks["rollback_io_error_retained"] = message.contains("SQLITE_IOERR")
        }
        checks["first_create_injected_once"] = fullCount() == 1
        checks["rollback_injected_once"] = rollbackCount() == 1
        checks["failed_open_closes_exactly_once"] = closeCount() + closeV2Count() == 1
        checks["failed_open_uses_close_v2"] = closeV2Count() == 1 && closeCount() == 0

        let reopened = try await store.snapshot()
        checks["same_owner_reopens_cleanly"] = reopened.revision == 0
            && reopened.playlists.isEmpty && reopened.members.isEmpty
            && reopened.migrationManifestID == nil
        let playlist = WallpaperPlaylist(name: "恢复后可写",
            createdAt: Date(timeIntervalSince1970: 1_000), sidebarRank: 0)
        let written = try await store.apply(.createPlaylist(playlist), expectedEpoch: reopened.resetEpoch)
        checks["reopened_owner_commits_real_write"] = written.revision == 1
            && written.playlists == [playlist]
        let independent = UserCollectionsStore(url: folder.appendingPathComponent("collections.sqlite3"))
        let persisted = try await independent.snapshot()
        checks["independent_owner_reads_committed_data"] = persisted == written
        checks["faults_do_not_repeat_during_reopen"] = fullCount() == 1 && rollbackCount() == 1
        // Keep the original owner alive until the cleanup counters above were
        // consumed; actor deinit is outside the failed-open cleanup operation.
        _ = try await store.snapshot()
        print(String(decoding: try JSONEncoder().encode(checks), as: UTF8.self))
    }
}
