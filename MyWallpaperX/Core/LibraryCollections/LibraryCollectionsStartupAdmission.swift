import Foundation

nonisolated enum LibraryCollectionsStartupOutcome: Sendable {
    case ready(store: UserCollectionsStore, snapshot: UserCollectionsSnapshot)
    case recoveryRequired(String)

    var recoveryMessage: String? {
        if case .recoveryRequired(let message) = self { return message }
        return nil
    }
}

@MainActor enum LibraryCollectionsStartupAdmission {
    private final class Completion { var outcome: LibraryCollectionsStartupOutcome? }

    static func databaseURL() throws -> URL {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return support.appendingPathComponent("MyWallpaperX/user-collections.sqlite3")
    }

    // NSApplication.run must stay on its original synchronous entry stack;
    // only the current actor-owned SQLite snapshot crosses this short bridge.
    static func waitForResult(timeout: TimeInterval = 30,
        operation: @escaping @Sendable () async throws -> LibraryCollectionsStartupOutcome
    ) throws -> LibraryCollectionsStartupOutcome {
        let completion = Completion()
        let task = Task { @MainActor in
            do { completion.outcome = try await operation() }
            catch { completion.outcome = .recoveryRequired(error.localizedDescription) }
            CFRunLoopStop(CFRunLoopGetMain())
        }
        CFRunLoopRunInMode(.defaultMode, timeout, false)
        guard let result = completion.outcome else {
            task.cancel()
            throw CocoaError(.userCancelled, userInfo: [NSLocalizedDescriptionKey: "资料库读取尚未完成，本次启动已停止，请重新启动。"])
        }
        return result
    }

    @concurrent static func prepare(at url: URL) async throws -> LibraryCollectionsStartupOutcome {
        let store = UserCollectionsStore(url: url)
        return .ready(store: store, snapshot: try await store.snapshot())
    }
}
