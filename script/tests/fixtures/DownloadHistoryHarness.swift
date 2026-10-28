import Combine
import Foundation

@main @MainActor struct DownloadHistoryHarness {
    static func receipt(_ provider: WallpaperProvider, _ sourceID: String, _ attempt: String,
                        _ outcome: DownloadTerminalOutcome, _ date: TimeInterval? = nil) -> DownloadTerminalReceipt {
        .init(id: .init(reference: .init(provider: provider, sourceID: sourceID), attemptID: attempt),
              title: provider.rawValue + sourceID, outcome: outcome,
              recordedAt: date.map(Date.init(timeIntervalSince1970:)), failureMessage: outcome == .failed ? "real failure" : nil)
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let url = root.appendingPathComponent("history.json")
        let history = try DownloadHistoryStore(persistenceURL: url)
        let success = receipt(.pixabay, "7", "actual-first", .completed, 300)
        let failed = receipt(.pixiv, "7:p2", "failed-first", .failed, 200)
        try history.record(success)
        try history.record(failed)
        try history.record(failed)
        precondition(history.entries.count == 2, "same terminal receipt cannot duplicate an attempt")
        var seedCalls = 0
        try history.importExistingSuccesses {
            seedCalls += 1
            return [receipt(.pixabay, "7", "existing-local", .existingLocal, 10),
                    receipt(.pixiv, "7:p2", "existing-local", .existingLocal, 20),
                    receipt(.wallhaven, "7", "existing-local", .existingLocal)]
        }
        precondition(history.entries.count == 4 && history.entries.contains(success) && history.entries.contains(failed),
                     "late initial scans must retain early terminals without adding a second success for their publication")
        precondition(history.entries.filter { $0.id.reference == success.id.reference }.count == 1)
        try history.importExistingSuccesses { seedCalls += 1; return [] }
        precondition(seedCalls == 1)
        let reloaded = try DownloadHistoryStore(persistenceURL: url)
        precondition(reloaded.entries == history.entries)
        try reloaded.clear()
        let cleared = try DownloadHistoryStore(persistenceURL: url)
        try cleared.importExistingSuccesses { preconditionFailure("clear must prevent seed resurrection") }
        precondition(cleared.entries.isEmpty)

        let earlyClear = try DownloadHistoryStore(persistenceURL: root.appendingPathComponent("early-clear.json"))
        try earlyClear.clear()
        try earlyClear.record(failed)
        try earlyClear.importExistingSuccesses { preconditionFailure("early clear must survive later real terminals") }
        precondition(earlyClear.entries == [failed])
        let emptyURL = root.appendingPathComponent("empty.json")
        try Data().write(to: emptyURL)
        let empty = try DownloadHistoryStore(persistenceURL: emptyURL)
        try empty.importExistingSuccesses { preconditionFailure("an existing empty file is already initialized") }

        let many = try DownloadHistoryStore(persistenceURL: root.appendingPathComponent("many.json"))
        try many.importExistingSuccesses { (0..<150).map { receipt(.pixabay, String($0), "existing-local", .existingLocal, Double($0)) } }
        precondition(many.entries.count == 150, "legacy source publications must not be silently truncated")
        let durable = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        do { try cleared.record(success); preconditionFailure("directory cannot become history") }
        catch { precondition(cleared.entries.isEmpty, "failed atomic persistence must not publish a phantom terminal") }
        try FileManager.default.removeItem(at: url)
        try durable.write(to: url)
        let corruptURL = root.appendingPathComponent("corrupt.json"), corrupt = Data("not-json".utf8)
        try corrupt.write(to: corruptURL)
        do { _ = try DownloadHistoryStore(persistenceURL: corruptURL); preconditionFailure("corrupt history was replaced") }
        catch { let retained = try Data(contentsOf: corruptURL); precondition(retained == corrupt) }

        let pixabayID = success.id, wallhavenID = receipt(.wallhaven, "7", "actual-first", .completed).id
        let pixivID = failed.id
        let active = DownloadTaskRow(id: pixabayID, title: "active", phase: .transferring, actions: [.cancel])
        let old = DownloadTaskRow(id: pixabayID, title: "old", phase: .completed, recordedAt: Date(timeIntervalSince1970: 10))
        let wallhaven = DownloadTaskRow(id: wallhavenID, title: "Wallhaven", phase: .completed, recordedAt: Date(timeIntervalSince1970: 20))
        let pixiv = DownloadTaskRow(id: pixivID, title: "Pixiv page 2", phase: .failed)
        let steamID = receipt(.steamWorkshop, "7", "actual-first", .completed).id
        let steam = DownloadTaskRow(id: steamID, title: "Steam", phase: .queued)
        let projection = DownloadTaskProjection.snapshot(current: [active, steam], history: [old, pixiv, wallhaven])
        precondition(projection.active.map(\.id) == [pixabayID, steamID] && projection.history.map(\.id) == [wallhavenID, pixivID])
        precondition(projection.count == 4 && projection.active[0].title == "active",
                     "namespaced source identities, current precedence and unknown-date ordering must survive aggregation")
        print("download-history-pass")
    }
}
